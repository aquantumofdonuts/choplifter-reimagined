#!/usr/bin/env python3
"""
generate_music.py - Generate all Choplifter Clone music via MIDI → FluidSynth → OGG.

Each biome has 3 dynamic layers (calm, tension, action) that share the same BPM,
key, and 8-bar loop length so they crossfade cleanly in Godot's AudioManager.
One-shot stings (victory, loss, sortie) are also generated.

Usage:
    python3 src/tools/generate_music.py                              # all
    python3 src/tools/generate_music.py --biome desert               # one biome
    python3 src/tools/generate_music.py --biome desert --layer calm  # one track
    python3 src/tools/generate_music.py --sting victory              # one sting
    python3 src/tools/generate_music.py --preview                    # keep WAVs
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from midiutil import MIDIFile
except ImportError:
    sys.exit("Install midiutil: pip install midiutil")

# ── Paths ─────────────────────────────────────────────────────────────────────

REPO_ROOT    = Path(__file__).resolve().parents[2]
SOUNDFONT    = REPO_ROOT / "assets/audio/soundfonts/chiptune.sf2"
OUT_DIR      = REPO_ROOT / "assets/audio/music"
PREVIEW_DIR  = OUT_DIR / "_preview"

# ── GM patch numbers (0-indexed, General MIDI) ────────────────────────────────
# These work with FluidR3_GM and most GM soundfonts.
PATCH_SQUARE_LEAD  = 80   # Square Wave lead (GM: Lead 1 Square)
PATCH_SAWTOOTH     = 81   # Sawtooth lead (GM: Lead 2 Sawtooth)
PATCH_SYNTH_BASS   = 38   # Synth Bass 1
PATCH_STRINGS      = 48   # String Ensemble 1 (for calm pads)
PATCH_BRASS        = 61   # Brass Section (for action countermelody)
PATCH_STANDARD_KIT = 0    # Drum kit (always channel 9)

# ── Scales and chord shapes ───────────────────────────────────────────────────

def scale(root_midi, intervals):
    """Return MIDI note list for a scale starting at root_midi."""
    return [root_midi + i for i in intervals]

NATURAL_MINOR = [0, 2, 3, 5, 7, 8, 10]
MAJOR         = [0, 2, 4, 5, 7, 9, 11]
PHRYGIAN      = [0, 1, 3, 5, 7, 8, 10]   # desert-ish
DORIAN        = [0, 2, 3, 5, 7, 9, 10]   # jungle-ish
WHOLE_TONE    = [0, 2, 4, 6, 8, 10]      # alien (atonal feel)

# Root notes (MIDI, octave 4)
ROOT = {
    "desert":   57,   # A3  (A minor)
    "jungle":   52,   # E3  (E minor)
    "arctic":   50,   # D3  (D minor)
    "tropical": 48,   # C3  (C major)
    "alien":    53,   # F3  (whole-tone)
}

BPM = {
    "desert":   120,
    "jungle":   135,
    "arctic":   100,
    "tropical": 140,
    "alien":    150,
}

SCALE_TYPE = {
    "desert":   PHRYGIAN,
    "jungle":   DORIAN,
    "arctic":   NATURAL_MINOR,
    "tropical": MAJOR,
    "alien":    WHOLE_TONE,
}

BIOMES = list(ROOT.keys())
LAYERS = ["calm", "tension", "action"]
STINGS = ["victory", "loss", "sortie"]

# ── MIDI building blocks ──────────────────────────────────────────────────────

def add_note(midi, track, channel, pitch, time, duration, volume=80):
    midi.addNote(track, channel, pitch, time, duration, volume)


def melody_desert(midi, track, ch, sc, bars=8):
    """Sparse, echo-y Phrygian melody. 4/4, half-note movement."""
    pattern = [0, None, 2, None, 1, None, 0, None,
               4, None, 3, None, 2, None, 0, None]
    t = 0
    for beat, deg in enumerate(pattern):
        if deg is not None and deg < len(sc):
            add_note(midi, track, ch, sc[deg], t, 0.9, 70)
        t += 0.5


def melody_jungle(midi, track, ch, sc, bars=8):
    """Driving 16th-note Dorian riff."""
    pattern = [0, 2, 3, 2, 0, 2, 3, 5, 4, 3, 2, 0, 3, 2, 0, None]
    for bar in range(bars // 2):
        t_base = bar * 4.0
        for i, deg in enumerate(pattern):
            if deg is not None and deg < len(sc):
                add_note(midi, track, ch, sc[deg], t_base + i * 0.25, 0.2, 85)


def melody_arctic(midi, track, ch, sc, bars=8):
    """Slow, wide-interval minor melody."""
    pattern = [(0, 2.0), (4, 1.0), (6, 1.0), (3, 2.0), (2, 2.0),
               (0, 2.0), (5, 1.0), (4, 1.0), (3, 2.0), (2, 4.0)]
    t = 0
    for deg, dur in pattern:
        if deg < len(sc):
            add_note(midi, track, ch, sc[deg] + 12, t, dur - 0.1, 65)
        t += dur


def melody_tropical(midi, track, ch, sc, bars=8):
    """Upbeat Caribbean 8th-note major melody."""
    pattern = [0, 2, 4, 5, 4, 2, 0, 2, 4, 7, 5, 4, 2, 4, 2, 0]
    for bar in range(bars // 2):
        t_base = bar * 4.0
        for i, deg in enumerate(pattern):
            if deg < len(sc):
                add_note(midi, track, ch, sc[deg] + 12, t_base + i * 0.5, 0.4, 90)


def melody_alien(midi, track, ch, sc, bars=8):
    """Dissonant whole-tone melody, irregular rhythm."""
    pattern = [(0, 0.5), (3, 0.25), (1, 0.75), (4, 0.5), (2, 1.0),
               (5, 0.5), (0, 0.25), (3, 0.25), (2, 0.5), (1, 1.0),
               (4, 0.5), (5, 0.75), (2, 0.25), (0, 1.5)]
    t = 0
    for bar in range(bars // 4):
        for deg, dur in pattern:
            if deg < len(sc):
                add_note(midi, track, ch, sc[deg] + 12, t + bar * 8, dur - 0.05, 75)
            t += dur


MELODIES = {
    "desert":   melody_desert,
    "jungle":   melody_jungle,
    "arctic":   melody_arctic,
    "tropical": melody_tropical,
    "alien":    melody_alien,
}


def add_bass(midi, track, ch, sc, biome, bars=8):
    """Root-fifth bass line, varied by biome."""
    bpm_factor = BPM[biome] / 120.0
    if biome in ("jungle", "tropical"):
        # Fast walking bass
        for bar in range(bars):
            t = bar * 4.0
            for beat, deg in [(0, 0), (1, 0), (2, 4), (3, 4)]:
                if deg < len(sc):
                    add_note(midi, track, ch, sc[deg] - 12, t + beat, 0.9, 75)
    elif biome == "alien":
        # Irregular, chromatic
        offsets = [0, 1, -1, 2, 0, 3, -1, 1]
        for bar in range(bars):
            t = bar * 4.0
            add_note(midi, track, ch, sc[0] - 12 + offsets[bar % len(offsets)],
                     t, 1.8, 70)
            add_note(midi, track, ch, sc[min(2, len(sc)-1)] - 12, t + 2.0, 1.8, 70)
    else:
        # Simple half-note root-fifth
        for bar in range(bars):
            t = bar * 4.0
            if len(sc) > 0:
                add_note(midi, track, ch, sc[0] - 12, t, 1.9, 80)
            if len(sc) > 4:
                add_note(midi, track, ch, sc[4] - 12, t + 2.0, 1.9, 80)


def add_drums(midi, track, ch, biome, bars=8):
    """Drum pattern on MIDI channel 9. GM drums: 36=kick, 38=snare, 42=hihat."""
    KICK, SNARE, HAT = 36, 38, 42
    if biome == "jungle":
        # Dense tribal pattern
        for bar in range(bars):
            t = bar * 4.0
            for b in [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]:
                add_note(midi, track, ch, HAT, t + b, 0.2, 60)
            for b in [0, 1, 2, 3]:
                add_note(midi, track, ch, KICK, t + b, 0.3, 90)
            for b in [1, 3]:
                add_note(midi, track, ch, SNARE, t + b, 0.3, 85)
    elif biome == "tropical":
        # Caribbean ska-ish upbeat
        for bar in range(bars):
            t = bar * 4.0
            for b in [0, 1, 2, 3]:
                add_note(midi, track, ch, KICK, t + b, 0.3, 85)
            for b in [0.5, 1.5, 2.5, 3.5]:
                add_note(midi, track, ch, HAT, t + b, 0.2, 70)
            for b in [1, 3]:
                add_note(midi, track, ch, SNARE, t + b, 0.3, 80)
    elif biome == "alien":
        # Irregular, sparse
        pattern = [0, 1.5, 2.25, 3, 3.75]
        for bar in range(bars):
            t = bar * 4.0
            for b in pattern:
                add_note(midi, track, ch, KICK if b == 0 else SNARE, t + b, 0.3, 80)
    elif biome == "arctic":
        # Sparse, slow
        for bar in range(bars):
            t = bar * 4.0
            add_note(midi, track, ch, KICK, t, 0.4, 80)
            add_note(midi, track, ch, SNARE, t + 2, 0.4, 75)
    else:  # desert
        # Moderate, slight swing
        for bar in range(bars):
            t = bar * 4.0
            add_note(midi, track, ch, KICK, t, 0.3, 85)
            add_note(midi, track, ch, KICK, t + 1.5, 0.3, 70)
            add_note(midi, track, ch, SNARE, t + 2, 0.3, 80)
            add_note(midi, track, ch, HAT, t + 3.5, 0.2, 60)


def add_countermelody(midi, track, ch, sc, biome, bars=8):
    """Action layer: lead countermelody on top of tension."""
    if biome == "desert":
        # High register call-response
        phrases = [(5, 0.5), (4, 0.5), (3, 1.0), (5, 0.5), (6, 1.5)]
        t = 0
        for _ in range(bars // 2):
            for deg, dur in phrases:
                if deg < len(sc):
                    add_note(midi, track, ch, sc[deg] + 24, t, dur - 0.05, 90)
                t += dur
    elif biome == "jungle":
        # Aggressive 8th-note run
        pattern = [5, 4, 3, 2, 4, 3, 2, 1]
        for bar in range(bars):
            t = bar * 4.0
            for i, deg in enumerate(pattern):
                if deg < len(sc):
                    add_note(midi, track, ch, sc[deg] + 24, t + i * 0.5, 0.4, 95)
    elif biome == "arctic":
        # Slow high sustained notes
        for bar in range(bars // 2):
            t = bar * 8.0
            if len(sc) > 6:
                add_note(midi, track, ch, sc[6] + 24, t, 3.8, 75)
                add_note(midi, track, ch, sc[4] + 24, t + 4, 3.8, 75)
    elif biome == "tropical":
        # Bright staccato horn hits
        pattern = [4, 4, 5, 4, 2, 2, 4, 2]
        for bar in range(bars // 2):
            t = bar * 4.0
            for i, deg in enumerate(pattern):
                if deg < len(sc):
                    add_note(midi, track, ch, sc[deg] + 24, t + i * 0.5, 0.3, 100)
    else:  # alien
        # Chromatic descending run
        for bar in range(bars // 2):
            t = bar * 8.0
            for i in range(8):
                pitch = sc[0] + 24 + (7 - i)
                add_note(midi, track, ch, pitch, t + i * 0.5, 0.4, 85)


# ── Layer builders ────────────────────────────────────────────────────────────

def build_layer(biome, layer) -> MIDIFile:
    """Construct a MIDIFile for one biome+layer combination."""
    bpm  = BPM[biome]
    root = ROOT[biome]
    sc   = scale(root, SCALE_TYPE[biome])
    bars = 8

    # Track layout: 0=melody, 1=bass, 2=drums, 3=countermelody
    n_tracks = 4 if layer == "action" else (3 if layer == "tension" else 2)
    midi = MIDIFile(n_tracks)

    for t in range(n_tracks):
        midi.addTempo(t, 0, bpm)

    # Track 0: melody (all layers)
    midi.addProgramChange(0, 0, 0, PATCH_SQUARE_LEAD)
    MELODIES[biome](midi, 0, 0, sc, bars)

    # Track 1: bass (all layers)
    midi.addProgramChange(1, 1, 0, PATCH_SYNTH_BASS)
    add_bass(midi, 1, 1, sc, biome, bars)

    if layer in ("tension", "action"):
        # Track 2: drums
        add_drums(midi, 2, 9, biome, bars)

    if layer == "action":
        # Track 3: countermelody
        midi.addProgramChange(3, 3, 0, PATCH_BRASS)
        add_countermelody(midi, 3, 3, sc, biome, bars)

    return midi


def build_sting(sting) -> MIDIFile:
    """Build a short one-shot sting MIDI."""
    midi = MIDIFile(1)
    midi.addTempo(0, 0, 140)
    midi.addProgramChange(0, 0, 0, PATCH_SQUARE_LEAD)

    if sting == "victory":
        # Ascending 4-note major fanfare
        for i, (deg, t, dur) in enumerate([(0, 0, 0.4), (2, 0.4, 0.4),
                                            (4, 0.8, 0.4), (7, 1.2, 1.2)]):
            sc = scale(60, MAJOR)
            add_note(midi, 0, 0, sc[deg % len(sc)], t, dur, 90)
    elif sting == "loss":
        # Descending minor tritone
        sc = scale(60, NATURAL_MINOR)
        for deg, t, dur in [(6, 0, 0.5), (4, 0.5, 0.5), (1, 1.0, 0.5), (0, 1.5, 1.5)]:
            add_note(midi, 0, 0, sc[deg % len(sc)], t, dur, 80)
    elif sting == "sortie":
        # March-like 3-note call
        sc = scale(60, MAJOR)
        for deg, t, dur in [(0, 0, 0.3), (4, 0.3, 0.3), (7, 0.6, 0.3),
                            (4, 0.9, 0.3), (7, 1.2, 0.6)]:
            add_note(midi, 0, 0, sc[deg % len(sc)], t, dur, 85)

    return midi


# ── Rendering ─────────────────────────────────────────────────────────────────

def render(midi: MIDIFile, out_ogg: Path, preview: bool = False) -> bool:
    """Write MIDI → WAV via FluidSynth → OGG via ffmpeg."""
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    preview_wav = PREVIEW_DIR / out_ogg.with_suffix(".wav").name

    with tempfile.NamedTemporaryFile(suffix=".mid", delete=False) as f:
        mid_path = Path(f.name)
        midi.writeFile(f)

    try:
        # MIDI → WAV
        wav_path = preview_wav if preview else mid_path.with_suffix(".wav")
        if preview:
            wav_path.parent.mkdir(parents=True, exist_ok=True)

        result = subprocess.run(
            ["fluidsynth", "-ni", "-F", str(wav_path), str(SOUNDFONT), str(mid_path)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"    [ERR] fluidsynth: {result.stderr.strip()[:120]}")
            return False

        if not preview:
            # WAV → OGG
            result = subprocess.run(
                ["ffmpeg", "-y", "-i", str(wav_path),
                 "-c:a", "libvorbis", "-q:a", "4", str(out_ogg)],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"    [ERR] ffmpeg: {result.stderr.strip()[-120:]}")
                return False
            wav_path.unlink(missing_ok=True)
        else:
            print(f"    [WAV] preview → {wav_path.relative_to(REPO_ROOT)}")

        return True
    finally:
        mid_path.unlink(missing_ok=True)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Generate Choplifter Clone music")
    parser.add_argument("--biome",   choices=BIOMES, help="Generate one biome")
    parser.add_argument("--layer",   choices=LAYERS, help="Generate one layer only")
    parser.add_argument("--sting",   choices=STINGS, help="Generate one sting")
    parser.add_argument("--preview", action="store_true",
                        help="Keep intermediate WAV files for listening")
    args = parser.parse_args()

    tasks = []  # list of (description, MIDIFile, out_path)

    if args.sting:
        stem = f"music_sting_{args.sting}"
        tasks.append((stem, build_sting(args.sting), OUT_DIR / f"{stem}.ogg"))
    elif args.biome:
        layers = [args.layer] if args.layer else LAYERS
        for layer in layers:
            stem = f"music_{args.biome}_{layer}"
            tasks.append((stem, build_layer(args.biome, layer), OUT_DIR / f"{stem}.ogg"))
    else:
        # All biome layers
        for biome in BIOMES:
            for layer in LAYERS:
                stem = f"music_{biome}_{layer}"
                tasks.append((stem, build_layer(biome, layer), OUT_DIR / f"{stem}.ogg"))
        # All stings
        for sting in STINGS:
            stem = f"music_sting_{sting}"
            tasks.append((stem, build_sting(sting), OUT_DIR / f"{stem}.ogg"))

    print(f"Generating {len(tasks)} music track(s)...")
    ok = err = 0
    for desc, midi, out_path in tasks:
        if not args.preview and out_path.exists():
            print(f"  [OK ] {desc}: skipped (already exists)")
            ok += 1
            continue
        success = render(midi, out_path, preview=args.preview)
        if success:
            label = "preview WAV" if args.preview else str(out_path.relative_to(REPO_ROOT))
            print(f"  [OK ] {desc}: {label}")
            ok += 1
        else:
            print(f"  [ERR] {desc}: failed")
            err += 1

    print(f"\nDone. {ok}/{ok+err} succeeded, {err} failed.")


if __name__ == "__main__":
    main()
