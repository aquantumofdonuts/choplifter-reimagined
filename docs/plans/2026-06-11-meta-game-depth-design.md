# Meta-Game Depth Additions — Design

**Date:** 2026-06-11
**Status:** Approved (brainstorming session with attack pass)
**Amends:** `ENHANCED_GAMEPLAY.md` §5.1, §5.5; adds §5.6. Implementation plan Task 37 extended, Task 37b added.

## Motivation

The Tier C meta-game (mission rating + persistent records) is intentionally thin — the restraint is load-bearing, since arcade-style point scoring would invert the game's rescue-over-kills values. These three additions deepen the *existing* grade/time system without making it bigger: no points, no leaderboards, no online component.

Decisions made during design:
- Grade ceiling shown **only on the end-of-wave summary card** — no real-time HUD toast (rejected: keeps the in-game HUD untouched).
- Splits compare against the **single PB run's** splits, not best-ever per-wave "golden splits".
- Career stats tracked in **all variants** (pure bookkeeping; no surface in faithful modes).
- Display: new **Records panel** in the Main Menu hub + run-relevant lines on the mission-end card only.

## 1. Grade Ceiling Indicator (extends §5.1)

At any moment the run has a *best achievable grade*: the §5.1 grade table evaluated against current casualties and sorties (which only increase), with S additionally requiring elapsed time still under the S target time. Implemented as a pure function `best_achievable_grade(casualties, sorties, elapsed) -> Grade`, sharing the same threshold constants as final grading (thresholds themselves remain TBD per §5.1).

The end-of-wave summary card gains one line: "S rank still in reach" while the ceiling is S, otherwise "Best possible: A/B/C". Computed at card render time — no cached state, no signals. Card duration stays 2 seconds. Reimagined-only (the card itself is the gate).

## 2. Per-Wave PB Splits (extends §5.5)

Each of the 6 PB record slots gains an optional field `best_time_splits: Array[float]` — 4 cumulative wave-boundary times captured from the run that set `best_time`. Written only when a completed victory beats the slot's best time, so splits always describe one coherent run.

The summary card's time line becomes a comparison: `Wave 2 — 4:12 (PB 4:06, +0:06)`. The **+/− sign is the primary signal** (colorblind-safe); green/red coloring is secondary.

Fallbacks: no PB yet, or a pre-feature PB record without splits → show wave time alone. ConfigFile tolerates missing keys; no migration.

Run state: `GameState.run_splits: Array[float]`, cleared at run start, appended at each wave delivery. Lives in the GameState autoload, so it survives the World.tscn reload-on-death (the R3-C3 class of bug does not apply).

## 3. Career Stats & Records Screen (new §5.6)

Lifetime counters, incremented in **all variants** but **never in demo/attract mode** (`not GameState.demo_mode` guard — demo auto-play delivers hostages and would otherwise inflate stats):

| Counter | Incremented when |
|---|---|
| `total_hostages_rescued` | Batch delivered to base |
| `total_hostages_killed` | Each casualty |
| `total_sorties_flown` | Sortie launch |
| `total_runs` | Run start |
| `total_victories` | Victory |
| `perfect_runs` | Victory with 0 casualties (any sorties; variant-agnostic, distinct from S rank) |
| `total_playtime_seconds` | In-game unpaused time |

**Storage:** separate `user://career.cfg` (not highscores.cfg) so the §5.5 corruption-reset of one file can never wipe the other. Writes go to a temp file then rename (best-effort atomicity — a crash mid-write must not zero lifetime stats). Same corruption rule: failed parse → reset, log warning, never crash.

**Flush points:** run start, each wave delivery, run end (victory / loss / quit-to-menu — all exits route through the Main Menu hub). A hard crash loses at most the current run's increments. Single-instance assumption: concurrent processes last-write-win; accepted for a single-player desktop/web game.

**Records screen:** slide-in panel in `MainMenu.tscn`, same pattern as SettingsPanel. Section 1: Career (table above). Section 2: Personal Bests — the 6 variant × mode slots (best grade, time, casualties, sorties, date; "—" when empty). Read-only; reads both cfg files on open.

**Ownership:** a new `Records.gd` autoload owns both cfg files (load, flush, atomic write, corruption handling). `GameState` keeps run-scoped state (`run_splits`, casualty/sortie counters) and calls into `Records` at flush points.

## Attack Pass Results

Issues found and fixed in this design: demo-mode stat inflation (guard added); underspecified career flush points (run start/wave/run end specified); non-atomic career.cfg writes (temp+rename); color-only split deltas (sign is primary signal). No architectural contradictions found otherwise. Design attack passed.
