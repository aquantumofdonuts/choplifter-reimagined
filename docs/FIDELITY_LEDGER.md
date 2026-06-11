# Fidelity Ledger

> **Purpose (plan Task 3d):** every Mode 1 mechanic is classified as `Exact`,
> `Approximation (documented)`, or `Enhanced (out of Mode 1)`. A mechanic may not be called
> "faithful" unless its row says `Exact` with a source line reference. Update the row whenever a
> task implements or deliberately deviates from source.
>
> Source: `docs/blondie-ChoplifterReverse/choplifter.s` (11,703-line annotated 6502 disassembly).

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
| House ignition (shoot-to-open; releases occupants; house 3 pre-opened with 8 fielded) | Exact | choplifter.s:8985–8998, 8605–8616, 11341–11360 | Task 14 — polarity is 0=closed/1=open; fire does NOT kill occupants. Source ordnance-vs-house test covers pages 0–2 only (house 3 starts open). R3 open question CLOSED by static verification: `spawnInitialHostages` ($9ea9) sets `houseStates+3 = $01` at game start, so the `cmp #$03` exclusion is correct by construction; `igniteHouse` is idempotent ($8b4b guards on `houseStates,x`) |
| Camera scroll clamps (`$02B0`–`$1208`) | Exact | choplifter.s:4768–4775 | Task 11 |
| Source RNG (rol/eor/ror through carry, V-flag seed bump) | Exact algorithm; seed/carry init approximated | choplifter.s:6069–6083 | Task 4 — source seed is the uninitialized accumulator; a bit-exact stream is unattainable by design |
| 16-house single field | Enhanced (Mode 2+) | — | Reimagined variant only; NOT Mode 1 — Task 35b |
| Source tick rate (15 Hz physics tick) | Approximation (documented) | choplifter.s:316–335 (demo: 224 frames ≈ one map crossing) | v0.1 playability fix — the Apple II loop was CPU-bound (~15 fps, no VBL); all extracted constants are per SOURCE frame, so the Godot physics tick IS the source tick. At 60 Hz the game ran ~4× too fast. 224-frame demo leg ≈ 15 s at 15 fps, matching original footage. Tunable 15–20 if feel-testing disagrees |
