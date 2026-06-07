# Choplifter Clone — Design Document

> **Engine:** Godot 4 · **Language:** GDScript · **Genre:** Side-scrolling rescue action  
> **Reference:** [blondie7575/ChoplifterReverse](https://github.com/blondie7575/ChoplifterReverse) — full annotated 6502 disassembly of the 1982 original  
> See also: [REVERSE_ENGINEER_ANALYSIS.md](REVERSE_ENGINEER_ANALYSIS.md)

> **Implementation note — reading `zeropage.s`:** Comments on ZP variables often describe the *state values or indices* stored in the variable, not physical magnitudes. For example, `ZP_ACCELY: $08 = Normal gravity, $0f = Full thrust up` means those are the values written into ZP_ACCELY to select table entries — not acceleration in units/frame². Always trace ZP variables through their lookup tables in `choplifter.s` before treating a comment value as a constant. This pattern caused several errors in `REVERSE_ENGINEER_ANALYSIS.md` that were inherited here; all known cases are corrected in this document.

---

## 1. Game Overview

A faithful-but-modernized reimplementation of Dan Gorlin's *Choplifter* (1982, Broderbund). The goal is to preserve the original's feel and mechanics while taking advantage of modern hardware for visuals, audio, and cross-platform reach.

**Guiding principle:** Every mechanical decision should ask "does this feel like Choplifter?" before "does this feel modern?". Where those conflict, Choplifter wins.

---

## 2. Core Loop

1. Take off from the base
2. Fly left toward hostage buildings; rescue run is left-to-right relative to the base
3. Land near hostage buildings; hostages run out and board automatically
4. Return right to base; they disembark on landing
5. Difficulty increases after each successful rescue run
6. Repeat until all 64 hostages are rescued (win) or any hostage is killed when `TOTAL_RESCUES + HOSTAGES_KILLED` reaches 64 / 3 lives exhausted (loss)

> **Note:** The player can fly freely in both directions at any time. The left/right orientation is the intended rescue route, not a restriction.

---

## 3. Win / Lose Conditions

Faithful to the original — **no score**.

| Condition | Trigger |
|---|---|
| **Victory** | `TOTAL_RESCUES == 64` (all 64 hostages rescued) |
| **Loss — hostages** | `TOTAL_RESCUES + HOSTAGES_KILLED == 64` while victory condition unmet — i.e. all 64 hostages are accounted for and at least one was killed |
| **Loss — lives** | 3 sorties (lives) used up |

> **Important:** There are exactly 64 hostages across all waves. The player must rescue **every single one**. Any kill makes a perfect run impossible — the game ends the moment the last unrescued hostage dies. "64 kills needed to lose" is incorrect; even one kill can end the game.

The counters displayed to the player:
- Rescued (total)
- Killed (total)
- On board (current sortie)

> **Hostages on board when chopper dies:** Carried hostages (`HOSTAGES_LOADED`) are counted as killed on chopper death — they add to `HOSTAGES_KILLED` and thus count toward the loss condition.

---

## 4. Enemies

| Enemy | Levels | Behavior |
|---|---|---|
| **Tank** | 0+ | Rolls on ground planes at varying depths; aims cannon at chopper; fires ballistic shells |
| **Jet** | 1+ | Flies at altitude; fires forward missiles and drops bombs; can attack from behind on higher levels |
| **Alien** | 2+ | UFO saucer that actively hunts the player; accelerates toward chopper on both axes (max VX ±5, max VY ±1); plays crackling audio keyed to animation frame; fires tank-shell-type projectiles downward at level 3+ (random spread, only at lower altitudes); despawns if player gets too far away on X; collides with and destroys the chopper on contact |

**Entity slot count:** 4 tanks, 4 jets, 4 aliens (entity table array sizes). **Mode 1 gameplay cap:** 2 tanks, 2 jets, 2 aliens at level 3 (see §4.1 spawn rate tables). The slot arrays are an engine limit; the spawn rate tables govern how many actually appear.

**Alien animation detail:** Saucer has two composited layers — a static body and a sliding mid-section that cycles through 3 frames. The mid-section position jitters by 1px on odd frames, creating a flickering energy-ring effect. The `ENTITY_DIR` field is reused as the mid-section animation frame counter (0–2) rather than direction.

**Houses** can be set on fire by enemy action, killing hostages inside.

### 4.1 Difficulty Scaling

**Mode 1 (faithful):** `CURR_LEVEL` runs **0–3** and is incremented after each successful rescue unload, capped at 3 by the source (`cmp #$03 / beq skip_increment`). It does **not** reset between sorties.

**Mode 2 / Mode 3 (enhanced):** Level cap is extended to 7, enabling the full biome progression. Levels 4–7 use the same enemy caps as level 3 but add tuned aggression, spawn rate adjustments, and biome transitions.

**Spawn schedule (from source):**
- Enemy vehicle spawn attempt: `FRAME_COUNT AND $2F == 0` — fires when bits 0,1,2,3,5 of the 8-bit frame counter are all zero. This produces a **non-uniform 16/48-frame alternating cadence** (~8 attempts per 256-frame cycle), not a fixed period. The value $2F is a bitmask, not a divisor; "every 47 frames" is a misreading of the source comment.
- Hostage emergence attempt: **every 4 frames** (`FRAME_COUNT AND $03 == 0`). Note: the original source comment incorrectly says "every three frames" — the code is `and #$03` which fires at frames 0, 4, 8, ...

**Max simultaneous enemies per level (faithful values from source):**

| `CURR_LEVEL` | Max Tanks | Max Jets | Max Aliens |
|---|---|---|---|
| 0 | 1 | 0 | 0 |
| 1 | 2 | 1 | 0 |
| 2 | 2 | 2 | 1 |
| 3 *(cap in Mode 1)* | 2 | 2 | 2 |
| 4–7 *(Mode 2/3 extension)* | 2 | 2 | 2 |

Levels 4–7 retain the same caps as level 3. Mode 2/3 difficulty tuning at those levels is via aggression, fire rate, and biome visual escalation — not more simultaneous units.

**Hostage wave structure:** `MAX_HOSTAGES = 16` (constant in source). The game runs 4 waves of 16 hostages, for 64 total. Cumulative counters (`TOTAL_RESCUES`, `HOSTAGES_KILLED`) track across all waves. Houses are not reset between sorties — only a new wave spawns when a rescue batch is delivered to base.

### 4.2 Entity Parameters

Values extracted from the original source; port should match these as a baseline before any tuning:

| Entity | Key Parameters |
|---|---|
| Tank | Patrols on a random depth plane; cannon aims at chopper X/Y each frame; fires at variable intervals based on player proximity. **Known source bug (Mode 1 must replicate):** `ENTITY_X_H` (high byte of tank X position) is always set to 0 — tanks always spawn on X-page 0 regardless of player position. |
| Jet | Spawns above chopper altitude; X-velocity driven by bank-angle table (barrel-roll animation ↔ velocity); fires missiles forward, drops bombs on proximity |
| Alien | Chase acceleration toward player each frame; max VX ±5 px/frame, max VY ±1 px/frame; **hover damp:** when the saucer body is off-screen or mid-animation cycle resets, `ENTITY_VY` is zeroed to level off flight (prevents dead-reckoning straight at the player); fires downward shells at level 3+ only when chopper is below a threshold altitude; despawns if Δx to player exceeds ~2 screens |
| Player bullet | 5 max on screen simultaneously; velocity and gravity keyed to `ZP_TURN_STATE` — bullets fire at different angles during turns (see §7 Bullet Trajectory) |
| Tank shell | Ballistic arc (gravity applied each frame) |
| Jet missile | Constant horizontal velocity, level flight |
| Jet bomb | Gravity drop from jet altitude |

---

## 5. Controls

### 5.1 Design Philosophy

Controls are defined as **abstract actions** in Godot's Input Map. Physical inputs (keys, buttons, touch) are bound to actions — game logic only ever checks actions, never specific hardware inputs. This gives us cross-platform input for free.

Runtime rebinding will be supported for keyboard/controller on desktop, saved to `user://input_map.cfg`.

### 5.2 Action Map

| Action | Description |
|---|---|
| `thrust_up` | Increase upward acceleration |
| `move_left` | Apply leftward acceleration |
| `move_right` | Apply rightward acceleration |
| `face_left` | Begin turn-in-place animation to face left |
| `face_right` | Begin turn-in-place animation to face right |
| `face_camera` | Begin turn-in-place animation to face camera (forward) |
| `fire` | Fire a bullet (max 5 on screen) |
| `pause` | Pause / unpause |

> **Note:** `face_*` actions do **not** lock firing. The player can fire during a turn; bullet angle and gravity vary with `turn_state` (see §7 Bullet Trajectory). `logical_face` flips instantly on `face_*` input; `turn_state` animates toward the new facing independently.

### 5.3 Keyboard + Mouse

| Action | Default Keys |
|---|---|
| `thrust_up` | `W` / `Up Arrow` |
| `move_left` | `A` / `Left Arrow` |
| `move_right` | `D` / `Right Arrow` |
| `face_left` | `Q` |
| `face_right` | `E` |
| `face_camera` | `S` / `Down Arrow` |
| `fire` | `Space` |
| `pause` | `Escape` / `P` |

Mouse is not used for gameplay.

### 5.4 Controller (Gamepad)

Godot detects Xbox, PlayStation, and Switch Pro controllers automatically via SDL. Button prompt glyphs will swap based on detected controller type.

| Action | Binding |
|---|---|
| `thrust_up` | Left Stick Up |
| `move_left` | Left Stick Left / D-pad Left |
| `move_right` | Left Stick Right / D-pad Right |
| `face_left` | Left Bumper (LB/L1) |
| `face_right` | Right Bumper (RB/R1) |
| `face_camera` | Left Stick Down / D-pad Down |
| `fire` | Right Trigger (RT/R2) / South Button (A/Cross) |
| `pause` | Start / Menu |

### 5.5 Touch (Mobile / Web on Touchscreen)

A virtual input overlay is rendered on touch-capable devices, hidden otherwise. Will use the **Virtual Joystick** addon from the Godot Asset Library or a custom implementation.

**Layout:**
- **Left half:** Virtual analog stick — maps to `thrust_up`, `move_left`, `move_right`. Stick-down maps to `face_camera`.
- **Right half — Fire button:** Large tap zone → `fire`
- **Right half — Face buttons:** Two smaller buttons for `face_left` / `face_right`

**Touch-specific UX notes:**
- Virtual stick appears where the thumb first touches (floating origin), not at a fixed position
- `face_camera` uses a **dedicated center button** between `face_left` and `face_right` (three face buttons total) — more discoverable than stick-down, avoids accidental triggers during descent
- Buttons use high-contrast icons with generous tap targets (minimum 48×48 dp)
- HUD counters are repositioned to avoid thumb overlap in portrait/landscape

### 5.6 Platform Matrix

| Platform | Keyboard | Controller | Touch |
|---|---|---|---|
| Windows / Linux / macOS | ✓ | ✓ | — |
| iOS | — | ✓ (MFi/BT) | ✓ |
| Android | — | ✓ (BT) | ✓ |
| Web (desktop browser) | ✓ | ✓ | — |
| Web (mobile browser) | — | — | ✓ |

---

## 6. Graphics & Visual Modes

### 6.1 Three-Tier Visual System

The game ships with three selectable visual modes. All three run on the same underlying gameplay code; only the asset set changes.

| Mode | Name | Resolution | Art Style | Status |
|---|---|---|---|---|
| 1 | **Retro** | ~280×192 logical | Authentic Apple II, integer-upscaled | v0.1 target |
| 2 | **Modern Pixel Art** | 480×270 | Full-color pixel art, detailed animation | v0.2–0.4 |
| 3 | **Hi-Res** | 1080p+ | Painterly / 3D-lit 2D (Godot 4 renderer) | v2.0 |

**Mode 1 is always a faithful port — bugs and all. No enhancements.**

Modes 2 and 3 present a **Gameplay Variant** picker before the sortie banner, offering three tiers of enhancement (Standard / Director's Cut / Reimagined). See [ENHANCED_GAMEPLAY.md](ENHANCED_GAMEPLAY.md) for the full specification.

### 6.2 Mode 1 — Retro (Authentic Apple II)

**The shortcut:** The original sprite binaries (`CHOPGFX`, `CHOPGFXHI`) are included in the reverse-engineer repo. A Python extraction tool at [src/tools/extract_sprites.py](../src/tools/extract_sprites.py) reads these and outputs all 128 named sprites as transparent PNGs.

```
python3 src/tools/extract_sprites.py \
  --gfx docs/blondie-ChoplifterReverse/CHOPGFX \
  --gfxhi docs/blondie-ChoplifterReverse/CHOPGFXHI \
  --out assets/graphics/original-sprites \
  --scale 4
```

**Apple II HGR sprite format:**
- Each byte holds 7 pixels (bits 0–6); bit 7 is the HGR palette selector
- Row order: bottom-to-top (extractor flips vertically)
- `--ntsc` flag approximates the authentic NTSC composite colour rendering

**Sprite inventory extracted:**
- Chopper: 11 sideways tilt frames + 5 head-on rotation frames + 2 squish + rotors
- Jet: 1 level + 24 turning frames (full 3D barrel-roll animation)
- Tank: turret, 2 tread frames, 5 cannon angles
- Hostages: 4 running + 3 waving + 2 loading frames
- Explosions: 5 frames
- Environments: 4 mountain patterns, base building, 5 fence tower depths, houses + fire
- UI: 10 digit glyphs, HUD elements, title cards, sortie banners

**Mode 1 color palette** (Apple II HGR 6 colours):
- Black `#000000`, White `#FFFFFF`
- Green `#3DFF39`, Violet `#C630FF`
- Orange `#FF6300`, Blue `#006BFF`

For Mode 1, extracted sprites are rendered **white on black** in Godot using a `CanvasItemMaterial` color modulate. This matches the cleanest reading of the original monochrome shapes. The `--ntsc` extractor output (orange/blue NTSC approximation) is available as a reference but is not used in-game — the pixel geometry is what matters for Mode 1, not the composite color fringing.

### 6.3 Mode 2 — Modern Pixel Art

**Target resolution:** 480×270 (exactly ¼ of 1080p → crisp integer scaling on any display)  
**Godot settings:** `Stretch/Mode = canvas_items`, `Textures/Default/Filter = Nearest`

**Sprite sizes at 480×270:**

| Sprite | Approx Size |
|---|---|
| Chopper | 48×24 px |
| Tank | 24×16 px |
| Hostage | 8×14 px |
| Jet | 32×12 px |

**AI-assisted art pipeline:**

| Task | Tool | Notes |
|---|---|---|
| Background environments | Midjourney / Leonardo.ai → Aseprite | Generate → palette-constrain → clean up |
| Terrain tiles | AI + Aseprite | 16×16 or 32×32 tileable tiles |
| Static sprites (reference) | AI generation | Use as color/shape reference only |
| Animated sprites | Aseprite (manual) | Use AI reference, hand-pixel the frames |
| Palette management | Lospec Palette List | Pick one 16–32 colour palette per biome |

**Required tool:** [Aseprite](https://www.aseprite.org/) (~$20). Non-negotiable for pixel art animation.

**Chopper animation breakdown (Mode 2):**
- 11 tilt frames (traced from Mode 1 as reference, redrawn at larger size)
- 5 head-on rotation frames
- 4-frame rotor spin cycle (main + tail, separately animated and composited)
- Total: ~20 unique frames, left-facing — engine mirrors for right-facing

### 6.4 Mode 3 — Hi-Res (Phase 2)

Godot 4's 3D renderer used for 2D gameplay — ambient lighting, SDFGI global illumination, screen-space effects. Sprites replaced with high-resolution painted art or pre-rendered 3D assets.

Asset pipeline:
- Environments: AI painterly generation at 1024×1024+, cleaned in Photoshop/GIMP
- Sprites: 3D models from Kenney.nl / Fab.com, pre-rendered to sprite sheets
- Lighting: Godot 4 `Light2D` nodes with normal maps

**Status:** Planned for v2.0. Do not start before Mode 2 is shipping.

### 6.5 Biomes (Mode 2 + 3)

Biomes are purely visual — same gameplay code, swappable `BiomeResource` containing sprite atlases, colour palettes, background scenes, and audio ambience. **Mode 1 has no biomes** — it uses the single original Apple II environment throughout.

Biome transitions are triggered by **rescue batch count** (not `CURR_LEVEL` directly), so they can progress smoothly across the extended 8-biome span independent of the 0–3 difficulty cap.

| Biome # | Biome | Trigger (rescue batches) | Sky / Ground | New Visual Elements |
|---|---|---|---|---|
| 0 | **Desert** | 0–1 | Orange dusk sky, sandy terrain | Mud-brick houses, palm trees |
| 1 | **Jungle** | 2–3 | Deep green canopy, foggy horizon | Bamboo huts, vines, mist particles |
| 2 | **Arctic** | 4–5 | Blue-white ice fields, aurora | Igloos, blizzard particle layer |
| 3 | **Tropical Island** | 6 | Turquoise water, coral reefs | Beach huts, volcanic mountains |
| 4 | **Alien World** *(final)* | 7 | Purple bio-luminescent landscape | Crystalline structures, glowing elements |

Each biome is primarily a **palette swap + background swap**. Hostage houses, mountains, and ground tiles are themed per biome. Enemy sprites keep their shapes but receive palette tints.

### 6.6 Render Layer Stack

**Mode 1 (faithful):** One mountain layer at exactly 50% scroll speed, matching the source (`renderMountains` does a single right-shift of `ZP_SCROLLPOS`).

**Mode 2 / Mode 3 (enhanced):** Two mountain layers plus a biome background layer.

```
z -4   Distant stars / sky gradient         (fixed, no scroll)
z -3   Far mountains           [Mode 2/3]   (parallax 30%)
z -2   Mountains               [Mode 1: 50% | Mode 2/3: 50%]
z -1   Biome background        [Mode 2/3 only]  (parallax 70%)
z  0   Ground plane, base, fence, houses
z  1–8 Tank depth planes (8 ground layers)  (z_index = depth_layer)
z  9   Hostages, bullets, shells
z 10   Chopper, jets, aliens
z 11   Explosions, particles
z 12   HUD overlay                          (separate CanvasLayer)
```

---

## 7. Physics & Movement

Faithful to the original values extracted from the reverse-engineer:

| Parameter | Original Value | Notes |
|---|---|---|
| Y acceleration model | `integrateAccelerationAccelYTable` (16-entry signed byte table) | See table below — do NOT use simple constant values |
| Gravity index (`ZP_ACCELY`) | 8 (index into table) → **−1 unit/frame** applied to velocity | Neutral stick / no thrust |
| Full thrust index (`ZP_ACCELY`) | 15 (index into table) → **+6 units/frame** applied to velocity | Full stick up |
| Turn animation frames | −5 to +5 (11 states) | Firing IS permitted during turns; bullet angle varies |
| Max player bullets | 5 on screen simultaneously | |
| One-hit kill | Yes | No health bar |

**Y acceleration table** (`integrateAccelerationAccelYTable`, source `choplifter.s:5266`):

| `ZP_ACCELY` index | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Accel (signed) | −10 | −9 | −8 | −7 | −6 | −5 | −4 | −3 | −2 | −1 | 0 | +1 | +2 | +3 | +4 | +6 |

> **Implementation warning:** The `zeropage.s` comment `$08 = Normal gravity, $0f = Full thrust up` describes the *index values* stored in `ZP_ACCELY`, not acceleration magnitudes. "$08" and "$0F" are table indices, not units/frame². Earlier versions of this doc transcribed them incorrectly as "8 units/frame²" and "15 units/frame²". Use the table above.

Physics will be implemented in `_physics_process()` using `CharacterBody2D`. For Mode 1, replicate the 16-bit fixed-point velocity integration verbatim (including the `>>8` velocity-to-position shift), then optionally refactor to float. Approximating directly in float risks losing the characteristic momentum feel.

**Turn state machine detail:**
- `turn_state` integer tracks −5 to +5 (11 states); 0 = facing camera, negative = left, positive = right
- `logical_face` is a separate boolean (left/right) that flips **instantly** on `face_*` input (`CHOP_FACE` source variable)
- Animation frame is driven by `turn_state`, not `logical_face`
- Player **can fire at any time** including during a turn (no turn-state-based fire lock)
- `turn_state` advances toward target at **variable speed**: 2 steps/frame when `|target − current| >= 2`, 1 step/frame when `|target − current| == 1`. A full −5 → +5 turn takes 5 frames.

**Bullet trajectory during turns** (`bulletGravityTable`, source `choplifter.s:7260`):

Bullets fire from the chopper front at an angle determined by `|turn_state|` (0 = fully sideways, 5 = fully toward camera). As the chopper turns toward camera, bullets arc downward:

| `|turn_state|` | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Bullet gravity (signed) | −2 | −2 | −1 | −1 | −1 | 0 |

`turn_state = 0` (fully sideways) = horizontal shot with slight upward trajectory. `turn_state = ±5` (fully camera-facing) = near-vertical downward drop. The `bulletVelocityTable` (`choplifter.s:4743`) maps turn state to the lateral velocity component.

**Landing physics (Mode 1 — source values):**
- `LAUNCHTHRESH`: minimum upward Y velocity required to leave the ground (become airborne)
- `MIN_VY`: maximum downward velocity for a safe landing; landing above this speed is treated as a crash
- `bounceThrustState`: thrust state applied on bounce (chopper pushed back up if landing velocity exceeds threshold)

These values must be extracted from `choplifter.s` and replicated exactly — they define the characteristic "floaty-but-precise" landing feel.

---

## 8. World & Rendering

- **Target resolution:** 480×270 (Mode 1 logical: 280×192 upscaled; Mode 2: native 480×270)
- **Scroll:** Horizontal only. Scroll position tracks a **lead offset ahead of the chopper** based on velocity direction — not a symmetric dead zone. The lead is asymmetric: `SCROLL_LEAD_L = $46` (70 px) when flying left, `SCROLL_LEAD_R = $D2` (210 px) when flying right — these are pixel values in the original 280×192 viewport. **Mode 1 mapping:** scale these proportionally to the Godot world-space coordinate system (e.g. if 1 Apple II pixel = N Godot units, multiply both lead values by N). The chopper appears roughly 25% from the left edge when flying left, further from the right edge when flying right. While grounded or flying backwards, the scroll clamps to a dead-band around the chopper position.
- **World width:** One continuous map per sortie. The original has **hard X bounds** (`BOUNDS_LEFT = $02D0`, `BOUNDS_RIGHT = $1300`) — the chopper's X velocity is zeroed and position is clamped at the edges. The world does **not** loop. The port should implement the same bounds rather than a wrap.
- **Parallax:** Mode 1: one mountain layer at ~50% (`renderMountains` computes `SCROLLPOS − (SCROLLPOS >> 1)` with `and #$FE` odd-pixel alignment mask). Mode 2/3: two layers at 30% and 50% plus a biome background layer.
- **Depth layers:** 8 distinct ground planes (z 1–8). Tanks occupy separate planes so they appear at different visual depths simultaneously.
- **Renderer:** Godot's built-in 2D renderer. `Stretch/Mode = canvas_items`, `Textures/Filter = Nearest` (pixel art).
- **Ground collision:** Flat ground at a fixed Y. Chopper lands when `position.y >= ground_y − chopper_height`. No terrain height variation (faithful to original).

---

## 9. Audio

### 9.1 Sound Effects

All significant actions have audio feedback. No duplicate sounds per frame (matches original behavior — `HOSTAGE_FIRSTLOAD` and `HOSTAGE_FIRSTDEATH` flags prevent this).

| Event | Sound Character |
|---|---|
| Chopper engine | Continuous low rotor hum, pitch shifts slightly with thrust |
| Fire bullet | Short sharp crack |
| Bullet impact / miss | Soft thud |
| Tank shell fire | Low boom |
| Jet missile fire | High whine |
| Explosion | Multi-layer crunch + rumble |
| Hostage boards | Short ascending beep |
| Hostage death | Descending tone |
| Landing (success) | Soft thud + settle |
| Alien present | Crackling electrical noise, pitch keyed to animation frame |
| Game over / victory | Simple fanfare |

**Source:** Original SFX are 1-bit Apple II speaker tones. For the port, use generated/synthesized SFX via **jsfxr** (web) or **Bfxr** (desktop) — these tools produce the correct retro character without requiring a sound designer.

### 9.2 Music

The original had **no music**. The port will add an optional **dynamic chiptune score**:

- **Calm layer:** Ambient melodic loop plays when no enemies are nearby
- **Tension layer:** Faster, more dissonant layer crossfades in as enemies approach or fire
- **Action layer:** Full percussion + lead melody when actively taking fire or rescuing hostages
- **Victory sting:** Short fanfare on rescue completion
- **Game over sting:** Descending phrase

Music is **off by default** in Mode 1 (Retro) to preserve authenticity. On by default in Mode 2+.

**Tooling:** Compose in **BeepBox** (free, browser-based, exports to JS/audio) or **FamiTracker** (NES-style chiptune). Export to OGG for Godot.

### 9.3 Settings

- Master volume (0–100)
- SFX volume (0–100)
- Music volume (0–100)
- Music on/off toggle
- All saved to `user://settings.cfg`

---

## 10. HUD & UI

### 10.1 In-Game HUD

Faithful to the original layout: counters along the top of the screen inside a bordered panel.

| Counter | Label | Source Variable |
|---|---|---|
| Rescued | `RESCUED` | `TOTAL_RESCUES_BCD` |
| Killed | `KILLED` | `HOSTAGES_KILLED_BCD` |
| On board | `ABOARD` | `HOSTAGES_LOADED_BCD` |

**Visual:** HUD sits in a fixed `CanvasLayer` above the game world, not affected by camera scroll. In Mode 1, uses extracted original digit sprites (6×7px each). In Mode 2+, redesigned with larger legible numerals.

**Lives display:** 3 helicopter icons, one greyed-out per sortie lost. Located in HUD corner.

### 10.2 Touch HUD Repositioning

On touchscreen, the HUD shifts to avoid overlap with virtual controls:
- Counters move to top-center
- Lives icons move to top-left
- Virtual controls occupy bottom 35% of screen

### 10.3 Pause Screen

- Overlay darkens the game world
- Shows: Resume, Restart Sortie, Quit to Title, Settings
- Settings accessible during pause (volume, controls, visual mode)

### 10.4 Retro Title Sequence

Plays only when launching **Retro mode** from the Main Menu (`RetroTitle.tscn`). Not shown in Modern or Hi-Res modes.

1. "Broderbund Presents" animation
2. Choplifter logo slides in from both sides (crossed, then separated)
3. "Your Mission: Rescue Hostages" card
4. Demo mode auto-play (attract loop — any input interrupts and returns to Main Menu)
5. Press any button → First Sortie banner

The Main Menu is the universal entry point; this sequence is Retro-mode flavour, not a gate.

---

## 11. Game States & Flow

### 11.1 Architecture Overview

The **Main Menu is the permanent hub.** Every exit path from gameplay — death, victory, quit — returns here. The menu is always rendered in modern hi-res style regardless of which game mode is active or selected.

The Apple II faithful title sequence (Broderbund card, logo animation, demo attract) belongs *to Retro mode* and plays only when that mode is launched, not at the meta level.

```
BOOT
  └─▶ [boot logo splash ~2 s]
        └─▶ MAIN_MENU  ◀────────────────────────────────────────────┐
              │                                                      │
              ├─▶ [Play → Retro Mode]                               │
              │     └─▶ RETRO_TITLE_SEQUENCE                        │
              │           ├─▶ (button) ──▶ SORTIE_BANNER            │
              │           └─▶ (attract) ─▶ DEMO_MODE ──▶ ──────────┤
              │                                                      │
              ├─▶ [Play → Modern Pixel Art]                         │
              │     └─▶ SORTIE_BANNER ──▶ GAMEPLAY                  │
              │                                                      │
              ├─▶ [Play → Hi-Res]                                   │
              │     └─▶ SORTIE_BANNER ──▶ GAMEPLAY                  │
              │                                                      │
              └─▶ [Settings] (modal panel, no scene swap)           │
                                                                     │
SORT IE_BANNER                                                       │
  └─▶ GAMEPLAY                                                       │
        ├─▶ (64 rescued) ──▶ VICTORY_SEQUENCE ──▶ ──────────────────┤
        ├─▶ (64 killed)  ──▶ LOSS_SEQUENCE    ──▶ ──────────────────┤
        ├─▶ (pause → quit) ─────────────────── ──▶ ─────────────────┤
        └─▶ (chopper dies)                                          │
              ├─▶ (sorties remain) ──▶ SORTIE_BANNER                │
              └─▶ (sorties = 0)   ──▶ LOSS_SEQUENCE ──▶ ───────────┘

GAMEPLAY (any time)
  └─▶ (pause input) ──▶ PAUSED ──▶ (resume)        ──▶ GAMEPLAY
                              └─▶ (quit to menu)   ──▶ MAIN_MENU
                              └─▶ (restart sortie) ──▶ SORTIE_BANNER
```

### 11.2 Persistent Autoloads

Four autoloads are never unloaded:

| Autoload | Role |
|---|---|
| `GameState.gd` | State enum, sortie #, lives remaining, hostage counts, selected visual mode |
| `Settings.gd` | Loads `user://settings.cfg` at boot; saves on any change |
| `AudioManager.gd` | Owns `AudioStreamPlayer` nodes for music + SFX; persists across scene swaps |
| `SceneTransition.gd` | Full-screen black `ColorRect` at z=100; exposes `async transition_to(path)` (fade-out → swap → fade-in, ~0.3 s) |

### 11.3 Main Menu

**Visual style:** Always modern and hi-res regardless of selected game mode. The menu runs at the native display resolution using Godot `Control` nodes — these are unaffected by the pixel-art `Stretch` and `Nearest` filter settings applied to the game world.

**Background:** A `SubViewport` renders a slow-scrolling animated game world preview (a biome appropriate to the selected mode, e.g. desert at dusk). The live world plays silently in the background at low speed with no entities. The menu UI panels overlay it with translucent dark backing.

**Layout (vertical navigation card):**
```
┌──────────────────────────────────────────────────────┐
│  [background: live animated world preview]            │
│                                                       │
│    CHOPLIFTER                  [logo, modern type]    │
│                                                       │
│    ┌─────────────────────────────────────────────┐   │
│    │  ▶  PLAY  [Retro / Modern / Hi-Res toggle]  │   │
│    ├─────────────────────────────────────────────┤   │
│    │     SETTINGS                                │   │
│    ├─────────────────────────────────────────────┤   │
│    │     CREDITS                                 │   │
│    ├─────────────────────────────────────────────┤   │
│    │     QUIT  (desktop only; hidden on web)     │   │
│    └─────────────────────────────────────────────┘   │
│                                                       │
│    Mode: [◀ Retro ▶]  [◀ Modern ▶]  [◀ Hi-Res ▶]    │
└──────────────────────────────────────────────────────┘
```

- **Mode selector** is persistent across sessions (saved to `settings.cfg`).
- **Play** launches the selected mode directly — no secondary mode-selection screen.
- **Settings** slides in as a panel from the right without leaving the scene.
- **Credits** is a scrolling overlay panel. No scene swap.
- **Quit** uses `get_tree().quit()`. Hidden on web export (Godot detects this via `OS.get_name()`).

**Navigation:** Keyboard (`↑↓ Enter`), controller (D-pad / left stick + A/Cross), mouse hover + click. Touch: tap targets minimum 48 dp.

### 11.4 Scene Ownership

| State | Scene | Notes |
|---|---|---|
| Boot | `Boot.tscn` | 1–2 frame scene. Loads `Settings.gd`, shows boot logo, transitions to `MainMenu.tscn` |
| Main Menu | `MainMenu.tscn` | Hub. Always modern/hi-res. Contains animated bg `SubViewport`, UI panels, mode selector |
| Retro title sequence | `RetroTitle.tscn` | Only played in Retro mode. Broderbund card → logo → mission card → attract demo. Any input skips to `SortieBanner.tscn` |
| Sortie Banner | `SortieBanner.tscn` | Fullscreen interstitial (~2 s, auto-advances). Shared across all modes |
| Gameplay | `World.tscn` | All gameplay. `HUD.tscn` is a `CanvasLayer` child. Victory/loss sequences play as states here |
| Pause | — | Not a scene. `SceneTree.paused = true` + `PauseMenu` node shown/hidden inside `World.tscn` |
| Settings | — | Not a scene. Slide-in panel within `MainMenu.tscn` and sub-panel within `PauseMenu` |

### 11.5 Loading & Transitions

No dedicated loading screen. Godot's built-in boot splash (black bg + logo) shows during the initial engine start. `SceneTransition.gd` fades handle every subsequent transition.

For web export, the browser renders a Godot progress bar before handing off to `Boot.tscn`. The boot splash image matches the game logo on black.

### 11.6 Pause Implementation

`SceneTree.paused = true` freezes all nodes with default `process_mode`. Nodes set to `ALWAYS`:

- `PauseMenu` and children — receives input, renders overlay
- `AudioManager.gd` — music continues uninterrupted
- `HUD.tscn` — stays visible behind the overlay

Pause menu options: **Resume** · **Restart Sortie** · **Quit to Menu** · **Settings**.

"Quit to Menu" sets `GameState.input_locked = true`, unpauses the tree, then calls `SceneTransition.transition_to("MainMenu.tscn")`.

### 11.7 Demo Mode (Retro Only)

The original ROM's `startDemoMode` replayed a hardcoded control table. The port stores this as a `Resource` array of `{action, duration_frames}` at `res://data/demo_input.tres`. When `GameState.demo_mode == true`, `Chopper.gd` reads from this table instead of real input. Any real input during demo mode triggers an immediate transition to `MainMenu.tscn`.

Demo mode is only reachable from `RetroTitle.tscn` (attract timer). Modern and Hi-Res modes do not have a demo/attract loop.

### 11.8 Victory & Loss Sequences

Both play inside `World.tscn` with the world still visible:

- **Victory:** Remaining hostages spawn waving, victory fanfare plays, "Mission Accomplished" overlay shown ~3 s, then `transition_to("MainMenu.tscn")`
- **Loss — all killed:** Loss sting plays, "Mission Failed" overlay ~2 s, then `transition_to("MainMenu.tscn")`
- **Loss — sorties exhausted:** Game-over card ~2 s, then `transition_to("MainMenu.tscn")`
- **Chopper death, sorties remain:** Explosion plays to completion, black hold ~1 s, `transition_to("SortieBanner.tscn")`

All end states set `GameState.input_locked = true` at onset.

---

## 12. Settings & Save

### 12.1 Settings (persisted to `user://settings.cfg`)

| Setting | Type | Default |
|---|---|---|
| Visual mode | Enum (1/2/3) | 1 (Retro) |
| Master volume | 0–100 | 80 |
| SFX volume | 0–100 | 100 |
| Music volume | 0–100 | 70 |
| Music enabled | Bool | false (Mode 1), true (Mode 2+) |
| Joystick X invert | Bool | false |
| Joystick Y invert | Bool | false |
| Input bindings | Dict | Defaults from Section 5 |

### 12.2 No Save File

The original game has no persistent save — each boot starts fresh. The port matches this. Settings are persisted; game progress is not.

### 12.3 Input Rebinding

Keyboard and controller bindings are remappable via an in-game key-capture UI (standard Godot `InputMap` pattern). Touch layout is not remappable but is auto-detected.

---

## 13. Project Structure (Godot)

```
choplifter-clone/
├── src/
│   ├── project.godot
│   ├── autoload/
│   │   ├── GameState.gd         ← State enum, sortie #, lives, hostage counts, visual mode
│   │   ├── Settings.gd          ← Load/save user://settings.cfg
│   │   ├── AudioManager.gd      ← Music + SFX players; duplicate-per-frame guard
│   │   └── SceneTransition.gd   ← Fade-black ColorRect z=100; transition_to(path)
│   ├── scenes/
│   │   ├── Boot.tscn            ← 1-frame init: load settings → transition to MainMenu
│   │   ├── MainMenu.tscn        ← Hub; always hi-res/modern; animated bg SubViewport
│   │   ├── RetroTitle.tscn      ← Retro-mode only: Broderbund → logo → demo attract
│   │   ├── SortieBanner.tscn    ← Shared interstitial (all modes)
│   │   ├── World.tscn           ← All gameplay; HUD CanvasLayer child
│   │   ├── HUD.tscn             ← CanvasLayer; process_mode=ALWAYS
│   │   └── PauseMenu.tscn       ← Overlay inside World; process_mode=ALWAYS
│   ├── entities/
│   │   ├── Chopper.tscn / Chopper.gd
│   │   ├── Tank.tscn / Tank.gd
│   │   ├── Jet.tscn / Jet.gd
│   │   ├── Alien.tscn / Alien.gd
│   │   ├── Hostage.tscn / Hostage.gd
│   │   ├── Bullet.tscn / Bullet.gd
│   │   ├── Shell.tscn / Shell.gd
│   │   ├── Missile.tscn / Missile.gd
│   │   ├── Bomb.tscn / Bomb.gd
│   │   └── Explosion.tscn / Explosion.gd
│   ├── world/
│   │   ├── Terrain.gd           ← Ground plane + depth layer management
│   │   ├── Base.tscn / Base.gd
│   │   ├── House.tscn / House.gd
│   │   ├── FenceTower.tscn
│   │   └── SpawnManager.gd      ← Enemy + hostage spawn timing tables
│   ├── ui/
│   │   ├── HUD.gd
│   │   ├── MenuPanel.tscn       ← Reusable translucent panel for menu cards
│   │   ├── SettingsPanel.tscn   ← Slide-in settings (used in MainMenu + PauseMenu)
│   │   ├── VirtualJoystick.tscn / VirtualJoystick.gd
│   │   └── TouchButtons.tscn
│   └── data/
│       └── demo_input.tres      ← Retro attract demo control table (Resource array)
├── assets/
│   ├── graphics/
│   │   ├── original-sprites/    ← Extracted Apple II sprites (Mode 1)
│   │   ├── mode2/               ← Modern pixel art (Mode 2, added during art phase)
│   │   ├── menu/                ← Hi-res menu assets (logo, backgrounds, icons)
│   │   └── ui/
│   ├── audio/
│   │   ├── sfx/
│   │   └── music/
│   └── fonts/                   ← Modern typeface(s) for main menu + Mode 2+ HUD
├── docs/
└── src/tools/                   ← Python pipeline tools (not shipped)
```

---

## 14. Release Roadmap

| Version | Goal | Key Features |
|---|---|---|
| **v0.1** | Playable core, Retro mode | Chopper physics, scrolling world, hostages, tanks, Mode 1 sprites |
| **v0.2** | Full game, Retro mode | Jets, aliens, difficulty scaling, sorties, win/lose, title screen |
| **v0.3** | Modern mode, Desert biome | Mode 2 pixel art, Desert biome, remastered SFX, chiptune music |
| **v0.4** | Biomes 2–3 | Jungle + Arctic biomes, dynamic music system |
| **v0.5** | Biomes 4–5 | Tropical Island + Alien World biomes |
| **v1.0** | Release | Polish pass, web export to itch.io, controller rumble, all platforms |
| **v2.0** | Hi-Res mode | Mode 3 visual overhaul (scope TBD after v1.0 ships) |

**Web export:** Primary release target alongside desktop. Published to **itch.io** (main distribution) and **GitHub Pages** (dev/preview builds).

**Controller haptics:** Light rumble on landing; strong pulse on death/explosion; gentle buzz on hostage boarding. Implemented via Godot's `Input.start_joy_vibration()`. Off by default, toggleable in settings.

---

## 15. Resolved Design Decisions

All previously open questions are now settled:

| Question | Decision |
|---|---|
| Art style | Three-tier mode system (Retro / Modern Pixel Art / Hi-Res) |
| Target resolution | 480×270 (Mode 2+); 280×192 logical upscaled (Mode 1) |
| `face_camera` on touch | Dedicated center button between `face_left` / `face_right`; more discoverable than stick-down |
| Music | Dynamic chiptune, 3 intensity layers; off by default in Mode 1, on in Mode 2+ |
| Web export destination | itch.io (primary) + GitHub Pages (dev previews) |
| Controller rumble | Yes — landing, death, explosion, hostage board; off by default in settings |
| Alien behavior | Fully documented in Section 4 (hover + chase AI, fires at level 3+) |
| Biome progression | Desert → Jungle → Arctic → Tropical Island → Alien World (levels 0–7) |
| Save system | Settings persist; game progress does not (faithful to original) |
| Meta-menu architecture | Permanent hi-res Main Menu hub; all exits return here. Apple II title sequence is Retro-mode-only. Menu uses native resolution Control nodes; game world runs in SubViewport |
| Title sequence ownership | Retro mode only (`RetroTitle.tscn`). Modern and Hi-Res modes launch directly to `SortieBanner.tscn` |
