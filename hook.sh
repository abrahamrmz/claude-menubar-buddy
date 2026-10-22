#!/usr/bin/env bash
# PreToolUse hook — asks buddy-rule what to do and carries the answer.
# buddy-rule (BuddyCore) is the same rule the app and the tests use: it says
# pass, card or defer, and this script only writes the request file, polls for
# the response written by the menu bar app, and emits the hookSpecificOutput
# decision.
# On timeout with no one at the menu bar app, a non-critical call falls back to
# Claude Code's normal interactive prompt; a critical one is denied, because
# handing it back would let the agent's own permission mode decide.

set -euo pipefail

DIR="$HOME/.config/claude-menubar-buddy"
# 700, not the umask's 755: the request files written below carry the command,
# diff or file content being approved. -m only applies when the directory is
# actually created, which is why the app also re-asserts the mode at launch.
# shellcheck disable=SC2174  # -m only reaches the deepest dir — which is the
# one that holds the sensitive files; ~/.config keeps the umask like any XDG dir.
mkdir -m 700 -p "$DIR"

INPUT="$(cat)"

# Nobody home: with the app not running, no response file will ever appear, so
# every tool call would sit in the poll loop below for the full 55s before
# falling back. Hand off to the native prompt immediately instead.
#
# This deliberately comes BEFORE buddy-rule. Auto mode and the always-allow
# list are signalled by the menu bar icon (the pencil, the panda) — with no app
# there is no signal, and a grant applied where nobody can see it is exactly
# what that icon exists to prevent.
if ! pgrep -x ClaudeMenuBarBuddy >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

ID="$(uuidgen)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // "unknown"')"

# The rule — what passes on its own, what needs a card, what is critical —
# lives in buddy-rule (BuddyCore), the same code the app and the tests use.
# This script only carries the answer. No binary, or no answer, is treated
# as the worst case: a card that is denied if nobody answers it.
RULE_BIN="${BUDDY_RULE:-$DIR/buddy-rule}"
RULE_OUT=""
if [ -x "$RULE_BIN" ]; then
  RULE_OUT="$(printf '%s' "$INPUT" | "$RULE_BIN" 2>/dev/null || true)"
fi
VERDICT="$(printf '%s' "$RULE_OUT" | jq -r '.verdict // empty' 2>/dev/null || true)"
if [ -z "$VERDICT" ]; then
  RULE_OUT='{"verdict":"card","category":"desconocido","critical":true,"reason":"no se pudo evaluar la regla","grant":null}'
  VERDICT="card"
fi
RULE_REASON="$(printf '%s' "$RULE_OUT" | jq -r '.reason // ""')"
RULE_CATEGORY="$(printf '%s' "$RULE_OUT" | jq -r '.category // "desconocido"')"
RULE_CRITICAL="$(printf '%s' "$RULE_OUT" | jq -r 'if .critical == true then "true" else "false" end')"
case "$VERDICT" in
  pass)
    jq -n --arg r "$RULE_REASON" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
    exit 0
    ;;
  defer)
    echo '{}'
    exit 0
    ;;
esac

# Where this session lives, for the request file the card reads.
CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[ -z "$CWD" ] && CWD="$PWD"
PROJECT_NAME=""
[ -n "$CWD" ] && PROJECT_NAME="$(basename "$CWD")"

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
# screen (scrolls beyond that); truncation here is only a payload safety cap,
# which is why it sits at 20k rather than the old 2k — a 2,100-character
# command was being shown cut at 2,000 while Allow still approved all 2,100,
# so `…####### ; rm -rf ~/importante` could ride in past the fold.
#
# The cap can still be hit by something genuinely enormous, so the count of
# what didn't fit rides along to the app, which says so on the card. Emitted
# as "<hidden>\n<hint>" — hidden first because the hint itself has newlines.
HINT_INFO="$(echo "$INPUT" | jq -r '
  (if .tool_name == "AskUserQuestion" then
    ([.tool_input.questions[]? | .question] | join("\n\n"))
  elif .tool_name == "ExitPlanMode" and .tool_input.plan != null then
    "PLAN PROPUESTO\n" + .tool_input.plan
  elif .tool_name == "Edit" and .tool_input.old_string != null then
    (.tool_input.file_path // "?") + "\n--- quita\n" + .tool_input.old_string + "\n+++ pone\n" + .tool_input.new_string
  elif .tool_name == "MultiEdit" and (.tool_input.edits | length) > 0 then
    (.tool_input.file_path // "?") + "\n" +
    ([.tool_input.edits[] | "--- quita\n" + (.old_string // "") + "\n+++ pone\n" + (.new_string // "")] | join("\n"))
  elif .tool_name == "Write" and .tool_input.content != null then
    (.tool_input.file_path // "?") + "\n+++ contenido\n" + .tool_input.content
  elif .tool_input.command then .tool_input.command
  elif .tool_input.file_path then .tool_input.file_path
  elif .tool_input.url then .tool_input.url
  elif .tool_input.query then .tool_input.query
  else (.tool_input | tostring)
  end) as $full
  | (($full | length) - 20000) as $over
  | ((if $over > 0 then $over else 0 end) | tostring) + "\n" + $full[0:20000]' 2>/dev/null || echo "0")"
case "$HINT_INFO" in
  *$'\n'*) HIDDEN="${HINT_INFO%%$'\n'*}"; HINT="${HINT_INFO#*$'\n'}" ;;
  *)       HIDDEN=0; HINT="" ;;
esac
# --argjson wants a real number, and this one came out of a subshell.
case "$HIDDEN" in ''|*[!0-9]*) HIDDEN=0 ;; esac

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
  --arg category "$RULE_CATEGORY" --arg reason "$RULE_REASON" --arg critical "$RULE_CRITICAL" \
  --argjson choices "$CHOICES" --argjson hidden "$HIDDEN" \
  '{id: $id, tool: $tool, hint: $hint, project: $project, cwd: $cwd,
    host_bundle: $host_bundle, term_program: $term_program, choices: $choices,
    hidden: $hidden, agent: "claude", category: $category, critical: ($critical == "true"),
    reason: $reason, ts: now}' > "$REQUEST_FILE"

RESPONSE_FILE="$DIR/response_${ID}.json"

# When the user answers in the terminal instead, Claude Code kills this hook —
# without this trap the request file would linger and the app would keep
# showing an already-resolved request.
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"; exit 0' TERM HUP INT

# Poll for up to 55s (keep under the hook's own timeout, set to 60s in settings.json)
for _ in $(seq 1 "${BUDDY_HOOK_WAIT_TICKS:-110}"); do
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
# the normal interactive prompt for routine work.
rm -f "$REQUEST_FILE"
# Critical and unanswered: it does not run. Handing it back would let the
# agent's own permission mode (Claude's auto mode, an allow rule) decide —
# exactly the unattended critical command this card exists to stop.
if [ "$RULE_CRITICAL" = "true" ]; then
  jq -n --arg r "Este comando necesita aprobación en el buddy y nadie respondió a tiempo; no se ejecutó. Espera o pide al usuario que lo apruebe antes de reintentar." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi
echo '{}'
exit 0
