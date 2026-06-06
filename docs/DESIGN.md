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
| **Alien** | 2+ | Jitters; exact behavior TBD (original source unclear) |

Max simultaneous: 4 tanks, 4 jets, 4 aliens.

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
- `face_camera` triggered by pushing stick fully down, or by a dedicated button (TBD based on playtesting)
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

For Mode 1, extracted sprites are tinted orange (the dominant Choplifter sprite colour) over a black background. No art work required — this mode is fully playable with extracted assets.

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
| 6 | **Alien World** | Purple bio-luminescent landscape | Crystalline structures, glowing elements |
| 7 | **Tropical Island** *(bonus)* | Turquoise water, coral reefs | Beach huts, volcanic mountains |

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

---

## 7. World & Rendering

- **Scroll:** Horizontal only. Camera follows chopper X position. Chopper is not locked to screen center — it can drift toward edges.
- **Parallax:** Background mountains scroll at ~50% of world scroll speed (built-in `ParallaxBackground`).
- **Depth layers:** Tanks exist on up to 8 distinct ground planes, creating pseudo-3D depth. Each plane has a slightly different Y position and `z_index`.
- **Renderer:** Godot's built-in 2D renderer. No custom blitter needed.
- **Target resolution:** TBD. Likely 480×270 (pixel art, 1:1 pixels at 1080p/4x) or 640×360. The original was 280×192.

---

## 8. Audio

- **Sound effects:** All actions have audio feedback (fire, explosion, hostage board/death, landing, engine hum). No duplicate sounds per frame (matches original behavior).
- **Music:** TBD — the original had no music. Options: silence (faithful), ambient chiptune loop, or dynamic music that reacts to enemy proximity.
- **Sound preference:** On/off toggle, saved to settings.

---

## 9. Open Questions

- [ ] Art style decision: pixel art retro vs. clean modern vector vs. hand-drawn
- [ ] Target resolution / pixel size
- [ ] `face_camera` on touch: stick-down or dedicated button?
- [ ] Music: yes/no, and if yes, what style?
- [ ] Web export: itch.io? GitHub Pages?
- [ ] Controller rumble on death/explosion?
- [ ] Alien behavior — needs more research into the original source
