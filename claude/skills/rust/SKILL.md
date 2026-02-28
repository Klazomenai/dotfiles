---
name: rust
description: Rust development patterns for async HTTP services, Ethereum/SIWE authentication, Foundry Solidity contracts, and Nix-based OCI builds. Covers tokio/hyper server patterns, alloy contract interaction, error handling, and integration testing. Use when writing Rust code, reviewing Rust PRs, or configuring Cargo/Foundry tooling.
---

# Rust Skill

## Project Structure

- `src/main.rs` for the entry point. Minimal — parse env vars, build config, start server.
- `src/lib.rs` for the core library. Required for integration tests to import via `use <crate>::*`.
- `src/auth.rs` (or domain modules) for business logic. Keep handlers and domain logic separate.
- `tests/` directory for integration tests. Each file is a separate test binary.
- `tests/common/mod.rs` for shared test utilities — imported with `mod common;` from integration test files.
- `Cargo.toml` with `[dev-dependencies]` for test-only crates (reqwest, tokio-test, etc.).
- `Cargo.lock` always committed — required for reproducible builds of binaries and services.

## Async HTTP (tokio/hyper)

- `#[tokio::main]` with multi-thread runtime (default). Use `#[tokio::main(flavor = "current_thread")]` only for single-threaded WASM or constrained environments.
- hyper 1.x with `http1::Builder` for HTTP/1.1 services. Use `hyper-util` for `TokioIo` adapter.
- Per-connection tasks: `tokio::spawn` a new task for each accepted TCP connection.
- State sharing: `Arc<AppState>` cloned into each spawned task. Never use global mutable state.
- `service_fn` for functional request handling — maps `Request` to `Future<Output = Result<Response, E>>`.
- Health endpoint: `/healthz` returning 200 with `text/plain` body for liveness probes.
- Random port in tests: bind to `127.0.0.1:0` and read `listener.local_addr()` for the assigned port.
- Response helpers: centralise response construction with Content-Type, CSP headers, and security headers (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`).
- Graceful shutdown: use `tokio::signal::ctrl_c()` or a `CancellationToken` to cancel the accept loop and call `graceful_shutdown()` on active connections.

## Ethereum Integration (alloy)

- `sol!` macro with `#[sol(rpc)]` for type-safe contract interfaces — generates call builders from Solidity signatures.
- `ProviderBuilder::new().connect_http(url)` for read-only calls. Add `.wallet(EthereumWallet::from(signer))` for transactions.
- `PrivateKeySigner` for local signing. Never hardcode private keys — load from environment or mounted files.
- Contract calls: `contract.methodName(args).call().await` for view functions, `.send().await` for state-changing.
- `Address::ZERO` as sentinel for "not configured" — check before making contract calls.
- Chain ID validation: verify `chain_id` in SIWE messages matches expected network. Reject mismatches.
- Error handling: `map_err` to convert `alloy::contract::Error` into domain-specific error types.
- Deployment in tests: load bytecode from `include_str!` on forge artifacts, encode constructor args, use `send_transaction`.

## SIWE Authentication

- `siwe` crate for EIP-4361 message parsing. `message.verify_eip191(&sig_bytes)` for signature verification.
- Signature format: 65 bytes (r=32, s=32, v=1). Convert with `try_into::<[u8; 65]>()`, reject if wrong length.
- Nonce generation: 16+ bytes from `rand::thread_rng().gen::<[u8; 16]>()`, hex-encoded. One-time use, server-generated.
- SIWE message fields: validate `domain`, `chain_id`, `issued_at`, `expiration_time`. Reject mismatches or expired messages.
- Session format: `address|expiry|base64url(hmac_sha256(address|expiry, secret))` — three pipe-delimited parts.
- Session creation: `Hmac::<Sha256>::new_from_slice(&secret)`, update with data, `finalize().into_bytes()`.
- Session verification: recompute HMAC, `mac.verify_slice(&signature)` for constant-time comparison. Check expiry against server clock.
- Cookie encoding: `base64::engine::general_purpose::URL_SAFE_NO_PAD` for cookie-safe values.
- Address recovery: extract from verified SIWE message, not from user-supplied input.

## Error Handling

- Custom `enum` for domain errors with variants for each failure mode (e.g. `InvalidSignature`, `AccessDenied`, `ContractCallFailed(String)`).
- Implement `Display` and `Error` traits manually. Use `thiserror` only if error boilerplate becomes excessive.
- `type BoxError = Box<dyn std::error::Error + Send + Sync>` for handler return types — ergonomic with `?` operator.
- `.map_err()` to convert library errors into domain errors with context.
- Match on `Result` directly in handlers to return context-specific HTTP error responses.
- Return early on errors (guard clauses). Avoid deep nesting of success paths.
- Never `.unwrap()` or `.expect()` in production code paths — reserve for infallible operations or test code.
- `unwrap_or_default()` and `unwrap_or_else(|| ...)` for fallbacks with explicit defaults.

## Release Profile

- `lto = true` — link-time optimisation for smaller, faster binaries.
- `strip = true` — strip debug symbols from release binary.
- `panic = "abort"` — immediate exit on panic, smaller binary (no unwinding tables).
- `codegen-units = 1` — single codegen unit for maximum optimisation (slower compile, better runtime).
- These settings in `[profile.release]` in `Cargo.toml`. Do not apply to dev profile.

## Foundry / Solidity

- `foundry.toml` for Solidity configuration. `solc` version pinned (e.g. `0.8.20`).
- `evm_version = "paris"` for Autonity — no PUSH0 opcode support (Shanghai feature).
- `optimizer = true` with `optimizer_runs = 10000` for production gas efficiency.
- Custom Solidity errors (`error NotAdmin()`) over `require` with string messages — cheaper gas, type-safe.
- `forge build` compiles to `out/` directory. `forge test` runs Solidity tests.
- Contract artifacts: JSON files in `out/<Contract>.sol/<Contract>.json` with `bytecode.object` field.
- In Rust integration tests: `include_str!` to load compiled artifacts, extract bytecode, deploy via alloy.

## Nix and Container Builds

- `nix2container` for OCI image building — faster and more reproducible than Docker.
- `buildRustPackage` with `cargoLock.lockFile = ./Cargo.lock` for deterministic Rust builds.
- `rust-overlay` for Rust toolchain management. Pin to a specific version (e.g. `pkgs.rust-bin.stable."1.84.0".minimal`) or use `pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml` for reproducibility.
- Minimal image closure: only the compiled binary and `pkgs.cacert` for TLS. No shell, no package manager.
- Non-root execution: `user = "65534:65534"` (nobody) in container config.
- `SSL_CERT_FILE` environment variable pointing to Nix CA bundle path.
- Multi-system support: `forAllSystems` pattern for cross-platform packages.
- `devenv.nix` for development shells: `languages.rust.enable = true`, foundry, cargo-watch, helm tools.
- Separate `default` (binary) and `<name>-image` (OCI) outputs in `packages`.

## Testing

- Unit tests in `#[cfg(test)] mod tests` within source files — co-located with implementation.
- Integration tests in `tests/` directory — test the public API via `use <crate>::*`.
- `#[tokio::test]` for async tests. `#[test]` for synchronous unit tests.
- `reqwest::Client` for HTTP integration tests. Configure with `.redirect(Policy::none())` and `.cookie_store(true)` for auth testing.
- Dynamic test server: bind to port 0, spawn server in background task, test against `local_addr`.
- Shared utilities in `tests/common/mod.rs`: test wallets, contract deployment helpers, node availability checks.
- External-dependency tests: prefer `#[ignore = "requires <service>"]` with a clear reason over returning early based on environment checks.
- E2E tests: deploy contracts, grant access, start server, run full auth flow — tests the entire stack.
- `assert_eq!` for value comparison (shows both values on failure). `assert!(result.is_err())` for error path verification.
- `[dev-dependencies]` in `Cargo.toml` for test-only crates — does not affect production binary.

## Linting and Formatting

- `cargo fmt` is non-negotiable — all Rust code must be formatted. CI check: `cargo fmt --check`.
- `cargo clippy -- -D warnings` for lint errors. Treat clippy warnings as errors in CI.
- CI order: format check, clippy, test. Fail fast on formatting before spending time on tests.
- `cargo audit` for dependency vulnerability scanning. Run in CI.
- `cargo test` with default features. Add `--all-features` only if feature combinations need testing.

## Anti-Patterns to Flag

- `.unwrap()` or `.expect()` in production code paths (use `?`, `map_err`, or match)
- `panic!` in library code (return `Result` instead)
- Missing `Cargo.lock` in binary/service repositories (non-reproducible builds)
- `unsafe` blocks without explicit justification and safety comments
- Blocking operations (std::fs, std::net) inside async functions without `spawn_blocking`
- `String` where `&str` suffices (unnecessary allocation)
- Missing `Send + Sync` bounds on error types used across async boundaries
- `#[ignore]` without a reason string (use `#[ignore = "reason"]`)
- `println!` for logging in production code (use `tracing` or `eprintln!` at minimum)
- Hardcoded private keys or secrets in source code (load from environment)
- `:latest` tags on container base images in Nix builds (use pinned versions or digests)
- `tokio::main(flavor = "current_thread")` without justification (limits concurrency)
