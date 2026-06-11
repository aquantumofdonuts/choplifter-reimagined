# Adversarial Design Review: ENHANCED_GAMEPLAY.md

**Date:** 2026-06-07
**Reviewer Alpha:** Claude Sonnet 4.6
**Reviewer Beta:** Claude Opus 4.8
**Document:** `docs/ENHANCED_GAMEPLAY.md`

---

## Executive Summary

The design document is structurally sound: the Tier A/B/C superset model is the right architecture, the additive guard pattern correctly implements it, and many of the Tier C mechanics (fuel hops, scatter) are individually well-reasoned. However, the adversarial process surfaced two high-severity defects that would produce incorrect behavior on implementation: the tank-spawn bug description targets the wrong code path (both reviewers verified against `choplifter.s`), and Tier B and Tier C have a direct logical contradiction in hostage death accounting. The document also contains an unverified loss-condition formula whose dimensions don't match its stated purpose. The design is implementable after these issues are resolved; it should not be handed to implementation as written.

---

## Consensus Findings

Both reviewers agree on the following. These are the highest-confidence findings.

### Critical

**C1 — Tank spawn bug description is wrong and the proposed fix overcorrects (§3.1)**

The source has two spawn paths: `spawnTankNegV` (player heading left, lines 3908–3915) correctly computes `ENTITY_X_H` from `$05`; `spawnTankPosV` (player heading right, lines 3920–3929) always stores `#$00` into `ENTITY_X_H`. The disassembler's own inline comment confirms this ("This does nothing — a bug or old code?"). The document describes the bug as universal ("tanks cluster at the world's left edge") and prescribes a blanket override "across all 8 depth planes." Implementing that override would also replace the working left-path code, introducing a regression.

**Fix:** Scope the bug description and the override to `spawnTankPosV` only. The left-moving path is correct and should not be touched.

### High

**C2 — §4.3 and §5.2 are logically contradictory in Reimagined mode**

Section 4.3 (Tier B, world continuity) states: "hostages aboard at death are added to `HOSTAGES_KILLED` before continuity is saved." Section 5.2 (Tier C, scatter on death) states: "each carried hostage spawns as a STRANDED entity." Both rules are active in Reimagined. As written, aboard hostages are simultaneously killed (4.3) and stranded (5.2). No override is stated.

**Fix:** Add an explicit rule: in Reimagined mode, §5.2 supersedes the §4.3 kill-accounting rule for aboard hostages. Aboard hostages at death become STRANDED, not counted in `HOSTAGES_KILLED` (they are only added to `HOSTAGES_KILLED` if their strand timer expires without rescue). This resolution is also the one most consistent with the mechanic's purpose.

**C4 — Grade evaluation order is undefined (§5.1)**

The grade threshold table lists conditions as independent predicates. Grade C's condition ("4–8 casualties OR 3 sorties used") overlaps with Grade A ("0 casualties, any sorties"). The document never states that grades are evaluated top-down with first-match winning. An implementer reading the table could produce a range of behaviors.

**Fix:** Add a note: "Grades are evaluated top-down; the first matching condition wins."

**C5 — Stranded hostage persistence across sorties is unspecified (§5.2)**

When a new sortie starts in Reimagined mode, the continuity rules (§4.3) state field hostages are reset. STRANDED hostages are a new state not addressed by these rules. Do they persist into the next sortie (the mechanic's value), get killed, or disappear silently?

**Fix:** Add an explicit rule: STRANDED hostages persist into the next sortie. They are not subject to the field-hostage reset. Their countdown timers continue from where they left off.

**C6 — Bounce-limit counter reset is underspecified (§4.1)**

"After 3 consecutive bounces without gaining meaningful altitude" — "consecutive" is undefined. Does any flight clear the counter, or only gaining `vy_peak >= MIN_VY × 0.5` after a bounce?

**Fix:** Define: the consecutive bounce counter resets when the chopper achieves `vy_peak >= MIN_VY × 0.5` on an upward trajectory after a bounce. A bounce that does not reach that peak does not reset the counter.

### Medium

**C9 — Jet approach randomization (Tier B) conflicts with jet coordination (Tier C) (§4.2, §5.4)**

Director's Cut (§4.2) randomizes jet initial facing at all levels. Reimagined (§5.4) assigns opposing directions when 2 jets are active. In Reimagined, both are active simultaneously. If jet 1 spawned with random facing, does jet coordination override that when jet 2 arrives? The `jet_directions_assigned: bool` flag in `SpawnManager.gd` doesn't resolve this.

**Fix:** In Reimagined, when a 2nd jet spawns, override jet 1's current approach direction to enforce the opposing-direction rule. The Tier C behavior supersedes Tier B's per-jet randomization in the 2-jet case.

**C10 — Enemy charge timer behavior when target leaves range is unspecified (§4.2)**

The 24-frame telegraph fires the projectile when `charge_timer` reaches 0, but the document doesn't say what happens if the player moves out of firing range during the charge.

**Fix:** State a defined behavior. Recommended: fire in the last-known player direction (wasted shot) — this avoids silent timer resets which could feel like AI "cheating" if exploited.

**C11 — Fuel × scatter combined feasibility is unanalyzed (§5.2, §5.3)**

At 25% emergency fuel per field landing, a chopper may be unable to reach stranded hostages within their 30-second window, especially if the crash site is far from the player's forced emergency landing location. The two systems were designed independently and their combined failure mode is not addressed.

**Fix:** Add a feasibility note. Either: (a) guarantee via playtesting that the 30-second timer is survivable on 25%-fuel hops from a worst-case emergency landing position; or (b) pause the strand timer while the player is performing a fuel emergency hop back toward the crash site.

**C12 — Alien fire base probability is missing (§4.3)**

The difficulty scaling table adds "+10%/+20%/+30%/+40%" alien fire probability at levels 4–7. These are relative modifiers with no stated base. A +30% modifier on 5% base is very different from +30% on 50% base.

**Fix:** State the base fire probability at level 3 alongside the scaling table.

**C13 — RNG seeding policy is undefined (§5.1, §5.5)**

Mission Rating and Persistent Records reward clean, fast runs. Enemy spawns use a free-running RNG. Grades are therefore partly luck-dependent. No seeding policy is stated — does a rated run use a fixed seed, or is RNG free-running?

**Fix:** State the seeding policy. Recommended: free-running RNG (matching game feel) with a note that grade thresholds should be set conservatively to account for RNG variance.

**C14 — HUD headroom display and stranded hostages (§3.2, §5.2)**

The headroom indicator ("how many more hostage deaths end the run") doesn't specify whether stranded hostages (not yet dead, not yet rescued) count as potential deaths. If they do, the counter should show them as "at-risk" to give the player accurate stakes information.

**Fix:** Clarify: stranded hostages are NOT counted in `HOSTAGES_KILLED` until their timer expires. The headroom indicator should treat them as at-risk (e.g. display the count in a warning color or with an indicator).

**C8 — `CRASH_VY` should be explicitly identified as a new Mode-2 construct (§4.1)**

`CRASH_VY = MIN_VY × 2.0` invents a new vertical landing band for Mode 2. The source's `CRASHSPEED` (line 4796) governs horizontal crash magnitude, not vertical landing — despite a misleading source annotation that labels it as Y-velocity. Deriving `CRASH_VY` from `MIN_VY` is valid, but the naming similarity to `CRASHSPEED` and the wrong source comment create a future-contributor trap.

**Fix:** Add a note: `CRASH_VY` is a new Mode-2 construct. Source `CRASHSPEED` is a horizontal crash threshold and is not the basis for `CRASH_VY`.

### Low

**C15 — Scroll lead rescaling is misclassified in the §6.3 summary table**

§3.2 correctly places scroll lead rescaling under Tier A. The §6.3 table lists it under `Chopper.gd → Tier B`. The body text wins; the table cell is a typo.

**Fix:** Move scroll lead rescaling from the Tier B column to the Tier A column in the §6.3 table.

**C16 — Fuel landing handler ordering**

"Full refill only happens on base landing" and "on touching ground anywhere, fuel refills to 25%" — the document's intent is clear but the implementation note doesn't distinguish the two paths. Low risk of being misimplemented.

**Fix:** Add implementation note: base landing handler runs `fuel = 1.0` regardless of prior emergency refills; the 25% emergency refill only applies in non-base landing handlers.

**C17 — Bounce `vy_peak` units need a precise definition (§4.1)**

`vy_peak < MIN_VY × 0.5` compares an upward-bounce peak velocity with a landing detection threshold. Units and sign conventions need to be explicit.

**Fix:** Define: `vy_peak` is the maximum upward speed (positive, in pixels/frame) achieved after a bounce. `MIN_VY` is a landing-detect threshold (also positive). The comparison is scalar magnitude.

**C18 — AccelY smoothing is one-sided on an asymmetric table (§4.1)**

The source `integrateAccelerationAccelYTable` is asymmetric (down to −10, up to +6). The Tier B change softens only the up tail (+6 → +5). The "overall thrust envelope is preserved" claim is slightly imprecise.

**Fix:** Add: "Only the positive (upward) tail is modified. The negative (downward) acceleration profile is unchanged."

**C19 — Pause semantics for timed systems are undefined (§5.2, §5.3)**

The strand countdown (`_process` decrement) and fuel depletion run in engine time. Does game pause freeze them?

**Fix:** State: game pause freezes both the strand timer and fuel depletion rate. Both use Godot's `_process(delta)` and respond to `SceneTree.paused`.

**C20 — Mode 3 (Hi-Res) tuning values are absent**

All numeric tuning values (scroll lead, capacity constants) are given for Mode 2 (480px frame). Mode 3 resolution and its scaling implications are unaddressed.

**Fix:** Either add Mode 3 scaling equivalents or add an explicit note: "All numeric values in this document are Mode-2-specific; Mode 3 values are derived by the same proportional scaling from the Mode 3 frame width."

---

## Contested Findings

### C3 — Loss condition formula (§3.2)

**Alpha's position:** The formula `64 - TOTAL_RESCUES - HOSTAGES_KILLED` computes "hostages still in play," not "deaths until loss." The HUD label ("how many more hostage deaths end the run") doesn't match. This may be a labeling error or a formula error — direction depends on source.

**Beta's position:** The formula is dimensionally wrong for its stated role as a run-ending metric. A quantity that *decreases on rescue* should not be what ends the run on *deaths*. The formula needs source verification, not just the label.

**Verdict (Alpha as Judge): Beta is right.** The formula as written means rescuing hostages shrinks the "headroom" displayed to the player — the opposite of the intended feedback. The run-ending condition should be based on a death budget (`MAX_KILLS_ALLOWED - HOSTAGES_KILLED`), not on remaining field population. The document's formula is wrong; the fix direction is: (a) source-verify the actual loss trigger, (b) rewrite the formula to compute deaths-to-loss, (c) verify the HUD label matches the corrected formula. Severity: High.

### C7 — Spawn cadence classification (§3.1)

**Alpha's position:** The `$2F` bitmask non-uniformity is a characteristically accidental bug. The design author calls it a bug; defer to that judgment.

**Beta's position:** Beta source-verified that the disassembler's "every 47 frames" comment is wrong. The actual pattern is 16/48-frame alternating (structural artifact of bitmask + `beq`). The author's "bug" call may rest on the incorrect annotation. Without confirmed authorial intent, reclassifying to Tier B is safer.

**Verdict (Alpha as Judge): Beta is right on the process argument.** The author's classification may rest on a wrong annotation. Since we cannot determine whether the 16/48 pattern was intended game rhythm or an unnoticed artifact, treating it as a rhythm change (Tier B) rather than a defect correction (Tier A) is the more conservative and reversible call. If the project author confirms the non-uniformity was unintended, it can be reclassified to Tier A. Severity: Medium; reclassify to Tier B pending author confirmation.

---

## Unique Insights

**From Reviewer Beta (Opus):**
- Source verification caught a directional bug in the tank spawn description that would have caused a regression in the working left-moving code path.
- The disassembler's own inline comment for `spawnTankPosV` ("This does nothing — a bug or old code?") confirms the bug, but for the `$2F` cadence, the disassembler comment is itself wrong. This means comment-level verification is insufficient; behavior must be traced from the opcode sequence.
- The CRASHSPEED/MIN_VY axis confusion is present in the source comments themselves — a misleading annotation that will trap future contributors.

**From Reviewer Alpha (Sonnet):**
- The 4.3/5.2 hostage contradiction reveals a structural gap: when Tier C overrides a Tier B rule, the document has no mechanism to state that. A "Tier C Overrides" table would prevent this class of error in future additions.
- The RNG seeding gap directly undermines the Mission Rating system's value proposition. A grading system that rewards clean play while using free-running RNG needs either seeding policy or conservative grade thresholds.
- Five TBD values are interdependent (fuel depletion rate affects strand-timer feasibility; CRASH_VY affects death condition; grade thresholds affect the entire rating system). These should be tested together, not in isolation.

---

## Strengths (Both Reviewers Agree)

- **The `>= variant` integer guard pattern** correctly implements the superset relationship without forking.
- **The §6.3 affected-systems table** is high-value — it maps features to files and tiers, preventing implementation drift.
- **The fuel "hops" loop** (25% emergency refill per field touch, full refill at base) is an elegant resolution of what could have been a death spiral.
- **Most source citations in §3.1** are correctly traceable (alien fire bug, level cap, AccelY table) and use assembly-level specificity that enables verification.
- **Conservative scope discipline in Tier C**: scatter and fuel are layered on top of core mechanics, not replacing them.
- **The roadmap phasing** (bug fixes at v0.2, enhancements at v0.4, new mechanics at v0.5) is sensible and low-risk.

---

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|----------|---------|----------------|-----------|
| 1 | Critical | Tank spawn bug targets both paths; fix overcorrects (§3.1) | Scope fix and description to `spawnTankPosV` only; leave `spawnTankNegV` untouched | Unanimous |
| 2 | High | §4.3 ↔ §5.2 logical contradiction (Reimagined) | Add: "In Reimagined, §5.2 supersedes §4.3 kill-accounting for aboard hostages" | Unanimous |
| 3 | High | Loss formula computes wrong quantity (§3.2) | Source-verify loss trigger; rewrite formula to compute deaths-to-loss budget | Majority (Beta stronger framing; Alpha concedes) |
| 4 | High | Grade evaluation order undefined (§5.1) | Add: "Grades checked top-down; first match wins" | Unanimous |
| 5 | High | Stranded hostage persistence across sorties undefined (§5.2) | Add: STRANDED hostages persist into next sortie; countdown continues | Unanimous |
| 6 | High | Bounce counter reset underspecified (§4.1) | Define: counter resets when `vy_peak >= MIN_VY × 0.5` after a bounce | Unanimous |
| 7 | Medium | Spawn cadence misfiled as Tier A (§3.1) | Reclassify to Tier B pending author confirmation of intent | Majority (Beta convinced Alpha) |
| 8 | Medium | `CRASH_VY` needs source-connection disclaimer (§4.1) | Add: "`CRASH_VY` is a Mode-2 construct; source `CRASHSPEED` is horizontal, not its basis" | Majority (merged fix) |
| 9 | Medium | Jet B/C interaction unresolved (§4.2, §5.4) | In Reimagined, 2nd jet spawn overrides jet 1 direction for opposing-pair rule | Unanimous |
| 10 | Medium | Charge timer out-of-range behavior unspecified (§4.2) | State: fire in last-known direction when timer expires regardless of player position | Unanimous |
| 11 | Medium | Fuel × scatter feasibility unanalyzed (§5.2, §5.3) | Verify 30s strand recovery is achievable on 25%-fuel hops, or pause timer during hops | Unanimous |
| 12 | Medium | Alien fire base probability missing (§4.3) | State base probability at level 3 in the difficulty scaling table | Unanimous |
| 13 | Medium | RNG seeding undefined (§5.1, §5.5) | State policy: free-running RNG + conservative grade thresholds | Unanimous |
| 14 | Medium | HUD headroom vs. stranded hostages (§3.2, §5.2) | Stranded hostages count as at-risk in the headroom display | Unanimous |
| 15 | Low | Scroll lead misclassified in §6.3 table | Move from Tier B to Tier A column in §6.3 | Unanimous |
| 16 | Low | Fuel handler implementation ordering | Base landing always sets `fuel = 1.0`; 25% only on non-base landing | Unanimous |
| 17 | Low | `vy_peak` units undefined | Define: positive pixels/frame, upward trajectory after bounce | Unanimous |
| 18 | Low | AccelY smoothing is one-sided | Note: only positive (upward) tail modified | Unanimous |
| 19 | Low | Pause semantics for strand/fuel timers | State: pause freezes both; both use `_process(delta)` | Unanimous |
| 20 | Low | Mode 3 tuning values absent | Add Mode-3 scaling note or mark values Mode-2-specific | Unanimous |

### Structural Recommendations (Both Reviewers)

**S1 — Add a "Tier C Overrides" table** between §4 and §5, listing each Tier B rule superseded in Reimagined mode: superseded rule (§ ref) → replacement rule (§ ref). Seed entries: C2 (§4.3 kill-accounting → §5.2 scatter), C9 (§4.2 jet randomization → §5.4 jet coordination in 2-jet case). This prevents the C2-class contradiction from recurring as Tier C expands.

**S2 — Every §3.1 bug fix must cite a specific source line reference** (function label or line number), and citations must be verified against opcode sequences — not against disassembler comments, which have been found to be wrong in two cases (the `$2F` cadence annotation and the `CRASHSPEED_H` axis annotation).

---

## Review Process Notes

**Where the adversarial process added the most value:**
- **B1 (tank spawn):** The single most consequential finding came only because Beta checked the actual disassembly. No amount of document-level review would have caught it. The adversarial setup created pressure to go to primary sources.
- **B3 (4.3/5.2 contradiction):** Alpha identified a persistence gap; Beta found the stronger logical contradiction underneath it. The staging format — where Beta reads Alpha's work and then goes deeper — surfaced a finding neither would have produced alone.
- **C7 (cadence source comment was wrong):** The multi-pass source verification revealed that a disassembler annotation used as justification was itself incorrect, reversing the classification call. This would not have been caught in a single-reviewer pass.

**Blind spots by model:**
- **Alpha (Sonnet):** Praised source-fidelity without consulting the source; over-severitized a documentation typo; missed the 4.3/5.2 kill-accounting contradiction; missed the loss-formula dimensional problem.
- **Beta (Opus):** Initially framed the CRASH_VY finding as "conflation" (slightly overstated); didn't initially flag the RNG/grading tension explicitly until the process created space for extended analysis.

**Process note for future reviews:** For design documents whose value proposition is source-fidelity, the review should include a mandatory source-verification step that checks each cited claim against actual code behavior (not comments). Assign source verification explicitly to one reviewer.
