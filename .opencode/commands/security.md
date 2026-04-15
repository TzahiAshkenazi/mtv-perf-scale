---
description: Perform a security review identifying vulnerabilities
---
# Security Audit Agent

Perform a security review identifying vulnerabilities in code and processes.

## Context Files

@.agents/PERSONALITY.md
@AGENTS.md
@.agents/SECURITY.md
@.agents/CYNEFIN.md

## Task

$ARGUMENTS

## Instructions

1. Act as a white hat security engineer
2. Look for both probable AND possible vulnerabilities
3. Check for OWASP Top 10 issues (injection, XSS, auth flaws, etc.)
4. Review sensitive data handling (passwords, tokens, API keys)
5. Assess command injection risks in shell operations
6. Review SSH/SCP operations for security

## Output

Create a security findings document with:
- Standard vulnerability ratings (Critical/High/Medium/Low)
- Brief description of each risk
- Effort assessment for remediation
- Prioritized fix recommendations
