# Adversarial Design Review: DESIGN.md — Mode 1 Faithful Port Fidelity

**Date:** 2026-06-06
**Reviewer Alpha:** Claude Sonnet 4.6
**Reviewer Beta:** Claude Opus 4
**Document:** `docs/DESIGN.md`
**Source of truth:** `docs/blondie-ChoplifterReverse/choplifter.s` (11,703 lines) + `zeropage.s`
**Review focus:** Mode 1 "Faithful Port" accuracy against the 6502 disassembly

---

## Executive Summary

The design document is well-structured and gets many things right — spawn rate tables, scroll lead values, CURR_LEVEL cap, entity variable names, and the general architecture are all accurate. However, three critical mechanical defects were found: the physics constants are wrong (the most dangerous error because they were *endorsed as verified*), firing is permitted during turns (the doc invents a fire-lock that doesn't exist), and the loss condition is misspecified. Additionally, a world-looping claim is factually false. All critical and high findings were independently confirmed against the source by both reviewers. An undocumented systemic root cause — zeropage.s comments describe table indices, not magnitudes — explains three of the numeric errors.

---

## Consensus Findings

### Critical

**C1 — Physics constants are wrong and were incorrectly endorsed as verified**

`DESIGN.md:310–311` states: `Gravity (Y accel) = 8 units/frame²` and `Max thrust (Y accel) = 15 units/frame²`.

These numbers are the `ZP_ACCELY` *index values* ($08 and $0F), not acceleration magnitudes. The actual physics uses `integrateAccelerationAccelYTable` (`choplifter.s:5266`), a 16-entry signed byte table:

```
$F6, $F7, $F8, $F9, $FA, $FB, $FC, $FD, $FE, $FF, $00, $01, $02, $03, $04, $06
```

Actual acceleration at each cited index:
- Index 8 ("normal gravity"): `$FF` = −1 unit/frame applied to velocity
- Index 15 ("full thrust"): `$06` = +6 units/frame applied to velocity

An implementer building "gravity = 8 px/frame²" will ship a helicopter that feels nothing like the original. This is the highest-priority defect.

**Source:** `choplifter.s:5266`, `zeropage.s:26`

---

**C2 — Firing is NOT locked during turns**

`DESIGN.md:§5.2-note` and `DESIGN.md:§7` both state that `face_*` actions lock firing during the turn animation, "matching original behavior." This is incorrect.

Source shooting gate (`choplifter.s:877–890`) checks exactly three conditions:
1. `ZP_AIRBORNE == 1` (cannot fire on the ground)
2. `ZP_DYING == 0` (cannot fire while dying)
3. `CURR_SHOTS < 5` (5-bullet cap)

There is no `ZP_TURN_STATE` check. Furthermore, `bulletGravityTable` (`choplifter.s:7260`, values `$FE,$FE,$FF,$FF,$FF,$00`) and `bulletVelocityTable` (`choplifter.s:4743`) explicitly map turn state to bullet trajectory — the original is *designed* for angled mid-turn shots. Implementing a fire-lock removes a real mechanic.

**Source:** `choplifter.s:877–890`, `choplifter.s:7260`

---

**C3 — Loss condition is misspecified**

`DESIGN.md:§3` states: "Loss — hostages: 64 hostages killed."

Source main loop (`choplifter.s:599–608`):
```
lda TOTAL_RESCUES    ; win check: rescued == 64?
cmp #$40
bne mainLoopNormal   ; no → continue
jmp mainLoopEndGame  ; YES → victory

mainLoopNormal:
clc
adc HOSTAGES_KILLED  ; loss check: rescued + killed == 64?
cmp #$40
bne mainLoopNoLossYet
jmp (ZP_INDIRECT_JMP_L)  ; LOSS
```

Loss triggers when `TOTAL_RESCUES + HOSTAGES_KILLED == 64` (win check runs first). With exactly 64 hostages total in the game, this means: the game ends when the last hostage is either rescued or killed. If you haven't won, any kill that brings the total to 64 ends the game. The correct framing is: **you must rescue all 64 hostages** — killing even one makes a perfect run impossible.

**Source:** `choplifter.s:599–613`

---

### High

**H1 — Turn speed is variable, not 1 step/frame**

`DESIGN.md:§7` states: "turn_state increments/decrements one step per frame."

Source `processChopTurn` (`choplifter.s:1009–1035`):
- When `|target − current| >= 2`: **2 steps per frame** (`turningLeftHard`/`turningRightHard`)
- When `|target − current| == 1`: **1 step per frame**

A full −5 → +5 turn takes **5 frames**, not 10. This affects the effective duration of the turn and any dependent behavior.

**Source:** `choplifter.s:1009–1035`

---

**H2 — "Max simultaneous: 4 tanks, 4 jets, 4 aliens" is the slot count, not the Mode 1 gameplay cap**

`DESIGN.md:§4` states this as a hard rule, but it is the entity table array size. The actual Mode 1 gameplay cap comes from `tankSpawnRateTable`, `jetSpawnRateTable`, `alienSpawnRateTable`:
- Level 3 (Mode 1 max): 2 tanks, 2 jets, 2 aliens
- The 4-slot entity tables are a system limit for Mode 2/3 levels

The §4.1 table is correct; the §4 header statement contradicts it.

**Source:** `choplifter.s:4621–4626`

---

**H3 — World does NOT loop; it has hard bounds**

`DESIGN.md:§8` states: "The original had a single scrolling level that looped."

Source `integrateVelocity` (`choplifter.s:5550–5587`) hard-clamps the chopper X position to `BOUNDS_LEFT_L/H` (`$02D0`) and `BOUNDS_RIGHT_L/H` (`$1300`) and zeroes velocity at the edges. The world has hard walls, not a loop.

**Source:** `choplifter.s:5550–5587`, `choplifter.s:4760–4766`

---

### Medium

**M1 — Enemy spawn cadence `AND #$2F` is not "every 47 frames"**

`DESIGN.md:§4.1` states: "Enemy vehicle spawn attempt: every 47 frames (~0.78 s at 60 fps)."

The source uses `FRAME_COUNT AND $2F == 0` (bitwise AND with 47 = `0010_1111`). This condition fires when bits 0,1,2,3,5 of the 8-bit frame counter are all zero — at frame counts {0, 16, 64, 80, 128, 144, 192, 208} per 256-frame cycle, a **non-uniform 16/48-frame alternating gap** averaging ~8 attempts per 256 frames. It is not a periodic 47-frame interval. The $2F value is not a divisor.

Note: The source code *comment* also says "every 47 frames" — this is an error in the original author's comment that both analysis documents inherited.

**Source:** `choplifter.s:4577–4579`

---

**M2 — Hostage spawn interval is every 4 frames, not 3**

`DESIGN.md:§4.1` states: "Hostage emergence attempt: every 3 frames."

Source (`choplifter.s:4572`): `and #$03 / bne spawnEnemiesNoHostages`. `FRAME_COUNT AND 3 == 0` triggers at frames {0, 4, 8, 12, …} — every **4 frames**, not 3. The source comment on this line also incorrectly says "every three frames."

**Source:** `choplifter.s:4569–4574`

---

**M3 — Tank spawn X-page bug is undocumented**

Source (`choplifter.s:3924–3929`): Code intended to set `ENTITY_X_H` (the high byte of tank X position) from the player's page, but immediately overwrites it with `lda #$00 / sta ENTITY_X_H,x`. The source comment says "This does nothing — a bug or old code? ... tanks are meant to spawn near you but High X is always set to zero." Tanks effectively always spawn near X = 0 page.

The design doc must decide whether Mode 1 replicates this bug. No policy is stated.

**Source:** `choplifter.s:3924–3929`

---

**M4 — Missing Mode 1 specs: landing physics, on-death hostage behavior, wave structure**

Three areas are unspecified:

1. **Landing physics:** `MIN_VY` (minimum velocity for a safe landing), `LAUNCHTHRESH` (minimum Y velocity to become airborne), and `bounceThrustState` are core to the "feels like Choplifter" landing behavior. Not documented.

2. **HOSTAGES_LOADED on chopper death:** When the chopper dies mid-sortie with hostages aboard, does the HOSTAGES_LOADED count contribute to HOSTAGES_KILLED? This affects the loss condition math in C3 and the "On board" counter display.

3. **Wave structure:** 64 total hostages = 4 waves × 16 (`MAX_HOSTAGES = 16`, always). The design doc does not state this structure, which affects how spawn logic and the cumulative counters are designed.

---

**M5 — Systemic root cause: zeropage.s comments describe indices, not magnitudes**

`zeropage.s:26` comments `ZP_ACCELY = $0B; $08 = Normal gravity, $0f = Full thrust up`. These describe the *values stored in* `ZP_ACCELY` that index into `integrateAccelerationAccelYTable` — not the acceleration magnitudes themselves.

Both `REVERSE_ENGINEER_ANALYSIS.md` and `DESIGN.md` misread these as physical constants. The same misreading pattern likely produced the $08/$0F physics error (C1), the "every 47 frames" comment inherit (M1), and the "every 3 frames" comment inherit (M2).

**Action:** Before implementation, audit every numeric constant in `DESIGN.md` that traces to a zeropage.s comment by verifying against the actual table lookup in `choplifter.s`. Do not treat ZP variable comments as magnitude specifications.

---

### Low

**L1 — Scroll leads not mapped to Godot coordinate space** *(severity contested)*

`$46` (70) and `$D2` (210) are pixel values in the original 280×192 viewport. The design doc documents these correctly but does not specify how they map to Godot's world-space coordinates for the Mode 1 upscaled viewport. **Alpha's position:** Medium — pixel-to-engine-unit reconciliation is a real faithfulness gap. **Beta's position:** Low — routine porting work implicit in any port.

---

**L2 — Mountain parallax description is slightly imprecise**

`DESIGN.md:§6.5/§8`: "single right-shift, exact source behaviour." Source `renderMountains` computes `SCROLLPOS − (SCROLLPOS >> 1)` with `and #$FE` (odd-pixel alignment mask). Net result is ~50%, but not a literal `lsr`. This is a documentation nuance; the gameplay effect is correct.

---

## Unique Insights

**From Reviewer Alpha:**
- The bullet trajectory during turns is a *mechanic*, not just a consequence of the turn animation. The `bulletGravityTable` values (`$FE,$FE,$FF,$FF,$FF,$00`) define gradually increasing bullet drop as the chopper faces more toward the camera. This should be explicitly documented as a Mode 1 feature.
- `CHOP_FACE` (logical direction) flips instantly on input (`choplifter.s:934`), while `ZP_TURN_STATE` animates toward the new direction. This two-value model is correct in §7 and is an important implementation note.

**From Reviewer Beta:**
- The acceleration integration is a full 16-entry signed table, and the velocity is 16-bit. Floating-point approximation ("equivalent behavior") may lose the feel. Consider porting the integer accumulation and the `>>8` velocity-to-position shift verbatim for Mode 1.
- The `joystickYTable` and `integrateAccelerationAccelYTable` are separate: the joystick table maps stick deflection to the ZP_ACCELY index, which then maps to the actual acceleration delta. Two levels of indirection, both undocumented.

---

## Strengths (Both Reviewers Agree)

- §4.1 spawn rate tables are exact source matches — a genuinely well-researched section.
- Scroll lead values ($46/$D2) and their asymmetric camera behavior are correctly described.
- CURR_LEVEL cap-at-3 with source citation is accurate and important.
- Entity variable names (`TOTAL_RESCUES_BCD`, `HOSTAGES_KILLED_BCD`, etc.) match source exactly.
- Biome isolation to Mode 2/3 (Mode 1 is single-environment) is correct design discipline.
- The 5-bullet cap, one-hit kill, no-score, and 3-sortie rules are all correct.
- The Python sprite extractor approach (using original `CHOPGFX`/`CHOPGFXHI` binaries) is the right path for pixel-authentic Mode 1 sprites.

---

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|---|---|---|---|
| 1 | Critical | Physics constants wrong | Replace §7 gravity/thrust with `integrateAccelerationAccelYTable` documentation; specify index→acceleration mapping; port integer math verbatim for Mode 1 | Unanimous |
| 2 | Critical | Fire-lock during turns invented | Remove all "cannot fire during turn" text from §5.2, §5.2-note, §7; add bulletGravityTable values as a documented Mode 1 mechanic | Unanimous |
| 3 | Critical | Loss condition misspecified | Fix §2, §3, §11.8 to: loss when `TOTAL_RESCUES + HOSTAGES_KILLED == 64`; reframe as "rescue all 64 or fail"; remove "64 killed" language | Unanimous |
| 4 | High | Turn speed not 1/frame | Fix §7 to: 2 steps/frame when delta ≥ 2, 1 step/frame when delta = 1 | Unanimous |
| 5 | High | Max-4 conflates slot count with cap | Fix §4: "4 entity slots per type; Mode 1 gameplay cap = 2 of each at level 3" | Unanimous |
| 6 | High | World does not loop | Fix §8: world has hard X bounds (`$02D0` – `$1300`), not a loop | Unanimous |
| 7 | Medium | Enemy spawn cadence wrong | Fix §4.1: `AND #$2F` fires ~8×/256 frames in non-uniform 16/48-frame alternating pattern | Unanimous |
| 8 | Medium | Hostage interval wrong | Fix §4.1: "every 4 frames" (`and #$03` = fires at frames 0,4,8,…) | Unanimous |
| 9 | Medium | Tank spawn bug undocumented | Add note: tank `ENTITY_X_H` always 0 (source bug); define Mode 1 replication policy | Unanimous |
| 10 | Medium | Landing physics unspecified | Add §7 sub-section: `MIN_VY`, `LAUNCHTHRESH`, `bounceThrustState` values for Mode 1 | Unanimous |
| 11 | Medium | On-death hostage behavior unspecified | Specify whether HOSTAGES_LOADED on death increases HOSTAGES_KILLED | Unanimous |
| 12 | Medium | Systemic: audit all ZP constants | Add implementation note: verify all numeric constants against table lookups, not zeropage.s comments | Unanimous |
| 13 | Low–Med | Scroll lead coordinate mapping | Map $46/$D2 to Godot world-space explicitly for Mode 1 | Contested (Alpha: Medium, Beta: Low) |
| 14 | Low | Bullet trajectory during turns | Add table of bulletGravityTable values to §7 or §4.2 | Unanimous |
| 15 | Low | Mountain parallax nuance | Correct "single right-shift" to `SCROLLPOS − (SCROLLPOS >> 1)` with `and #$FE` mask | Unanimous |

---

## Review Process Notes

**Where the adversarial process added most value:**

The most significant outcome was the inversion of one of Alpha's "verified correct" endorsements into a Critical finding. Alpha's Stage 1 stamped `$08/$0F` physics as source-confirmed; Beta's independent reading of `choplifter.s:5266` found the actual acceleration table and identified the index/magnitude confusion. No single-reviewer pass would have caught this because the wrong numbers appear in the pre-existing analysis document with apparent authority.

The fire-lock finding (W1/B2) was independently reached by both reviewers, confirming it with high confidence. The `bulletGravityTable` as positive evidence — not just absence of a check — is the key element that makes this finding airtight.

**Blind spots each model had:**

*Alpha:* Endorsed the physics constants by trusting the zeropage.s comment rather than tracing the table lookup. Missed the world-looping claim, hostage interval, and landing physics. Strong on mechanical rule-checking (fire conditions, loss conditions, turn state logic).

*Beta:* More thorough on the physics integration path (found the acceleration table). Slightly weaker on the initial mechanics review — independently confirmed W1/W2/W3 rather than surfacing new mechanic findings. The systemic root-cause framing (M5) is Beta's most original contribution.

**Recommendation for implementer:** Before writing any code, read `choplifter.s:7434` (`chopperPhysics`) and `choplifter.s:5160` (`integrateAcceleration`) in full. These 80 lines of commented assembly are the definitive spec for Mode 1 physics feel — no design document can substitute for them.
