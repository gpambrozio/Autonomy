#!/usr/bin/env python3
"""
Autonomy Stop handler.

Reads the Stop hook's JSON input from stdin (which includes a
`last_assistant_message` field with the text of claude's final reply) and
drives the tmux pane based on that message:

- "done"    -> claude is finished; send /exit + Enter so the session ends.
- "waiting" -> claude is parked on a background job; do nothing so the
               session sits idle until something else resumes it.
- anything else -> nudge claude to confirm by replying with "done" or
                   "waiting" next time. The next Stop will re-check.

A 1s sleep precedes the tmux send-keys so the Stop event has settled in
the TUI before the keystrokes arrive at claude's prompt box.
"""

import json
import os
import subprocess
import sys
import time


NUDGE = (
    "If there are no background jobs you're waiting for and you're done working "
    "reply with \"done\" only. "
    "If you are waiting for background jobs reply with \"waiting\" only."
)


def send_keys(pane: str, *keys: str) -> None:
    subprocess.run(["tmux", "send-keys", "-t", pane, *keys], check=False)


def main() -> int:
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        print("autonomy stop: TMUX_PANE not set", file=sys.stderr)
        return 0

    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        hook_input = {}

    last_message = (hook_input.get("last_assistant_message") or "").strip().lower()

    if last_message == "waiting":
        # Claude flagged it's waiting on a background job; leave the session
        # alone — no /exit, no nudge.
        return 0

    time.sleep(1)

    if last_message == "done":
        send_keys(pane, "/exit")
    else:
        send_keys(pane, NUDGE)

    # An Enter sent immediately after the text only inserts a newline in the
    # prompt box; pausing briefly first makes it submit instead.
    time.sleep(1)
    send_keys(pane, "Enter")

    return 0


if __name__ == "__main__":
    sys.exit(main())
