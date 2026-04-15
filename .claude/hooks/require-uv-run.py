#!/usr/bin/env python3
"""Ensure Python commands are run via 'uv run'."""

import json
import re
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "").strip()
has_python = re.search(r"(?<![a-z])(?:python3?|pytest)\s", cmd)
starts_with_uv = cmd.startswith("uv run")

if has_python and not starts_with_uv:
    print(json.dumps({"result": "BLOCKED: Python commands must use 'uv run'. Change to: uv run " + cmd}))
    sys.exit(2)
