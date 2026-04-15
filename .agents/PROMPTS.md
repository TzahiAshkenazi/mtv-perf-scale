- # Prompt Engineering & AI Tool Integration Principle

## Core Principle: Describe Data, Not Tools
When writing prompts or system instructions for AI models that use function calling:
- ❌ **NEVER** list explicit tool/function names in prompts (e.g., "use report_portal_get_test_launches")
- ❌ **NEVER** show "FORBIDDEN" or "don't do this" examples - models learn patterns from ALL examples, including negative ones
- ✅ **DO** describe the DATA or TASK needed (e.g., "get test launches for bundle X", "check pod logs")
- ✅ **DO** let the model discover appropriate tools from its tool declarations

**Rationale**: Models learn patterns from examples. Showing explicit function names or "wrong" syntax teaches the model to reproduce those patterns as text output instead of using native function calling APIs.

## Systematic Fix Verification
After identifying and fixing an issue:
1. **Board Sweep**: Always ask "Are there other locations with the same issue?" and use grep/search systematically
2. **Build Verification**: Always verify builds pass before committing (`uv run pytest tests`)
3. **Multi-Repo Awareness**: Changes often span both code repos and GitOps config repos - coordinate commits

## Code Review Pattern
When reviewing code changes:
1. Create formal review documents with severity levels (HIGH/MEDIUM/LOW)
2. Verify each issue exists before fixing
3. Track technical debt items that aren't fixed immediately
4. Provide clear commit messages for each repo affected
