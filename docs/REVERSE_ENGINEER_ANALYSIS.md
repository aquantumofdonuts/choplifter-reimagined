# Choplifter Reverse-Engineer Analysis & Porting Strategy

Source: [blondie7575/ChoplifterReverse](https://github.com/blondie7575/ChoplifterReverse)  
Full write-up by Quinn Dunki: https://blondihacks.com/reversing-choplifter

> **Authority note:** This document is an exploratory analysis. Where any value here conflicts with [DESIGN.md](DESIGN.md), **DESIGN.md is authoritative** — it carries the source-verified constants. An early version of this analysis inherited several misreadings of `zeropage.s` comments (treating table *indices* as magnitudes) and of in-source comments (spawn cadences). Those values have been corrected in place below; the corrections are flagged where they occur.

---

## 1. What the Source Code Is

This is a **complete, fully-commented reverse-engineer** of the original 1982 Apple II 6502 binary, done clean-room by Quinn Dunki. The assembled output is binary-identical to the original game (except for the floppy loader, which was replaced with a ProDOS version).

- `choplifter.s` — 11,703 lines, all game logic
- `zeropage.s` — 197 lines, all zero-page variable allocations (the Apple II's "fast registers")
- `loader.s` — 230 lines, ProDOS boot loader replacement

The comments are excellent and explain *why* code works, not just what it does. This is a high-quality source for a port.

---

## 2. Game Systems Inventory

### 2.1 Rendering Pipeline

The Apple II HGR (Hi-Res Graphics) system is 280×192 pixels, 6 colors, with a bizarre bit-packing scheme. The entire renderer is a **custom software blitter** written in hand-optimized 6502.

Key rendering subsystems:

| System | Description |
|---|---|
| Double buffering | Alternates between `$2000` and `$4000` HGR pages each frame |
| Sprite blitter | Pixel-level rendering with masking; separate left-facing/right-facing routines |
| Tilted sprites | Dedicated routines for diagonal sprite rendering (chopper logo animation) |
| Parallax mountains | Scroll at 50% of world speed for depth illusion |
| Clipping | Full left/right/top/bottom clipping with sub-byte precision |
| Screen erase | Sprites are erased by overwriting sky or ground fill color before redraw |

**Modern translation:** All of this becomes trivial in any modern engine. Double buffering, sprite flipping, parallax layers — all built-in.

### 2.2 Entity System

A **fixed-size intrusive linked list** of up to 30 entities, sorted by `ENTITY_GROUND` (depth) for painter's-algorithm rendering.

Each entity record is **10 bytes**:

| Field | Size | Description |
|---|---|---|
| ID | 1B | Entity identifier (`$0A` is always the chopper) |
| TYPE | 1B | 0=chopper, 1=crashing, 2=sinking, 3=tank, 4=missile, 5=bomb, 6=bullet, 8=tank shell, 9=jet, 10=alien |
| VX | 1B | X velocity (signed) |
| VY | 1B | Y velocity (signed) |
| DIR | 1B | Direction/gravity/aim (interpreted per type) |
| X_L/X_H | 2B | 16-bit screen-space X position |
| Y | 1B | Screen-space Y position |
| GROUND | 1B | Depth layer (ground plane, used for painter's sort) |
| NEXT | 1B | Linked-list next pointer |

Separate tables track active IDs per type: `tankTable[4]`, `jetTable[4]`, `alienTable[4]`. Entity update is dispatched through a function pointer table.

### 2.3 Helicopter Physics

The most sophisticated system in the game. All physics state lives in zero-page for single-cycle access.

```
ZP_VELX_16_L/H     16-bit signed X velocity (positive = right)
ZP_VELY_16_L/H     16-bit signed Y velocity (positive = up)
ZP_ACCELX          Current X acceleration from stick input
ZP_ACCELY          Current Y acceleration ($08=gravity, $0f=full thrust)
ZP_TURN_STATE      Animation frame for chopper rotation (-5 to +5)
ZP_AIRBORNE        $01 if airborne
ZP_LANDED          $01 if fully settled on ground
ZP_LANDED_BASE     $01 if on the home base pad
ZP_DYING           $01 during death animation
ZP_DEATHTIMER      Death animation counter (counts to $FF)
```

**Physics model:**
1. Stick input updates `ZP_ACCELX` and `ZP_ACCELY`
2. Acceleration is applied to 16-bit velocity each frame
3. Velocity is applied to position
4. Ground collision sets Y velocity to zero and sets `ZP_LANDED`
5. `ZP_TURN_STATE` is a separate animation counter (-5 to +5) that animates the chopper's rotation independently from the physics facing direction

**Turn animation:** When you change direction, the chopper animates through a rotation sequence before the physics direction flips. This is the iconic "turning in place" animation. `CHOP_FACE` (logical direction) vs `ZP_TURN_STATE` (animation state) are separate.

### 2.4 Scrolling

- 16-bit horizontal scroll position (`ZP_SCROLLPOS_L/H`)
- World scrolls based on chopper X velocity — the helicopter is roughly centered
- Mountains parallax at ~50% of world scroll speed
- No vertical scrolling (commented-out code suggests it was attempted but cut)
- Scroll window has configurable top/bottom bounds (never actually used)

### 2.5 Hostage System

```
MAX_HOSTAGES = 16 (always)
4 houses, 4 per house initially

Per-hostage state (4 bytes):
  [0] Animation frame ($FF = unallocated)
  [1] Action: $00=waving, $FF=run left, $01=run right, $FE=loading right, $02=loading left
  [2] X position (low byte, 16-bit)
  [3] X position (high byte)

House states: $00=untouched, $01=on fire
```

**Hostage state machine:**
1. Inside house → waving (idle)
2. Chopper lands nearby → run toward chopper
3. Reach chopper → loading animation → board
4. Chopper returns to base and lands → run to base door
5. Base door reached → rescue counted

Victory: `TOTAL_RESCUES == 64` (all 64 hostages across all rounds)  
Loss: `TOTAL_RESCUES + HOSTAGES_KILLED == 64` (with the win check running first) OR sorties exhausted. With exactly 64 hostages total, this means the game ends when the last hostage is accounted for — any kill that completes the count of 64 ends the game without a win. (`choplifter.s:599–608`. Corrected: earlier text said `HOSTAGES_KILLED == 64`.)

### 2.6 Enemy Spawning & Difficulty

```
SORTIE   0–2    Lives remaining (3 lives total)
CURR_LEVEL  0–3    Difficulty in Mode 1, capped at 3 by source (`cmp #$03 / beq`); incremented after each rescue batch. (Mode 2/3 extend the cap to 7.)
```

**Spawn schedule:** Enemy vehicle spawn attempt when `FRAME_COUNT AND $2F == 0` (`choplifter.s:4578`) — a bitmask, producing a non-uniform 16/48-frame alternating cadence, **not** a fixed 47-frame period. Hostage emergence attempt when `FRAME_COUNT AND $03 == 0` (`choplifter.s:4572`) — every **4** frames. (Corrected: earlier text said "every 47 frames" and "every 3 frames," inherited from incorrect in-source comments.)

| Level | Tanks | Jets | Aliens |
|---|---|---|---|
| 0 | 1 max | 0 | 0 |
| 1 | 2 max | 1 max | 0 |
| 2 | 2 max | 2 max | 1 max |
| 3+ | 2 max | 2 max | 2 max |

**Tank behavior:** Random depth plane, fire shells ballistically toward player. Cannon aims based on player position.

**Jet behavior:** Spawn above player, at altitude based on chopper height. Higher levels spawn from behind the player. Fire missiles (forward) and bombs (drop). X-velocity tables map jet bank angle to velocity components.

**Alien behavior:** Appear at level 2+, jitter every other frame.

### 2.7 Projectiles

| Type | Physics | Notes |
|---|---|---|
| Player bullet | `updateBasicPhysics` (simple) | 5 max on screen |
| Tank shell | `updateBasicPhysics` + gravity arc | Ballistic |
| Jet missile | Forward velocity, level flight | Horizontal |
| Jet bomb | Gravity drop | Falls |

### 2.8 Sound

Single-bit Apple II speaker — toggled at specific frequencies to generate tones. No music. Sound effects: shell fire, hostage events, death. There is a sound-on/off preference (`PREFS_SOUND`).

### 2.9 No Score System

**Choplifter has no score.** There are no points. The counters are purely:
- Rescued hostages (win at 64)
- Killed hostages (lose at 64)
- Loaded hostages (on board right now)
- Sorties / lives remaining

---

## 3. Recommended Modern Stack

### 3.1 Engine: Godot 4

**Godot 4 is the best fit for this project.** Here's why each original system maps cleanly:

| Original System | Godot 4 Equivalent |
|---|---|
| Entity linked list | `Node` scene tree; one scene per entity type |
| Entity type dispatch | `virtual func _physics_process()` per node class |
| 16-bit X velocity physics | Replicate in `CharacterBody2D._physics_process()` |
| Double-buffered HGR | Handled automatically by Godot's renderer |
| Sprite left/right flip | `AnimatedSprite2D.flip_h` |
| Turn state animation | `AnimationPlayer` or `AnimatedSprite2D` with animation states |
| Painter's sort by depth | `z_index` on nodes, or `CanvasLayer` ordering |
| Parallax mountains | `ParallaxBackground` + `ParallaxLayer` (built-in) |
| Scroll position | `Camera2D` with limits, or manual scroll via `position` |
| Clipping at screen edges | Godot's viewport handles this |
| 1-bit speaker sound | `AudioStreamPlayer` + generated/sampled SFX |

**Language:** GDScript (Python-like, fast to write) or C# (if you want static typing + IDE support). GDScript is recommended for a project of this scope.

**Why not other engines:**
- **Unity:** Overkill, licensing concerns, heavy for a 2D arcade game
- **Pygame:** Fine but lacks built-in scene management, animation, and physics; you'd rebuild a lot of what Godot provides
- **Phaser:** Good choice if browser-first is a goal, but Godot exports to web too
- **Bevy:** ECS is a perfect conceptual match for the entity system, but Rust's learning curve and boilerplate cost is high
- **raylib/C:** Would be a direct spiritual translation, but you'd hand-build everything Godot provides for free

---

## 4. Porting Strategy

### 4.1 Approach: Faithful Reimplementation

Do **not** attempt a line-by-line translation of the assembly. Instead, use the reverse-engineer as a **specification** — the comments tell you exactly what each system does; implement those behaviors in idiomatic GDScript.

The original game's core loop is simple:

```
each frame:
  check input
  erase sprites
  render background (stars, moon, mountains, base, fence, houses)
  update hostages
  spawn enemies
  update all entities
  defragment entity list
  flip buffers
```

### 4.2 Implementation Order

Recommended build sequence (each step is playable before moving to the next):

1. **Chopper physics** — Get the helicopter feeling right first. Implement the 16-bit velocity model, gravity, thrust, and the turn animation state machine. This is the core feel of the game.

2. **Scrolling world** — Camera follows chopper X position. Static ground plane. Mountains with parallax.

3. **Base + landing** — Render the base, implement landing detection, landed/airborne state.

4. **Hostages** — Spawn 16 hostages in 4 houses. Implement the state machine (wave → run → board → rescue).

5. **Chopper weapons** — Firing bullets, 5-shot limit.

6. **Tanks** — Spawn, roll, aim cannon, fire shells. Shell ballistics.

7. **Jets** — Spawn, fly patterns, fire missiles and bombs. Difficulty-gated.

8. **Aliens** — Spawn at difficulty 2+.

9. **Difficulty scaling** — CURR_LEVEL increments, spawn rate tables.

10. **Sorties / lives** — Death animation, reset, 3-life limit.

11. **Win/lose conditions** — End sequences.

12. **Polish** — Sound, title screen, demo mode.

### 4.3 Key Faithful Details to Preserve

These are what make Choplifter feel like Choplifter:

- **The turn animation** — chopper rotates through a multi-frame sequence when changing direction. **Firing is permitted during the turn** — the shooting gate (`choplifter.s:877–890`) checks only airborne/dying/5-shot-cap, never turn state; bullet angle and gravity vary with turn state (see DESIGN.md §7). This is iconic.
- **The hover physics** — the chopper has real momentum and drift. It does not stop instantly.
- **Ground depth layers** — tanks appear on different "planes" at different depths, creating a pseudo-3D battlefield. Use `z_index` + subtle Y-position offset per depth layer.
- **Hostages getting shot** — tanks and jets can kill hostages on the ground. Houses can be set on fire.
- **5-bullet cap** — player cannot fire until a bullet leaves the screen.
- **Gravity** — chopper will fall if you cut thrust. `ZP_ACCELY` holds a **table index**, not a magnitude: index `$08` (normal gravity) → −2 unit/frame, index `$0F` (full thrust) → +6 unit/frame, via `integrateAccelerationAccelYTable` (`choplifter.s:5266`). Do not treat `$08`/`$0F` as accelerations.
- **No score** — don't add points. Stick to the hostage counters.

### 4.4 Modern Enhancements (Optional)

Things the original couldn't do due to hardware limits, reasonable to add:

- Smooth 60fps animation (original was limited by CPU budget)
- Full-color pixel art (original had 6 colors max, plus Apple II's palette quirks)
- Remastered/chiptune sound effects and ambient audio
- Resolution options (original was 280×192)
- Additional levels/worlds beyond the one map
- Leaderboard (time to rescue all hostages, since there's no score)
- Gamepad support (joystick was the original control)

### 4.5 Things to Avoid

- Don't add a score system unless you're intentionally departing from the original
- Don't add health — original is one-hit kill
- Don't make the chopper faster or more maneuverable than the physics allow — the momentum-based feel is intentional

---

## 5. Godot 4 Project Structure

```
choplifter-clone/
├── src/
│   ├── entities/
│   │   ├── Chopper.gd / Chopper.tscn
│   │   ├── Tank.gd / Tank.tscn
│   │   ├── Jet.gd / Jet.tscn
│   │   ├── Alien.gd / Alien.tscn
│   │   ├── Hostage.gd / Hostage.tscn
│   │   ├── Bullet.gd / Bullet.tscn
│   │   ├── Shell.gd / Shell.tscn
│   │   └── Missile.gd / Missile.tscn
│   ├── world/
│   │   ├── World.gd / World.tscn       ← main scene, holds scroll + camera
│   │   ├── Terrain.gd                  ← ground plane + depth layers
│   │   ├── Base.gd / Base.tscn
│   │   ├── House.gd / House.tscn
│   │   └── SpawnManager.gd             ← enemy + hostage spawning logic
│   ├── ui/
│   │   ├── HUD.gd / HUD.tscn           ← rescued/killed/loaded counters
│   │   └── TitleScreen.gd / TitleScreen.tscn
│   └── autoload/
│       └── GameState.gd                ← SORTIE, CURR_LEVEL, hostage counts, global state
├── assets/
│   ├── graphics/
│   ├── audio/
│   └── fonts/
└── docs/
```

---

## 6. Data to Port Faithfully

These numeric values from the source are the result of careful tuning — preserve them:

| Constant | Value | Meaning |
|---|---|---|
| Max entities | 30 | Total object cap |
| Max hostages | 16 | Per wave |
| Max tanks | 4 | Active at once |
| Max jets | 4 | Active at once |
| Max aliens | 4 | Active at once |
| Max bullets | 5 | Player shots on screen |
| Sorties | 3 | Lives |
| Win condition | 64 rescues | All hostages |
| Loss condition | `TOTAL_RESCUES + HOSTAGES_KILLED == 64` | OR 0 sorties (win check runs first) |
| Gravity index | `$08` (8) → −2/frame | Index into Y-accel table, not a magnitude |
| Full thrust index | `$0F` (15) → +6/frame | Index into Y-accel table, not a magnitude |
| Turn frames | -5 to +5 | 11 animation frames for rotation |
| Spawn interval | `FRAME_COUNT AND $2F` | Bitmask; non-uniform 16/48-frame cadence, not 47 |
| Hostage spawn | `FRAME_COUNT AND $03` | Every 4 frames |
| CURR_LEVEL max | 3 (Mode 1); 7 (Mode 2/3) | Source caps Mode 1 at 3 |

---

## 7. Quick Start Recommendation

1. Install **Godot 4.x** (latest stable)
2. Create a new 2D project
3. Start with `Chopper.gd` + `World.gd` — get the helicopter flying with proper physics
4. Reference `zeropage.s` for variable names and `choplifter.s` for function comments when implementing each system
5. The main game loop (line 591 of `choplifter.s`) is your frame-by-frame guide

The reverse-engineer's comments are good enough to treat as a design spec. When in doubt about game feel, play the original (available on Archive.org).
