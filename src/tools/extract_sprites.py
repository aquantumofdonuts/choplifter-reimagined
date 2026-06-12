#!/usr/bin/env python3
"""
Choplifter Apple II sprite extractor.

Reads CHOPGFX / CHOPGFXHI binaries from blondie7575/ChoplifterReverse and
outputs every named sprite as a PNG.

Apple II HGR sprite format (as documented in choplifter.s):
  byte 0  : width in pixels
  byte 1  : height in pixels
  bytes 2+: pixel data, row-major, ceil(width/7) bytes per row
             Each byte holds 7 pixels in bits 0-6 (bit 0 = leftmost pixel).
             Bit 7 is the HGR palette selector and is ignored for extraction.
             Pixel value 0 → transparent; 1 → foreground.

Load addresses (from loader.s):
  CHOPGFX   → $a102  (7662 bytes)
  CHOPGFXHI → $bef0  (112 bytes, a small trailing page that overlaps ProDOS)

Usage:
  python3 extract_sprites.py [--gfx CHOPGFX] [--gfxhi CHOPGFXHI] [--out OUTPUT_DIR] [--scale N]

Requires: Pillow  (pip install pillow)
"""

import argparse
import math
import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install pillow")


# ---------------------------------------------------------------------------
# Apple II 6-colour HGR palette (NTSC composite approximation)
# Pixel encoding: two adjacent bits → colour.  Odd/even column + palette bit
# determine the actual hue.  For "mode 1 faithful" export we do a simple
# per-pixel lookup; for "mask only" export we just use white-on-transparent.
# ---------------------------------------------------------------------------
#
# NTSC composite colours (commonly used emulator values):
#   black   #000000   violet  #C630FF   green   #3DFF39   white   #FFFFFF
#   orange  #FF6300   blue    #006BFF
#
# Simplified 1-bit per pixel mapping used below:
#   bit=0 → transparent (alpha 0)
#   bit=1 → sprite_color (default white, overridable)
#
# For a full NTSC composite render you would need to look at pairs of
# adjacent pixels and the palette bit together.  That is left as an option
# (--ntsc) below for completeness.

NTSC_PALETTE = {
    # (palette_bit, pixel_column_parity): (R, G, B)
    (0, 0): (0xC6, 0x30, 0xFF),   # violet
    (0, 1): (0x3D, 0xFF, 0x39),   # green
    (1, 0): (0x00, 0x6B, 0xFF),   # blue
    (1, 1): (0xFF, 0x63, 0x00),   # orange
}
WHITE  = (0xFF, 0xFF, 0xFF)
BLACK  = (0x00, 0x00, 0x00)
TRANSP = (0, 0, 0, 0)


# ---------------------------------------------------------------------------
# All named sprite tables extracted from choplifter.s ($a000 region).
# Format: (group_name, [(label, address), ...])
# Addresses are Apple II memory addresses; we convert to file offsets below.
# ---------------------------------------------------------------------------
SPRITE_TABLES = [
    ("chopper_side", [
        ("tilt_m5",   0xa102),   # -5 full nose-down
        ("tilt_m4",   0xa14c),
        ("tilt_m3",   0xa18e),
        ("tilt_m2",   0xa1db),
        ("tilt_m1",   0xa223),
        ("tilt_0",    0xa26b),   # no tilt (level)
        ("tilt_p1",   0xa2ae),
        ("tilt_p2",   0xa2f1),
        ("tilt_p3",   0xa334),
        ("tilt_p4",   0xa37c),
        ("tilt_p5",   0xa3c9),   # +5 full nose-up
    ]),
    ("chopper_headon", [
        ("headon_0",  0xa41b),   # Normal head-on
        ("rotate_1",  0xa437),   # Rotating to sideways frame 1
        ("rotate_2",  0xa453),
        ("rotate_3",  0xa47c),
        ("rotate_4",  0xa4b2),
    ]),
    ("chopper_squish", [
        ("squish_side",   0xa4e8),
        ("squish_headon", 0xa526),
    ]),
    ("rotor_main", [
        ("frame_1", 0xa540),
        ("frame_2", 0xa547),
        ("frame_3", 0xa54e),
    ]),
    ("rotor_tail", [
        ("frame_1", 0xa555),
        ("frame_2", 0xa55d),
        ("frame_3", 0xa565),
        ("frame_4", 0xa56b),
    ]),
    ("jet", [
        ("level",      0xa574),
        ("turn_01",    0xa585),
        ("turn_02",    0xa5b3),
        ("turn_03",    0xa5dc),
        ("turn_04",    0xa60b),
        ("turn_05",    0xa62d),
        ("turn_06",    0xa662),
        ("turn_07",    0xa6a4),
        ("turn_08",    0xa6e6),
        ("turn_09",    0xa709),
        ("turn_10",    0xa735),
        ("turn_11",    0xa75f),
        ("turn_12",    0xa789),
        ("turn_13",    0xa7c2),
        ("turn_14",    0xa81e),
        ("turn_15",    0xa85c),
        ("turn_16",    0xa892),
        ("turn_17",    0xa8c4),
        ("turn_18",    0xa8e7),
        ("turn_19",    0xa8fb),
        ("turn_20",    0xa957),
        ("turn_21",    0xa995),
        ("turn_22",    0xa9cb),
        ("turn_23",    0xaa01),
        ("turn_24",    0xaa24),
    ]),
    ("tank", [
        ("turret",    0xaa38),
        ("tread_1",   0xaa40),
        ("tread_2",   0xaa5a),
    ]),
    ("tank_cannon", [
        ("right",     0xaa74),
        ("up_right",  0xaa7b),
        ("up",        0xaa81),
        ("up_left",   0xaa87),
        ("left",      0xaa8d),
    ]),
    ("bullet", [
        ("chopper_bullet",  0xaa94),
        ("tank_shell",      0xaa99),
        ("jet_missile",     0xaa9e),
        ("jet_bomb",        0xaaa6),
        ("muzzle_flash",    0xaaa9),
    ]),
    ("alien", [
        ("body",     0xaaaf),
        ("mid_1",    0xaac5),
        ("mid_2",    0xaacb),
        ("mid_3",    0xaad1),
    ]),
    ("explosion", [
        ("frame_1",  0xaad7),
        ("frame_2",  0xaaf4),
        ("frame_3",  0xab17),
        ("frame_4",  0xab3d),
        ("frame_5",  0xab63),
    ]),
    ("chopper_debris", [
        ("rubble",        0xab7d),
        ("dying_hostage", 0xab87),
    ]),
    ("hostage_running", [
        ("frame_1",  0xab9f),
        ("frame_2",  0xabb7),
        ("frame_3",  0xabcf),
        ("frame_4",  0xabe7),
    ]),
    ("hostage_waving", [
        ("frame_1",  0xabff),
        ("frame_2",  0xac17),
        ("frame_3",  0xac2f),
    ]),
    ("hostage_loading", [
        ("frame_1",  0xac47),
        ("frame_2",  0xac5f),
    ]),
    ("mountain", [
        ("pattern_0",  0xac77),
        ("pattern_1",  0xad59),
        ("pattern_2",  0xae1f),
        ("pattern_3",  0xaf1d),
    ]),
    ("hud", [
        ("border",      0xb01b),
        ("corner",      0xb034),
        ("bubble",      0xb77f),
        ("bg_bubble",   0xb78f),
    ]),
    ("base", [
        ("building",       0xb04e),
        ("grass_corner",   0xb344),
        ("flagpole",       0xb350),
        ("flag_1",         0xb35e),
        ("flag_2",         0xb370),
        ("sidewalk_left",  0xb382),
        ("sidewalk_right", 0xb38a),
    ]),
    ("fence_tower", [
        ("size_4_far",   0xb392),
        ("size_3",       0xb399),
        ("size_2",       0xb3a7),
        ("size_1",       0xb3b7),
        ("size_0_near",  0xb3d4),
    ]),
    ("house", [
        ("normal",   0xb3f7),
        ("on_fire",  0xb57a),
        ("sill",     0xb6fd),
        ("debris",   0xb707),
        ("fire_1",   0xb70d),
        ("fire_2",   0xb719),
    ]),
    ("font", [
        ("digit_0",  0xb725),
        ("digit_1",  0xb72e),
        ("digit_2",  0xb737),
        ("digit_3",  0xb740),
        ("digit_4",  0xb749),
        ("digit_5",  0xb752),
        ("digit_6",  0xb75b),
        ("digit_7",  0xb764),
        ("digit_8",  0xb76d),
        ("digit_9",  0xb776),
    ]),
    ("title", [
        ("rescue_hostages",   0xb7c7),
        ("choplifter_logo",   0xb943),
        ("broderbund",        0xba70),
        ("dan_gorlin",        0xbba6),
        ("the_end",           0xbc85),
        ("crown_logo",        0xbcf0),
    ]),
    ("sortie_banner", [
        ("first",   0xbd5b),
        ("second",  0xbe02),
        ("third",   0xbeb8),
    ]),
]


# ---------------------------------------------------------------------------
# Binary loading
# ---------------------------------------------------------------------------

CHOPGFX_BASE   = 0xa102
CHOPGFXHI_BASE = 0xbef0


def load_memory(chopgfx_path: Path, chopgfxhi_path: Path) -> dict[int, int]:
    """Return a dict of address → byte value for the combined graphics ROM."""
    mem: dict[int, int] = {}

    data = chopgfx_path.read_bytes()
    for i, b in enumerate(data):
        mem[CHOPGFX_BASE + i] = b

    data = chopgfxhi_path.read_bytes()
    for i, b in enumerate(data):
        mem[CHOPGFXHI_BASE + i] = b

    return mem


# ---------------------------------------------------------------------------
# Sprite decoding
# ---------------------------------------------------------------------------

def bytes_per_row(width_px: int) -> int:
    """Choplifter sprite bitmaps store 8 pixels per byte (applyClipping: width+7 >> 3).

    NOTE: this is the SOURCE IMAGE format, not the Apple II screen format. The
    renderer converts 8-px source bytes to 7-px HGR screen bytes at blit time
    (calcRowBitByte and friends, choplifter.s:1386+)."""
    return math.ceil(width_px / 8)


def decode_sprite(mem: dict[int, int], addr: int, ntsc: bool = True) -> Image.Image:
    """
    Decode one sprite from the given memory dict starting at addr.
    Returns an RGBA PIL Image.
    """
    width  = mem.get(addr, 0)
    height = mem.get(addr + 1, 0)

    if width == 0 or height == 0:
        # Return a tiny red placeholder so bad addresses are visible
        img = Image.new("RGBA", (8, 8), (255, 0, 0, 128))
        return img

    stride = bytes_per_row(width)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = img.load()

    offset = addr + 2
    for row in range(height):
        # Source row 0 is the TOP of the sprite: the blitter walks the source image
        # forward while DECREMENTING the bottom-up screen row counter
        # (nextImageDestRow / dec ZP_RENDER_CURR_Y, choplifter.s:2070).
        bits = []
        for byte_idx in range(stride):
            b = mem.get(offset + row * stride + byte_idx, 0)
            # All 8 bits are pixels, MSB first (bit 7 = leftmost): the blitter
            # discards left-clipped pixels with ASL (choplifter.s:1836).
            for bit in range(7, -1, -1):
                bits.append((b >> bit) & 1)
        bits = bits[:width]

        # NTSC artifact colour (composite monitor look). Choplifter's renderer never
        # sets the HGR palette bit (no ORA #$80 in the blit path), so everything is
        # palette 0: adjacent on-pixels fuse to WHITE; an isolated on-pixel shows as
        # VIOLET on even columns and GREEN on odd columns. Alternating-pixel fills
        # (houses, logo text) therefore render as solid colour fields — decoding
        # them as 1-bit white produced the "checkerboard noise" seen in v0.1.
        VIOLET = (0xC6, 0x30, 0xFF, 255)
        GREEN  = (0x3D, 0xFF, 0x39, 255)
        WHITE_PX = (255, 255, 255, 255)
        for col in range(width):
            if not bits[col]:
                continue
            left_on  = col > 0 and bits[col - 1]
            right_on = col + 1 < width and bits[col + 1]
            if ntsc is False:
                pixels[col, row] = WHITE_PX                     # raw 1-bit (--no-ntsc)
                continue
            if left_on or right_on:
                pixels[col, row] = WHITE_PX                     # white burst
                continue
            # Isolated pixel: the NTSC colour cycle smears it across a 2-px band
            # (this is what turns alternating-column fills into SOLID colour fields).
            colour = VIOLET if col % 2 == 0 else GREEN
            pixels[col, row] = colour
            for n in (col - 1, col + 1):
                if 0 <= n < width and not bits[n] and pixels[n, row][3] == 0:
                    pixels[n, row] = colour

    return img


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Extract Choplifter Apple II sprites to PNG")
    parser.add_argument("--gfx",   default="CHOPGFX",   help="Path to CHOPGFX binary (default: ./CHOPGFX)")
    parser.add_argument("--gfxhi", default="CHOPGFXHI", help="Path to CHOPGFXHI binary (default: ./CHOPGFXHI)")
    parser.add_argument("--out",   default="sprites",   help="Output directory (default: ./sprites)")
    parser.add_argument("--scale", type=int, default=4, help="Integer upscale factor, 1–8 (default: 4)")
    parser.add_argument("--no-ntsc", dest="ntsc", action="store_false", default=True, help="Raw 1-bit white-on-transparent instead of NTSC composite colours (default: NTSC)")
    args = parser.parse_args()

    gfx_path   = Path(args.gfx)
    gfxhi_path = Path(args.gfxhi)

    for p in (gfx_path, gfxhi_path):
        if not p.exists():
            sys.exit(f"Error: file not found: {p}")

    out_dir = Path(args.out)
    scale   = max(1, min(8, args.scale))

    print(f"Loading {gfx_path} ({gfx_path.stat().st_size} bytes) → ${CHOPGFX_BASE:04x}")
    print(f"Loading {gfxhi_path} ({gfxhi_path.stat().st_size} bytes) → ${CHOPGFXHI_BASE:04x}")

    mem = load_memory(gfx_path, gfxhi_path)

    total_exported = 0
    total_errors   = 0

    for group, sprites in SPRITE_TABLES:
        group_dir = out_dir / group
        group_dir.mkdir(parents=True, exist_ok=True)

        for label, addr in sprites:
            w  = mem.get(addr, 0)
            h  = mem.get(addr + 1, 0)
            fn = group_dir / f"{label}.png"

            if w == 0 or h == 0:
                print(f"  WARN  ${addr:04x}  {group}/{label}  — zero dimensions, skipping")
                total_errors += 1
                continue

            try:
                img = decode_sprite(mem, addr, ntsc=args.ntsc)

                if scale > 1:
                    img = img.resize(
                        (img.width * scale, img.height * scale),
                        Image.NEAREST,
                    )

                img.save(fn)
                print(f"  OK    ${addr:04x}  {group}/{label}  {w}×{h}px  → {fn}")
                total_exported += 1
            except Exception as exc:
                print(f"  ERROR ${addr:04x}  {group}/{label}  — {exc}")
                total_errors += 1

    print()
    print(f"Done. {total_exported} sprites exported, {total_errors} warnings/errors.")
    print(f"Output: {out_dir.resolve()}")


if __name__ == "__main__":
    main()
