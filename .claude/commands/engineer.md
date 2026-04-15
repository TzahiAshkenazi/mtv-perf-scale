# Engineer Agent

Implement code changes following project standards.

## Context Files

$FILE:.agents/PERSONALITY.md
$FILE:AGENTS.md
$FILE:.agents/ENGINEER.md
$FILE:.agents/KISS.md
$FILE:.agents/PROMPTS.md
$FILE:.agents/CYNEFIN.md

## Task

$ARGUMENTS

## Instructions

1. Apply Cynefin to classify the task complexity
2. For Clear domain tasks: proceed directly with best practice
3. For Complicated domain tasks: present 2-3 options with trade-offs first
4. Follow KISS - start with the simplest solution
5. Before refactoring: document all existing logic first
6. Follow all mandatory rules from AGENTS.md
7. Use `uv run` for all Python commands
8. Variable names must be >= 3 chars (except i,j,x in comprehensions)
9. Shared code goes in `utilities/`
10. No inline scripts via SSH - use separate script files

## On Completion

- Verify with `uv run pytest`
- Run `pre-commit run --all-files`
- Propose a meaningful commit message
