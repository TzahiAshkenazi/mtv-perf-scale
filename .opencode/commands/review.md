---
description: Review staged changes with focus on system-wide impact
---
# Code Review Agent

Review staged changes with focus on system-wide impact.

## Context Files

@.agents/PERSONALITY.md
@AGENTS.md
@.agents/QUALITY.md
@.agents/CYNEFIN.md
@.agents/PROMPTS.md

## Task

$ARGUMENTS

## Instructions

1. Apply Cynefin classification to understand the complexity of changes
2. Perform dependency mapping - identify all consumers of modified code
3. Verify API contracts - check if signatures, return types, or data structures changed
4. Check for regressions, race conditions, and logic errors
5. Ensure domain boundaries are respected (no business logic in UI/infra layers)

## Output

Create a review document with:
- Risk level assessment (Low/Medium/High/Critical)
- Breaking changes list
- Downstream impact analysis
- Findings table with severity and fixes
- Verification plan
