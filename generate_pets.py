#!/usr/bin/env python3
"""Generate the AI pets' mood GIFs through the PixelLab API.

Unlike the panda (hand-authored pixel grids in generate_gifs.py) and the 18
firmware pets (extracted from C++ in generate_species_gifs.py), these pets are
generated. That makes reproducibility the whole problem: the prompts, the
seed and the character IDs *are* the source, and if they only ever lived in a
chat window the art couldn't be regenerated. Hence this file, and the
per-species manifests it writes beside itself.

Three API calls, one per species plus two per mood:

  1. `create-character-v3` makes the base character from a text description.
     Its id is the anchor for everything after it — every mood is an edit *of
     that id* — so it lands in the manifest before anything else is spent.

  2. `create-character-state` applies a text edit to the base character and
     returns 8 rotations, of which we keep `south`. It takes the base
     character's *id*, so the model knows what it's editing — which is why
     the koala's bionic eye survives as an X inside its own metal rim.
     `inpaint-v3` costs exactly the same (20 generations, measured) and only
     sees a mask, so it painted the implant away. Don't switch to it.

  3. `animate-with-text-v3` turns that still into a loop for 1 generation.
     `last_frame` is set to the first frame, which is what makes the loop
     seamless: with it, frames 0 and N come back pixel-identical to the input
     and only the middle moves. Without it the sprite visibly degrades —
     measured as the koala's implant eroding from 90 cyan pixels down to 63.

21 generations per mood, measured exactly (a `celebrate` rebuild moved the
balance 1804 -> 1783). A CORE pet is ~169, a FULL one ~232, against the
2000/month that Tier 1 includes.

Usage:  .venv/bin/python3 generate_pets.py <species> [mood ...]
        .venv/bin/python3 generate_pets.py <species> --base-only
Needs Pillow (see .venv) and a PixelLab key in $PIXELLAB_KEY or
~/.pixellab_key. Already-generated moods are skipped unless named
explicitly, so a rerun after an interruption costs nothing.
"""

import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

API = "https://api.pixellab.ai/v2"
OUT_DIR = "Sources/ClaudeMenuBarBuddy/Resources"
SEED = 20260808

# `image_size` is the *generation* size, not the frame we get back: the API
# pads the canvas ~2x for animation room. Asking for 120 returned a 228px
# field holding a 106px sprite — pixel art at twice the koala's density,
# which would have looked like a different art style in the same menu. The
# koala was made at ~60, so 64 keeps the whole family on one pixel grid.
PIXEN = 64

# What ships. The canvas has to divide 128: FloatingPet.swift's three sizes
# are 128/192/256pt, a 2x screen turns those into 256/384/512 backing pixels,
# and 128 is their gcd — so only a canvas that divides it lands on whole
# screen pixels at every size. Both options qualify, and a pet too big for
# the small square gets the large one rather than a resample or a blur.
CANVAS_CHOICES = (64, 128)

# mood -> (edit applied to the base, motion for the loop, ms per frame)
#
# The edits describe expressions and props, never the animal, so the same
# table dresses every species. The tempo is the vocabulary the panda uses:
# brisk for the moods that mean something is happening, slow for the ones
# that mean it isn't. `idle` has no edit — it *is* the base character.
MOODS = {
    "idle":      (None,
                  "idle breathing, gentle bob, occasional slow blink", 500),
    "pending":   ("alert and attentive, eyes wide open, ears perked straight up",
                  "alert bouncing, ears twitching", 250),
    "working":   ("sitting behind a small laptop computer, paws on the keyboard, focused",
                  "typing quickly on the laptop, paws moving", 180),
    "thinking":  ("one paw raised to the chin, looking up and to the side thoughtfully",
                  "thinking, slowly tapping the chin", 450),
    "tired":     ("sleepy, heavy half-closed drooping eyelids",
                  "slow tired breathing, head drooping", 650),
    "stressed":  ("tense and anxious, a bead of sweat on the forehead, worried frown",
                  "nervous fidgeting, quick shallow breathing", 220),
    "critical":  ("exhausted, both eyes squeezed shut like X marks, mouth open panting, sweat drop",
                  "wobbling unsteadily, exhausted panting", 700),
    "asleep":    ("fast asleep, eyes closed, peaceful, small Z floating above the head",
                  "slow deep sleeping breaths", 800),
    "heart":     ("delighted, eyes shaped like pink hearts, blushing cheeks",
                  "happy little bounce", 220),
    # "both arms raised high in the air" put the arms in front of the face and
    # the model returned a grey blob with no features at all. Keeping the arms
    # beside the head, and saying outright that the face stays visible, fixes
    # it — the edit prompts steer the whole sprite, not just the part named.
    "celebrate": ("celebrating happily, paws raised beside the head, big open smile, "
                  "face fully visible, both eyes visible",
                  "jumping and cheering", 200),
    "sad":       ("crying, a single blue tear rolling down the cheek, mouth turned down",
                  "slow sad slump, sniffling", 700),
    "excited":   ("excited and amazed, star-shaped eyes, mouth open in a big grin",
                  "excited jumping up and down", 170),
}

# The nine that MoodEngine can't fake. thinking/excited/sad are omitted from
# CORE because gifName already degrades them to working/celebrate/tired, which
# read as the same thing; stressed and critical are not omitted, because they
# have no fallback and the pet would look identical at 40% and 90% of a limit.
CORE = ["idle", "pending", "working", "tired", "stressed",
        "critical", "asleep", "heart", "celebrate"]
FULL = list(MOODS)

# Each pet gets its own neon so they read apart at a glance, and the same
# sentence shape so they read as one family.
#
# Posture is stated outright even though the koala never needed it: left to
# itself the model drew the piglet on four legs in profile and the cat
# sitting down, and the mood edits assume a biped seen from the front — you
# cannot raise a quadruped's paws beside its head or sit it behind a laptop
# without the model rebuilding the whole character, which is how the koala's
# first `celebrate` came back as a faceless blob.
UPRIGHT = "standing upright on two hind legs facing the viewer, full body"
# The pig needed more than the others: "standing upright on two hind legs"
# still returned a four-legged pig in profile twice. The model's prior for
# "pig" is strong enough that it takes the word anthropomorphic to break it,
# where koala, panda and cat stand up on the milder phrasing alone.
UPRIGHT_PIG = ("anthropomorphic bipedal cartoon character, standing on two legs "
               "facing the viewer, arms at its sides, full body")
PETS = {
    "koala": (FULL, "cyberpunk koala mascot, round fluffy grey ears, big dark nose, "
                    "one glowing cyan bionic eye with a thin metal rim, small neon "
                    "circuit accents on the fur, friendly and charismatic"),
    "piglet": (CORE, f"cyberpunk piglet mascot, {UPRIGHT_PIG}, round pink snout, small "
                     "floppy ears, one glowing magenta bionic eye with a thin metal "
                     "rim, small neon circuit accents on the skin, friendly and "
                     "charismatic"),
    "panda": (CORE, f"cyberpunk panda mascot, {UPRIGHT}, round black ears, black eye "
                    "patches, fluffy fur, one glowing green bionic eye with a thin "
                    "metal rim, small neon circuit accents on the fur, friendly and "
                    "charismatic"),
    "kitty": (CORE, f"cyberpunk cat mascot, {UPRIGHT}, pointed ears, small pink nose, "
                    "fluffy fur, one glowing amber bionic eye with a thin metal rim, "
                    "small neon circuit accents on the fur, friendly and charismatic"),
}

TOKEN = None


def key():
    if os.environ.get("PIXELLAB_KEY"):
        return os.environ["PIXELLAB_KEY"].strip()
    path = os.path.expanduser("~/.pixellab_key")
    if not os.path.exists(path):
        sys.exit("No PixelLab key: set $PIXELLAB_KEY or write ~/.pixellab_key")
    with open(path) as f:
        return f.read().strip()


def post(endpoint, payload):
    req = urllib.request.Request(
        f"{API}/{endpoint}", method="POST",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {TOKEN}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{endpoint} failed ({e.code}): {e.read().decode()[:300]}")


def wait(job_id, label, timeout=900):
    """Poll a background job. These take one to three minutes."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(6)
        req = urllib.request.Request(
            f"{API}/background-jobs/{job_id}",
            headers={"Authorization": f"Bearer {TOKEN}"})
        with urllib.request.urlopen(req) as r:
            job = json.load(r)
        if job.get("status") == "completed":
            return job
        if job.get("status") == "failed":
            sys.exit(f"{label}: job failed — {json.dumps(job)[:300]}")
    sys.exit(f"{label}: timed out after {timeout}s")


def balance():
    req = urllib.request.Request(
        f"{API}/balance", headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)["subscription"]["generations"]


def manifest_path(species):
    return f"{species}_manifest.json"


def save(species, manifest):
    with open(manifest_path(species), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)


def as_b64(image):
    buf = io.BytesIO()
    image.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def decode(payload):
    raw = payload["base64"] if isinstance(payload, dict) else payload
    if raw.startswith("data:"):
        raw = raw.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(raw))).convert("RGBA")


def south_url(manifest, character_id):
    """Rotation URLs follow the account/character path, so they can be rebuilt
    from an id. Worth deriving rather than storing: a state costs 20
    generations, and losing its URL to a failed download shouldn't mean
    paying for it twice."""
    account = manifest["base_south_url"].split("/pixellab-characters/")[1].split("/")[0]
    return (f"https://backblaze.pixellab.ai/file/pixellab-characters/"
            f"{account}/{character_id}/rotations/south.png")


def download(url, path):
    # Storage rejects urllib's default User-Agent with a 403 — curl works,
    # Python doesn't, and the difference is only this header.
    request = urllib.request.Request(url, headers={"User-Agent": "claude-menubar-buddy"})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(request) as r, open(path, "wb") as f:
        f.write(r.read())


def ensure_base(species, manifest):
    """The base character. Every mood is an edit of its id, so losing it means
    the whole set has to be rebuilt from scratch and stops matching."""
    if manifest.get("base_character_id"):
        return
    _, prompt = PETS[species]
    print(f"  create-character-v3 ({species})")
    submitted = post("create-character-v3", {
        "description": prompt,
        "image_size": {"width": PIXEN, "height": PIXEN},
        "no_background": True,
        "seed": SEED,
    })
    job = wait(submitted["background_job_id"], f"{species} base")
    response = job["last_response"]
    manifest["base_character_id"] = response["character_id"]
    manifest["base_prompt"] = prompt
    manifest["base_south_url"] = response["storage_urls"]["south"]
    manifest["seed"] = SEED
    save(species, manifest)
    path = f".build/{species}/base.png"
    download(manifest["base_south_url"], path)
    print(f"  base character {response['character_id'][:8]} -> {path}")


def still_for(species, mood, edit, manifest):
    """The mood's static sprite: base for idle, an edited state otherwise.

    Resolved cheapest-first — cached file, then an already-paid-for character
    id, and only then a new generation.
    """
    cached = manifest.get("stills", {}).get(mood)
    if cached and os.path.exists(cached):
        return Image.open(cached).convert("RGBA")

    known = manifest.get("character_ids", {}).get(mood)
    if edit is None:
        url = manifest["base_south_url"]
    elif known:
        print(f"  reusing state {known[:8]} — no charge")
        url = south_url(manifest, known)
    else:
        print(f"  create-character-state ({mood}) — 20 generations")
        submitted = post("create-character-state", {
            "character_id": manifest["base_character_id"],
            "edit_description": edit,
            "no_background": True,
            "use_color_palette_from_reference": True,
            "seed": SEED,
            "state_name": mood,
        })
        job = wait(submitted["background_job_id"], mood)
        response = job["last_response"]
        # Recorded before the download, so a network failure here can't turn
        # into a second 20-generation charge on the next run.
        manifest.setdefault("character_ids", {})[mood] = response["character_id"]
        save(species, manifest)
        url = response["storage_urls"]["south"]

    path = f".build/{species}/{mood}.png"
    download(url, path)
    manifest.setdefault("stills", {})[mood] = path
    return Image.open(path).convert("RGBA")


def animate(still, action):
    """A seamless loop. `last_frame` is the whole trick — see the module docstring."""
    frame = {"base64": as_b64(still)}
    submitted = post("animate-with-text-v3", {
        "first_frame": frame,
        "last_frame": frame,
        "action": action,
        "frame_count": 4,
        "no_background": True,
        "drift_threshold": 0.0,
        "seed": SEED,
    })
    job = wait(submitted["background_job_id"], action)
    return [decode(image) for image in job["last_response"]["images"]]


def union_box(frames_by_mood):
    """Smallest box containing every non-transparent pixel of every frame."""
    boxes = [frame.getchannel("A").getbbox()
             for frames in frames_by_mood.values() for frame in frames]
    boxes = [b for b in boxes if b]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def derive_crop(union, field):
    """A square box centred on the sprite, clamped inside the `field` canvas.

    Computed rather than hardcoded because each character sits differently on
    PixelLab's field — the koala's union was 53x62 at (34,30), and a box that
    fits one pet will clip another.
    """
    width, height = union[2] - union[0], union[3] - union[1]
    target = next((c for c in sorted(CANVAS_CHOICES)
                   if c >= width and c >= height and c <= field), None)
    if target is None:
        sys.exit(f"sprite is {width}x{height} on a {field}px field, and no canvas in "
                 f"{CANVAS_CHOICES} holds it. Regenerate at a smaller PIXEN, or add a "
                 f"larger canvas that still divides 128 — anything else falls off the "
                 f"whole-pixel ladder the pet sizes in FloatingPet.swift depend on.")
    left = min(max((union[0] + union[2]) // 2 - target // 2, 0), field - target)
    top = min(max((union[1] + union[3]) // 2 - target // 2, 0), field - target)
    return (left, top, left + target, top + target)


def crop_frames(frames, crop, label):
    """Trim the padding, refusing to clip the pet.

    A beheaded pet is a worse outcome than a small one, and it would be
    invisible in a 4-frame loop until someone happened to look at the right
    beat — so the box is verified against each frame instead of assumed.
    """
    for i, frame in enumerate(frames):
        box = frame.getchannel("A").getbbox()
        if box and not (box[0] >= crop[0] and box[1] >= crop[1]
                        and box[2] <= crop[2] and box[3] <= crop[3]):
            sys.exit(f"{label}[{i}]: sprite {box} escapes crop {crop}. Delete the "
                     f"manifest's crop to recompute it over every mood, rather "
                     f"than shipping a clipped pet.")
    return [frame.crop(crop) for frame in frames]


def frames_for(species, mood, manifest):
    edit, action, _ = MOODS[mood]
    print(f"{mood}:")
    still = still_for(species, mood, edit, manifest)
    print("  animate-with-text-v3 — 1 generation")
    frames = animate(still, action)
    # The loop already closes on itself, so the repeated final frame would
    # only make the pet hang for an extra beat on the pose it just held.
    if len(frames) > 1 and frames[0].tobytes() == frames[-1].tobytes():
        frames = frames[:-1]
    return frames


def write_gif(species, mood, frames):
    path = f"{OUT_DIR}/{species}_{mood}.gif"
    duration = MOODS[mood][2]
    frames[0].save(path, save_all=True, append_images=frames[1:],
                   duration=[duration] * len(frames), loop=0, disposal=2)
    print(f"  wrote {path} — {len(frames)} frames, {frames[0].size[0]}px")


def main():
    global TOKEN
    if len(sys.argv) < 2 or sys.argv[1] not in PETS:
        sys.exit(f"Usage: generate_pets.py <{'|'.join(PETS)}> [mood ...] [--base-only]")
    species = sys.argv[1]
    args = sys.argv[2:]
    base_only = "--base-only" in args
    named = [a for a in args if not a.startswith("--")]
    moods, _ = PETS[species]
    unknown = [m for m in named if m not in moods]
    if unknown:
        sys.exit(f"{species} has no mood(s): {', '.join(unknown)}")

    TOKEN = key()
    manifest = {}
    if os.path.exists(manifest_path(species)):
        with open(manifest_path(species)) as f:
            manifest = json.load(f)

    print(f"{balance():.0f} generations available\n")
    ensure_base(species, manifest)
    if base_only:
        save(species, manifest)
        print(f"\nBase only. Look at .build/{species}/base.png before spending "
              f"{(len(moods) - 1) * 20 + len(moods)} more on moods.")
        return

    # Explicitly named moods are always rebuilt; a bare run only fills gaps,
    # so an interrupted set can be resumed without paying twice.
    requested = named or [m for m in moods
                          if not os.path.exists(f"{OUT_DIR}/{species}_{m}.gif")]
    print(f"building {len(requested)} mood(s) for {species}\n")

    built = {}
    try:
        for mood in requested:
            built[mood] = frames_for(species, mood, manifest)
    finally:
        save(species, manifest)

    # The crop is computed once, over every mood at once, and then frozen in
    # the manifest — a box derived from a single-mood rerun would sit
    # somewhere else and the pet would jump between moods.
    crop = manifest.get("crop")
    if crop is None:
        missing = [m for m in moods if m not in built]
        if missing:
            sys.exit(f"Need every mood in one run to place the crop box; missing "
                     f"{', '.join(missing)}. Run without naming moods.")
        field = next(iter(built.values()))[0].size[0]
        crop = derive_crop(union_box(built), field)
        manifest["crop"] = list(crop)
        save(species, manifest)
        print(f"\ncrop box {crop} (from the union across all moods)")
    for mood, frames in built.items():
        write_gif(species, mood, crop_frames(frames, tuple(crop), f"{species}_{mood}"))

    print(f"\n{balance():.0f} generations left. Manifest: {manifest_path(species)}")


if __name__ == "__main__":
    main()
