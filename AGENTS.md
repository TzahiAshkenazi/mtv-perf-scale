# AGENTS.md

## Commands

```bash
# Run deployer
uv run python -m {MODULE} --config config.yml
uv run python -m {MODULE} --config config.yml --phase deploy

# Tests
uv run pytest
uv run pytest tests/path.py::TestClass::test_method -v

# Lint
pre-commit run --all-files
```

## Architecture

**Key modules:**

**Key abstractions:**

**Environment variables:**

## Mandatory Rules

1. **Use `uv run` for all Python** - Never bare `python` or `pytest`
2. **Variable names ≥3 chars** - Except `i`, `j`, `x` in comprehensions/lambdas
3. **No import aliases without user confirmation**
4. **Shared code → `utilities/`** - Extract when logic appears in 2+ modules
5. **Max 500 lines per module**
6. **No inline scripts via SSH** - Never embed Python/Bash scripts in SSH commands. Instead:
   - Create a separate script file in `scripts/`
   - SCP the script to the remote host
   - Execute via SSH, then clean up
7. **No heredocs for remote file writes** - Use `tempfile.NamedTemporaryFile` + `scp_put()`
8. **Tempfile with context management** - Always use `with tempfile.NamedTemporaryFile(...) as f:` pattern. Never use `tempfile.mkstemp()` with manual `os.unlink()`
9. **Build paths with `os.path.join()`** - When constructing paths involving variables or function calls, use `os.path.join()`. Hardcoded absolute paths like `Path("/var/run/ocp-deployer")` are acceptable. For parent directory navigation, use `Path(__file__).parent` (not `os.pardir`). Example: `Path(os.path.join(Path(__file__).parent.parent, "scripts", "file.py"))`
10. **Use `.test` TLD in tests (RFC 2606)** - Use `example.test` in test files, not `example.com`. The `.test` TLD is reserved for testing and will never resolve. Use `example.com` only in documentation and user-facing examples.
11. **Imports at top of file** - All imports must be at the top of the file unless absolutely necessary (e.g., circular import prevention). Do not create unnecessary intermediate variables for imported modules - use `module.function()` directly. Do not rename imports (e.g., `import foo as f`) unless necessary - use the full import path when needed.

## Code Style

- Line length: 120 chars
- Max file length: 500 lines
- Python 3.14+, type hints enforced (mypy)
- 90% test coverage required
- Use `from __future__ import annotations`
- Keep `__init__.py` files empty

## Sensitive Information

- Use sensitive=True to suppress logging
- Sanitize data before exposing in errors

Never log passwords, tokens, API keys, or commands containing them.

## References

Directories:
[.agents/](.agents/) Directory contains all persona information
