#!/usr/bin/env python3
"""
generate_store_assets.py — Generate Google Play Store assets via Scenario API.

Generates 2 candidates per image, downloads them, then adds game-title text
overlay via Pillow. Each variant gets its own subdirectory in assets/store/.

Usage:
    python3 src/tools/generate_store_assets.py            # all 3 variants
    python3 src/tools/generate_store_assets.py --variant dustoff
    python3 src/tools/generate_store_assets.py --variant air_rescue
    python3 src/tools/generate_store_assets.py --variant evac
    python3 src/tools/generate_store_assets.py --dry-run

Each variant produces:
    icon_512x512_raw_0.png / _1.png    — Scenario output (pick best manually)
    icon_512x512.png                   — best candidate + title text overlay
    feature_1024x500_raw_0.png / _1.png
    feature_1024x500.png
    screenshot_desert_raw_0.png / _1.png
    screenshot_desert.png
    screenshot_jungle_raw_0.png / _1.png
    screenshot_jungle.png
"""

import sys
import time
import argparse
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Install requests: pip install requests")

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Install Pillow: pip install Pillow")

# ── API constants ─────────────────────────────────────────────────────────────

TEAM_ID    = "team_c35Dy4P8bthbSsx3iFWnX9k2"
PROJECT_ID = "proj_91rmZo5Lsyp4q6VXdYq6GTk2"
AUTH       = "Basic YXBpX1pGTGVnZEtMazJibWIxZ1dUaHhnd1pOeTpMbnpuQWpXZTRhWjhBakIyQ3FEdjlGS00="
BASE_URL   = "https://api.cloud.scenario.com/v1"
MODEL_ID   = "model_retrodiffusion-plus"

HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "Accept": "application/json",
}

POLL_DELAY  = 3
POLL_MAX    = 120
RETRY_MAX   = 6
RETRY_BASE  = 15
CANDIDATES  = 2

REPO_ROOT   = Path(__file__).resolve().parents[2]
STORE_DIR   = REPO_ROOT / "assets/store"

# ── Visual identity definitions ───────────────────────────────────────────────

VARIANTS = {
    "dustoff": {
        "name": "Dustoff!",
        "tagline": "Rescue. Evade. Survive.",
        "bg": (42, 58, 78),
        "accent": (220, 170, 50),
        "text_color": (240, 230, 200),
        "images": {
            "icon": {
                "width": 384, "height": 384,
                "removeBg": False,
                "prompt": (
                    "military rescue helicopter flying in front of desert canyon, "
                    "pixel art game app icon, amber golden sunset, steel blue-grey sky, "
                    "small tank silhouette below, bold centered composition, "
                    "retro arcade game icon, high contrast, dramatic lighting"
                ),
                "negative": (
                    "text, watermark, logo, letters, words, blurry, "
                    "modern 3d render, photorealistic, nsfw"
                ),
            },
            "feature": {
                "width": 384, "height": 192,
                "removeBg": False,
                "prompt": (
                    "side-scrolling military helicopter action game, wide banner scene, "
                    "desert biome with mountains, rescue helicopter flying centre-right, "
                    "military base on left, tank on right, hostage figures on ground, "
                    "amber-golden sky, pixel art, retro arcade game art, "
                    "dramatic action scene, epic composition"
                ),
                "negative": (
                    "text, watermark, ui elements, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
            "screenshot_desert": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "side-scrolling helicopter rescue game portrait screenshot, desert level, "
                    "pixel art, military helicopter in flight centre, sand dunes and rocky mountains, "
                    "military base structure on left, enemy tank on right, small running figures, "
                    "steel blue-grey sky, amber highlights, retro arcade game style, "
                    "dynamic gameplay moment"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
            "screenshot_jungle": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "side-scrolling helicopter rescue game portrait screenshot, jungle level, "
                    "pixel art, military helicopter hovering above dense jungle canopy, "
                    "tropical trees and foliage, enemy tank visible through trees, "
                    "hostage figures running, twilight amber sky above treeline, "
                    "retro arcade game style, action gameplay moment"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
        },
    },

    "air_rescue": {
        "name": "Air Rescue",
        "tagline": "The Classic Returns.",
        "bg": (20, 30, 80),
        "accent": (255, 80, 80),
        "text_color": (255, 255, 80),
        "images": {
            "icon": {
                "width": 384, "height": 384,
                "removeBg": False,
                "prompt": (
                    "retro 1980s arcade helicopter game icon, pixel art, deep royal blue sky, "
                    "bright red rescue helicopter centred, bold arcade colour palette, "
                    "yellow and red highlights, classic arcade cabinet aesthetic, "
                    "bold square composition, high contrast pixel art game icon"
                ),
                "negative": (
                    "text, watermark, words, letters, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
            "feature": {
                "width": 384, "height": 192,
                "removeBg": False,
                "prompt": (
                    "retro 1980s arcade side-scrolling helicopter game, wide landscape banner, "
                    "jungle biome, deep blue arcade sky, red helicopter flying right, "
                    "yellow enemy fighters, green jungle below, classic arcade game art, "
                    "bold primary colours, energetic action scene, pixel art"
                ),
                "negative": (
                    "text, watermark, ui, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
            "screenshot_desert": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "retro arcade helicopter game portrait screenshot, desert level, pixel art, "
                    "deep blue arcade sky, bright red rescue helicopter in flight, "
                    "desert sand and rocks, yellow sun, enemy tank, hostage figures, "
                    "bold primary arcade colours, classic 1980s video game aesthetic"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
            "screenshot_jungle": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "retro arcade helicopter game portrait screenshot, jungle level, pixel art, "
                    "deep blue sky above bright green jungle canopy, red helicopter, "
                    "yellow and red enemy threats, hostage rescue, classic arcade colours, "
                    "1980s video game pixel art aesthetic, bold vibrant"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw"
                ),
            },
        },
    },

    "evac": {
        "name": "EVAC",
        "tagline": "Every Second Counts.",
        "bg": (8, 12, 20),
        "accent": (0, 220, 120),
        "text_color": (220, 255, 230),
        "images": {
            "icon": {
                "width": 384, "height": 384,
                "removeBg": False,
                "prompt": (
                    "tactical helicopter evacuation game icon, pixel art, near-black night sky, "
                    "neon green glowing helicopter silhouette, dark military atmosphere, "
                    "glowing green accents, dark sci-fi aesthetic, bold centred composition, "
                    "tactical stealth game icon, dramatic"
                ),
                "negative": (
                    "text, watermark, words, letters, blurry, modern 3d, photorealistic, nsfw, "
                    "bright colours, pastel"
                ),
            },
            "feature": {
                "width": 384, "height": 192,
                "removeBg": False,
                "prompt": (
                    "tactical helicopter extraction game, wide banner, alien world biome, "
                    "near-black sky with neon green atmospheric glow, strange alien landscape, "
                    "dark helicopter mid-extraction, glowing green environmental lighting, "
                    "dark sci-fi pixel art, dramatic cinematic composition, moody atmosphere"
                ),
                "negative": (
                    "text, watermark, ui, blurry, modern 3d, photorealistic, nsfw, "
                    "bright colours, cheerful, cartoonish"
                ),
            },
            "screenshot_desert": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "tactical helicopter game portrait screenshot, alien desert level, pixel art, "
                    "near-black sky, alien rock formations, neon green atmospheric lighting, "
                    "dark helicopter in flight, strange alien enemy units, "
                    "rescue figures on alien ground, dark moody atmosphere, sci-fi"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw, bright"
                ),
            },
            "screenshot_jungle": {
                "width": 192, "height": 384,
                "removeBg": False,
                "prompt": (
                    "tactical helicopter game portrait screenshot, alien jungle level, pixel art, "
                    "dark bioluminescent alien vegetation, neon green glowing plants, "
                    "helicopter extraction through alien forest, dark threatening atmosphere, "
                    "glowing green environment, tactical sci-fi pixel art"
                ),
                "negative": (
                    "text, hud, ui, watermark, blurry, modern 3d, photorealistic, nsfw, bright"
                ),
            },
        },
    },
}

# ── API helpers ───────────────────────────────────────────────────────────────

def submit_job(spec: dict) -> str:
    payload = {
        "prompt":     spec["prompt"],
        "negative":   spec.get("negative", ""),
        "width":      spec["width"],
        "height":     spec["height"],
        "numOutputs": CANDIDATES,
        "removeBg":   spec.get("removeBg", False),
        "projectId":  PROJECT_ID,
    }
    url = f"{BASE_URL}/generate/custom/{MODEL_ID}?teamId={TEAM_ID}"
    for attempt in range(RETRY_MAX):
        time.sleep(8)   # proactive throttle
        try:
            r = requests.post(url, json=payload, headers=HEADERS, timeout=30)
        except (requests.exceptions.ConnectionError,
                requests.exceptions.ConnectTimeout,
                requests.exceptions.ReadTimeout) as exc:
            print(f"    [net] submit error, retrying ({attempt+1}/{RETRY_MAX}): {exc}")
            continue
        if r.status_code not in (200, 201, 429):
            print(f"    [{r.status_code}] body: {r.text[:400]}", file=sys.stderr)
            r.raise_for_status()
        if r.status_code == 429:
            wait = RETRY_BASE * (2 ** attempt)
            try:
                remaining = int(r.json().get("details", {}).get("remainingSeconds", 0))
                if remaining > wait:
                    wait = remaining + 5
            except Exception:
                pass
            print(f"    [429] waiting {wait}s (attempt {attempt+1}/{RETRY_MAX})")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()["job"]["jobId"]
    raise RuntimeError("Gave up after rate-limit retries")


def poll_job(job_id: str) -> list[str]:
    url = f"{BASE_URL}/jobs/{job_id}?teamId={TEAM_ID}"
    network_errors = 0
    for _ in range(POLL_MAX):
        time.sleep(POLL_DELAY)
        try:
            r = requests.get(url, headers=HEADERS, timeout=30)
            r.raise_for_status()
            network_errors = 0
        except (requests.exceptions.ConnectionError,
                requests.exceptions.ConnectTimeout,
                requests.exceptions.ReadTimeout) as exc:
            network_errors += 1
            if network_errors > 10:
                raise RuntimeError(f"Too many network errors polling {job_id}: {exc}")
            print(f"    [net] poll error ({network_errors}/10), retrying: {exc}")
            time.sleep(5)
            continue
        job = r.json()["job"]
        status = job["status"]
        if status == "success":
            return job["metadata"].get("assetIds", [])
        if status in ("failed", "error", "cancelled"):
            raise RuntimeError(f"Job {job_id} ended with status={status}")
    raise TimeoutError(f"Job {job_id} timed out")


def get_asset_url(asset_id: str) -> str:
    url = f"{BASE_URL}/assets/{asset_id}?teamId={TEAM_ID}"
    r = requests.get(url, headers=HEADERS, timeout=15)
    r.raise_for_status()
    return r.json()["asset"]["url"]


def download_url(cdn_url: str, dest: Path):
    for attempt in range(6):
        try:
            r = requests.get(cdn_url, timeout=60)
            r.raise_for_status()
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(r.content)
            return
        except (requests.exceptions.ConnectionError,
                requests.exceptions.ConnectTimeout,
                requests.exceptions.ReadTimeout) as exc:
            if attempt >= 5:
                raise
            print(f"    [net] download error, retrying ({attempt+1}/5): {exc}")
            time.sleep(5)


# ── Font helper ───────────────────────────────────────────────────────────────

def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


# ── Overlay helpers ───────────────────────────────────────────────────────────

def apply_icon_overlay(img: Image.Image, v: dict) -> Image.Image:
    """Add game name + accent bar to icon."""
    img = img.convert("RGBA").resize((512, 512), Image.NEAREST)
    draw = ImageDraw.Draw(img)
    name = v["name"]
    font = load_font(72)

    # Dark strip at bottom
    overlay = Image.new("RGBA", (512, 130), (0, 0, 0, 180))
    img.paste(overlay, (0, 382), overlay)

    bbox = draw.textbbox((0, 0), name, font=font)
    tw = bbox[2] - bbox[0]
    x = (512 - tw) // 2
    # Shadow
    draw.text((x + 2, 390 + 2), name, font=font, fill=(0, 0, 0, 200))
    draw.text((x, 390), name, font=font, fill=v["text_color"])
    # Accent underline
    draw.rectangle([(x, 470), (x + tw, 474)], fill=v["accent"])
    return img


def apply_feature_overlay(img: Image.Image, v: dict) -> Image.Image:
    """Add game name + tagline to feature graphic, crop to 1024×500."""
    img = img.convert("RGBA").resize((1024, 512), Image.NEAREST)
    # Crop to 1024×500
    img = img.crop((0, 6, 1024, 506))
    W, H = img.size
    draw = ImageDraw.Draw(img)

    # Dark gradient strip at bottom
    overlay = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for y in range(120):
        alpha = int(200 * (y / 120))
        od.line([(0, y), (W, y)], fill=(0, 0, 0, alpha))
    img.paste(overlay, (0, H - 120), overlay)

    font_title = load_font(80)
    font_tag   = load_font(30)

    # Accent left bar
    draw.rectangle([(36, H - 110), (40, H - 18)], fill=v["accent"])

    name = v["name"]
    tag  = v["tagline"]
    bbox = draw.textbbox((0, 0), name, font=font_title)
    tw = bbox[2] - bbox[0]
    draw.text((46 + 2, H - 110 + 2), name, font=font_title, fill=(0, 0, 0, 200))
    draw.text((46, H - 110), name, font=font_title, fill=v["text_color"])
    draw.text((48, H - 26), tag, font=font_tag, fill=v["accent"])

    return img


def apply_screenshot_overlay(img: Image.Image, v: dict, label: str) -> Image.Image:
    """Upscale to 1080×2400, add minimal HUD hints top and bottom."""
    # Upscale raw image to full portrait size
    img = img.convert("RGBA").resize((1080, 1620), Image.NEAREST)
    # Extend canvas to 1080×2400 with bg colour at top/bottom
    canvas = Image.new("RGBA", (1080, 2400), (*v["bg"], 255))
    canvas.paste(img, (0, 390))
    draw = ImageDraw.Draw(canvas)

    # Top HUD bar
    draw.rectangle([(0, 0), (1080, 110)], fill=(0, 0, 0, 220))
    font_hud = load_font(44)
    draw.text((24, 30), "FUEL  ████████░░    SCORE  000000",
              font=font_hud, fill=v["accent"])

    # Scene label (below HUD)
    font_lbl = load_font(52)
    draw.text((40, 130), label, font=font_lbl, fill=v["accent"])

    # Game name top-right
    font_name = load_font(48)
    name = v["name"]
    bbox = draw.textbbox((0, 0), name, font=font_name)
    draw.text((1080 - (bbox[2] - bbox[0]) - 24, 32), name,
              font=font_name, fill=v["text_color"])

    # Bottom controls strip
    draw.rectangle([(0, 2240), (1080, 2400)], fill=(0, 0, 0, 200))
    font_ctrl = load_font(40)
    draw.text((60, 2290), "◀  ▲  ▼  ▶                  🔫", font=font_ctrl, fill=v["text_color"])

    return canvas


OVERLAY_FNS = {
    "icon":               (apply_icon_overlay,       None),
    "feature":            (apply_feature_overlay,    None),
    "screenshot_desert":  (apply_screenshot_overlay, "Desert Rescue"),
    "screenshot_jungle":  (apply_screenshot_overlay, "Jungle Extraction"),
}

# ── Core generate / composite ─────────────────────────────────────────────────

def generate_image(variant_key: str, image_key: str, spec: dict, v: dict, dry_run: bool):
    out_dir = STORE_DIR / variant_key
    out_dir.mkdir(parents=True, exist_ok=True)

    raw_paths = [out_dir / f"{image_key}_raw_{i}.png" for i in range(CANDIDATES)]
    final_path = out_dir / f"{image_key.replace('screenshot_desert', 'screenshot_desert').replace('screenshot_jungle','screenshot_jungle')}.png"

    # Normalise final filename
    if image_key == "icon":
        final_path = out_dir / "icon_512x512.png"
    elif image_key == "feature":
        final_path = out_dir / "feature_1024x500.png"
    elif image_key == "screenshot_desert":
        final_path = out_dir / "screenshot_desert.png"
    elif image_key == "screenshot_jungle":
        final_path = out_dir / "screenshot_jungle.png"

    if dry_run:
        print(f"  [DRY RUN] {variant_key}/{image_key}  {spec['width']}×{spec['height']}")
        return

    # Skip if all raws already exist
    if all(p.exists() for p in raw_paths):
        print(f"  [skip] {variant_key}/{image_key} raws already present")
    else:
        print(f"  Submitting {variant_key}/{image_key} ({spec['width']}×{spec['height']}) …", flush=True)
        job_id    = submit_job(spec)
        asset_ids = poll_job(job_id)
        for i, aid in enumerate(asset_ids[:CANDIDATES]):
            cdn = get_asset_url(aid)
            download_url(cdn, raw_paths[i])
            print(f"    → raw_{i} saved")

    # Composite: always pick raw_0 as the base for the final image
    # (user can swap in raw_1 manually if they prefer it)
    overlay_fn, overlay_arg = OVERLAY_FNS[image_key]
    base = Image.open(raw_paths[0]).convert("RGBA")
    if overlay_arg is not None:
        final = overlay_fn(base, v, overlay_arg)
    else:
        final = overlay_fn(base, v)

    final.save(final_path)
    print(f"    → {final_path.relative_to(REPO_ROOT)}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=list(VARIANTS.keys()),
                        help="Generate one variant only")
    parser.add_argument("--image", choices=list(next(iter(VARIANTS.values()))["images"].keys()),
                        help="Generate one image type only")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    keys = [args.variant] if args.variant else list(VARIANTS.keys())
    image_filter = args.image

    total = 0
    for vk in keys:
        v = VARIANTS[vk]
        print(f"\n── {v['name']} ({vk}) ──")
        for ik, spec in v["images"].items():
            if image_filter and ik != image_filter:
                continue
            generate_image(vk, ik, spec, v, args.dry_run)
            total += 1

    print(f"\nDone — {total} image(s) processed.")


if __name__ == "__main__":
    main()
