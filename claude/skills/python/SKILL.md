---
name: python
description: Python development patterns for async services, Slack bots, and Web3 applications. Covers pyproject.toml configuration, ruff linting, pytest setup, structlog logging, pydantic validation, and Docker builds. Use when writing Python code, reviewing Python PRs, or configuring Python tooling.
---

# Python Skill

## Project Structure

- `src/<pkg>/` layout with `__init__.py` in each package directory.
- `pyproject.toml` as single source of truth — no `setup.py`, no `setup.cfg`.
- `tests/` directory at project root with `conftest.py` for shared fixtures.
- `requirements.txt` for pinned production dependencies. `requirements-dev.txt` for dev/test dependencies.
- `Makefile` with standard targets: `test`, `lint`, `format`, `clean`, `docker-build`.
- Entry points defined in `pyproject.toml` under `[project.scripts]` — not as standalone scripts.

## pyproject.toml

- Single file for all tool configuration: pytest, ruff, coverage, project metadata.
- pytest config under `[tool.pytest.ini_options]`: `asyncio_mode = "auto"`, `pythonpath = ["src"]`.
- ruff config under `[tool.ruff]`: `line-length = 100`, `target-version = "py311"`.
- Coverage config under `[tool.coverage.run]`: `source = ["src/<pkg>"]`, `branch = true`.
- Project metadata: `requires-python = ">=3.11"`, abstract dependencies declared in `[project.dependencies]`. Use `requirements.txt` for pinned/locked versions (generated from or consistent with `pyproject.toml`).
- Build system: `[build-system]` with `hatchling` or `setuptools` backend.

## Async Patterns

- `asyncio` for concurrent I/O operations. `async def` for coroutines, `await` for suspension points.
- `asyncio.gather()` for concurrent task execution — use `return_exceptions=True` when partial failure is acceptable.
- Task cancellation: handle `asyncio.CancelledError` for graceful cleanup. Never swallow cancellation silently.
- `asyncio.create_task()` for fire-and-forget background work — store a reference if you need to later cancel, await, or handle exceptions from the task.
- Event loops: never call `asyncio.run()` inside an already-running loop. Use `await` instead.
- Timeouts: `asyncio.wait_for(coro, timeout=N)` or `async with asyncio.timeout(N):` (Python 3.11+).

## Ruff Linting

- `ruff check` for linting + `ruff format` for formatting. Replaces both `black` and `flake8`.
- Rule sets: `E` (pycodestyle errors), `F` (pyflakes), `I` (isort), `W` (pycodestyle warnings) as baseline.
- `ruff check --fix` for auto-fixable issues. `ruff format` is opinionated with limited configuration (e.g., line length, quote style).
- CI command: `ruff check . && ruff format --check .` — fail fast on lint before running tests.
- No `black`, no `flake8`, no `isort` as separate tools — ruff replaces all three.
- Quote style: configure `quote-style = "double"` in `[tool.ruff.format]` for consistency.

## Pydantic and Config

- Environment-based configuration using Pydantic settings: for Pydantic v1 use `pydantic.BaseSettings`; for Pydantic v2 install `pydantic-settings` and use `pydantic_settings.BaseSettings`; or use plain dataclasses with env parsing.
- `.env` files for local development — NEVER committed to version control. Add to `.gitignore`.
- Typed config classes: all configuration values have explicit types and defaults where appropriate.
- Validation: pydantic validates on construction. Use validators (`@validator` in v1, `field_validator` in v2) for custom rules.
- Test isolation: `monkeypatch.setenv` / `monkeypatch.delenv` in fixtures. `autouse=True` fixtures for clearing env state.
- Secrets in config: load from environment variables or mounted files, never from `.env` in production.

## Testing with pytest

- `conftest.py` for shared fixtures. One at `tests/conftest.py`, additional per-subdirectory as needed.
- `autouse=True` fixtures for test isolation — e.g. clearing `TIDE_*`, `SLACK_*`, `REDIS_*` env vars before each test.
- `fakeredis` for Redis mocking — `fakeredis.FakeRedis()` sync or `fakeredis.aioredis.FakeRedis()` async.
- `@pytest.mark.parametrize` for table-driven tests. Name test IDs descriptively.
- `monkeypatch` fixture for environment variables, attribute patching, and dictionary mutation.
- `tmp_path` fixture for filesystem tests — auto-cleaned, unique per test.
- `capfd` / `capsys` for capturing stdout/stderr output in tests.
- Test file naming: `tests/test_<module>.py` mapping to `src/<pkg>/<module>.py`.

## Logging with structlog

- Structured key-value logging: `structlog.get_logger()` returns a bound logger.
- Context binding: `logger.bind(user_id=uid)` for request-scoped context. Propagates through call chain.
- Lazy formatting: pass values as keyword arguments, not f-strings — `logger.info("token issued", user=uid)` not `logger.info(f"token issued for {uid}")`.
- Log levels: `debug` for development detail, `info` for operational events, `warning` for recoverable issues, `error` for failures.
- Processors: configure `structlog.dev.ConsoleRenderer()` for local dev, `structlog.processors.JSONRenderer()` for production.
- Never log secrets, tokens, or credentials — even at debug level.

## Docker Builds

- Base image: `python:3.11-slim` for production. Never `python:3.11` (full image is 900MB+).
- Multi-stage: builder stage installs dependencies, runtime stage copies only installed packages.
- `PYTHONUNBUFFERED=1` for immediate log output (no buffered stdout).
- `--no-cache-dir` on all `pip install` commands to reduce image size.
- Non-root user: `RUN useradd -r -u 10001 appuser` then `USER appuser` before `CMD`.
- Copy `requirements.txt` and install before copying source — leverages Docker layer caching.
- `CMD ["python", "-m", "<pkg>"]` using module execution for proper import resolution.

## Dependency Management

- Pinned versions in `requirements.txt`: `package==1.2.3`, not `package>=1.2.3`.
- Separate `requirements-dev.txt` for test/lint tools: `-r requirements.txt` at top to include production deps.
- No `pip install -e .` in Docker containers — install normally for reproducible builds.
- `pip-audit` in CI to check for known vulnerabilities (install via `pip install pip-audit`).
- Update strategy: patch versions freely, minor with changelog review, major with testing.
- `pip freeze > requirements.txt` from a clean virtualenv to capture exact versions.

## Anti-Patterns to Flag

- `setup.py` or `setup.cfg` in new projects (use `pyproject.toml`)
- `black` or `flake8` or `isort` as separate tools (ruff replaces all three)
- `print()` for logging in production code (use structlog)
- f-strings in log calls (defeats lazy formatting and structured logging)
- `.env` files committed to version control
- `pip install -e .` in Dockerfiles (non-reproducible)
- `asyncio.run()` inside an already-running event loop
- `PYTHONUNBUFFERED` not set in Docker containers (buffered logs lost on crash)
- `unittest.TestCase` subclasses in a pytest project (mixing frameworks)
- Unpinned dependencies in `requirements.txt` (`>=` without upper bound)
