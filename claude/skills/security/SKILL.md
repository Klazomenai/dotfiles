---
name: security
description: Cross-cutting security guidance for authentication, authorisation, secrets management, container hardening, input validation, and cryptographic operations. Use when reviewing code for security concerns, handling secrets, configuring authentication, or hardening containers and services.
---

# Security Skill

## JWT Security

- Algorithm: RS256 with RSA-2048 minimum key size. NEVER allow HS256 with shared secrets for service-to-service auth.
- Reject `alg:none` explicitly — validate the `alg` header before parsing claims.
- Short-lived tokens: 1 hour max for access tokens, 15 minutes for child/scoped tokens, 30 days max for parent/refresh tokens.
- JTI (JWT ID) is mandatory for revocable tokens — store revoked JTIs in Redis with TTL matching token expiry.
- Validate `aud` (audience) and `iss` (issuer) on every verification — never skip these claims.
- Claims must be typed: `network`, `rate_limit`, `user_id`, `token_type`, `parent_jti` — reject tokens with unexpected claim types.
- Key rotation: support JWKS endpoint (`/.well-known/jwks.json`) for public key distribution. Multiple keys via `kid` header.
- Parse with `golang-jwt/v5` (Go) or equivalent maintained library — never hand-roll JWT parsing.

## CSRF Protection

- Redis-backed one-time tokens: generate with `crypto/rand`, store in Redis with TTL cap (e.g. 1 hour).
- Consume via atomic `DEL` — if DEL returns 0, the token was already used or expired. Reject.
- Fail-closed on Redis errors: if Redis is unreachable, deny the request. Never fall back to "allow".
- Token format: hex-encoded 32 bytes minimum. Never use predictable values (timestamps, sequential IDs).
- Bind CSRF tokens to the user session — a token generated for session A must not validate for session B.
- Double-submit pattern: token in both cookie (HttpOnly=false for JS access) and request header/body.

## SIWE Authentication

- Verify EIP-191 signatures using the `siwe` crate (Rust) or equivalent — never hand-roll signature recovery.
- Nonce freshness: generate server-side, store with TTL, consume on verification (one-time use).
- Bind to SIWE message domain (`message.domain`) and chain ID (`message.chain_id`) — reject mismatches.
- Validate `issued-at` and `expiration-time` fields — reject expired or future-dated messages.
- Contract-based authorisation: after signature verification, check on-chain access control (e.g. `IKeyRAAccessControl.hasAccess`).
- Address recovery must match the claimed address exactly — use checksum comparison (EIP-55).

## Secret Handling

- NEVER inline sensitive values in command arguments — they leak to shell history, process tables, and logs.
- Use `export VAR=value` as a separate step, or ask the user to set environment variables themselves.
- Kubernetes secrets: create with `--from-file=` or `--from-env-file=` (or stdin-based tooling). Avoid `--from-literal=` for sensitive values because it exposes secrets via process arguments.
- RSA private keys: mount from PVC or Vault-injected volume. Never pass as environment variables (size limits, logging risk).
- Never run `kubectl get secret -o yaml` — base64 is not encryption, and the output may be logged.
- Terraform sensitive vars: use `TF_VAR_*` environment variables, never `-var` flags with inline values.
- Git: never commit `.env`, `credentials.json`, private keys, or bearer tokens. Use `.gitignore` and pre-commit hooks.

## Input Validation

- JWT format: verify 3 dot-separated parts before any parsing. Reject malformed tokens early.
- Base64url decoding: decode header and payload independently. Reject non-base64url characters.
- Ethereum addresses: validate checksum (EIP-55) before use. Reject non-checksummed addresses in security contexts.
- HTTP body size: enforce limits at the framework level (e.g. `http.MaxBytesReader` in Go, body size middleware).
- Claims type safety: unmarshal into typed structs, not `map[string]interface{}`. Reject unknown fields where possible.
- Path traversal: treat all user-supplied paths as untrusted. Join them against an allowed base directory, use `filepath.Clean` (Go) or equivalent on the joined path, and reject absolute paths or any resolved path that escapes the base (including via symlinks).

## Container Hardening

- Multi-stage builds: separate builder stage from runtime. Builder has toolchain, runtime has binary only.
- Non-root execution: `adduser -D -u 10001 appuser` in Alpine, `USER appuser` in Dockerfile.
- Minimal base images: version-pinned Alpine (e.g. `alpine:3.21`) or `distroless`, ideally digest-pinned. Never `ubuntu` or `debian` for production services. Never `:latest` tags — mutable tags are a supply chain risk.
- Go binaries: `CGO_ENABLED=0` for static linking. Only `ca-certificates` needed in runtime stage.
- Rust binaries: static linking via `x86_64-unknown-linux-musl` target or Nix `pkgsStatic`.
- No shell in production containers where possible — reduces attack surface for container escape.
- Read-only filesystem: set `readOnlyRootFilesystem: true` in Kubernetes security context.

## Fail-Closed Design

- Auth service unreachable: deny request. Never fall through to "allow" on connectivity failure.
- Redis errors (connection refused, timeout): deny the operation that depends on Redis state (token revocation check, CSRF validation, rate limiting).
- Smart contract call failure (RPC error, revert): deny access. Log the error, but do not grant access on uncertainty.
- Istio AuthorizationPolicy: use `ALLOW`-only policies so that non-matching requests are implicitly denied; explicitly enumerate known-good paths only.
- ExtAuthz failure mode: configure Envoy with `failure_mode_allow: false` (or Istio with `failureModeAllow: false`) to fail closed. Never configure it to allow on failure.
- Rate limiter failure: if rate limit state is unavailable, apply the most restrictive limit.

## Session Security

- HMAC-SHA256 signed cookies: `session_data|timestamp|HMAC(session_data|timestamp, secret)`.
- Server-side TTL: sessions expire based on server clock, not client-supplied expiry.
- Tamper detection: recompute HMAC on every request. Reject if signature does not match.
- Cookie attributes: `Secure` (HTTPS only), `HttpOnly` (no JS access), `SameSite=Strict` or `Lax`.
- Session ID entropy: minimum 32 bytes from cryptographic RNG.
- Invalidation: server-side session store with explicit delete on logout. Do not rely solely on cookie expiry.

## Cryptographic Operations

- RSA key size: 2048-bit minimum. 4096-bit for long-lived keys (>1 year).
- Random number generation: `crypto/rand` (Go), `rand::rngs::OsRng` or `rand::thread_rng` (Rust; both are CSPRNGs, prefer `OsRng` for direct OS entropy), `secrets` module (Python). NEVER `math/rand` or `random` module for security.
- Entropy: 32 bytes minimum for tokens, nonces, and session identifiers.
- Key encoding: PKCS#1 for RSA-specific interop, PKIX/SPKI for general public key distribution. Be explicit about which format.
- Hash functions: SHA-256 minimum for HMAC and signatures. No MD5 or SHA-1 in any security context.
- Constant-time comparison: use `hmac.Equal` (Go), `constant_time_eq` crate (Rust), `hmac.compare_digest` (Python) for secret comparison.

## Dependency Auditing

- Go: `govulncheck ./...` in CI. Review advisories before updating.
- Python: `pip audit` or `safety check`. Pin all dependencies in `requirements.txt`.
- Rust: `cargo audit` in CI. Review `RUSTSEC` advisories.
- Update strategy: patch versions freely, minor versions with changelog review, major versions with testing.
- Transitive dependencies: audit the full dependency tree, not just direct dependencies.
- Container base images: rebuild regularly to pick up OS-level security patches. Pin digest, not just tag.

## Anti-Patterns to Flag

- `alg:none` accepted or `alg` header not validated before JWT parsing
- HS256 with shared secrets for service-to-service authentication
- Secrets passed as CLI arguments or command flags, or secrets committed into scripts via inline environment variable assignments (for example, checked-in `export VAR=...` or `VAR=... cmd`)
- `math/rand` (Go) or `random` module (Python) for security-sensitive values
- Missing `aud`/`iss` validation on JWT verification
- `failure_mode_allow: true` (or missing explicit `false`) in ExtAuthz/auth proxy configuration
- CSRF tokens that are not one-time use (no atomic consume)
- Redis errors silently ignored in auth/security code paths
- Container running as root or with writable root filesystem
- `kubectl get secret -o yaml` in any context
- Hardcoded secrets, API keys, or private keys in source code
- Missing rate limiting on authentication endpoints
- Session cookies without `Secure`, `HttpOnly`, or `SameSite` attributes
- SHA-1 or MD5 used in any security context (signatures, HMAC, token generation)
- Base64 encoding treated as encryption or obfuscation
