# Choplifter Clone — Design Document

> **Engine:** Godot 4 · **Language:** GDScript · **Genre:** Side-scrolling rescue action  
> **Reference:** [blondie7575/ChoplifterReverse](https://github.com/blondie7575/ChoplifterReverse) — full annotated 6502 disassembly of the 1982 original  
> See also: [REVERSE_ENGINEER_ANALYSIS.md](REVERSE_ENGINEER_ANALYSIS.md)

---

## 1. Game Overview

A faithful-but-modernized reimplementation of Dan Gorlin's *Choplifter* (1982, Broderbund). The goal is to preserve the original's feel and mechanics while taking advantage of modern hardware for visuals, audio, and cross-platform reach.

**Guiding principle:** Every mechanical decision should ask "does this feel like Choplifter?" before "does this feel modern?". Where those conflict, Choplifter wins.

---

## 2. Core Loop

1. Take off from the base
2. Fly left across side-scrolling terrain under enemy fire
3. Land near hostage buildings; hostages run out and board automatically
4. Return rescued hostages to base; they disembark on landing
5. Difficulty increases after each successful rescue run
6. Repeat until all 64 hostages are rescued (win) or 64 are killed / 3 lives exhausted (loss)

---

## 3. Win / Lose Conditions

Faithful to the original — **no score**.

| Condition | Trigger |
|---|---|
| **Victory** | 64 total hostages rescued |
| **Loss — hostages** | 64 hostages killed |
| **Loss — lives** | 3 sorties (lives) used up |

The counters displayed to the player:
- Rescued (total)
- Killed (total)
- On board (current sortie)

---

## 4. Enemies

| Enemy | Levels | Behavior |
|---|---|---|
| **Tank** | 0+ | Rolls on ground planes at varying depths; aims cannon at chopper; fires ballistic shells |
| **Jet** | 1+ | Flies at altitude; fires forward missiles and drops bombs; can attack from behind on higher levels |
| **Alien** | 2+ | UFO saucer that actively hunts the player; accelerates toward chopper on both axes (max VX ±5, max VY ±1); plays crackling audio keyed to animation frame; fires tank-shell-type projectiles downward at level 3+ (random spread, only at lower altitudes); despawns if player gets too far away on X; collides with and destroys the chopper on contact |

Max simultaneous: 4 tanks, 4 jets, 4 aliens.

**Alien animation detail:** Saucer has two composited layers — a static body and a sliding mid-section that cycles through 3 frames. The mid-section position jitters by 1px on odd frames, creating a flickering energy-ring effect. The `ENTITY_DIR` field is reused as the mid-section animation frame counter (0–2) rather than direction.

**Houses** can be set on fire by enemy action, killing hostages inside.

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

> **Note:** `face_*` actions lock firing input during the turn animation, matching original behavior. The chopper's logical facing and its animation state are tracked separately.

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

Biomes are purely visual — same gameplay code, swappable `BiomeResource` containing sprite atlases, colour palettes, background scenes, and audio ambience.

| Difficulty Level | Biome | Sky / Ground | New Visual Elements |
|---|---|---|---|
| 0–1 | **Desert** | Orange dusk sky, sandy terrain | Mud-brick houses, palm trees |
| 2–3 | **Jungle** | Deep green canopy, foggy horizon | Bamboo huts, vines, mist particles |
| 4–5 | **Arctic** | Blue-white ice fields, aurora | Igloos, blizzard particle layer |
| 6 | **Tropical Island** | Turquoise water, coral reefs | Beach huts, volcanic mountains |
| 7 | **Alien World** *(final)* | Purple bio-luminescent landscape | Crystalline structures, glowing elements |

Each biome is primarily a **palette swap + background swap**. Hostage houses, mountains, and ground tiles are themed per biome. Enemy sprites keep their shapes but receive palette tints.

### 6.6 Render Layer Stack

```
z -4   Distant stars / sky gradient         (fixed, no scroll)
z -3   Far mountains                        (parallax 30%)
z -2   Mid mountains                        (parallax 50%)
z -1   Biome background elements            (parallax 70%)
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
| Gravity (Y accel) | 8 units/frame² | Always pulling chopper down |
| Max thrust (Y accel) | 15 units/frame² | Full stick up |
| Turn animation frames | −5 to +5 (11 frames) | Cannot fire during turn |
| Max player bullets | 5 on screen simultaneously | |
| One-hit kill | Yes | No health bar |

Physics will be implemented in `_physics_process()` using `CharacterBody2D`. The 16-bit fixed-point velocity model from the original will be replicated as floating-point in Godot (equivalent behavior, easier to work with).

**Turn state machine detail:**
- `turn_state` integer tracks −5 to +5 (11 states); 0 = facing camera, negative = left, positive = right
- `logical_face` is a separate boolean (left/right) that flips instantly on `face_*` input
- Animation frame is driven by `turn_state`, not `logical_face`
- Player cannot fire while `|turn_state| > 0` (turning in progress)
- `turn_state` increments/decrements one step per frame toward the target state

---

## 8. World & Rendering

- **Target resolution:** 480×270 (Mode 1 logical: 280×192 upscaled; Mode 2: native 480×270)
- **Scroll:** Horizontal only. `Camera2D` follows chopper X. Chopper is not locked to screen center — it drifts toward edges within a dead zone.
- **World width:** One continuous map per sortie, approximately 3–4 screens wide. The original had a single scrolling level that looped.
- **Parallax:** `ParallaxBackground` with two mountain layers (30% and 50% scroll speed).
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

### 10.4 Title Screen

Faithful to original sequence:
1. "Broderbund Presents" animation
2. Choplifter logo slides in from both sides (crossed, then separated)
3. "Your Mission: Rescue Hostages" card
4. Demo mode auto-play (attracts new players)
5. Press any button → start game

---

## 11. Game States & Flow

```
BOOT
  └─▶ TITLE_SEQUENCE
        ├─▶ (button press) ──▶ NEW_GAME
        └─▶ (timer) ─────────▶ DEMO_MODE ──▶ TITLE_SEQUENCE

NEW_GAME
  └─▶ SORTIE_BANNER  ("First Sortie" / "Second Sortie" / "Third Sortie")
        └─▶ GAMEPLAY
              ├─▶ (64 rescued) ──▶ VICTORY_SEQUENCE ──▶ TITLE_SEQUENCE
              ├─▶ (64 killed)  ──▶ LOSS_SEQUENCE    ──▶ TITLE_SEQUENCE
              └─▶ (chopper dies)
                    ├─▶ (sorties remain) ──▶ SORTIE_BANNER
                    └─▶ (sorties = 0)   ──▶ LOSS_SEQUENCE ──▶ TITLE_SEQUENCE
```

**Implemented as a Godot `SceneTree` scene-swap or `GameState` autoload singleton** managing the current state enum. Each major state is its own scene or a state within `World.tscn`.

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
│   │   ├── GameState.gd       ← Global state: sortie, level, hostage counts, current mode
│   │   ├── Settings.gd        ← Load/save settings.cfg
│   │   └── AudioManager.gd    ← Plays SFX/music; prevents duplicate-per-frame sounds
│   ├── scenes/
│   │   ├── World.tscn         ← Main gameplay scene (camera, terrain, spawn manager)
│   │   ├── TitleScreen.tscn
│   │   ├── SortieBanner.tscn
│   │   ├── HUD.tscn           ← CanvasLayer, always on top
│   │   └── PauseMenu.tscn
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
│   │   ├── Terrain.gd         ← Ground plane + depth layer management
│   │   ├── Base.tscn / Base.gd
│   │   ├── House.tscn / House.gd
│   │   ├── FenceTower.tscn
│   │   └── SpawnManager.gd    ← Enemy + hostage spawn timing and tables
│   ├── ui/
│   │   ├── HUD.gd
│   │   ├── VirtualJoystick.tscn / VirtualJoystick.gd
│   │   └── TouchButtons.tscn
│   └── tools/                 ← Editor/pipeline scripts, not shipped
│       └── (sprite extractor etc.)
├── assets/
│   ├── graphics/
│   │   ├── original-sprites/  ← Extracted Apple II sprites (Mode 1)
│   │   ├── mode2/             ← Modern pixel art (Mode 2, added during art phase)
│   │   └── ui/
│   ├── audio/
│   │   ├── sfx/
│   │   └── music/
│   └── fonts/
├── docs/
└── src/tools/                 ← Python pipeline tools
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
