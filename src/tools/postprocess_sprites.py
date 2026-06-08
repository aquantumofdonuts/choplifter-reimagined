#!/usr/bin/env python3
"""
Choplifter Clone Mode 2 sprite post-processor.

For each Scenario-generated sprite candidate:
  1. Resize to exact target dimensions (ImageMagick, NEAREST neighbour)
  2. Quantize to Endesga-32 palette (ImageMagick)
  3. Remove background → alpha channel (Pillow flood-fill from corners)
  4. Score silhouette clarity (edge density, alpha coverage, palette compliance)
  5. Auto-select the best candidate and write to final output path
  6. Flag groups where all candidates score below threshold for manual review

Usage:
    python3 src/tools/postprocess_sprites.py --sprite chopper_side_0
    python3 src/tools/postprocess_sprites.py --group  chopper_side
    python3 src/tools/postprocess_sprites.py --pass   all          # all groups
    python3 src/tools/postprocess_sprites.py --pass   consistency  # re-score only
    python3 src/tools/postprocess_sprites.py --pass   fix          # re-run flagged

Requires: Pillow, ImageMagick (convert command)
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Pillow is required: pip install pillow")

PROJECT_ROOT   = Path(__file__).resolve().parent.parent.parent
SPEC_PATH      = PROJECT_ROOT / "src" / "tools" / "config" / "sprites_mode2.json"
PALETTE_PATH   = PROJECT_ROOT / "src" / "tools" / "config" / "palette_mode2.gpl"
CANDIDATES_DIR = PROJECT_ROOT / "assets" / "graphics" / "mode2" / "_candidates"
OUT_BASE       = PROJECT_ROOT / "assets" / "graphics" / "mode2"
FLAG_FILE      = PROJECT_ROOT / "assets" / "graphics" / "mode2" / "_flagged.json"

# Minimum combined score (0–1) for auto-promotion; below this → manual review
AUTO_SELECT_THRESHOLD = 0.30


# ─────────────────────────────────────────────────────────────────────────────
# Palette loading
# ─────────────────────────────────────────────────────────────────────────────

def load_palette_gpl(path: Path) -> list[tuple[int, int, int]]:
    """Parse a GIMP .gpl palette file and return a list of (R, G, B) tuples."""
    colors: list[tuple[int, int, int]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.lower().startswith("gimp") or line.lower().startswith("name"):
            continue
        parts = line.split()
        if len(parts) >= 3:
            try:
                r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
                colors.append((r, g, b))
            except ValueError:
                continue
    return colors


# ─────────────────────────────────────────────────────────────────────────────
# ImageMagick helpers
# ─────────────────────────────────────────────────────────────────────────────

def _run_im(args: list[str]) -> None:
    """Run an ImageMagick command; raise RuntimeError on failure."""
    res = subprocess.run(["convert"] + args, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ImageMagick error:\n{res.stderr[-400:]}")


def resize_nearest(src: Path, dst: Path, width: int, height: int) -> None:
    """Resize *src* to *width*×*height* with nearest-neighbour interpolation."""
    _run_im([str(src), "-filter", "Point", "-resize",
             f"{width}x{height}!", str(dst)])


def quantize_palette(src: Path, dst: Path, palette_path: Path) -> None:
    """
    Quantize *src* to the Endesga-32 palette using Pillow.
    Transparency is preserved; dithering is disabled.

    ImageMagick cannot decode .gpl directly, so we use Pillow's quantize
    with a 'P'-mode palette image built from the parsed GPL colours.
    """
    colors = load_palette_gpl(palette_path)
    if not colors:
        raise RuntimeError(f"No colours parsed from {palette_path}")

    # Build a Pillow palette image (mode 'P')
    pal_img = Image.new("P", (1, 1))
    flat: list[int] = []
    for r, g, b in colors:
        flat.extend([r, g, b])
    flat += [0] * (256 * 3 - len(flat))   # pad to 256 entries
    pal_img.putpalette(flat)

    img = Image.open(src).convert("RGBA")
    alpha = img.split()[3]

    # Quantize the RGB channels, then restore alpha
    quantized = img.convert("RGB").quantize(palette=pal_img, dither=0).convert("RGBA")
    quantized.putalpha(alpha)
    quantized.save(dst)


# ─────────────────────────────────────────────────────────────────────────────
# Background removal
# ─────────────────────────────────────────────────────────────────────────────

def remove_background(img: Image.Image, tolerance: int = 30) -> Image.Image:
    """
    Remove the background from *img* using corner-seeded flood-fill.

    Samples corner pixels (TL, TR, BL, BR) and flood-fills any pixel whose
    colour is within *tolerance* Euclidean distance of the sampled colour.
    Returns an RGBA image with the background made transparent.
    """
    img = img.convert("RGBA")
    w, h = img.size
    data = img.load()

    # Sample the dominant corner colour
    corners = [
        data[0, 0], data[w - 1, 0],
        data[0, h - 1], data[w - 1, h - 1],
    ]
    # Pick the most common corner RGB (ignoring alpha)
    from collections import Counter
    bg_rgb = Counter(c[:3] for c in corners).most_common(1)[0][0]

    def _dist(px: tuple) -> float:
        return ((px[0] - bg_rgb[0]) ** 2 +
                (px[1] - bg_rgb[1]) ** 2 +
                (px[2] - bg_rgb[2]) ** 2) ** 0.5

    # BFS flood-fill from all four corners
    transparent = (0, 0, 0, 0)
    visited: set[tuple[int, int]] = set()
    queue: list[tuple[int, int]] = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]

    while queue:
        x, y = queue.pop()
        if (x, y) in visited:
            continue
        if not (0 <= x < w and 0 <= y < h):
            continue
        px = data[x, y]
        if _dist(px) > tolerance:
            continue
        visited.add((x, y))
        data[x, y] = transparent
        queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    return img


def corner_uniformity(img: Image.Image) -> float:
    """
    Returns a 0–1 confidence score for how uniform the corner pixels are.
    Higher = more uniform background → easier to remove reliably.
    """
    img = img.convert("RGB")
    w, h = img.size
    data = img.load()
    corners = [
        data[0, 0], data[w - 1, 0],
        data[0, h - 1], data[w - 1, h - 1],
    ]
    # Mean pairwise distance between corners (lower = more uniform)
    dists = []
    for i in range(4):
        for j in range(i + 1, 4):
            d = sum((corners[i][k] - corners[j][k]) ** 2 for k in range(3)) ** 0.5
            dists.append(d)
    mean_dist = sum(dists) / len(dists)
    # Map: 0 → 1.0,  255√3 ≈ 441 → 0.0
    return max(0.0, 1.0 - mean_dist / 441.0)


# ─────────────────────────────────────────────────────────────────────────────
# Scoring
# ─────────────────────────────────────────────────────────────────────────────

def score_candidate(img: Image.Image) -> dict[str, float]:
    """
    Compute the four scoring dimensions and the weighted total for *img*.

    Returns a dict with keys: silhouette, alpha_coverage, palette_compliance,
    bg_removability, total.
    """
    rgba = img.convert("RGBA")
    w, h = rgba.size
    total_px = w * h

    # ── Silhouette clarity: Canny-like edge density on alpha mask ────────────
    alpha = rgba.split()[3]
    alpha_l = alpha.convert("L")
    edges = alpha_l.filter(ImageFilter.FIND_EDGES)
    edge_arr = list(edges.getdata())
    edge_px   = sum(1 for v in edge_arr if v > 30)
    edge_density = edge_px / total_px
    # Good range: 0.05–0.25
    sil_score = _range_score(edge_density, 0.05, 0.25)

    # ── Alpha coverage: fraction of non-transparent pixels ──────────────────
    alpha_arr    = list(alpha.getdata())
    opaque_px    = sum(1 for v in alpha_arr if v > 10)
    alpha_cov    = opaque_px / total_px
    # Good range: 0.10–0.70
    alpha_score  = _range_score(alpha_cov, 0.10, 0.70)

    # ── Palette compliance: unique RGB colors in opaque pixels ───────────────
    rgb = rgba.convert("RGB")
    rgb_data = list(rgb.getdata())
    unique_colors = len(set(
        rgb_data[i] for i, a in enumerate(alpha_arr) if a > 10
    ))
    # Good: ≤ 32 (score 1.0 at ≤32, falls off linearly to 0 at 64)
    palette_score = max(0.0, 1.0 - max(0, unique_colors - 32) / 32.0)

    # ── Background removability: corner uniformity ───────────────────────────
    bg_score = corner_uniformity(img)

    # Weights: silhouette×3, alpha×2, palette×1, bg×2  (max total=8)
    total = (sil_score * 3 + alpha_score * 2 + palette_score * 1 + bg_score * 2) / 8.0

    return {
        "silhouette":       round(sil_score,    3),
        "alpha_coverage":   round(alpha_score,  3),
        "palette_compliance": round(palette_score, 3),
        "bg_removability":  round(bg_score,     3),
        "total":            round(total,         3),
    }


def _range_score(value: float, lo: float, hi: float) -> float:
    """Map *value* in [lo, hi] → 1.0, outside → 0.0 (hard clip)."""
    if lo <= value <= hi:
        return 1.0
    return 0.0


# ─────────────────────────────────────────────────────────────────────────────
# Spec loading
# ─────────────────────────────────────────────────────────────────────────────

def load_spec() -> list[dict]:
    if not SPEC_PATH.exists():
        sys.exit(f"Sprite spec not found: {SPEC_PATH}\nRun sprites_mode2.json generation first.")
    return json.loads(SPEC_PATH.read_text())


def get_output_path(entry: dict) -> Path:
    """Return the final output PNG path for a sprite spec entry."""
    biome = entry.get("biome")
    group = entry["group"]
    name  = entry["name"]
    if biome:
        return OUT_BASE / f"biome_{biome}" / group / f"{name}.png"
    return OUT_BASE / group / f"{name}.png"


def get_candidates(name: str) -> list[Path]:
    """Return sorted list of candidate PNGs for a sprite name."""
    cdir = CANDIDATES_DIR / name
    if not cdir.exists():
        return []
    return sorted(cdir.glob("candidate_*.png"))


# ─────────────────────────────────────────────────────────────────────────────
# Core post-process pipeline
# ─────────────────────────────────────────────────────────────────────────────

def postprocess_sprite(entry: dict, verbose: bool = True) -> dict:
    """
    Run the full post-process pipeline for one sprite entry.

    Returns a result dict: {name, best_candidate, score, flagged, output_path}.
    """
    name      = entry["name"]
    size_px   = entry["size_px"]   # [width, height]
    target_w, target_h = size_px[0], size_px[1]

    candidates = get_candidates(name)
    if not candidates:
        if verbose:
            print(f"  SKIP  {name} — no candidates in {CANDIDATES_DIR / name}/")
        return {"name": name, "flagged": True, "reason": "no_candidates"}

    scores: list[tuple[float, int, Path]] = []

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        for idx, cand_path in enumerate(candidates):
            # Step 1: resize
            resized = tmp / f"resized_{idx}.png"
            try:
                resize_nearest(cand_path, resized, target_w, target_h)
            except RuntimeError as e:
                if verbose:
                    print(f"  WARN  {name} candidate_{idx}: resize failed — {e}")
                continue

            # Step 2: quantize to Endesga-32
            quantized = tmp / f"quantized_{idx}.png"
            try:
                quantize_palette(resized, quantized, PALETTE_PATH)
            except RuntimeError as e:
                if verbose:
                    print(f"  WARN  {name} candidate_{idx}: quantize failed — {e}")
                shutil.copy(resized, quantized)  # fall back to resized

            # Step 3: score (on quantized image before BG removal — uses raw corners)
            img = Image.open(quantized)
            sc  = score_candidate(img)
            scores.append((sc["total"], idx, quantized))

            if verbose:
                print(f"         {name} candidate_{idx}: "
                      f"sil={sc['silhouette']:.2f}  "
                      f"alpha={sc['alpha_coverage']:.2f}  "
                      f"pal={sc['palette_compliance']:.2f}  "
                      f"bg={sc['bg_removability']:.2f}  "
                      f"→ total={sc['total']:.3f}")

        if not scores:
            return {"name": name, "flagged": True, "reason": "all_candidates_failed"}

        scores.sort(key=lambda t: t[0], reverse=True)
        best_score, best_idx, best_path = scores[0]

        # Step 4: flag if all candidates are low-quality
        flagged = best_score < AUTO_SELECT_THRESHOLD

        if flagged:
            if verbose:
                print(f"  FLAG  {name} — best score {best_score:.3f} < threshold "
                      f"{AUTO_SELECT_THRESHOLD:.2f} (manual review needed)")
            return {"name": name, "flagged": True, "reason": "low_score",
                    "best_score": best_score}

        # Step 5: BG removal on best candidate
        img     = Image.open(best_path)
        img_out = remove_background(img)

        # Step 6: write final output
        out_path = get_output_path(entry)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        img_out.save(out_path, "PNG")

        if verbose:
            print(f"  OK    {name}  candidate_{best_idx}  "
                  f"score={best_score:.3f}  →  {out_path.relative_to(PROJECT_ROOT)}")

        return {
            "name":           name,
            "flagged":        False,
            "best_candidate": best_idx,
            "best_score":     best_score,
            "output_path":    str(out_path.relative_to(PROJECT_ROOT)),
        }


# ─────────────────────────────────────────────────────────────────────────────
# Flag file helpers
# ─────────────────────────────────────────────────────────────────────────────

def load_flagged() -> dict:
    if FLAG_FILE.exists():
        return json.loads(FLAG_FILE.read_text())
    return {}


def save_flagged(data: dict) -> None:
    FLAG_FILE.parent.mkdir(parents=True, exist_ok=True)
    FLAG_FILE.write_text(json.dumps(data, indent=2))


# ─────────────────────────────────────────────────────────────────────────────
# High-level passes
# ─────────────────────────────────────────────────────────────────────────────

def run_sprites(entries: list[dict], verbose: bool = True) -> None:
    flagged_map = load_flagged()
    ok = flagged = skipped = 0

    for entry in entries:
        result = postprocess_sprite(entry, verbose=verbose)
        if result.get("flagged"):
            flagged_map[entry["name"]] = result
            flagged += 1
        else:
            flagged_map.pop(entry["name"], None)
            ok += 1

    save_flagged(flagged_map)
    print(f"\nDone. {ok} OK, {flagged} flagged for manual review, {skipped} skipped.")
    if flagged:
        print(f"Flagged list saved to: {FLAG_FILE.relative_to(PROJECT_ROOT)}")


def run_consistency(spec: list[dict]) -> None:
    """Re-score all generated sprites and report outliers (no re-processing)."""
    print("Consistency check — scoring all generated sprites...\n")
    issues = []
    for entry in spec:
        out = get_output_path(entry)
        if not out.exists():
            continue
        img = Image.open(out)
        sc  = score_candidate(img)
        if sc["total"] < AUTO_SELECT_THRESHOLD:
            issues.append((entry["name"], sc["total"], str(out.relative_to(PROJECT_ROOT))))
            print(f"  LOW   {entry['name']:<40s}  score={sc['total']:.3f}")

    if not issues:
        print("All generated sprites pass the consistency threshold.")
    else:
        print(f"\n{len(issues)} sprites below threshold — re-run with --pass fix to reprocess.")


def run_fix(spec: list[dict]) -> None:
    """Re-run post-processing only on flagged sprites."""
    flagged_map = load_flagged()
    if not flagged_map:
        print("No flagged sprites to fix.")
        return
    entries = [e for e in spec if e["name"] in flagged_map]
    print(f"Re-processing {len(entries)} flagged sprites...\n")
    run_sprites(entries)


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Post-process Scenario-generated Mode 2 sprites for Choplifter Clone"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--sprite", metavar="NAME",
                       help="Post-process a single sprite by name")
    group.add_argument("--group",  metavar="GROUP",
                       help="Post-process all sprites in a group")
    group.add_argument("--pass",   dest="run_pass",
                       choices=["all", "consistency", "fix"],
                       help="Run a named pass over all sprites")
    parser.add_argument("--quiet", action="store_true",
                        help="Suppress per-candidate scoring output")
    args = parser.parse_args()

    # Validate dependencies
    if shutil.which("convert") is None:
        sys.exit("ImageMagick 'convert' not found. Install: sudo apt install imagemagick")
    if not PALETTE_PATH.exists():
        sys.exit(f"Palette file not found: {PALETTE_PATH}")

    verbose = not args.quiet

    if args.sprite:
        spec = load_spec()
        entry = next((e for e in spec if e["name"] == args.sprite), None)
        if entry is None:
            sys.exit(f"Sprite {args.sprite!r} not found in sprites_mode2.json")
        run_sprites([entry], verbose=verbose)

    elif args.group:
        spec    = load_spec()
        entries = [e for e in spec if e["group"] == args.group]
        if not entries:
            sys.exit(f"Group {args.group!r} not found in sprites_mode2.json")
        print(f"Post-processing group '{args.group}' ({len(entries)} sprites)...\n")
        run_sprites(entries, verbose=verbose)

    elif args.run_pass == "all":
        spec = load_spec()
        print(f"Post-processing all {len(spec)} sprites...\n")
        run_sprites(spec, verbose=verbose)

    elif args.run_pass == "consistency":
        spec = load_spec()
        run_consistency(spec)

    elif args.run_pass == "fix":
        spec = load_spec()
        run_fix(spec)


if __name__ == "__main__":
    main()
