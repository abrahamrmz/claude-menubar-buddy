# Claude Menu Bar Buddy




A hardware-free, native macOS menu bar companion for [Claude Code](https://claude.com/claude-code) — a desk pet that reacts to permission requests (Allow/Deny), and shows session status, token usage, and plan limits at a glance.

It's a software-only stand-in for Anthropic's [Claude Desktop Buddy](https://github.com/anthropics/claude-desktop-buddy) (the M5StickC-based BLE hardware pet). No soldering, no BLE pairing, no separate device — just a 🐼 in your menu bar.

## What it looks like

<img width="336" height="432" alt="image" src="https://github.com/user-attachments/assets/6fe47a82-6fde-4d50-a02d-f74e664113a9" />

*(No pending requests · session status · tokens used today · 5-hour and weekly plan limits)*

When a permission request comes in, the icon changes, a sound plays, and the dropdown shows the tool + command with Allow/Deny buttons.

## Features

- **Approve/Deny in the menu bar** for Bash, Write, Edit, WebFetch, and NotebookEdit tool calls — an alternative to answering permission prompts in the terminal or Claude Desktop
- **Styled approval card** on the desktop, next to the floating pet: per-tool accent color and icon (teal Bash, orange Edit, purple Write, pink plans), project badge, the full command or a red/green mini-diff in a scrollable code block, and pill Allow/Deny buttons — non-activating, so deciding never steals focus from what you're typing
- **Micro-interactions** — buttons visibly sink when pressed (also when triggered via hotkey), and deciding flashes a green ✓ / red ✕ verdict over the card before it fades out; queued requests then enter one at a time
- **Always allow** (⚡ on Bash cards, or ⌥⌘⏎) — approve AND remember the base command (`gh`, `npm`, …) in a buddy-managed allowlist; from then on `hook.sh` auto-approves it in ~20ms with no card at all. Managed from `Settings ▸ Safety` (select an entry, press Remove, and its card comes back). Stored in `always_allow.json`, never touching `~/.claude/settings.json`.
- **Auto-approve Edits mode** (⚡ on Edit/Write cards, or the menu toggle) — while on, file edits skip the card entirely; a ✏️ badge on the menu bar icon keeps the standing grant visible, and unchecking the menu item returns to ask-before-each-edit
- **Answering questions, not just approving** — when Claude asks with named options (`AskUserQuestion`), the card shows those options as buttons with what each one means, pickable by click or ⌘1-4; several questions in one call are walked one at a time. The answer goes back through the tool's own `answers` field, so Claude receives an ordinary result rather than a blocked tool. Multi-select questions and free-text "Other" go straight to the native picker, which is the right place to type. **Plans** get their three real choices too — approve and review each edit (⌘⏎), approve and auto-accept from here (⌥⌘⏎), or keep planning (⇧⌘⏎, which tells Claude *why* rather than just refusing).
- **Hand off to VS Code** (↗ on any card; it's also ⌥⌘⏎ on plan cards) — the hook returns immediately with no decision, so the native prompt appears right away with its full options (for plans: auto-accept, manually approve, tell Claude what to do). Long plans read better there than on a card.
- **Jump to the session** (⧉ on the card, or ⌘M) — raises the exact window that's asking, then leaves the card up and pending so you can read the diff or plan in context and still answer with ⌘⏎. The hook records which app hosts each session, so with two VS Code windows open on two repos it brings forward the one holding *this* session's folder; terminals just come to the front. Hidden when there's no host to jump to (ssh, tmux).
- **Global approval shortcuts** — ⌘⏎ approves, ⇧⌘⏎ denies, ⌥⌘⏎ takes the card's quiet action, from any app without switching focus; the hotkeys are registered only while a request is actually pending, so ⌘⏎ (and ⌘M for Minimize) keep working normally everywhere else
- **Working vs thinking** — while a turn is in flight the panda types away on a little laptop when a tool is actually running, and switches to a paw-on-chin pose while the model itself is what everyone's waiting on. It can tell them apart because a running tool and a thinking model both leave the transcript quiet — but the record that went quiet says which. Back to idle (or the limit mood) a few seconds after the turn ends.
- **17 pet characters** to choose from (`Settings ▸ Appearance`): a pixel-art panda plus 16 ASCII-art pets reused from the M5Stick Hardware Buddy firmware (cat, turtle, dragon, ghost, robot, and more)
- **Settings window** (⌘, from the menu) — three tabs: **Behavior** (remap every shortcut, toast threshold, projected-limit warnings, start at login), **Appearance** (pet, menu bar icon style, floating pet), **Safety** (auto-approve edits, the auto-allowed command list, the decision log). The menu itself stays short and keeps what you'd want at a glance: status, usage, burn rate, sessions, history — plus the two standing grants, which change what the buddy does *without asking* and so don't belong behind a window.
- **Session status** — idle / active, based on recent Claude Code session file activity
- **Active Sessions submenu** — lists each active session's project path and how long ago it was last active; click one to reveal that project folder in Finder
- **Mood pet** — the pet itself reacts to your 5-hour limit: active below 50%, visibly tired at 50%, feeling the pressure at 70%, running on fumes at 85%, and fast asleep (with drifting Zzz) once the limit is hit — same joke for all 18 pets. Being nearly out of budget outranks looking busy; the milder bands don't.
- **Pet the buddy** — click the pet in the dropdown for a happy heart-eyes reaction
- **Reactions** — a denied request gets three seconds of visible disappointment (downcast eyes, a tear), and a session the buddy hasn't met yet gets a star-eyed "hi!" the first time it says something. Both revert to the real mood on their own.
- **Celebrate on refresh** — when the 5-hour limit rolls back over to healthy, the pet throws a little arms-up celebration (with a notification) instead of silently snapping back to idle
- **Floating desktop pet** (Codex Pet-style) — an always-on-top, draggable panda that sits on your desktop independent of the menu bar dropdown, with the same mood system refreshed in the background every ~5s. Toggle from the menu (`Floating Pet`). Panda only for now.
- **Token usage today** — summed from local session transcripts, no network calls
- **Plan usage** — 5-hour and weekly limit bars, read from the same file Claude Desktop itself writes, color-coded (green/orange/red at 50%/80% used). Only Claude Desktop refreshes that file: with it closed the reading goes stale, so after 30 minutes the bars turn gray with an age tag ("· 11d ago"), clicking the line opens Claude Desktop to refresh, and stale numbers stop driving the pet's mood and threshold notifications
- **Menu bar icon** — a drawn panda silhouette (template image), so it follows the menu bar's own appearance instead of sitting in it as a fixed-color emoji: light or dark wallpaper, reduced transparency, and the inversion while the menu is open. A pending request turns it orange *and* widens its eyes (color alone isn't a signal everyone can read); auto-approve-edits adds a pencil; active sessions and queued requests show as a count beside it. `Menu Bar Icon ▸ Panda emoji` puts the original 🐼 back.
- **Accessible controls** — the status button, approval card, its buttons, the pet, and the toast all carry VoiceOver labels that say what they are and what they'll do, rather than announcing decorative glyphs and shortcut symbols
- **Burn rate** — a percentage tells you where you are; a slope tells you whether to keep going. With Claude Desktop running, the buddy fits a line through the recent 5-hour samples and shows `▲ 12%/h · 90% ≈ 16:40`, warning once per window when the current pace lands on 75% (and 90%) within the hour. It knows to cut the fit at a window rollover — the limit really does drop from 78% to 3% in nine minutes, and fitting across that would report nonsense. Without Desktop there are no live percentages to project from, so it degrades to output tokens per hour from local transcripts and says so (`~120K tok/h (plan % stale)`) rather than inventing a deadline.
- **Threshold notifications** — a macOS notification fires the first time a limit crosses into the warning (50%) or critical (80%) band, so you don't have to keep the menu open to notice
- **Turn-finished toast** — when a turn that took 15+ seconds finishes, a compact green card pops up at the pet with the project and duration (and the pet celebrates); quick back-and-forth stays silent, and the plain macOS banner only fires as a fallback when the app isn't running
- **Login item** — starts automatically, no manual launch needed
- Stats refresh in the background every ~5s, kept cheap by a per-file token cache that stats each transcript and reads only newly appended bytes (plus a fresh compute every time the menu opens)

## How it works

A `PreToolUse` hook (`hook.sh`) is registered in `~/.claude/settings.json`. When Claude Code is about to run a tool that needs a permission decision, the hook:

1. Writes the request (tool name + command/file/URL) to `~/.config/claude-menubar-buddy/pending_request.json`
2. Polls for a response file for up to 60 seconds
3. If you click Allow/Deny in the menu bar app, it writes `response_<id>.json`, which the hook picks up and returns as the tool decision
4. If nothing responds in time, the hook returns nothing and Claude Code falls back to its normal interactive prompt — so this is additive, never a single point of failure

No BLE, no external device, no cloud service — just local files.

## Install

See [`SKILL.md`](./SKILL.md) — it's written as a self-install skill for Claude Code itself. Clone this repo, open it in Claude Code, and ask Claude to read `SKILL.md` and install it. Claude will:

- generate the pet GIFs (if not already committed),
- build the app with `swift build` (no Xcode required, just Command Line Tools),
- install the hook script and merge the `PreToolUse` config into your own `~/.claude/settings.json` (never overwriting existing settings),
- register a login item,
- and launch it.

You'll be asked to approve one native permission prompt along the way (editing `settings.json` itself is intentionally never auto-approved by a hook — that would be a way for a hook to grant itself more power unsupervised).

### Manual install

If you'd rather do it by hand:

```bash
git clone <this-repo>
cd claude-menubar-buddy
python3 generate_gifs.py            # panda
python3 generate_species_gifs.py    # other 16 pets (needs claude-desktop-buddy checked out too — see script header)
swift build
mkdir -p ~/.config/claude-menubar-buddy
cp hook.sh ~/.config/claude-menubar-buddy/hook.sh
chmod +x ~/.config/claude-menubar-buddy/hook.sh
```

Then merge the `hooks.PreToolUse` block from `SKILL.md` into `~/.claude/settings.json` yourself (use your actual home directory in the `command` path, not `~`), and optionally set up the LaunchAgent plist shown there for auto-start at login.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools — `xcode-select --install`)
- Python 3 with Pillow (`pip3 install Pillow`) — only needed to (re)generate GIFs
- `jq` (`brew install jq`) — used by the hook script

## Project layout

```
Package.swift                          # Swift Package manifest
Sources/ClaudeMenuBarBuddy/
  main.swift                           # bootstrap, AppDelegate core, menus, poll loop
  ApprovalCard.swift                   # the floating card: build, decide, verdict animation
  FloatingPet.swift                    # desktop pet window + dragging
  MoodEngine.swift                     # which mood/GIF the pet shows, and when
  Toast.swift                          # turn-finished toast
  JumpToHost.swift                     # raise the editor/terminal hosting a session
  BurnRate.swift                       # how fast the 5-hour limit is going
  StatusIcon.swift                     # the menu bar icon + accessibility label
  SettingsWindow.swift                 # settings window, panes, always-allow table
  HotKeys.swift                        # global shortcuts (KeyboardShortcuts)
  Prefs.swift                          # Defaults keys + hook flag files
  UsageStats.swift                     # reads session JSONL + plan-usage-history.json
  Resources/                           # generated GIFs + species.txt (checked in)
hook.sh                                # the PreToolUse hook script
notify-done.sh                         # UserPromptSubmit/Stop hook (working state + toast)
generate_gifs.py                       # renders the pixel-art panda GIFs
generate_species_gifs.py               # extracts ASCII pets from claude-desktop-buddy and renders them
SKILL.md                               # self-install instructions for Claude Code
```

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.claudemenubarbuddy.app   # or your LaunchAgent label
rm ~/Library/LaunchAgents/com.claudemenubarbuddy.app.plist
rm -rf ~/.config/claude-menubar-buddy
```

Then remove the `hooks.PreToolUse` entries pointing at `claude-menubar-buddy/hook.sh` from `~/.claude/settings.json`.

## Why this exists instead of the hardware Buddy

Both are complementary, not competing — see the [Claude Desktop Buddy](https://github.com/anthropics/claude-desktop-buddy) project if you want the physical version too. This one exists because:

- No hardware to buy or wait for shipping on
- No BLE pairing, no Developer Mode toggle in Claude Desktop required
- Covers Claude Code's own permission hooks directly, which the BLE bridge doesn't see
- Compiles fresh from source on your machine, so there's nothing to code-sign or notarize, and no Gatekeeper friction

If a hardware Buddy is also paired, they don't conflict: this app's hook resolves the decision first (before a native prompt is even shown); if it times out, the request falls through to the normal prompt, which the hardware Buddy can also see and approve from.

## License

[MIT](./LICENSE) — use it, fork it, modify it freely.

16 of the 17 pet designs (all except the panda, which is original pixel art drawn for this project) are rendered from ASCII-art poses in Anthropic's [claude-desktop-buddy](https://github.com/anthropics/claude-desktop-buddy) firmware (`src/buddies/*.cpp`), © 2026 Anthropic, PBC, also MIT licensed.
