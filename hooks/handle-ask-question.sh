#!/bin/bash
#
# handle-ask-question.sh - PreToolUse hook for the AskUserQuestion tool.
#
# When CLAUDE_AUTO_QUESTIONS_OK=1 the call is allowed through (exit 0 with
# no JSON output = no opinion, default permission rules apply).
#
# Otherwise the call is denied via the PreToolUse decision JSON. The
# permissionDecisionReason is surfaced to Claude in place of a tool
# result, which lets us hand back a stock "use your best judgement"
# instruction without ever pausing for a human.

set -e

if [[ "${CLAUDE_AUTO_QUESTIONS_OK:-0}" == "1" ]]; then
    exit 0
fi

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "This session is running in autonomous mode (CLAUDE_AUTO_QUESTIONS_OK is not set to 1), so no human is available to answer. Do not call AskUserQuestion again. Use your best judgement based on the existing code, project conventions, and the original task description, and continue. State any non-obvious assumptions you made in your final output so they can be reviewed later."
  }
}
JSON
