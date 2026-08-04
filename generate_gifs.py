#!/usr/bin/env python3
"""Generate animated panda GIFs for Claude Menu Bar Buddy from the same
pixel-art grids used in the M5StickC Plus2 firmware (src/buddies/panda.cpp)."""

from PIL import Image, ImageDraw, ImageFont

PPX = 10  # pixels per art-cell — bumped up from 8 (2026-07-12, for the
          # floating always-on-top pet) for a crisper look at a size that's
          # now also rendered outside a menu dropdown, standalone on the
          # desktop where it needs to hold up next to Codex's pets

BASE = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWKKW..WKKWWW.",
    ".WWWKKW..WKKWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
BLINK = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWKKW..WKKWWW.",
    ".WWWWWW..WWWWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
WIDE = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWKKKW..WKKKWW.",
    ".WWKKKW..WKKKWW.", ".WWKKKW..WKKKWW.", ".WBWWWWWKKWWWBW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
# 5-hour-limit mood states: same body, progressively more-closed eyes.
TIRED = [  # half-lidded — top of eye droops shut, pupil still peeking below
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWWWWW..WWWWWW.",
    ".WWWKKW..WKKWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
SLEEPY = [  # eyes fully shut, still upright
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWWWWW..WWWWWW.",
    ".WWWWWWW..WWWWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
ASLEEP = SLEEPY  # same face; Zzz + no bounce is what sells "asleep" (added at render time)

HEART = [  # clicked/petted — pink heart-shaped eyes
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWPPW..WPPWWW.",
    ".WWWPPW..WPPWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
CELEBRATE = [  # 5-hour limit just reset — arms-up, wide happy eyes
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWKKKW..WKKKWW.",
    ".WWKKKW..WKKKWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "K.WWWWWWWWWWWW.K", "KK.WWWWWWWWWW.KK", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]

# Working: Claude is actively running in some session — panda at a little
# gray laptop, paws alternating over the keyboard row.
WORK_A = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWKKW..WKKWWW.",
    ".WWWKKW..WKKWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWGGGGGGWWWW.", "KWWWWGGGGGGWWWWK", "KKWWWKGGGGKWWWKK",
    "..KK........KK..",
]
WORK_B = [  # same pose, paws shifted a key inward — the typing wiggle
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWKKW..WKKWWW.",
    ".WWWKKW..WKKWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWGGGGGGWWWW.", "KWWWWGGGGGGWWWWK", "KKWWWGKGGKGWWWKK",
    "..KK........KK..",
]

COLORS = {"K": (132, 136, 140, 255), "W": (255, 255, 255, 255),
          "P": (255, 77, 148, 255), "B": (255, 170, 190, 140),
          "G": (95, 100, 108, 255),
          ".": (0, 0, 0, 0)}


def render(grid, yoff=0, marks=None):
    """marks: list of (glyph, x, y, color) drawn in headroom above the
    sprite — used for the drifting "Z" (asleep) and celebrate sparkles."""
    w = max(len(r) for r in grid) * PPX
    h = len(grid) * PPX
    pad_top = 24 if marks else 0
    img = Image.new("RGBA", (w, h + pad_top), (0, 0, 0, 0))
    px = img.load()
    for r, row in enumerate(grid):
        for c, ch in enumerate(row):
            color = COLORS.get(ch, (0, 0, 0, 0))
            if color[3] == 0:
                continue
            y0 = r * PPX + yoff + pad_top
            for dy in range(PPX):
                yy = y0 + dy
                if yy < 0 or yy >= h + pad_top:
                    continue
                for dx in range(PPX):
                    px[c * PPX + dx, yy] = color
    if marks:
        d = ImageDraw.Draw(img)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 16)
        except Exception:
            font = ImageFont.load_default()
        for glyph, x, y, color in marks:
            d.text((x, y), glyph, font=font, fill=color)
    return img


def save_gif(frames, durations, path):
    frames[0].save(path, save_all=True, append_images=frames[1:],
                    duration=durations, loop=0, disposal=2)


# Idle: blink cycle
idle_frames = [render(BASE), render(BASE), render(BASE), render(BLINK), render(BASE), render(BASE)]
save_gif(idle_frames, [500, 500, 500, 150, 500, 500], "Sources/ClaudeMenuBarBuddy/Resources/buddy_idle.gif")

# Pending/attention: wide eyes + little bounce
pend_frames = [render(WIDE, 0), render(WIDE, -2), render(WIDE, 0), render(WIDE, -2)]
save_gif(pend_frames, [250, 250, 250, 250], "Sources/ClaudeMenuBarBuddy/Resources/buddy_pending.gif")

# 5-hour-limit moods: tired (half-lidded, still bounces a little), sleepy
# (eyes shut, slower bounce), asleep (eyes shut, no bounce, Zzz drifting up).
tired_frames = [render(TIRED, 0), render(TIRED, -1)]
save_gif(tired_frames, [600, 600], "Sources/ClaudeMenuBarBuddy/Resources/buddy_tired.gif")

sleepy_frames = [render(SLEEPY, 0), render(SLEEPY, -1)]
save_gif(sleepy_frames, [900, 900], "Sources/ClaudeMenuBarBuddy/Resources/buddy_sleepy.gif")

ZZZ = (180, 200, 255, 230)
w0 = max(len(r) for r in ASLEEP) * PPX
asleep_frames = [
    render(ASLEEP, 0, marks=[("Z", w0 - 34, 8, ZZZ)]),
    render(ASLEEP, 0, marks=[("Z", w0 - 31, 2, ZZZ)]),
    render(ASLEEP, 0, marks=[("Z", w0 - 28, -4, ZZZ)]),
]
save_gif(asleep_frames, [500, 500, 500], "Sources/ClaudeMenuBarBuddy/Resources/buddy_asleep.gif")

# Heart: clicked/petted — pink heart eyes, tiny happy bounce
heart_frames = [render(HEART, 0), render(HEART, -2)]
save_gif(heart_frames, [200, 200], "Sources/ClaudeMenuBarBuddy/Resources/buddy_heart.gif")

# Celebrate: 5-hour limit just reset — arms up + sparkles drifting past
SPARK = (255, 210, 80, 255)
w1 = max(len(r) for r in CELEBRATE) * PPX
celebrate_frames = [
    render(CELEBRATE, 0, marks=[("*", 4, 6, SPARK), ("*", w1 - 20, 10, SPARK)]),
    render(CELEBRATE, -3, marks=[("*", 10, -2, SPARK), ("*", w1 - 26, 0, SPARK)]),
    render(CELEBRATE, 0, marks=[("*", 4, 6, SPARK), ("*", w1 - 20, 10, SPARK)]),
    render(CELEBRATE, -3, marks=[("*", 10, -2, SPARK), ("*", w1 - 26, 0, SPARK)]),
]
save_gif(celebrate_frames, [200, 200, 200, 200], "Sources/ClaudeMenuBarBuddy/Resources/buddy_celebrate.gif")

# Working: brisk typing loop, no body bounce — heads-down concentration,
# clearly distinct from idle's slow blink at a glance.
working_frames = [render(WORK_A), render(WORK_B), render(WORK_A), render(WORK_B)]
save_gif(working_frames, [170, 170, 170, 170], "Sources/ClaudeMenuBarBuddy/Resources/buddy_working.gif")

print("Wrote buddy_idle/pending/tired/sleepy/asleep/heart/celebrate/working.gif")
