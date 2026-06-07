#!/usr/bin/env python3
"""
Choplifter Clone SFX synthesizer.

Reads parameter specs from src/tools/config/sfx_spec.py and synthesizes
all 20 sound effects as OGG Vorbis files in assets/audio/sfx/.

Usage:
    python3 src/tools/generate_sfx.py                    # all SFX
    python3 src/tools/generate_sfx.py --sfx explosion    # single SFX
    python3 src/tools/generate_sfx.py --sfx explosion --preview  # WAV preview

Requires: numpy, scipy, ffmpeg (system binary)
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

# ── import spec from sibling config/ package (namespace package, no __init__ needed) ──
sys.path.insert(0, str(Path(__file__).parent))
from config.sfx_spec import SFX_SPECS, SAMPLE_RATE as SR  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR      = PROJECT_ROOT / "assets" / "audio" / "sfx"
PREVIEW_DIR  = OUT_DIR / "_preview"


# ─────────────────────────────────────────────────────────────────────────────
# ADSR envelope
# ─────────────────────────────────────────────────────────────────────────────

def adsr(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """Return an ADSR amplitude envelope of length *n* samples."""
    env     = np.empty(n, dtype=np.float32)
    a_n     = min(int(attack  * SR), n)
    d_n     = min(int(decay   * SR), n - a_n)
    r_n     = min(int(release * SR), n)
    s_start = a_n + d_n
    r_start = max(s_start, n - r_n)

    if a_n:
        env[:a_n]        = np.linspace(0.0, 1.0,     a_n,     dtype=np.float32)
    if d_n:
        env[a_n:s_start] = np.linspace(1.0, sustain, d_n,     dtype=np.float32)
    if s_start < r_start:
        env[s_start:r_start] = sustain
    if r_start < n:
        env[r_start:]    = np.linspace(sustain, 0.0, n - r_start, dtype=np.float32)

    return env


# ─────────────────────────────────────────────────────────────────────────────
# Oscillators
# ─────────────────────────────────────────────────────────────────────────────

def _phase(freq_start: float, freq_end: float, sweep: str, n: int) -> np.ndarray:
    """Compute instantaneous phase array for a frequency sweep."""
    if abs(freq_end - freq_start) < 1e-3:
        freqs = np.full(n, freq_start, dtype=np.float64)
    elif sweep == "exp" and freq_start > 0 and freq_end > 0:
        t     = np.linspace(0.0, 1.0, n, dtype=np.float64)
        freqs = freq_start * (freq_end / freq_start) ** t
    else:
        freqs = np.linspace(freq_start, freq_end, n, dtype=np.float64)
    return (2.0 * np.pi * np.cumsum(freqs) / SR).astype(np.float32)


def oscillator(waveform: str, freq_start: float, freq_end: float,
               sweep: str, n: int, rng: np.random.Generator) -> np.ndarray:
    """Generate *n* raw oscillator samples (no envelope applied)."""
    if waveform == "noise":
        return rng.standard_normal(n).astype(np.float32)

    ph = _phase(freq_start, freq_end, sweep, n)

    if waveform == "square":
        return np.sign(np.sin(ph)).astype(np.float32)
    if waveform == "sawtooth":
        return (2.0 * (ph / (2.0 * np.pi) % 1.0) - 1.0).astype(np.float32)
    # default: sine
    return np.sin(ph).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# Filters
# ─────────────────────────────────────────────────────────────────────────────

def _sos_lp(hz: float) -> np.ndarray:
    return butter(4, np.clip(hz, 20.0, SR / 2 - 1), btype="low",  fs=SR, output="sos")

def _sos_hp(hz: float) -> np.ndarray:
    return butter(4, np.clip(hz, 20.0, SR / 2 - 1), btype="high", fs=SR, output="sos")

def _sos_bp(lo: float, hi: float) -> np.ndarray:
    lo = np.clip(lo, 20.0, SR / 2 - 200)
    hi = np.clip(hi, lo + 10, SR / 2 - 1)
    return butter(3, [lo, hi], btype="band", fs=SR, output="sos")

def apply_filters(buf: np.ndarray, spec: dict) -> np.ndarray:
    if "lowpass_hz"  in spec:
        buf = sosfilt(_sos_lp(spec["lowpass_hz"]),         buf)
    if "highpass_hz" in spec:
        buf = sosfilt(_sos_hp(spec["highpass_hz"]),        buf)
    if "bandpass_hz" in spec:
        buf = sosfilt(_sos_bp(*spec["bandpass_hz"]),       buf)
    return buf.astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# Crackle gate — gives alien-saucer electrical stuttering
# ─────────────────────────────────────────────────────────────────────────────

def apply_crackle(buf: np.ndarray, rate_ms: float, duty: float,
                  rng: np.random.Generator) -> np.ndarray:
    chunk    = max(1, int(SR * rate_ms / 1000.0))
    n_chunks = (len(buf) + chunk - 1) // chunk
    gate     = (rng.random(n_chunks) < duty).astype(np.float32)
    gate_arr = np.repeat(gate, chunk)[: len(buf)]
    return buf * gate_arr


# ─────────────────────────────────────────────────────────────────────────────
# Core synthesis
# ─────────────────────────────────────────────────────────────────────────────

def _note(spec: dict, freq: float, dur: float, rng: np.random.Generator) -> np.ndarray:
    """Synthesize a single note using the spec's waveform and envelope."""
    n       = max(1, int(dur * SR))
    env_d   = spec.get("envelope", {"attack": 0.005, "decay": 0.0, "sustain": 1.0, "release": 0.02})
    wav     = oscillator(spec["waveform"], freq, freq, "none", n, rng)
    env_arr = adsr(n, env_d.get("attack", 0.005), env_d.get("decay", 0.0),
                      env_d.get("sustain", 1.0),  env_d.get("release", 0.02))
    return wav * env_arr


def synthesize(name: str, spec: dict) -> np.ndarray:
    """
    Synthesize one SFX from *spec*.  Returns float32 array normalised to
    ``[-amplitude, +amplitude]`` (amplitude taken from spec, default 0.7).
    """
    rng       = np.random.default_rng(hash(name) & 0xFFFF_FFFF)
    n         = max(1, int(spec["duration"] * SR))
    amplitude = float(spec.get("amplitude", 0.7))
    env_d     = spec.get("envelope", {"attack": 0.01, "decay": 0.0, "sustain": 1.0, "release": 0.05})

    # ── multi-note path ───────────────────────────────────────────────────────
    if "notes" in spec:
        buf = np.zeros(n, dtype=np.float32)
        for note in spec["notes"]:
            i0  = int(note["start"]    * SR)
            nv  = max(1, int(note["duration"] * SR))
            i1  = min(i0 + nv, n)
            if i1 <= i0:
                continue
            wav = _note(spec, note["freq"], note["duration"], rng)
            buf[i0:i1] += wav[: i1 - i0]

    # ── single-tone / noise path ──────────────────────────────────────────────
    else:
        freq_s = float(spec.get("freq_start", 440.0))
        freq_e = float(spec.get("freq_end",   freq_s))
        sweep  = spec.get("freq_sweep", "linear")

        buf = oscillator(spec["waveform"], freq_s, freq_e, sweep, n, rng)

        noise_mix = float(spec.get("noise_mix", 0.0))
        if noise_mix > 0.0:
            noise = rng.standard_normal(n).astype(np.float32)
            buf   = buf * (1.0 - noise_mix) + noise * noise_mix

        env_arr = adsr(n, env_d.get("attack",  0.01), env_d.get("decay",   0.0),
                          env_d.get("sustain", 1.0),  env_d.get("release", 0.05))
        buf = buf * env_arr

    # ── crackle gate ──────────────────────────────────────────────────────────
    if "crackle_rate_ms" in spec:
        buf = apply_crackle(buf, spec["crackle_rate_ms"],
                            float(spec.get("crackle_duty", 0.5)), rng)

    # ── filters ───────────────────────────────────────────────────────────────
    buf = apply_filters(buf, spec)

    # ── normalise to target amplitude ─────────────────────────────────────────
    # Seamless-loop waveforms (engine_loop) are periodic by design:
    #   80 Hz × 0.5 s = 40 complete cycles → phase-coherent at loop boundaries.
    peak = float(np.max(np.abs(buf)))
    if peak > 1e-9:
        buf = buf / peak * amplitude
    return np.clip(buf, -1.0, 1.0).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# I/O
# ─────────────────────────────────────────────────────────────────────────────

def write_wav(samples: np.ndarray, path: Path) -> None:
    """Write float32 samples as 16-bit mono PCM WAV (no external libraries)."""
    pcm      = (samples * 32767.0).clip(-32768, 32767).astype(np.int16)
    n        = len(pcm)
    data_sz  = n * 2
    with path.open("wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + data_sz))
        f.write(b"WAVE")
        f.write(b"fmt ")
        # chunk_size=16, PCM=1, channels=1, sample_rate, byte_rate, block_align, bits=16
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data")
        f.write(struct.pack("<I", data_sz))
        f.write(pcm.tobytes())


def wav_to_ogg(wav_path: Path, ogg_path: Path) -> None:
    """Convert WAV → OGG Vorbis via ffmpeg (quality 4 ≈ 128 kbps VBR)."""
    ogg_path.parent.mkdir(parents=True, exist_ok=True)
    res = subprocess.run(
        ["ffmpeg", "-y", "-i", str(wav_path),
         "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
        capture_output=True, text=True,
    )
    if res.returncode != 0:
        raise RuntimeError(f"ffmpeg error:\n{res.stderr[-400:]}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Choplifter Clone SFX synthesizer — generates assets/audio/sfx/*.ogg"
    )
    parser.add_argument(
        "--sfx",
        metavar="NAME",
        help="Generate a single SFX by name (omit to generate all 20)",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Write WAV to assets/audio/sfx/_preview/ instead of converting to OGG",
    )
    args = parser.parse_args()

    if args.sfx:
        if args.sfx not in SFX_SPECS:
            sys.exit(
                f"Unknown SFX name: {args.sfx!r}\n"
                f"Available: {', '.join(sorted(SFX_SPECS))}"
            )
        targets = {args.sfx: SFX_SPECS[args.sfx]}
    else:
        targets = SFX_SPECS

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if args.preview:
        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    ok = errors = 0
    for name, spec in targets.items():
        try:
            samples = synthesize(name, spec)
            dur_s   = len(samples) / SR

            if args.preview:
                out = PREVIEW_DIR / f"{name}.wav"
                write_wav(samples, out)
                print(f"  PREVIEW  {name:<28s}  {dur_s:.3f}s  →  {out.name}")
            else:
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    tmp_path = Path(tmp.name)
                write_wav(samples, tmp_path)
                out = OUT_DIR / f"{name}.ogg"
                wav_to_ogg(tmp_path, out)
                tmp_path.unlink(missing_ok=True)
                kb = out.stat().st_size / 1024
                print(f"  OK   {name:<28s}  {dur_s:.3f}s  →  {out.name}  ({kb:.1f} KB)")

            ok += 1

        except Exception as exc:
            print(f"  ERROR  {name}: {exc}")
            errors += 1

    print(f"\nDone. {ok} OK, {errors} errors.")
    if not args.preview and ok:
        print(f"Output: {OUT_DIR.resolve()}")


if __name__ == "__main__":
    main()
