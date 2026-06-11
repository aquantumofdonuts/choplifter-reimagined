# Choplifter Clone — Project Status

> Repo memory (per `.claude/CLAUDE.md`). High-level status, decisions, and progress only —
> detailed plans live in `docs/plans/`, design docs in `docs/`.

## Repo
`/home/chris/Github/choplifter-clone` — Godot 4, GDScript, mobile-first (Android + Web)

## Where things stand (2026-06-11)

### Asset pipeline — COMPLETE (all committed)
- **Mode 1 sprites:** 128 PNGs in `assets/graphics/mode1/` (extracted from Apple II CHOPGFX, e71e257)
- **Mode 2 sprites:** 161/161 in `assets/graphics/mode2/` (Scenario REST API, 880fc8d); `_flagged.json` empty
- **SFX:** 21 OGGs in `assets/audio/sfx/`
- **Music:** 18 OGGs in `assets/audio/music/` — 5 biomes × 3 layers + 3 stings (fbf3bdc)
- Soundfont gitignored — restore with `cp /usr/share/sounds/sf2/FluidR3_GM.sf2 assets/audio/soundfonts/chiptune.sf2`
- Do NOT re-run generation (wastes paid Scenario credits). Integration of assets into scenes is still pending at plan positions.

### Godot project — IN PROGRESS (Phases 0–9 complete)
- **Authoritative plan:** `docs/plans/2026-06-07-implementation-plan.md` (round-3 review fixes already merged in, 92c0921; review docs archived under `docs/plans/archive/`)
- **Plus:** `docs/plans/2026-06-11-meta-game-depth-design.md` (Tasks 37/37b amendments)
- **Done:** Tasks 1, 2, 3, 3b, 3c, 3d — project bootstrap (Godot 4.6.3, GdUnit4 v6.1.3 verified
  headless via `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/`), physics layer
  names, Fidelity Ledger (`docs/FIDELITY_LEDGER.md`)
- **Done (Phase 1):** Tasks 4–7 — all four autoloads registered (GameState w/ source RNG +
  hostage universe, Settings, AudioManager w/ SFX+Music buses, SceneTransition w/ runtime
  content_scale_mode switch). 15 GdUnit4 tests green.
- Placeholder `src/scenes/Boot.tscn` existed so headless runs stayed clean — replaced by the real Boot scene in Task 21
- **Gotcha found:** GdUnit4 hooks are `before_test`/`after_test`, NOT `before_each`/`after_each`
  (plan's test snippets use the wrong names — fix when transcribing future tasks' tests)
- **Done (Phase 2):** Tasks 8–10 — Chopper.gd/.tscn with source-faithful CF1 integration
  (golden traces green), turn state machine, input map (9 actions, keyboard+gamepad; LB/RB =
  face_left/face_right — plan's double-assignment of LB resolved). 26 GdUnit4 tests green.
- Hitbox masks are BITMASKS: plan's "layers 3|5|7" = collision_mask 84 (Chopper.tscn)
- assets/store/ is the maintainer's side-work (store listings) — leave untracked; has .gdignore
- **Done (Phases 3–4):** Tasks 11–13 — World scene (source-unit camera, asymmetric 70/210 lead,
  R3-M1 clamps, R3-C2 vertical framing), Terrain parallax (plan sign bug fixed: layer at
  scroll − compute%period, NOT −compute which scrolls 1.5×), landing/crash/launch + Base Area2D.
  34 GdUnit4 tests green. SpawnManager/HostageManager/HUD are stubs until Tasks 14/16/20.
- GDScript gotcha: `-6 << 8` is a parse error (negative shift operand) — write `-(6 << 8)`
- **Done (Phases 5–6):** Tasks 14–15 — hostage system (Hostage/House/HostageManager: no detect
  radius, 8–9 boarding band, run-backs, unload-credits-rescues, CHOP_LOADED level gate, R3-C3
  serialize/restore) and bullets (source velocity table; `gravity` renamed `gravity_step` —
  Area2D native member collision; enemy hits duck-typed via take_hit()). 45 GdUnit4 tests green.
- **Done (Phases 7–9):** Tasks 16–18 — Tank (+Shell, PosV page-0 spawn bug replicated), Jet
  (+Missile/Bomb, R3-H6a bomb latch), Alien (chase ±5/±1, Mode-1 ==3 fire gate), SpawnManager
  ($2F cadence, single-RNG-byte type pick per R3-H2). 55 GdUnit4 tests green. Jet/alien spawn
  *placement* is a documented approximation (plan only specifies gates/cadence).
- `hostage_rescued` SFX referenced by HostageManager has no .ogg (warns harmlessly) — map to an
  existing sound or synthesize in Task 24
- **Done (Phase 10, Task 19):** death/sortie/win-loss — Chopper.die() full sequence (GameState
  accounting + explosion SFX + 1.5s before `chopper_died`; `chopper_landed` emitted on _settle
  transition), World end-condition routing (loss → MainMenu; survivable death → serialize field
  hostages → SortieBanner → World reload), SortieBanner scene (2s auto-advance), MainMenu.tscn
  is a PLACEHOLDER until Task 21. `_check_end_conditions()` exists but is unwired until HUD
  tasks (per plan). 58 GdUnit4 tests green.
- **Task 19 review follow-up (38fa301):** World `_ending` latch freezes the sim once any end state
  starts (fixes post-death spawn desync of GameState counters + victory/death race);
  `serialize_field_hostages()` now runs after the 1.0s death wait; SceneTransition.transition_to
  re-entrancy guard (first wins); Chopper dead `death_timer` removed, `hostages_aboard` zeroed in
  die(); test_sortie now exercises die() end-to-end. 58 tests still green.
- **Done (Task 19b, b0093e1):** MF1 integration gates — `tests/integration/test_rescue_loop.gd`
  (boots real World.tscn, full spawn→run→board→deliver loop on live physics frames; enemy spawn
  scenes nulled in-test: a tank shell would kill the landed chopper and SceneTransition mid-suite)
  and `tests/integration/test_physics_golden_trace.gd` (thrust/gravity traces + descend-to-land,
  all via real Input actions). 62 GdUnit4 tests green, runner exit 0.
- **Done (Tasks 20/20b, 2de02c4 + abf74cc):** HUD (top-strip rescued/killed/aboard counters polled
  from GameState per frame + 3 dimming chopper life icons; PROCESS_MODE_ALWAYS; World.tscn now
  instances HUD.tscn) and PauseMenu (layer 50, Resume/QuitToMenu; World._unhandled_input toggles
  on "pause" action, guarded by GameState.input_locked). 63 GdUnit4 tests green.
- **Done (Tasks 21/22, ebeed17 + 3d2d9ba):** Boot (applies native-res menu scale mode via public
  `SceneTransition.apply_scale_mode_for()`, copies Settings→GameState with enum casts, 1.5 s splash
  → MainMenu) and MainMenu (Play → RetroTitle in Retro mode else SortieBanner; Quit hidden on web;
  Settings button disabled until Task 40; mode label). RetroTitle: 4-phase attract
  (Broderbund/Logo/Mission/Demo cards using extracted mode1 title sprites at exact 4× downscale);
  input-skip armed only after a no-input frame and gated on `input_locked` (held Play click can't
  insta-skip); **v0.1 deviation:** DEMO is a static card looping back to BRODERBUND after ~10 s —
  recorded-input demo (`data/demo_input.tres`) deferred to v1.0, file intentionally not created.
  64 tests green; Boot→MainMenu and RetroTitle full-cycle headless smoke runs clean.
- Next step: Task 24 (wire SFX to game events; Task 23's SFX assets were pre-generated in e71e257)

## Key settled decisions
- Renderer: **Compatibility** (required for Android + Web)
- Stretch: `viewport` + `integer` scale, 480×270, Nearest filter — **authoritative** (DESIGN.md, 55633ee)
  - Consequence: menus switch `content_scale_mode` to DISABLED (native res) at runtime; game scenes restore VIEWPORT+INTEGER. `SceneTransition.transition_to()` owns the switch. (Decided 2026-06-11, resolving plan/DESIGN contradiction.)
- Mode 1 simulates in **raw source units** (1:1 with 6502 disassembly); camera zoom 480/280 scales at render. Note: mode1 sprites were extracted at 4× — node-level sprite scale must compensate.
- Touch: floating-origin virtual joystick, dedicated `face_camera` button
- Web export: itch.io (primary) + GitHub Pages (dev previews)
- No save system for game progress (faithful to original); settings persist. Tier C adds `user://highscores.cfg` + `user://career.cfg` (see meta-game design doc).

## Environment
- Godot binary: installed to `~/.local/bin/godot` (latest stable 4.x) — headless used for GDUnit4 CLI runs
- Python 3.12 + pytest/Pillow/numpy/scipy, ffmpeg, fluidsynth, ImageMagick: all present
- **Action item (user):** rotate the Scenario API key (exposed during setup; lives in git-ignored `.vscode/mcp.json`; never committed). Not needed again until Mode 3, if ever.

## Tools
- `src/tools/generate_mode2_sprites.py` — Scenario REST API bulk sprite gen (idempotent)
- `src/tools/postprocess_sprites.py` — candidate selection + palette quantize
- `src/tools/generate_music.py` — midiutil → FluidSynth → OGG
- `src/tools/generate_sfx.py` — numpy/scipy → OGG
- `src/tools/extract_sprites.py` — Apple II CHOPGFX → Mode 1 PNGs
