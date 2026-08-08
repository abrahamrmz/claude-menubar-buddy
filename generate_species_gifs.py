#!/usr/bin/env python3
"""Render the M5StickC Plus2 Buddy species as animated GIFs for the menu bar app.

The firmware (claude-desktop-buddy/src/buddies/*.cpp) draws each pet as ASCII
sprites on a 6x8 character grid. Every pose function has the same shape:

    static const char* const REST[5] = { "...", ... };   // named sprites
    const char* const* P[10] = { REST, LOOK_L, ... };     // pose table
    static const uint8_t SEQ[] = { 0,0,0,3,0,1, ... };    // choreography
    static const int8_t Y_BOB[] = { 0,-1,0,-1, ... };     // per-beat offset
    uint8_t beat = (t / 5) % sizeof(SEQ);
    buddyPrintSprite(P[SEQ[beat]], 5, Y_BOB[beat], 0xC2A6);

so the animation is fully recoverable: walk SEQ, look each index up in P, and
hold each frame for `divisor * TICK_MS`. That is what this script does — the
pets move here exactly the way they move on the hardware, at the same tempo,
rather than being frozen on their first sprite.
"""

import os
import re
import glob
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

OUT_DIR = "Sources/ClaudeMenuBarBuddy/Resources"
FIRMWARE_REPO = "https://github.com/anthropics/claude-desktop-buddy.git"
# Cloned under .build/ (already gitignored) so a re-run on a fresh checkout
# just works. The previous hard-coded ~/Downloads path rotted the moment that
# folder was cleaned out, which is how axolotl went missing for a month.
DEFAULT_CHECKOUT = ".build/firmware"

TICK_MS = 200          # buddy.cpp: animations advance at 5 fps
FW_CHAR_W, FW_CHAR_H = 6, 8    # buddy.cpp: BUDDY_CHAR_W / BUDDY_CHAR_H

FONT_SIZE = 14
CHAR_W, CHAR_H = 9, 16  # monospace cell size at this font size
XSCALE, YSCALE = CHAR_W / FW_CHAR_W, CHAR_H / FW_CHAR_H

try:
    FONT = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", FONT_SIZE)
except Exception:
    FONT = ImageFont.load_default()

# Which firmware pose backs each mood, and how fast to play it. The firmware
# only ever drew seven poses, so the limit ladder borrows tempo as a second
# axis — which is what the firmware itself does (doCelebrate runs at t/3 while
# the calm poses run at t/5). Slower than idle reads as tired; faster than
# working reads as frantic.
MOODS = {
    "idle":      ("doIdle",      1.0),
    "pending":   ("doAttention", 1.0),
    "working":   ("doBusy",      1.0),
    "tired":     ("doIdle",      1.7),   # same pet, drowsier
    "stressed":  ("doBusy",      0.6),   # knocking-things-off-the-table energy
    "critical":  ("doDizzy",     1.0),   # x-eyes, woozy, about to fall over
    "asleep":    ("doSleep",     1.0),
    "heart":     ("doHeart",     1.0),
    "celebrate": ("doCelebrate", 1.0),
}


def resolve_src_dir():
    """Find the firmware sources, cloning them on demand."""
    override = os.environ.get("BUDDY_FIRMWARE_SRC")
    if override:
        path = os.path.expanduser(override)
        if not os.path.isdir(path):
            sys.exit(f"BUDDY_FIRMWARE_SRC={path} is not a directory")
        # Accept either the repo root or the buddies folder itself.
        nested = os.path.join(path, "src", "buddies")
        return nested if os.path.isdir(nested) else path

    buddies = os.path.join(DEFAULT_CHECKOUT, "src", "buddies")
    if os.path.isdir(buddies):
        return buddies
    if not shutil.which("git"):
        sys.exit("git not found; set BUDDY_FIRMWARE_SRC to a local checkout")
    print(f"cloning {FIRMWARE_REPO} into {DEFAULT_CHECKOUT} ...")
    os.makedirs(os.path.dirname(DEFAULT_CHECKOUT) or ".", exist_ok=True)
    subprocess.run(["git", "clone", "--depth", "1", FIRMWARE_REPO,
                    DEFAULT_CHECKOUT], check=True)
    if not os.path.isdir(buddies):
        sys.exit(f"cloned, but {buddies} is missing")
    return buddies


def function_body(src, func_name):
    """Return the body of `static void <func_name>(...) { ... }`.

    Brace counting has to skip string and char literals: several species draw
    braces as art (axolotl's gills are `"}}~(______)~{{"`), and a naive depth
    counter ends the function early on them — which is exactly why axolotl
    silently produced no GIFs at all until this was fixed.
    """
    m = re.search(rf"static void {func_name}\([^)]*\)\s*{{", src)
    if not m:
        return None
    i, depth, n = m.end(), 1, len(src)
    while i < n and depth:
        c = src[i]
        if c == "\\":
            i += 2
            continue
        if c in "\"'":
            quote, i = c, i + 1
            while i < n and src[i] != quote:
                i += 2 if src[i] == "\\" else 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[m.end():i]


def split_args(text):
    """Split a call's argument list on top-level commas."""
    args, depth, cur = [], 0, ""
    for c in text:
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        if c == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
    if cur.strip():
        args.append(cur.strip())
    return args


def parse_ints(text):
    return [int(x, 0) for x in re.findall(r"-?\d+", text)]


def parse_pose(body):
    """Recover (frames, beat_ms) from a pose function body.

    frames is a list of (lines, dx, dy) in firmware pixels.
    """
    # Match the literal list itself rather than "everything up to the closing
    # brace" — chonk's CALC_B draws a mouth as `" (   ;;   ) "`, and any
    # pattern that treats `;` or `}` as a terminator loses that sprite.
    sprites = {
        name: [s.replace('\\\\', '\\').replace('\\"', '"')
               for s in re.findall(r"\"((?:[^\"\\]|\\.)*)\"", block)]
        for name, block in
        re.findall(r"const char\* const (\w+)\[\d+\]\s*=\s*"
                   r"\{((?:\s*\"(?:[^\"\\]|\\.)*\"\s*,?)+)\}", body)
    }
    ptr = re.search(r"const char\* const\* (\w+)\[\d+\]\s*=\s*\{([^}]*)\}", body)
    beat = re.search(r"\(\s*t\s*/\s*(\d+)\s*\)\s*%\s*sizeof\(\s*(\w+)\s*\)", body)
    if not sprites or not ptr or not beat:
        return None

    divisor, seq_name = int(beat.group(1)), beat.group(2)
    seq_m = re.search(rf"const uint8_t {seq_name}\[\]\s*=\s*\{{([^}}]*)\}}", body)
    if not seq_m:
        return None
    seq = parse_ints(seq_m.group(1))

    table = [n.strip() for n in ptr.group(2).split(",") if n.strip()]
    if any(n not in sprites for n in table) or max(seq) >= len(table):
        return None

    # Per-beat offsets come from the buddyPrintSprite call, not from "any
    # int8_t array in scope" — doDizzy also declares OX/OY for its orbiting
    # sparkles, which are indexed by t % 8 and belong to the overlay.
    call = re.search(r"buddyPrintSprite\s*\(([^;]*)\)\s*;", body)
    offsets = {}
    if call:
        args = split_args(call.group(1))
        for slot, idx in (("dy", 2), ("dx", 4)):
            if idx >= len(args):
                continue
            ref = re.fullmatch(r"(\w+)\[\s*beat\s*\]", args[idx])
            if ref:
                arr = re.search(
                    rf"const int8_t {ref.group(1)}\[\]\s*=\s*\{{([^}}]*)\}}", body)
                if arr:
                    vals = parse_ints(arr.group(1))
                    if len(vals) == len(seq):
                        offsets[slot] = vals

    dxs, dys = offsets.get("dx"), offsets.get("dy")
    frames = [(sprites[table[p]],
               dxs[i] if dxs else 0,
               dys[i] if dys else 0)
              for i, p in enumerate(seq)]
    return frames, divisor * TICK_MS


def rgb565(value):
    r = (value >> 11) & 0x1F
    g = (value >> 5) & 0x3F
    b = value & 0x1F
    return (round(r * 255 / 31), round(g * 255 / 63), round(b * 255 / 31), 255)


def legible(color):
    """Keep achromatic pets visible outside the firmware's black screen.

    The species colours are picked for a 240x135 TFT that is always black, so
    ghost, goose, rabbit and robot are drawn in pure white. Both of our
    surfaces are transparent — the floating pet sits on the wallpaper, the
    menu pet on a background that follows the system appearance — and white
    on a light menu is nothing at all. Pull greys down until they read on
    white; colours with a hue of their own already carry contrast and are
    left exactly as the firmware chose them.
    """
    r, g, b, a = color
    if max(r, g, b) - min(r, g, b) > 60:
        return color
    cap = 168
    peak = max(r, g, b)
    if peak <= cap:
        return color
    k = cap / peak
    return (round(r * k), round(g * k), round(b * k), a)


def species_color(src):
    """The colour each species passes to buddyPrintSprite, as RGBA."""
    hits = re.findall(r"buddyPrintSprite\s*\([^;]*?(0x[0-9A-Fa-f]{4})", src)
    if not hits:
        return legible((255, 255, 255, 255))
    return legible(rgb565(int(max(set(hits), key=hits.count), 16)))


def render_sequence(frames, color):
    """Rasterise frames onto one shared canvas.

    buddyPrintLine centres every line on its own — including its padding
    spaces — so a wider line sticks out on both sides. Reproduce that, or
    axolotl's gills and cat's crouch land in the wrong place.
    """
    pad_x = max(abs(dx) for _, dx, _ in frames) * XSCALE
    pad_y = max(abs(dy) for _, _, dy in frames) * YSCALE
    rows = max(len(lines) for lines, _, _ in frames)
    art_w = max(len(l) for lines, _, _ in frames for l in lines) * CHAR_W

    w = int(art_w + 2 * pad_x)
    h = int(rows * CHAR_H + 2 * pad_y)
    imgs = []
    for lines, dx, dy in frames:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        for r, line in enumerate(lines):
            x = w / 2 - len(line) * CHAR_W / 2 + dx * XSCALE
            y = pad_y + r * CHAR_H + dy * YSCALE
            d.text((x, y), line, font=FONT, fill=color)
        imgs.append(img)
    return imgs


def collapse(imgs, durations):
    """Merge runs of identical frames, including across the loop seam.

    SEQ repeats poses to hold them (`0,0,0,3,0,...`); emitting each repeat as
    its own GIF frame would trip the decoder that many times a second for no
    visible change.
    """
    out_imgs, out_durs = [], []
    for img, dur in zip(imgs, durations):
        if out_imgs and img.tobytes() == out_imgs[-1].tobytes():
            out_durs[-1] += dur
        else:
            out_imgs.append(img)
            out_durs.append(dur)
    if len(out_imgs) > 1 and out_imgs[0].tobytes() == out_imgs[-1].tobytes():
        out_durs[0] += out_durs.pop()
        out_imgs.pop()
    return out_imgs, out_durs


def render_species(path):
    name = os.path.splitext(os.path.basename(path))[0]
    with open(path) as f:
        src = f.read()
    color = species_color(src)

    poses, missing = {}, []
    for fn in sorted({fn for fn, _ in MOODS.values()}):
        body = function_body(src, fn)
        parsed = parse_pose(body) if body else None
        if parsed:
            poses[fn] = parsed
        else:
            missing.append(fn)
    if missing:
        print(f"skip {name}: could not parse {', '.join(missing)}")
        return None

    total = 0
    for mood, (fn, speed) in MOODS.items():
        frames, beat_ms = poses[fn]
        imgs = render_sequence(frames, color)
        imgs, durs = collapse(imgs, [round(beat_ms * speed)] * len(imgs))
        imgs[0].save(f"{OUT_DIR}/{name}_{mood}.gif", save_all=True,
                     append_images=imgs[1:], duration=durs, loop=0, disposal=2)
        total += len(imgs)

    print(f"ok {name:9s} rgb{color[:3]}  {total} frames across {len(MOODS)} moods")
    return name


def prune_stale(names):
    """Drop GIFs from moods this script no longer emits (e.g. the old
    `sleepy` band, which `critical` replaced). The hand-drawn panda is
    generated by generate_gifs.py and is never touched here."""
    keep = {f"{n}_{m}" for n in names for m in MOODS}
    for path in glob.glob(f"{OUT_DIR}/*.gif"):
        stem = os.path.splitext(os.path.basename(path))[0]
        if stem.startswith("buddy_") or stem in keep:
            continue
        if stem.split("_")[0] in names:
            os.remove(path)
            print(f"pruned stale {os.path.basename(path)}")


if __name__ == "__main__":
    src_dir = resolve_src_dir()
    print(f"firmware: {src_dir}\n")
    os.makedirs(OUT_DIR, exist_ok=True)
    names = []
    for path in sorted(glob.glob(f"{src_dir}/*.cpp")):
        n = render_species(path)
        if n:
            names.append(n)
    prune_stale(names)
    # Pets that don't come from the firmware: the hand-drawn panda
    # (generate_gifs.py) and anything generated (generate_koala_gifs.py).
    # Discovered by looking for an idle GIF rather than listed by name, so a
    # new pet doesn't silently vanish from the picker the next time this
    # script runs — which is exactly how it would have happened.
    extras = sorted(
        os.path.basename(path)[: -len("_idle.gif")]
        for path in glob.glob(f"{OUT_DIR}/*_idle.gif")
        if os.path.basename(path)[: -len("_idle.gif")] not in names)
    names += extras
    with open(f"{OUT_DIR}/species.txt", "w") as f:
        f.write("\n".join(names))
    print(f"\n{len(names)} species available:", ", ".join(names))
