# Choplifter Clone — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a faithful Godot 4 reimplementation of Choplifter (1982) in three visual tiers — Retro (Apple II sprites), Modern Pixel Art, and Hi-Res — with additive gameplay enhancement tiers (Standard, Director's Cut, Reimagined).

**Architecture:** Godot 4 `CharacterBody2D`-based entity system for movement, with **child `Area2D` hitboxes for all hit detection** (`CharacterBody2D` emits no `body_entered` signal); four persistent autoloads (`GameState`, `Settings`, `AudioManager`, `SceneTransition`); one scene per entity type; asset pipeline driven by Python tools and Scenario MCP. **All Mode 1 positions and velocities are stored in raw source units (1:1 with the 6502 disassembly); a fixed source-unit→pixel scale is applied only at render time** (see Task 3c). Mode 1 gameplay is always faithful to source (bugs included); enhancements are layered behind `GameState.gameplay_variant` guards.

**Tech Stack:** Godot 4.x (GDScript), GDUnit4 (testing), Python 3 (asset tools), ImageMagick + Pillow (sprite post-processing), numpy/scipy/ffmpeg (SFX), midiutil/FluidSynth (music), Scenario MCP (Mode 2 sprite generation).

**Definition of Done:** The plan is "done" when all of the following behavioral criteria pass:
- All 64 hostages are rescuable in a single play-through (win condition reachable). *Caveat (source-faithful, R3-H7): hostages that walk to the base door on foot — chopper-full run-backs — despawn safe but uncredited, exactly as in the original; the validating play-through must avoid triggering them (don't fill the chopper while runners are en route).*
- All three loss conditions are reachable (sorties exhausted, all hostages killed/rescued)
- A **production-path integration test** passes: one hostage spawns from a house, runs to a landed chopper, boards (respecting the 16-aboard cap), is delivered to base via the base-runner unload, and increments `GameState.total_rescues` — driven through the real `World` scene graph, not isolated helpers
- A **physics golden-trace test** passes: a recorded input sequence reproduces an expected per-frame chopper position/velocity trace within tolerance
- An **input-path landing test** passes: holding the real `descend` action takes an airborne chopper to `landed == true` through `_handle_input()` — no direct state pokes. (R3-H8: the other two gates bypass the input layer and cannot catch a broken control path.)
- GDUnit4 test suite passes cleanly with zero failures
- Python pytest suite passes cleanly
- Game runs at a stable 60fps locked tick rate (no frame-rate-dependent physics drift)
- Web export boots and plays in a browser without audio autoplay errors

After all criteria pass, perform a final audit using the "full-review" skill.

**Source references:**
- `docs/blondie-ChoplifterReverse/choplifter.s` — 11,703-line annotated 6502 disassembly
- `docs/blondie-ChoplifterReverse/zeropage.s` — zero-page variable allocations
- `docs/DESIGN.md` — authoritative for all physics constants
- `docs/ENHANCED_GAMEPLAY.md` — variant-tier specs
- `docs/ASSET_PIPELINE.md` — tool specs for sprites, SFX, music

> **Critical:** `zeropage.s` comments describe *table indices*, not physical magnitudes. E.g. `ZP_ACCELY = $08` means index 8 into `integrateAccelerationAccelYTable` → −2 unit/frame. Never treat those values as raw accelerations. See `DESIGN.md §7`.

---

## Roadmap Summary

| Version | Scope | Key Deliverable |
|---|---|---|
| **v0.1** | Mode 1 core | Fully playable Retro game, Apple II sprites, 3 lives, all enemies |
| **v0.2** | Mode 1 polish | Tier A bug fixes, SFX pipeline, Mode 1 audio wired |
| **v0.3** | Mode 2 start | Variant picker UI, Desert biome, Scenario style model trained |
| **v0.4** | Mode 2 full | All 5 biomes, Tier B mechanics, music pipeline |
| **v0.5** | Tier C | Scatter-on-death, fuel system, mission rating + grade ceiling, PB wave splits, career stats + Records screen |
| **v1.0** | Polish | Web export, touch controls, fuel system tuned, full review |
| **v2.0** | Mode 3 | Hi-Res assets, Godot 4 3D renderer for 2D gameplay |

> **Start with v0.1.** Mode 2 *asset generation* (the Task 23/30 pipeline portions) has already run
> ahead of this gate with the maintainer's sign-off — see the execution-status note below. The gate
> now applies to *integrating* Mode 2 assets into the game (Task 29 onward), which still must wait
> for v0.1 to be playable end-to-end.

> **Execution status (2026-06-11, updated):** All asset generation is **complete and committed**:
> Task 3 (Mode 1 sprite extraction, 128 PNGs — e71e257), Task 23 (SFX pipeline, 21 OGGs — e71e257),
> Task 30 pipeline scripts/spec + all 161/161 Mode 2 sprites (a742dce, 690ea2e, 880fc8d), and the
> Task 34 music pipeline output (18 tracks — fbf3bdc). Executors must treat the asset-generation
> portions of Tasks 3, 23, 30, and 34 as done — do not re-run extraction or generation; doing so
> wastes paid Scenario credits. The *integration* portions (wiring assets into scenes, variant
> picker, music-state logic) remain to be done at their plan positions.

---

## Phase 0: Godot Project Bootstrap

### Task 1: Initialize Godot 4 project

**Files:**
- Create: `project.godot`
- Create: `.gitignore` (append Godot-specific entries)

**Step 1: Create the Godot project**

Open Godot 4. Create a new project in `/home/chris/Github/choplifter-clone/` using the **Compatibility** renderer (best web/mobile reach for a 2D pixel art game).

**Step 2: Configure project settings**

In `Project → Project Settings`:

```
Display/Window/Size/Viewport Width = 480
Display/Window/Size/Viewport Height = 270
Display/Window/Stretch/Mode = viewport
Display/Window/Stretch/Aspect = keep
Display/Window/Stretch/Scale Mode = integer
Rendering/Textures/Canvas Textures/Default Texture Filter = 0  (Nearest)
Application/Run/Main Scene = res://src/scenes/Boot.tscn
Physics/Common/Physics Ticks Per Second = 15   (amended at v0.1 — see below)
```

> **Amended at the v0.1 playability check:** the physics tick is the SOURCE tick. The Apple II
> original was CPU-bound at ~15 fps (no VBL), and every extracted constant is per source frame —
> at 60 Hz the game ran ~4× too fast. Evidence: the attract demo flies 224 source frames to cross
> the ~4100-unit map ≈ 15 s at 15 fps, matching footage. Ledgered as Approximation; rendering
> still runs at the display rate.

> **Stretch mode is `viewport` + `integer` (DESIGN.md §Appendix, commit 55633ee — authoritative):**
> pixel-perfect on high-DPI mobile screens; `canvas_items` would blur sub-pixel edges. Consequence:
> ALL canvas items, including `Control` UI, render at 480×270 while this mode is active. Menu scenes
> therefore switch `get_tree().root.content_scale_mode` to `DISABLED` (native res) at runtime, and
> game scenes restore `VIEWPORT`+`INTEGER`. `SceneTransition.transition_to()` (Task 7) owns the
> switch, keyed on destination scene path. See DESIGN.md §11.3.

> **Physics determinism:** All source-faithful entity logic MUST live in `_physics_process`, not
> `_process`. The locked physics tick (15 Hz = the source tick, amended at v0.1) is the emulation
> substrate — Mode 1 fidelity is void otherwise. Every entity added in later phases must follow
> this rule.

**Step 3: Add Godot entries to .gitignore**

```bash
cat >> .gitignore << 'EOF'

# Godot 4
.godot/
*.translation
export_presets.cfg
EOF
```

**Step 4: Create directory structure**

```bash
mkdir -p src/{autoload,entities,scenes,world,ui}
mkdir -p assets/{graphics/{mode1,mode2,mode3},audio/{sfx,music},fonts}
touch src/autoload/.gitkeep src/entities/.gitkeep src/scenes/.gitkeep \
      src/world/.gitkeep src/ui/.gitkeep \
      assets/graphics/mode1/.gitkeep assets/graphics/mode2/.gitkeep \
      assets/audio/sfx/.gitkeep assets/audio/music/.gitkeep
```

**Step 5: Commit**

```bash
git add project.godot .gitignore src/ assets/
git commit -m "chore: initialize Godot 4 project structure"
```

---

### Task 2: Install GDUnit4 testing addon

GDUnit4 is the standard unit testing framework for Godot 4.

**Step 1: Download GDUnit4**

In Godot → Asset Library → Search "GDUnit4" → Install. Or:

```bash
# Manual install: download the addon zip from https://github.com/MikeSchulze/gdUnit4/releases
# Extract to addons/gdUnit4/ inside the project root
```

**Step 2: Enable the addon**

`Project → Project Settings → Plugins` → Enable `GdUnit4`.

**Step 3: Verify installation**

In Godot, run `GdUnit4 → Run All Tests`. Expect: "No tests found." (not a crash).

**Step 4: Create test directory**

```bash
mkdir -p tests/unit tests/integration
touch tests/unit/.gitkeep tests/integration/.gitkeep
```

**Step 5: Commit**

```bash
git add addons/ tests/
git commit -m "chore: add GDUnit4 testing addon"
```

---

### Task 3: Extract Apple II sprites

**Files:**
- Read: `src/tools/extract_sprites.py` (already exists)
- Output: `assets/graphics/mode1/<sprite_name>.png`

**Step 1: Run the extractor**

```bash
python3 src/tools/extract_sprites.py \
  --gfx docs/blondie-ChoplifterReverse/CHOPGFX \
  --gfxhi docs/blondie-ChoplifterReverse/CHOPGFXHI \
  --out assets/graphics/mode1 \
  --scale 4
```

Expected output: ~128 PNG files in `assets/graphics/mode1/`. File names should match sprite groups from `DESIGN.md §6.2`.

**Step 2: Verify sprite groups are present**

```bash
ls assets/graphics/mode1/ | grep -E "chopper|tank|jet|alien|hostage|explosion|mountain|hud"
```

Expected: files from all listed groups.

**Step 3: Commit**

```bash
git add assets/graphics/mode1/
git commit -m "assets: extract Apple II Mode 1 sprites (128 PNGs)"
```

---

### Task 3b: Define collision layers and the hit-detection architecture

> **Must be done before any entity adds a collision node.** Two rules govern all hit detection:
>
> 1. **`CharacterBody2D` does NOT emit `body_entered`.** Only `Area2D` (and `RigidBody2D` with
>    contact monitoring) emit body/area-entered signals. Every entity therefore keeps its
>    `CharacterBody2D` **for movement only** and gains a **child `Area2D` "Hitbox" node** that owns
>    the collision shape used for hit detection. All overlap signals are wired from these `Area2D`
>    hitboxes — never from the `CharacterBody2D` root.
> 2. Without explicit layers, every hitbox detects every other and bullets hit the chopper, shells
>    trigger on each other, hostages block bullets. The layer/mask matrix below prevents that.

**Step 1: Configure layers in Project Settings**

In `Project → Project Settings → Layer Names → 2D Physics`:

| Layer # | Name | Occupants |
|---|---|---|
| 1 | `world` | Ground / terrain `StaticBody2D` |
| 2 | `chopper` | Chopper `Area2D` hitbox |
| 3 | `enemies` | Tank / Jet / Alien `Area2D` hitboxes |
| 4 | `player_bullets` | Bullet `Area2D` hitbox |
| 5 | `enemy_projectiles` | Shell / Missile / Bomb `Area2D` hitboxes |
| 6 | `hostages` | Hostage `Area2D` hitbox |
| 7 | `base` | Base `Area2D` |
| 8 | `houses` | House `Area2D` hitbox (shoot-to-open — R3 house model) |

**Hit-detection architecture (apply to every entity scene):**

- Root `CharacterBody2D` — `collision_layer = 0`, `collision_mask = 1` (world only). Mode 1 drives
  `position` directly in source units (manual integration), so it does **not** rely on
  `move_and_slide()`; the body type is retained only to keep an optional world/ground query channel
  available and a consistent node shape across entities. It participates in **no** hit detection.
- Child `Area2D` named `Hitbox` — carries the `collision_layer`/`collision_mask` from the matrix
  below and the `CollisionShape2D`. Connect its `area_entered(area)` signal (hitbox-vs-hitbox) to
  the owning script. Resolve the logical entity from the area via `area.owner` (the entity root).
- The `Base` is a plain `Area2D` (no movement body); it connects `area_entered` and checks for the
  chopper's hitbox.

**Collision mask matrix** (who detects whom — applies to each entity's `Area2D` hitbox):

| Entity hitbox | Collision Layer | Collision Mask (detects) |
|---|---|---|
| Chopper | 2 | 3 (enemies), 5 (enemy projectiles), 7 (base) |
| Tank / Jet / Alien | 3 | 4 (player bullets) |
| Bullet | 4 | 3 (enemies), 6 (hostages), 8 (houses — shoot-to-open) |
| Shell / Missile / Bomb | 5 | 2 (chopper) |
| Hostage | 6 | 4 (player bullets) |
| Base (`Area2D`) | 7 | 2 (chopper) |
| House | 8 | — (passive; detected by player bullets) |

> Ground interaction (landing, shells hitting dirt) is handled by the movement `CharacterBody2D`
> against layer 1, not by the hitbox matrix above.

**Step 2: Apply layers to each entity when building its .tscn**

When Task 8 (Chopper), Task 13 (Base), Task 14 (Hostage), Task 15 (Bullet), Task 16 (Tank/Shell),
Task 17 (Jet/Missile/Bomb), Task 18 (Alien) create their scenes, add the `Area2D` `Hitbox` child and
set `collision_layer`/`collision_mask` on it per the matrix above, leaving the movement root on
layer 0 / mask 1.

**Step 3: Commit**

```bash
git commit --allow-empty -m "chore: define collision layer/mask matrix and Area2D hitbox architecture"
```

---

### Task 3c: Source coordinate & unit model

> **Decision (locked): Mode 1 works in raw source units, 1:1 with the 6502 disassembly.** A fixed
> scale converts source units to display pixels only at render time. This lets every extracted
> constant (`BOUNDS_LEFT=$02D0`, `MIN_VY=$FBA0`, `CRASHSPEED=$EB01`, accel tables, `$B0` tank offset,
> etc.) be used verbatim with no per-constant conversion, eliminating an entire class of
> transcription bugs.

**The model:**

- **Horizontal world is the source 16-bit X space.** `BOUNDS_LEFT = 0x02D0` (720), `BOUNDS_RIGHT =
  0x1300` (4864), `BASE_X = 0x1274` (4724), `FARHOUSE_X = 0x0380` (896). Entity X positions and the
  16-bit `vel_x` are stored in these units, and **node `position` is set to these source units 1:1.**
- **Vertical** uses the source Y range for chopper/entities; altitude is up-positive in the
  simulation. Y velocity is the source 16-bit `vel_y` (high byte is the integer part — see Task 8).
- **Scale happens once, at the camera.** The World `Camera2D.zoom` maps source units to screen
  pixels (`SRC_TO_PX = 480/280`). The simulation and every node `position` stay in source units; only
  the camera (and any pixel-sized UI) applies the scale. This is why `WORLD_BOUNDS_*` are now source
  units, not pixels.
- **Godot Y is down-positive; source altitude is up-positive.** Negate exactly once, at the
  `pos_y → position.y` boundary (`Chopper._update_render_position`). Never sprinkle sign flips
  through the physics.

**Concretely:**

```gdscript
# On GameState (see Task 4):
const SRC_BOUNDS_LEFT: int = 0x02D0    # 720
const SRC_BOUNDS_RIGHT: int = 0x1300   # 4864
const SRC_BASE_X: int = 0x1274         # 4724
const SRC_FARHOUSE_X: int = 0x0380     # 896
const SRC_TO_PX: float = 480.0 / 280.0 # Camera2D zoom factor (screen px per source unit)

static func src_to_px(src_x: float) -> float:
    return src_x * SRC_TO_PX
```

> **Rule for all later tasks:** any value taken from `choplifter.s` is stored and computed in source
> units, and node positions are those source units 1:1. The only place the source→pixel scale appears
> is the `Camera2D.zoom` (and pixel-sized UI). Tests assert source-unit values, not pixels.

**Step 1: Add the constants to `GameState` (folded into Task 4).**
**Step 2: Add a `tests/unit/test_coordinate_model.gd`** asserting `SRC_BOUNDS_RIGHT == 4864`,
`SRC_BASE_X == 4724`, and `src_to_px(280.0) == 480.0`.
**Step 3: Commit**

```bash
git commit --allow-empty -m "docs: lock source-unit coordinate model for Mode 1"
```

---

### Task 3d: Fidelity Ledger

> **Cross-cutting safeguard.** The recurring failure mode in early drafts was labeling an
> *approximation* as *source-faithful* (hostage topology, tank-spawn bug, delivery, landing, RNG).
> Maintain a single **Fidelity Ledger** table — every Mode 1 mechanic classified as `Exact`,
> `Approximation (documented)`, or `Enhanced (out of Mode 1)`. Update the row whenever a task
> implements or deliberately deviates from source. A mechanic may not be called "faithful" unless its
> ledger row says `Exact` with a source line reference.

Create `docs/FIDELITY_LEDGER.md` with this seed table (extend per task):

| Mechanic | Classification | Source ref | Notes |
|---|---|---|---|
| Chopper Y integration (ease-to-target) | Exact | choplifter.s:5207–5234 | Task 8 |
| Chopper X integration (friction + accel table + clamp) | Exact | choplifter.s:5160–5260 | Task 8 |
| Proportional vertical input (ACCELY index 0–15) | Exact (digital on keyboard) | choplifter.s:5630–5658 | Task 10 — keyboard `descend` = full deflection (index 0); analog sticks map proportionally |
| Landing / crash / launch thresholds (touchdown gated on centered X stick) | Exact | choplifter.s:4792–4804, 5287–5331 | Task 13 |
| Hostage topology (4 houses / 64 reservoir / 16 active) | Exact | choplifter.s:3742–3815 | Task 14 |
| House choice (under-chopper preference + random-start ring scan) | Exact | choplifter.s:3756–3795 | Task 14 |
| 16-aboard cap + "chopper full" run-back | Exact | choplifter.s:3509–3556 | Task 14 |
| Run-back / door walk-in (no rescue credit) | Approximation (documented) | choplifter.s:3460–3526 | Task 14 — source underflows `BASE_RUNNERS` and leaks `HOSTAGES_ACTIVE`; we keep the no-credit rule, fix the counter leaks |
| Base-runner unload + `CURR_LEVEL`-on-unload (`CHOP_LOADED` batch) | Exact | choplifter.s:3789–3826 | Task 13/14 — rescues credited at UNLOAD, not at the door |
| Enemy spawn selection (one per `$2F` tick; RNG gates `$28`/bit 7) | Exact | choplifter.s:4570–4618 | Task 16 |
| Tank spawn velocity branch + PosV high-byte bug | Exact | choplifter.s:3886–3922 | Task 16 |
| Shell launch velocity (always 3) | Exact | choplifter.s:4560–4565 | Task 16 |
| Jet motion / fire cadence | Approximation (documented) | `$6C00` velocity tables not ported | Task 17 |
| Alien fire gates (anim frame 0, own Y < `$58`, RNG mask `$48`) | Approximation (screen-row mapping) | choplifter.s:9280–9296 | Task 18 |
| Bullet velocity (table + chopper-VX inheritance) | Exact | choplifter.s:7194–7259 (`initBulletPhysics`), 4743 (`bulletVelocityTable` $6f8d, 72 bytes), 7260 (`bulletGravityTable` $7fbc) | Task 15 — index = 12×\|turn_state\| + 2×\|stick_x\|; (vx, vy) byte pairs; vx += \|chopper VX high byte\|; vy sign from turn⊕stick |
| Hostage run trigger (no detect radius) | Exact | choplifter.s:3407–3423 (`updateHostagesPlayerAloft`) | Task 14 — source has NO range check: every field hostage runs toward a landed chopper at any distance, gated only by airborne / landed-at-base / `HOSTAGES_LOADED == 16` |
| House ignition (shoot-to-open; releases occupants; house 3 pre-opened with 8 fielded) | Exact | choplifter.s:8985–8998, 8605–8616, 11341–11360 | Task 14 — polarity is 0=closed/1=open; fire does NOT kill occupants. Source ordnance-vs-house test covers pages 0–2 only (house 3 starts open). **R3 open question CLOSED by static verification:** `spawnInitialHostages` ($9ea9) sets `houseStates+3 = $01` at game start, so the `cmp #$03` exclusion is correct by construction; `igniteHouse` is also idempotent ($8b4b guards on `houseStates,x`). No emulator check needed |
| Camera scroll clamps (`$02B0`–`$1208`) | Exact | choplifter.s:4768–4775 | Task 11 |
| Source RNG (rol/eor/ror through carry, V-flag seed bump) | Exact algorithm; seed/carry init approximated | choplifter.s:6069–6083 | Task 4 — source seed is the uninitialized accumulator; a bit-exact stream is unattainable by design |
| 16-house single field | Enhanced (Mode 2+) | — | Reimagined variant only; NOT Mode 1 — Task 35b |

**Step: Commit**

```bash
git add docs/FIDELITY_LEDGER.md
git commit -m "docs: add Fidelity Ledger classifying every Mode 1 mechanic"
```

> **Secret-handling rule (applies to the whole project, esp. Task 30 Scenario):** API keys live in a
> git-ignored `.env` only. **Never** base64-encode a key in a shell (base64 is encoding, not
> encryption, and lands in shell history), never `echo` a key, never commit `.env`. If a key is ever
> exposed, treat it as compromised and rotate it immediately. The Scenario key surfaced during this
> project's setup must be rotated.

---

## Phase 1: Autoloads (Global Singletons)

All four autoloads must be registered in `Project → Project Settings → Autoload` after creation.

### Task 4: GameState autoload

**Files:**
- Create: `src/autoload/GameState.gd`

**Step 1: Write the test**

Create `tests/unit/test_game_state.gd`:

```gdscript
extends GdUnitTestSuite

func before_each():
    GameState.reset()

func test_initial_values():
    assert_int(GameState.sortie).is_equal(0)
    assert_int(GameState.lives_remaining).is_equal(3)
    assert_int(GameState.curr_level).is_equal(0)
    assert_int(GameState.total_rescues).is_equal(0)
    assert_int(GameState.hostages_killed).is_equal(0)
    assert_int(GameState.hostages_loaded).is_equal(0)
    assert_bool(GameState.input_locked).is_false()
    assert_int(GameState.visual_mode).is_equal(1)

func test_source_coordinate_constants():
    assert_int(GameState.SRC_BOUNDS_RIGHT).is_equal(4864)
    assert_int(GameState.SRC_BASE_X).is_equal(4724)
    assert_float(GameState.src_to_px(280.0)).is_equal_approx(480.0, 0.001)

func test_hostage_universe_initialized():
    # 4 houses × 16 = 64 reservoir; max 16 active; max 16 aboard. Game start (source
    # spawnInitialHostages): house 3 pre-ignited (open) with 8 hostages already fielded.
    assert_int(GameState.NUM_HOUSES).is_equal(4)
    assert_array(GameState.hostages_in_houses).is_equal([16, 16, 16, 8])
    assert_array(GameState.house_states).is_equal([0, 0, 0, 1])  # 0 = closed, 1 = ignited/open
    assert_int(GameState.hostages_left).is_equal(56)
    assert_int(GameState.hostages_active).is_equal(8)
    assert_int(GameState.base_runners).is_equal(0)
    assert_int(GameState.field_hostage_records.size()).is_equal(8)

func test_source_rng_is_deterministic():
    GameState._rnd = 0x42
    GameState._rnd_seed = 0x00
    GameState._rnd_carry = 0
    var first := GameState.random_byte()
    GameState._rnd = 0x42
    GameState._rnd_seed = 0x00
    GameState._rnd_carry = 0
    var repeat := GameState.random_byte()
    assert_int(first).is_equal(repeat)          # same seed → same sequence
    assert_int(first).is_between(0, 255)

func test_win_condition():
    GameState.total_rescues = 64
    assert_bool(GameState.is_victory()).is_true()

func test_loss_condition_all_accounted():
    GameState.total_rescues = 10
    GameState.hostages_killed = 54
    assert_bool(GameState.is_mission_loss()).is_true()

func test_no_loss_when_victory_also_met():
    # Win check runs first — 64 rescues = win even if no kills
    GameState.total_rescues = 64
    GameState.hostages_killed = 0
    assert_bool(GameState.is_victory()).is_true()
    assert_bool(GameState.is_mission_loss()).is_false()
```

**Step 2: Run test to verify it fails**

In GDUnit4 runner: `tests/unit/test_game_state.gd` → Run.
Expected: FAIL — `GameState` not found.

**Step 3: Implement GameState.gd**

```gdscript
extends Node

# --- Visual and variant ---
enum VisualMode { RETRO = 1, MODERN = 2, HI_RES = 3 }
enum GameplayVariant { STANDARD = 0, DIRECTORS_CUT = 1, REIMAGINED = 2 }

var visual_mode: VisualMode = VisualMode.RETRO
var gameplay_variant: GameplayVariant = GameplayVariant.STANDARD

# --- Game progress ---
var sortie: int = 0           # 0-based sortie index (0 = first life)
var lives_remaining: int = 3
var curr_level: int = 0       # 0-3 in Mode 1; 0-7 in Mode 2/3
var total_rescues: int = 0    # TOTAL_RESCUES — credited at UNLOAD as each carried hostage disembarks
                              # (choplifter.s:3814); door arrival only decrements BASE_RUNNERS (R3-M10)
var hostages_killed: int = 0  # HOSTAGES_KILLED
var hostages_loaded: int = 0  # HOSTAGES_LOADED — currently aboard the chopper
var input_locked: bool = false

# --- Tier C extras ---
var fuel_enabled: bool = false
var scatter_on_death: bool = true  # Always true in Reimagined

# --- Demo mode ---
var demo_mode: bool = false

const TOTAL_HOSTAGES: int = 64
const MAX_SORTIES: int = 3
const MODE1_LEVEL_CAP: int = 3
const MODE2_LEVEL_CAP: int = 7

# --- Source coordinate & unit model (Task 3c) — Mode 1 simulates in raw source units ---
# Node positions are these source units 1:1; the World Camera2D zoom scales source→screen at render.
const SRC_BOUNDS_LEFT: int = 0x02D0     # 720  — BOUNDS_LEFT
const SRC_BOUNDS_RIGHT: int = 0x1300    # 4864 — BOUNDS_RIGHT
const SRC_BASE_X: int = 0x1274          # 4724 — BASE_X
const SRC_FARHOUSE_X: int = 0x0380      # 896  — FARHOUSE_X (left-most house anchor)
const SRC_SCROLL_END_X: int = 0x02B0    # 688  — SCROLL_END: leftmost viewport-left camera clamp (R3-M1)
const SRC_SCROLL_START_X: int = 0x1208  # 4616 — SCROLL_START: rightmost viewport-left camera clamp
const SRC_VIEW_WIDTH: int = 280         # source viewport width (units visible across the screen)
const SRC_TO_PX: float = 480.0 / 280.0  # render scale = Camera2D zoom factor (screen px per src unit)

# Aliases kept so existing references resolve; these are SOURCE units, not pixels.
const WORLD_BOUNDS_LEFT: float = float(SRC_BOUNDS_LEFT)    # 720
const WORLD_BOUNDS_RIGHT: float = float(SRC_BOUNDS_RIGHT)  # 4864

static func src_to_px(src_x: float) -> float:
    return src_x * SRC_TO_PX

# --- Hostage universe (authoritative; OWNED BY GameState so it survives World.tscn reloads) ---
# Source: 4 houses, 16 hostages each = 64 reservoir; max 16 active records; max 16 aboard.
const NUM_HOUSES: int = 4                # spawnHostages iterates cpx #$04 (choplifter.s:3776)
const HOSTAGES_PER_HOUSE: int = 16       # 4 × 16 = 64 = TOTAL_HOSTAGES
const MAX_ACTIVE_HOSTAGES: int = 16      # MAX_HOSTAGES hostageTable record count
const MAX_ABOARD: int = 16               # HOSTAGES_LOADED cmp #$10 cap
const MAX_SPAWN_BATCH: int = 5           # HOSTAGES_ACTIVE cmp #$05 spawn throttle
# Source X anchors for the 4 houses: FARHOUSE_X + index*256 (high byte += index).
# These are the house ANCHORS — the +$0A hostage-emerge offset is applied once, at spawn
# (choplifter.s:3858–3866). Do not bake it in here too (R3-M2).
const HOUSE_SRC_X: Array[int] = [0x0380, 0x0480, 0x0580, 0x0680]

var hostages_in_houses: Array[int] = []  # hostagesInHouses[4] — remaining inside each house
var house_states: Array[int] = []        # houseStates[4] — 1 = standing, 0 = on fire
var hostages_left: int = 0               # HOSTAGES_LEFT — reservoir not yet emerged
var hostages_active: int = 0             # HOSTAGES_ACTIVE — emerged & in the field
var base_runners: int = 0                # BASE_RUNNERS — disembarked, walking to the base door
var chop_loaded: bool = false            # CHOP_LOADED — armed on each boarding, cleared on the first
                                         # unload of the batch; gates the CURR_LEVEL increment (R3-H4)

# R3-C3: field-hostage records that must survive World.tscn reloads (the source hostageTable lives
# in RAM across deaths; scene nodes do not). Serialized by World before a sortie reload,
# re-instantiated by HostageManager.restore_field_hostages() on the next sortie.
var field_hostage_records: Array[Dictionary] = []  # [{ "x": float, "state": int, "counted_in_base_runners": bool }]

# --- Source RNG (HF8 / R3-H1) — faithful port of randomNumber (choplifter.s:6069–6083) ---
# 6502 rol/ror rotate THROUGH the carry flag (9-bit), adc consumes the carry left by ror, and the
# extra seed bump is gated on the OVERFLOW flag (bvc), not carry. The carry flag is modeled as
# persistent state. Ledger: Exact algorithm; the source seed ("whatever was in the accumulator
# when the loader was done") and initial carry are approximated as fixed values — a bit-exact
# stream vs. real hardware is unattainable by design.
var _rnd: int = 0x42         # ZP_RND seed (any nonzero start)
var _rnd_seed: int = 0x00    # randomSeed
var _rnd_carry: int = 0      # modeled 6502 carry flag

func random_byte() -> int:
    var a := _rnd                                        # lda ZP_RND
    var c := _rnd_carry
    var c_out := (_rnd >> 7) & 1                         # rol ZP_RND — 9-bit, through carry
    _rnd = ((_rnd << 1) | c) & 0xFF
    c = c_out
    a = a ^ _rnd                                         # eor ZP_RND
    c_out = _rnd & 1                                     # ror ZP_RND — 9-bit, through carry
    _rnd = ((_rnd >> 1) | (c << 7)) & 0xFF
    c = c_out
    _rnd_seed = (_rnd_seed + 1) & 0xFF                   # inc randomSeed (does not touch flags)
    var sum := a + _rnd_seed + c                         # adc randomSeed — consumes ror's carry
    var result := sum & 0xFF
    _rnd_carry = 1 if sum > 0xFF else 0
    # bvc randomNumberAlt — the extra seed bump fires on signed OVERFLOW (V flag), not carry
    if (~(a ^ _rnd_seed) & (a ^ result)) & 0x80 != 0:
        _rnd_seed = (_rnd_seed + 1) & 0xFF
    _rnd = result                                        # sta ZP_RND
    return result

func _init_hostage_universe() -> void:
    # R3 house-model fix — source polarity ($7311, choplifter.s:5097): 0 = untouched/CLOSED,
    # 1 = on fire/OPEN. Hostages emerge ONLY from ignited (open) houses; igniting RELEASES the
    # occupants, it does not kill them (igniteHouse, choplifter.s:8985–8998). The player opens
    # houses by shooting them (ordnance-vs-house check, choplifter.s:8605–8616).
    hostages_in_houses = []
    house_states = []
    for _i in range(NUM_HOUSES):
        hostages_in_houses.append(HOSTAGES_PER_HOUSE)
        house_states.append(0)  # closed
    hostages_left = TOTAL_HOSTAGES
    hostages_active = 0
    base_runners = 0
    # Game-start setup (spawnInitialHostages, choplifter.s:11341–11360): the right-most house
    # begins IGNITED with 8 of its hostages already in the field beside it. Seed them as field
    # records; World._ready()'s restore_field_hostages() instantiates them.
    house_states[3] = 1
    hostages_in_houses[3] -= 8
    hostages_left -= 8
    hostages_active = 8
    field_hostage_records.clear()
    for i in range(8):
        field_hostage_records.append({
            "x": float(HOUSE_SRC_X[3] + 0x0A + i * 6),
            "state": 0,  # Hostage.State.WAVING (raw int — avoids a cross-class dependency here)
            "counted_in_base_runners": false,
        })

func reset() -> void:
    sortie = 0
    lives_remaining = MAX_SORTIES
    curr_level = 0
    total_rescues = 0
    hostages_killed = 0
    hostages_loaded = 0
    input_locked = false
    demo_mode = false
    chop_loaded = false
    field_hostage_records.clear()
    _init_hostage_universe()

func is_victory() -> bool:
    return total_rescues >= TOTAL_HOSTAGES

func is_mission_loss() -> bool:
    # Win check runs first — call is_victory() before this
    if is_victory():
        return false
    return total_rescues + hostages_killed >= TOTAL_HOSTAGES

func is_sorties_loss() -> bool:
    return lives_remaining <= 0

func level_cap() -> int:
    return MODE1_LEVEL_CAP if visual_mode == VisualMode.RETRO else MODE2_LEVEL_CAP

# Source increments CURR_LEVEL during base unload, gated by cmp #$03 (choplifter.s:3822–3826).
# Mode 2/3 extend the cap to 7 — use level_cap(), not the hardcoded Mode 1 constant (R3-H5).
func increment_level_on_unload() -> void:
    if curr_level < level_cap():
        curr_level += 1

func on_chopper_death(aboard: int) -> void:
    # Hostages aboard are lost; active field hostages persist (state owned here, not in the scene).
    hostages_killed += aboard
    hostages_loaded = 0
    lives_remaining -= 1
    sortie += 1
```

> **State ownership (HF2):** the hostage/house inventory lives here, not on `World.tscn`. When a
> sortie ends, `World.tscn` may be reloaded freely; `_init_hostage_universe()` is called **once** at
> new-game start (from the main menu / `reset()`), never on sortie reload. Houses and hostages
> re-instantiated by a reloaded `World` read their counts from `GameState`, so totals never exceed 64
> and `is_victory()` / `is_mission_loss()` stay correct.


**Step 4: Register autoload**

`Project Settings → Autoload`: path = `res://src/autoload/GameState.gd`, name = `GameState`.

**Step 5: Run test to verify it passes**

Expected: all assertions PASS.

**Step 6: Commit**

```bash
git add src/autoload/GameState.gd tests/unit/test_game_state.gd
git commit -m "feat: add GameState autoload with win/loss conditions"
```

---

### Task 5: Settings autoload

**Files:**
- Create: `src/autoload/Settings.gd`

**Step 1: Write the test**

Create `tests/unit/test_settings.gd`:

```gdscript
extends GdUnitTestSuite

func test_default_volumes():
    assert_float(Settings.master_volume).is_equal(1.0)
    assert_float(Settings.sfx_volume).is_equal(1.0)
    assert_float(Settings.music_volume).is_equal(0.8)

func test_music_default_off_in_mode1():
    GameState.visual_mode = GameState.VisualMode.RETRO
    assert_bool(Settings.music_enabled).is_false()

func test_save_and_reload():
    Settings.master_volume = 0.5
    Settings.save()
    Settings.master_volume = 1.0  # Overwrite in memory
    Settings.load_settings()      # Reload from user://settings.cfg
    assert_float(Settings.master_volume).is_equal(0.5)

func after_each():
    # Restore defaults so saved cfg doesn't pollute other tests
    Settings.master_volume = 1.0
    Settings.save()
```

**Step 2: Run test — verify it fails**

Expected: FAIL — `Settings` not found.

**Step 3: Implement Settings.gd**

```gdscript
extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 0.8
var music_enabled: bool = false  # Off by default in Mode 1; toggled by visual_mode on load
var selected_visual_mode: int = 1
var selected_variant: int = 0
var fuel_enabled: bool = false

func _ready() -> void:
    load_settings()

func load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return  # Use defaults on missing or corrupt file
    master_volume = cfg.get_value("audio", "master_volume", 1.0)
    sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
    music_volume = cfg.get_value("audio", "music_volume", 0.8)
    music_enabled = cfg.get_value("audio", "music_enabled", false)
    selected_visual_mode = cfg.get_value("game", "visual_mode", 1)
    selected_variant = cfg.get_value("game", "variant", 0)
    fuel_enabled = cfg.get_value("game", "fuel_enabled", false)

func save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("audio", "master_volume", master_volume)
    cfg.set_value("audio", "sfx_volume", sfx_volume)
    cfg.set_value("audio", "music_volume", music_volume)
    cfg.set_value("audio", "music_enabled", music_enabled)
    cfg.set_value("game", "visual_mode", selected_visual_mode)
    cfg.set_value("game", "variant", selected_variant)
    cfg.set_value("game", "fuel_enabled", fuel_enabled)
    cfg.save(SETTINGS_PATH)
```

**Step 4: Register autoload**

`Project Settings → Autoload`: path = `res://src/autoload/Settings.gd`, name = `Settings`.

**Step 5: Run test — verify it passes**

**Step 6: Commit**

```bash
git add src/autoload/Settings.gd tests/unit/test_settings.gd
git commit -m "feat: add Settings autoload with save/load"
```

---

### Task 6: AudioManager autoload

**Files:**
- Create: `src/autoload/AudioManager.gd`

**Step 1: Write the test**

Create `tests/unit/test_audio_manager.gd`:

```gdscript
extends GdUnitTestSuite

func test_play_sfx_does_not_crash_on_missing_file():
    # Should warn and return, not crash
    AudioManager.play_sfx("nonexistent_sound")

func test_sfx_respects_volume():
    AudioManager.play_sfx("bullet_fire")
    # AudioStreamPlayer is found and its volume_db is set from Settings
    var player = AudioManager.get_node_or_null("BulletFire")
    if player:
        assert_float(player.volume_db).is_not_equal(-80.0)
```

**Step 2: Run test — verify it fails**

**Step 3: Implement AudioManager.gd**

```gdscript
extends Node

const SFX_BASE_PATH: String = "res://assets/audio/sfx/"
const MUSIC_BASE_PATH: String = "res://assets/audio/music/"

var _sfx_players: Dictionary = {}
var _loop_players: Dictionary = {}    # name → AudioStreamPlayer for sustained loops
var _music_calm: AudioStreamPlayer
var _music_tension: AudioStreamPlayer
var _music_action: AudioStreamPlayer
var _current_music_state: String = "calm"
var _audio_unlocked: bool = false     # HTML5/Web: audio starts muted until a user gesture

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS  # Persist through pause
    _music_calm = _make_music_player("calm")
    _music_tension = _make_music_player("tension")
    _music_action = _make_music_player("action")
    # Web export: browsers suspend the AudioContext until the first user gesture.
    # Keep the master bus muted until we see one, then unmute. Harmless on desktop.
    if OS.has_feature("web"):
        AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

func _unhandled_input(event: InputEvent) -> void:
    if _audio_unlocked or not OS.has_feature("web"):
        return
    if event is InputEventKey or event is InputEventMouseButton \
       or event is InputEventJoypadButton or event is InputEventScreenTouch:
        _audio_unlocked = true
        AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)

func _make_music_player(layer: String) -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.name = "Music_" + layer
    p.bus = "Music"
    add_child(p)
    return p

func play_sfx(sfx_name: String) -> void:
    var path := SFX_BASE_PATH + sfx_name + ".ogg"
    if not ResourceLoader.exists(path):
        push_warning("AudioManager: SFX not found: " + path)
        return
    if not _sfx_players.has(sfx_name):
        var p := AudioStreamPlayer.new()
        p.name = sfx_name.to_pascal_case()
        p.bus = "SFX"
        p.stream = load(path)
        add_child(p)
        _sfx_players[sfx_name] = p
    var player: AudioStreamPlayer = _sfx_players[sfx_name]
    player.volume_db = linear_to_db(Settings.master_volume * Settings.sfx_volume)
    player.play()

# --- Sustained loops (chopper engine, alien crackle) ---------------------------
# Lifecycle: start_loop on spawn/engine-on, stop_loop on death/despawn/engine-off.
# Idempotent — calling start twice is a no-op; stop on an absent loop is safe.
func start_loop(loop_name: String) -> void:
    if _loop_players.has(loop_name) and _loop_players[loop_name].playing:
        return
    var path := SFX_BASE_PATH + loop_name + ".ogg"
    if not ResourceLoader.exists(path):
        push_warning("AudioManager: loop SFX not found: " + path)
        return
    var p: AudioStreamPlayer
    if _loop_players.has(loop_name):
        p = _loop_players[loop_name]
    else:
        p = AudioStreamPlayer.new()
        p.name = "Loop_" + loop_name.to_pascal_case()
        p.bus = "SFX"
        var stream := load(path)
        if stream is AudioStreamOggVorbis:
            stream.loop = true   # ensure the .ogg actually loops
        p.stream = stream
        add_child(p)
        _loop_players[loop_name] = p
    p.volume_db = linear_to_db(Settings.master_volume * Settings.sfx_volume)
    p.play()

func stop_loop(loop_name: String) -> void:
    if _loop_players.has(loop_name):
        _loop_players[loop_name].stop()

func set_music_state(state: String, biome: String = "desert") -> void:
    if not Settings.music_enabled:
        return
    _current_music_state = state
    # Crossfade logic: fade out non-active layers, fade in active layer
    # Simple version: just play/stop (crossfade added in v0.4)
    for layer_name in ["calm", "tension", "action"]:
        var player: AudioStreamPlayer = get_node("Music_" + layer_name)
        if layer_name == state:
            if not player.playing:
                var path := MUSIC_BASE_PATH + "music_%s_%s.ogg" % [biome, layer_name]
                if ResourceLoader.exists(path):
                    player.stream = load(path)
                    player.play()
        else:
            player.stop()

func stop_music() -> void:
    for layer_name in ["calm", "tension", "action"]:
        get_node("Music_" + layer_name).stop()
```

**Step 4: Register autoload**

`Project Settings → Autoload`: path = `res://src/autoload/AudioManager.gd`, name = `AudioManager`.

**Step 5: Run test — verify it passes**

**Step 6: Add audio buses**

In Godot `Audio` panel (bottom of editor):
- Add bus: `SFX` (below Master)
- Add bus: `Music` (below Master)

Save `res://default_bus_layout.tres`.

**Step 7: Commit**

```bash
git add src/autoload/AudioManager.gd tests/unit/test_audio_manager.gd default_bus_layout.tres
git commit -m "feat: add AudioManager autoload with SFX and music layer support"
```

---

### Task 7: SceneTransition autoload

**Files:**
- Create: `src/autoload/SceneTransition.gd`
- Create: `src/autoload/SceneTransition.tscn` (Node → ColorRect child)

**Step 1: Implement SceneTransition.gd**

```gdscript
extends CanvasLayer

@onready var _overlay: ColorRect = $Overlay

const FADE_DURATION: float = 0.3

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 100
    _overlay.color = Color.BLACK
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _overlay.modulate.a = 0.0
    _overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func transition_to(scene_path: String) -> void:
    GameState.input_locked = true
    await _fade_to(1.0)
    get_tree().change_scene_to_file(scene_path)
    await get_tree().process_frame
    await _fade_to(0.0)
    GameState.input_locked = false

func _fade_to(target_alpha: float) -> void:
    var tween := create_tween()
    tween.tween_property(_overlay, "modulate:a", target_alpha, FADE_DURATION)
    await tween.finished
```

**Step 2: Create SceneTransition.tscn**

In Godot editor: create a scene with root `CanvasLayer`, add `ColorRect` child named `Overlay`. Save as `src/autoload/SceneTransition.tscn`.

**Step 3: Register autoload**

`Project Settings → Autoload`: path = `res://src/autoload/SceneTransition.tscn`, name = `SceneTransition`.

**Step 4: Commit**

```bash
git add src/autoload/SceneTransition.gd src/autoload/SceneTransition.tscn
git commit -m "feat: add SceneTransition autoload with fade-to-black"
```

---

## Phase 2: Chopper Physics

> The most critical system. Get this feeling right before building anything else.

### Task 8: Chopper physics — source-faithful integration (CF1)

> **This is the algorithm, not just the table.** The source `integrateAcceleration`
> (choplifter.s:5160–5260) does **not** add the accel-table value to velocity. The Y table holds
> **target velocities**; each frame Y velocity eases *toward* the target (halving the remaining
> distance while it is ≥ 2). X velocity has per-frame friction (`VELX -= VELX>>4`), a 16-bit accel
> table indexed by bank amount, and a `±$15` high-byte clamp. Getting this exact is what makes the
> chopper feel like Choplifter; a naive `vel += accel` Euler step compiles, passes a table-only test,
> and ships feeling wrong.

The 16-entry signed-byte Y target-velocity table from `choplifter.s:5266`. Index 8 = gravity target
(−2), index 15 = full-thrust target (+6).

**Files:**
- Create: `src/entities/Chopper.gd`
- Create: `src/entities/Chopper.tscn` (`CharacterBody2D` root + `Area2D` Hitbox child)
- Test: `tests/unit/test_chopper_physics.gd`

**Step 1: Write the failing test**

> Assert the **integration behavior** (golden frame-by-frame traces), not just the table. These
> traces are computed by hand from the source algorithm and are the regression anchor for CF1.

```gdscript
extends GdUnitTestSuite

# Y target-velocity table from choplifter.s:5266
const ACCEL_Y_TABLE := [-10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6]

func _new_chopper() -> Chopper:
    var c: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(c)
    return c

func test_target_table_values():
    assert_int(ACCEL_Y_TABLE[8]).is_equal(-2)   # gravity target
    assert_int(ACCEL_Y_TABLE[15]).is_equal(6)   # full thrust target

func test_chopper_table_matches_source():
    var c := _new_chopper()
    assert_array(c.ACCEL_Y_TABLE).is_equal(ACCEL_Y_TABLE)
    c.queue_free()

func test_y_eases_toward_thrust_target_not_added():
    # From rest, full thrust (target +6): high byte eases 0→3→4→5→6→6 (halve-when-≥2),
    # NOT 0→6→12 (which a naive vel+=accel would produce).
    var c := _new_chopper()
    c.vel_y = 0
    c.accely_index = 15
    var trace := []
    for i in range(5):
        c.integrate_acceleration()
        trace.append(c.vel_y_hi())
    assert_array(trace).is_equal([3, 4, 5, 6, 6])
    c.queue_free()

func test_y_gravity_eases_to_minus_2():
    # From rest, gravity (target -2): high byte eases 0→-1→-2→-2.
    var c := _new_chopper()
    c.vel_y = 0
    c.accely_index = 8
    var trace := []
    for i in range(3):
        c.integrate_acceleration()
        trace.append(c.vel_y_hi())
    assert_array(trace).is_equal([-1, -2, -2])
    c.queue_free()

func test_x_velocity_clamped_to_high_byte_0x15():
    # Hold full right joystick; X high byte must clamp at +0x15 (21), never exceed.
    var c := _new_chopper()
    c.vel_x = 0
    c.accelx = 5  # max joystick-X magnitude (ACCEL_X_TABLE[5])
    for i in range(40):
        c.integrate_acceleration()
    assert_int(c.vel_x_hi()).is_less_equal(0x15)
    assert_int(c.vel_x_hi()).is_greater(0)
    c.queue_free()

func test_x_friction_decays_velocity_when_centered():
    # With no joystick input (accelx 0, ACCEL_X_TABLE[0]=0), friction VELX -= VELX>>4 decays to 0.
    var c := _new_chopper()
    c.vel_x = 0x1000
    c.accelx = 0
    var before := c.vel_x
    c.integrate_acceleration()
    assert_int(c.vel_x).is_less(before)
    c.queue_free()
```

**Step 2: Run test — verify it fails**

Expected: FAIL — `Chopper.tscn` not found.

**Step 3: Implement Chopper.gd (physics only)**

```gdscript
extends CharacterBody2D
class_name Chopper

# --- Source-faithful tables (choplifter.s:5262–5267) ---
# Y: TARGET velocities (units/frame, high-byte). Velocity eases toward these — never added.
const ACCEL_Y_TABLE: Array[int] = [-10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6]
# X: 16-bit signed acceleration magnitudes, indexed by bank amount |turn_state| (0 = head-on).
const ACCEL_X_TABLE: Array[int] = [0x0000, 0x0060, 0x00B4, 0x0108, 0x015C, 0x01A4]

const GRAVITY_INDEX: int = 8          # ZP_ACCELY default (no thrust) — target −2
const FULL_THRUST_INDEX: int = 15     # ZP_ACCELY max — target +6
const DESCEND_INDEX: int = 0          # ZP_ACCELY min — full stick-down, target −10 (R3-C1: required
                                      # to reach MIN_VY and land; gravity alone tops out at −2)
const VEL_X_CLAMP_HI: int = 0x15      # high-byte clamp ±21 (source cmp #$15 / #$EB)
const VEL_FRAC: int = 256             # velocity is 8.8 fixed point (low byte = fraction)
const MAX_BULLETS: int = 5
const TURN_STATES: int = 11           # -5 to +5

# --- Bullet gravity table from choplifter.s:7260 (|turn_state| → drop) ---
const BULLET_GRAVITY_TABLE: Array[int] = [-2, -2, -1, -1, -1, 0]

# --- 16-bit fixed-point velocity (source ZP_VELX_16 / ZP_VELY_16) ---
var vel_x: int = 0   # 8.8 fixed point, source units/frame
var vel_y: int = 0   # 8.8 fixed point; low byte is forced to 0 each frame by the Y algorithm

# --- Position in SOURCE units (Task 3c); render layer scales to pixels ---
var pos_x: float = 0.0   # source X (SRC_BOUNDS_LEFT … SRC_BOUNDS_RIGHT)
var pos_y: float = 0.0   # source altitude, UP-POSITIVE (0 = ground); Godot Y negated at render

# --- State ---
var accely_index: int = GRAVITY_INDEX
var accelx: int = 0            # ZP_STICKX: joystick-X input, -5…+5; |accelx| indexes ACCEL_X_TABLE
var turn_state: int = 0        # -5 (left side) … 0 (head-on) … +5 (right side); rotor facing
var logical_face: int = 1      # 1 = right, -1 = left (flips instantly on input)
var airborne: bool = false     # set by ground check (Task 13)
var landed: bool = false       # set by ground check (Task 13)
var landed_at_base: bool = false
var grounding: bool = false    # ZP_GROUNDING — ground-intersection latch (Task 13)
var dying: bool = false
var death_timer: int = 0
var hostages_aboard: int = 0
var active_bullets: int = 0
var fuel: float = 1.0          # Tier C only; ignored in Mode 1

func _ready() -> void:
    add_to_group("chopper")    # entities/managers resolve the player via this group

# Arithmetic shift right (sign-preserving) — matches source arithmeticShiftRight16.
func _asr(v: int, n: int) -> int:
    return v >> n

func vel_y_hi() -> int:
    return _asr(vel_y, 8)

func vel_x_hi() -> int:
    return _asr(vel_x, 8)

func get_y_target() -> int:
    return ACCEL_Y_TABLE[accely_index]

# --- The integration step (CF1): X first, then Y, matching integrateAcceleration ---
func integrate_acceleration() -> void:
    _integrate_x()
    _integrate_y()

func _integrate_x() -> void:
    # Per-frame friction/drag: VELX -= VELX >> 4 (source caches, ASR16 by 4, subtracts).
    vel_x -= _asr(vel_x, 4)
    # Joystick acceleration: magnitude from table[|accelx|], direction = sign(accelx).
    # (Source stores accel sign-reversed internally vs. screen velocity; the net on-screen effect is
    # acceleration toward the input direction, which this expresses directly.)
    var idx := absi(accelx)
    var a := ACCEL_X_TABLE[idx]
    vel_x += signi(accelx) * a
    # Clamp the high byte (source cmp #$15 / cmp #$EB, choplifter.s:5240–5258): the positive side
    # clamps AT +$15 (zeroing the low byte at exactly $15xx); the negative side clamps below −$15
    # to $EB00. R3-L1.
    var hi := vel_x_hi()
    if hi >= VEL_X_CLAMP_HI:
        vel_x = VEL_X_CLAMP_HI << 8
    elif hi < -VEL_X_CLAMP_HI:
        vel_x = -(VEL_X_CLAMP_HI << 8)

func _integrate_y() -> void:
    # Ease Y velocity HIGH BYTE toward the table TARGET (halve remaining distance while ≥ 2).
    var target := get_y_target()
    var vy_h := vel_y_hi()
    var diff := target - vy_h
    var mag := absi(diff)
    if mag >= 2:
        mag = mag >> 1                       # source: cmp #$02 / lsr
    var step := (1 if diff >= 0 else -1) * mag
    vy_h += step
    vel_y = vy_h << 8                         # VELY_L := 0

func integrate_velocity() -> void:
    # Advance source-unit position by the 8.8 fixed-point velocity.
    pos_x += float(vel_x) / float(VEL_FRAC)
    pos_y += float(vel_y) / float(VEL_FRAC)  # up-positive (thrust +6 raises altitude)

func _physics_process(_delta: float) -> void:
    if dying or GameState.input_locked:
        return
    _handle_input()          # Task 10: sets accely_index, accelx, target_turn_state, fires
    _advance_turn_state()    # Task 9: animates turn_state toward target_turn_state
    integrate_acceleration()
    integrate_velocity()
    _clamp_to_world_bounds()
    _check_ground()                          # implemented in Task 13 (source thresholds)
    _update_render_position()
    if landed and not dying:
        _check_boarding_nearby_hostages()

func _clamp_to_world_bounds() -> void:
    if pos_x < GameState.SRC_BOUNDS_LEFT:
        pos_x = GameState.SRC_BOUNDS_LEFT
        vel_x = 0
    elif pos_x > GameState.SRC_BOUNDS_RIGHT:
        pos_x = GameState.SRC_BOUNDS_RIGHT
        vel_x = 0

func _update_render_position() -> void:
    # Node positions are SOURCE units 1:1 (the World Camera2D zoom scales source→screen at render).
    # Only the Y axis is flipped here (source altitude is up-positive; Godot Y is down-positive).
    const GROUND_SRC_Y := 0.0   # source ground reference; altitude 0 sits on the ground line
    position.x = pos_x
    position.y = GROUND_SRC_Y - pos_y

func _check_ground() -> void:
    # Stub here; Task 13 implements source ground intersection (MIN_VY threshold, crash, launch).
    pass

func _check_boarding_nearby_hostages() -> void:
    for hostage in get_tree().get_nodes_in_group("hostages"):
        hostage.check_boarding(self)
```

**Step 4: Create Chopper.tscn**

In Godot editor: create scene, root = `CharacterBody2D` (movement only; `collision_layer = 0`,
`collision_mask = 1`), attach `Chopper.gd`. Add a child `Area2D` named `Hitbox`
(`collision_layer = 2`, `collision_mask = 3 | 5 | 7`) with a `CollisionShape2D` (rectangle, ~48×14
px). Add an `AnimatedSprite2D` child. Wire `Hitbox.area_entered` to a handler that resolves
`area.owner` (Task 16+ enemies / projectiles). Save as `src/entities/Chopper.tscn`.

**Step 5: Run test — verify it passes**

**Step 6: Update the Fidelity Ledger**

Mark "Chopper Y integration" and "Chopper X integration" rows `Exact`.

**Step 7: Commit**

```bash
git add src/entities/Chopper.gd src/entities/Chopper.tscn tests/unit/test_chopper_physics.gd \
        docs/FIDELITY_LEDGER.md
git commit -m "feat: chopper physics — source-faithful ease-to-target integration (CF1)"
```

---

### Task 9: Turn state machine

From `DESIGN.md §7`: `turn_state` ranges −5 to +5 (11 states). Advances at 2 steps/frame when distance ≥ 2, 1 step/frame when distance == 1. `logical_face` flips instantly on input. A full −5 → +5 turn takes 5 frames.

**Files:**
- Modify: `src/entities/Chopper.gd`
- Test: `tests/unit/test_chopper_turns.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

var chopper: Chopper

func before_each():
    chopper = preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)

func after_each():
    chopper.queue_free()

func test_full_turn_takes_5_frames():
    chopper.turn_state = -5  # Full left
    chopper.target_turn_state = 5  # Full right
    var frames := 0
    while chopper.turn_state != 5 and frames < 10:
        chopper._advance_turn_state()
        frames += 1
    assert_int(frames).is_equal(5)

func test_fast_advance_when_distance_gte_2():
    chopper.turn_state = 0
    chopper.target_turn_state = 5
    chopper._advance_turn_state()
    assert_int(chopper.turn_state).is_equal(2)  # Advances 2 at a time

func test_slow_advance_when_distance_1():
    chopper.turn_state = 4
    chopper.target_turn_state = 5
    chopper._advance_turn_state()
    assert_int(chopper.turn_state).is_equal(5)

func test_logical_face_flips_instantly():
    chopper.logical_face = -1  # facing left
    chopper.face_right()
    assert_int(chopper.logical_face).is_equal(1)
    # turn_state has NOT reached +5 yet (it animates separately)
    assert_bool(chopper.turn_state == 5).is_false()

func test_firing_allowed_during_turn():
    chopper.turn_state = 2  # Mid-turn
    chopper.airborne = true
    chopper.active_bullets = 0
    assert_bool(chopper.can_fire()).is_true()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement turn state machine in Chopper.gd**

Add to `Chopper.gd`:

```gdscript
var target_turn_state: int = 0

func face_left() -> void:
    logical_face = -1
    target_turn_state = -5

func face_right() -> void:
    logical_face = 1
    target_turn_state = 5

func face_camera() -> void:
    target_turn_state = 0

func _advance_turn_state() -> void:
    var dist := target_turn_state - turn_state
    if dist == 0:
        return
    var step := 2 if abs(dist) >= 2 else 1
    turn_state += sign(dist) * step
    turn_state = clamp(turn_state, -5, 5)

func can_fire() -> bool:
    return airborne and not dying and active_bullets < MAX_BULLETS

func get_bullet_gravity() -> int:
    return BULLET_GRAVITY_TABLE[abs(turn_state)]
```

And call `_advance_turn_state()` from `_physics_process()`.

**Step 4: Run test — verify it passes**

**Step 5: Commit**

```bash
git add src/entities/Chopper.gd tests/unit/test_chopper_turns.gd
git commit -m "feat: chopper turn state machine — 5-frame full turn, instant logical_face flip"
```

---

### Task 10: Input handling

**Files:**
- Modify: `project.godot` (Input Map actions)
- Modify: `src/entities/Chopper.gd`

**Step 1: Define input actions**

In `Project → Project Settings → Input Map`, add:

| Action | Default Keys |
|---|---|
| `thrust_up` | W, Up Arrow; Left Stick Up; LB on gamepad |
| `move_left` | A, Left Arrow; Left Stick Left; D-pad Left |
| `move_right` | D, Right Arrow; Left Stick Right; D-pad Right |
| `face_left` | Q; LB/L1 |
| `face_right` | E; RB/R1 |
| `descend` | S, Down Arrow; Left Stick Down; D-pad Down |
| `face_camera` | X; Right Stick Click / Y (pad) |
| `fire` | Space; RT/R2; A/Cross |
| `pause` | Escape, P; Start/Menu |

> **R3-C1 — `descend` is required for the game to be completable.** Touchdown registers only at
> `vy_hi ≤ −5` (MIN_VY), and gravity alone eases to −2. The source stick is proportional —
> `joystickYTable` maps deflection to ACCELY index 0–15 (choplifter.s:5630–5658). Keyboard
> `descend` is digital full-deflection (index 0); analog gamepad sticks SHOULD map the Y axis
> proportionally across indexes 0–15.

**Step 2: Add input polling to Chopper.gd**

```gdscript
func _handle_input() -> void:
    if GameState.input_locked or dying:
        return

    # Facing (logical_face flips instantly; turn_state animates separately)
    if Input.is_action_just_pressed("face_left"):
        face_left()
    elif Input.is_action_just_pressed("face_right"):
        face_right()
    elif Input.is_action_just_pressed("face_camera"):
        face_camera()

    # Vertical: thrust up, descend (required to land — see the R3-C1 note above), or gravity.
    if Input.is_action_pressed("thrust_up"):
        accely_index = FULL_THRUST_INDEX
    elif Input.is_action_pressed("descend"):
        accely_index = DESCEND_INDEX
    else:
        accely_index = GRAVITY_INDEX

    # Horizontal movement: ramp accelx toward ±5 while held, decay toward 0 when released.
    # |accelx| indexes ACCEL_X_TABLE (0 = no input, 5 = full deflection).
    if Input.is_action_pressed("move_right"):
        accelx = mini(accelx + 1, 5)
    elif Input.is_action_pressed("move_left"):
        accelx = maxi(accelx - 1, -5)
    else:
        accelx = signi(accelx) * maxi(absi(accelx) - 1, 0)

    # Fire
    if Input.is_action_just_pressed("fire") and can_fire():
        _fire_bullet()
```

Call `_handle_input()` at the top of `_physics_process()`.

**Step 3: Commit**

```bash
git add project.godot src/entities/Chopper.gd
git commit -m "feat: chopper input handling — all actions wired, gamepad-aware"
```

---

## Phase 3: World & Scrolling

### Task 11: World scene with camera scroll

`DESIGN.md §8`: Scroll tracks a lead offset ahead of the chopper based on velocity direction. Lead
is asymmetric: **70 source units left, 210 source units right** (the original 280-unit viewport).
Node positions are source units 1:1; the `Camera2D.zoom` (`SRC_TO_PX = 480/280`) is the only place the
source→pixel scale is applied.

**Files:**
- Create: `src/world/World.gd`
- Create: `src/world/World.tscn`
- Test: `tests/unit/test_world_scroll.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_scroll_lead_left():
    assert_float(World.SCROLL_LEAD_LEFT).is_equal(70.0)   # source units

func test_scroll_lead_right():
    assert_float(World.SCROLL_LEAD_RIGHT).is_equal(210.0)  # source units
```

**Step 2: Run test — verify it fails**

**Step 3: Implement World.gd**

```gdscript
extends Node2D
class_name World

const SCROLL_LEAD_LEFT: float = 70.0    # source units (original 70px / 280-unit viewport)
const SCROLL_LEAD_RIGHT: float = 210.0  # source units (original 210px / 280-unit viewport)

signal victory_achieved  # emitted by HostageManager when TOTAL_HOSTAGES are rescued

@onready var camera: Camera2D = $Camera2D
@onready var chopper: Chopper = $Chopper
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var hostage_manager: HostageManager = $HostageManager
@onready var terrain: Terrain = $Terrain
@onready var hud: CanvasLayer = $HUD

var _frame_count: int = 0  # global frame counter (replicates FRAME_COUNT)

func _ready() -> void:
    # The ONLY source→pixel scaling in the game: zoom maps source units to screen pixels.
    camera.zoom = Vector2(GameState.SRC_TO_PX, GameState.SRC_TO_PX)
    camera.position_smoothing_enabled = false  # we drive the camera manually
    # Top-left anchoring so camera.position == viewport top-left in source-unit world space,
    # keeping the scroll-lead formulas (source-unit offsets) correct as written.
    camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
    chopper.chopper_died.connect(_on_chopper_died)
    victory_achieved.connect(_start_victory)
    hostage_manager.setup(self, chopper)
    hostage_manager.restore_field_hostages()  # R3-C3: re-instantiate survivors from the prior sortie

func _physics_process(_delta: float) -> void:
    _frame_count = (_frame_count + 1) & 0xFF  # 8-bit wrap (matches source FRAME_COUNT)
    _update_camera()
    spawn_manager.tick(_frame_count)
    hostage_manager.tick(_frame_count)

const SRC_VIEW_HEIGHT: float = 270.0 / (480.0 / 280.0)  # 157.5 source units visible vertically
const GROUND_MARGIN_SRC: float = 24.0  # source units of terrain visible BELOW the ground line (tune by eye)

func _update_camera() -> void:
    # Work entirely in source units; the camera zoom handles the render scale.
    var view := float(GameState.SRC_VIEW_WIDTH)  # 280 source units
    var target_x: float
    if chopper.logical_face >= 0:  # facing right
        target_x = chopper.pos_x - SCROLL_LEAD_RIGHT
    else:
        target_x = chopper.pos_x - (view - SCROLL_LEAD_LEFT)
    # R3-M1: clamp to the source scroll limits SCROLL_END/SCROLL_START ($02B0–$1208,
    # choplifter.s:4768–4775) — the viewport may show up to 32 units beyond the world bounds.
    target_x = clampf(target_x,
        float(GameState.SRC_SCROLL_END_X), float(GameState.SRC_SCROLL_START_X))
    camera.position.x = target_x
    # R3-C2: vertical framing. Gameplay renders at y ≤ 0 (altitude is up-positive, negated once at
    # render), so the camera's top-left must sit ABOVE the ground line: the visible band is
    # [-(SRC_VIEW_HEIGHT - GROUND_MARGIN_SRC), +GROUND_MARGIN_SRC] — sky above, a strip of terrain
    # below. With y = 0 the camera would show only the underground half-plane.
    camera.position.y = -(SRC_VIEW_HEIGHT - GROUND_MARGIN_SRC)
    terrain.update_scroll(int(target_x))  # parallax mountains track the scroll (Task 12 wiring)
```

**Step 4: Create World.tscn**

In Godot: create scene, root = `Node2D`, attach `World.gd`. Add children:
- `Camera2D` (name: `Camera2D`) — `zoom` set in `_ready()`
- `Chopper.tscn` instance (name: `Chopper`)
- `Node` → attach `SpawnManager.gd` (name: `SpawnManager`)
- `Node` → attach `HostageManager.gd` (name: `HostageManager`)
- `Terrain.tscn` instance (name: `Terrain`) — parallax mountains + ground sprite (Task 12); scroll
  is driven from `_update_camera()` above
- `CanvasLayer` → attach `HUD.gd` (name: `HUD`) — stub for now
- `StaticBody2D` for ground (name: `Ground`), `CollisionShape2D` along the world width at the
  ground baseline (source y = 0)
- `Base.tscn` instance at `x = SRC_BASE_X` (name: `Base`)
- **4 × `House.tscn` instances** (Mode 1) at `GameState.HOUSE_SRC_X` (`0x038A, 0x048A, 0x058A,
  0x068A`). Name them `House0`–`House3` and set each `house_index` 0–3. (The 16-house layout is
  Mode 2+ only — Task 35b.)

Save as `src/world/World.tscn`.

**Step 5: Run test — verify it passes**

**Step 6: Commit**

```bash
git add src/world/World.gd src/world/World.tscn tests/unit/test_world_scroll.gd
git commit -m "feat: World scene with asymmetric camera scroll lead (source-faithful)"
```

---

### Task 12: Parallax mountains (Mode 1)

`DESIGN.md §8`: One mountain layer at exactly 50% scroll speed. Source: `SCROLLPOS − (SCROLLPOS >> 1)` with `and #$FE` odd-pixel alignment mask.

**Files:**
- Create: `src/world/Terrain.gd`
- Modify: `src/world/World.tscn`
- Test: `tests/unit/test_terrain_parallax.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_mountain_parallax_is_half_speed():
    var terrain := preload("res://src/world/Terrain.tscn").instantiate()
    add_child(terrain)
    # Simulate scroll position of 200
    var mountain_x := terrain.compute_mountain_x(200)
    # Source: scrollpos - (scrollpos >> 1), then AND #$FE (clear bit 0)
    var expected := (200 - (200 >> 1)) & ~1  # = 100, bit 0 cleared = 100
    assert_int(int(mountain_x)).is_equal(expected)
    terrain.queue_free()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement Terrain.gd**

```gdscript
extends Node2D
class_name Terrain

@onready var mountains_layer: Node2D = $Mountains
@onready var ground_sprite: Sprite2D = $Ground

func compute_mountain_x(scroll_pos: int) -> int:
    # Source: renderMountains — SCROLLPOS - (SCROLLPOS >> 1) AND #$FE
    return (scroll_pos - (scroll_pos >> 1)) & ~1

func update_scroll(scroll_pos: int) -> void:
    mountains_layer.position.x = -float(compute_mountain_x(scroll_pos))
```

**Step 4: Run test — verify it passes**

**Step 5: Commit**

```bash
git add src/world/Terrain.gd src/world/Terrain.tscn tests/unit/test_terrain_parallax.gd
git commit -m "feat: terrain parallax mountains at 50% speed (source-faithful formula)"
```

---

## Phase 4: Base & Landing

### Task 13: Landing, crash/launch, and base detection (HF3, CF2)

> Mode 1 does **not** use `move_and_slide()` for the chopper's ground contact. It replicates the
> source ground model (choplifter.s:4792–4804, 5380–5470): a minimum downward velocity registers a
> touchdown, excess speed crashes, and a launch threshold lifts off. The `Base` is an `Area2D` that
> flags when the chopper is over the landing pad (CF2 — no `body_entered` on `CharacterBody2D`).

**Source constants (exact):** `MIN_VY=$FBA0` (high byte −5 — min downward speed to register
ground), `CRASHSPEED=$EB01` (high byte `$EB` = −0x15 — the ±0x15 horizontal-speed magnitude at/above
which a touchdown crashes), `LAUNCHTHRESH=$0100` (high byte +1 — upward speed needed to leave the
ground), `MAX_SINK=$06`.

**Files:**
- Create: `src/world/Base.gd` / `Base.tscn` (`Area2D`)
- Modify: `src/entities/Chopper.gd`
- Test: `tests/unit/test_landing.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

var chopper: Chopper

func before_each():
    GameState.reset()
    chopper = preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)

func after_each():
    chopper.queue_free()

func test_safe_landing_sets_landed():
    chopper.airborne = true
    chopper.over_base = false
    chopper.pos_y = -1.0          # just below ground line
    chopper.vel_y = -6 << 8       # descending at vy_hi = -6 (past MIN_VY = -5)
    chopper.vel_x = 0             # horizontal speed safe
    chopper._check_ground()
    assert_bool(chopper.landed).is_true()
    assert_bool(chopper.dying).is_false()
    assert_int(chopper.vel_y).is_equal(0)

func test_crash_when_horizontal_speed_at_max():
    chopper.airborne = true
    chopper.pos_y = -1.0
    chopper.vel_y = -6 << 8
    chopper.vel_x = 0x15 << 8     # |vx_hi| == CRASHSPEED magnitude
    chopper._check_ground()
    assert_bool(chopper.dying).is_true()

func test_launch_requires_threshold():
    chopper.airborne = false
    chopper.landed = true
    chopper.pos_y = 0.0
    chopper.vel_y = 1 << 8        # vy_hi = +1 == LAUNCHTHRESH
    chopper._check_ground()
    assert_bool(chopper.airborne).is_true()

func test_base_landing_sets_landed_at_base():
    chopper.airborne = true
    chopper.over_base = true       # set by Base.area_entered
    chopper.pos_y = -1.0
    chopper.vel_y = -6 << 8
    chopper.vel_x = 0
    chopper._check_ground()
    assert_bool(chopper.landed_at_base).is_true()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement landing in Chopper.gd**

```gdscript
# --- Landing constants (choplifter.s:4792–4804), in source high-byte units ---
const MIN_VY_HI: int = -5        # MIN_VY $FBA0 — min downward speed to register ground
const CRASHSPEED_HI: int = 0x15  # CRASHSPEED $EB01 — |vx_hi| at/above which a touchdown crashes
const LAUNCHTHRESH_HI: int = 1   # LAUNCHTHRESH $0100 — upward speed to leave the ground
const MAX_SINK: int = 6          # MAX_SINK $06 — max ground settle depth (source units)

var over_base: bool = false      # set true while the chopper hitbox overlaps the Base Area2D

func _check_ground() -> void:
    if pos_y > 0.0:
        airborne = true
        landed = false
        landed_at_base = false
        return
    # At or below the ground line.
    pos_y = max(pos_y, float(-MAX_SINK))
    var vy_h := vel_y_hi()
    if airborne:
        # Touchdown only registers when descending at least MIN_VY *with the X stick centered* —
        # the source reaches the intersection check only through the ZP_ACCELX == 0 branch
        # (chopperPhysicsNoAccel, choplifter.s:5287–5292). R3-M3.
        if accelx == 0 and vy_h <= MIN_VY_HI:
            if absi(vel_x_hi()) >= CRASHSPEED_HI:
                crash()
                return
            _settle()
        # Gentle approach: hover at ground without latching landed.
    else:
        # Already grounded: lift off only when upward thrust beats the launch threshold.
        if vy_h >= LAUNCHTHRESH_HI:
            airborne = true
            landed = false
            landed_at_base = false
        else:
            _settle()

func _settle() -> void:
    pos_y = 0.0
    vel_y = 0
    vel_x -= _asr(vel_x, 1)       # ground X decay (source chopperPhysics_Decay: ASR by 1)
    landed = true
    airborne = false
    landed_at_base = over_base

func crash() -> void:
    if dying:
        return
    die()                          # Task 19: counts aboard hostages as killed, plays explosion
```

> **Delivery is NOT instant.** When `landed and landed_at_base`, the hostage-spawn tick in `World`
> (Task 14) unloads carried hostages one per cycle into base-runners. This is what credits
> `total_rescues` and advances `curr_level`. The chopper does not deliver hostages itself.

**Step 4: Create Base.tscn**

In Godot: `Area2D` root named `Base` (`collision_layer = 7`, `collision_mask = 2`) with a
`CollisionShape2D` (landing pad, ~source-unit width 0x40). Attach `Base.gd`:

```gdscript
extends Area2D
class_name Base

func _ready() -> void:
    position.x = float(GameState.SRC_BASE_X)   # source units 1:1
    area_entered.connect(_on_area_entered)
    area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
    var entity := area.owner
    if entity is Chopper:
        entity.over_base = true

func _on_area_exited(area: Area2D) -> void:
    var entity := area.owner
    if entity is Chopper:
        entity.over_base = false
```

**Step 5: Run test — verify it passes**

**Step 6: Update the Fidelity Ledger**

Mark "Landing / crash / launch thresholds" `Exact`; note the crash trigger (horizontal speed ≥
CRASHSPEED) as the documented interpretation.

**Step 7: Commit**

```bash
git add src/world/Base.gd src/world/Base.tscn src/entities/Chopper.gd \
        tests/unit/test_landing.gd docs/FIDELITY_LEDGER.md
git commit -m "feat: source-faithful landing/crash/launch + Base Area2D detection (HF3, CF2)"
```

---

## Phase 5: Hostage System

### Task 14: Hostage system — 4 houses, rescue loop, aboard cap (CF3, CF4, HF5, HF6)

> **Topology (CF3) is source-exact:** **4 houses**, a **64-hostage reservoir**, a **16-record active
> table**, and a **16-aboard cap** — no waves. (`spawnHostagesChooseHouse` masks RNG with `#$03` and
> iterates `cpx #$04`; `MAX_HOSTAGES`=16 is the active-record table size; `HOSTAGES_LEFT` starts at
> 64. choplifter.s:3742–3815.) The earlier "16 houses × 4" model was fabricated and is **removed from
> Mode 1**; it is retained only as a Mode 2+ Reimagined enhancement (Task 35b).
>
> **The rescue loop must be wired through production (CF4).** A dedicated `HostageManager` node,
> ticked every physics frame by `World`, runs the source `spawnHostages`/unload cycle. Without it the
> DoD ("all 64 rescuable") is structurally impossible.

**World layout (source-faithful):** the 4 houses sit at source X anchors `FARHOUSE_X + index*256`
(`GameState.HOUSE_SRC_X = [0x038A, 0x048A, 0x058A, 0x068A]`). The base sits at `SRC_BASE_X`
(0x1274). Hostage/house inventory is owned by `GameState` (HF2), so a reloaded `World` re-reads
counts and totals never exceed 64.

**Files:**
- Create: `src/entities/Hostage.gd` / `Hostage.tscn` (`CharacterBody2D` + `Area2D` Hitbox)
- Create: `src/world/House.gd` / `House.tscn`
- Create: `src/world/HostageManager.gd` (the spawn/unload tick — CF4 wiring)
- Test: `tests/unit/test_hostage_state.gd`, `tests/unit/test_hostage_manager.gd`

**Step 1: Write the failing tests**

```gdscript
# test_hostage_state.gd
extends GdUnitTestSuite

func before_each():
    GameState.reset()

func _new_hostage(src_x: float) -> Hostage:
    var h: Hostage = preload("res://src/entities/Hostage.tscn").instantiate()
    add_child(h)
    h.position.x = src_x
    return h

func test_hostage_initial_state_is_waving():
    var h := _new_hostage(1000.0)
    assert_int(h.state).is_equal(Hostage.State.WAVING)
    h.queue_free()

func test_hostage_runs_when_landed_chopper_in_range():
    var h := _new_hostage(1000.0)
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_x = 1040.0          # within detect range, left of hostage
    chopper.landed = true
    chopper.landed_at_base = false
    h.on_chopper_landed(chopper)
    assert_int(h.state).is_equal(Hostage.State.RUNNING)
    h.queue_free(); chopper.queue_free()

func test_board_respects_16_aboard_cap_runs_back_when_full():
    # HF5: chopper full → hostage does NOT board; it turns back toward base.
    GameState.hostages_loaded = 16
    var h := _new_hostage(1000.0)
    h.state = Hostage.State.RUNNING
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_x = 992.0           # within boarding prox (8 units left)
    h.check_boarding(chopper)
    assert_int(h.state).is_not_equal(Hostage.State.RESCUED)
    assert_int(GameState.hostages_loaded).is_equal(16)   # unchanged
    h.queue_free(); chopper.queue_free()

func test_board_when_space_available():
    GameState.hostages_loaded = 0
    GameState.hostages_active = 1
    var h := _new_hostage(1000.0)
    h.state = Hostage.State.RUNNING
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_x = 992.0           # 8 units left → in boarding band [8,10)
    h.check_boarding(chopper)
    assert_int(GameState.hostages_loaded).is_equal(1)
    assert_int(chopper.hostages_aboard).is_equal(1)
    h.queue_free(); chopper.queue_free()
```

```gdscript
# test_hostage_manager.gd
extends GdUnitTestSuite

func before_each():
    GameState.reset()

func test_field_spawn_draws_from_house_reservoir():
    var mgr := preload("res://src/world/HostageManager.gd").new()
    add_child(mgr)
    mgr.setup(self, _stub_chopper(0.0, false))   # chopper not at base
    # R3 house model: hostages emerge only from IGNITED houses, and the game-start state has
    # house 3 open with 8 already-active fielded hostages (which would block the <5 spawn
    # throttle). Set up a clean single-open-house state for this test.
    GameState.house_states = [1, 0, 0, 0]        # only house 0 ignited/open
    GameState.hostages_in_houses = [16, 16, 16, 16]
    GameState.hostages_left = 64
    GameState.hostages_active = 0
    GameState.field_hostage_records.clear()
    var before := GameState.hostages_left
    mgr.tick(0)                                   # frame 0 passes the &3 cadence gate
    assert_int(GameState.hostages_left).is_equal(before - 1)
    assert_int(GameState.hostages_active).is_equal(1)
    mgr.queue_free()

func test_unload_at_base_increments_rescues_and_level():
    GameState.hostages_loaded = 2
    GameState.chop_loaded = true     # armed by boarding (CHOP_LOADED) — gates the level increment
    GameState.curr_level = 0
    var chopper := _stub_chopper(float(GameState.SRC_BASE_X), true)
    chopper.hostages_aboard = 2
    var mgr := preload("res://src/world/HostageManager.gd").new()
    add_child(mgr)
    mgr.setup(self, chopper)
    mgr.tick(0)                                   # unloads one hostage this cycle
    assert_int(GameState.total_rescues).is_equal(1)
    assert_int(GameState.hostages_loaded).is_equal(1)
    assert_int(GameState.base_runners).is_equal(1)
    assert_int(GameState.curr_level).is_equal(1)  # CURR_LEVEL +1 on first unload of the batch
    mgr.queue_free(); chopper.queue_free()

func _stub_chopper(src_x: float, at_base: bool) -> Chopper:
    var c: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(c)
    c.pos_x = src_x
    c.landed = true
    c.landed_at_base = at_base
    return c
```

**Step 2: Run tests — verify they fail**

**Step 3: Implement Hostage.gd**

```gdscript
extends CharacterBody2D
class_name Hostage

# State machine. FIELD hostages emerge → wave → run → board. BASE_RUNNER hostages are the disembarked
# survivors walking to the base door (source: BASE_RUNNERS walking right to DOOR_X).
enum State { WAVING, RUNNING, LOADING, RESCUED, DEAD, BASE_RUNNER }

# Boarding proximity in SOURCE units (choplifter.s:3500–3556): board when the chopper is 8–9 units to
# one side; closer than 8 crushes the hostage; 10+ keeps running.
const BOARD_MIN: int = 8
const BOARD_MAX: int = 10
const RUN_STEP: float = 2.0          # source moves a hostage 2 units/frame
# NOTE: there is NO detect radius in the source (choplifter.s:3407–3423). Every field hostage
# runs toward a landed chopper at ANY distance; the only gates are airborne, landed-at-base,
# and a full cabin (HOSTAGES_LOADED == 16). An earlier draft used DETECT_RANGE = 96.0 — removed.

var state: State = State.WAVING
var house: House = null
var countdown_timer: float = 0.0     # Tier C: stranded countdown
var counted_in_base_runners: bool = false  # true only for unloaded runners (those that inc'd
                                           # BASE_RUNNERS); chopper-full run-backs stay false (R3-H7)

func _ready() -> void:
    add_to_group("hostages")

func on_chopper_landed(chopper: Chopper) -> void:
    # Only field hostages react; ignore if chopper is at the base or airborne.
    if state != State.WAVING:
        return
    if not chopper.landed or chopper.landed_at_base:
        return
    if GameState.hostages_loaded >= 16:   # full cabin: source gate at choplifter.s:3414 (cmp #$10)
        return
    state = State.RUNNING                 # any distance — source has no detect radius

func _physics_process(_delta: float) -> void:
    match state:
        State.RUNNING:
            _run_toward(_nearest_chopper_x())
        State.BASE_RUNNER:
            _run_to_base_door()

func _nearest_chopper_x() -> float:
    var c := get_tree().get_first_node_in_group("chopper") as Chopper
    return c.pos_x if c else position.x

func _run_toward(target_x: float) -> void:
    position.x += signf(target_x - position.x) * RUN_STEP

func _run_to_base_door() -> void:
    position.x += RUN_STEP            # walk right toward the base door
    if position.x >= float(GameState.SRC_BASE_X):
        # R3-H7 (Approximation, documented in the Fidelity Ledger): door arrival despawns the
        # hostage SAFE but UNCREDITED — faithful to source, which never increments TOTAL_RESCUES
        # at the door (choplifter.s:3460–3471). Unlike the source we keep the counters clean: the
        # source dec's BASE_RUNNERS even for chopper-full run-backs that never incremented it
        # (underflow to $FF) and leaks HOSTAGES_ACTIVE forever.
        if counted_in_base_runners:
            GameState.base_runners = maxi(GameState.base_runners - 1, 0)
        else:
            GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
        queue_free()                  # reached the door — safe!

# Called by Chopper._check_boarding_nearby_hostages() each frame while landed.
func check_boarding(chopper: Chopper) -> void:
    if state != State.RUNNING:
        return
    var dx := absi(int(round(position.x - chopper.pos_x)))
    if dx < BOARD_MIN:
        _crush()                      # too close — crushed by the chopper
    elif dx < BOARD_MAX:
        _try_board(chopper)

func _try_board(chopper: Chopper) -> void:
    if GameState.hostages_loaded >= GameState.MAX_ABOARD:
        # HF5: chopper full — turn back toward the base instead of boarding. The hostage remains
        # an ACTIVE field hostage (counted_in_base_runners stays false) — source keeps it in
        # HOSTAGES_ACTIVE (choplifter.s:3521–3526).
        state = State.BASE_RUNNER
        return
    state = State.RESCUED
    chopper.hostages_aboard += 1
    GameState.hostages_loaded += 1
    GameState.chop_loaded = true      # CHOP_LOADED — re-arms the per-batch CURR_LEVEL gate (R3-H4)
    GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
    AudioManager.play_sfx("hostage_board")
    queue_free()

func _crush() -> void:
    _die()

func _die() -> void:
    state = State.DEAD
    GameState.hostages_killed += 1
    GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
    AudioManager.play_sfx("hostage_death")
    queue_free()
```

**Step 4: Implement House.gd**

```gdscript
extends Node2D
class_name House

# Houses do NOT own hostage counts — GameState does (HF2). A house is a view + an ignition flag
# bound to its index in GameState.hostages_in_houses / GameState.house_states.
#
# R3 house-model fix (the earlier draft had this inverted): source polarity is 0 = untouched/
# CLOSED, 1 = on fire/OPEN ($7311, choplifter.s:5097). Igniting a house RELEASES its occupants —
# they emerge over time via the spawn tick — it does NOT kill them (igniteHouse,
# choplifter.s:8985–8998). The player opens houses by shooting them; house 3 starts open.
@export var house_index: int = 0

func _ready() -> void:
    position.x = float(GameState.HOUSE_SRC_X[house_index])

func is_open() -> bool:
    return GameState.house_states[house_index] == 1

func ignite() -> void:
    # Idempotent — the source returns early if the house is already burning.
    GameState.house_states[house_index] = 1
```

**Step 5: Implement HostageManager.gd (CF4 — the rescue-loop wiring)**

```gdscript
extends Node
class_name HostageManager

# Faithful port of spawnHostages (choplifter.s:62f2). Ticked every physics frame by World.
var _world: Node = null
var _chopper: Chopper = null
var _hostage_scene: PackedScene = preload("res://src/entities/Hostage.tscn")

func setup(world: Node, chopper: Chopper) -> void:
    _world = world
    _chopper = chopper

func tick(frame_count: int) -> void:
    # Source emits hostages on a 4-frame cadence (FRAME_COUNT AND $03 == 0).
    if frame_count & 0x03 != 0:
        return
    # Active cap: BASE_RUNNERS + HOSTAGES_ACTIVE may not exceed 16.
    if GameState.base_runners + GameState.hostages_active >= GameState.MAX_ACTIVE_HOSTAGES:
        return
    if _chopper.landed and _chopper.landed_at_base:
        _unload_one()
    elif GameState.hostages_left > 0 and GameState.hostages_active < GameState.MAX_SPAWN_BATCH:
        _spawn_field_hostage()
    # When a landed (non-base) chopper is present, nudge field hostages into their run.
    if _chopper.landed and not _chopper.landed_at_base:
        for h in get_tree().get_nodes_in_group("hostages"):
            h.on_chopper_landed(_chopper)

func _unload_one() -> void:
    # HF6: disembark one carried hostage per cycle into a base-runner walking to the door.
    if GameState.hostages_loaded <= 0:
        return
    GameState.total_rescues += 1
    GameState.hostages_loaded -= 1
    GameState.base_runners += 1
    _chopper.hostages_aboard = maxi(_chopper.hostages_aboard - 1, 0)
    AudioManager.play_sfx("hostage_rescued")
    # R3-H4: CURR_LEVEL increments once per batch, where a "batch" is delimited by BOARDING —
    # CHOP_LOADED is armed on each boarding and cleared on the FIRST unload after it
    # (choplifter.s:3552–3557, 3819–3826). Partial-unload → re-board → re-unload increments again.
    if GameState.chop_loaded:
        GameState.chop_loaded = false
        GameState.increment_level_on_unload()
    _spawn_base_runner()
    if GameState.is_victory():
        _world.emit_signal("victory_achieved")

func _spawn_base_runner() -> void:
    var h: Hostage = _hostage_scene.instantiate()
    h.state = Hostage.State.BASE_RUNNER
    h.counted_in_base_runners = true      # this runner DID increment BASE_RUNNERS (R3-H7)
    h.position.x = _chopper.pos_x + 4.0   # disembark just right of the chopper, walk to door
    _world.add_child(h)

func _spawn_field_hostage() -> void:
    var idx := _choose_house()
    if idx < 0:
        return
    GameState.hostages_in_houses[idx] -= 1
    GameState.hostages_left -= 1
    GameState.hostages_active += 1
    var h: Hostage = _hostage_scene.instantiate()
    h.state = Hostage.State.WAVING
    h.position.x = float(GameState.HOUSE_SRC_X[idx] + 0x0A)   # anchor + $0A emerge offset — applied
                                                              # ONCE, here only (R3-M2)
    _world.add_child(h)

func _choose_house() -> int:
    # R3-H3, source-exact (choplifter.s:3756–3795): prefer the house UNDER the chopper
    # (CHOP_POS_X_H − FARHOUSE_X_H in 0..3), else a random-start RING SCAN over all four houses —
    # exactly ONE RNG call, guaranteed to find any eligible house.
    var strip := (int(_chopper.pos_x) >> 8) - (GameState.SRC_FARHOUSE_X >> 8)
    if strip >= 0 and strip < GameState.NUM_HOUSES and _house_eligible(strip):
        return strip
    var start := GameState.random_byte() & 0x03
    var idx := start
    while true:
        if _house_eligible(idx):
            return idx
        idx = (idx + 1) % GameState.NUM_HOUSES
        if idx == start:
            break
    return -1

func _house_eligible(idx: int) -> bool:
    return GameState.house_states[idx] == 1 and GameState.hostages_in_houses[idx] > 0

# --- R3-C3: field hostages must survive World.tscn reloads (the source hostageTable persists in
# RAM across deaths; scene nodes do not). World calls serialize before the sortie transition and
# restore from _ready() on the next sortie. RUNNING demotes to WAVING — the chopper respawns at
# the base, so the run trigger re-evaluates naturally next time it lands nearby.
func serialize_field_hostages() -> void:
    GameState.field_hostage_records.clear()
    for h in get_tree().get_nodes_in_group("hostages"):
        if h.state in [Hostage.State.WAVING, Hostage.State.RUNNING, Hostage.State.BASE_RUNNER]:
            GameState.field_hostage_records.append({
                "x": h.position.x,
                "state": Hostage.State.WAVING if h.state == Hostage.State.RUNNING else h.state,
                "counted_in_base_runners": h.counted_in_base_runners,
            })

func restore_field_hostages() -> void:
    for rec in GameState.field_hostage_records:
        var h: Hostage = _hostage_scene.instantiate()
        h.state = rec["state"]
        h.counted_in_base_runners = rec["counted_in_base_runners"]
        _world.add_child(h)
        h.position.x = rec["x"]
    GameState.field_hostage_records.clear()
```

**Step 6: Create scenes & wire into World**

- `Hostage.tscn`: `CharacterBody2D` root (movement; layer 0 / mask 1) + child `Area2D` `Hitbox`
  (`collision_layer = 6`, `collision_mask = 4`) so player bullets can kill it. Attach `Hostage.gd`.
- `House.tscn`: `Node2D` + sprite (closed and burning frames keyed off `is_open()`) + child `Area2D`
  `Hitbox` (`collision_layer = 8` `houses`, `collision_mask = 0`) sized to the house body, so player
  bullets can ignite it (the bullet's mask detects layer 8 and calls `ignite()`). Attach `House.gd`.
- In `World` (Task 11): add a `HostageManager` node, call `hostage_manager.setup(self, chopper)` in
  `_ready()`, and `hostage_manager.tick(_frame_count)` in `_physics_process()`. Instantiate **4**
  `House.tscn` nodes with `house_index` 0–3.

**Step 7: Run tests — verify they pass**

**Step 8: Update the Fidelity Ledger**

Mark "Hostage topology", "House choice", "House ignition", "16-aboard cap + run-back", and
"Base-runner unload + `CURR_LEVEL`-on-unload (`CHOP_LOADED` batch)" `Exact`; mark "Run-back / door
walk-in (no rescue credit)" `Approximation (documented)`.

**Step 9: Commit**

```bash
git add src/entities/Hostage.gd src/entities/Hostage.tscn \
        src/world/House.gd src/world/House.tscn src/world/HostageManager.gd \
        tests/unit/test_hostage_state.gd tests/unit/test_hostage_manager.gd \
        docs/FIDELITY_LEDGER.md
git commit -m "feat: source-faithful hostage system — 4 houses, rescue loop wired, 16-aboard cap (CF3/CF4/HF5/HF6)"
```

---

## Phase 6: Chopper Weapons

### Task 15: Bullet firing with 5-shot cap

**Files:**
- Create: `src/entities/Bullet.gd` / `Bullet.tscn`
- Modify: `src/entities/Chopper.gd`
- Test: `tests/unit/test_bullet.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_bullet_gravity_at_turn_state_0():
    # Head-on facing: gravity = -2 (steepest drop)
    var b := preload("res://src/entities/Bullet.tscn").instantiate()
    b.init(0, 0, 0)  # turn_state = 0, stick centered, chopper stationary
    assert_int(b.gravity).is_equal(-2)
    b.queue_free()

func test_bullet_gravity_at_turn_state_5():
    # Full side: gravity = 0 (flies straight)
    var b := preload("res://src/entities/Bullet.tscn").instantiate()
    b.init(5, 0, 0)
    assert_int(b.gravity).is_equal(0)
    b.queue_free()

func test_bullet_velocity_full_side_inherits_chopper_speed():
    # bulletVelocityTable row 5, stick 0 = (26, 0); chopper vx 4 → bullet vx 30
    var b := preload("res://src/entities/Bullet.tscn").instantiate()
    b.init(5, 0, 4)
    assert_int(b.vel_x).is_equal(30)
    b.queue_free()

func test_bullet_velocity_facing_left_negates_table_vx():
    var b := preload("res://src/entities/Bullet.tscn").instantiate()
    b.init(-5, 0, -4)  # full side left, flying left
    assert_int(b.vel_x).is_equal(-30)
    b.queue_free()

func test_5_bullet_cap():
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.airborne = true
    chopper.active_bullets = 5
    assert_bool(chopper.can_fire()).is_false()
    chopper.queue_free()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement Bullet.gd**

```gdscript
extends Area2D
class_name Bullet

# Source-exact ballistics (initBulletPhysics, choplifter.s:7194–7259).
# bulletVelocityTable ($6f8d, 72 bytes): rows by |turn_state| 0–5, columns by |stick_x| 0–5,
# (vx, vy) pairs in source units/frame; source index = 12·|turn| + 2·|stick|.
const VELOCITY_TABLE: Array = [
    [[0, 0],  [0, 0],  [1, 0],  [2, 0],  [2, 0],  [2, 0]],   # |turn| 0 (facing camera)
    [[3, 0],  [3, 0],  [3, 0],  [3, 0],  [3, 1],  [4, 2]],   # |turn| 1
    [[8, 0],  [8, 0],  [8, 0],  [8, 1],  [8, 2],  [8, 2]],   # |turn| 2
    [[12, 0], [12, 0], [12, 1], [12, 2], [11, 2], [10, 2]],  # |turn| 3
    [[16, 0], [16, 1], [16, 1], [16, 1], [15, 2], [14, 2]],  # |turn| 4
    [[26, 0], [26, 2], [26, 4], [26, 6], [25, 8], [25, 10]], # |turn| 5 (full side)
]
# From choplifter.s:7260 — |turn_state| → bullet drop (Euler accumulation, per source).
const GRAVITY_TABLE: Array[int] = [-2, -2, -1, -1, -1, 0]

var gravity: int = 0
var vel_x: int = 0           # signed units/frame; table vx signed by facing + chopper VX inherited
var vel_y: int = 0           # integer units/frame; accumulates gravity each frame
var owner_chopper: Chopper = null

func init(turn_state: int, stick_x: int, chop_vx: int) -> void:
    # turn_state and stick_x are signed as in the source; chop_vx is the chopper's
    # 16-bit X velocity high byte (whole units/frame) — bullets inherit chopper speed.
    var t := clampi(absi(turn_state), 0, 5)
    var s := clampi(absi(stick_x), 0, 5)
    var face := -1 if turn_state < 0 else 1
    vel_x = face * VELOCITY_TABLE[t][s][0] + chop_vx
    # vy sign flips when turn and stick disagree (tilt direction, choplifter.s:7243–7250)
    var tilt_flip := (turn_state < 0) != (stick_x < 0)
    vel_y = -VELOCITY_TABLE[t][s][1] if tilt_flip else VELOCITY_TABLE[t][s][1]
    gravity = GRAVITY_TABLE[t]

func _ready() -> void:
    add_to_group("projectiles")   # sortie-reset cleanup frees this group (Task 33) — R3-M7
    # Hitbox lives on this Area2D root (layer 4 = player_bullets, mask 3|6 = enemies|hostages).
    area_entered.connect(_on_area_entered)

func _physics_process(_delta: float) -> void:
    # Frame-based integer arithmetic (requires the 60Hz locked tick). Positions are source units.
    vel_y += gravity
    position.x += float(vel_x)
    position.y -= float(vel_y)    # vel_y negative → moves down (Godot Y down-positive)
    if position.x < GameState.SRC_BOUNDS_LEFT - 32 \
       or position.x > GameState.SRC_BOUNDS_RIGHT + 32 \
       or position.y < -200 or position.y > 200:
        _despawn()

func _on_area_entered(area: Area2D) -> void:
    var entity := area.owner
    if entity is Tank or entity is Jet or entity is Alien:
        entity.take_hit()
        _despawn()
    elif entity is Hostage:
        entity._die()
        _despawn()
    elif entity is House:
        # R3 house model: shooting a closed house ignites it, RELEASING its occupants
        # (ordnance-vs-house check + igniteHouse, choplifter.s:8605–8616, 8985–8998).
        entity.ignite()
        _despawn()

func _despawn() -> void:
    if owner_chopper:
        owner_chopper.active_bullets -= 1
    queue_free()
```

**Step 4: Add `_fire_bullet` to Chopper.gd**

```gdscript
@export var bullet_scene: PackedScene

func _fire_bullet() -> void:
    if not can_fire():
        return
    active_bullets += 1
    var b: Bullet = bullet_scene.instantiate()
    # Signed turn_state and stick_x, plus whole-unit chopper VX (16-bit velocity high byte),
    # per initBulletPhysics (choplifter.s:7194–7259)
    b.init(turn_state, stick_x, int(vel_x) >> 8)
    b.owner_chopper = self
    b.position = Vector2(pos_x + float(logical_face) * 24.0, -pos_y)
    get_parent().add_child(b)
    AudioManager.play_sfx("bullet_fire")
```

**Step 5: Run test — verify it passes**

**Step 6: Commit**

```bash
git add src/entities/Bullet.gd src/entities/Bullet.tscn \
        src/entities/Chopper.gd tests/unit/test_bullet.gd
git commit -m "feat: bullets — 5-shot cap, turn-state gravity table (source-faithful)"
```

---

## Phase 7: Tank

### Task 16: Tank entity

`DESIGN.md §4.2`: Patrols at a random depth plane (z 1–8). Cannon aims at chopper X/Y each frame. Fires ballistic shells. **Replicate source bug (Mode 1):** in `spawnTankPosV` path (player heading right), `ENTITY_X_H` is always stored as 0.

**Files:**
- Create: `src/entities/Tank.gd` / `Tank.tscn`
- Create: `src/entities/Shell.gd` / `Shell.tscn`
- Test: `tests/unit/test_tank.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_tank_aims_cannon_at_chopper():
    var tank := preload("res://src/entities/Tank.tscn").instantiate()
    add_child(tank)
    var chopper_pos := Vector2(300, 150)
    tank.position = Vector2(100, 200)
    tank.aim_cannon(chopper_pos)
    # Cannon angle should point roughly at chopper
    assert_float(tank.cannon_angle).is_not_equal(0.0)
    tank.queue_free()

func test_shell_has_gravity():
    var shell := preload("res://src/entities/Shell.tscn").instantiate()
    add_child(shell)
    var initial_vy := shell.vel_y
    shell._physics_process(1.0 / 60.0)
    assert_float(shell.vel_y).is_less(initial_vy)  # Falling
    shell.queue_free()

func test_mode1_spawn_bug_replicated():
    # spawnTankPosV: ENTITY_X_H always 0 when player heading right → X pinned to page 0
    var spawn_manager := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(spawn_manager)
    var x := spawn_manager.spawn_tank_pos_v(4724.0)   # base-side chopper X
    # ENTITY_X_H == 0 → X < 256 (within first page)
    assert_float(x).is_less(256.0)
    spawn_manager.queue_free()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement Tank.gd**

```gdscript
extends CharacterBody2D
class_name Tank

const PATROL_SPEED: float = 0.5         # source units/frame
const PATROL_HALF_WIDTH: float = 320.0  # patrol ±320 source units around spawn
const FIRE_INTERVAL: int = 120          # frames between shots (60Hz)

var depth_plane: int = 1   # z_index 1-8
var cannon_angle: float = 0.0
var fire_cooldown: int = 0
var _spawn_x: float = 0.0
var _patrol_dir: int = 1

@export var shell_scene: PackedScene

func _ready() -> void:
    z_index = depth_plane
    _spawn_x = position.x       # source units
    add_to_group("enemies")

func aim_cannon(chopper_world_pos: Vector2) -> void:
    var d := chopper_world_pos - position
    cannon_angle = rad_to_deg(atan2(-d.y, d.x))

func take_hit() -> void:
    AudioManager.play_sfx("explosion")
    queue_free()

func _physics_process(_delta: float) -> void:
    if position.x >= _spawn_x + PATROL_HALF_WIDTH:
        _patrol_dir = -1
    elif position.x <= _spawn_x - PATROL_HALF_WIDTH:
        _patrol_dir = 1
    position.x += PATROL_SPEED * float(_patrol_dir)
    var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
    if chopper:
        aim_cannon(Vector2(chopper.pos_x, -chopper.pos_y))
    fire_cooldown -= 1
    if fire_cooldown <= 0:
        _fire_shell(chopper)
        fire_cooldown = FIRE_INTERVAL

func _fire_shell(chopper: Chopper) -> void:
    if not shell_scene or not chopper:
        return
    var shell: Shell = shell_scene.instantiate()
    shell.position = position
    shell.launch_at(Vector2(chopper.pos_x, -chopper.pos_y))
    get_parent().add_child(shell)
    AudioManager.play_sfx("tank_fire")
```

Tank scene: `CharacterBody2D` root (layer 0 / mask 1) + child `Area2D` `Hitbox` (`collision_layer =
3`, `collision_mask = 4`) so player bullets detect it.

**Step 4: Implement Shell.gd**

```gdscript
extends Area2D
class_name Shell

const SPEED: float = 2.0     # source units/frame horizontal

var vel_x: float = 0.0
var vel_y: int = 0           # source convention: +up; gravity decrements each frame

func _ready() -> void:
    add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
    # Hitbox on this Area2D root (layer 5 = enemy_projectiles, mask 2 = chopper).
    area_entered.connect(_on_area_entered)

func launch_at(target_world_pos: Vector2) -> void:
    var dx := target_world_pos.x - position.x
    vel_x = signf(dx) * SPEED
    vel_y = 3                # initial upward V — source shellLaunchVTable is always 3
                             # (choplifter.s:4560–4565)

func launch_downward() -> void:
    vel_x = 0.0
    vel_y = -3               # straight down (the alien shot reuses the tank-shell entity type)

func _physics_process(_delta: float) -> void:
    vel_y -= 1               # gravity
    position.x += vel_x
    position.y -= float(vel_y)   # +vel_y rises, -vel_y falls (Godot Y down-positive)
    if position.y > 200 or position.x < GameState.SRC_BOUNDS_LEFT - 32 \
       or position.x > GameState.SRC_BOUNDS_RIGHT + 32:
        queue_free()

func _on_area_entered(area: Area2D) -> void:
    if area.owner is Chopper:
        area.owner.die()
        queue_free()
```

**Step 5: Implement SpawnManager.gd with tank spawn bug**

Create `src/world/SpawnManager.gd`:

```gdscript
extends Node
class_name SpawnManager

@export var tank_scene: PackedScene
@export var jet_scene: PackedScene
@export var alien_scene: PackedScene

# Source spawn schedule: FRAME_COUNT AND $2F == 0
# Bitmask $2F = 0b00101111; fires when bits 0,1,2,3,5 are all zero
const SPAWN_BITMASK: int = 0x2F  # Mode 1: faithful non-uniform cadence

var active_tanks: Array = []
var active_jets: Array = []
var active_aliens: Array = []

func tick(frame_count: int) -> void:
    if frame_count & SPAWN_BITMASK == 0:
        _try_spawn_enemy()

func _max_tanks() -> int:  return [1, 2, 2, 2][clampi(GameState.curr_level, 0, 3)]
func _max_jets() -> int:   return [0, 1, 2, 2][clampi(GameState.curr_level, 0, 3)]
func _max_aliens() -> int: return [0, 0, 1, 2][clampi(GameState.curr_level, 0, 3)]

func can_spawn_jet() -> bool:
    return GameState.curr_level >= 1 and active_jets.size() < _max_jets()

func can_spawn_alien() -> bool:
    return GameState.curr_level >= 2 and active_aliens.size() < _max_aliens()

func _try_spawn_enemy() -> void:
    # R3-H2, source-exact (spawnEnemyVehicles, choplifter.s:4582–4618): ONE spawn attempt per $2F
    # tick. A single RNG byte gates the pick — alien needs (rnd & $28) == 0 (level 2+), jet needs
    # bit 7 clear (level 1+), otherwise tank. A failed gate or full cap falls through to the next
    # type. (Round-2 MF3 replaced this with parallel per-type spawns; that over-corrected — it
    # fixed elif starvation but spawned up to 3 enemies per tick, which the source never does.)
    var r := GameState.random_byte()
    if GameState.curr_level >= 2 and (r & 0x28) == 0 and active_aliens.size() < _max_aliens():
        _spawn_alien()
        return
    if GameState.curr_level >= 1 and (r & 0x80) == 0 and active_jets.size() < _max_jets():
        _spawn_jet()
        return
    if active_tanks.size() < _max_tanks():
        _spawn_tank()

# --- Source-faithful tank X selection (choplifter.s spawnTank{Pos,Neg,Med}V) ---
# Branch on the chopper X-velocity high byte:
#   |vx_hi| <= 0x10            → MedV: random behind/ahead (RNG and #$08)
#   vx_hi <  0 (moving left)   → NegV: spawn left of player (X = chop_x - 0xB0)
#   vx_hi >= 0 (moving right)  → PosV: spawn right of player  **but ENTITY_X_H = 0 (bug)**
func select_tank_spawn_x(chopper: Chopper) -> float:
    var vx_hi := chopper.vel_x_hi()
    if vx_hi > -0x11 and vx_hi < 0x11:
        if GameState.random_byte() & 0x08 != 0:
            return spawn_tank_pos_v(chopper.pos_x)
        return spawn_tank_neg_v(chopper.pos_x)
    elif vx_hi < 0:
        return spawn_tank_neg_v(chopper.pos_x)
    else:
        return spawn_tank_pos_v(chopper.pos_x)

func spawn_tank_pos_v(chopper_pos_x: float) -> float:
    # BUG replicated: low byte = (CHOP_POS_X_L + 0xB0) & 0xFF, ENTITY_X_H forced to 0.
    # Result is always pinned to source page 0 (X < 256) regardless of player position.
    return float((int(chopper_pos_x) + 0xB0) & 0xFF)

func spawn_tank_neg_v(chopper_pos_x: float) -> float:
    # Correct: X = CHOP_POS_X - 0xB0 (full 16-bit), clamped to the world.
    return clampf(chopper_pos_x - float(0xB0),
        float(GameState.SRC_BOUNDS_LEFT), float(GameState.SRC_BOUNDS_RIGHT))

func _spawn_tank() -> void:
    if not tank_scene:
        return
    var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
    if not chopper:
        return
    var tank: Tank = tank_scene.instantiate()
    tank.position = Vector2(select_tank_spawn_x(chopper), 0.0)   # ground = altitude 0
    tank.depth_plane = (GameState.random_byte() & 0x07) + 1   # z 1-8
    get_parent().add_child(tank)
    active_tanks.append(tank)
    tank.tree_exiting.connect(func(): active_tanks.erase(tank))
```

**Step 6: Run test — verify it passes**

**Step 7: Commit**

```bash
git add src/entities/Tank.gd src/entities/Tank.tscn \
        src/entities/Shell.gd src/entities/Shell.tscn \
        src/world/SpawnManager.gd src/world/SpawnManager.tscn \
        tests/unit/test_tank.gd
git commit -m "feat: tank — patrol, cannon aim, ballistic shells; SpawnManager with Mode 1 bug replicated"
```

---

## Phase 8: Jet

### Task 17: Jet entity

`DESIGN.md §4.2`: Spawns above chopper altitude. X-velocity driven by bank-angle table. Fires missiles forward, drops bombs on proximity. Level 1+ only.

**Files:**
- Create: `src/entities/Jet.gd` / `Jet.tscn`
- Create: `src/entities/Missile.gd` / `Missile.tscn`
- Create: `src/entities/Bomb.gd` / `Bomb.tscn`
- Test: `tests/unit/test_jet.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_jet_only_spawns_at_level_1_plus():
    GameState.curr_level = 0
    # SpawnManager should not spawn jets at level 0
    var spawn_manager := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(spawn_manager)
    assert_bool(spawn_manager.can_spawn_jet()).is_false()
    GameState.curr_level = 1
    assert_bool(spawn_manager.can_spawn_jet()).is_true()
    spawn_manager.queue_free()
    GameState.reset()

func test_missile_flies_horizontally():
    var missile := preload("res://src/entities/Missile.tscn").instantiate()
    add_child(missile)
    missile.launch(1)  # Facing right
    var initial_y := missile.position.y
    missile._physics_process(0.5)
    assert_float(missile.position.y).is_equal_approx(initial_y, 1.0)  # Level flight
    missile.queue_free()

func test_bomb_falls_with_gravity():
    var bomb := preload("res://src/entities/Bomb.tscn").instantiate()
    add_child(bomb)
    var initial_y := bomb.position.y
    bomb._physics_process(0.5)
    assert_float(bomb.position.y).is_greater(initial_y)  # Falling in Godot
    bomb.queue_free()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement Jet.gd**

```gdscript
extends CharacterBody2D
class_name Jet

const SPEED: float = 2.0            # source units/frame
const FIRE_INTERVAL: int = 180     # frames between missiles (60Hz)
const BOMB_PROXIMITY: float = 150.0  # source units

@export var missile_scene: PackedScene
@export var bomb_scene: PackedScene

var facing: int = 1  # 1 = right, -1 = left
var fire_timer: int = 0
var bank_frame: int = 0  # animation frame for barrel-roll
var _bomb_dropped: bool = false  # one bomb per proximity pass, not one per frame (R3-H6a)

func _ready() -> void:
    add_to_group("enemies")

func _physics_process(_delta: float) -> void:
    position.x += float(facing) * SPEED
    if position.x < GameState.SRC_BOUNDS_LEFT - 64 \
       or position.x > GameState.SRC_BOUNDS_RIGHT + 64:
        queue_free()
        return
    fire_timer -= 1
    if fire_timer <= 0:
        _fire_missile()
        fire_timer = FIRE_INTERVAL
    _check_bomb_drop()

func _fire_missile() -> void:
    if not missile_scene:
        return
    var m: Missile = missile_scene.instantiate()
    m.position = position
    m.launch(facing)
    get_parent().add_child(m)
    AudioManager.play_sfx("jet_fire")

func _check_bomb_drop() -> void:
    var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
    if not chopper:
        return
    if absf(position.x - chopper.pos_x) < BOMB_PROXIMITY:
        if _bomb_dropped or not bomb_scene:
            return                   # R3-H6a: latch — one bomb per pass
        _bomb_dropped = true
        var b: Bomb = bomb_scene.instantiate()
        b.position = position
        get_parent().add_child(b)
    else:
        _bomb_dropped = false        # re-arm once outside the proximity window

func take_hit() -> void:
    AudioManager.play_sfx("explosion")
    queue_free()
```

Jet scene: `CharacterBody2D` root (layer 0 / mask 1) + child `Area2D` `Hitbox` (`collision_layer =
3`, `collision_mask = 4`).

**Step 4: Implement Missile.gd and Bomb.gd**

```gdscript
# Missile.gd — constant horizontal velocity, level flight (source units)
extends Area2D
class_name Missile

const SPEED: float = 3.0   # source units/frame

var dir: int = 1

func _ready() -> void:
    add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
    # layer 5 = enemy_projectiles, mask 2 = chopper
    area_entered.connect(_on_area_entered)

func launch(d: int) -> void:
    dir = d

func _physics_process(_delta: float) -> void:
    position.x += float(dir) * SPEED
    if position.x < GameState.SRC_BOUNDS_LEFT - 64 \
       or position.x > GameState.SRC_BOUNDS_RIGHT + 64:
        queue_free()

func _on_area_entered(area: Area2D) -> void:
    if area.owner is Chopper:
        area.owner.die()
        queue_free()
```

```gdscript
# Bomb.gd — gravity drop from jet altitude (source units)
extends Area2D
class_name Bomb

var vel_y: int = 0   # source units/frame, accumulates downward each frame

func _ready() -> void:
    add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
    area_entered.connect(_on_area_entered)

func _physics_process(_delta: float) -> void:
    vel_y += 1
    position.y += float(vel_y)   # Godot Y down-positive → falls
    if position.y > 200:
        queue_free()

func _on_area_entered(area: Area2D) -> void:
    if area.owner is Chopper:
        area.owner.die()
        queue_free()
```

Missile and Bomb scenes are `Area2D` roots carrying their own `CollisionShape2D`.

**Step 5: `can_spawn_jet` already lives on SpawnManager (Task 16)** — the level-gated cap check
(`curr_level >= 1 and active_jets.size() < _max_jets()`) is defined there; no change needed here.

**Step 6: Run test — verify it passes**

**Step 7: Commit**

```bash
git add src/entities/{Jet,Missile,Bomb}.gd src/entities/{Jet,Missile,Bomb}.tscn \
        tests/unit/test_jet.gd
git commit -m "feat: jet — barrel-roll, missiles, bomb drop; level-gated spawning"
```

---

## Phase 9: Alien

### Task 18: Alien entity

`DESIGN.md §4`: UFO that hunts the player. Accelerates toward chopper (max VX ±5, max VY ±1). Level 2+. Fires downward shells at level 3+ only (Mode 1: `== 3`). Despawns if Δx > ~2 screens. Two-layer animation: static body + sliding mid-section (3-frame cycle, jitter on odd frames).

**Files:**
- Create: `src/entities/Alien.gd` / `Alien.tscn`
- Test: `tests/unit/test_alien.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_alien_accelerates_toward_chopper():
    var alien := preload("res://src/entities/Alien.tscn").instantiate()
    add_child(alien)
    alien.position = Vector2(100, 100)
    alien.vel_x = 0.0; alien.vel_y = 0.0
    alien.chase(Vector2(200, 150))  # Chopper is right and below
    assert_float(alien.vel_x).is_greater(0.0)  # Moved right
    assert_float(alien.vel_y).is_greater(0.0)  # Moved down (Godot Y)
    alien.queue_free()

func test_alien_vel_capped():
    var alien := preload("res://src/entities/Alien.tscn").instantiate()
    add_child(alien)
    alien.vel_x = 100.0; alien.vel_y = 100.0
    alien.chase(Vector2(alien.position.x + 500, alien.position.y))
    assert_float(alien.vel_x).is_less_equal(5.0)
    assert_float(abs(alien.vel_y)).is_less_equal(1.0)
    alien.queue_free()

func test_alien_only_fires_at_level_3_in_mode1():
    GameState.visual_mode = GameState.VisualMode.RETRO
    GameState.curr_level = 2
    var alien := preload("res://src/entities/Alien.tscn").instantiate()
    add_child(alien)
    assert_bool(alien.can_fire()).is_false()
    GameState.curr_level = 3
    assert_bool(alien.can_fire()).is_true()
    alien.queue_free()
    GameState.reset()

func test_alien_despawns_when_far():
    var alien := preload("res://src/entities/Alien.tscn").instantiate()
    add_child(alien)
    alien.position = Vector2(0, 100)
    # ~2 screens = ~960px at 480px viewport
    alien.check_despawn(Vector2(1100, 100))
    assert_bool(alien.is_queued_for_deletion()).is_true()
    alien.queue_free()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement Alien.gd**

```gdscript
extends CharacterBody2D
class_name Alien

const MAX_VX: float = 5.0
const MAX_VY: float = 1.0
const DESPAWN_DIST_X: float = 560.0  # ~2 view widths (2 × 280 source units)
const FIRE_MIN_ALTITUDE: float = 72.0  # R3-H6b: source gates on the ALIEN'S OWN screen Y < $58
                                       # (choplifter.s:9289–9291) — i.e. the alien must be high
                                       # enough. ≈ altitude > 72 source units with the ground at
                                       # screen row ~160. Ledgered Approximation (screen-row map).

var vel_x: float = 0.0
var vel_y: float = 0.0
var mid_section_frame: int = 0  # Reuses ENTITY_DIR field — 0,1,2 cycle
var _physics_frame: int = 0

@export var shell_scene: PackedScene

func _ready() -> void:
    add_to_group("enemies")    # R3-M7 — bullet hits and sortie-reset cleanup resolve via this group

func chase(chopper_pos: Vector2) -> void:
    # Accelerate toward chopper
    vel_x += sign(chopper_pos.x - position.x)
    vel_y += sign(chopper_pos.y - position.y)
    vel_x = clamp(vel_x, -MAX_VX, MAX_VX)
    vel_y = clamp(vel_y, -MAX_VY, MAX_VY)
    # Hover damp: if off-world horizontally, zero VY
    if position.x < GameState.SRC_BOUNDS_LEFT or position.x > GameState.SRC_BOUNDS_RIGHT:
        vel_y = 0.0

func can_fire() -> bool:
    if GameState.visual_mode == GameState.VisualMode.RETRO:
        return GameState.curr_level == 3  # Mode 1: exact equality (source bug)
    else:
        return GameState.curr_level >= 3  # Mode 2: fixed to >= (Tier A fix)

func check_despawn(chopper_pos: Vector2) -> void:
    if abs(position.x - chopper_pos.x) > DESPAWN_DIST_X:
        queue_free()

func _physics_process(_delta: float) -> void:
    _physics_frame += 1
    var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
    if not chopper:
        return
    var cpos := Vector2(chopper.pos_x, -chopper.pos_y)   # source units, world space
    chase(cpos)
    position.x += vel_x
    position.y += vel_y
    check_despawn(cpos)
    _update_mid_section_animation()
    _try_fire(cpos)

func _update_mid_section_animation() -> void:
    # Mid-section cycles 0→1→2; jitters by 1px on odd physics frames
    if _physics_frame % 3 == 0:
        mid_section_frame = (mid_section_frame + 1) % 3

func _try_fire(_chopper_pos: Vector2) -> void:
    # R3-H6b — source gate order (choplifter.s:9280–9296):
    if not can_fire():                       # CURR_LEVEL check (Mode 1: == 3)
        return
    if mid_section_frame != 0:               # only on mid-section animation frame 0 (ENTITY_DIR)
        return
    # (source also requires alienStillAnimating; our mid-section animates continuously)
    if -position.y < FIRE_MIN_ALTITUDE:      # only when the ALIEN itself is high enough (Y < $58)
        return
    if (GameState.random_byte() & 0x48) == 0:  # and #$48 — fires on ~1/4 of eligible frames
        _fire_shell()

func _fire_shell() -> void:
    if not shell_scene:
        return
    var shell: Shell = shell_scene.instantiate()
    shell.position = position
    shell.launch_downward()
    get_parent().add_child(shell)

func take_hit() -> void:
    AudioManager.play_sfx("explosion")
    queue_free()
```

Alien scene: `CharacterBody2D` root (layer 0 / mask 1) + child `Area2D` `Hitbox` (`collision_layer =
3`, `collision_mask = 4`).

**Step 4: Run test — verify it passes**

**Step 5: Commit**

```bash
git add src/entities/Alien.gd src/entities/Alien.tscn tests/unit/test_alien.gd
git commit -m "feat: alien — chase physics (VX±5 VY±1), Mode 1 fire bug replicated, despawn"
```

---

## Phase 10: Sorties & Win/Loss

### Task 19: Death, sortie reset, and end conditions

**Files:**
- Modify: `src/entities/Chopper.gd` (death animation, signal)
- Modify: `src/world/World.gd` (win/loss handling)
- Create: `src/scenes/SortieBanner.gd` / `SortieBanner.tscn`
- Test: `tests/unit/test_sortie.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_death_counts_aboard_as_killed():
    GameState.reset()
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.hostages_aboard = 3
    GameState.on_chopper_death(3)
    assert_int(GameState.hostages_killed).is_equal(3)
    assert_int(GameState.lives_remaining).is_equal(2)
    chopper.queue_free()
    GameState.reset()

func test_loss_when_sorties_exhausted():
    GameState.lives_remaining = 0
    assert_bool(GameState.is_sorties_loss()).is_true()
    GameState.reset()

func test_win_at_64_rescues():
    GameState.total_rescues = 64
    assert_bool(GameState.is_victory()).is_true()
    GameState.reset()
```

**Step 2: Run test — verify it fails**

**Step 3: Add death handling to Chopper.gd**

```gdscript
signal chopper_died
signal chopper_landed

const DEATH_DURATION: float = 1.5  # Seconds for explosion animation

func die() -> void:
    if dying:
        return
    dying = true
    death_timer = 0
    GameState.on_chopper_death(hostages_aboard)
    AudioManager.play_sfx("explosion")
    # Play explosion animation, then emit signal
    await get_tree().create_timer(DEATH_DURATION).timeout
    emit_signal("chopper_died")
```

**Step 4: Handle signals in World.gd**

```gdscript
func _on_chopper_died() -> void:
    # victory is signalled separately by HostageManager (World.victory_achieved) — not re-checked here
    if GameState.is_mission_loss():
        _start_loss("hostages")
    elif GameState.is_sorties_loss():
        _start_loss("sorties")
    else:
        # R3-C3: survive the scene reload — serialize field hostages into GameState (the source
        # hostageTable persists in RAM across deaths; scene nodes do not).
        hostage_manager.serialize_field_hostages()
        await get_tree().create_timer(1.0).timeout
        SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")

func _start_victory() -> void:
    GameState.input_locked = true
    AudioManager.play_sfx("ui_confirm")  # Victory sting placeholder
    await get_tree().create_timer(3.0).timeout
    SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")

func _start_loss(reason: String) -> void:
    GameState.input_locked = true
    await get_tree().create_timer(2.0).timeout
    SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")

func _check_end_conditions() -> void:
    if GameState.is_victory():
        _start_victory()
    elif GameState.is_mission_loss():
        _start_loss("hostages")
```

**Step 5: Create SortieBanner.tscn**

Simple full-screen scene showing sortie number and hostage counts. Auto-advances after 2 seconds:

```gdscript
# SortieBanner.gd
extends Control

@onready var label: Label = $Label

func _ready() -> void:
    label.text = "Sortie %d\nRescued: %d  Killed: %d" % [
        GameState.sortie + 1, GameState.total_rescues, GameState.hostages_killed
    ]
    await get_tree().create_timer(2.0).timeout
    SceneTransition.transition_to("res://src/world/World.tscn")
```

**Step 6: Run test — verify it passes**

**Step 7: Commit**

```bash
git add src/entities/Chopper.gd src/world/World.gd \
        src/scenes/SortieBanner.gd src/scenes/SortieBanner.tscn \
        tests/unit/test_sortie.gd
git commit -m "feat: chopper death, sortie reset, win/loss transitions"
```

---

### Task 19b: Production-path integration & physics golden-trace tests (MF1)

These are the three **Definition of Done** gates that exercise the real wiring rather than isolated
helpers. They must run headless under the GDUnit4 runner.

**Files:**
- Test: `tests/integration/test_rescue_loop.gd`
- Test: `tests/integration/test_physics_golden_trace.gd` (also hosts the input-path landing gate)

**Step 1: Production-path rescue-loop integration test**

Drives a *real* `World` scene graph — `HostageManager`, `House`, `Chopper`, `Base` — through one
full rescue with no shortcuts. The test advances physics frames and asserts the end-to-end effect on
`GameState`.

```gdscript
extends GdUnitTestSuite

# Boots the actual World scene and runs the full house→run→board→deliver→rescue loop.
func test_full_rescue_increments_total_rescues() -> void:
    GameState.reset()
    var world: World = preload("res://src/world/World.tscn").instantiate()
    add_child(world)
    await get_tree().physics_frame

    var gs := GameState
    var start_rescues := gs.total_rescues

    # R3 house model: open only house 0 and drop the game-start house-3 squad so every spawn
    # lands within the chopper's detect range — keeps the test deterministic instead of relying
    # on the RNG to pick house 0 before the active cap fills. (1 = ignited/open, 0 = closed.)
    gs.house_states = [1, 0, 0, 0]
    gs.hostages_in_houses = [16, 16, 16, 16]
    gs.hostages_left = 64
    gs.hostages_active = 0
    gs.field_hostage_records.clear()

    # 1) Land the chopper at a field house so a hostage spawns and runs to it.
    world.chopper.pos_x = float(gs.HOUSE_SRC_X[0])
    world.chopper.pos_y = 0.0
    world.chopper.vel_x = 0
    world.chopper.vel_y = 0
    world.chopper.over_base = false   # field landing, not the base

    # Pump frames until a hostage spawns from the house, runs over, and boards.
    var boarded := false
    for _i in range(1200):  # ≤20 s @60Hz
        await get_tree().physics_frame
        if world.chopper.hostages_aboard >= 1:
            boarded = true
            break
    assert_bool(boarded).is_true()

    # 2) Fly to the base and land; the HostageManager must unload via a base-runner.
    world.chopper.pos_x = float(gs.SRC_BASE_X)
    world.chopper.pos_y = 0.0
    world.chopper.vel_x = 0
    world.chopper.vel_y = 0
    world.chopper.over_base = true

    var delivered := false
    for _i in range(1200):
        await get_tree().physics_frame
        if gs.total_rescues > start_rescues:
            delivered = true
            break
    assert_bool(delivered).is_true()

    world.queue_free()
    GameState.reset()
```

> **Why this matters (MF1):** unit tests call `HostageManager._unload_one()` directly and would pass
> even if `World` never instantiated or ticked the manager. This test fails if any wiring is missing
> — the exact class of regression the per-task tests cannot catch.

**Step 2: Physics golden-trace test**

Records a fixed input sequence and asserts the chopper reproduces an expected per-frame
velocity/position trace within tolerance. The expected values are the golden traces already asserted
in Task 8 (thrust → `vel_y_hi` `[3,4,5,6,6]`; gravity → `[-1,-2,-2]`), here verified through the full
`_physics_process` path (input → integration) rather than the isolated integrator.

```gdscript
extends GdUnitTestSuite

func test_thrust_trace_through_physics_process() -> void:
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_y = 100.0   # airborne so ground checks don't interfere
    chopper.vel_y = 0

    Input.action_press("thrust_up")   # simulate holding thrust through the real input path
    var trace := []
    for _i in range(5):
        chopper._physics_process(1.0 / 60.0)
        trace.append(chopper.vel_y_hi())
    Input.action_release("thrust_up")
    assert_array(trace).is_equal([3, 4, 5, 6, 6])
    chopper.queue_free()

func test_gravity_trace_through_physics_process() -> void:
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_y = 100.0
    chopper.vel_y = 0

    var trace := []   # no thrust held → gravity ease-down
    for _i in range(3):
        chopper._physics_process(1.0 / 60.0)
        trace.append(chopper.vel_y_hi())
    assert_array(trace).is_equal([-1, -2, -2])
    chopper.queue_free()

func test_descend_and_land_via_input_path() -> void:
    # Third DoD gate (R3-C1 / R3-H8): the chopper must be able to LAND using only real input
    # actions — the other two gates bypass the input layer and stay green even when no control
    # path can reach MIN_VY. Descend (index 0, target −10) passes vy_hi ≤ −5 within 2 frames.
    var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
    add_child(chopper)
    chopper.pos_y = 40.0
    chopper.airborne = true
    chopper.vel_x = 0
    chopper.vel_y = 0

    Input.action_press("descend")
    for _i in range(120):
        chopper._physics_process(1.0 / 60.0)
        if chopper.landed:
            break
    Input.action_release("descend")
    assert_bool(chopper.landed).is_true()
    chopper.queue_free()
```

> Driving via `Input.action_press/release` exercises `_handle_input()` → integration exactly as it
> runs in-game, so the trace validates the production path, not a test-only shortcut.

**Step 3: Run both tests — verify they pass**

**Step 4: Commit**

```bash
git add tests/integration/test_rescue_loop.gd tests/integration/test_physics_golden_trace.gd
git commit -m "test: production-path rescue-loop + physics golden-trace integration gates (MF1)"
```

---

## Phase 11: HUD & UI Scenes

### Task 20: In-game HUD

**Files:**
- Create: `src/ui/HUD.gd` / `HUD.tscn`
- Test: `tests/unit/test_hud.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_hud_updates_on_rescue():
    var hud := preload("res://src/ui/HUD.tscn").instantiate()
    add_child(hud)
    GameState.total_rescues = 5
    hud.refresh()
    assert_str(hud.get_rescued_text()).is_equal("05")
    hud.queue_free()
    GameState.reset()
```

**Step 2: Run test — verify it fails**

**Step 3: Implement HUD.gd**

```gdscript
extends CanvasLayer
class_name HUD

@onready var rescued_label: Label = $Panel/Rescued
@onready var killed_label: Label = $Panel/Killed
@onready var aboard_label: Label = $Panel/Aboard
@onready var lives_container: HBoxContainer = $Panel/Lives

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS  # Visible during pause
    refresh()

func _process(_delta: float) -> void:
    refresh()

func refresh() -> void:
    rescued_label.text = "%02d" % GameState.total_rescues
    killed_label.text = "%02d" % GameState.hostages_killed
    aboard_label.text = "%02d" % GameState.hostages_loaded
    _update_lives()

func get_rescued_text() -> String:
    return rescued_label.text

func _update_lives() -> void:
    for i in range(lives_container.get_child_count()):
        var icon := lives_container.get_child(i) as TextureRect
        if icon:
            icon.modulate.a = 1.0 if i < GameState.lives_remaining else 0.3
```

**Step 4: Create HUD.tscn**

In Godot editor: `CanvasLayer` root → `Panel` child → `HBoxContainer` with labels for `Rescued`, `Killed`, `Aboard`, plus `HBoxContainer` named `Lives` with 3 `TextureRect` helicopter icons.

**Step 5: Run test — verify it passes**

**Step 6: Commit**

```bash
git add src/ui/HUD.gd src/ui/HUD.tscn tests/unit/test_hud.gd
git commit -m "feat: HUD — rescued/killed/aboard counters + lives display"
```

---

### Task 20b: Pause menu

The v0.1 playability checklist requires pause to work. This task must be completed before v0.1.

**Files:**
- Create: `src/ui/PauseMenu.gd` / `PauseMenu.tscn`
- Modify: `src/world/World.gd` (wire `pause` action)

**Step 1: Implement PauseMenu.gd**

```gdscript
extends CanvasLayer

@onready var resume_button: Button = $Panel/VBox/Resume
@onready var quit_button: Button = $Panel/VBox/QuitToMenu

func _ready() -> void:
    layer = 50  # Above HUD (layer 0), below SceneTransition (layer 100)
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS

func show_pause() -> void:
    visible = true
    get_tree().paused = true
    resume_button.grab_focus()

func hide_pause() -> void:
    visible = false
    get_tree().paused = false

func _on_resume_pressed() -> void:
    hide_pause()

func _on_quit_to_menu_pressed() -> void:
    get_tree().paused = false
    GameState.input_locked = false
    SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")
```

**Step 2: Create PauseMenu.tscn**

In Godot editor: `CanvasLayer` root → `Panel` child (centered, ~200×120px) →
`VBoxContainer` → two `Button` nodes: `Resume` and `QuitToMenu`. Attach `PauseMenu.gd`.

**Step 3: Wire `pause` action in World.gd**

Add to `World.gd`:

```gdscript
@onready var pause_menu: PauseMenu = $PauseMenu

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        if pause_menu.visible:
            pause_menu.hide_pause()
        else:
            pause_menu.show_pause()
```

Add `PauseMenu.tscn` as a child of `World.tscn` (name: `PauseMenu`).

**Step 4: Ensure all nodes that must run during pause set `process_mode`**

- `HUD.gd`: already sets `PROCESS_MODE_ALWAYS`
- `AudioManager.gd`: already sets `PROCESS_MODE_ALWAYS`
- `SceneTransition.gd`: already sets `PROCESS_MODE_ALWAYS`
- `PauseMenu.gd`: sets `PROCESS_MODE_ALWAYS` (above)

**Step 5: Commit**

```bash
git add src/ui/PauseMenu.gd src/ui/PauseMenu.tscn src/world/World.gd
git commit -m "feat: pause menu — resume and quit-to-menu; wired to pause action"
```

---

### Task 21: Main Menu and Boot scenes

**Files:**
- Create: `src/scenes/Boot.gd` / `Boot.tscn`
- Create: `src/scenes/MainMenu.gd` / `MainMenu.tscn`

**Step 1: Implement Boot.gd**

```gdscript
extends Node

func _ready() -> void:
    # Load settings (already done by Settings autoload _ready)
    GameState.visual_mode = Settings.selected_visual_mode
    GameState.gameplay_variant = Settings.selected_variant
    await get_tree().create_timer(1.5).timeout  # Boot logo display
    SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")
```

**Step 2: Implement MainMenu.gd**

```gdscript
extends Control

@onready var play_button: Button = $Panel/VBox/Play
@onready var settings_button: Button = $Panel/VBox/Settings
@onready var quit_button: Button = $Panel/VBox/Quit
@onready var mode_label: Label = $Panel/ModeLabel

func _ready() -> void:
    # Hide Quit on web export
    quit_button.visible = OS.get_name() != "Web"
    _update_mode_display()
    play_button.grab_focus()

func _on_play_pressed() -> void:
    GameState.reset()
    if GameState.visual_mode == GameState.VisualMode.RETRO:
        SceneTransition.transition_to("res://src/scenes/RetroTitle.tscn")
    else:
        SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")

func _on_quit_pressed() -> void:
    get_tree().quit()

func _update_mode_display() -> void:
    var names := ["Retro", "Modern", "Hi-Res"]
    mode_label.text = names[GameState.visual_mode - 1]
```

**Step 3: Create both .tscn files in Godot editor**

Boot scene: `Node` root, `AnimationPlayer` or simple `Label` for logo splash.
MainMenu scene: `Control` root, `Panel`, `VBoxContainer` with buttons.

**Step 4: Commit**

```bash
git add src/scenes/Boot.gd src/scenes/Boot.tscn \
        src/scenes/MainMenu.gd src/scenes/MainMenu.tscn
git commit -m "feat: Boot and MainMenu scenes — mode selector, quit hidden on web"
```

---

### Task 22: Retro Title Sequence

`DESIGN.md §10.4` and `§11.4`: Broderbund card → logo animation → mission card → demo attract. Any input skips to first sortie.

**Files:**
- Create: `src/scenes/RetroTitle.gd` / `RetroTitle.tscn`
- Create: `res://data/demo_input.tres` (Resource array of `{action, duration_frames}`)

**Step 1: Implement RetroTitle.gd**

```gdscript
extends Control

enum Phase { BRODERBUND = 0, LOGO = 1, MISSION = 2, DEMO = 3 }

# Ordered array used by _advance_phase — avoids invalid .values() call on GDScript 4 enum
const PHASE_ORDER: Array = [Phase.BRODERBUND, Phase.LOGO, Phase.MISSION, Phase.DEMO]

var phase: Phase = Phase.BRODERBUND
var phase_timer: float = 0.0

const PHASE_DURATIONS: Dictionary = {
    Phase.BRODERBUND: 2.0,
    Phase.LOGO: 3.0,
    Phase.MISSION: 2.0,
}
# LF1: these durations are APPROXIMATE — the original Apple II title timings were not
# reverse-engineered from choplifter.s. Tune by eye against reference footage; classify the
# title sequence as "Approximation" in the Fidelity Ledger, not "Exact".

# NOTE: Demo/attract input-replay is out of scope for v0.1.
# Phase.DEMO currently shows a live uncontrolled game (cosmetically acceptable for v0.1).
# A recorded-input playback system will be designed and added in v1.0 polish.

func _process(delta: float) -> void:
    # Any real input → go to first sortie. This must keep working DURING the demo phase (R3-M6) —
    # the v0.1 demo is a live uncontrolled game, so there is no synthetic input to collide with.
    # When recorded-input replay lands (v1.0), replayed actions must bypass this check.
    if Input.is_anything_pressed():
        _go_to_sortie()
        return
    phase_timer += delta
    match phase:
        Phase.BRODERBUND:
            if phase_timer >= PHASE_DURATIONS[Phase.BRODERBUND]:
                _advance_phase()
        Phase.LOGO:
            if phase_timer >= PHASE_DURATIONS[Phase.LOGO]:
                _advance_phase()
        Phase.MISSION:
            if phase_timer >= PHASE_DURATIONS[Phase.MISSION]:
                phase = Phase.DEMO
                GameState.demo_mode = true
                phase_timer = 0.0

func _advance_phase() -> void:
    var idx := PHASE_ORDER.find(int(phase))
    if idx >= 0 and idx + 1 < PHASE_ORDER.size():
        phase = PHASE_ORDER[idx + 1] as Phase
    phase_timer = 0.0

func _go_to_sortie() -> void:
    GameState.demo_mode = false
    SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")
```

**Step 2: Commit**

```bash
git add src/scenes/RetroTitle.gd src/scenes/RetroTitle.tscn data/
git commit -m "feat: Retro title sequence — Broderbund card, logo, mission card, demo attract"
```

---

## Phase 12: Asset Pipelines

### Task 23: SFX synthesis pipeline

`ASSET_PIPELINE.md §4`: All SFX synthesized via numpy/scipy → ffmpeg → OGG.

**Files:**
- Create: `src/tools/config/sfx_spec.py`
- Create: `src/tools/generate_sfx.py`
- Test: `tests/test_sfx_pipeline.py` (pytest)

**Step 1: Install dependencies**

```bash
sudo apt install ffmpeg python3-numpy python3-scipy
python3 -c "import numpy, scipy; print('OK')"
```

**Step 2: Write the failing test**

Create `tests/test_sfx_pipeline.py`:

```python
import subprocess
import sys
from pathlib import Path

def test_sfx_spec_has_required_keys():
    sys.path.insert(0, "src/tools/config")
    from sfx_spec import SFX_SPECS
    required_sfx = [
        "bullet_fire", "explosion", "hostage_board", "hostage_death",
        "landing", "tank_fire", "jet_fire", "engine_loop",
        "ui_select", "ui_confirm"
    ]
    for sfx in required_sfx:
        assert sfx in SFX_SPECS, f"Missing SFX spec: {sfx}"

def test_generate_sfx_produces_ogg(tmp_path, monkeypatch):
    monkeypatch.setenv("SFX_OUT_DIR", str(tmp_path))
    result = subprocess.run(
        ["python3", "src/tools/generate_sfx.py", "--sfx", "bullet_fire", "--out-dir", str(tmp_path)],
        capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "bullet_fire.ogg").exists()
```

**Step 3: Run test — verify it fails**

```bash
python3 -m pytest tests/test_sfx_pipeline.py -v
```

Expected: FAIL — `sfx_spec` not found.

**Step 4: Create sfx_spec.py**

Create `src/tools/config/sfx_spec.py`:

```python
"""
SFX parameter specifications for generate_sfx.py.
Each entry defines waveform synthesis parameters.
All values are tuning targets — adjust during playtest.
"""

SFX_SPECS = {
    "bullet_fire": {
        "waveform": "square",
        "freq_start": 880, "freq_end": 440,
        "duration": 0.08,
        "amplitude_envelope": "decay",
        "noise_mix": 0.05,
    },
    "bullet_impact": {
        "waveform": "noise",
        "freq_start": 400, "freq_end": 200,
        "duration": 0.05,
        "amplitude_envelope": "decay",
        "noise_mix": 0.8,
    },
    "tank_fire": {
        "waveform": "square",
        "freq_start": 120, "freq_end": 60,
        "duration": 0.15,
        "amplitude_envelope": "decay",
        "noise_mix": 0.4,
        "lowpass_hz": 400,
    },
    "jet_fire": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 880,
        "duration": 0.12,
        "amplitude_envelope": "decay",
        "noise_mix": 0.1,
    },
    "bomb_drop": {
        "waveform": "sine",
        "freq_start": 600, "freq_end": 200,
        "duration": 0.2,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
    },
    "explosion": {
        "waveform": "noise",
        "freq_start": 200, "freq_end": 50,
        "duration": 0.4,
        "amplitude_envelope": "exp_decay",
        "noise_mix": 1.0,
        "lowpass_hz": 800,
    },
    "explosion_small": {
        "waveform": "noise",
        "freq_start": 300, "freq_end": 100,
        "duration": 0.2,
        "amplitude_envelope": "exp_decay",
        "noise_mix": 1.0,
        "lowpass_hz": 1000,
    },
    "hostage_board": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 880,
        "duration": 0.15,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
        "notes": [440, 554, 659],  # Ascending 3-note beep
    },
    "hostage_death": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 293,
        "duration": 0.2,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
        "notes": [440, 369],  # Descending minor 3rd
    },
    "landing": {
        "waveform": "noise",
        "freq_start": 300, "freq_end": 100,
        "duration": 0.12,
        "amplitude_envelope": "exp_decay",
        "noise_mix": 0.9,
        "lowpass_hz": 500,
    },
    "engine_loop": {
        "waveform": "square",
        "freq_start": 80, "freq_end": 80,
        "duration": 1.0,
        "amplitude_envelope": "flat",
        "noise_mix": 0.15,
        "loop": True,
        "lowpass_hz": 300,
    },
    "alien_crackle_0": {
        "waveform": "noise",
        "freq_start": 800, "freq_end": 800,
        "duration": 0.1,
        "amplitude_envelope": "flat",
        "noise_mix": 1.0,
        "highpass_hz": 600,
    },
    "alien_crackle_1": {
        "waveform": "noise",
        "freq_start": 1200, "freq_end": 1200,
        "duration": 0.1,
        "amplitude_envelope": "flat",
        "noise_mix": 1.0,
        "highpass_hz": 900,
    },
    "alien_crackle_2": {
        "waveform": "noise",
        "freq_start": 1600, "freq_end": 1600,
        "duration": 0.1,
        "amplitude_envelope": "flat",
        "noise_mix": 1.0,
        "highpass_hz": 1200,
    },
    "fire_telegraph": {
        "waveform": "square",
        "freq_start": 300, "freq_end": 600,
        "duration": 0.3,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
    },
    "stranded_warning": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 440,
        "duration": 0.15,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
    },
    "fuel_low": {
        "waveform": "square",
        "freq_start": 200, "freq_end": 200,
        "duration": 0.2,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
    },
    "bounce": {
        "waveform": "noise",
        "freq_start": 400, "freq_end": 150,
        "duration": 0.08,
        "amplitude_envelope": "exp_decay",
        "noise_mix": 0.7,
        "lowpass_hz": 600,
    },
    "ui_select": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 440,
        "duration": 0.04,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
    },
    "ui_confirm": {
        "waveform": "square",
        "freq_start": 440, "freq_end": 550,
        "duration": 0.12,
        "amplitude_envelope": "decay",
        "noise_mix": 0.0,
        "notes": [440, 550],
    },
}
```

**Step 5: Create generate_sfx.py**

Create `src/tools/generate_sfx.py`:

```python
#!/usr/bin/env python3
"""
SFX synthesis pipeline for Choplifter Clone.
Synthesizes WAV from parameters using numpy/scipy, converts to OGG via ffmpeg.

Usage:
    python3 src/tools/generate_sfx.py                     # Generate all SFX
    python3 src/tools/generate_sfx.py --sfx bullet_fire   # Single SFX
    python3 src/tools/generate_sfx.py --sfx bullet_fire --preview  # WAV preview only
"""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal as scipy_signal

# Resolve paths relative to project root
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
SFX_OUT_DIR = Path(os.environ.get("SFX_OUT_DIR", str(PROJECT_ROOT / "assets" / "audio" / "sfx")))
PREVIEW_DIR = SFX_OUT_DIR / "_preview"

SAMPLE_RATE = 44100

# Import spec from config
import sys
sys.path.insert(0, str(PROJECT_ROOT / "src" / "tools" / "config"))
from sfx_spec import SFX_SPECS


def synthesize(spec: dict) -> np.ndarray:
    """Synthesize waveform from spec parameters. Returns float32 array [-1, 1]."""
    duration = spec.get("duration", 0.1)
    freq_start = spec.get("freq_start", 440)
    freq_end = spec.get("freq_end", freq_start)
    waveform_type = spec.get("waveform", "square")
    noise_mix = spec.get("noise_mix", 0.0)
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)

    # Frequency sweep
    freq = np.linspace(freq_start, freq_end, len(t))
    phase = np.cumsum(2 * np.pi * freq / SAMPLE_RATE)

    # Waveform
    if waveform_type == "square":
        wave = np.sign(np.sin(phase))
    elif waveform_type == "sine":
        wave = np.sin(phase)
    elif waveform_type == "noise":
        wave = np.random.uniform(-1, 1, len(t))
    else:
        wave = np.sin(phase)

    # Noise mix
    if 0 < noise_mix < 1:
        noise = np.random.uniform(-1, 1, len(t))
        wave = wave * (1 - noise_mix) + noise * noise_mix
    elif noise_mix >= 1:
        wave = np.random.uniform(-1, 1, len(t))

    # Amplitude envelope
    envelope_type = spec.get("amplitude_envelope", "decay")
    if envelope_type == "decay":
        envelope = np.linspace(1.0, 0.0, len(t))
    elif envelope_type == "exp_decay":
        envelope = np.exp(-5.0 * t / duration)
    elif envelope_type == "flat":
        envelope = np.ones(len(t))
    else:
        envelope = np.ones(len(t))
    wave = wave * envelope

    # Lowpass filter
    if "lowpass_hz" in spec:
        sos = scipy_signal.butter(4, spec["lowpass_hz"], fs=SAMPLE_RATE, btype="low", output="sos")
        wave = scipy_signal.sosfilt(sos, wave)

    # Highpass filter
    if "highpass_hz" in spec:
        sos = scipy_signal.butter(4, spec["highpass_hz"], fs=SAMPLE_RATE, btype="high", output="sos")
        wave = scipy_signal.sosfilt(sos, wave)

    # Normalize
    peak = np.max(np.abs(wave))
    if peak > 0:
        wave = wave / peak * 0.9

    return wave.astype(np.float32)


def write_wav(samples: np.ndarray, path: Path) -> None:
    """Write float32 samples to WAV file."""
    import wave, struct
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(int_samples.tobytes())


def convert_to_ogg(wav_path: Path, ogg_path: Path) -> None:
    """Convert WAV to OGG using ffmpeg."""
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "5", str(ogg_path)],
        check=True, capture_output=True
    )


def generate_sfx(name: str, preview: bool = False, out_dir: Path = SFX_OUT_DIR) -> None:
    if name not in SFX_SPECS:
        print(f"ERROR: Unknown SFX: {name}")
        return
    spec = SFX_SPECS[name]
    # Deterministic noise so repeated builds produce byte-identical audio (reproducibility).
    import zlib
    np.random.seed(zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF)
    samples = synthesize(spec)
    out_dir.mkdir(parents=True, exist_ok=True)

    if preview:
        preview_dir = out_dir / "_preview"
        preview_dir.mkdir(parents=True, exist_ok=True)
        wav_path = preview_dir / f"{name}.wav"
        write_wav(samples, wav_path)
        print(f"Preview: {wav_path}")
        return

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        write_wav(samples, tmp_path)
        ogg_path = out_dir / f"{name}.ogg"
        convert_to_ogg(tmp_path, ogg_path)
        print(f"Generated: {ogg_path}")
    finally:
        tmp_path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description="Generate Choplifter SFX")
    parser.add_argument("--sfx", help="Single SFX name to generate")
    parser.add_argument("--preview", action="store_true", help="Output WAV preview only")
    parser.add_argument("--out-dir", type=Path, default=SFX_OUT_DIR)
    args = parser.parse_args()

    if args.sfx:
        generate_sfx(args.sfx, preview=args.preview, out_dir=args.out_dir)
    else:
        for name in SFX_SPECS:
            generate_sfx(name, out_dir=args.out_dir)


if __name__ == "__main__":
    main()
```

**Step 6: Run test — verify it passes**

```bash
python3 -m pytest tests/test_sfx_pipeline.py -v
```

Expected: PASS.

**Step 7: Generate all SFX**

```bash
python3 src/tools/generate_sfx.py
ls assets/audio/sfx/
```

Expected: 20 `.ogg` files.

**Step 8: Commit**

```bash
git add src/tools/generate_sfx.py src/tools/config/sfx_spec.py \
        assets/audio/sfx/ tests/test_sfx_pipeline.py
git commit -m "feat: SFX synthesis pipeline — 20 OGG files from numpy/scipy waveforms"
```

---

### Task 24: Wire SFX to game events

**Files:**
- Modify: `src/entities/Chopper.gd`, `Tank.gd`, `Jet.gd`, `Alien.gd`, `Hostage.gd`

> All `AudioManager.play_sfx("name")` calls are already in the entity code above.
> This task ensures they are verified against the generated OGG files.

**Step 1: Audit SFX calls**

```bash
grep -r "play_sfx" src/ --include="*.gd" | sort
```

Verify every string matches a key in `SFX_SPECS`.

**Step 1b: Wire sustained-loop lifecycle (engine, alien crackle)**

One-shot SFX use `play_sfx`; sustained sounds use the loop lifecycle so they start and stop with the
emitter (no leaked voices on death/despawn):

- `Chopper.gd`: `AudioManager.start_loop("engine_loop")` at the end of `_ready()`;
  `AudioManager.stop_loop("engine_loop")` inside `die()` (before the await) and on pause/quit.
- `Alien.gd`: `AudioManager.start_loop("alien_crackle_0")` in `_ready()`;
  `AudioManager.stop_loop("alien_crackle_0")` in `take_hit()` and just before any `queue_free()`
  in `check_despawn()`. (The 3-frame crackle variants are cycled by the visual mid-section
  animation; the audio loop itself is a single sustained voice.)

> Because only one Chopper exists and aliens stop their loop on removal, `_loop_players` holds at
> most a handful of voices. `stop_loop` is idempotent, so death/despawn ordering is safe.

**Step 2: Verify all SFX files exist**

```bash
python3 -c "
import json
from pathlib import Path
specs = Path('src/tools/config/sfx_spec.py').read_text()
exec(specs)
for name in SFX_SPECS:
    ogg = Path('assets/audio/sfx') / (name + '.ogg')
    status = 'OK' if ogg.exists() else 'MISSING'
    print(f'{status}: {name}')
"
```

Expected: all OK.

**Step 3: Commit**

```bash
git commit -am "chore: verify SFX wiring — all play_sfx calls match generated files"
```

---

## v0.1 Playability Check

At this point the game should be fully playable in Mode 1 (Retro). Verify manually:

**Step 1: Run the game**

Open Godot → `F5` (Run Project).

**Checklist:**
- [ ] Boot → Main Menu appears
- [ ] Play → Retro → Title sequence plays; any key advances to Sortie Banner
- [ ] Sortie Banner shows, auto-advances to World
- [ ] Chopper spawns at base, floats with gravity, thrust works
- [ ] Descend (S/Down) accelerates downward; touchdown registers only while the X input is centered
- [ ] Chopper rotates through 11 turn frames; logical_face flips instantly
- [ ] Camera scrolls with asymmetric lead (further ahead when flying right); sky and ground line are framed correctly (playfield on screen)
- [ ] Mountains parallax at ~50% speed
- [ ] Chopper lands on base; landing resets vertical velocity
- [ ] House 3 starts open with 8 hostages outside; shooting a closed house ignites it and hostages stream out
- [ ] Hostages wave, run, board when chopper lands nearby
- [ ] Field hostages survive a chopper death (still present after the sortie reload)
- [ ] Delivering hostages to base increments Rescued counter
- [ ] Firing bullets: max 5 on screen; gravity varies with turn state
- [ ] Tanks spawn, patrol, aim cannon, fire shells
- [ ] Jets spawn at level 1+, fire missiles and bombs
- [ ] Aliens spawn at level 2+, chase player, fire at level 3 only
- [ ] Chopper death counts aboard hostages as killed; sortie banner shown if lives remain
- [ ] 3rd death → main menu with loss
- [ ] 64 rescues → victory → main menu
- [ ] HUD counters update in real time
- [ ] Pause (Escape) works; resume, quit-to-menu work
- [ ] SFX audible for: bullet fire, explosion, hostage board/death, landing

**Step 2: Commit milestone**

```bash
git tag v0.1-alpha
git commit --allow-empty -m "milestone: v0.1 — Mode 1 Retro fully playable"
```

---

## Phase 13: v0.2 — Tier A Bug Fixes

> Mode 1 is still the only mode. These fixes apply only in `visual_mode >= MODERN`.
> Mode 1 is deliberately left broken in the ways the original was.

### Task 25: Tank spawn distribution fix (Tier A)

`ENHANCED_GAMEPLAY.md §3.1`: The `spawnTankPosV` path bug (ENTITY_X_H always 0) is fixed only when `gameplay_variant >= STANDARD` and `visual_mode >= MODERN`.

**Files:**
- Modify: `src/world/SpawnManager.gd`
- Test: `tests/unit/test_tier_a_tank_spawn.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_mode2_standard_fixes_tank_spawn():
    GameState.visual_mode = GameState.VisualMode.MODERN
    GameState.gameplay_variant = GameState.GameplayVariant.STANDARD
    var spawn_manager := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(spawn_manager)
    # With the fix, X should NOT always be in page 0
    var positions := []
    for i in range(20):
        positions.append(spawn_manager.spawn_tank_pos_v(2000.0))
    var all_in_page_0 := positions.all(func(x): return x < 256)
    assert_bool(all_in_page_0).is_false()  # Fixed: spread across world
    spawn_manager.queue_free()
    GameState.reset()

func test_mode1_replicates_tank_spawn_bug():
    GameState.visual_mode = GameState.VisualMode.RETRO
    var spawn_manager := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(spawn_manager)
    for i in range(10):
        var x := spawn_manager.spawn_tank_pos_v(2000.0)
        assert_float(x).is_less(256.0)  # Bug replicated: always page 0
    spawn_manager.queue_free()
    GameState.reset()
```

**Step 2: Run test — verify it fails**

**Step 3: Update `spawn_tank_pos_v` in SpawnManager.gd**

```gdscript
func spawn_tank_pos_v(chopper_pos_x: float) -> float:
    if GameState.visual_mode >= GameState.VisualMode.MODERN \
       and GameState.gameplay_variant >= GameState.GameplayVariant.STANDARD:
        # Tier A fix: spread X around the chopper instead of pinning to page 0.
        var offset := (GameState.random_byte() - 128) * 5   # ±640 source units
        return clampf(chopper_pos_x + float(offset),
            float(GameState.SRC_BOUNDS_LEFT), float(GameState.SRC_BOUNDS_RIGHT))
    # Mode 1 faithful bug: low byte = (CHOP_POS_X_L + 0xB0) & 0xFF, ENTITY_X_H forced to 0.
    return float((int(chopper_pos_x) + 0xB0) & 0xFF)
```

**Step 4: Run test — verify it passes**

**Step 5: Commit**

```bash
git add src/world/SpawnManager.gd tests/unit/test_tier_a_tank_spawn.gd
git commit -m "feat(tier-a): fix tank spawn distribution in Mode 2+ Standard — Mode 1 bug preserved"
```

---

### Task 26: Alien fire level fix (Tier A)

**Files:**
- Modify: `src/entities/Alien.gd`
- Test already written in Task 18 (`test_alien_only_fires_at_level_3_in_mode1`)

The `can_fire()` method already has this distinction. Verify the existing test passes for both Mode 1 (equality) and Mode 2 (≥):

**Step 1: Run existing test**

```bash
# GDUnit4 runner → tests/unit/test_alien.gd::test_alien_only_fires_at_level_3_in_mode1
```

Expected: PASS (already implemented in Task 18).

**Step 2: Commit if not already committed**

```bash
git commit --allow-empty -m "chore: verify alien fire level fix (Tier A) — already in Alien.gd"
```

---

### Task 27: Uniform spawn cadence (Tier A)

`ENHANCED_GAMEPLAY.md §3.1`: Replace bitmask spawn with uniform timer + jitter in Mode 2+.

**Files:**
- Modify: `src/world/SpawnManager.gd`
- Test: `tests/unit/test_spawn_cadence.gd`

**Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_mode1_uses_bitmask_cadence():
    GameState.visual_mode = GameState.VisualMode.RETRO
    var sm := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(sm)
    assert_bool(sm.use_bitmask_cadence()).is_true()
    sm.queue_free()
    GameState.reset()

func test_mode2_standard_uses_timer_cadence():
    GameState.visual_mode = GameState.VisualMode.MODERN
    GameState.gameplay_variant = GameState.GameplayVariant.STANDARD
    var sm := preload("res://src/world/SpawnManager.tscn").instantiate()
    add_child(sm)
    assert_bool(sm.use_bitmask_cadence()).is_false()
    sm.queue_free()
    GameState.reset()
```

**Step 2: Run test — verify it fails**

**Step 3: Update SpawnManager.gd**

```gdscript
const BASE_SPAWN_INTERVAL: int = 32  # Frames; avg of 16/48 cadence
const SPAWN_JITTER: int = 5

var _spawn_timer: int = BASE_SPAWN_INTERVAL
var _uniform_mode: bool = false

func use_bitmask_cadence() -> bool:
    return GameState.visual_mode == GameState.VisualMode.RETRO \
        or GameState.gameplay_variant < GameState.GameplayVariant.STANDARD

func tick(frame_count: int) -> void:
    if use_bitmask_cadence():
        if frame_count & SPAWN_BITMASK == 0:
            _try_spawn_enemy()
    else:
        _spawn_timer -= 1
        if _spawn_timer <= 0:
            _try_spawn_enemy()
            _spawn_timer = BASE_SPAWN_INTERVAL + randi_range(-SPAWN_JITTER, SPAWN_JITTER)
```

**Step 4: Run test — verify it passes**

**Step 5: Commit**

```bash
git add src/world/SpawnManager.gd tests/unit/test_spawn_cadence.gd
git commit -m "feat(tier-a): uniform spawn timer in Mode 2+ Standard; bitmask cadence preserved for Mode 1"
```

---

### Task 28: HUD polish — death readout & triple counter (Tier A)

`ENHANCED_GAMEPLAY.md §3.2`: "X hostages lost" overlay on death. Triple counter (Rescued / Remaining / Killed).

**Files:**
- Modify: `src/ui/HUD.gd` / `HUD.tscn`
- Create: `src/ui/DeathReadout.gd` / `DeathReadout.tscn`

**Step 1: Update HUD.gd to show Remaining counter in Mode 2+**

```gdscript
@onready var remaining_label: Label = $Panel/Remaining  # Hidden in Mode 1

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var is_enhanced := GameState.visual_mode >= GameState.VisualMode.MODERN \
        and GameState.gameplay_variant >= GameState.GameplayVariant.STANDARD
    remaining_label.visible = is_enhanced
    refresh()

func refresh() -> void:
    rescued_label.text = "%02d" % GameState.total_rescues
    killed_label.text = "%02d" % GameState.hostages_killed
    aboard_label.text = "%02d" % GameState.hostages_loaded
    var remaining := 64 - GameState.total_rescues - GameState.hostages_killed
    remaining_label.text = "%02d" % max(0, remaining)
    _update_lives()
```

**Step 2: Create DeathReadout.gd — "X hostages lost" overlay**

```gdscript
extends Control
class_name DeathReadout

@onready var message_label: Label = $Label

func show_loss(count: int) -> void:
    if count <= 0:
        return
    message_label.text = "%d hostage%s lost" % [count, "s" if count != 1 else ""]
    visible = true
    await get_tree().create_timer(2.0).timeout
    visible = false
```

Wire `DeathReadout.show_loss(hostages_aboard)` to Chopper's die() method.

**Step 3: Commit**

```bash
git add src/ui/HUD.gd src/ui/HUD.tscn \
        src/ui/DeathReadout.gd src/ui/DeathReadout.tscn
git commit -m "feat(tier-a): triple-counter HUD + death readout overlay"
```

---

## v0.2 Complete — Mode 1 + Tier A

**Playability check:**

- [ ] Mode 1: Tank spawn bug replicated (tanks cluster left when flying right)
- [ ] Mode 2 Standard: Tank spawn fixed (spread across world)
- [ ] Mode 2 Standard: Alien fires at level 3+ (not just exactly 3)
- [ ] Mode 2 Standard: Spawn cadence is uniform (not bursty)
- [ ] Mode 2 Standard: Triple counter visible in HUD
- [ ] Death with hostages aboard shows "X hostages lost" card

```bash
git tag v0.2-alpha
git commit --allow-empty -m "milestone: v0.2 — Mode 1 complete, Tier A bug fixes applied"
```

---

## Phase 14: v0.3 — Mode 2 Setup

### Task 29: Variant picker UI

`ENHANCED_GAMEPLAY.md §2`: Three-card picker shown before sortie in Mode 2/3. One card per tier. Saves selection to `settings.cfg`.

**Files:**
- Create: `src/scenes/VariantPicker.gd` / `VariantPicker.tscn`
- Modify: `src/scenes/MainMenu.gd` (route Mode 2 through VariantPicker)

**Step 1: Implement VariantPicker.gd**

```gdscript
extends Control

signal variant_selected(variant: int)

@export var cards: Array[Control] = []

var _selected: int = GameState.GameplayVariant.STANDARD

func _ready() -> void:
    _selected = Settings.selected_variant
    _highlight_card(_selected)

func _on_card_selected(variant_idx: int) -> void:
    _selected = variant_idx
    GameState.gameplay_variant = variant_idx
    Settings.selected_variant = variant_idx
    Settings.save()
    await get_tree().create_timer(0.3).timeout
    SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")

func _highlight_card(idx: int) -> void:
    for i in range(cards.size()):
        cards[i].modulate = Color.WHITE if i == idx else Color(0.7, 0.7, 0.7)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("move_left"):
        _selected = max(0, _selected - 1)
        _highlight_card(_selected)
    elif event.is_action_pressed("move_right"):
        _selected = min(2, _selected + 1)
        _highlight_card(_selected)
    elif event.is_action_pressed("fire"):
        _on_card_selected(_selected)
```

**Step 2: Update MainMenu to route through picker**

```gdscript
func _on_play_pressed() -> void:
    GameState.reset()
    if GameState.visual_mode == GameState.VisualMode.RETRO:
        SceneTransition.transition_to("res://src/scenes/RetroTitle.tscn")
    else:
        SceneTransition.transition_to("res://src/scenes/VariantPicker.tscn")
```

**Step 3: Commit**

```bash
git add src/scenes/VariantPicker.gd src/scenes/VariantPicker.tscn \
        src/scenes/MainMenu.gd
git commit -m "feat: variant picker UI — three-card selector for Standard/Director's Cut/Reimagined"
```

---

### Task 30: Scenario sprite pipeline setup

`ASSET_PIPELINE.md §2.3` and `§3.6`: Train a custom Scenario LoRA style model, then generate sprites per group.

> **Status (2026-06-11): mostly complete — do not re-run.** The pipeline scripts and spec are
> committed (`postprocess_sprites.py`, `sprites_mode2.json` — **161** sprite specs, commit a742dce)
> and generation is **in flight**: 117/161 sprites generated (commit 690ea2e), remainder running
> now. Generation uses the **Scenario REST API** via `src/tools/generate_mode2_sprites.py` (key in
> git-ignored `src/tools/.env`) — not the MCP server originally described here; the MCP route
> remains an optional interactive alternative. Re-running completed generation wastes paid credits
> and can clobber in-flight output. Remaining work in this task: finish the last sprites, then the
> consistency pass.

> **This is a human-in-the-loop workflow. It requires a Scenario Pro account** (REST API key, or
> the Scenario MCP server for the interactive alternative).

> **Fallback path:** If the Scenario service is unavailable, rate-limited, or produces
> inconsistent output, Mode 2 sprites can be hand-authored using Aseprite (pixel art) at the
> same dimensions as the spec JSON. Place hand-authored PNGs directly in
> `assets/graphics/mode2/<group>/` following the naming convention in `sprites_mode2.json`.
> Run `postprocess_sprites.py --pass consistency` to find gaps.
> v0.3/v0.4 must not block on external service availability — use the fallback if needed and
> retrain/replace with Scenario output later.

**Step 1: Connect Scenario MCP to VS Code**

In VS Code command palette: `Copilot: Add MCP Server` → `https://mcp.scenario.com/mcp` → authenticate with API key from `src/tools/.env`.

**Step 2: Create sprite spec JSON**

Create `src/tools/config/sprites_mode2.json` with all 161 sprite entries (see `ASSET_PIPELINE.md §3.3` for the full table; ✅ already committed in a742dce). Start with the chopper group:

```json
[
  {
    "name": "chopper_side_0",
    "group": "chopper_side",
    "size_px": [48, 24],
    "prompt": "military rescue helicopter side view, pixel art, facing left, transparent background, game sprite, clean silhouette, Endesga 32 palette",
    "negative": "3d render, realistic, blurry, text, watermark, low contrast, anti-aliased",
    "candidates": 4,
    "biome": null
  }
]
```

**Step 3: Implement postprocess_sprites.py**

Create `src/tools/postprocess_sprites.py`:

```python
#!/usr/bin/env python3
"""
Post-processes Scenario-generated sprites:
  - Resize to exact target dimensions (ImageMagick)
  - Quantize to Endesga 32 palette (ImageMagick)
  - Remove background → alpha channel (Pillow)
  - Silhouette clarity scoring (Pillow + scipy)

Usage:
    python3 src/tools/postprocess_sprites.py --sprite chopper_side_0
    python3 src/tools/postprocess_sprites.py --group chopper_side
    python3 src/tools/postprocess_sprites.py --pass consistency
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
SPEC_FILE = PROJECT_ROOT / "src" / "tools" / "config" / "sprites_mode2.json"
CANDIDATES_DIR = PROJECT_ROOT / "assets" / "graphics" / "mode2" / "_candidates"
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "mode2"
PALETTE_FILE = PROJECT_ROOT / "src" / "tools" / "config" / "palette_mode2.gpl"


def load_specs() -> dict:
    specs = json.loads(SPEC_FILE.read_text())
    return {s["name"]: s for s in specs}


def get_output_path(spec: dict) -> Path:
    if spec.get("biome"):
        return OUT_DIR / f"biome_{spec['biome']}" / spec["group"] / f"{spec['name']}.png"
    return OUT_DIR / spec["group"] / f"{spec['name']}.png"


def remove_background(img: Image.Image) -> Image.Image:
    """Flood-fill background removal using corner pixel color."""
    img = img.convert("RGBA")
    data = np.array(img)
    # Sample corner pixels to determine BG color
    corners = [data[0, 0, :3], data[0, -1, :3], data[-1, 0, :3], data[-1, -1, :3]]
    bg_color = np.median(corners, axis=0).astype(np.uint8)
    # Create mask where pixels are within threshold of BG color
    threshold = 30
    diff = np.abs(data[:, :, :3].astype(int) - bg_color.astype(int))
    mask = np.all(diff < threshold, axis=2)
    data[mask, 3] = 0
    return Image.fromarray(data)


def postprocess(spec_name: str) -> bool:
    specs = load_specs()
    if spec_name not in specs:
        print(f"ERROR: Unknown sprite: {spec_name}")
        return False
    spec = specs[spec_name]
    candidate_dir = CANDIDATES_DIR / spec_name
    if not candidate_dir.exists():
        print(f"ERROR: No candidates found at {candidate_dir}")
        return False

    # Find best candidate (auto-select first for now; scoring in consistency pass)
    candidates = sorted(candidate_dir.glob("*.png"))
    if not candidates:
        print(f"ERROR: No PNG files in {candidate_dir}")
        return False
    src = candidates[0]

    out_path = get_output_path(spec)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Step a: Resize with ImageMagick
    w, h = spec["size_px"]
    resized = CANDIDATES_DIR / f"_{spec_name}_resized.png"
    subprocess.run(
        ["convert", str(src), "-resize", f"{w}x{h}!", str(resized)],
        check=True, capture_output=True
    )

    # Step b: Quantize to Endesga 32 palette
    quantized = CANDIDATES_DIR / f"_{spec_name}_quantized.png"
    subprocess.run(
        ["convert", str(resized), "-remap", str(PALETTE_FILE), str(quantized)],
        check=True, capture_output=True
    )

    # Step c: Remove background
    img = Image.open(quantized)
    img = remove_background(img)
    img.save(str(out_path))

    # Cleanup temp files
    resized.unlink(missing_ok=True)
    quantized.unlink(missing_ok=True)
    print(f"OK: {out_path}")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sprite", help="Single sprite name")
    parser.add_argument("--group", help="Sprite group name")
    parser.add_argument("--pass", dest="pass_name", choices=["consistency", "fix"])
    args = parser.parse_args()

    if args.sprite:
        postprocess(args.sprite)
    elif args.group:
        specs = load_specs()
        for name, spec in specs.items():
            if spec["group"] == args.group:
                postprocess(name)
    elif args.pass_name == "consistency":
        specs = load_specs()
        for name in specs:
            out = get_output_path(specs[name])
            if not out.exists():
                print(f"MISSING: {name}")


if __name__ == "__main__":
    main()
```

**Step 4: Install post-processing dependencies**

```bash
pip install Pillow --break-system-packages
sudo apt install imagemagick
python3 -c "from PIL import Image; print('Pillow OK')"
# ImageMagick 7 renames convert -> magick; prefer magick, fall back to convert (IM6)
magick --version 2>/dev/null | head -1 || convert --version | head -1
```

**Step 5: Train Scenario style model (human step)**

Tell the assistant in a new conversation: "Train the Choplifter Mode 2 style model" — the assistant will use the Scenario MCP `train` tool to guide reference image collection and model training.

**Step 6: Generate chopper sprites (human step)**

Tell the assistant: "Generate the chopper_side sprites for Choplifter Mode 2" — the assistant calls `run_model` and `display_asset` for each frame.

**Step 7: Commit pipeline scripts**

```bash
git add src/tools/postprocess_sprites.py src/tools/config/sprites_mode2.json
git commit -m "feat: Mode 2 sprite post-processing pipeline and sprite spec JSON"
```

---

## Phase 15: v0.4 — Mode 2 Full + Tier B Mechanics

> Detailed execution follows the same pattern as v0.1–v0.3 tasks. Summarized here.

### Task 31: Director's Cut physics (Tier B)

**Files to modify:** `src/entities/Chopper.gd`

**Smoother Y-acceleration curve** — replace index 15 entry from +6 to +5:

```gdscript
# In Chopper.gd — REPLACE the body of get_y_target() from Task 8. _integrate_y() already calls
# get_y_target(), so the variant override is live without further wiring (R3-M4).
func get_y_target() -> int:
    var v := ACCEL_Y_TABLE[accely_index]
    if v == 6 and GameState.gameplay_variant >= GameState.GameplayVariant.DIRECTORS_CUT:
        v = 5  # Smoother top-end thrust
    return v
```

**Three-zone landing system** — `DESIGN.md §4.1`:

```gdscript
const CRASH_VY_MULTIPLIER: int = 2
const MAX_CONSECUTIVE_BOUNCES: int = 3
var consecutive_bounces: int = 0
var vy_peak_since_bounce: int = 0

# Wired from _check_ground()'s touchdown branch when visual_mode >= MODERN and
# gameplay_variant >= DIRECTORS_CUT (Mode 1 keeps the source thresholds untouched — R3-M4).
# All velocities are HIGH-BYTE source units (ints); vel_y is 8.8 fixed point, so shift the
# bounce-back up by 8 when writing it.
func _handle_landing_mode2(impact_vy_hi: int, min_vy_hi: int) -> void:
    var crash_vy_hi := min_vy_hi * CRASH_VY_MULTIPLIER
    if absi(impact_vy_hi) <= absi(min_vy_hi):
        consecutive_bounces = 0
        _settle()
    elif absi(impact_vy_hi) <= absi(crash_vy_hi):
        if consecutive_bounces >= MAX_CONSECUTIVE_BOUNCES \
           and vy_peak_since_bounce < absi(min_vy_hi) >> 1:
            die()
        else:
            consecutive_bounces += 1
            vy_peak_since_bounce = 0
            vel_y = (absi(impact_vy_hi) * 2 / 5) << 8  # 0.4× bounce-back, integer 8.8 fixed point
            AudioManager.play_sfx("bounce")
    else:
        die()
```

**Momentum bleed through turns** — halve `accelx` effectiveness for first 3 frames of a turn.

**Commit each mechanic separately:**

```bash
git commit -am "feat(tier-b): smoother Y-accel top-end (index 15 = +5 in DCut)"
git commit -am "feat(tier-b): three-zone landing — safe/bounce/crash with consecutive bounce limit"
git commit -am "feat(tier-b): momentum bleed through turns — 3-frame decel reduction"
```

---

### Task 32: Enemy fire telegraph (Tier B)

**Files:** `src/entities/Tank.gd`, `src/entities/Jet.gd`

Add 24-frame charge timer before firing. During charge, play telegraph animation + SFX:

```gdscript
# In Tank.gd — frame-based like the rest of Mode 1 physics: fire_cooldown is an int counted in
# 60Hz physics frames; do NOT mix in float deltas (R3-M4). Called from _physics_process().
const TELEGRAPH_FRAMES: int = 24  # 0.4s at 60fps

var _charge_frames: int = 0

func _update_fire(chopper: Chopper) -> void:
    fire_cooldown -= 1
    if fire_cooldown <= 0:
        if GameState.gameplay_variant >= GameState.GameplayVariant.DIRECTORS_CUT:
            _charge_frames = TELEGRAPH_FRAMES
            AudioManager.play_sfx("fire_telegraph")   # the tell starts when the charge starts
        else:
            _fire_shell(chopper)
        fire_cooldown = FIRE_INTERVAL

    if _charge_frames > 0:
        _charge_frames -= 1
        if _charge_frames == 0:
            _fire_shell(chopper)
```

Aliens are exempt from the telegraph — their unpredictability is intentional.

```bash
git commit -am "feat(tier-b): enemy fire telegraph — 24-frame charge tell for tanks and jets"
```

---

### Task 33: World continuity on death (Tier B)

`ENHANCED_GAMEPLAY.md §4.3`: On death, preserve `TOTAL_RESCUES`, `HOSTAGES_KILLED`, cleared houses, `CURR_LEVEL`. Reset enemies, field hostages, chopper position.

**Files:** `src/world/World.gd`

```gdscript
func _reset_for_new_sortie() -> void:
    # Clear enemies and projectiles
    for entity in get_tree().get_nodes_in_group("enemies"):
        entity.queue_free()
    for proj in get_tree().get_nodes_in_group("projectiles"):
        proj.queue_free()
    # Reset field hostages (not STRANDED in Tier C)
    for hostage in get_tree().get_nodes_in_group("hostages"):
        if hostage.state in [Hostage.State.RUNNING, Hostage.State.LOADING]:
            GameState.hostages_killed += 1
            hostage.queue_free()
    # Chopper respawns at base — set the SOURCE-unit state, not the node position: the render
    # pass overwrites `position` from pos_x/pos_y every frame (R3-M5).
    chopper.pos_x = float(GameState.SRC_BASE_X)
    chopper.pos_y = 0.0
    chopper.vel_x = 0; chopper.vel_y = 0
    chopper.dying = false; chopper.hostages_aboard = 0
    # GameState: lives/rescues/kills/level preserved (Tier B+)
    GameState.hostages_loaded = 0
```

```bash
git commit -am "feat(tier-b): world continuity on death — enemy reset, state preserved"
```

---

### Task 34: Music pipeline (v0.4)

`ASSET_PIPELINE.md §5`: Compose in Python via midiutil, render with FluidSynth, convert to OGG.

**Files:**
- Create: `src/tools/generate_music.py`
- Create: `src/tools/config/music_spec.py`

Implement the dynamic layer architecture (calm/tension/action per biome, plus victory/loss stings). Follow the same pattern as `generate_sfx.py`: define specs as parameter dicts, synthesize MIDI, render to WAV, convert to OGG.

```bash
git add src/tools/generate_music.py src/tools/config/music_spec.py
git commit -m "feat: music pipeline — midiutil → FluidSynth → OGG, 3-layer dynamic system"
```

**Step 5 (additional): Implement runtime crossfade in AudioManager**

`AudioManager.set_music_state()` currently uses hard play/stop. Replace with tween-based crossfade:

```gdscript
func set_music_state(state: String, biome: String = "desert") -> void:
    if not Settings.music_enabled:
        return
    _current_music_state = state
    for layer_name in ["calm", "tension", "action"]:
        var player: AudioStreamPlayer = get_node("Music_" + layer_name)
        var target_vol := linear_to_db(Settings.master_volume * Settings.music_volume)
        if layer_name == state:
            if not player.playing:
                var path := MUSIC_BASE_PATH + "music_%s_%s.ogg" % [biome, layer_name]
                if ResourceLoader.exists(path):
                    player.stream = load(path)
                    player.volume_db = -80.0
                    player.play()
            var t := create_tween()
            t.tween_property(player, "volume_db", target_vol, 1.0)
        else:
            if player.playing:
                var t := create_tween()
                t.tween_property(player, "volume_db", -80.0, 1.0)
                t.tween_callback(player.stop)
```

```bash
git commit -am "feat: music crossfade — 1s tween between calm/tension/action layers"
```

---

## Phase 16: v0.5 — Tier C Mechanics

> Tier C is additive on Tier B. All guards use `== REIMAGINED`.

### Task 35: Scatter on death (Tier C)

`ENHANCED_GAMEPLAY.md §5.2`: Carried hostages spawn as STRANDED at crash site with 30-second countdown. Off-screen arrow indicator. Second death halves timer. Third death kills immediately.

**Files:** `src/entities/Hostage.gd`, `src/entities/Chopper.gd`, `src/ui/HUD.gd`

1. Add `STRANDED` state to `Hostage.State` enum *(already in Hostage.gd above)*
2. In `GameState.on_chopper_death()`, when `gameplay_variant == REIMAGINED`, spawn STRANDED hostages instead of killing them
3. Add countdown timer on each STRANDED hostage node
4. Add off-screen directional arrow to HUD

```bash
git commit -am "feat(tier-c): scatter on death — STRANDED state, 30s countdown, directional HUD arrow"
```

> Note: `STRANDED` is NOT yet in the `Hostage.State` enum from Task 14 — add it here (the earlier
> "already in Hostage.gd above" claim was stale).

---

### Task 35b: Reimagined 16-house field (Tier C)

`ENHANCED_GAMEPLAY.md §5`: the Reimagined variant replaces the 4-house Mode 1 field with a
**16-house single field** (4 hostages each; same 64 total). Mode 1 topology is untouched. This is
the `Enhanced (Mode 2+)` Fidelity Ledger row — Tasks 11/14 forward-reference it here (it was
previously mis-referenced as "Task 33", which is world-continuity-on-death).

**Files:** `src/world/World.gd` / `World.tscn`, `src/world/HostageManager.gd`, `src/autoload/GameState.gd`

1. Behind `gameplay_variant == REIMAGINED`: build 16 house anchors procedurally across the field;
   size `hostages_in_houses` / `house_states` from a `num_houses()` helper instead of the
   `NUM_HOUSES` constant (4 hostages per house in this variant).
2. `_choose_house` masks the RNG with `& 0x0F` in this variant; the ring scan is unchanged.
3. Tests: 16 houses exist only in Reimagined; Mode 1 still spawns exactly 4; totals still sum to 64.

```bash
git commit -am "feat(tier-c): Reimagined 16-house field — Mode 1 topology untouched"
```

---

### Task 36: Fuel system (Tier C, optional toggle)

`ENHANCED_GAMEPLAY.md §5.3`: `fuel: float` 0–1, depletes during flight, emergency refill to 25% on field landing.

**Files:** `src/entities/Chopper.gd`, `src/ui/HUD.gd`

Gated by `GameState.fuel_enabled and GameState.gameplay_variant == REIMAGINED`.

```bash
git commit -am "feat(tier-c): fuel system — depletion, emergency landing refill, HUD gauge"
```

---

### Task 37: Mission rating, grade ceiling & PB splits (Tier C)

`ENHANCED_GAMEPLAY.md §5.1, §5.5` (see also `docs/plans/2026-06-11-meta-game-depth-design.md`): S/A/B/C/F grade computed from casualties, sorties, and time. Shown on mission-end card. Saved to `user://highscores.cfg`.

**Files:** `src/scenes/MissionEnd.gd` / `MissionEnd.tscn`, `src/autoload/GameState.gd`, `src/autoload/Records.gd` (new)

1. Grade table + pure function `best_achievable_grade(casualties, sorties, elapsed) -> Grade` sharing the grading threshold constants
2. End-of-wave summary card: grade ceiling line ("S rank still in reach" / "Best possible: A/B/C"), computed at card render time — no cached state or signals
3. `GameState.run_splits: Array[float]` — cleared at run start, appended at each wave delivery (survives World.tscn reload-on-death by living in the autoload)
4. PB record slots gain optional `best_time_splits` field, written only when a victory beats the slot's best time; summary card shows `Wave 2 — 4:12 (PB 4:06, +0:06)` with +/− sign as primary signal, color secondary; fall back to plain wave time when no PB or pre-feature record
5. `Records.gd` autoload owns highscores.cfg load/save and §5.5 corruption handling

```bash
git commit -am "feat(tier-c): mission rating — grade + ceiling indicator + PB wave splits"
```

---

### Task 37b: Career stats & Records screen

`ENHANCED_GAMEPLAY.md §5.6`: lifetime counters in `user://career.cfg`, Records panel in Main Menu. Tracked in **all variants and all modes** (not Tier C-gated), so this task is independent of the variant system — but it lands here because the Records panel also displays the Task 37 PB slots.

**Files:** `src/autoload/Records.gd`, `src/autoload/GameState.gd`, `src/scenes/MainMenu.tscn`, `src/ui/RecordsPanel.gd` / `RecordsPanel.tscn` (new, modeled on SettingsPanel)

1. Career counters per §5.6 table; every increment guarded by `not GameState.demo_mode` (demo attract loop delivers hostages — must not inflate stats)
2. Flush points: run start, each wave delivery, run end (victory / loss / quit-to-menu)
3. `career.cfg` written via temp file + rename (crash mid-write must not zero lifetime stats); failed parse → reset + warning, never crash
4. RecordsPanel: Career section + Personal Bests section (6 variant × mode slots, "—" when empty); read-only, reads both cfg files on open
5. `perfect_runs` = victory with 0 casualties, any sorties — variant-agnostic, distinct from S rank

```bash
git commit -am "feat(meta): career stats (career.cfg) + Records panel in main menu"
```

---

## Phase 17: v1.0 Polish

### Task 38: Touch controls

`DESIGN.md §5.5`: Virtual joystick (floating origin) for left half. Fire button + face buttons for right half. Virtual controls hidden on non-touch devices.

**Files:** `src/ui/TouchControls.gd` / `TouchControls.tscn`

Use the [Virtual Joystick](https://godotengine.org/asset-library/) addon or implement:

```gdscript
extends CanvasLayer

func _ready() -> void:
    visible = DisplayServer.is_touchscreen_available()
```

Map virtual stick outputs to the same actions used by keyboard/controller.

```bash
git commit -am "feat: touch controls — floating-origin virtual joystick, fire/face buttons"
```

---

### Task 39: Web export

**Files:** `export_presets.cfg`

In Godot: `Project → Export → Add → Web (HTML5)`. Configure:
- Custom HTML template for the browser wrapper
- Progressive Web App manifest (optional)
- Ensure all SFX/music load with `AudioServer.set_enable_tagging_used_audio_streams(false)` to avoid browser autoplay restrictions

Test in browser:

```bash
godot --export-debug "Web" /tmp/choplifter-web/index.html
python3 -m http.server 8080 -d /tmp/choplifter-web
# Open http://localhost:8080
```

```bash
git add export_presets.cfg
git commit -m "chore: web export preset configured and verified"
```

---

### Task 40: Settings panel

Full settings UI accessible from Main Menu and Pause screen:

- Master / SFX / Music volume sliders
- Music on/off toggle
- Visual mode selector
- Controls rebinding (keyboard/controller)
- All saved via `Settings.save()`

```bash
git commit -am "feat: settings panel — volume, music toggle, controls rebinding"
```

---

### Task 41: Final audit

When all tasks above are complete, run the full-review skill:

> Tell the assistant: **"@full-review"** — audit the entire codebase for quality, correctness, security, and design spec compliance.

Address all findings before tagging v1.0.

```bash
git tag v1.0
git commit --allow-empty -m "milestone: v1.0 — all modes and tiers complete, audit passed"
```

---

## Phase 18: v2.0 — Mode 3 Hi-Res

> Do not begin until v1.0 is shipped.

Mode 3 uses Godot 4's 3D renderer for 2D gameplay. Sprites replaced with high-resolution painted art or pre-rendered 3D assets. Two additional mountain layers. `Light2D` nodes with normal maps.

Asset sources:
- Environments: AI painterly generation at 1024×1024+
- Sprites: 3D models from Kenney.nl / Fab.com, pre-rendered to sprite sheets
- Normal maps: generated from height maps in Godot's built-in tooling

See `DESIGN.md §6.4` for full specification.

```bash
git commit --allow-empty -m "milestone: v2.0 kickoff — Mode 3 Hi-Res"
```

---

## Appendix: Key Constants Reference

> All values from `DESIGN.md §7` and `REVERSE_ENGINEER_ANALYSIS.md §2.6`. Use these; do not guess.

| Constant | Value | Notes |
|---|---|---|
| `ACCEL_Y_TABLE` | `[-10,-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,6]` | 16 target velocities the chopper eases toward. Index 8 = gravity (−2), index 15 = full thrust (+6) |
| `BULLET_GRAVITY_TABLE` | `[-2,-2,-1,-1,-1,0]` | Indexed by `\|turn_state\|`. 0=head-on (most drop), 5=side (no drop) |
| `SCROLL_LEAD_LEFT` | 70 source units | Original 70px in the 280-unit viewport (scaled to screen by `Camera2D.zoom`) |
| `SCROLL_LEAD_RIGHT` | 210 source units | Original 210px in the 280-unit viewport |
| `SRC_VIEW_WIDTH` | 280 source units | Visible width; `Camera2D.zoom = 480/280` scales to screen px |
| `WORLD_BOUNDS_LEFT` | 720 source units (`$02D0`) | Alias of `SRC_BOUNDS_LEFT` |
| `WORLD_BOUNDS_RIGHT` | 4864 source units (`$1300`) | Alias of `SRC_BOUNDS_RIGHT` |
| `SRC_SCROLL_END_X` | 688 source units (`$02B0`) | Leftmost viewport-left camera clamp |
| `SRC_SCROLL_START_X` | 4616 source units (`$1208`) | Rightmost viewport-left camera clamp |
| `SRC_BASE_X` | 4724 source units (`$1274`) | Base/door X |
| `MAX_BULLETS` | 5 | Player shots simultaneous |
| `MAX_HOSTAGES` | 64 | Mode 1: 4 houses × 16 hostages, present in the single scrolling field (no waves). The 16-house layout is Mode 2+ only |
| `TURN_FRAMES` | −5 to +5 (11 states) | 0 = camera-facing |
| `TURN_SPEED` | 2 steps/frame if dist ≥ 2; 1 if dist == 1 | Full −5→+5 takes 5 frames |
| `SPAWN_BITMASK` | `0x2F` | `FRAME_COUNT AND $2F == 0`; non-uniform 16/48-frame cadence |
| `HOSTAGE_EMERGE_MASK` | `0x03` | Every 4 frames |
| `MODE1_LEVEL_CAP` | 3 | `cmp #$03 / beq` in source |
| `MODE2_LEVEL_CAP` | 7 | Extended for biome progression |
| `ALIEN_MAX_VX` | ±5 source units/frame | |
| `ALIEN_MAX_VY` | ±1 source units/frame | |
| `ALIEN_DESPAWN_DX` | ~560 source units | ~2 viewport widths (2 × 280) |

---

## Appendix: Test Command Reference

```bash
# Python tests (pytest)
python3 -m pytest tests/ -v

# Single Python test
python3 -m pytest tests/test_sfx_pipeline.py::test_generate_sfx_produces_ogg -v

# Godot unit tests (GDUnit4)
# Run from inside Godot editor: GdUnit4 → Run All Tests
# Or from CLI (requires Godot in PATH):
godot --headless -s addons/gdUnit4/bin/GdUnitRunner.gd

# Run single test suite
godot --headless -s addons/gdUnit4/bin/GdUnitRunner.gd \
  --add tests/unit/test_chopper_physics.gd

# SFX pipeline
python3 src/tools/generate_sfx.py --sfx bullet_fire --preview  # WAV preview
python3 src/tools/generate_sfx.py                               # All OGG

# Sprite post-processing
python3 src/tools/postprocess_sprites.py --sprite chopper_side_0
python3 src/tools/postprocess_sprites.py --group chopper_side
python3 src/tools/postprocess_sprites.py --pass consistency

# Sprite extraction (Mode 1)
python3 src/tools/extract_sprites.py \
  --gfx docs/blondie-ChoplifterReverse/CHOPGFX \
  --gfxhi docs/blondie-ChoplifterReverse/CHOPGFXHI \
  --out assets/graphics/mode1 --scale 4
```

---

## Appendix: File Creation Order

The dependency order matters — each file below may `preload` files above it:

```
1.  src/autoload/GameState.gd
2.  src/autoload/Settings.gd
3.  src/autoload/AudioManager.gd + SceneTransition.gd
4.  src/entities/Bullet.gd + Bullet.tscn
5.  src/entities/Shell.gd + Shell.tscn
6.  src/entities/Missile.gd + Missile.tscn  
7.  src/entities/Bomb.gd + Bomb.tscn
8.  src/entities/Chopper.gd + Chopper.tscn
9.  src/entities/Hostage.gd + Hostage.tscn
10. src/entities/Tank.gd + Tank.tscn
11. src/entities/Jet.gd + Jet.tscn
12. src/entities/Alien.gd + Alien.tscn
13. src/world/Terrain.gd + Terrain.tscn
14. src/world/Base.gd + Base.tscn
15. src/world/House.gd + House.tscn
16. src/world/SpawnManager.gd + SpawnManager.tscn
17. src/world/World.gd + World.tscn
18. src/ui/HUD.gd + HUD.tscn
19. src/ui/DeathReadout.gd + DeathReadout.tscn
20. src/scenes/Boot.gd + Boot.tscn
21. src/scenes/MainMenu.gd + MainMenu.tscn
22. src/scenes/SortieBanner.gd + SortieBanner.tscn
23. src/scenes/RetroTitle.gd + RetroTitle.tscn
24. src/scenes/VariantPicker.gd + VariantPicker.tscn  (v0.3+)
25. src/scenes/MissionEnd.gd + MissionEnd.tscn         (v0.5+)
```
