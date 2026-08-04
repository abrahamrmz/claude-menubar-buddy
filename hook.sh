#!/usr/bin/env bash
# PreToolUse hook — routes permission decisions to the Claude Menu Bar Buddy app.
# Reads the tool-call JSON on stdin, writes a request file, polls for a response
# written by the menu bar app, and emits the hookSpecificOutput decision.
# On timeout (no one at the menu bar app in time), emits nothing so Claude Code
# falls back to its normal interactive permission prompt.

set -euo pipefail

DIR="$HOME/.config/claude-menubar-buddy"
mkdir -p "$DIR"

INPUT="$(cat)"
ID="$(uuidgen)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // "unknown"')"

HINT="$(echo "$INPUT" | jq -r '
  if .tool_input.command then .tool_input.command
  elif .tool_input.file_path then .tool_input.file_path
  elif .tool_input.url then .tool_input.url
  else (.tool_input | tostring)
  end' 2>/dev/null || echo "")"

# Project = basename of the session's cwd, so the approval UI can show which
# repo/session is actually asking (avoids approving something from the wrong
# project when several sessions run at once).
PROJECT="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
PROJECT_NAME=""
[ -n "$PROJECT" ] && PROJECT_NAME="$(basename "$PROJECT")"

# One file per request (request_<id>.json) so concurrent sessions queue up
# in the app instead of overwriting each other's single pending_request.json.
REQUEST_FILE="$DIR/request_${ID}.json"

jq -n --arg id "$ID" --arg tool "$TOOL" --arg hint "$HINT" --arg project "$PROJECT_NAME" \
  '{id: $id, tool: $tool, hint: $hint, project: $project, ts: now}' > "$REQUEST_FILE"

RESPONSE_FILE="$DIR/response_${ID}.json"

# When the user answers in the terminal instead, Claude Code kills this hook —
# without this trap the request file would linger and the app would keep
# showing an already-resolved request.
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"; exit 0' TERM HUP INT

# Poll for up to 55s (keep under the hook's own timeout, set to 60s in settings.json)
for i in $(seq 1 110); do
  if [ -f "$RESPONSE_FILE" ]; then
    DECISION="$(jq -r '.decision' "$RESPONSE_FILE" 2>/dev/null || echo "")"
    rm -f "$RESPONSE_FILE" "$REQUEST_FILE"
    if [ "$DECISION" = "allow" ]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Approved via Claude Menu Bar Buddy"}}'
      exit 0
    elif [ "$DECISION" = "deny" ]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied via Claude Menu Bar Buddy"}}'
      exit 0
    fi
  fi
  sleep 0.5
done

# Timeout: no decision made at the menu bar in time. Clean up and fall back to
# the normal interactive prompt (no permissionDecision = default "ask" flow).
rm -f "$REQUEST_FILE"
echo '{}'
exit 0
