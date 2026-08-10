---
name: install-claude-menubar-buddy
description: Build and install Claude Menu Bar Buddy — a hardware-free, native macOS menu bar app that shows a panda that reacts to Claude Code permission requests (Allow/Deny), session status, token usage today, and 5-hour/weekly plan limits. Self-installing — no code signing, no download, compiles fresh on the user's own machine from source in this folder.
---

# Claude Menu Bar Buddy — Self-Install Skill

You are setting this up for **whoever is running you right now** — use *their*
home directory, *their* username, *their* paths. Nothing here should be
hardcoded to any other machine. This folder (containing this SKILL.md,
`Package.swift`, `Sources/`, `generate_gifs.py`, `hook.sh`) is the complete,
portable source — copy the whole folder to the target machine first if it
isn't already there.

**What this gives the user:** a menu bar icon (panda by default — 17 pets
available via "Choose Buddy" in the menu). When Claude Code needs a
Bash/Write/Edit/WebFetch/NotebookEdit permission decision, it shows up there
(with sound) instead of only in the terminal/Claude Desktop — click Allow or
Deny. The menu also shows session status, tokens used today, and plan usage
(5-hour + weekly limits), refreshed each time it's opened.

## Prerequisites check

1. `swift --version` — needs Swift 5.9+. Ships with Xcode Command Line Tools
   (`xcode-select --install` if missing — Xcode itself is NOT required, CLT
   is enough).
2. `python3 -c "import PIL"` — needed once, to render the panda GIFs from
   pixel-art data. If missing: `pip3 install Pillow`.
3. `jq --version` — used by the hook script to parse tool-call JSON. Install
   via `brew install jq` if missing.

If any prerequisite can't be installed, stop and tell the user what's
missing rather than guessing around it.

## Steps

### 1. Generate the GIFs (skip if already committed to the repo)

The pet GIFs are checked into `Sources/ClaudeMenuBarBuddy/Resources/` —
if they're already there (check `ls Sources/ClaudeMenuBarBuddy/Resources/*.gif`),
skip this step. If missing (fresh clone without them, or adding more pets
later), regenerate:

```bash
cd <this-folder>
python3 generate_gifs.py           # panda (pixel-art)
python3 generate_species_gifs.py   # the other 16 species (ASCII-art, requires
                                    # a sibling checkout of the M5Stick Buddy
                                    # firmware repo at the path hardcoded near
                                    # the top of that script — adjust if not present)
```

Confirm `Sources/ClaudeMenuBarBuddy/Resources/species.txt` lists the
available pets, and that a `<name>_idle.gif` / `<name>_pending.gif` pair
exists for each one.

### 2. Build

```bash
cd <this-folder>
swift build
```

Confirm `Build complete!` and that
`.build/debug/ClaudeMenuBarBuddy` exists and runs (`file .build/debug/ClaudeMenuBarBuddy`).

### 3. Install the hook scripts

`hook.sh` and `notify-done.sh` in this folder are already portable (they use
`$HOME`, not a hardcoded path). Copy both to the user's own config location:

```bash
mkdir -p ~/.config/claude-menubar-buddy
cp hook.sh ~/.config/claude-menubar-buddy/hook.sh
cp notify-done.sh ~/.config/claude-menubar-buddy/notify-done.sh
chmod +x ~/.config/claude-menubar-buddy/hook.sh ~/.config/claude-menubar-buddy/notify-done.sh
```

`notify-done.sh` is separate from `hook.sh` on purpose: it powers the
turn-finished notification (see step 4b) and never needs a permission
decision or the menu bar app to be running, so it doesn't share `hook.sh`'s
polling/timeout logic.

### 4. Wire the hook into Claude Code's settings

**Back up the existing file first**, before any merge:

```bash
[ -f ~/.claude/settings.json ] && cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d%H%M%S)
```

This is a plain copy to a new filename, not an edit of `settings.json`
itself, so it does not trigger the native permission prompt described below.
Keep the backup even after a successful merge — it's the rollback path if
the merge turns out wrong.

Read `~/.claude/settings.json` first (create `{}` if it doesn't exist yet).
**Merge, don't overwrite** — this user may already have other permissions or
hooks configured. Add these `PreToolUse` entries (adjust if a `hooks` key
already exists — append to it, don't replace):

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "Write", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "Edit", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "MultiEdit", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "WebFetch", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "WebSearch", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "NotebookEdit", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "ExitPlanMode", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] },
      { "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/hook.sh", "timeout": 60, "statusMessage": "Waiting for Claude Menu Bar Buddy..." }] }
    ]
  }
}
```

The last two aren't permission decisions — `ExitPlanMode` is a plan to accept
three different ways, and `AskUserQuestion` is Claude asking the user
something with named options. The card presents both properly (see the
"Answering questions" section of README.md); as always, if the app isn't
running the hook times out and the normal prompt takes over.

Replace `ABSOLUTE_HOME` with this user's actual resolved home directory
(e.g. from `echo $HOME`) — **do not use a literal `~`** in the `command`
field; write out the real absolute path. This was verified working this way
during development; don't assume `~` expansion without re-testing it.

### 4b. Wire the turn-finished notification (optional but recommended)

Add `UserPromptSubmit`, `Stop` and `PreCompact` entries alongside the
`PreToolUse` block above — same file, no `matcher` field needed for these
events:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/notify-done.sh", "timeout": 5 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/notify-done.sh", "timeout": 5 }] }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "ABSOLUTE_HOME/.config/claude-menubar-buddy/notify-done.sh", "timeout": 5 }] }
    ]
  }
}
```

This fires a plain macOS notification ("Finished in 1m 20s — project-name")
whenever a turn takes 30+ seconds — short back-and-forth stays silent since
you're already watching. It's independent of the menu bar app being open;
it calls `osascript` directly.

`PreCompact` fires when Claude Code compacts its context (manual `/compact`
or automatic): the script drops a marker file and the pet meditates through
the compaction. Purely cosmetic — with the app closed the marker is simply
ignored — but without this entry the meditate mood never triggers.

Validate after writing:
```bash
python3 -c "import json; json.load(open('$HOME/.claude/settings.json'))" && echo "valid JSON"
```

**Editing settings.json itself will trigger the user's own native Claude Code
permission prompt (this is intentional — settings.json changes are protected
from being self-approved by hooks). Tell the user to expect and approve this
one prompt.**

### 5. Auto-start at login (LaunchAgent)

Write to `~/Library/LaunchAgents/com.claudemenubarbuddy.app.plist`, with
`<string>` paths built from `$HOME` for **this** user (don't hardcode):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudemenubarbuddy.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>REPLACE_WITH_ABSOLUTE_PATH_TO/.build/debug/ClaudeMenuBarBuddy</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/menubar_buddy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/menubar_buddy.log</string>
</dict>
</plist>
```

`ProgramArguments` **must** be an absolute path (LaunchAgents don't expand
`~`) — resolve `<this-folder>/.build/debug/ClaudeMenuBarBuddy` to an
absolute path for this specific install location before writing.

```bash
plutil -lint ~/Library/LaunchAgents/com.claudemenubarbuddy.app.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claudemenubarbuddy.app.plist
```

### 6. Verify

```bash
ps aux | grep ClaudeMenuBarBuddy | grep -v grep
```

Tell the user to look for the 🐼 in their menu bar. It should show idle
status when clicked. It stays that way until a permission request comes in.

## Notes for whoever's running this skill

- Everything above is idempotent-ish but not bulletproof against re-runs —
  if `com.claudemenubarbuddy.app` is already loaded, `launchctl bootstrap`
  will error; use `launchctl kickstart -k gui/$(id -u)/com.claudemenubarbuddy.app`
  to restart an existing install instead.
- Kickstarting immediately after `swift build` usually gets SIGKILLed once
  ("Code Signature Invalid" / "Launch Constraint Violation" in
  `~/Library/Logs/DiagnosticReports/`): launchd raced the linker replacing
  the binary, and the ad-hoc signature it read no longer matched the file.
  Nothing is wrong with the build — run the same `kickstart` a second time,
  or sleep a second between the two. Always confirm with `pgrep -f
  ClaudeMenuBarBuddy` rather than assuming the first one took.
- Don't skip the "merge, don't overwrite" step on settings.json — a naive
  overwrite would silently delete whatever permissions/hooks the user
  already had configured. Read first, merge, write.
- If the user later wants to uninstall: `launchctl bootout gui/$(id -u)/com.claudemenubarbuddy.app`,
  delete the plist, remove the `hooks.PreToolUse` entries pointing at
  `claude-menubar-buddy/hook.sh` from settings.json, delete
  `~/.config/claude-menubar-buddy/`.
