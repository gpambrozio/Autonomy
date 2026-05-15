#!/bin/bash
#
# Autonomy StopFailure handler.
#
# Counts consecutive turn failures for this session in $TMPDIR/<session-id>.
# Up to 5 failures: retry by sending Up+Enter to the controlling tmux pane
# (re-submits the previous prompt). After the 6th failure, give up: remove
# the counter and send /exit to end the session.

set -u

COUNTER_FILE="${TMPDIR:-/tmp}/${CLAUDE_CODE_SESSION_ID}"

if [[ -f "$COUNTER_FILE" ]]; then
    COUNT=$(<"$COUNTER_FILE")
    COUNT=$((COUNT + 1))
else
    COUNT=1
fi

if (( COUNT > 5 )); then
    rm -f "$COUNTER_FILE"
    sleep 1
    tmux send-keys -t "$TMUX_PANE" /exit Enter
else
    echo "$COUNT" >"$COUNTER_FILE"
    sleep 10
    tmux send-keys -t "$TMUX_PANE" Up Enter
fi
