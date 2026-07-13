# Project Instructions

This file provides project-specific instructions for AI/LLM agents working in this repository.

## Project Overview

**MTV** (Migration Toolkit for Virtualization) scale testing scripts for Red Hat virtualization migrations:

- VM migration testing (warm and cold migrations)
- Provider setup and configuration
- Migration health validation
- Scale and performance testing

## Tech Stack

| Stack | Usage | Tooling |
|-------|-------|---------|
| **Bash/Shell** | Primary scripting language | shellcheck |
| **Python** | Utilities and report parsing | ruff, pip |
| **YAML** | Test configuration and manifests | — |

## Development Conventions

### Shell Scripts

- Use `set -euo pipefail` at the start of scripts
- Quote all variable expansions
- Run `shellcheck` before committing
- Common functions are in `lib/common.sh`

### Python

- Use `ruff` for linting and formatting
- Pin dependencies in `requirements.txt`
- Use type hints for function signatures

### Testing

- Use `.test` TLD for all domain names in test fixtures (per RFC 2606)
- Test configurations should not contain real credentials or endpoints

### File Organization

```
MTV/
├── lib/                # Shared shell functions (common.sh)
├── config/             # Test configuration (tests.yaml)
├── utils/              # Utility scripts
├── MainMTV.sh          # Main entry point
└── SetupProvider.sh    # Provider setup
```

## Agent Configuration

Shared agent configuration is located in `.agents/`:

- `.agents/CYNEFIN.md` — Problem classification framework
- `.agents/PERSONALITY.md` — Shared agent values and behavioral commitments
- `.agents/LESSONS.md` — Lessons learned from past sessions (index)
- `.agents/lessons/` — Themed lesson files (architecture, code-quality, communication, implementation, process, security)
- `.agents/REQUIREMENTS.md` — Non-negotiable project requirements (index)
- `.agents/SECURITY_REVIEW_CHECKLIST.md` — Security review process for external context files
- `.agents/pipelines/` — Pipeline process definitions (SDLC, Jira, Skill Generation)
- `.agents/requirements/` — Individual requirement definitions (REQ-001 through REQ-011)
- `.agents/roles/` — Role-specific instructions for each SDLC gate

Platform-specific configuration:

- `.claude/` — Claude Code skills and settings
