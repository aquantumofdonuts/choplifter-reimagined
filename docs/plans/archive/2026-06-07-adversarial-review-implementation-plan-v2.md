# Adversarial Design Review: 2026-06-07-implementation-plan.md (Round 2)

**Date:** 2026-06-07
**Reviewer Alpha:** Claude Opus 4.8 (independent review + judge)
**Reviewer Beta:** GitHub Copilot (counter-review, separate pass)
**Document:** `docs/plans/2026-06-07-implementation-plan.md`
**Context reviewed:** `docs/DESIGN.md`, `docs/ENHANCED_GAMEPLAY.md`, `docs/ASSET_PIPELINE.md`,
`docs/blondie-ChoplifterReverse/choplifter.s` (verified: lines 3308–3940, 4760–4810, 5180–5380,
6068–6085, 7200–7290), `docs/blondie-ChoplifterReverse/zeropage.s`, and the prior review
`docs/plans/2026-06-07-adversarial-review-implementation-plan.md`.

> This is an independent second-round adversarial review, conducted fresh against the source
> disassembly. It reaches several of the prior review's conclusions independently and adds new
> source-grounded findings (chopper integration algorithm, collision architecture, base-runner
> unload model, aboard cap, RNG port, credential hygiene).

## Executive Summary

The implementation plan is **structurally strong but not ready to execute past the bootstrap and
autoload phases (Tasks 1–7).** Its milestone sequencing, TDD cadence, variant-guard architecture,
and data-table extraction (the `ACCEL_Y_TABLE` and `BULLET_GRAVITY_TABLE` byte values are correct
against source) are genuinely good. However, both reviewers independently found that, **if
implemented exactly as written, v0.1 would neither feel like Choplifter nor be completable.** Four
issues are Critical: the chopper physics *algorithm* is wrong (table values are target velocities
eased toward, not accelerations added), the projectile/collision architecture does not produce
working hit detection, the hostage *data model* contradicts the source (four houses, not sixteen),
and the hostage rescue loop is never wired through production code. A repair pass is required before
Task 8. Once patched, the existing plan structure becomes a solid foundation again.

## Consensus Findings

Both reviewers agree on all of the following after debate.

### Critical

**CF1 — Chopper physics algorithm is wrong (not just untuned).**
The source `integrateAcceleration` (choplifter.s:5205–5234) eases Y velocity *toward* the table
value: `diff = accelYTable[ZP_ACCELY] − VELY_H`, take `|diff|`, halve it when `≥ 2` (`cmp #$02 / lsr`),
reapply sign, add to velocity. The table entries are **target velocities**, not accelerations. The
plan's Task 8 does `vel_y += accelYTable[i]` (simple Euler), a different model. X physics is
likewise oversimplified to `accelx ∈ {−1,0,1}` / `vel_x += accelx`, dropping the 16-bit X-accel
table, the `±$15` velocity clamp (5236–5260), and ground ASR friction decay (5340–5352). This is the
most dangerous defect because it compiles, passes every test in the plan (which assert the *table*,
not the *integration*), and ships feeling wrong.

**CF2 — Collision/hit-detection architecture is invalid as written.**
Bullet, Shell, Missile, Bomb, Tank, Jet, Alien, Hostage are `CharacterBody2D` and rely on
`_on_body_entered(body)`. `CharacterBody2D` emits no `body_entered` signal, and the `.tscn`
instructions add only a `CollisionShape2D` — no `Area2D`, no signal wiring. As authored, no
projectile hits anything: enemies can't be killed, the chopper can't be hit, win/loss is
unreachable. *(Agreed framing: the plan fails to specify a valid collision architecture — Area2D
hitboxes or explicit `get_slide_collision()` processing — not that CharacterBody2D roots are
impossible.)*

**CF3 — Hostage topology contradicts the source.**
Task 14 specifies "16 houses × 4 hostages, all in one field, no waves." The source uses **four**
house indices: `spawnHostagesChooseHouse` masks the RNG with `#$03` and iterates `cpx #$04`
(choplifter.s:3793–3815); `MAX_HOSTAGES = 16` is the **active hostage-record table size**, not a
house count; `HOSTAGES_LEFT` initializes to 64 (the in-house reservoir). The plan's topology is
fabricated and labeled faithful.

**CF4 — Hostage rescue loop is never wired through production code.**
`House.try_release_hostage()` is never called by `World`/`SpawnManager`;
`Hostage.on_chopper_landed()` (WAVING→RUNNING) is never invoked; nothing advances LOADING →
`board_chopper()`. The DoD ("all 64 hostages rescuable") is structurally impossible with the v0.1
code as written.

### High

**HF1 — Coordinate normalization is unresolved and currently inconsistent.**
Source: `BOUNDS_LEFT=$02D0`, `BOUNDS_RIGHT=$1300`, `BASE_X=$1274`, `FARHOUSE_X=$0380`
(choplifter.s:4760–4790). The plan uses `WORLD_BOUNDS_LEFT=0`, `RIGHT=4864`, base at `x=0`, houses
`320…4640` — neither raw source space nor a documented transform. Affects clamps, camera lead,
spawn positions, house/fence/base placement, and despawn.

**HF2 — Scene-reload vs. state ownership corrupts the fixed hostage universe.**
v0.1 reloads `World.tscn` after death while `GameState` counters persist cumulatively. Scene-local
houses regenerate 64 hostages each sortie → totals exceed 64, breaking `is_victory()`/
`is_mission_loss()`. The real defect is *ownership*: hostage/house inventory must live in (or be
serialized to) `GameState`, not the scene. Reload is acceptable if state is reapplied.

**HF3 — Landing/crash constants missing from Mode 1 core.**
Source has exact values: `MIN_VY=$FBA0`, `CRASHSPEED=$EB01`, `LAUNCHTHRESH=$0100`, `MAX_SINK=$06`
(choplifter.s:4792–4804). Task 13 reduces landing to `vel_y=0; landed=true`. Safe/crash/launch/sink/
bounce behavior is core feel, not polish. (Three independent reviews flagged this.)

**HF4 — Tank spawn bug approximated incorrectly.**
Source branches on player X-velocity `ZP_VELX_16_H` (3893–3900) across three paths — `PosV`,
`NegV`, `MedV` (the `and #$08` "spawn behind you"). The `PosV` bug zeros only `ENTITY_X_H` while
keeping `ENTITY_X_L = CHOP_POS_X_L + $B0`. The plan keys off `logical_face`, drops `MedV`, and
randomizes the low byte too — capturing the symptom but not the bug.

**HF5 — 16-hostage aboard capacity cap missing.**
Source gates boarding on `HOSTAGES_LOADED cmp #$10` in multiple places, with explicit "chopper
full" behavior that sends the hostage running back toward base (3470–3520). The plan's
`board_chopper()` increments unconditionally.

**HF6 — Base-runner / unload model not captured.**
On base landing the source unloads carried hostages one at a time via `spawnNewHostage`: decrement
`HOSTAGES_LOADED`, increment `BASE_RUNNERS`, and count `inc TOTAL_RESCUES` only as each runner
reaches the base door. `CURR_LEVEL` is incremented *inside this unload path* (gated `cmp #$03 / beq`,
keyed on `CHOP_LOADED`), not on the landing event. The plan's immediate `total_rescues +=
hostages_aboard` + `increment_level()` on landing is an approximation.

**HF7 — Scenario credential hygiene (security).**
The terminal context shows a live Scenario API key being base64-encoded in a shell
(`echo -n 'api_…:…' | base64`). Base64 is encoding, not encryption — this is a plaintext credential
now in shell history. **Treat the exposed key as compromised and rotate it.** Add a secret-handling
rule: `.env` only, never base64-in-shell, never committed, scrub history.

**HF8 — Source RNG not ported.**
Mode 1 uses Godot RNG for alien fire, tank spawn, plane selection. The source RNG is an 8-bit
`rol/eor/ror` + seed LCG (choplifter.s:6072–6083, ~8 instructions). Cheap to port; required for
"bug-for-bug faithful Mode 1" and the deferred attract/demo replay. *(Severity resolved to High,
framed as a cheap fidelity/replay fix — not a functional blocker for v0.1.)*

### Medium

**MF1 — Test suite is helper-centric; can be green while DoD is unmet.**
Nearly every test exercises an isolated helper (`spawn_tank_pos_v`, `on_chopper_landed`,
`_check_boarding`, constant assertions) and none drives the real scene graph. Several physics tests
call `_physics_process(delta)` manually with fabricated deltas, unreliable around `move_and_slide()`
and integer-stepped entities. Add a v0.1 production-path integration test (house → run → board →
deliver → `total_rescues++`) and a physics golden-trace test.

**MF2 — Runtime audio loops incomplete.**
`engine_loop` and alien-crackle SFX are generated but never wired: no engine-loop lifecycle, no
thrust/pitch coupling, no crackle keyed to alien animation frame. Audio buses are created manually;
`default_bus_layout.tres` reproducibility is unverified. Web audio autoplay (a DoD gate) needs a
concrete user-gesture unlock strategy.

**MF3 — Enemy spawn priority biases composition (plan-logic).**
`_try_spawn_enemy`'s elif-chain spawns a jet only when tanks are at cap and an alien only when jets
are at cap, so the alien slot is reachable only when both tanks and both jets are simultaneously
alive at a spawn tick. A plan-logic bias independent of source; replace with independent per-type
cap checks.

### Low

**LF1 — Retro title phase timings are guessed** (2s/3s/2s). Valid but non-blocking; extract source
frame timings or mark as approximate presentation timing.

## Contested Findings

After four debate stages, only severity ranking remained contested — no finding survived as a
substantive disagreement.

**Contested: RNG severity (HF8).**
- *Alpha:* High — the goal "bug-for-bug faithful Mode 1" is Critical-labeled in the plan, and the
  fix is ~10 lines; leaving it non-deterministic is a poor trade, and attract/demo replay depends on it.
- *Beta:* Medium/High — deterministic replay is not an explicit v0.1 DoD criterion; not a functional
  blocker.
- **Judge verdict: High,** with mandatory framing as "cheap fidelity fix, needed for faithful Mode 1
  and future attract/demo replay — not a v0.1 functional blocker." Both reviewers accepted this wording.

**Contested: Is physics *the* top blocker, or co-equal with hostage issues?**
- *Alpha:* Physics is the most dangerous because it's silent and untested.
- *Beta:* Physics makes it "not Choplifter"; hostage topology/wiring makes it "not completable" — co-equal.
- **Judge verdict: co-equal Critical.** The report must not imply physics is the only pre-Phase-2
  blocker. CF1–CF4 are all showstoppers.

## Unique Insights

Findings caught by only one reviewer that survived cross-examination:

- **Alpha (survived):** The chopper integration *algorithm* error (CF1) — the single defect that is
  invisible to the plan's own tests. The collision-signal defect (CF2). The `_try_spawn_enemy`
  starvation as a self-contained plan-logic bug (MF3).
- **Beta (survived):** The hostage *topology* contradiction (CF3, upgraded to Critical by Alpha's
  concession). The base-runner/unload model (HF6). The 16-aboard cap (HF5). The Scenario credential
  hygiene risk (HF7). The reframing of scene-reload as a *state-ownership* problem (HF2).
- **Cross-cutting (emerged from debate):** A whole class of "approximation mislabeled as fidelity"
  (topology, tank spawn, delivery, landing, RNG). The recommended single artifact to catch all of
  them is a **Fidelity Ledger** (see Recommendations).
- **Nuance surfaced by debate:** `CURR_LEVEL` increments on *hostage-unload processing* (per batch,
  gated by `CHOP_LOADED`), not on the landing event itself.

## Strengths

Both reviewers agreed the plan gets these right:

- **Milestone sequencing** — Mode 1 playable first; Scenario/Mode 2 deferred until the core is real.
- **Variant-guard architecture** — Mode 1 fidelity vs. enhancement tiers behind
  `visual_mode`/`gameplay_variant` guards, no core fork.
- **Data-table extraction** — `ACCEL_Y_TABLE` (`$F6…$06` = −10…+6) and `BULLET_GRAVITY_TABLE`
  (`$fe,$fe,$ff,$ff,$ff,$00` = −2,−2,−1,−1,−1,0) verified correct against source; bitmask reading of
  `$2F`/`$03` is correct; bullet-trajectory inversion fixed.
- **TDD cadence and collision-layer planning** — the fail/pass/commit rhythm and up-front layer/mask
  matrix are good practice; the main weakness is *what* the tests assert, not that tests exist.
- **Absorbed prior-review fixes** — world bounds on `GameState`, explicit camera anchoring, victory
  signal wiring, pause-menu scope, behavior-based DoD.

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|----------|---------|----------------|-----------|
| 1 | Critical | CF1 Physics algorithm wrong | Reimplement Y integration as ease-to-target with `>>1`-when-≥2 halving; port X-accel table, `±$15` clamp, ground ASR decay. Add golden-frame tests. | Unanimous |
| 2 | Critical | CF2 Collision invalid | Define a real hit-detection architecture (Area2D hitboxes + wired signals, or `get_slide_collision()` loops) before any entity task depends on it. | Unanimous |
| 3 | Critical | CF3 Hostage topology | Replace 16-house model with source-backed 4-house / 64-reservoir / 16-active-slot / 16-aboard model, OR explicitly mark 16-house as a non-faithful enhancement excluded from Mode 1. | Unanimous |
| 4 | Critical | CF4 Rescue loop unwired | Wire house release, WAVING→RUNNING, and LOADING→board through production; add an end-to-end rescue integration test. | Unanimous |
| 5 | High | HF1 Coordinate model | Add a pre-Phase-2 "source coordinate & unit model" task: decide raw vs normalized space and the source-unit→Godot conversion, applied everywhere. | Unanimous |
| 6 | High | HF2 State ownership | Persist house/hostage inventory in `GameState` (or stop reloading `World.tscn` between sorties). | Unanimous |
| 7 | High | HF3 Landing constants | Extract `MIN_VY`/`CRASHSPEED`/`LAUNCHTHRESH`/`MAX_SINK` + bounce/sink; implement Mode 1 landing before base-delivery logic. | Unanimous |
| 8 | High | HF4 Tank spawn | Branch on `ZP_VELX_16_H`; preserve `ENTITY_X_L=CHOP_POS_X_L+$B0` and the high-byte-only zero bug; include `spawnTankMedV`. | Unanimous |
| 9 | High | HF5 Aboard cap | Add `MAX_HOSTAGES_ABOARD=16` guard + "chopper full" run-back behavior; test full-capacity. | Unanimous |
| 10 | High | HF6 Unload model | Implement (or explicitly approximate, in the Fidelity Ledger) base-runner unload + `CURR_LEVEL`-on-unload. | Unanimous |
| 11 | High | HF7 Credential hygiene | **Rotate the exposed Scenario key now.** Add secret-handling rules; never base64-in-shell or commit `.env`. | Unanimous |
| 12 | High | HF8 Source RNG | Port the 8-bit LCG for Mode 1 (cheap fidelity/replay fix; not a v0.1 functional blocker). | Majority (severity) |
| 13 | Medium | MF1 Helper-centric tests | Add scene-level integration tests + physics golden traces; stop driving `_physics_process` manually. | Unanimous |
| 14 | Medium | MF2 Runtime audio | Tasks for engine-loop lifecycle, alien crackle, bus reproducibility, web audio unlock. | Unanimous |
| 15 | Medium | MF3 Spawn priority bias | Replace elif-chain with independent per-type cap checks. | Unanimous |
| 16 | Low | LF1 Title timings | Source-extract or mark approximate. | Unanimous |

### Cross-cutting recommendation (both reviewers, highest leverage)

**Add a "Fidelity Ledger" to the plan** — a table classifying every Mode 1 mechanic as `Exact`,
`Approximation (documented)`, or `Enhanced`. The plan's recurring failure mode is labeling
approximations as source-faithful (topology, tank spawn, delivery, landing, RNG). A single ledger
artifact would have caught CF3, HF4, HF5, HF6, and HF8 before implementation, and prevents silent
fidelity downgrades going forward.

### Suggested repair sequence (before Task 8)

1. Source coordinate & unit model (HF1).
2. Fidelity Ledger (cross-cutting).
3. Correct chopper physics tasks + golden tests (CF1).
4. Source hostage topology + rescue-loop integration test (CF3, CF4).
5. Valid collision architecture (CF2).
6. State ownership across sorties (HF2).
7. Credential rotation + secret-handling notes (HF7).

## Review Process Notes

**Where the adversarial process added the most value.** The two reviewers approached from
complementary angles and the union was materially larger than either alone. Alpha (physics/engine
focus) caught the integration-algorithm error and the collision-signal defect — both invisible to
the plan's tests. Beta (data-model/operations focus) caught the hostage topology contradiction, the
base-runner unload model, the aboard cap, and the credential hygiene risk. Neither reviewer's
initial list contained the other's top unique finding; the debate is what merged them.

**Blind spots observed.**
- *Alpha:* initially under-weighted the hostage *data model* (focused on wiring, not topology) and
  missed the operational credential risk despite it being in plain sight in the terminal context.
- *Beta:* initially softened the collision finding and was cautious on physics severity; sharpened
  both after cross-examination.
- *Shared:* both initially accepted the plan's "16 houses" and immediate-delivery framing until
  forced back to the disassembly — a reminder that a confidently-worded plan can anchor reviewers
  away from the source.

**Highest-value next action.** Not another isolated unit test — a single production-path integration
test proving one hostage can spawn from a house, run to a landed chopper, board (respecting the
16-cap), be delivered to base, and increment `GameState.total_rescues`, plus a physics golden-trace
test for the chopper. These two tests would convert the plan's "green but unwinnable" risk into a
real completion signal.
