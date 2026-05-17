#!/bin/bash
#
# attended-run.sh - Run claude-auto in a detached tmux session you intend
# to attach to from another terminal, with AskUserQuestion left enabled.
#
# By default Autonomy assumes nobody is watching and the PreToolUse hook
# denies AskUserQuestion outright. That is the right policy for cron,
# batch, and parallel runs. This script is for the opposite case: you
# want the session to run autonomously most of the time, but you plan to
# attach so you can answer the occasional genuinely-ambiguous question.
#
# Setting CLAUDE_AUTO_QUESTIONS_OK=1 here:
#   - swaps the SessionStart context to the softer "ask only if
#     absolutely necessary" wording, and
#   - allows AskUserQuestion to actually reach you.
#
# Usage:
#   ./attended-run.sh "your prompt here"
#
# Then, from any other terminal:
#   tmux attach -t <session-name printed at start>
#
# Optional env vars:
#   OUT_LOG       Path to the transcript log (default: /tmp/<session>.log).
#   CLAUDE_ARGS   Extra args forwarded to claude-auto (default:
#                 --dangerously-skip-permissions).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_AUTO="$SCRIPT_DIR/../bin/claude-auto"

PROMPT="${1:?usage: attended-run.sh \"your prompt\"}"
SESSION="autonomy-attended-$(date +%Y%m%d-%H%M%S)-$$"
OUT_LOG="${OUT_LOG:-/tmp/$SESSION.log}"
CLAUDE_ARGS="${CLAUDE_ARGS:---dangerously-skip-permissions}"

# Export so claude-auto inherits the var, which is then inherited by
# claude and finally by the hook subprocess that decides whether to deny
# AskUserQuestion.
export CLAUDE_AUTO_QUESTIONS_OK=1

tmux new-session -d -s "$SESSION" \
    "'$CLAUDE_AUTO' --log '$OUT_LOG' $CLAUDE_ARGS '$PROMPT'; exit"

echo "Started attended tmux session: $SESSION"
echo "  attach NOW so you can answer questions when they come:"
echo "      tmux attach -t $SESSION"
echo "  log:     $OUT_LOG"
echo
echo "Waiting for the session to finish (Ctrl-C here is safe; the tmux"
echo "session keeps running and you can re-attach to it)."

while tmux has-session -t "$SESSION" 2>/dev/null; do
    sleep 5
done

echo
echo "Session finished. Transcript: $OUT_LOG"
