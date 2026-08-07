#!/usr/bin/env bash
# UserPromptSubmit + Stop hook — notifies when a turn that took a while
# (not every turn — quick back-and-forth doesn't need a notification,
# you're already watching) finishes. No approve/deny decision needed here,
# so unlike hook.sh this never routes through the menu bar app or waits on
# anyone; it just marks a start time and, on Stop, checks how long it's
# been and fires a plain macOS notification if it was worth interrupting
# you for.

set -euo pipefail

DIR="$HOME/.config/claude-menubar-buddy"
# 700 for the same reason hook.sh uses it — see the note there.
mkdir -m 700 -p "$DIR"

INPUT="$(cat)"
EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "unknown"')"
CWD="$(echo "$INPUT" | jq -r '.cwd // "unknown"')"
PROJECT_NAME="$(basename "$CWD")"

MARK_FILE="$DIR/turn_start_${SESSION_ID}.json"

# Only notify for turns that actually took a while — this threshold is
# deliberately conservative; below it, you're almost certainly still
# looking at the terminal and a notification would just be noise.
MIN_SECONDS_TO_NOTIFY=30

case "$EVENT" in
  UserPromptSubmit)
    jq -n --arg start "$(date +%s)" '{start: ($start | tonumber)}' > "$MARK_FILE"
    ;;
  Stop)
    if [ -f "$MARK_FILE" ]; then
      START="$(jq -r '.start' "$MARK_FILE" 2>/dev/null || echo "")"
      rm -f "$MARK_FILE"
      if [ -n "$START" ]; then
        NOW="$(date +%s)"
        ELAPSED=$((NOW - START))
        # Hand the finished turn to the menu bar app regardless of duration —
        # it shows a toast card at the pet, applying its own minimum-duration
        # threshold (kept app-side so tuning it doesn't mean editing hooks).
        jq -n --arg project "$PROJECT_NAME" --argjson elapsed "$ELAPSED" \
          '{project: $project, elapsed: $elapsed, ts: now}' > "$DIR/done_${SESSION_ID}.json"
        if [ "$ELAPSED" -ge "$MIN_SECONDS_TO_NOTIFY" ]; then
          MINS=$((ELAPSED / 60))
          SECS=$((ELAPSED % 60))
          if [ "$MINS" -gt 0 ]; then
            DURATION_TEXT="${MINS}m ${SECS}s"
          else
            DURATION_TEXT="${SECS}s"
          fi
          # Banner only as fallback — when the app is running, the toast
          # (plus its Glass sound) already covers this and a second banner
          # would be double noise.
          #
          # The two values go in as ARGUMENTS, never spliced into the script
          # text. A project name is just a folder name, i.e. attacker-shaped
          # input: a directory called `proyecto" & (do shell script "…") & "`
          # closed the old string literal and ran whatever followed.
          if ! pgrep -x ClaudeMenuBarBuddy >/dev/null 2>&1; then
            osascript -e 'on run argv
              display notification ("Finished in " & (item 1 of argv)) ¬
                with title ("Claude Code — " & (item 2 of argv)) sound name "Glass"
            end run' "$DURATION_TEXT" "$PROJECT_NAME" >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
    ;;
esac

echo '{}'
exit 0
