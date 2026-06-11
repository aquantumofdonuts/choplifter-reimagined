# Adversarial Design Review: ASSET_PIPELINE.md

**Date:** 2026-06-07
**Reviewer Alpha:** Claude Sonnet 4.6
**Reviewer Beta:** Claude Opus 4.8
**Document:** `docs/ASSET_PIPELINE.md`
**Reviewed in light of:** `docs/DESIGN.md`, `docs/ENHANCED_GAMEPLAY.md`

---

## Executive Summary

ASSET_PIPELINE.md describes the right architecture for automating a 145+-sprite, multi-biome, multi-layer audio asset production pipeline. The core decisions — Scenario for style-consistent AI sprite generation, numpy/scipy for waveform synthesis, midiutil/FluidSynth for chiptune music — are well-reasoned and documented. The versioning/manifest design (§9) is sophisticated and production-worthy.

However, the document cannot be handed to implementation without significant correction. The adversarial process surfaced two categories of defect, each independently sufficient to cause project failure:

**Workflow breakage:** The document is directly and silently contradicted by DESIGN.md on both the sprite pipeline (Aseprite-mandatory vs. Scenario-automated) and the audio tooling (jsfxr/BeepBox vs. numpy/FluidSynth). A developer following one document will plan incompatible work from the other.

**Quantitative unreliability:** The sprite count (stated 145, actual ~165), SFX count (stated 21, actual 22), and all three cost estimates (~150 / 150–300 / "ample headroom") are mutually inconsistent and formula-breaking. The pipeline has a single paid dependency (Scenario Pro) whose cost is misstated.

Beyond these, the debate surfaced a serious technical feasibility gap: Scenario cannot generate usable pixel art at the sub-16px sprite sizes the spec requires for projectiles and hostages.

The document should be corrected in the order given by the priority table before any pipeline implementation work begins.

---

## Consensus Findings

Both reviewers agreed independently on the following. Highest confidence.

### Critical

**C1 — DESIGN.md sprite-pipeline contradiction (Alpha W1 / Beta A-W3)**

`DESIGN.md §6.3` mandates Aseprite as "non-negotiable for pixel art animation" and states that animated sprites are "hand-pixeled" in Aseprite using AI as reference only. `ASSET_PIPELINE.md` eliminates Aseprite entirely and auto-generates animation frames via the Scenario MCP pipeline. No reconciliation, no supersession statement exists. A developer reading DESIGN.md will budget $20 for Aseprite and plan manual animation work. A developer reading ASSET_PIPELINE.md will set up Scenario MCP and expect zero manual frame work. These plans are mutually exclusive.

**Fix:** Update DESIGN.md §6.3 to reflect the Scenario pipeline. Remove the Aseprite mandate. Add an explicit note in ASSET_PIPELINE.md: "This document supersedes DESIGN.md §6.3 on sprite tooling."

---

**C2 — DESIGN.md audio-tooling contradiction (Alpha W2 / Beta A-W4)**

`DESIGN.md §9.1` specifies jsfxr/Bfxr for SFX. `DESIGN.md §9.2` specifies BeepBox/FamiTracker for music. `ASSET_PIPELINE.md` uses numpy/scipy for SFX and midiutil/FluidSynth for music. The ASSET_PIPELINE §4 note ("A standalone Python sfxr port does not exist on PyPI") implicitly acknowledges the switch from jsfxr but does not declare the supersession, and DESIGN.md still points to the old tools.

**Fix:** Update DESIGN.md §9.1 and §9.2 to reflect numpy/scipy and midiutil/FluidSynth. Remove jsfxr, Bfxr, BeepBox, and FamiTracker references. Add supersession note to ASSET_PIPELINE.md.

---

**C3 — Sprite inventory count wrong: ~165, not ~145 (Beta A-W1, Alpha conceded)**

Both reviewers independently verified the table in §3.3:
- Non-biome sprites: 11+5+2+4+4+25+7+4+3+2+5+6+1+1+1+1 = **82**
- Per-biome sprites (5 biomes): (4+1+2+1+5)×5 = **65**
- Fonts/HUD: 10+~8 = **~18**
- **Total: ~165**

The "~145" claim appears in §1 (table), §2.2 (Note), and §3.3 ("Total" line and the "Why Scenario" paragraph). A 14% undercount propagates into the cost estimates and the core consistency argument ("All 145 sprites generated from one model").

**Fix:** Correct all instances of "~145" to "~165." Recompute credit estimates (see C4).

---

**C4 — Cost estimates mutually inconsistent and formula-breaking (Beta A-W2, Alpha R4)**

This is independent of C3 and compound. At the *stated* 145 sprites × 4 candidates × 0.5 credits/image = **290 credits**, which already nearly hits the §2.2 ceiling of 300 and wildly exceeds the §1 table's "~150 for full set." At the *actual* 165 sprites, the formula yields **330 credits** — above the stated ceiling entirely. The "ample headroom" claim in §2.2 is unsupportable.

Three cost figures (~150 / 150–300 / "ample headroom") are simultaneously present and mutually contradictory. None follows from the stated formula under any reasonable reading.

**Fix:** After resolving C3 (true sprite count) and H1 (which sprites need Scenario vs. manual authoring): recompute actual credits. Remove the "~150 for full set" figure from §1 table. Fix §2.2 with a single, formula-consistent estimate.

**Cross-dependency:** Fixing H1 (small-sprite authoring path) changes the Scenario-generated count, which changes C4. These must be resolved as a cluster.

---

**C5 — No precedence/reconciliation statement in either document (Beta A-M1)**

ASSET_PIPELINE.md was created after DESIGN.md and supersedes it on both sprite and audio tooling. Neither document says so. Without a supersession clause, the two documents are equally authoritative and flatly contradictory. Any future update to one without the other recreates the conflict.

**Fix:** Add to ASSET_PIPELINE.md header: "Where this document conflicts with DESIGN.md, this document is authoritative for asset tooling decisions." Update DESIGN.md §6.3/§9.1/§9.2 with cross-references to ASSET_PIPELINE.md as the authoritative source.

---

### High

**H1 — Sub-16px downscaling not viable for projectile and character sprites (Beta A-M7, Alpha conceded)**

Scenario generates images at 512px+. ImageMagick resize/quantize to 6×4 (`bullet`), 8×4 (`shell`), 12×4 (`missile`), 6×8 (`bomb`), and 8×14 (`hostage_*`) will not produce usable pixel art at these sizes — meaningful detail cannot survive ~98% downscaling from a generative model. The pipeline's viability is unaddressed for ~13 sprite definitions (the 4 projectiles + 9 hostage frames).

This is likely the largest technical feasibility risk in the document. The pipeline probably works for sprites ≥24px; it probably doesn't for sprites ≤16px.

**Fix:** Add a note to §3.1 and §3.3: sub-16px sprites (bullet, shell, missile, bomb, and hostage frames) must be authored manually or via a tool that works at native resolution (e.g., Aseprite, Piskel, hand-editing in any pixel editor). Remove these from the Scenario workflow and recompute C4 credits.

**Cross-dependency with C3/C4:** Removing ~13 sprite definitions from the Scenario workflow lowers the generation count and cost. Resolve H1 before finalizing C4.

---

**H2 — Per-biome directory/naming collision (Beta A-M4, Alpha conceded)**

§3.1 Phase 3e writes to `assets/graphics/mode2/<group>/<name>.png` (groups like `mountain`, `house`, `base`). §7's directory structure shows `biome_desert/`, `biome_jungle/` as top-level directories. These layouts contradict each other. Under the §3.1 layout, five `house` sprites (one per biome) would all map to `mode2/house/house_0.png` — a collision. The correct layout must include the biome qualifier in either the directory or the filename.

**Fix:** Pick one layout and apply it consistently to §3.1, §3.3 sprite spec JSON examples, §7 directory tree, and the `sprites_mode2.json` config schema. Recommend: `mode2/biome_<biome>/<group>/<name>.png` or `mode2/<group>/<biome>_<name>.png`. Document the naming convention explicitly.

**Cross-dependency with L5 (naming convention):** The same fix resolves both H2 and L5.

---

**H3 — All pipeline scripts and configs are missing; document reads as operational (Beta A-R3, subsuming Alpha R3)**

`postprocess_sprites.py`, `generate_sfx.py`, `generate_music.py`, `verify_assets.py`, and configs `sprites_mode2.json`, `sfx_spec.py`, `music_instruments.json` are all referenced with imperative `python3 src/tools/...` commands and runtime estimates ("~5 seconds," "~30 seconds"). None exist — only `extract_sprites.py` is present in `src/tools/`. A developer following §6 verbatim will fail at every step.

**Fix:** Add a status qualifier to §1 or §6: "Note: Pipeline scripts listed in this document are planned, not yet implemented. Implementation begins at v0.2." Replace run commands with `# planned` markers or add an implementation status column to §10.

---

**H4 — Missing `## 3. Sprites Pipeline` section header (Alpha W3 / Beta A-W5)**

The document jumps from §2.6 directly to a floating `**Generation:** Scenario MCP...` label and then into `### 3.1 How It Works`. There is no `## 3` heading. The section numbering and any generated table of contents are broken.

**Fix:** Add `## 3. Sprite Pipeline (Mode 2)` before the `**Generation:**` line.

---

**H5 — Overview table Markdown is malformed (Alpha W4 / Beta A-W6)**

The §1 table separator is split across two lines:
```
| Asset Type | Tool Stack | Requires | Cost |
|---|---|---|
---|
```
This will fail to render as a table in any standard Markdown parser.

**Fix:** Replace the two-line separator with `|---|---|---|---|` on a single line.

---

**H6 — Header incorrectly claims Mode 3 coverage (Alpha W5 / Beta A-W7)**

The document header states: "Covers Mode 2 (Modern Pixel Art) and Mode 3 (Hi-Res) assets only." There is zero Mode 3 content in the document. §10 explicitly defers Mode 3 to v2.0 as "separate design, TBD," and §7 marks menu hi-res as "separate pipeline, TBD."

**Fix:** Change header to: "Covers Mode 2 (Modern Pixel Art) assets only. Mode 3 (Hi-Res) asset pipeline is planned for v2.0 — see DESIGN.md §6.4."

---

### Medium

**M1 — SFX file count wrong: 22, not 21 (Beta A-W8, Alpha conceded)**

`alien_crackle.ogg` is explicitly described as "3 pitch variants, 3 files" in §4.2. The table has 20 rows; with `alien_crackle` counting 3: 19 + 3 = **22** files. "Total: 21 files" in §4.2, the "(21 files total)" comment in §7, and the v0.2 roadmap "all 21 SFX" are all wrong.

**Fix:** Change all instances of "21" to "22" in these locations.

---

**M2 — Victory/loss sting duplication across pipelines (Beta A-M5, Alpha conceded)**

§4.2 (SFX pipeline) defines `victory_sting.ogg` and `loss_sting.ogg`. §5.1 (Music pipeline) defines `music_sting_victory.ogg` and `music_sting_loss.ogg`. There are two parallel sting sets from two different toolchains with no statement of which the game plays or whether both are needed.

**Fix:** Decide which subsystem owns end-game stings. Either: (a) SFX owns them — remove from §5.1 and note in AudioManager.gd; or (b) Music owns them — remove from §4.2. One toolchain, one set. The naming convention (no `music_` prefix vs. `music_` prefix) currently splits ownership ambiguously.

---

**M3 — FluidSynth command syntax is incomplete (Beta A-R5, Alpha conceded)**

§5.3 shows: `FluidSynth --audio-driver=file --soundfont=chiptune.sf2` with no input MIDI file path and no output path. This command does not produce the described WAV file. The correct headless render invocation is: `fluidsynth -ni -F output.wav chiptune.sf2 input.mid`.

**Fix:** Replace the malformed example with the correct invocation form.

*Note: The Stage 1 strength "audio pipeline technically sound" (S2) must be qualified — the architecture is sound, but the concrete invocation is broken and the scripts are unbuilt.*

---

**M4 — Auto-selection heuristic undefined (Alpha M1)**

§3.1 Phase 2 step 4: "Assistant auto-selects best candidate by silhouette/quality heuristic." For ~165 sprites at 4 candidates each, the assistant makes ~165 selection decisions. No algorithm, threshold, or scoring criteria is defined anywhere. Without a spec, auto-selection is subjective and inconsistent across sessions. §3.1 Phase 3d mentions "score silhouette clarity; flag if below threshold" but the threshold and metric are not specified.

**Fix:** Define the selection heuristic concretely in a new §3.4 spec section: scoring dimensions (silhouette edge density, background alpha coverage, palette compliance, color count), minimum thresholds, and behavior when no candidate passes (either flag for manual review or default to candidate 0).

---

**M5 — Single point of failure on Scenario MCP service (Alpha R2)**

The entire sprite generation pipeline depends on `https://mcp.scenario.com/mcp` being operational and API-compatible. The document names 22 specific Scenario MCP tools (`train`, `run_model`, `display_asset`, `manage_assets`, etc.). If Scenario changes its MCP API surface, raises prices, or discontinues the service, the pipeline has no fallback. The 145+ sprites span multiple milestones across potentially 6–12 months.

**Fix:** Add a §3.7 "Fallback Path" noting that in the event Scenario is unavailable: (a) sub-16px sprites (H1) are already manual; (b) larger sprites can be generated via Scenario's web UI with the trained model, then manually downloaded and post-processed; (c) the LoRA model should be exported/backed up from the Scenario project for portability. Document the model download step.

---

## Contested Findings

One finding was contested across stages; verdict follows.

**Contested: Severity ranking of DESIGN.md contradictions vs. sprite count error**

Alpha ranked the two DESIGN.md contradictions (C1/C2) strictly above the sprite count/cost errors (C3/C4) on the grounds that workflow impact > budget impact in a solo project. Beta argued they are co-equal Critical because the count error corrupts the core cost estimate for the single paid dependency.

**Verdict: Co-equal Critical.** Beta's argument is more persuasive. The Scenario credit cost is not a passive detail — it is the explicitly stated basis for the "Pro account covers the full set" claim that a developer must use to decide whether to pay $45/month. A 14% undercount of the work item that drives this decision is a planning-integrity defect of the same severity as a workflow contradiction. The final priority table treats C1/C2 and C3/C4 as co-equal Critical.

---

## Unique Insights (survived cross-examination from one reviewer only)

**From Beta (not in Alpha's review):**

- **Sub-16px downscaling infeasibility (H1):** The single most important technical feasibility finding not in Alpha's review. Scenario-generated sprites at 512px+ simply cannot be resized to 6×4 or 8×14 and produce usable pixel art. This was obvious in retrospect but Alpha missed it because Alpha read the inventory table without mapping the sizes to typical AI generation resolutions. The adversarial process added real value here.

- **SFX/music sting duplication (M2):** Two parallel sting sets from two toolchains. Beta caught this; Alpha missed it. This would produce a runtime ambiguity (which file does AudioManager play?) not discovered until implementation.

- **FluidSynth command syntax error (M3):** Alpha called the audio pipeline "technically sound" (S2) without scrutinizing the one explicit shell command in the chain. Beta caught the error. The adversarial process correctly punished an unverified strength claim.

**From Alpha (not in Beta's review):**

- **Engine pitch-shift cross-reference (L1):** Alpha identified a gap between DESIGN.md §9.1 (engine pitch shifts with thrust) and the pipeline spec (static loop). After debate, both reviewers agree the gap belongs in AudioManager.gd, not the asset pipeline. But the requirement exists in DESIGN.md and needs to be tracked somewhere — Alpha surfaced a coordination concern Beta missed.

- **IP risk on training data (R1):** Both reviewers flagged this, but Alpha named it first. It remains the project-level risk with the greatest external consequence.

---

## Strengths

Both reviewers agreed on the following:

- **Scenario rationale is the right call.** Custom LoRA for visual consistency across 165 sprites is the correct architectural decision. Generic per-image APIs would produce an incoherent sprite set. The rejection of Replicate is well-argued.

- **Audio pipeline architecture is sound (with qualified S2).** numpy/scipy waveform synthesis + midiutil/FluidSynth/ffmpeg is technically correct, dependency-minimal, and free. The dynamic three-layer crossfade architecture (same BPM/key/loop-length per biome) is a real, working technique. *Caveat: the FluidSynth command syntax is broken (M3) and the scripts don't exist yet (H3).*

- **Versioning and manifest design (§9) is genuinely sophisticated.** Config-hash-based incremental reprocessing is a production concern that most asset pipelines omit. Getting this right early avoids painful full-regeneration runs later.

- **Roadmap/milestone alignment with DESIGN.md is correct.** The biome progression (Desert v0.3 → Jungle/Arctic v0.4 → Tropical Island/Alien World v0.5) matches DESIGN.md §14 exactly.

- **Security hygiene is handled correctly.** `.env` in `.gitignore`, API key never in committed files, the split between committed final assets and gitignored intermediates (candidates, soundfonts, previews) is clearly defined.

---

## Prioritized Recommendations

| # | Severity | Finding | Recommendation | Consensus |
|---|----------|---------|----------------|-----------|
| 1 | Critical | C5 — No precedence statement | Add supersession clause to ASSET_PIPELINE.md header; cross-reference from DESIGN.md | Unanimous |
| 2 | Critical | C1 — Aseprite vs. Scenario contradiction | Update DESIGN.md §6.3 to Scenario pipeline; remove Aseprite mandate | Unanimous |
| 3 | Critical | C2 — jsfxr/BeepBox vs. numpy/FluidSynth contradiction | Update DESIGN.md §9.1/§9.2 to numpy/scipy + midiutil/FluidSynth; remove old tool refs | Unanimous |
| 4 | Critical | C3 — Sprite count wrong (~165 not ~145) | Recount and fix all "~145" instances; recompute downstream figures | Unanimous |
| 5 | Critical | C4 — Cost figures mutually inconsistent | After H1+C3 resolved: recompute single consistent credit estimate; remove conflicting figures | Unanimous |
| 6 | High | H1 — Sub-16px sprites not viable via Scenario | Carve bullet, shell, missile, bomb, hostage frames to manual path; update count/cost | Majority (Beta first) |
| 7 | High | H2 — Per-biome dir/naming collision | Pick and document one layout (recommend `biome_<x>/<group>/`); apply everywhere | Unanimous |
| 8 | High | H3 — All scripts missing, doc reads operational | Add "planned, not yet implemented" qualifier; mark commands as planned | Unanimous |
| 9 | High | H4 — Missing §3 section header | Add `## 3. Sprite Pipeline (Mode 2)` header | Unanimous |
| 10 | High | H5 — Malformed table separator | Fix to single `\|---|---|---|---\|` line | Unanimous |
| 11 | High | H6 — False Mode 3 claim in header | Correct header to Mode 2 only; reference DESIGN.md §6.4 for Mode 3 | Unanimous |
| 12 | Medium | M1 — SFX count 22 not 21 | Fix "21" → "22" in §4.2, §7, v0.2 roadmap | Unanimous |
| 13 | Medium | M2 — Sting duplication | Decide ownership (SFX or Music); remove from the other subsystem | Unanimous |
| 14 | Medium | M3 — FluidSynth command broken | Replace with `fluidsynth -ni -F output.wav soundfont.sf2 input.mid` | Unanimous |
| 15 | Medium | M4 — Auto-selection heuristic undefined | Add §3.4 defining scoring dimensions, thresholds, and failure behavior | Unanimous |
| 16 | Medium | M5 — Scenario SPOF | Add §3.7 fallback path: web UI fallback, model export/backup | Unanimous |
| 17 | Low | L1 — Engine pitch-shift (cross-reference) | Note in AudioManager.gd section of DESIGN.md that engine pitch uses `pitch_scale` | Unanimous |
| 18 | Low | L2 — `--break-system-packages` | Replace with `python3 -m venv .venv && source .venv/bin/activate` in §2.1/§11 | Unanimous |
| 19 | Low | L3 — Soundfont URL fragility | Add a SHA-256 checksum and second mirror URL to §2.4 | Unanimous |
| 20 | Low | L4 — No licensing section | Add §12 covering Scenario output rights, Endesga 32 terms, soundfont license | Unanimous |
| 21 | Low | L5 — No naming convention doc | Document naming convention as a rule; cross-reference from §3.3 and §7 | Unanimous |
| 22 | Low | L6 — Mode 1 SFX aesthetic gap | Add note to §4.2: synthesized square waves are acceptable for Mode 1; no separate 1-bit SFX needed | Unanimous |

---

## Review Process Notes

**Where the adversarial process added the most value:**

1. **Arithmetic verification (B-MISS1, B-MISS2).** Alpha accepted the document's own numbers without independently computing them. The debate forced a recount and surfaced a 14% sprite-count error and a 1-file SFX error. This is exactly the class of finding that single-model reviews miss — Alpha treated "~145" as approximately-correct rather than arithmetically verifiable.

2. **Technical feasibility for small sprites (H1).** Alpha read the inventory table and recognized the 6×4 `bullet` without connecting it to the Scenario generation resolution floor. Beta connected the two and identified a likely pipeline failure mode for 13 sprite definitions. Cross-model review surfaced a blind spot.

3. **Strength claim verification (S2 → M3).** Alpha's Stage 1 strength "audio pipeline technically sound" was written without scrutinizing the one explicit shell command. Beta's independent read immediately caught the broken FluidSynth invocation. The adversarial process correctly punished a strength claim that wasn't verified.

**Where each model had blind spots:**

- **Alpha (Sonnet)** accepted document-stated numbers at face value. It also over-focused on structural/qualitative findings (formatting, contradiction type) without doing arithmetic verification. W6 (engine pitch shift) was an invented requirement — Alpha found a real cross-doc discrepancy but misidentified the responsibility as pipeline's rather than runtime's.

- **Beta (Opus)** showed stronger quantitative instinct (independently counted the table, caught the sting duplication) but initially under-weighted the sub-16px issue relative to the DESIGN.md contradictions. Beta's FP1 call on W6 was correct and improved the final output.

**Key cross-dependencies for implementation:**

- C5 (precedence statement) gates C1/C2 (contradictions can't be "fixed" without declaring which doc wins)
- C3 (count) + H1 (small-sprite authoring) together determine the true Scenario scope, which determines C4 (cost)
- H2 (naming) + L5 (convention) are the same fix — resolve together
