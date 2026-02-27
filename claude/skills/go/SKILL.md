---
name: go
description: Go development patterns for HTTP services, WASM plugins, and Redis-backed applications. Covers project structure, error handling, gorilla/mux routing, Prometheus metrics, Makefile targets, and Docker multi-stage builds. Use when writing Go code, reviewing Go PRs, or setting up Go project infrastructure.
---

# Go Skill

## Project Structure

- `cmd/server/main.go` for the application entry point. Minimal — parse flags, initialise dependencies, start server.
- `pkg/<domain>/` for domain logic packages. Each package owns its types, handlers, and tests.
- `go.mod` at repository root. Module path matches the GitHub repo (e.g. `github.com/<owner>/<repo>`).
- Makefile with standard targets: `help`, `build`, `test`, `lint`, `clean`, `docker-build`, `docker-push`.
- `internal/` for packages that must not be imported by external consumers.
- Keep `main.go` thin — it wires dependencies together and does not implement business logic.

## Error Handling

- Return `error` as the last return value. Always check returned errors — never discard with `_`.
- Wrap errors with context: `fmt.Errorf("failed to create token: %w", err)`. Use `%w` for wrapping (enables `errors.Is`/`errors.As`).
- Define domain-specific sentinel errors: `var ErrTokenExpired = errors.New("token expired")`. Check with `errors.Is(err, ErrTokenExpired)`.
- Never `panic` in library code. Reserve `panic` for truly unrecoverable states in `main`.
- Never use `log.Fatal` in library code — it calls `os.Exit(1)` and skips deferred cleanup.
- Return early on error (guard clauses) — avoid deep nesting of success paths.
- Custom error types implement `Error() string`. Use `errors.As` for type-based matching.

## HTTP Service Patterns

- `gorilla/mux` for routing — supports path variables, method matching, middleware chaining.
- `httptest.NewServer` and `httptest.NewRecorder` for handler testing — never bind real ports in unit tests.
- JSON responses: `json.NewEncoder(w).Encode(resp)` with `w.Header().Set("Content-Type", "application/json")` before writing.
- Set `Content-Type` before `WriteHeader` — headers sent after `WriteHeader` are silently dropped.
- `/healthz` endpoint returning 200 for liveness probes. `/readyz` for readiness (check dependencies).
- `/metrics` endpoint via `promhttp.Handler()` for Prometheus scraping.
- `http.MaxBytesReader` on request bodies to prevent oversized payloads.
- Graceful shutdown: `http.Server.Shutdown(ctx)` with a timeout context on SIGTERM/SIGINT.

## Redis Integration

- `go-redis/v9` client with context-based operations (every call takes `context.Context`).
- Key prefixing by domain: `revoked:<jti>`, `csrf:<token>`, `rate:<client>`. Prevents key collisions.
- TTL on all keys — no unbounded key growth. Match TTL to the resource lifetime (e.g. token expiry).
- Atomic `DEL` for one-time token consumption: `DEL` returns 1 if deleted, 0 if absent. Use the return value, not a separate `GET` + `DEL`.
- Connection pooling: configure `PoolSize`, `MinIdleConns`, and `DialTimeout` for production workloads.
- Fail-closed on Redis errors: if Redis is unreachable, deny operations that depend on Redis state (revocation checks, CSRF validation).
- Test with `alicebob/miniredis/v2` — in-memory Redis, supports `FastForward` for TTL testing.

## Prometheus Metrics

- `prometheus/client_golang` for instrumentation. Define metrics as package-level `var`s, then either register them explicitly during setup (e.g. in `main`) or use `promauto` for auto-registration (avoid unnecessary `init()` side effects).
- Counter for events (requests served, tokens issued, errors). Histogram for latencies (request duration, Redis round-trip).
- Bounded label cardinality: use fixed label values (HTTP method, status code class). Never use unbounded values (user ID, token JTI) as labels.
- Expose via `promhttp.Handler()` on `/metrics`. Separate from the application router if needed.
- Metric naming: `<namespace>_<subsystem>_<name>_<unit>` (e.g. `jwt_auth_requests_total`, `jwt_auth_request_duration_seconds`).
- Register custom collectors only if default Go runtime metrics are insufficient.

## WASM Build

- Build target: `GOOS=wasip1 GOARCH=wasm` for WASI-compatible modules.
- `proxy-wasm-go-sdk` for Envoy/Istio WASM plugins — implements the proxy-wasm ABI.
- No external runtime dependencies — WASM modules must be self-contained. No CGO, no filesystem access.
- Fail-closed on host call errors: if the host (Envoy) returns an error from a host call, deny the request.
- Validate with `wasm-validate` after build to catch ABI issues before deployment.
- Keep WASM module size small — strip debug info, avoid unnecessary imports.

## Module Hygiene

- `go mod tidy` after adding/removing dependencies. Commit both `go.mod` and `go.sum`.
- Pin dependencies to release tags (e.g. `v1.2.3`), not branches or commit SHAs.
- Avoid `replace` directives in committed code — they break consumers. Use only for local development.
- `go mod verify` in CI to detect tampered dependencies.
- Update strategy: patch versions freely, minor with changelog review, major with testing.
- `govulncheck ./...` in CI to catch known vulnerabilities in dependencies.

## Docker Multi-Stage

- Builder stage: `golang:1.24-alpine` with `CGO_ENABLED=0` for static binaries.
- Runtime stage (Alpine): version-pinned Alpine (e.g. `alpine:3.21`). Never `:latest`.
- Runtime stage (distroless): version-pinned distroless image (e.g. `gcr.io/distroless/static:nonroot`) when you don't need a shell or package manager.
- Non-root user (Alpine): `RUN adduser -D -u 10001 appuser` in the runtime stage, then `USER appuser` before `ENTRYPOINT`.
- Non-root user (distroless): run as a numeric UID/GID, e.g. `USER 10001:10001`; if you need `/etc/passwd`, copy a pre-created file from the builder stage.
- Only `ca-certificates` needed in runtime for TLS connections.
- Copy only the compiled binary from builder — no source code, no toolchain in production.
- `ENTRYPOINT ["/app"]` with exec form (not shell form) for proper signal handling.

## Linting

- `gofmt` is non-negotiable — all Go code must be formatted. CI check: `test -z "$(gofmt -l .)"`.
- `go vet ./...` for static analysis of common mistakes (printf format strings, unreachable code, etc.).
- `golangci-lint run` with default linters for comprehensive analysis.
- CI order: format check, vet, lint, test. Fail fast on formatting before spending time on tests.
- `goimports` for import grouping: stdlib, external, internal. Consistent import ordering.

## Anti-Patterns to Flag

- `panic` or `log.Fatal` in library/package code (only acceptable in `main`)
- Discarding errors with `_ = someFunc()` without explicit justification
- `fmt.Errorf("...: %s", err)` instead of `%w` (breaks `errors.Is`/`errors.As` chain)
- Unbounded label cardinality in Prometheus metrics (user IDs, JTIs, request paths as labels)
- `replace` directives committed to `go.mod` (breaks downstream consumers)
- Missing `Content-Type` header on JSON responses
- `go.sum` not committed (non-reproducible builds)
- `CGO_ENABLED=1` in container builds without explicit justification
- Separate `GET` + `DEL` instead of atomic `DEL` for one-time token consumption
- `:latest` tags on base images in Dockerfiles
