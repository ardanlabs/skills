#!/usr/bin/env python3
"""PreToolUse hook: before any git write op (commit/push/merge/branch/tag) or GitHub
op (gh pr/issue/label/project), inject a reminder of the project's git/GitHub policy.
Advisory only — the hard blocks on merge / push-to-main / force-push live in
.claude/settings.json's deny list; this just surfaces the policy at the moment it matters.

settings.json runs this only after a cheap shell prefilter matches `git`/`gh`, so python
does not spawn for ordinary Bash calls; the precise gating below is the source of truth."""

import json
import re
import sys

# git/gh subcommands whose policy the project agent must recall before running them
TRIGGER = re.compile(
    r"\bgit\s+(commit|push|merge|branch|tag|switch|checkout|rebase)\b"
    r"|\bgh\s+(pr|issue|label|project)\b"
)

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

command = data.get("tool_input", {}).get("command", "")
if not TRIGGER.search(command):
    sys.exit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": (
            "Git/GitHub interaction detected. Project policy: you MAY stage, commit, and "
            "push to feature branches, and open or update PRs and issues. You must NEVER "
            "merge, push to the main branch, force-push, or delete branches or tags. Do not "
            "add a Co-Authored-By trailer. Follow the project's branch-naming and PR-title "
            "conventions."
        ),
    }
}))
sys.exit(0)
