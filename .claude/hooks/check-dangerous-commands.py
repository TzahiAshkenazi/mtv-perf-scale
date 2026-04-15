#!/usr/bin/env python3
"""Block dangerous Bash commands like 'rm -rf /' and 'sudo'."""

import json
import re
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "").lower()
dangerous = any(re.search(p, cmd) for p in [r"rm\s+-rf\s+/", r"sudo"])
sys.exit(2 if dangerous else 0)
