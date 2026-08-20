#!/usr/bin/env bash
# PreToolUse hook — routes permission decisions to the Claude Menu Bar Buddy app.
# Reads the tool-call JSON on stdin, writes a request file, polls for a response
# written by the menu bar app, and emits the hookSpecificOutput decision.
# On timeout (no one at the menu bar app in time), emits nothing so Claude Code
# falls back to its normal interactive permission prompt.

set -euo pipefail

DIR="$HOME/.config/claude-menubar-buddy"
# 700, not the umask's 755: the request files written below carry the command,
# diff or file content being approved. -m only applies when the directory is
# actually created, which is why the app also re-asserts the mode at launch.
mkdir -m 700 -p "$DIR"

INPUT="$(cat)"

# Nobody home: with the app not running, no response file will ever appear, so
# every tool call would sit in the poll loop below for the full 55s before
# falling back. Hand off to the native prompt immediately instead.
#
# This deliberately comes BEFORE the standing-grant fast paths below.
# Auto-approve-edits and the always-allow list are signalled by the menu bar
# icon (the pencil, the panda) — with no app there is no signal, and a grant
# applied where nobody can see it is exactly what that icon exists to prevent.
if ! pgrep -x ClaudeMenuBarBuddy >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

ID="$(uuidgen)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // "unknown"')"

# Fast path: auto-approve-edits mode. Toggled from the app's menu (or the ⚡
# row on an Edit card); while the flag file exists, file-modifying tools
# skip the card entirely. Delete the flag (or uncheck the menu item) to go
# back to ask-before-each-edit.
if [ -f "$DIR/auto_approve_edits" ]; then
  case "$TOOL" in
    Edit|MultiEdit|Write|NotebookEdit)
      EDIT_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
      # "Stop asking about edits" means the edits you were watching go by, not
      # the handful of files that decide what runs on this machine tomorrow.
      # These always get a card, however tired of clicking you are:
      #   - credentials, and the launchd/git-hook paths that are code
      #     execution on the next login or the next commit;
      #   - Claude Code's own configuration;
      #   - the buddy's own config, which is the important one — without it an
      #     auto-approved Write could append to always_allow.json and quietly
      #     widen the very grant that let it through;
      #   - anything not absolute or containing "..", because a glob can't
      #     tell where those land, and "can't tell" has to mean "ask".
      case "$EDIT_PATH" in
        ""|[!/]*|*..*) ;;
        */.ssh/*|*/.gnupg/*) ;;
        */Library/LaunchAgents/*|*/Library/LaunchDaemons/*) ;;
        */.git/hooks/*) ;;
        "$HOME"/.claude/*|"$HOME"/.config/claude-menubar-buddy/*) ;;
        "$HOME"/Library/"Application Support"/Claude/*) ;;
        */.zshrc|*/.zshenv|*/.zprofile|*/.bashrc|*/.bash_profile|*/.profile) ;;
        /etc/*|/usr/*|/bin/*|/sbin/*|/Library/*) ;;
        *)
          jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"Auto-approved edit via Claude Menu Bar Buddy"}}'
          exit 0
          ;;
      esac
      ;;
  esac
fi

# Where this session lives. Needed this early because allowlist grants are
# scoped by it; the project *name* below is only ever for display.
CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[ -z "$CWD" ] && CWD="$PWD"
PROJECT_NAME=""
[ -n "$CWD" ] && PROJECT_NAME="$(basename "$CWD")"

# Fast path: Bash commands whose base command the user marked "Always allow"
# from the approval card get approved instantly — no card, no waiting. The
# list is maintained by the menu bar app (always_allow.json); removing an
# entry from Settings ▸ Safety re-enables the card.
ALLOW_FILE="$DIR/always_allow.json"
if [ "$TOOL" = "Bash" ] && [ -f "$ALLOW_FILE" ]; then
  FULL_CMD="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"

  # An allowlist entry names ONE command, so it may only ever speak for ONE
  # command. Anything that chains, substitutes, redirects or expands means the
  # base token has stopped describing what actually runs, and the grant the
  # user gave ("gh won't ask again") would be covering something they never
  # agreed to: `echo hi ; rm -rf ~` used to sail through on "echo" alone.
  # Those always get a card, however boring their first word looks.
  case "$FULL_CMD" in
    *[\;\&\|\<\>\(\)\`\$\\]* | *$'\n'*) FAST_PATH_SHAPE="unsafe" ;;
    *) FAST_PATH_SHAPE="single" ;;
  esac

  if [ "$FAST_PATH_SHAPE" = "single" ]; then
    # First token that isn't an env assignment (FOO=bar) — the same base the
    # app extracts when offering the "Always allow" button.
    CMD_BASE="$(printf '%s' "$FULL_CMD" \
      | awk '{for(i=1;i<=NF;i++){if($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/){print $i; exit}}}')"
    # Two scopes: `global` (allowed anywhere) and `projects[<absolute cwd>]`
    # (allowed only where it was granted). Keyed by the full path and matched
    # exactly — two checkouts can share a basename, and a prefix match would
    # make a grant on /repo also cover /repo-secrets.
    #
    # A bare array is the pre-scopes shape of this file. Those entries were
    # granted with no project in the picture, so they read as global; the app
    # rewrites the file in the new shape on its next change.
    SCOPE=""
    if [ -n "$CMD_BASE" ]; then
      SCOPE="$(jq -r --arg c "$CMD_BASE" --arg d "$CWD" '
        (if type == "array" then {global: ., projects: {}} else . end)
        | if ((.global // []) | index($c)) != null then "everywhere"
          elif ((.projects[$d] // []) | index($c)) != null then "in this project"
          else "" end' "$ALLOW_FILE" 2>/dev/null || echo "")"
    fi
    if [ -n "$SCOPE" ]; then
      jq -n --arg r "Always-allowed $SCOPE via Claude Menu Bar Buddy: $CMD_BASE" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
      exit 0
    fi
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

# CWD / PROJECT_NAME are computed near the top — the allowlist fast path
# needs them before it can decide, and it runs long before this point.

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
  --argjson choices "$CHOICES" --argjson hidden "$HIDDEN" \
  '{id: $id, tool: $tool, hint: $hint, project: $project, cwd: $cwd,
    host_bundle: $host_bundle, term_program: $term_program, choices: $choices,
    hidden: $hidden, ts: now}' > "$REQUEST_FILE"

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
