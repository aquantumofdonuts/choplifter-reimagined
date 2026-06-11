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

### Godot project — IN PROGRESS (Phases 0–1 complete)
- **Authoritative plan:** `docs/plans/2026-06-07-implementation-plan.md` (round-3 review fixes already merged in, 92c0921; review docs archived under `docs/plans/archive/`)
- **Plus:** `docs/plans/2026-06-11-meta-game-depth-design.md` (Tasks 37/37b amendments)
- **Done:** Tasks 1, 2, 3, 3b, 3c, 3d — project bootstrap (Godot 4.6.3, GdUnit4 v6.1.3 verified
  headless via `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/`), physics layer
  names, Fidelity Ledger (`docs/FIDELITY_LEDGER.md`)
- **Done (Phase 1):** Tasks 4–7 — all four autoloads registered (GameState w/ source RNG +
  hostage universe, Settings, AudioManager w/ SFX+Music buses, SceneTransition w/ runtime
  content_scale_mode switch). 15 GdUnit4 tests green.
- Placeholder `src/scenes/Boot.tscn` exists so headless runs stay clean — Task 21 replaces it
- **Gotcha found:** GdUnit4 hooks are `before_test`/`after_test`, NOT `before_each`/`after_each`
  (plan's test snippets use the wrong names — fix when transcribing future tasks' tests)
- Next step: Phase 2 (Task 8: chopper physics — source-faithful integration, CF1)

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
