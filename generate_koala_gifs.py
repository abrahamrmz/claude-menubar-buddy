#!/usr/bin/env python3
"""Generate the cyberpunk koala's mood GIFs through the PixelLab API.

Unlike the panda (hand-authored pixel grids in generate_gifs.py) and the 18
firmware pets (extracted from C++ in generate_species_gifs.py), this pet is
generated. That makes reproducibility the whole problem: the prompts, the
seed and the character IDs *are* the source, and if they only ever lived in a
chat window the art couldn't be regenerated. Hence this file, and the
manifest it writes beside itself.

Two API calls per mood:

  1. `create-character-state` applies a text edit to the base character and
     returns 8 rotations, of which we keep `south`. It takes the base
     character's *id*, so the model knows what it's editing — which is why
     the bionic eye survives as an X inside its own metal rim. `inpaint-v3`
     costs exactly the same (20 generations, measured) and only sees a mask,
     so it painted the implant away. Don't switch to it.

  2. `animate-with-text-v3` turns that still into a loop for 1 generation.
     `last_frame` is set to the first frame, which is what makes the loop
     seamless: with it, frames 0 and N come back pixel-identical to the input
     and only the middle moves. Without it the sprite visibly degrades —
     measured as the implant eroding from 90 cyan pixels down to 63.

Roughly 21 generations per mood, ~250 for the full set, against the 2000/month
that Tier 1 includes.

Usage:  python3 generate_koala_gifs.py [mood ...]
Needs a PixelLab key in $PIXELLAB_KEY or ~/.pixellab_key. Already-generated
moods are skipped unless named explicitly, so a rerun after an interruption
costs nothing.
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
MANIFEST = "koala_manifest.json"
SPECIES = "koala"
SEED = 20260808

# The base character, generated once with create-character-v3. Kept here
# rather than regenerated because every mood is an edit *of this id* — losing
# it means the whole set has to be rebuilt from scratch and stops matching.
BASE_CHARACTER_ID = "bfcf4185-dce5-4bc4-9701-a5824b1e165e"
BASE_PROMPT = (
    "cyberpunk koala mascot, round fluffy grey ears, big dark nose, one glowing "
    "cyan bionic eye with a thin metal rim, small neon circuit accents on the fur, "
    "friendly and charismatic"
)

# mood -> (edit applied to the base, motion for the loop, ms per frame)
#
# The tempo is the same vocabulary the panda uses: brisk for the moods that
# mean something is happening, slow for the ones that mean it isn't. `idle`
# has no edit — it *is* the base character.
# PixelLab returns a 120x120 canvas with the character small and centred: the
# union of every frame of every mood is only 53x62, so 57% of the image is
# transparent padding. Every other pet fills its own canvas (the panda 100%,
# the firmware pets 75-100%), which meant the koala drew at less than half
# their size for the same window — scaling the padding, not the pet.
#
# Cropping to 64x64 puts it at 83% like the rest. 64 specifically because the
# app's three pet sizes are 128/192/256pt and a 2x screen then lands on
# exactly 4, 6 and 8 screen pixels per source pixel; pixel art shows a
# fractional scale immediately. Box is top-left origin, PIL's convention, and
# it is checked against every frame rather than trusted — see crop_frames.
CROP = (28, 29, 92, 93)

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


def key():
    if os.environ.get("PIXELLAB_KEY"):
        return os.environ["PIXELLAB_KEY"].strip()
    path = os.path.expanduser("~/.pixellab_key")
    if not os.path.exists(path):
        sys.exit("No PixelLab key: set $PIXELLAB_KEY or write ~/.pixellab_key")
    with open(path) as f:
        return f.read().strip()


TOKEN = None


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


def save(manifest):
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)


def balance():
    req = urllib.request.Request(
        f"{API}/balance", headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)["subscription"]["generations"]


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


def still_for(mood, edit, manifest):
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
            "character_id": BASE_CHARACTER_ID,
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
        save(manifest)
        url = response["storage_urls"]["south"]

    path = f".build/koala/{mood}.png"
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


def crop_frames(frames, mood):
    """Trim the transparent padding, refusing to clip the pet.

    A beheaded koala is a worse outcome than a small one, and it would be
    invisible in a 4-frame loop until someone happened to look at the right
    beat — so the box is verified against each frame instead of assumed.
    """
    for i, frame in enumerate(frames):
        box = frame.getchannel("A").getbbox()
        if box and not (box[0] >= CROP[0] and box[1] >= CROP[1]
                        and box[2] <= CROP[2] and box[3] <= CROP[3]):
            sys.exit(f"{mood}[{i}]: sprite {box} escapes crop {CROP}. "
                     f"Widen CROP (and re-check the pet sizes in FloatingPet.swift, "
                     f"which assume a 64px canvas) rather than shipping a clipped pet.")
    return [frame.crop(CROP) for frame in frames]


def build(mood, manifest):
    edit, action, duration = MOODS[mood]
    print(f"{mood}:")
    still = still_for(mood, edit, manifest)
    print(f"  animate-with-text-v3 — 1 generation")
    frames = animate(still, action)
    # The loop already closes on itself, so the repeated final frame would
    # only make the pet hang for an extra beat on the pose it just held.
    if len(frames) > 1 and frames[0].tobytes() == frames[-1].tobytes():
        frames = frames[:-1]
    frames = crop_frames(frames, mood)
    path = f"{OUT_DIR}/{SPECIES}_{mood}.gif"
    frames[0].save(path, save_all=True, append_images=frames[1:],
                   duration=[duration] * len(frames), loop=0, disposal=2)
    print(f"  wrote {path} — {len(frames)} frames")


if __name__ == "__main__":
    TOKEN = key()
    manifest = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest = json.load(f)
    manifest.setdefault("base_character_id", BASE_CHARACTER_ID)
    manifest.setdefault("base_prompt", BASE_PROMPT)
    manifest.setdefault("seed", SEED)
    if "base_south_url" not in manifest:
        sys.exit("Manifest needs base_south_url (the base character's south rotation).")

    requested = sys.argv[1:] or list(MOODS)
    unknown = [m for m in requested if m not in MOODS]
    if unknown:
        sys.exit(f"Unknown mood(s): {', '.join(unknown)}")
    # Explicitly named moods are always rebuilt; a bare run only fills gaps,
    # so an interrupted set can be resumed without paying twice.
    if not sys.argv[1:]:
        requested = [m for m in requested
                     if not os.path.exists(f"{OUT_DIR}/{SPECIES}_{m}.gif")]

    print(f"{balance():.0f} generations available; building {len(requested)} mood(s)\n")
    try:
        for mood in requested:
            build(mood, manifest)
    finally:
        save(manifest)
    print(f"\n{balance():.0f} generations left. Manifest: {MANIFEST}")
