---
name: nix
description: Nix flake hygiene, reproducible builds, OCI image patterns, devenv usage, and security enforcement. Use when working with flake.nix, devenv.nix, Nix builds, or Nix-based OCI container images.
---

# Nix Skill

## Flake Hygiene

### Input Updates

- NEVER run `nix flake update` — this updates ALL inputs simultaneously, risking untested combinations
- Update inputs individually: `nix flake update --update-input <name>` (e.g. `nix flake update --update-input nixpkgs`)
- After updating an input, build and test before updating the next
- Use `inputs.<name>.follows = "nixpkgs"` to deduplicate nixpkgs across multiple inputs — prevents version skew:
  ```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };
  ```

### Lock File

- `flake.lock` MUST be committed to the repository — it pins exact revisions for reproducibility
- NEVER add `flake.lock` to `.gitignore`
- After any input update, review the `flake.lock` diff — confirm only the intended input changed

## Build Verification

### Closure Size

- Check closure size after builds: `nix path-info -S ./result` (self size) and `nix path-info -rS ./result` (closure size)
- Large closures indicate unwanted build-time dependencies leaking into runtime
- Common offenders: `gcc`, `binutils`, `go`, `rustc` in runtime closure — these should only be `nativeBuildInputs`
- For OCI images, closure size directly determines image size — keep minimal

### Reproducibility

- Use `nix build --check` to verify build reproducibility (rebuilds and compares outputs against the existing store path)
- Use `nix build --rebuild` to force a local rebuild ignoring substitutes/binary caches (does NOT compare outputs)
- Pin `src` with SRI hashes for external fetches — NEVER use `sha256 = ""` or `lib.fakeSha256` in committed code (only for initial hash discovery)
- Go modules: `vendorHash` must match vendored dependencies — update when `go.mod` changes
- Rust crates: use `cargoLock.lockFile = ./Cargo.lock` — no hash needed when `Cargo.lock` is committed

## OCI Image Patterns

### Non-Root Requirement

- ALWAYS set a non-root user in OCI image config.

  For `pkgs.dockerTools.buildLayeredImage` (Docker config semantics — capitalised fields):
  ```nix
  config = {
    User = "65534:65534";  # nobody:nogroup
  };
  ```

  For `nix2container` (OCI config semantics — lowercase fields):
  ```nix
  config = {
    user = "65534:65534";  # nobody:nogroup
  };
  ```
- NEVER omit the user field — defaults to root

### Minimal Closure

- Include ONLY runtime dependencies in the image root — no compilers, no build tools
- Always include `pkgs.cacert` for HTTPS connectivity:

  dockerTools (`Env`):
  ```nix
  config = {
    Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
  };
  ```

  nix2container (`env`):
  ```nix
  config = {
    env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
  };
  ```
- Use `copyToRoot` with `pkgs.buildEnv` (nix2container) or `contents` (dockerTools) to control exactly what enters the image
- Prefer `nix2container` over `dockerTools` for smaller, more reproducible images — `nix2container` produces deterministic layers without Docker daemon

### Image Tagging

- Pin image tags to versions, not `latest` — use flake metadata or explicit version strings
- For dynamic version extraction in flakes, use `self` metadata (flake sources exclude `.git`):
  ```nix
  # Inside a flake output where `self` is in scope
  version =
    if self ? shortRev then self.shortRev
    else if self ? rev then builtins.substring 0 8 self.rev
    else "0.1.0-dev";  # Fallback for dirty/uncommitted trees
  ```

## Devenv Patterns

### Package Management

- NEVER use `nix-env -i` — imperative installs are not reproducible and pollute the user profile
- ALWAYS use `devenv.nix` with `packages` for development dependencies:
  ```nix
  packages = with pkgs; [
    gopls
    golangci-lint
    gh
  ];
  ```
- Pin language versions explicitly:
  ```nix
  languages.go = {
    enable = true;
    package = pkgs.go_1_xx;  # Pin to a version available in your nixpkgs
  };
  ```

### Shell Scripts

- Use `scripts` for project-specific commands — these are available only inside the devenv:
  ```nix
  scripts = {
    build-wasm.exec = ''
      GOOS=wasip1 GOARCH=wasm go build -o plugin.wasm main.go
    '';
  };
  ```
- Prefer `scripts` over shell aliases or Makefiles for Nix-managed projects

### Git Hooks

- Use `git-hooks.hooks` in devenv for pre-commit checks:
  ```nix
  git-hooks.hooks = {
    gofmt.enable = true;
    govet.enable = true;
  };
  ```
- These run automatically on `git commit` when the devenv is active

## Security

### Purity

- NEVER use `--impure` flag — impure builds depend on host state and are not reproducible
- NEVER use `builtins.getEnv` in flake expressions — flakes are hermetic by design
- If a build needs environment variables, pass them via `nativeBuildInputs` or build-time configuration, not runtime host state

### Hash Integrity

- ALL external fetches MUST include integrity hashes:
  - `fetchurl` → `hash = "sha256-...";` (SRI format)
  - `fetchFromGitHub` → `hash = "sha256-...";` (SRI format)
  - `builtins.fetchTarball` → `sha256 = "...";` (Nix base32 format — does not support SRI; higher-level wrappers may differ)
- Flake inputs are hashed automatically via `flake.lock` — no manual hashes needed for inputs
- NEVER use `builtins.fetchurl` without a hash — it fetches without integrity verification

### Multi-System Support

- ALWAYS support at minimum `x86_64-linux` and `aarch64-linux` for CI and server builds
- Use `forAllSystems` or `flake-utils.lib.eachDefaultSystem` to avoid per-system duplication
- Test on both architectures if possible — cross-compilation issues are common

## Anti-Patterns to Flag

- `nix flake update` without `--update-input` (updates all inputs simultaneously)
- `nix build --impure` (depends on host state)
- `builtins.fetchurl` or `builtins.fetchTarball` without hash (no integrity verification)
- OCI images without `user` field (runs as root)
- `nix-env -i` (imperative, not reproducible — use devenv)
- Missing `flake.lock` in repository (unpinned dependencies)
- `sha256 = ""` or `lib.fakeSha256` in committed code (placeholder hashes)
- Build tools (`gcc`, `rustc`, `go`) in OCI image runtime closure (bloated image)
- `tag = "latest"` on OCI images built with Nix (defeats reproducibility)
- Missing `pkgs.cacert` in OCI images that make HTTPS calls (TLS failures at runtime)
