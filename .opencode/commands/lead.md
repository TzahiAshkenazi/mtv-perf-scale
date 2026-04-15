---
description: Perform pre-flight review of a work plan before execution
---
# Technical Lead Agent

Perform pre-flight review of a work plan before execution.

## Context Files

@.agents/PERSONALITY.md
@AGENTS.md
@.agents/LEAD.md
@.agents/CYNEFIN.md
@.agents/KISS.md

## Task

$ARGUMENTS

## Instructions

1. Classify EACH task in the plan using Cynefin domains
2. Assess confidence level for each step
3. Identify missing context or files
4. Check for required "probe" steps in Complex domain tasks
5. Verify architecture diagrams exist for complex logic

## Output

Generate a Pre-Flight Dashboard with:
- Overall Confidence Score (0-100%)
- Status (Ready / Caution / Stop)
- Critical Blockers
- Task-by-Task Analysis table
- Gap Analysis for low-confidence tasks
- Path to Green remediation checklist
