#!/usr/bin/env python3
"""PostToolUse(Edit|Write|MultiEdit) on a workflow spec.yaml — advisory, never blocks.

After a spec edit the generated *-workflow/ package, its rjsf.json and its test results all
describe the previous spec, so anything read out of them before the next compile is stale.
Silent for every other file.
"""

import json
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

path = (payload.get("tool_input") or {}).get("file_path") or ""
if path.split("/")[-1] != "spec.yaml":
    sys.exit(0)

NOTICE = (
    "spec.yaml changed — the generated *-workflow/ package, rjsf.json and the test results are "
    "now stale. Recompile before trusting any of them, and re-run the cases after."
)

# additionalContext is what reaches the model on PostToolUse; systemMessage is what the human sees.
json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": NOTICE,
        },
        "systemMessage": NOTICE,
    },
    sys.stdout,
)
