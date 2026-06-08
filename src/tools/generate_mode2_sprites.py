#!/usr/bin/env python3
"""
generate_mode2_sprites.py - Bulk generate Mode 2 sprites via Scenario REST API.

Reads sprites_mode2.json, generates 4 candidates per sprite, downloads them to
assets/graphics/mode2/_candidates/<name>/candidate_N.png, then runs
postprocess_sprites.py for each group to auto-select the best.

Usage:
    python3 src/tools/generate_mode2_sprites.py                # all 161 sprites
    python3 src/tools/generate_mode2_sprites.py --group chopper_side
    python3 src/tools/generate_mode2_sprites.py --sprite chopper_side_5
    python3 src/tools/generate_mode2_sprites.py --dry-run      # print plan only
    python3 src/tools/generate_mode2_sprites.py --no-postprocess  # skip postprocess step
"""

import os
import sys
import json
import time
import argparse
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    import requests
except ImportError:
    sys.exit("Install requests: pip install requests")

# ── Constants ────────────────────────────────────────────────────────────────

TEAM_ID     = "team_c35Dy4P8bthbSsx3iFWnX9k2"
PROJECT_ID  = "proj_91rmZo5Lsyp4q6VXdYq6GTk2"
AUTH        = "Basic YXBpX1pGTGVnZEtMazJibWIxZ1dUaHhnd1pOeTpMbnpuQWpXZTRhWjhBakIyQ3FEdjlGS00="
BASE_URL    = "https://api.cloud.scenario.com/v1"
MODEL_ID    = "model_retrodiffusion-plus"
POLL_DELAY      = 3      # seconds between polls
POLL_MAX        = 120    # max polls per job (~6 min)
WORKERS         = 1      # parallel generation jobs (keep 1 to avoid 429)
RETRY_MAX       = 6      # retries on 429 / transient errors
RETRY_BASE      = 15     # base seconds for exponential backoff on 429
SUBMIT_DELAY    = 8      # seconds to sleep between each job submission

REPO_ROOT       = Path(__file__).resolve().parents[2]
SPEC_FILE       = REPO_ROOT / "src/tools/config/sprites_mode2.json"
CANDIDATES_DIR  = REPO_ROOT / "assets/graphics/mode2/_candidates"
POSTPROCESS     = REPO_ROOT / "src/tools/postprocess_sprites.py"

HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "Accept": "application/json",
}

# ── API helpers ───────────────────────────────────────────────────────────────

def submit_job(sprite: dict) -> str:
    """POST to generate endpoint, return job_id. Retries on 429."""
    w, h = sprite["gen_size_px"]
    payload = {
        "prompt":     sprite["prompt"],
        "negative":   sprite["negative"],
        "width":      w,
        "height":     h,
        "numOutputs": sprite["candidates"],
        "style":      "low_res",
        "removeBg":   True,
        "projectId":  PROJECT_ID,
    }
    url = f"{BASE_URL}/generate/custom/{MODEL_ID}"
    for attempt in range(RETRY_MAX):
        if attempt == 0:
            time.sleep(SUBMIT_DELAY)   # proactive throttle before every submission
        r = requests.post(url, json=payload, headers=HEADERS, timeout=30)
        if r.status_code == 429:
            wait = RETRY_BASE * (2 ** attempt)
            print(f"    [429] rate-limited, waiting {wait}s (attempt {attempt+1}/{RETRY_MAX})")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()["job"]["jobId"]
    raise RuntimeError(f"Gave up after {RETRY_MAX} retries (429 rate limit)")


def poll_job(job_id: str) -> list[str]:
    """Poll until job succeeds. Returns list of asset_ids."""
    url = f"{BASE_URL}/jobs/{job_id}?teamId={TEAM_ID}"
    for _ in range(POLL_MAX):
        time.sleep(POLL_DELAY)
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        job = r.json()["job"]
        status = job["status"]
        if status == "success":
            return job["metadata"].get("assetIds", [])
        if status in ("failed", "error", "cancelled"):
            raise RuntimeError(f"Job {job_id} ended with status={status}")
    raise TimeoutError(f"Job {job_id} timed out after {POLL_MAX * POLL_DELAY}s")


def get_asset_url(asset_id: str) -> str:
    """Fetch signed CDN URL for an asset."""
    url = f"{BASE_URL}/assets/{asset_id}?teamId={TEAM_ID}"
    r = requests.get(url, headers=HEADERS, timeout=15)
    r.raise_for_status()
    return r.json()["asset"]["url"]


def download_url(cdn_url: str, dest: Path):
    """Download a CDN URL to dest."""
    r = requests.get(cdn_url, timeout=60)
    r.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(r.content)


# ── Core logic ────────────────────────────────────────────────────────────────

def generate_sprite(sprite: dict) -> tuple[str, bool, str]:
    """Generate + download all candidates. Returns (name, success, msg)."""
    name = sprite["name"]
    out_dir = CANDIDATES_DIR / name
    expected = sprite["candidates"]

    # Skip if already complete
    if out_dir.exists():
        existing = sorted(out_dir.glob("candidate_*.png"))
        if len(existing) >= expected:
            return name, True, f"skipped ({len(existing)} already exist)"

    try:
        job_id = submit_job(sprite)
        asset_ids = poll_job(job_id)

        if not asset_ids:
            return name, False, "job succeeded but returned no assets"

        out_dir.mkdir(parents=True, exist_ok=True)
        for i, asset_id in enumerate(asset_ids[:expected]):
            cdn_url = get_asset_url(asset_id)
            dest = out_dir / f"candidate_{i}.png"
            download_url(cdn_url, dest)

        return name, True, f"{len(asset_ids)} candidates saved"

    except Exception as exc:
        return name, False, str(exc)


def run_postprocess(group: str, quiet: bool = False) -> bool:
    """Run postprocess_sprites.py for a group. Returns True if clean exit."""
    cmd = [sys.executable, str(POSTPROCESS), "--group", group]
    if quiet:
        cmd.append("--quiet")
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=not quiet)
    if result.returncode != 0 and not quiet:
        print(f"  [POSTPROCESS WARN] {group} exited {result.returncode}", file=sys.stderr)
        if result.stderr:
            print(result.stderr.decode(errors="replace"), file=sys.stderr)
    return result.returncode == 0


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--group",         help="Only generate sprites in this group")
    parser.add_argument("--sprite",        help="Only generate this specific sprite")
    parser.add_argument("--workers", type=int, default=WORKERS,
                        help=f"Parallel workers (default {WORKERS})")
    parser.add_argument("--dry-run",       action="store_true",
                        help="Print what would be generated, don't run")
    parser.add_argument("--no-postprocess", action="store_true",
                        help="Skip running postprocess_sprites.py after each group")
    parser.add_argument("--force",         action="store_true",
                        help="Re-generate even if candidates already exist")
    args = parser.parse_args()

    sprites = json.loads(SPEC_FILE.read_text())

    if args.sprite:
        sprites = [s for s in sprites if s["name"] == args.sprite]
    elif args.group:
        sprites = [s for s in sprites if s["group"] == args.group]

    if not sprites:
        print("No sprites matched.", file=sys.stderr)
        sys.exit(1)

    if args.force:
        # Remove existing candidates so they get regenerated
        for s in sprites:
            d = CANDIDATES_DIR / s["name"]
            if d.exists():
                import shutil
                shutil.rmtree(d)

    # Group ordering for postprocess (process each group together)
    groups_ordered = list(dict.fromkeys(s["group"] for s in sprites))

    print(f"{'DRY RUN: ' if args.dry_run else ''}Generating {len(sprites)} sprites "
          f"across {len(groups_ordered)} group(s) with {args.workers} workers")
    if args.dry_run:
        for g in groups_ordered:
            group_sprites = [s for s in sprites if s["group"] == g]
            print(f"\n  [{g}] {len(group_sprites)} sprites")
            for s in group_sprites:
                print(f"    {s['name']:40s}  {s['gen_size_px'][0]}x{s['gen_size_px'][1]}")
        return

    failed = []
    succeeded = 0

    # Generate group-by-group so postprocess can run after each group completes
    for group in groups_ordered:
        group_sprites = [s for s in sprites if s["group"] == group]
        print(f"\n── {group} ({len(group_sprites)} sprites) ──")

        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(generate_sprite, s): s["name"] for s in group_sprites}
            for future in as_completed(futures):
                name = futures[future]
                try:
                    _, ok, msg = future.result()
                except Exception as exc:
                    ok, msg = False, str(exc)

                status = "OK " if ok else "ERR"
                print(f"  [{status}] {name}: {msg}")
                if ok:
                    succeeded += 1
                else:
                    failed.append(name)

        if not args.no_postprocess:
            print(f"  → postprocess {group}...")
            run_postprocess(group, quiet=False)

    print(f"\n{'─'*60}")
    print(f"Done. {succeeded}/{len(sprites)} succeeded, {len(failed)} failed.")
    if failed:
        print(f"Failed sprites:\n  " + "\n  ".join(failed))
        sys.exit(1)


if __name__ == "__main__":
    main()
