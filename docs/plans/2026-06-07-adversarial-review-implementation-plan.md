# Adversarial Design Review: 2026-06-07-implementation-plan.md

**Date:** 2026-06-07  
**Reviewer Alpha:** GitHub Copilot  
**Reviewer Beta:** Explore subagent  
**Document:** `docs/plans/2026-06-07-implementation-plan.md`  
**Context Reviewed:** `docs/DESIGN.md`, `docs/ENHANCED_GAMEPLAY.md`, `docs/ASSET_PIPELINE.md`, `docs/blondie-ChoplifterReverse/choplifter.s`, `docs/blondie-ChoplifterReverse/zeropage.s`

## Executive Summary

The current implementation plan is much stronger than the prior adversarial-review baseline: earlier blockers around `WORLD_BOUNDS_RIGHT`, camera anchoring, victory signal wiring, pause-menu scope, collision layers, and the circular Definition of Done have been addressed. The remaining risks are more fundamental to Mode 1 fidelity: the hostage topology in the plan now diverges from the source, the hostage lifecycle is still not wired end to end, and the physics/coordinate model is under-specified. As written, v0.1 can still pass many unit tests while failing the core rescue loop in production. The plan should not proceed past Task 8-14 until the hostage model, coordinate normalization, and physics unit contract are corrected.

## Consensus Findings

### C1 - Hostage Topology Conflicts With Source [Critical]

The plan's Task 14 claims a source-faithful world with **16 houses total**, each holding 4 hostages, and states that there is no wave-respawn model. The source does not support that topology.

The original source initializes four house counters (`houseStates`, `hostagesInHouses`) and sets each house to `$10` hostages, with `HOSTAGES_LEFT = $40` and `MAX_HOSTAGES = 16` meaning active hostage slots, not house count. `spawnHostages` chooses among four houses and enforces a maximum of 16 active/base-running hostages at a time.

This must be resolved before implementation. Either the plan should model the source as four houses with 64 total hostages and 16 active slots, or it should explicitly declare a non-faithful 16-house simplification and keep that out of Mode 1.

### C2 - Hostages Never Spawn In Production [Critical]

`House.try_release_hostage(frame_count)` is defined, but the plan never calls it from `World`, `SpawnManager`, or any other production loop. `World._physics_process()` increments `_frame_count`, updates camera, and calls `spawn_manager.tick(_frame_count)`, while `SpawnManager.tick()` handles enemy spawn attempts only.

Result: houses can exist with nonzero hostage counts, but no hostage nodes enter the world unless tests instantiate them directly.

### C3 - Waving Hostages Never Start Running [Critical]

`Hostage.on_chopper_landed(chopper_pos)` performs the `WAVING -> RUNNING` transition and is tested directly, but no production code invokes it. `Chopper._check_boarding_nearby_hostages()` calls `hostage._check_boarding(position)`, which only acts on hostages already in `RUNNING` state.

The source `updateHostages` reevaluates chopper landed/airborne/base state every frame and uses that to choose hostage movement. The plan needs an equivalent production call path.

### C4 - Boarding Does Not Complete [Critical]

`Hostage._check_boarding()` sets `state = LOADING`, but the plan does not advance the loading animation or call `board_chopper(chopper)`. `board_chopper()` is therefore dead code in the current snippets.

This breaks the rescue loop: even if hostages spawn and run, they can become stuck in `LOADING`, never increment `hostages_aboard`, and never make victory reachable.

### C5 - Coordinate Model Is Inconsistent With Source Bounds [Critical]

The source defines `BOUNDS_LEFT = $02D0` (720) and `BOUNDS_RIGHT = $1300` (4864). The plan sets `WORLD_BOUNDS_LEFT = 0.0` and `WORLD_BOUNDS_RIGHT = 4864.0`, which is neither raw source coordinates nor a normalized span.

If the port normalizes left to 0, the right bound should be transformed consistently. If it uses raw source coordinates, left should remain 720. This affects chopper clamp, camera clamp, projectile despawn, tank spawn clamps, and house placement.

### C6 - Physics Units Mix Frame-Based Source Math With Godot Px/S [High]

The plan says Mode 1 uses source-faithful frame-based integration, but snippets accumulate values such as `vel_y += get_y_acceleration()` per physics frame and then assign those values to `CharacterBody2D.velocity`, which Godot treats as pixels/second in `move_and_slide()`.

Examples include chopper acceleration, hostage `RUN_SPEED = 28.0 # px/frame` assigned to `velocity.x`, bullet frame-based gravity mixed with `SPEED` px/s, and shell/bomb delta-based gravity. Without an explicit conversion policy, source constants will be off by large factors and entity feel will be tuned against accidental unit errors.

### C7 - Landing Constants Are Not Extracted Before Landing Logic [High]

`DESIGN.md` requires Mode 1 landing behavior to use source values for `MIN_VY`, `LAUNCHTHRESH`, `CRASHSPEED`, bounce thrust, and sinking thresholds. The plan's base landing task handles delivery and landed flags but does not first extract or test those values.

Relevant source constants include `MIN_VY = $FBA0`, `CRASHSPEED = $EB01`, `LAUNCHTHRESH = $0100`, and `MAX_SINK = $06`. These should be captured before Task 13 lands, not retrofitted during Tier B tuning.

### C8 - Chopper Capacity Constraint Is Missing [High]

The source caps `HOSTAGES_LOADED` at `$10` before allowing boarding. The plan's `board_chopper()` increments `chopper.hostages_aboard` and `GameState.hostages_loaded` without a max-capacity guard.

This is a semantic fidelity bug, not a runtime integer overflow. Add a `MAX_HOSTAGES_ABOARD = 16` constant and tests for full-chopper behavior.

### C9 - Entity Groups And Cleanup Are Under-Specified [Medium]

The plan relies on groups for important behavior, including `get_tree().get_nodes_in_group("hostages")` and sortie reset cleanup of `enemies` and `projectiles`. Some snippets register groups (`Hostage`, `Tank`), but bullets, shells, missiles, bombs, jets, and aliens are not consistently shown adding themselves to their required groups.

This can leave stale entities after sortie reset and make production behavior differ from tests.

### C10 - Mode 1 Spawn Details Are Approximate [Medium]

Enemy spawning is close enough for a first structural pass but not yet source-faithful. The plan uses deterministic tank-then-jet-then-alien priority rather than fully reproducing source random/table selection. It also approximates the `spawnTankPosV` bug as random page-0 placement, while the source keeps `ENTITY_X_L = CHOP_POS_X_L + $B0` and only incorrectly zeroes `ENTITY_X_H`.

These are lower priority than the rescue-loop blockers, but should be corrected before calling Mode 1 faithful.

### C11 - Runtime Audio Wiring Is Incomplete [Medium]

The pipeline generates `engine_loop` and alien crackle SFX, and the design requires continuous rotor audio and alien crackle keyed to animation frame. The implementation plan does not yet wire engine loop start/stop/pitch or alien animation-frame crackle at runtime.

### C12 - Audio Bus Setup Is Manual [Medium]

Task 6 creates SFX and Music buses through the Godot UI and commits `default_bus_layout.tres`, but the plan does not verify that the file is created and versioned or provide a code fallback. This is reproducibility risk for fresh clones and CI.

### C13 - Retro Title Timings Are Guessed [Low]

The Retro title sequence uses hardcoded 2s/3s/2s phase durations. For strict Mode 1 fidelity, the frame timings should be extracted from the source or explicitly marked as approximate v0.1 presentation timing.

## Contested Findings

### W1 - 16-House Model: Verdict, Alpha Correct

Beta initially listed the 16-house model as a strength, then independently rejected it after checking the source. The final position accepts that the plan and source are inconsistent. The source has four house counters with 16 occupants each and a 16-active-hostage slot limit, not 16 simultaneous houses with four occupants each.

### W2 - `on_chopper_landed()` Wiring: Verdict, Alpha Correct

Beta's critique claimed `Chopper._check_boarding_nearby_hostages()` calls `on_chopper_landed()`. Re-reading the plan shows it calls `_check_boarding(position)`, not `on_chopper_landed()`. Therefore the `WAVING -> RUNNING` production transition remains unwired.

### W3 - Enemy Spawn Cadence: Verdict, Not A v0.1 Defect

The `$2F` bitmask cadence is intentionally source-faithful for Mode 1. Tier A later replacing it with a uniform timer is consistent with the variant design. The remaining requirement is test coverage proving Mode 1 preserves the bitmask and Mode 2 Standard uses the uniform timer.

### W4 - Capacity Wording: Verdict, Finding Valid, Framing Softened

The missing hostage capacity is not a runtime overflow problem in GDScript. It is a missing source constraint that can corrupt gameplay semantics. The recommendation stands, with softened framing.

## Unique Insights

- Alpha caught the core production-wiring gap across three separate hostage transitions: house release, landed-chopper run trigger, and boarding completion.
- Beta added useful secondary gaps around house refill/wave ambiguity, audio bus reproducibility, and title timing approximation.
- The debate clarified that some issues are deliberate Mode 1 bugs (`$2F` spawn cadence, alien fire equality, tank spawn high-byte bug), while others are inaccurate approximations of source behavior.
- Both reviewers converged on the need for a single pre-implementation constants/coordinate/physics pass before entity work continues.

## Strengths

- The plan has incorporated several high-value fixes from the earlier review: world bounds live on `GameState`, camera anchoring is explicit, victory signal wiring exists, `Phase.values()` is gone, collision layers are planned, pause menu is scoped, and Definition of Done is behavior-based.
- The version sequencing is sensible: v0.1 playable Retro core first, Mode 2 assets and Scenario dependency later.
- The architectural pattern of Mode 1 fidelity plus guarded Mode 2/3 enhancements is the right foundation.
- The plan's TDD shape is good; the main weakness is that several tests exercise helper methods directly instead of production wiring.

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|---|---|---|---|
| 1 | Critical | Hostage topology conflicts with source | Replace 16-house model with source-backed four-house/64-hostage/16-active-slot model, or explicitly mark 16 houses as non-faithful and exclude from Mode 1 | Unanimous |
| 2 | Critical | Hostages never spawn in production | Call `House.try_release_hostage(frame_count)` from `World` or `SpawnManager`; add production integration test | Unanimous |
| 3 | Critical | `WAVING -> RUNNING` transition unwired | Call `Hostage.on_chopper_landed()` or equivalent when the chopper lands near hostages/houses | Unanimous |
| 4 | Critical | `LOADING -> aboard` transition unwired | Add loading completion and call `board_chopper(chopper)`; test one full board cycle through production code | Unanimous |
| 5 | Critical | Coordinate bounds inconsistent | Decide raw vs normalized source coordinates; update `WORLD_BOUNDS_LEFT/RIGHT`, camera clamps, house coordinates, and spawn clamps together | Unanimous |
| 6 | High | Physics unit model undefined | Add a physics-unit policy before Task 8: source fixed-point/frame stepping or explicit conversion to Godot px/s | Unanimous |
| 7 | High | Landing constants missing | Extract `MIN_VY`, `LAUNCHTHRESH`, `CRASHSPEED`, `MAX_SINK`, and bounce behavior before Task 13 | Unanimous |
| 8 | High | Missing hostage capacity | Add `MAX_HOSTAGES_ABOARD = 16`, guard boarding, and test full-capacity behavior | Unanimous |
| 9 | Medium | Groups/cleanup incomplete | Add `_ready()` group registration requirements for all enemies/projectiles/hostages and tests for sortie reset cleanup | Unanimous |
| 10 | Medium | Spawn behavior approximated | Source-verify enemy choice tables and exact tank high-byte bug before claiming Mode 1 fidelity | Unanimous |
| 11 | Medium | Runtime audio loops missing | Add tasks for chopper engine loop and alien crackle keyed to animation state | Unanimous |
| 12 | Medium | Audio bus reproducibility | Verify `default_bus_layout.tres` is committed or auto-create buses in `AudioManager` | Beta-led |
| 13 | Low | Retro title timings guessed | Extract source frame timings or mark durations as approximate | Beta-led |

## Review Process Notes

The adversarial process added the most value by separating stale findings from current ones. The old report's critical items around camera anchoring, victory signal wiring, and world-bound ownership have been fixed; repeating them would have created noise. The second pass exposed deeper remaining issues: source topology, production wiring, and unit consistency.

Reviewer Alpha's main blind spot was initially treating deterministic enemy spawn priority as more urgent than it is. Reviewer Beta's main blind spot was a mistaken claim that `on_chopper_landed()` was wired and an initial contradiction around the 16-house model. Cross-checking against the source resolved both.

The next review should happen after the plan is patched in Tasks 8-14. The highest-value acceptance test is not another isolated unit test; it is an integration test proving that, through production `World` code, one hostage can spawn from a house, run to a landed chopper, board, be delivered to base, and increment `GameState.total_rescues`.
