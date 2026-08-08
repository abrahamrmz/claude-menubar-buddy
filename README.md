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
- **A queue you can reach into** — when several sessions ask at once, the orange `+N` badge on the card is a button: it lists what's waiting (tool, project, command), lets you jump to any of them with ⌘1-9 or a click, and offers `Allow all` / `Deny all` for the whole line at once. The batch actions sit one level in behind a confirmation, because answering things you haven't read is exactly what this app exists to prevent — and the list above them is what makes it an informed choice. Picking a request pins it, so the queue doesn't re-sort it away underneath you.
- **Jump to the session** (⧉ on the card, or ⌘M) — raises the exact window that's asking, then leaves the card up and pending so you can read the diff or plan in context and still answer with ⌘⏎. The hook records which app hosts each session, so with two VS Code windows open on two repos it brings forward the one holding *this* session's folder; terminals just come to the front. Hidden when there's no host to jump to (ssh, tmux).
- **Global approval shortcuts** — ⌘⏎ approves, ⇧⌘⏎ denies, ⌥⌘⏎ takes the card's quiet action, from any app without switching focus; the hotkeys are registered only while a request is actually pending, so ⌘⏎ (and ⌘M for Minimize) keep working normally everywhere else
- **Working vs thinking** — while a turn is in flight the panda types away on a little laptop when a tool is actually running, and switches to a paw-on-chin pose while the model itself is what everyone's waiting on. It can tell them apart because a running tool and a thinking model both leave the transcript quiet — but the record that went quiet says which. Back to idle (or the limit mood) a few seconds after the turn ends.
- **20 pet characters** to choose from (`Settings ▸ Appearance`): a pixel-art panda, a cyberpunk koala, and 18 ASCII-art pets reused from the M5Stick Hardware Buddy firmware (cat, axolotl, turtle, dragon, ghost, robot, and more). The firmware pets animate with the choreography their own firmware plays — the same pose sequence at the same tempo, in the colour that species is drawn in on the device
- **The koala** is generated rather than drawn, and `generate_koala_gifs.py` is the source: prompts, seed and character IDs live in `koala_manifest.json` so the whole set rebuilds from a clean checkout. Each mood is an edit *of the base character's id*, which is what keeps the bionic eye intact from pose to pose — it even survives as an X inside its own metal rim when the 5-hour limit runs out. It's the only pet with all twelve moods besides the panda
- **Settings window** (⌘, from the menu) — three tabs: **Behavior** (remap every shortcut, toast threshold, projected-limit warnings, start at login), **Appearance** (pet, menu bar icon style, floating pet), **Safety** (auto-approve edits, the auto-allowed command list, the decision log). The menu itself stays short and keeps what you'd want at a glance: status, usage, burn rate, sessions, history — plus the two standing grants, which change what the buddy does *without asking* and so don't belong behind a window.
- **Welcome & setup check** (from the menu, and once on first run) — four short pages: what the card does, a setup check, your shortcuts, and what the pet's moods mean. The setup check is the useful half and it doesn't expire: it reads your actual `~/.claude/settings.json` and reports which tools really route through the buddy, whether `hook.sh` is installed and executable, whether the installed copy has drifted from the repo's, and whether `jq` is there. Every one of those fails *silently* otherwise — the hook just never fires and the buddy sits there looking perfectly healthy — so when something blocks approvals the menu says `⚠︎ Setup needs attention…` instead of leaving you to guess. It never edits `settings.json`; it prints the line to run and leaves the decision to you.
- **Doesn't go blind when Claude Code updates** — the buddy leans on four things Claude Code owes it no compatibility for: the hook contract, the transcript format, a plan-usage file that belongs to Claude Desktop, and the set of tools that ask permission. Approvals can't break (hooks are additive — if ours fails, the native prompt takes over), but those seams can shift quietly. So the setup check also records which Claude Code series it was last verified against and says so when that moves (minor versions only — patches ship too often to be worth a word), asserts the transcript still carries the fields it reads, and lists tools that ran without ever passing through the card. That last one is how a newly permission-gated tool announces itself instead of being noticed weeks later by its absence; the tool names cost nothing to collect, because they're picked up from lines the token counter is already parsing.
- **Session status** — idle / active, based on recent Claude Code session file activity
- **Active Sessions submenu** — lists each active session's project path and how long ago it was last active; click one to reveal that project folder in Finder
- **Mood pet** — the pet itself reacts to your 5-hour limit: active below 50%, visibly tired at 50%, feeling the pressure at 70%, running on fumes at 85%, and fast asleep (with drifting Zzz) once the limit is hit — same joke for all 19 pets, each animated with the pose choreography its firmware actually plays. Being nearly out of budget outranks looking busy; the milder bands don't.
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
- **Quiet when nobody's looking** — the pets stop animating while the screen is locked or the display is asleep, and the dropdown's pet only animates while the dropdown is actually open. A looping GIF redraws whether or not anyone can see it, and that was most of the app's idle wakeups: ~155/s down to ~36/s, which is the difference between a desk pet and a desk pet you notice in your battery

## How it works

A `PreToolUse` hook (`hook.sh`) is registered in `~/.claude/settings.json`. When Claude Code is about to run a tool that needs a permission decision, the hook:

1. Writes the request (tool name + command/file/URL) to `~/.config/claude-menubar-buddy/pending_request.json`
2. Polls for a response file for up to 60 seconds
3. If you click Allow/Deny in the menu bar app, it writes `response_<id>.json`, which the hook picks up and returns as the tool decision
4. If nothing responds in time, the hook returns nothing and Claude Code falls back to its normal interactive prompt — so this is additive, never a single point of failure

No BLE, no external device, no cloud service — just local files.

## What it can see, and what it can do

This app sits between Claude Code and your answer to "may I run this?", so its reach is worth spelling out.

**It makes no network connections at all.** No telemetry, no update check, no API client — grep the sources for `URLSession` and there is nothing to find. Everything below stays on the machine.

**It reads your local Claude Code transcripts.** Every `.jsonl` under `~/.claude/projects/`, to count today's output tokens and tell which sessions are active. It sums the `usage` numbers and reads the last record of the newest file to tell a running tool from a thinking model. It also reads `~/Library/Application Support/Claude/plan-usage-history.json`, which Claude Desktop writes, for the limit bars.

**It writes what you're being asked to approve to disk.** Each pending request lands in `~/.config/claude-menubar-buddy/request_<id>.json` — the command, or the diff, or the file content — and is deleted the moment it's answered. Every decision is then appended to `decisions.jsonl` along with the first 200 characters of what it was about, and that log is deliberately never rotated: it's your audit trail, and `Settings ▸ Safety` opens it. Both the hook and the app keep that directory owner-only (`0700`) — the shell's default umask would otherwise leave every pending command and diff readable by any other account on the machine.

**Debug screenshots are off unless you ask for them.** The app can render the approval card, the pet, the menu bar icon or the settings panes straight to a PNG — an in-process render, because a non-activating panel comes out blank through ScreenCaptureKit. Useful while working on the layout, and a poor thing to leave standing: it photographs whatever is on the card, which can be a diff carrying a credential, and any process running as you can drop the file that asks for one. Set `CLAUDE_BUDDY_DEBUG=1` in the app's environment to turn it on. Without it the `capture_*` flags are never even looked at.

**It asks for none of the invasive macOS permissions.** No Accessibility (the global shortcuts are Carbon hot keys), no Screen Recording (the debug screenshots are rendered in-process), no camera, microphone, contacts or location. The one thing it takes is the ⌘⏎ / ⇧⌘⏎ / ⌥⌘⏎ / ⌘M combinations, and only while a card is actually on screen.

**The hook fails safe.** A timeout, an error, or the app not running all return no decision, which means Claude Code falls back to its own prompt. Nothing is ever approved because something broke; the worst case is being asked twice.

### The two standing grants

Both approve things without showing you a card, so both are worth understanding before turning them on — and both stay visible in the menu bar the whole time they're active, because a grant you can't see is a grant you'll forget you gave.

**Always allow `<command>`** remembers one base command in `always_allow.json`. It only ever speaks for a single command: anything carrying `;` `&` `|` `<` `>` `(` `)` `` ` `` `$` `\` or a newline gets a card regardless of its first word, since past that point the first word has stopped describing what will actually run. Keep the list to things that read and navigate — `cat`, `git`, `grep`, `ls`. An interpreter on that list (`python`, `node`, `swift`) is equivalent to allowing everything, because one clean command is all it takes.

**Auto-approve Edits** lets `Edit`/`Write`/`NotebookEdit` through without a card and puts a ✏️ on the menu bar icon for as long as it's on. It stops at the files that decide what runs on this machine tomorrow: `~/.ssh`, `~/.gnupg`, LaunchAgents and LaunchDaemons, `.git/hooks`, `~/.claude`, the buddy's own config directory, shell startup files, and the system directories. Anything relative, or containing `..`, gets a card too — there's no way to tell where those land, and "can't tell" has to mean "ask". The buddy's own config is on that list on purpose: without it, an auto-approved write could append to `always_allow.json` and widen the very grant that let it through.

Neither grant is applied while the app isn't running. Both are announced by an icon, and with no icon on screen there is nothing doing the announcing.

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
python3 generate_species_gifs.py    # other 18 pets (clones the firmware into .build/ on first run)
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
  Queue.swift                          # picking from and answering the waiting line
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
