---
name: testing
description: Cross-cutting testing guidance for Go, Python, and Rust projects. Covers table-driven tests, async test patterns, Redis mocking, coverage targets, CI integration, and security-focused test cases. Use when writing tests, reviewing test coverage, or setting up CI test pipelines.
---

# Testing Skill

## Go Testing

- Standard `testing` package — no external test frameworks (testify is acceptable for assertions, not required).
- Table-driven tests with `[]struct` and `t.Run()` for named sub-tests. Every test case gets a descriptive name.
- `httptest.NewServer` for HTTP handler tests — never start real servers in unit tests.
- `httptest.NewRecorder` for testing individual handlers without a full server.
- Always run with `-race` flag — data races are bugs, not warnings.
- Coverage: `-covermode=atomic` (required for `-race` compatibility). `-coverprofile=coverage.out`.
- `t.Fatalf` for setup failures that prevent further testing. `t.Errorf` for assertion failures (allows other assertions to run).
- `t.Helper()` on all test helper functions — fixes line number reporting in failure output.
- `t.Cleanup()` for teardown instead of `defer` in tests — register cleanup alongside setup, runs after subtests, avoids `defer` in loops, and gives consistent cleanup ordering.
- `t.Parallel()` for independent tests — but never on tests sharing mutable state (Redis, filesystem).

## Python Testing

- pytest exclusively — no `unittest.TestCase` subclasses.
- `asyncio_mode = "auto"` in `pyproject.toml` — no need for `@pytest.mark.asyncio` on every async test.
- `pythonpath = ["src"]` in pytest config (e.g. under `[tool.pytest.ini_options]`) — ensures `src/<pkg>/` layout imports work.
- `conftest.py` for shared fixtures. One at `tests/conftest.py`, additional per-directory as needed.
- `autouse=True` fixtures for test isolation (e.g. clearing environment variables before each test).
- `fakeredis` for Redis mocking — drop-in replacement, no real Redis needed.
- `@pytest.mark.parametrize` for table-driven tests — Python equivalent of Go table-driven pattern.
- `monkeypatch` fixture for environment variables — `monkeypatch.setenv`, `monkeypatch.delenv`.
- `tmp_path` fixture for filesystem tests — auto-cleaned, unique per test.
- Never use `print()` for test debugging — use `pytest -s` to see stdout, or `capfd`/`capsys` fixtures.

## Rust Testing

- Unit tests in `#[cfg(test)] mod tests` within the source file — co-located with implementation.
- Integration tests in `tests/` directory — these test the public API via `use <crate>::*`.
- Shared test utilities in `tests/common/mod.rs` — imported with `mod common;` from integration tests.
- `#[tokio::test]` for async tests — defaults to current-thread runtime, use `#[tokio::test(flavor = "multi_thread")]` when testing concurrent behaviour.
- `reqwest::Client` for HTTP integration tests against a real server started on a random port.
- External-dependency tests: prefer `#[ignore = "requires <service>/env"]` with a clear reason, or gate via `#[cfg(feature = "external-deps")]` / a separate integration-test binary instead of returning early based on environment variables.
- `assert_eq!` for value comparison (shows both values on failure), `assert!` for boolean conditions.
- `#[should_panic(expected = "...")]` for panic tests — always include the `expected` substring.
- `[dev-dependencies]` in `Cargo.toml` for test-only crates — these do not affect production binary.

## Redis Mocking

- Go: `alicebob/miniredis/v2` — in-memory Redis server, supports most commands. Start with `miniredis.Run()`, close in `t.Cleanup()`.
- Go time: `mr.FastForward(duration)` to simulate TTL expiry without real sleeps.
- Python: `fakeredis.FakeRedis()` or `fakeredis.aioredis.FakeRedis()` for async — drop-in for `redis.Redis`.
- Always test failure paths: call `mr.Close()` (Go) or replace the client with a connection-refused mock (Python) to simulate Redis unavailability.
- Test concurrent access: use goroutines (Go) or `asyncio.gather` (Python) to verify atomic operations (e.g. one-time CSRF token consumption).
- Key isolation: use unique key prefixes per test to prevent cross-test contamination when tests share a mock instance.

## Security Test Coverage

Every authentication/authorisation feature must have tests for:

- **Valid path**: correct credentials accepted, expected claims/response returned.
- **Invalid path**: wrong credentials rejected with appropriate error code.
- **Expired**: time-based tokens rejected after expiry. Use `FastForward` (Go) or `freezegun` (Python).
- **Tampered**: modified tokens, altered signatures, changed claims — all rejected.
- **Concurrent**: multiple simultaneous requests for one-time tokens — exactly one succeeds.
- **Dependency failure**: Redis down, RPC unreachable, key file missing — fail-closed behaviour verified.
- **Boundary**: empty strings, maximum length inputs, unicode, null bytes, special characters.
- **Replay**: one-time tokens cannot be reused. Second use returns error.
- **Key rejection**: wrong algorithm, wrong key, expired key — all rejected cleanly.

## Coverage Targets

- Go: `-covermode=atomic -coverprofile=coverage.out`. View with `go tool cover -html=coverage.out`.
- Python: `--cov=src/<pkg> --cov-report=term-missing`. Config in `pyproject.toml`: `branch = true`.
- Rust: `cargo llvm-cov` or `cargo tarpaulin` for coverage reporting.
- Progressive targets: 72% baseline (current) -> 80% M1 -> 85% M2 -> 90% M3.
- Prioritise security code paths first — auth, crypto, session handling must be at or above target.
- Coverage is necessary but not sufficient — 100% line coverage with no assertions is worse than 80% with thorough assertions.
- Branch coverage (`branch = true`) catches untested conditional paths that line coverage misses.

## Test Organisation

- Go: `_test.go` files co-located with source in the same package. Test package can be `<pkg>_test` for black-box testing.
- Python: `tests/test_<module>.py` mapping to `src/<pkg>/<module>.py`. Shared fixtures in `tests/conftest.py`.
- Rust: unit tests in `#[cfg(test)]` blocks within source files. Integration tests in `tests/` directory.
- Solidity: `forge test` — test files in `test/` directory with `Test` suffix.
- Name tests descriptively: `TestCSRFToken_ExpiredToken_ReturnsError` (Go), `test_csrf_token_expired_returns_error` (Python).
- Group related tests: `t.Run()` sub-tests (Go), parametrize (Python), nested `mod tests` (Rust).

## CI Integration

- Lint before test — fail fast on formatting/style before spending time on tests.
- Go: `test -z "$(gofmt -l .)" && go vet ./... && golangci-lint run && go test -race -covermode=atomic -coverpkg=./... -coverprofile=coverage.out ./...`
- Python: `ruff check . && ruff format --check . && pytest --cov --cov-report=term-missing`
- Rust: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`
- Coverage artifacts: upload `coverage.out` (Go), `.coverage` (Python) for CI reporting.
- Tests on every PR push and on push to main — no exceptions.
- Docker build gated on tests: build step depends on test step passing.
- Separate test and build stages — test failures should not produce Docker images.

## Concurrency Testing

- Go: launch N goroutines that each attempt the same one-time operation. Collect results via error channel. Assert exactly one success, N-1 failures.
- Python: `asyncio.gather(*[consume_token(token) for _ in range(N)])` — verify exactly-once semantics.
- Redis atomic DEL: verify that concurrent `DEL` on the same key results in exactly one `1` return and the rest `0`.
- Use `sync.WaitGroup` (Go) or `asyncio.Barrier` (Python) to synchronise goroutine/task start for maximum contention.
- Race detection: Go `-race` flag catches data races at runtime. Enable unconditionally in CI.
- Flaky test policy: concurrent tests that fail intermittently indicate a real bug — investigate, do not skip.

## Anti-Patterns to Flag

- Tests without assertions (coverage padding)
- `time.Sleep` in tests instead of `FastForward`, `freezegun`, or channel synchronisation
- Tests that depend on execution order or shared mutable state
- Ignoring `-race` flag in Go CI
- `unittest.TestCase` in a pytest project (mixing frameworks)
- `#[ignore]` without a reason string (use `#[ignore = "reason"]` to document why)
- Coverage targets enforced only on new code, not overall (allows rot)
- Testing implementation details instead of behaviour (brittle tests)
- Missing failure-path tests for security-critical code
- Mocking too much — mock boundaries (Redis, HTTP), not internal functions
- `assert True` or `assert result` without checking the actual value
- Tests that pass when the feature is broken (false positives)
