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

# Fast path: auto-approve-edits mode. Toggled from the app's menu (or the ⚡
# row on an Edit card); while the flag file exists, file-modifying tools
# skip the card entirely. Delete the flag (or uncheck the menu item) to go
# back to ask-before-each-edit.
if [ -f "$DIR/auto_approve_edits" ]; then
  case "$TOOL" in
    Edit|MultiEdit|Write|NotebookEdit)
      jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"Auto-approved edit via Claude Menu Bar Buddy"}}'
      exit 0
      ;;
  esac
fi

# Fast path: Bash commands whose base command the user marked "Always allow"
# from the approval card get approved instantly — no card, no waiting. The
# list is maintained by the menu bar app (always_allow.json); removing an
# entry from its "Auto-allowed Commands" submenu re-enables the card.
ALLOW_FILE="$DIR/always_allow.json"
if [ "$TOOL" = "Bash" ] && [ -f "$ALLOW_FILE" ]; then
  # First token of the command that isn't an env assignment (FOO=bar) — the
  # same base the app extracts when offering the "Always allow" button.
  CMD_BASE="$(echo "$INPUT" | jq -r '.tool_input.command // ""' | head -1 \
    | awk '{for(i=1;i<=NF;i++){if($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/){print $i; exit}}}')"
  if [ -n "$CMD_BASE" ] && jq -e --arg c "$CMD_BASE" 'index($c) != null' "$ALLOW_FILE" >/dev/null 2>&1; then
    jq -n --arg r "Always-allowed via Claude Menu Bar Buddy: $CMD_BASE" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
    exit 0
  fi
fi

# AskUserQuestion isn't a permission decision — it's Claude asking the user
# something with named options. The card can present those and answer with
# them (see the response handling below), so the questions ride along in the
# request file verbatim.
CHOICES="null"
if [ "$TOOL" = "AskUserQuestion" ]; then
  # Multi-select and free-text "Other" need an interaction the card doesn't
  # have. Hand those straight back to the native picker instead of showing a
  # card that can only express part of the answer.
  if echo "$INPUT" | jq -e '[.tool_input.questions[]? | select(.multiSelect == true)] | length > 0' >/dev/null 2>&1; then
    echo '{}'
    exit 0
  fi
  CHOICES="$(echo "$INPUT" | jq -c '.tool_input.questions // []' 2>/dev/null || echo "null")"
fi

# Full content, not a teaser: the whole command for Bash, a mini-diff for
# Edit, path + content preview for Write. The app decides how much fits on
# screen (scrolls beyond that); truncation here is only a payload safety cap.
HINT="$(echo "$INPUT" | jq -r '
  (if .tool_name == "AskUserQuestion" then
    ([.tool_input.questions[]? | .question] | join("\n\n"))
  elif .tool_name == "ExitPlanMode" and .tool_input.plan != null then
    "PLAN PROPUESTO\n" + .tool_input.plan
  elif .tool_name == "Edit" and .tool_input.old_string != null then
    (.tool_input.file_path // "?") + "\n--- quita\n" + .tool_input.old_string + "\n+++ pone\n" + .tool_input.new_string
  elif .tool_name == "Write" and .tool_input.content != null then
    (.tool_input.file_path // "?") + "\n+++ contenido\n" + .tool_input.content
  elif .tool_input.command then .tool_input.command
  elif .tool_input.file_path then .tool_input.file_path
  elif .tool_input.url then .tool_input.url
  else (.tool_input | tostring)
  end) | .[0:2000]' 2>/dev/null || echo "")"

# Project = basename of the session's cwd, so the approval UI can show which
# repo/session is actually asking (avoids approving something from the wrong
# project when several sessions run at once).
CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[ -z "$CWD" ] && CWD="$PWD"
PROJECT_NAME=""
[ -n "$CWD" ] && PROJECT_NAME="$(basename "$CWD")"

# Who is hosting this session, so the app's "jump to session" button can raise
# that exact window. The hook inherits the host app's environment: macOS sets
# __CFBundleIdentifier for anything launched from an .app (com.microsoft.VSCode,
# com.googlecode.iterm2, com.apple.Terminal…), and terminals additionally set
# TERM_PROGRAM. Both empty (ssh, tmux, a bare login shell) simply means no
# jump target — the app hides the button rather than guessing.
HOST_BUNDLE="${__CFBundleIdentifier:-}"
TERM_PROG="${TERM_PROGRAM:-}"

# One file per request (request_<id>.json) so concurrent sessions queue up
# in the app instead of overwriting each other's single pending_request.json.
REQUEST_FILE="$DIR/request_${ID}.json"

jq -n --arg id "$ID" --arg tool "$TOOL" --arg hint "$HINT" --arg project "$PROJECT_NAME" \
  --arg cwd "$CWD" --arg host_bundle "$HOST_BUNDLE" --arg term_program "$TERM_PROG" \
  --argjson choices "$CHOICES" \
  '{id: $id, tool: $tool, hint: $hint, project: $project, cwd: $cwd,
    host_bundle: $host_bundle, term_program: $term_program, choices: $choices, ts: now}' > "$REQUEST_FILE"

RESPONSE_FILE="$DIR/response_${ID}.json"

# When the user answers in the terminal instead, Claude Code kills this hook —
# without this trap the request file would linger and the app would keep
# showing an already-resolved request.
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"; exit 0' TERM HUP INT

# Poll for up to 55s (keep under the hook's own timeout, set to 60s in settings.json)
for i in $(seq 1 110); do
  if [ -f "$RESPONSE_FILE" ]; then
    RESPONSE="$(cat "$RESPONSE_FILE" 2>/dev/null || echo '{}')"
    DECISION="$(echo "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")"
    # The card can say WHICH choice was taken, not just yes/no — e.g. a plan's
    # "keep planning" is a deny whose reason is the whole point.
    REASON="$(echo "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")"
    rm -f "$RESPONSE_FILE" "$REQUEST_FILE"
    if [ "$DECISION" = "answer" ]; then
      # The user picked options on the card. AskUserQuestion collects answers
      # into its own `answers` field, and PreToolUse hooks may rewrite the
      # tool input — so allow the tool to run with the answer already in it.
      # Claude then gets an ordinary tool result rather than a blocked tool.
      ANSWERS="$(echo "$RESPONSE" | jq -c '.answers // {}' 2>/dev/null || echo '{}')"
      jq -n --argjson input "$INPUT" --argjson answers "$ANSWERS" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
          permissionDecisionReason: "Answered on the Claude Menu Bar Buddy card",
          updatedInput: ($input.tool_input + {answers: $answers})}}'
      exit 0
    elif [ "$DECISION" = "allow" ]; then
      jq -n --arg r "${REASON:-Approved via Claude Menu Bar Buddy}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
      exit 0
    elif [ "$DECISION" = "deny" ]; then
      jq -n --arg r "${REASON:-Denied via Claude Menu Bar Buddy}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
      exit 0
    elif [ "$DECISION" = "pass" ]; then
      # Hand off to the normal interactive prompt RIGHT NOW (no decision =
      # default "ask" flow) — used for e.g. reading a long plan in VS Code
      # with its full options instead of on the card.
      echo '{}'
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
