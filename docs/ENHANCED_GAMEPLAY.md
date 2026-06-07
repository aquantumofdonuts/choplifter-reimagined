# Choplifter Clone — Enhanced Gameplay Design

> **Applies to:** Mode 2 (Modern Pixel Art) and Mode 3 (Hi-Res) only.  
> Mode 1 (Retro) is always a faithful port — bugs and all. No variant picker.  
> See also: [DESIGN.md](DESIGN.md)

---

## 1. Overview

When launching Mode 2 or Mode 3, the player is presented with a **Gameplay Variant** picker before the sortie banner. The picker offers three tiers, each a strict superset of the previous:

| Tier | Name | Description |
|---|---|---|
| A | **Standard** | Bug fixes and polish only. The game as it should have been. |
| B | **Director's Cut** | Standard + enhanced physics, better readability, improved progression. |
| C | **Reimagined** | Director's Cut + new mechanics. The best version of the concept. |

The selected variant is saved to `user://settings.cfg` and pre-selected on next launch.

**Implementation pattern:** A `gameplay_variant` enum in `GameState.gd`:

```
enum GameplayVariant { STANDARD, DIRECTORS_CUT, REIMAGINED }
```

All enhancement code checks `GameState.gameplay_variant` before activating. The base code path is always the same; enhancements are layered additively on top. This means Mode 1 and Mode 2/Standard share the same gameplay core — no forking.

---

## 2. Variant Picker UI

Shown after mode selection (Modern/Hi-Res), before the sortie banner. Single screen, three cards presented horizontally or vertically depending on aspect ratio.

**Each card shows:**
- Tier name and subtitle
- 2–3 bullet points describing what's included
- "Includes everything in [previous tier]" note for B and C

Navigation: keyboard `←→` / D-pad, mouse hover+click, touch tap. Confirm with Enter / A / tap. The previously-selected variant is highlighted on open.

**Mode 1 (Retro):** No picker shown. Proceeds directly to `RetroTitle.tscn` or `SortieBanner.tscn`.

---

## 3. Tier A — Standard (Bug Fixes + Polish)

These are corrections to source bugs and invisible friction. Nothing changes how the game plays.

### 3.1 Bug Fixes

**Tank spawn distribution**

- **Source bug:** `ENTITY_X_H` (high byte of tank X position) is always set to 0, clustering all tanks at the world's left edge near the base.
- **Fix:** Spawn tanks at player's current X position ± random spread, clamped to world bounds. Apply across all 8 depth planes. Tanks now appear throughout the world as the game's visual design implies.
- **Implementation:** In `SpawnManager.gd`, when `GameState.gameplay_variant >= STANDARD`, override the X_H=0 path with `player_x + randi_range(-screen_widths, +screen_widths)`.

**Alien fire condition**

- **Source bug:** `cmp #$03 / bne skip_shot` — aliens only fire at exactly `CURR_LEVEL == 3`. At levels 4–7 (Mode 2 extended difficulty), aliens go silent again.
- **Fix:** Change to `bcc` — aliens fire at level 3 and above.
- **Implementation:** `Alien.gd` fire-check: `if GameState.curr_level >= 3` (replacing the equality check).

**Enemy spawn cadence**

- **Source bug:** `FRAME_COUNT AND $2F == 0` bitmask produces a non-uniform 16-frame/48-frame alternating burst pattern. Enemies arrive in clumps with long gaps.
- **Fix:** Replace with a uniform timer (`spawn_timer`) initialized to a base interval with ±5 frame random jitter per cycle. Base interval matches the *average* cadence of the original (~32 frames) so overall enemy pressure is unchanged.
- **Implementation:** `SpawnManager.gd` — replace bitmask check with `spawn_timer` countdown. Reset to `base_interval + randi_range(-5, 5)` after each attempt.

**Hostage spawn interval**

- **Source:** Every 4 frames (`FRAME_COUNT AND $03 == 0` — fires at 0, 4, 8, ...).
- **Fix:** Tune to a value that feels appropriately responsive at 60fps. The original 4-frame interval at ~30fps Apple II speed is effectively every 8 frames at 60fps. Use 8 frames as the base in Standard mode.

### 3.2 Polish (No Mechanical Change)

**Death readout**

When the chopper dies with hostages aboard, show a brief "X hostages lost" overlay card during the explosion animation (before the sortie banner). Players currently have no feedback about why their killed count jumped. Card fades after 2 seconds — no input required.

**Loss condition clarity**

HUD shows remaining headroom: a small indicator (e.g. skull icon + count) showing how many more hostage deaths end the run. The formula is `64 - TOTAL_RESCUES - HOSTAGES_KILLED`. Updates in real time. Makes the stakes legible without changing the rules.

**Scroll lead rescaling**

The original `SCROLL_LEAD_L = $46` (70 px) and `SCROLL_LEAD_R = $D2` (210 px) are viewport-relative values at 280px width. Scale proportionally to 480px width:
- Left lead: `70 × (480/280)` ≈ **120 px**
- Right lead: `210 × (480/280)` ≈ **360 px**

The asymmetry is preserved. The chopper still sits ~25% from the left edge when flying left.

---

## 4. Tier B — Director's Cut (Enhanced Mechanics)

Includes all of Tier A. These changes make the game more learnable and satisfying without adding anything that wasn't implied by the original design.

### 4.1 Physics Improvements

**Smoother Y acceleration curve**

The source `integrateAccelerationAccelYTable` has an abrupt step at the top: index 14 = +4, index 15 = +6. Fine altitude control is difficult near max thrust.

Replace the top 4 entries with a smoother ramp:

| Index | Original | Standard (Mode 2) |
|---|---|---|
| 12 | +2 | +2 |
| 13 | +3 | +3 |
| 14 | +4 | +4 |
| 15 | +6 | +5 |

Full thrust is slightly less aggressive; fine hovering becomes more precise. The overall thrust envelope is preserved.

**Landing forgiveness window**

The source has a single `MIN_VY` threshold — land above it and you die. Mode 2 adds a three-zone system:

| Zone | Condition | Result |
|---|---|---|
| Safe | `vy <= MIN_VY` | Normal landing |
| Bounce | `MIN_VY < vy <= CRASH_VY` | Chopper bounces up with ~40% of impact velocity; plays a thud sound |
| Crash | `vy > CRASH_VY` | Death (same as original) |

`CRASH_VY` = `MIN_VY × 2.0` (exact multiplier tuned during playtesting).

**Bounce limit:** After 3 consecutive bounces without gaining meaningful altitude (defined as `vy_peak < MIN_VY × 0.5` between bounces), the next landing always crashes. Prevents infinite bouncing.

**Momentum bleed through turns**

In Mode 1, `logical_face` flips instantly and `turn_state` animates purely cosmetically — horizontal velocity is not affected by the turn. Mode 2 Director's Cut applies a momentum bleed:

- During the first 3 frames of a turn (`|turn_delta| >= 3` from target), horizontal deceleration is reduced by 50%.
- The chopper continues drifting in the previous direction before the new direction takes full effect.
- After 3 frames, normal acceleration applies.

This is implemented by temporarily halving `ZP_ACCELX` effectiveness in the first 3 turn frames. The effect is subtle — approximately 3–5 px of extra drift — but it makes direction changes feel physical rather than binary.

### 4.2 Readability Improvements

**Enemy fire telegraph**

Tanks and jets show a visible "charge" tell before firing:
- 0.4s before firing: gun/cannon plays a brief bright flash animation (1–2 frames) + a short rising tone
- The projectile fires as normal after the delay

The tell is purely cosmetic — it does not reduce fire frequency or damage. It makes the threat skill-readable rather than invisible. Aliens are **exempt** — their chaotic, hunting behavior should feel different and unpredictable.

**Implementation:** In `Tank.gd` and `Jet.gd`, insert a `charge_timer` (24 frames at 60fps) before `fire_projectile()`. During `charge_timer > 0 and charge_timer <= 24`, play the telegraph animation. Fire when timer reaches 0.

**Hostage capacity display**

HUD counter for "on board" changes from a plain number to a `current/max` fraction (e.g. `3/5`). The denominator is the chopper's maximum hostage capacity (extracted from source or set as a tunable constant in `GameState.gd`).

Gives players the information to decide whether to make another pass or return to base.

**Jet approach variety**

The source always spawns "easy" jets (low levels) facing right — making their approach pattern exploitable within one play session. Director's Cut randomizes initial facing at all levels. At higher levels jets still use player-velocity-based spawn direction (from source); at low levels it's now random.

### 4.3 Progression Improvements

**Continuous difficulty above level 3**

Mode 1 caps `CURR_LEVEL` at 3. Mode 2 extends to 7. At levels 4–7, enemy counts stay at 2/2/2 (same cap as level 3), but aggression scales:

| Metric | Level 4 | Level 5 | Level 6 | Level 7 |
|---|---|---|---|---|
| Tank fire interval multiplier | 0.85× | 0.75× | 0.65× | 0.55× |
| Jet spawn-from-behind probability | 60% | 70% | 80% | 90% |
| Alien fire probability (per eligible frame) | +10% | +20% | +30% | +40% |

Base values are from the source at level 3. Multipliers are initial tuning targets; adjust during playtesting.

**Between-sortie world continuity**

On chopper death, the following state is **preserved** into the next sortie:
- `TOTAL_RESCUES` (rescued count)
- `HOSTAGES_KILLED` (kill count — importantly, hostages aboard at death are added to this before continuity is saved)
- Which houses have been cleared (no hostages remaining inside)
- `CURR_LEVEL`

The following state is **reset**:
- All enemy entities (tanks, jets, aliens, projectiles)
- Hostages currently in the field (running, boarding) — they are considered lost; add to `HOSTAGES_KILLED`
- Chopper position (respawns at base)
- `HOSTAGES_LOADED` (carried count — reset to 0)

Houses with remaining hostages are preserved — if a house still has occupants, they can be rescued next sortie. This means partially-cleared houses carry over, which is the main mechanical benefit.

---

## 5. Tier C — Reimagined

Includes all of Tier A and Tier B. These additions introduce new mechanics and feedback loops. The game is still recognizably Choplifter; the additions layer on top without replacing the core.

### 5.1 Mission Rating

After each sortie completion (win or loss) and after each wave delivery (end-of-wave summary), display a letter grade: **S / A / B / C / F**.

**Formula inputs:**

| Input | Weight | Notes |
|---|---|---|
| Casualties (`HOSTAGES_KILLED`) | High | Primary metric; 0 kills required for S |
| Sorties used | Medium | Fewer deaths = higher grade |
| Time (seconds) | Low | Faster = higher grade within same kill/sortie bracket |

**Grade thresholds** (TBD — set during playtesting, after establishing baseline completion times):

| Grade | Condition |
|---|---|
| S | 0 casualties, ≤ 1 sortie used, within target time |
| A | 0 casualties, any sorties, any time |
| B | 1–3 casualties, ≤ 2 sorties |
| C | 4–8 casualties or 3 sorties used |
| F | 9+ casualties or all 3 sorties used |

The grade is shown on a mission-end card. No leaderboard, no online component — purely a personal benchmark.

**End-of-wave summary card** (shown after each batch delivery):
- Hostages this wave: rescued / killed
- Time for this wave
- Running grade for the full run
- Brief 2-second display, then auto-continues

### 5.2 Scatter on Death

When the chopper dies with hostages aboard, instead of immediately counting them as killed:

1. Each carried hostage spawns as a "stranded" entity at the crash site, distributed slightly around the explosion center.
2. Stranded hostages enter a 30-second countdown (visible as a small pulsing indicator above each one).
3. If the player returns and lands near them before the timer expires, they board normally.
4. If the timer expires, they are killed and added to `HOSTAGES_KILLED`.

**Off-screen indicator:** While any stranded hostages exist, a blinking directional arrow appears on the HUD edge pointing toward their position. Arrow disappears when all stranded are dead or aboard.

**Second death:** If the player dies again before rescuing stranded hostages, the stranded hostages' remaining countdown is halved. If a third death occurs with any still stranded, they are immediately killed.

**One-time tutorial:** On the first death-with-scatter in a session, a brief tooltip appears: "Hostages stranded at crash site — rescue them before they're lost." Shown once per session, not once per game.

**Implementation notes:**
- Stranded hostages use a new `STRANDED` state in the hostage state machine.
- Their countdown timer is a `float` on each `Hostage` node, decremented in `_process`.
- They do not move, wave, or run — they sit at the crash position.
- Enemy fire does not target stranded hostages (simplification — avoids complex targeting logic for an edge case).

### 5.3 Fuel System

**Default:** Off. Toggled in Settings (`fuel_enabled: Bool`, default `false`). Available in Reimagined mode only.

**Mechanics:**

- Fuel gauge starts full at sortie start and on every base landing.
- Fuel depletes at a base rate during flight; full-thrust depletes fuel 2× faster than hover.
- At 25% fuel remaining, a warning indicator appears on the HUD (color change + audio pulse).
- At 0% fuel:
  - Thrust is reduced to hover-only (no forward acceleration, no climb above current altitude).
  - The chopper descends at a controlled rate (gravity still applies, but gently — not a freefall).
  - On touching ground anywhere, fuel refills to **25%** — enough for one careful return trip to base.
  - Full refill only happens on base landing.

**Carried hostages:** Not affected by fuel state. They stay aboard during emergency descent and relaunch.

**Relaunch from field:** The player can relaunch immediately after an emergency landing (press thrust). If fuel is at 25% they can fly carefully back to base. If they run out again mid-return, they descend again and refuel to 25% again on landing. This creates a "hops" pattern back to base rather than a death spiral.

**Implementation notes:**
- `fuel: float` on `Chopper.gd`, range 0.0–1.0. Decremented each physics frame during flight.
- `THRUST_FUEL_RATE` and `HOVER_FUEL_RATE` constants (tuned during playtesting).
- Fuel state checked in `Chopper.gd._physics_process()` before applying acceleration.
- HUD fuel gauge: horizontal bar in HUD, hidden when `fuel_enabled == false`.
- Emergency refill on landing: set `fuel = 0.25` in the landing handler when `fuel <= 0`.

### 5.4 Enemy Coordination

**Tank depth exclusion**

Before spawning a new tank, `SpawnManager.gd` checks the ground planes of all active tanks. The new tank is assigned to an unoccupied plane. If all planes in the target area are occupied, the spawn is deferred until a plane frees up. Maximum 4 tanks but always visually separated.

**Alien despawn grace**

The source instantly despawns the alien when `|delta_x| > ~2 screens`. Reimagined adds a 2-second grace timer: when the alien first exceeds the despawn threshold, start the timer. If the player moves back within range before the timer expires, the timer resets. Only despawn when the timer completes. Makes escaping aliens feel intentional rather than accidental.

**Jet coordination**

If 2 jets are active simultaneously, they are assigned opposing approach directions: one attacks from ahead, one from behind. A `jet_directions_assigned: bool` flag in `SpawnManager.gd` ensures this. Single-jet situations remain random.

### 5.5 Persistent Records

Saved to `user://highscores.cfg`. One record per variant × mode combination (6 total: Standard/DCut/Reimagined × Mode2/Mode3).

| Field | Type |
|---|---|
| Best grade | Enum (S/A/B/C/F) |
| Best time (seconds) | Float |
| Best casualty count | Int |
| Best sorties used | Int |
| Date of best run | ISO date string |

Records are displayed on the mission-end card ("Personal best: A — 4:32"). No online component.

**Corruption handling:** If `highscores.cfg` fails to parse, silently reset records to default (no record). Log warning to Godot output. Do not crash.

---

## 6. Implementation Notes

### 6.1 Variant Check Pattern

All enhancement code uses a consistent guard pattern:

```gdscript
# Tier A and above:
if GameState.gameplay_variant >= GameState.GameplayVariant.STANDARD:
    pass

# Tier B and above:
if GameState.gameplay_variant >= GameState.GameplayVariant.DIRECTORS_CUT:
    pass

# Tier C only:
if GameState.gameplay_variant == GameState.GameplayVariant.REIMAGINED:
    pass
```

Since tiers are integers in ascending order, `>=` correctly handles the superset relationship.

### 6.2 New State in GameState.gd

```gdscript
enum GameplayVariant { STANDARD = 0, DIRECTORS_CUT = 1, REIMAGINED = 2 }
var gameplay_variant: GameplayVariant = GameplayVariant.STANDARD

# Tier C additions:
var fuel_enabled: bool = false       # Loaded from settings.cfg
var scatter_on_death: bool = true    # Always true in Reimagined; not a toggle
```

### 6.3 Affected Systems Summary

| System | Tier A | Tier B | Tier C |
|---|---|---|---|
| `SpawnManager.gd` | Tank spawn fix, cadence fix | Jet direction variety, fire telegraph | Tank exclusion, jet coordination, alien grace timer |
| `Chopper.gd` | — | Momentum bleed, landing zones, scroll lead rescale | Fuel system |
| `Alien.gd` | Alien fire level fix | — | Despawn grace timer |
| `Tank.gd` / `Jet.gd` | — | Fire telegraph | — |
| `Hostage.gd` | Spawn interval fix | — | Scatter on death (STRANDED state) |
| `HUD.gd` | Death readout, loss headroom, scroll fix | Capacity display | Fuel gauge, stranded indicator, grade display |
| `GameState.gd` | — | World continuity on death | Variant enum, fuel_enabled, scatter state |
| `World.tscn` | — | End-of-wave summary | Mission rating card, persistent records |

### 6.4 Roadmap Placement

| Feature Group | Target Version |
|---|---|
| Tier A (all bug fixes) | v0.2 (full Retro game complete) |
| Variant picker UI | v0.3 (Mode 2 Desert biome) |
| Tier B mechanics | v0.4 (Mode 2 full biomes) |
| Tier C mechanics | v0.5 / v1.0 polish pass |
| Fuel system (optional) | v1.0 (can be gated behind settings toggle until polished) |

---

## 7. Design Notes & Constraints

- **Mode 1 is never touched.** The `gameplay_variant` enum is only checked when `GameState.visual_mode >= 2`. All variant guards are no-ops in Mode 1.
- **Tiers are supersets.** No feature in Tier B contradicts or disables a Tier A feature. No feature in Tier C contradicts or disables Tier B. This invariant must be maintained during implementation.
- **Fuel is optional within Reimagined.** It's the only Tier C feature that is user-toggleable. Everything else in Reimagined is always active when that tier is selected.
- **No multiplayer, no online features.** All records are local. No network calls anywhere in this system.
- **Playtesting is required** before finalizing: acceleration table index 15 value, `CRASH_VY` multiplier, fuel depletion rates, mission rating thresholds, stranded hostage countdown duration. All are marked TBD in this document and must be set empirically.
