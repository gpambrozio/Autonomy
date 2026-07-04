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
    tmux send-keys -t "$TMUX_PANE" /exit
    sleep 1
    tmux send-keys -t "$TMUX_PANE" Enter
    # With background work still running, /exit shows a "Background work is
    # running" dialog instead of exiting; its default option is "Exit anyway",
    # so one more Enter confirms it. Poll briefly for the dialog — if it never
    # appears, the session exited cleanly.
    for _ in 1 2 3 4 5; do
        sleep 1
        if tmux capture-pane -p -t "$TMUX_PANE" 2>/dev/null \
                | grep -q -e 'Background work is running' -e 'Exit anyway'; then
            tmux send-keys -t "$TMUX_PANE" Enter
            break
        fi
    done
else
    echo "$COUNT" >"$COUNTER_FILE"
    sleep 10
    tmux send-keys -t "$TMUX_PANE" Up
    sleep 1
    tmux send-keys -t "$TMUX_PANE" Enter
fi
