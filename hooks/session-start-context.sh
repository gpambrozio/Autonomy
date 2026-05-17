#!/bin/bash
#
# session-start-context.sh - SessionStart hook for the Autonomy plugin.
#
# Picks which autonomous-mode context to inject based on whether the user
# allowed Claude to ask questions in this session.
#
#   CLAUDE_AUTO_QUESTIONS_OK=1   -> permissive context; AskUserQuestion is
#                                   allowed but discouraged.
#   anything else (or unset)     -> strict no-questions context; the
#                                   AskUserQuestion PreToolUse hook will
#                                   also deny the tool outright.

set -e

if [[ "${CLAUDE_AUTO_QUESTIONS_OK:-0}" == "1" ]]; then
    cat "${CLAUDE_PLUGIN_ROOT}/hooks/autonomous-context.txt"
else
    cat "${CLAUDE_PLUGIN_ROOT}/hooks/autonomous-context-no-questions.txt"
fi
