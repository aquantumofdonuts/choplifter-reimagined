"""
SFX parameter specifications for src/tools/generate_sfx.py.

Each key is the output filename stem (→ assets/audio/sfx/<name>.ogg).

Fields:
  waveform      : "square" | "sine" | "sawtooth" | "noise"
  freq_start/end: Hz — for tonal waveforms defines frequency (or sweep range)
  freq_sweep    : "linear" | "exp"  (default "linear")
  duration      : seconds
  amplitude     : 0–1 peak level after normalisation
  envelope      : ADSR dict — attack/decay/release in seconds, sustain in 0–1
  noise_mix     : 0–1 fraction of white noise blended into tonal wave
  lowpass_hz    : static lowpass cutoff (Hz)
  highpass_hz   : static highpass cutoff (Hz)
  bandpass_hz   : (lo_hz, hi_hz) bandpass  [noise waveform only]
  crackle_rate_ms: if present, multiply by random gate of this period (ms)
  crackle_duty  : fraction of gate windows that are "on"  (default 0.5)
  loop_seamless : True → no attack/release envelope; waveform period divides
                  loop length exactly so Godot can loop without a click
  notes         : list of {freq, start, duration} for multi-tone sounds;
                  when present, top-level freq_start/end are ignored
"""

SAMPLE_RATE: int = 44100

SFX_SPECS: dict[str, dict] = {

    # ── chopper engine — 80 Hz × 0.5 s = 40 complete cycles, phase-coherent ──
    "engine_loop": {
        "waveform":      "square",
        "freq_start":    80.0,
        "freq_end":      80.0,
        "duration":      0.5,
        "amplitude":     0.55,
        "envelope":      {"attack": 0.0, "decay": 0.0, "sustain": 1.0, "release": 0.0},
        "noise_mix":     0.06,
        "lowpass_hz":    1800.0,
        "loop_seamless": True,
    },

    # ── weapons ──────────────────────────────────────────────────────────────
    "bullet_fire": {
        "waveform":   "square",
        "freq_start": 880.0,
        "freq_end":   220.0,
        "freq_sweep": "exp",
        "duration":   0.08,
        "amplitude":  0.65,
        "envelope":   {"attack": 0.002, "decay": 0.07, "sustain": 0.0, "release": 0.01},
        "noise_mix":  0.05,
    },

    "bullet_impact": {
        "waveform":   "noise",
        "duration":   0.10,
        "amplitude":  0.50,
        "envelope":   {"attack": 0.001, "decay": 0.09, "sustain": 0.0, "release": 0.01},
        "lowpass_hz": 800.0,
    },

    "tank_fire": {
        "waveform":   "square",
        "freq_start": 140.0,
        "freq_end":    55.0,
        "freq_sweep": "exp",
        "duration":   0.25,
        "amplitude":  0.80,
        "envelope":   {"attack": 0.002, "decay": 0.22, "sustain": 0.0, "release": 0.03},
        "noise_mix":  0.45,
        "lowpass_hz": 1200.0,
    },

    "jet_fire": {
        "waveform":   "sawtooth",
        "freq_start": 280.0,
        "freq_end":   840.0,
        "freq_sweep": "exp",
        "duration":   0.18,
        "amplitude":  0.70,
        "envelope":   {"attack": 0.006, "decay": 0.0, "sustain": 1.0, "release": 0.10},
        "noise_mix":  0.18,
    },

    "bomb_drop": {
        "waveform":   "sine",
        "freq_start": 580.0,
        "freq_end":   110.0,
        "freq_sweep": "exp",
        "duration":   0.40,
        "amplitude":  0.60,
        "envelope":   {"attack": 0.005, "decay": 0.0, "sustain": 1.0, "release": 0.08},
    },

    # ── explosions ────────────────────────────────────────────────────────────
    "explosion": {
        "waveform":   "noise",
        "duration":   0.55,
        "amplitude":  0.88,
        "envelope":   {"attack": 0.002, "decay": 0.48, "sustain": 0.0, "release": 0.07},
        "lowpass_hz": 700.0,
    },

    "explosion_small": {
        "waveform":   "noise",
        "duration":   0.22,
        "amplitude":  0.70,
        "envelope":   {"attack": 0.001, "decay": 0.18, "sustain": 0.0, "release": 0.04},
        "lowpass_hz": 1100.0,
    },

    # ── hostages ──────────────────────────────────────────────────────────────
    "hostage_board": {
        "waveform":  "square",
        "duration":  0.24,
        "amplitude": 0.58,
        "notes": [
            {"freq": 523.25, "start": 0.00, "duration": 0.07},   # C5
            {"freq": 659.25, "start": 0.08, "duration": 0.07},   # E5
            {"freq": 783.99, "start": 0.16, "duration": 0.07},   # G5
        ],
        "envelope": {"attack": 0.004, "decay": 0.0, "sustain": 1.0, "release": 0.025},
    },

    "hostage_death": {
        "waveform":  "sine",
        "duration":  0.34,
        "amplitude": 0.55,
        "notes": [
            {"freq": 440.00, "start": 0.00, "duration": 0.15},   # A4
            {"freq": 369.99, "start": 0.17, "duration": 0.15},   # F#4 — descending minor 3rd
        ],
        "envelope": {"attack": 0.010, "decay": 0.0, "sustain": 1.0, "release": 0.04},
    },

    # ── chopper physics ───────────────────────────────────────────────────────
    "landing": {
        "waveform":   "noise",
        "duration":   0.30,
        "amplitude":  0.72,
        "envelope":   {"attack": 0.003, "decay": 0.27, "sustain": 0.0, "release": 0.03},
        "lowpass_hz": 550.0,
    },

    "bounce": {
        "waveform":   "noise",
        "duration":   0.15,
        "amplitude":  0.65,
        "envelope":   {"attack": 0.001, "decay": 0.13, "sustain": 0.0, "release": 0.02},
        "lowpass_hz": 1000.0,
    },

    # ── alien saucer — 3 pitch variants via bandpass-filtered crackle noise ──
    "alien_crackle_lo": {
        "waveform":        "noise",
        "duration":        0.45,
        "amplitude":       0.48,
        "envelope":        {"attack": 0.01, "decay": 0.0, "sustain": 1.0, "release": 0.08},
        "bandpass_hz":     (120.0, 280.0),
        "crackle_rate_ms": 9.0,
        "crackle_duty":    0.55,
    },

    "alien_crackle_mid": {
        "waveform":        "noise",
        "duration":        0.45,
        "amplitude":       0.48,
        "envelope":        {"attack": 0.01, "decay": 0.0, "sustain": 1.0, "release": 0.08},
        "bandpass_hz":     (280.0, 560.0),
        "crackle_rate_ms": 7.0,
        "crackle_duty":    0.50,
    },

    "alien_crackle_hi": {
        "waveform":        "noise",
        "duration":        0.45,
        "amplitude":       0.48,
        "envelope":        {"attack": 0.01, "decay": 0.0, "sustain": 1.0, "release": 0.08},
        "bandpass_hz":     (560.0, 1200.0),
        "crackle_rate_ms": 5.0,
        "crackle_duty":    0.45,
    },

    # ── Mode 2+ telegraphs and warnings ───────────────────────────────────────
    "fire_telegraph": {
        "waveform":   "square",
        "freq_start": 220.0,
        "freq_end":   660.0,
        "freq_sweep": "linear",
        "duration":   0.30,
        "amplitude":  0.58,
        "envelope":   {"attack": 0.01, "decay": 0.0, "sustain": 1.0, "release": 0.05},
    },

    "stranded_warning": {
        "waveform":  "square",
        "duration":  1.80,
        "amplitude": 0.50,
        "notes": [
            {"freq": 440.0, "start": 0.00, "duration": 0.12},
            {"freq": 440.0, "start": 0.60, "duration": 0.12},
            {"freq": 440.0, "start": 1.20, "duration": 0.12},
        ],
        "envelope": {"attack": 0.005, "decay": 0.0, "sustain": 1.0, "release": 0.05},
    },

    "fuel_low": {
        "waveform":   "square",
        "freq_start": 220.0,
        "freq_end":   220.0,
        "duration":   0.14,
        "amplitude":  0.52,
        "envelope":   {"attack": 0.005, "decay": 0.0, "sustain": 1.0, "release": 0.05},
    },

    # ── UI ────────────────────────────────────────────────────────────────────
    "ui_select": {
        "waveform":    "noise",
        "duration":    0.04,
        "amplitude":   0.38,
        "envelope":    {"attack": 0.001, "decay": 0.03, "sustain": 0.0, "release": 0.01},
        "highpass_hz": 1500.0,
    },

    "ui_confirm": {
        "waveform":  "square",
        "duration":  0.22,
        "amplitude": 0.52,
        "notes": [
            {"freq": 523.25, "start": 0.00, "duration": 0.09},   # C5
            {"freq": 783.99, "start": 0.11, "duration": 0.09},   # G5
        ],
        "envelope": {"attack": 0.005, "decay": 0.0, "sustain": 1.0, "release": 0.03},
    },
}
