# Adversarial Design Review: 2026-06-07-implementation-plan.md (Round 3)

**Date:** 2026-06-11
**Reviewer Alpha:** Claude Fable 5 (independent review, rebuttal, judge)
**Reviewer Beta:** Claude Opus 4.8 (counter-review + final position, via subagents)
**Document:** `docs/plans/2026-06-07-implementation-plan.md`
**Context reviewed:** `docs/blondie-ChoplifterReverse/choplifter.s` (verified: ~3300–3870, 4560–4810, 5150–5470, 5630–5700, 5820–5895, 6065–6085, 9275–9320), prior reviews (rounds 1–2), repo state (asset pipeline mid-run, 117/161 Mode 2 sprites generated).

> ⚠️ **Asset pipeline note (per request):** No finding in this review requires rerunning any part of the
> asset pipeline. The only asset-related findings (R3-M11, R3-L3) are documentation/status corrections to
> Task 30 and execution-order safeguards. Generated sprites, SFX, and the in-flight Mode 2 generation are
> all unaffected.

## Executive Summary

Round 3 confirms the rounds-1–2 repairs were largely successful — the chopper integration algorithm, collision architecture, hostage topology, boarding band, landing constants, and unload crediting all now match the disassembly. However, both reviewers independently concluded that **v0.1 as written is still unwinnable and largely invisible**: there is no descend input (so the MIN_VY touchdown threshold is unreachable and the chopper can never land), the camera's vertical framing shows the underground half of the world, and a single death orphans all active field hostages, corrupting the win/loss math. Compounding this, both Definition-of-Done gates bypass the input path and would stay green through the worst defect. A second cluster of findings repeats the round-2 failure mode at a smaller scale: four mechanics are ledgered `Exact` that are not (RNG, landing gate, house choice, enemy spawn selection). A focused repair pass on Tasks 10, 11, 13–14, 16–19b — roughly a dozen surgical edits — restores the plan to executable.

## Consensus Findings

All findings below were independently verified by both reviewers against `choplifter.s`. No finding remained contested after Stage 4.

### Critical

**R3-C1 — Landing is unreachable: the plan has no descend input.**
Source `handleJoystickY` (choplifter.s:5630–5658) maps the proportional stick through `joystickYTable` to ACCELY indexes **0–15** — stick-down commands target velocities down to −10. Task 10 only ever sets `accely_index` to 8 (gravity, target −2) or 15 (full thrust, +6). Touchdown requires `VELY ≤ $FBA0` (effectively vy_hi ≤ −5, since the Y algorithm forces VELY_L to 0), which the ease-to-target loop can never reach from a −2 target. No input sequence can land the chopper; boarding, delivery, and the DoD are structurally impossible. Fix: add a `descend` action (and analog stick-Y mapping) covering the full index range.

**R3-C2 — Camera vertical framing shows the wrong half of the world.**
Task 11 sets `ANCHOR_MODE_FIXED_TOP_LEFT` and `camera.position.y = 0.0`. At zoom 480/280, the viewport spans world y ∈ [0, +157.5] — but all gameplay renders at y ≤ 0 (`position.y = −pos_y`). The playfield sits above the top screen edge; the plan never specifies the ground line's screen position. Fix: specify `camera.position.y` (≈ −(view_height − ground_margin)) and add a smoke test that the airborne chopper renders inside the viewport.

**R3-C3 — Mode 1 sortie reload orphans active field hostages.**
Death → SortieBanner → `World.tscn` reload destroys field-hostage *nodes* while `GameState.hostages_active` and the reservoir math persist. Orphaned hostages are unkillable and unrescuable: `total_rescues + hostages_killed` can never reach 64, and the `< 5` spawn throttle stays partially clogged. HF2 (round 2) moved the *counts* into GameState but not the active-record state the counts describe; the plan's comment "active field hostages persist" is false. Fix: persist per-hostage records in GameState (mirroring the source `hostageTable`) or reconcile counts on World reload.

### High

**R3-H1 — RNG port is not faithful but is ledgered `Exact`.**
6502 `rol`/`ror` rotate **through the carry flag** (9-bit); `adc` consumes the carry from `ror`; the extra `inc randomSeed` is gated on `bvc` — the **overflow** flag, not carry (choplifter.s:6069–6083). The plan's `random_byte()` uses 8-bit circular rotates and a carry-out test. Joint framing: bit-exactness is unattainable anyway (the source seed is "whatever was in the accumulator when the loader was done"), so the actionable defect is the false ledger label. Port the algorithm faithfully (through-carry rotates, V-flag gate), and ledger the seed as a documented approximation.

**R3-H2 — Enemy spawn selection diverges from source.**
`spawnEnemyVehicles` (choplifter.s:4582–4618) spawns **at most one** enemy per `$2F` tick, chosen by RNG gates (alien attempt requires `rnd & $28 == 0`, jet attempt requires bit 7 clear, else tank), with caps from per-level tables. The plan's round-2 MF3 "fix" spawns *every* under-cap type on the same tick with no randomness — up to 3 at once. The caps match; the selection doesn't. Restore one-per-tick RNG-gated selection for Mode 1; keep the uniform-timer change behind the Mode 2 guard.

**R3-H3 — `_choose_house` mismatches source and its own comment.**
Source prefers the house **under the chopper** (`CHOP_POS_X_H − FARHOUSE_X_H` ∈ 0–3, choplifter.s:3760–3772), then falls back to a random-start **ring scan** over all 4 houses (exactly one RNG call, guaranteed to find any eligible house, 3774–3795). The plan does 4 independent random draws: no preference, can spuriously fail with eligible houses remaining, and consumes 1–4 RNG calls (divergent stream).

**R3-H4 — Batch level-increment semantics are wrong.**
Source sets `CHOP_LOADED = $FF` on each **boarding** (3552–3557) and clears it on the first unload, gating `inc CURR_LEVEL` (3819–3826). The plan's `_batch_counted` resets when `hostages_loaded` hits 0 — partial-unload → re-board → re-unload sequences increment the level in source but not in the plan. Re-arm the batch flag on boarding.

**R3-H5 — Mode 2 level progression is dead.**
`increment_level_on_unload()` hardcodes `MODE1_LEVEL_CAP` (3); `level_cap()` and `MODE2_LEVEL_CAP` (7) are never used. Mode 2 cannot pass level 3.

**R3-H6 — Jet and alien behavior is fabricated, not source-derived.** *(merges Stage-1 H6 + H7)*
Named, testable symptoms:
- (a) The jet drops a bomb **every frame** while within 150 units (`_check_bomb_drop` has no latch) — ~75+ bombs per pass; also a concrete performance bug.
- (b) The alien **never fires**: the guard `if chopper_pos.y < FIRE_ALTITUDE_THRESHOLD: return` is always true (chopper_pos.y = −pos_y ≤ 0). The source check is on the **alien's own** `ENTITY_Y cmp #$58`, with RNG mask `$48`, gated on mid-section animation frame == 0 and `alienStillAnimating` (choplifter.s:9280–9296) — the plan is wrong in entity, sign, constant, and mask.
- (c) Jet motion in source is table-driven (`jetYVelocityTables` at $6C00); the plan substitutes a constant speed. Source `shellLaunchVTable` is always 3; the plan launches shells at 6.

**R3-H7 — Run-back/door accounting needs an explicit fidelity decision.**
Source: a chopper-full run-back stays `HOSTAGES_ACTIVE`, walks to the door, hits `dec BASE_RUNNERS` (never incremented for it → **underflows to $FF**), and despawns with **no rescue credit**, leaking `HOSTAGES_ACTIVE` (choplifter.s:3460–3471, 3521–3526). The plan half-replicates this (clamps the underflow, leaks active, no credit). Either way, any walk-in makes both the 64-rescue win and the mission-loss condition unreachable. Decide: replicate the source bug exactly (and ledger it, with a DoD caveat that the player must avoid full-chopper run-backs) or fix it as a documented deviation.

**R3-H8 — Both DoD gates bypass the input path.** *(Beta's unique catch)*
The "physics golden-trace" test merely re-asserts Task 8's hand traces through `_physics_process` (tautological; never exercises descend). The rescue-loop integration test force-sets `pos_x/pos_y` and reaches `landed` only through the undocumented `airborne = false` default settle path. Both gates stay green through R3-C1. **Add a third DoD gate:** take off, descend, and land purely via `Input.action_press`, asserting `landed == true`.

### Medium

| # | Finding |
|---|---|
| R3-M1 | Camera scroll clamps should use source `SCROLL_END = $02B0` (688) and `SCROLL_START = $1208` (4616) (choplifter.s:4768–4775), not `[720, 4584]`. |
| R3-M2 | House anchor double-offset: `HOUSE_SRC_X` already bakes in the source's `+$0A` hostage-spawn offset (`$038A…`), then `_spawn_field_hostage` adds another +10. Houses anchor at `$0380 + i·$100`; the single `+$0A` belongs in spawn only (choplifter.s:3858–3866). |
| R3-M3 | Source runs the MIN_VY touchdown check only when `ZP_ACCELX == 0` (X stick centered, choplifter.s:5287–5292); the plan checks every frame. Ledger says `Exact`; it isn't. |
| R3-M4 | Tier B code rot: Task 31's `get_y_acceleration()` is dead (Task 8 named it `get_y_target()` and `_integrate_y` reads the const table); `vel_y = abs(impact_vy) * 0.4` assigns float to `int` (GDScript error); `_handle_landing_mode2` is never wired into `_check_ground`; Task 32 mixes `fire_cooldown: int` with `-= delta` and references undefined `fire_interval`. |
| R3-M5 | Tasks 11/14 reference "16-house layout — Task 33," but Task 33 is world continuity; **no task implements the Reimagined 16-house field**. Task 33 also resets `chopper.position = base.position`, which `_update_render_position` immediately overwrites from stale `pos_x/pos_y`. |
| R3-M6 | RetroTitle demo is unskippable: the skip is gated on `not GameState.demo_mode`; once DEMO starts there is no exit — contradicts "any input skips." |
| R3-M7 | Group-registration gaps: Task 33 frees group `"projectiles"` but no projectile joins it; Alien never does `add_to_group("enemies")`. |
| R3-M8 | Fidelity Ledger has no rows for Jet, Alien, Bullet, Shell, scroll, or parallax, and the plan ships invented constants (jet `SPEED`/`FIRE_INTERVAL`/`BOMB_PROXIMITY`, tank `PATROL_SPEED`/`FIRE_INTERVAL`, bullet `SPEED`, hostage `DETECT_RANGE`) in a document that says "use these; do not guess." Add rows or mark Enhanced. |
| R3-M9 | `House.set_on_fire()` is never called by anything — an unwired mechanic (who burns houses, and when?). Same class as round-2 CF4. |
| R3-M10 | GameState comment "`total_rescues` — counted as each base-runner reaches the door" contradicts the source (counted at **unload**, `inc TOTAL_RESCUES` choplifter.s:3814; the door only does `dec BASE_RUNNERS`, 3468) and the plan's own `_unload_one`. The code is right; fix the comment (and round-2 HF6's wording, which the source contradicts). |
| R3-M11 | The plan has no completed-status markers while Tasks 3, 23, and most of 30 are already done (commits e71e257, a742dce, 690ea2e) and the sprite pipeline is mid-run (117/161). An executor starting at Task 1 could re-init the project and clobber finished/in-flight asset work. **Status annotations only — no pipeline rerun needed.** |

### Low

- **R3-L1** — X-clamp edge: source clamps at `|hi| ≥ $15` (zeroing the low byte at exactly `$15xx`); the plan clamps only `> $15`.
- **R3-L2** — `convert` is deprecated in ImageMagick 7; use `magick`. (Pipeline currently works; note only.)
- **R3-L3** — Asset-pipeline doc drift: Task 30 describes "Scenario MCP, ~165 sprites"; reality is the REST script `src/tools/generate_mode2_sprites.py`, 161 specs, 117 generated. Mode 2 generation also began before v0.1, contradicting the plan's own gate ("do not begin Mode 2 asset work until v0.1 is playable") — update the gate wording to match sanctioned reality. **Doc-only; explicitly no pipeline rerun needed.**

## Contested Findings

None survived to Stage 4. Three framing adjustments were debated and resolved:
- **H6/H7 merge** — resolved: one High finding ("jet/alien fabricated") with bomb-per-frame and never-fires retained as named, testable symptoms (Alpha's condition, Beta accepted).
- **H1 framing** — resolved to Beta's framing: the defect is the false `Exact` ledger label; bit-exact RNG is unattainable due to the uninitialized source seed.
- **L4 severity** — resolved to Medium (R3-M11): with the pipeline mid-run, clobber risk is a near-term hazard, not housekeeping.

## Unique Insights

- **Alpha (survived):** R3-C1 (no descend input — the round's most important finding), R3-C3 (orphaned active hostages), R3-H2/H3/H4 (spawn-selection, house-choice, and batch-semantics drift), R3-H7 (run-back underflow/leak), R3-M2 (double offset, verifiable to the byte).
- **Beta (survived):** R3-H8 (both DoD gates bypass the input layer; golden trace is tautological; the integration test depends on an undocumented default settle path) — the insight that explains *why* C1 would ship undetected. The alien-fire refinement (wrong entity/constant/mask + missing animation gates, choplifter.s:9280–9296). The RNG seed-unattainability framing.
- **Joint (emerged in debate):** the third DoD gate — land via the real input path — is the single test that converts C1 from invisible to caught.

## Strengths

Both reviewers agree the plan gets these right (verified against source):
- **The chopper integration is now a correct port** — ease-to-target Y with halve-when-≥2, X friction `VELX −= VELX>>4`, 16-bit accel table, `±$15` clamp (choplifter.s:5160–5267), with correct golden traces `[3,4,5,6,6]` / `[−1,−2,−2]`.
- **Hostage topology, boarding band ([8,10) board, <8 crush), 16-aboard cap with run-back, 4-frame cadence, spawn-anytime gating, and unload-time rescue crediting** all match the disassembly.
- **Task 3b/3c/3d** (Area2D hitbox architecture, source-unit coordinate model, Fidelity Ledger) are the right structural safeguards — this round's findings are mostly the ledger *not being applied broadly enough*, which validates the ledger concept.
- The SFX pipeline is correct, deterministic, and already shipped; the variant-guard architecture and milestone sequencing remain sound.

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|----------|---------|----------------|-----------|
| 1 | Critical | R3-C1 no descend input | Add `descend` action mapping `accely_index` below 8 (full `joystickYTable` range); Task 10 | Unanimous |
| 2 | Critical | R3-C2 camera framing | Specify `camera.position.y` / ground-line screen row; add viewport smoke test; Task 11 | Unanimous |
| 3 | Critical | R3-C3 orphaned hostages | Persist active-hostage records in GameState or reconcile on World reload; Tasks 14/19 | Unanimous |
| 4 | High | R3-H8 DoD gates blind | Add third DoD gate: take off → descend → land via `Input.action_press`, assert `landed` | Unanimous |
| 5 | High | R3-H2 spawn selection | One enemy per `$2F` tick, RNG-gated alien/jet/tank selection for Mode 1; Task 16 | Unanimous |
| 6 | High | R3-H3 house choice | Under-chopper preference + random-start ring scan; Task 14 | Unanimous |
| 7 | High | R3-H4 batch semantics | Re-arm `_batch_counted` on boarding (CHOP_LOADED semantics); Task 14 | Unanimous |
| 8 | High | R3-H5 Mode 2 level cap | Use `level_cap()` in `increment_level_on_unload()`; Task 4 | Unanimous |
| 9 | High | R3-H6 jet/alien fabricated | Bomb-drop latch; alien fire on own Y < $58, mask $48, animation gates; ledger or source the motion tables; Tasks 17/18 | Unanimous |
| 10 | High | R3-H7 run-back accounting | Decide replicate-vs-fix; ledger row; DoD caveat; Task 14 | Unanimous |
| 11 | High | R3-H1 RNG ledger label | Faithful algorithm port (through-carry rol/ror, V-flag); reclassify ledger row; Task 4 | Unanimous |
| 12 | Medium | R3-M1–M10 | Apply the ten Medium fixes (mostly one-line diffs; M4/M5 block Tier B from compiling) | Unanimous |
| 13 | Medium | R3-M11 status markers | Mark Tasks 1–3, 23, 30 status before any plan execution; protect in-flight pipeline | Unanimous |
| 14 | Low | R3-L1–L3 | Edge-clamp note; `magick`; update Task 30 pipeline text + gate wording (**doc-only, no rerun**) | Unanimous |

## Review Process Notes

**Where the adversarial process added the most value.** Alpha (source-verification focus) found the unwinnability cluster (C1/C3) and four "ledgered-Exact-but-isn't" divergences by re-deriving each mechanic from the disassembly. Beta's decisive contribution was meta-level: proving the plan's *own acceptance gates* could not detect Alpha's top finding (R3-H8), which converted "fix the input" into "fix the input *and* the gate that should have caught it." Beta also corrected Alpha's alien-fire diagnosis from "inverted sign" to "wrong entity entirely," sharpening the fix.

**Blind spots.** Alpha initially understated the alien-fire divergence and rated the executor-clobber risk Low despite the pipeline being mid-run. Beta added no new Criticals of its own — its strength was auditing the verification machinery rather than the mechanics. Both reviewers note that round 2's MF3 "fix" (independent per-type spawn checks) *introduced* R3-H2 — a caution that review-driven fixes need the same source verification as original plan content.

**Highest-value next action.** A single repair commit to the plan covering R3-C1/C2/C3 + the third DoD gate, before any further task execution. The Medium set can be batched into the affected task texts. Nothing in this review touches the running asset pipeline.

---

## Addendum (2026-06-11, post-review fix pass)

**R3-C4 — The house model was inverted (found while wiring R3-M9; both reviewers missed it).**
While answering M9's "who burns houses?", the fix pass found the plan's entire house mechanic was
backwards. Source ground truth: `houseStates` polarity is **$00 = untouched/closed, $01 = on
fire/open** (choplifter.s:5097); `igniteHouse` "sets a house on fire, **releasing** all the
hostages inside" (8985–8998) and is triggered by ordnance hitting the house strip (8605–8616);
`spawnHostages` skips houses whose state is **0** — hostages emerge **only from ignited houses**.
At game start, `spawnInitialHostages` (11341–11360) pre-ignites house 3 and fields 8 of its
hostages. The plan had hostages emerging from *intact* houses from frame 0, fire *killing*
occupants, and nothing ever igniting a house. Both reviewers read the eligibility check with the
plan's polarity and validated "spawn-anytime gating" as faithful — a shared blind spot worth
noting for round 4: verify the *meaning* of each flag against its declaration comment, not just
the control flow.

Applied in the same fix pass: corrected polarity and release semantics, bullet→house ignition
wiring (new collision layer 8), game-start house-3 setup seeded through the R3-C3
`field_hostage_records` machinery, and ledger/test updates. One open question is flagged in the
plan: the source ordnance-vs-house check covers house pages 0–2 only (`cmp #$03`), which is
consistent with house 3 starting open but should be verified in an emulator before being relied on.
