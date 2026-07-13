#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Wrapper script to run MTV automation with Bitwarden Secrets Manager (bws).
# All secrets from the configured project(s) are injected as environment
# variables into the child process.
#
# Prerequisites:
#   - bws CLI installed and in PATH
#   - BWS_ACCESS_TOKEN exported (machine account access token)
#
# Usage:
#   ./run-with-secrets.sh ./MainMTV.sh
#   ./run-with-secrets.sh ./SetupProvider.sh
#   ./run-with-secrets.sh bash  # interactive shell with secrets available

set -euo pipefail

if ! command -v bws &>/dev/null; then
    echo "ERROR: bws CLI not found in PATH. Install from https://github.com/bitwarden/sdk-sm/releases" >&2
    exit 1
fi

if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    echo "ERROR: BWS_ACCESS_TOKEN not set. Export your machine account access token." >&2
    echo "  export BWS_ACCESS_TOKEN=\"<your-token>\"" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command> [args...]" >&2
    echo "Example: $0 ./MainMTV.sh" >&2
    exit 1
fi

exec bws run -- "$@"
