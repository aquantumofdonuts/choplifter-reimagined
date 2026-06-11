# Choplifter Clone → Public Release Fork: Copyright Remediation Spec

**Date:** 2026-06-11  
**Status:** PLANNED — applies to the public/store fork only, not the private reserve build  
**Companion to:** `docs/plans/2026-06-07-implementation-plan.md` (private build, unchanged)

---

## Overview

The private build faithfully implements the full original design including Mode 1 (Retro)
with extracted Apple II sprites and the Broderbund title sequence. That build is a personal
archive and is never published.

The public/store fork removes all third-party IP before Play Store submission:

1. Extracted Apple II sprites → replaced with original pixel art
2. "Broderbund Presents" title sequence → replaced or removed
3. "Choplifter" name/trademark → replaced with chosen identity
4. Disk image files → removed from repo entirely

This document specifies all changes required. Implementation follows the private build
reaching a playable state; the fork is then made and this spec is applied.

---

## 1. Name & Identity (Pending Final Decision)

Three candidate identities are prepared in `assets/store/`. Owner selects one before forking.

| Option | Name | Tagline | Identity |
|--------|------|---------|----------|
| A | **Dustoff!** | Rescue. Evade. Survive. | Spiritual successor — military rescue, own world |
| B | **Air Rescue** | The Classic Returns. | Retro homage — openly references arcade heritage |
| C | **EVAC** | Every Second Counts. | Fully original IP — maximum distance from source |

**Action:** Choose A, B, or C. Update this document, then proceed.

---

## 2. Mode 1 (Retro) — Asset Replacement

### 2.1 What Must Change

| Item | Current (private) | Required (public) |
|------|-------------------|-------------------|
| Chopper sprites | Extracted from `CHOPGFX` Apple II binary | New hand-pixelled or generated originals |
| Tank, jet, hostage, base, mountain | Same — extracted | New originals |
| Digit font (6×7px) | Extracted from HGR binary | New original pixel font |
| `CHOPGFX` / `CHOPGFXHI` files | In repo under `docs/blondie-ChoplifterReverse/` | Removed from repo entirely (see §5) |

### 2.2 Replacement Approach (Recommended)

**Option A — Reuse Mode 2 sprites downscaled:**  
Mode 2 sprites are already generated, original, and owned. For Retro mode, downscale them
to the original logical resolution (e.g. chopper 48×24 → 12×6 nearest-neighbour) and apply
a monochrome palette pass. This is fast, free, and consistent with the game's existing assets.

**Option B — Hand-author 1-bit sprites:**  
Draw new Apple II–resolution sprites in Aseprite or Piskel. Highest authenticity, most effort.

**Recommendation:** Option A. The Mode 2 sprites are already owned and suitable.

### 2.3 Sprite List (Mode 1 Retro, all must be replaced)

Sourced from `extract_sprites.py` output. All sprites in `assets/graphics/original-sprites/`
are derived from copyrighted binaries and must not appear in the public build.

Groups to replace: `chopper_side`, `chopper_headon`, `chopper_squish`, `rotor_main`,
`rotor_tail`, `jet`, `tank`, `tank_cannon`, `hostage_running`, `hostage_waving`,
`hostage_loading`, `explosion`, `base`, `fence_tower`, `house`, `mountain`, `font`,
`hud`, `bullet`, `alien`, `sortie_banner`

---

## 3. Title Sequence Replacement (Mode 1 Retro)

### 3.1 What Must Change

The `RetroTitle.tscn` sequence in the private build reproduces:
- "Broderbund Presents" card with Broderbund branding
- Choplifter logo animation
- Mission briefing card referencing original lore
- Attract demo with original sprite gameplay

All of these must be replaced or removed.

### 3.2 Replacement

Replace `RetroTitle.tscn` content with:

1. **Publisher card:** "[Your Studio Name] Presents" — plain text, no Broderbund reference
2. **Title card:** Chosen game name (Dustoff! / Air Rescue / EVAC) in large pixel font
3. **Mission card:** New lore text (see §4) — no reference to Broderbund or Choplifter
4. **Attract demo:** Keep — it uses gameplay code only, no IP issue

Remove all string literals containing "Broderbund", "Choplifter", "Dan Gorlin" from
the public build's source code and scenes.

---

## 4. Lore & Text Replacements

### Private build lore references to replace:

| Location | Private text | Public replacement |
|----------|-------------|-------------------|
| Mission briefing | "Choplifter mission" / original story | New story (see below) |
| Credits screen | "Based on Choplifter by Dan Gorlin / Broderbund" | "Inspired by 1980s arcade rescue games" |
| README | Current credits referencing Blondihacks, Broderbund | Keep Blondihacks credit (her work is fine), remove Broderbund |

### Suggested replacement lore (adapt to chosen identity):

> **Year 2031. The Accord has collapsed.**  
> Civilian evacuation teams are the last line between survival and abandonment.  
> You are Callsign DUSTOFF [or EVAC / RESCUE]. Five sectors. Limited fuel.  
> Get them out.

---

## 5. Repository Cleanup (Public Fork)

The following files/directories must be **removed from the public fork's git history**
(not just `.gitignore`d — they must not appear in any commit reachable from the public remote):

```
docs/blondie-ChoplifterReverse/CHOPLIFTER.po
docs/blondie-ChoplifterReverse/DiskImageParts/
docs/blondie-ChoplifterReverse/CHOPGFX
docs/blondie-ChoplifterReverse/CHOPGFXHI
assets/graphics/original-sprites/   ← all extracted sprite PNGs
```

**Method:** Use `git filter-repo --path <file> --invert-paths` to excise these from
the fork's history before making the repo public. Do NOT simply delete and commit —
git history would still contain the files.

Quinn Dunki's source files (`.s`, `Makefile`, `README.md` etc.) may stay — they are
her own work and she has made them public. Only the original Broderbund binary-derived
content must go.

---

## 6. App Store Assets

Generated in `assets/store/` for all three identity options:

```
assets/store/
├── dustoff/
│   ├── icon_512x512.png
│   ├── feature_1024x500.png
│   ├── screenshot_desert.png
│   ├── screenshot_jungle.png
│   └── store_copy.md
├── air_rescue/
│   ├── (same structure)
└── evac/
    ├── (same structure)
```

**Screenshots note:** Current screenshots are sprite composites generated from Mode 2 assets.
Final store screenshots must be captured from the running game. Replace before submission.

---

## 7. Implementation Sequence

1. Private build reaches playable v0.1 (per existing implementation plan)
2. **Owner chooses identity** (A / B / C) — update §1 of this document
3. Fork repo: `choplifter-clone-public` (or name matching chosen identity)
4. Apply `git filter-repo` to excise copyrighted binaries from fork history
5. Replace Mode 1 sprites (§2) — downscale Mode 2 assets via new `src/tools/make_retro_sprites.py`
6. Replace title sequence (§3) — edit `RetroTitle.tscn`
7. Replace lore/text strings (§4)
8. Replace store copy and finalize screenshots (§6)
9. Rename Godot project to chosen identity
10. Submit to Google Play

---

## 8. What Does NOT Change

- All Mode 2 sprites — original AI-generated, fully owned ✅
- All SFX — synthesized from scratch ✅
- All music — generated via midiutil/FluidSynth ✅
- All gameplay mechanics — not copyrightable ✅
- Quinn Dunki's disassembly reference files (`.s`, docs) — her work, publicly available ✅
- Godot source code — entirely new ✅
