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
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWWWW..WWWWWW.",
    ".WWWKKW..WKKWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
SHUT = [  # eyes fully shut, still upright
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWWWW..WWWWWW.",
    ".WWWWWW..WWWWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWWWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
ASLEEP = SHUT  # Zzz + no bounce is what sells "asleep" (added at render time)

# 70% of the 5-hour limit. Eyes braced wide, jaw clenched, and a bead of
# sweat running down the temple — the tell that separates this from pending,
# which wears the same wide eyes but none of the strain.
STRESSED_A = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWWT.", ".WWKKKW..WKKKWW.",
    ".WWKKKW..WKKKWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWKKKKWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
STRESSED_B = [  # the bead has slid down past the cheek
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWKKKW..WKKKWWT",
    ".WWKKKW..WKKKWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWKKKKWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
# 85%. X'd-out eyes — borrowing the firmware's own vocabulary for a pet that
# has had enough, since doDizzy draws x eyes too — over a mouth open two rows
# deep. Stressed clenches a flat line; this one is panting.
CRITICAL = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WKWKWWWWKWKW..", ".WWWKWW..WWKWWW.",
    ".WWKWKW..WKWKWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWKKKKWWWW.",
    "..WWWWWKKKKWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]

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

# Thinking: a turn is in flight but no tool is running — Claude itself is
# what we're waiting on. Paw up at the chin, eyes rolled up in thought.
THINKING = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WKKWWW..KKWWWW.",
    ".WWWWWW..WWWWWW.", ".WBWWWWWKKWWWBW.", ".WWWWWWWWWKKKWW.",
    "..WWWWWWWWKKKW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", "KWWWW......WWWWK", "KKWWW......WWWKK",
    "..KK........KK..",
]
# Sad: a request just got denied. Downcast eyes, a tear, corners of the
# mouth turned down — three seconds of visible disappointment, then back
# to whatever the real mood is.
SAD = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWWWWW..WWWWWW.",
    ".WWWWKW..WKWWWW.", ".WBWTWWWKKWWWBW.", ".WWWWWWKWWKWWWW.",
    "..WWWWWWWWWWWW..", "..WWWWWWWWWWWW..", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", ".WWWW......WWWW.", "KKWWW......WWWKK",
    "..KK........KK..",
]
# Excited: a session the buddy hasn't met yet just started talking. Star
# eyes, open mouth, arms up. Deliberately louder than celebrate — this one
# is a greeting, not a sigh of relief.
EXCITED = [
    "...KK......KK...", "..KKKK....KKKK..", "..KKKK....KKKK..",
    "...WWWWWWWWWW...", "..WWWWWWWWWWWW..", ".WWYYYW..WYYYWW.",
    ".WWYKYW..WYKYWW.", ".WBWWWWKKKKWWBW.", ".WWWWWWWWWWWWWW.",
    "K.WWWWWWWWWWWW.K", "KK.WWWWWWWWWW.KK", ".WWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWW.", ".WWWW......WWWW.", "KKWWW......WWWKK",
    "..KK........KK..",
]

COLORS = {"K": (132, 136, 140, 255), "W": (255, 255, 255, 255),
          "P": (255, 77, 148, 255), "B": (255, 170, 190, 140),
          "G": (95, 100, 108, 255),
          "T": (120, 190, 255, 255),   # tear
          "Y": (255, 210, 80, 255),    # star-struck eyes
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

# The 5-hour-limit ladder: tired (50%, half-lidded, still bounces a little),
# stressed (70%, braced and sweating, quick anxious jitter), critical (85%,
# x-eyed and slumping), asleep (100%, eyes shut, no bounce, Zzz drifting up).
tired_frames = [render(TIRED, 0), render(TIRED, -1)]
save_gif(tired_frames, [600, 600], "Sources/ClaudeMenuBarBuddy/Resources/buddy_tired.gif")

# Quick and shallow — the jitter is what reads as tension, not the sweat.
stressed_frames = [render(STRESSED_A, 0), render(STRESSED_A, -1),
                   render(STRESSED_B, 0), render(STRESSED_B, -1)]
save_gif(stressed_frames, [200, 200, 200, 200], "Sources/ClaudeMenuBarBuddy/Resources/buddy_stressed.gif")

# Slow and heavy, sagging a pixel further each beat before catching itself.
critical_frames = [render(CRITICAL, 0), render(CRITICAL, 1),
                   render(CRITICAL, 2), render(CRITICAL, 1)]
save_gif(critical_frames, [700, 700, 700, 700], "Sources/ClaudeMenuBarBuddy/Resources/buddy_critical.gif")

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

# Thinking: unhurried — thought dots accumulate above the head, and the
# slow cadence is the whole point next to working's brisk typing.
THINK = (200, 210, 230, 235)
w2 = max(len(r) for r in THINKING) * PPX
thinking_frames = [
    render(THINKING, 0, marks=[(".", w2 - 44, 2, THINK)]),
    render(THINKING, 0, marks=[("..", w2 - 44, 2, THINK)]),
    render(THINKING, -1, marks=[("...", w2 - 44, 2, THINK)]),
    render(THINKING, 0, marks=[("...", w2 - 44, 2, THINK)]),
]
save_gif(thinking_frames, [450, 450, 450, 450], "Sources/ClaudeMenuBarBuddy/Resources/buddy_thinking.gif")

# Sad: denied. A slow, small slump — no bounce back up.
sad_frames = [render(SAD, 0), render(SAD, 1)]
save_gif(sad_frames, [700, 700], "Sources/ClaudeMenuBarBuddy/Resources/buddy_sad.gif")

# Excited: new session — a proper jump, with "!" popping on either side.
BANG = (255, 210, 80, 255)
w3 = max(len(r) for r in EXCITED) * PPX
excited_frames = [
    render(EXCITED, 0, marks=[("!", 6, 8, BANG), ("!", w3 - 18, 8, BANG)]),
    render(EXCITED, -5, marks=[("!", 2, 0, BANG), ("!", w3 - 14, 0, BANG)]),
    render(EXCITED, 0, marks=[("!", 6, 8, BANG), ("!", w3 - 18, 8, BANG)]),
    render(EXCITED, -5, marks=[("!", 2, 0, BANG), ("!", w3 - 14, 0, BANG)]),
]
save_gif(excited_frames, [160, 160, 160, 160], "Sources/ClaudeMenuBarBuddy/Resources/buddy_excited.gif")

print("Wrote buddy_idle/pending/tired/stressed/critical/asleep/heart/celebrate"
      "/working/thinking/sad/excited.gif")
