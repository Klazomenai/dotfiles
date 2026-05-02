---
name: nix
description: Nix flake hygiene, reproducible builds, OCI image patterns, devenv and task-runner layering, Android SDK provisioning, and security enforcement. Use when working with flake.nix, devenv.nix, Nix builds, Makefile/mix/pnpm integration with Nix, or Nix-based OCI container images.
---

# Nix Skill

This skill covers flake-level concerns: building artefacts, packaging them for OCI, setting up devenv, layering task runners, Android SDK provisioning, and flake-evaluation security. Once you move from *producing* an artefact to *running it as a hardened systemd service on NixOS*, see the [`nix-modules-hardening` skill](../nix-modules-hardening/SKILL.md) for `services.<name>` module authoring, `DynamicUser` + `LoadCredential` patterns, and the systemd hardening matrix (`ProtectSystem`, `RestrictAddressFamilies`, `SystemCallFilter`, etc.).

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

### Drv-hash stability as drift proof

When a PR ships a refactor / formatting / comment-only change that's intended NOT to alter runtime behaviour, the rendered drv hash is the artefact-of-no-drift: if the hash before and after the change is byte-identical, the resulting derivation is too. Quote the hash in commit messages and PR bodies so reviewers don't have to re-derive it:

```
Local check: `all checks passed!` (cached integration drv —
comment-only changes). Hardening drv hash unchanged
(`lqhfcckvx8d8`).
```

The full hash is the leading 32-character base32 segment of the `.drv` filename in `/nix/store/` (e.g. `/nix/store/lqhfcckvx8d8zskw1z4lm4iiya98npzb-hardening-matrix-ok.drv`). In commit messages, quoting the first 8–12 characters is the practical community convention — Nix store hashes are dense enough that a 12-char prefix is essentially always unique within a project's store, and shorter prefixes keep commit messages readable. Pick a length and stay consistent across the PR. To find the full hash deterministically:

- For a flake check or attribute output: `nix path-info --derivation .#checks.x86_64-linux.<name>` (or `.#packages.<system>.<attr>`) prints the full `.drv` path; the hash is the prefix.
- For an existing build output (something already in `./result` or another store path): `nix path-info --derivation <out>` resolves the output back to the `.drv` that produced it. **Plain `nix path-info <out>` returns the OUTPUT path, not the derivation; you need the `--derivation` flag for the `.drv`.**
- If you only want the output path itself (e.g. to confirm two builds produced the same artefact rather than the same recipe), `nix build --no-link --print-out-paths .#<attr>` is the matching command.

`nix flake check --print-build-logs` prints build progress and surfaces evaluation-resolved drv paths in lines like `derivation evaluated to /nix/store/<hash>-<name>.drv` — readable in the log stream but not a deterministic single-output value to script against. For machine-friendly extraction, use `nix path-info --derivation` directly.

Reviewers can re-verify with their own `nix flake check` + the same `nix path-info --derivation` command.

Useful for:

- Refactors where the rendered systemd unit / OCI image / config file is meant to stay byte-identical (comment-only edits, regex narrowing on values that already conformed, `lib.escapeShellArg` swaps where the output for the test fixture is identical).
- Updates to a `tests/hardening-matrix.nix`-style static-shape check, where hash stability across a refactor proves no expected-shape regression.
- Sandbox-irrelevant changes to a runtime script (preflight checks, audit-log lines, fail-fast guards) where the rendered unit drv may legitimately change but a sibling drv (e.g. `hardening`) shouldn't.

Concrete language to use in commit messages:

- **"Hardening drv hash unchanged (`<hash>`)"** — for changes that should NOT alter the security-relevant rendered shape.
- **"Integration drv hash changed because <reason>; this is expected"** — for changes that DO alter the runtime artefact deliberately, with the reason called out.
- **"Cached integration drv — comment-only changes"** — for changes that don't touch any rendered artefact at all.

If you write "no shape drift" in a PR description, back it with the hash. The artefact is cheap to quote and turns a claim into a check.

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

## Task Runners, Dev Shells, and Reproducible Builds

Nix covers three distinct concerns that are easy to conflate. Treat them as three orthogonal layers:

| Layer | Purpose | Tools | Example invocations |
|---|---|---|---|
| Developer environment | Pin tool versions, env vars, hooks, background processes | `devenv shell`, `nix develop` | `go version` resolves the pinned Go, `pnpm` resolves the pinned pnpm |
| Task runner | Short commands for common operations (build, test, lint, deploy) | `Makefile`, `mix` aliases, `package.json` scripts, `just`, `devenv scripts` | `make test`, `mix test`, `pnpm build`, `just lint` |
| Reproducible build | Hermetic, canonical, bit-for-bit identical output | `flake.nix` packages/checks, `nix build`, `nix run`, `nix flake check` | `nix build .#default`, `nix flake check` |

Each layer sits on a separate rung. `devenv shell` does not produce artefacts. `nix build` is not a task runner — it is the hermetic artefact producer. Task runners are the contract between a developer's muscle memory and the underlying build/test commands, and they are where Nix entrypoints become discoverable to humans and CI.

### Upstream-First Selection Heuristic

For forks intended for upstream contribution, match upstream's task-runner idiom. Introducing a foreign runner (inventing a Makefile in an Elixir project, or replacing `pnpm` scripts with `devenv scripts`) breaks upstream conventions and makes upstream PRs harder to land.

| Upstream's task runner | Where to expose Nix | Example |
|---|---|---|
| Makefile (Go, C/C++, many Python projects) | Add targets to the existing Makefile | `test-nix-build: ; nix build .#default --print-build-logs` |
| `mix.exs` aliases (Elixir/Phoenix) | Add entries under `aliases:` as function references with `case` + `Mix.raise/1` exit-status handling | See "Exposing Nix Entrypoints via Task Runners" below for the safe form |
| `package.json` scripts (Node) | Keep upstream scripts untouched; optionally add a namespaced `nix:*` entry for discoverability | `"nix:build": "nix build .#default"` (optional) or no change + `enterShell`/README |
| `Cargo.toml` (Rust, binary crates) | No `Cargo.toml` equivalent of npm scripts — surface Nix via `enterShell` / README / CI | No wrapper; `nix build` documented alongside `cargo build` |
| None (greenfield project) | `devenv scripts`, `just`, or documented direct flake commands | `scripts.nix-build.exec = "nix build .#default";` |
| Fork whose upstream has NO Makefile | **Never invent a Makefile** — use upstream's native runner | Elixir upstream → `mix` aliases, not a new Makefile |

The goal is **discoverability** of the hermetic entrypoints, not uniformity of mechanism. Ecosystems that have an idiomatic task-runner surface (Makefile, `mix`, `pnpm`) earn a target or alias there. Ecosystems without one (Cargo; greenfield) surface `nix build` and `nix flake check` via `enterShell` messaging, README, and CI config — all three are valid discovery paths.

### Exposing Nix Entrypoints via Task Runners

Go + Makefile (upstream has `make`, extend it):

```makefile
test-nix-build:
	nix build .#default --print-build-logs

test-nix-check:
	nix flake check . --print-build-logs
```

Elixir + `mix.exs` aliases (upstream has `mix`, extend it). In `mix`, string aliases are interpreted as Mix task invocations, not shell commands, so a bare alias like `"nix build .#default --print-build-logs"` would be treated as a Mix task name rather than executing `nix`. To run external commands, use a function alias that calls `Mix.shell().cmd/1`. Also note that `Mix.shell().cmd/1` returns the exit status as an integer; it does NOT raise on non-zero, so CI could report success even when the external command failed. Wrap it in `case` + `Mix.raise/1` so non-zero exits propagate through the mix exit code:

```elixir
defp aliases do
  [
    "nix.build": fn _args ->
      case Mix.shell().cmd("nix build .#default --print-build-logs") do
        0 -> :ok
        status -> Mix.raise("`nix build` failed with exit status #{status}")
      end
    end,
    "nix.check": fn _args ->
      case Mix.shell().cmd("nix flake check --print-build-logs") do
        0 -> :ok
        status -> Mix.raise("`nix flake check` failed with exit status #{status}")
      end
    end,
  ]
end
```

Node + `package.json` scripts (keep upstream scripts untouched; `devenv.nix` pins the toolchain):

```json
{
  "scripts": {
    "dev": "./tools/scripts/dev.sh",
    "build": "next build",
    "lint:tsc": "tsc -p ./tsconfig.json"
  }
}
```

`nix build .#default` remains the canonical hermetic entrypoint for CI and downstream operators; developers still type `pnpm build` inside `devenv shell` for iterative work. The two coexist — do not collapse them.

### Discovery via `enterShell`

Task runners advertise their targets via `make help`, `mix help`, etc. Nix entrypoints are not auto-discovered — surface them in the `enterShell` message so developers see them immediately on entering the dev shell:

```nix
enterShell = ''
  echo "Nix:"
  echo "  nix build .#default    - Build the project"
  echo "  nix flake check        - Run hermetic checks"
  echo ""
  echo "Native:"
  echo "  make test-nix-build    - Same hermetic build, via Makefile"
'';
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
- Use `scripts` for devenv-local commands that don't belong in upstream's task runner (e.g. `build-wasm` that nothing else calls). For common tasks (build, test, lint), expose them through upstream's native runner — see "Task Runners, Dev Shells, and Reproducible Builds" above

### Git Hooks

- Use `git-hooks.hooks` in devenv for pre-commit checks:
  ```nix
  git-hooks.hooks = {
    gofmt.enable = true;
    govet.enable = true;
  };
  ```
- These run automatically on `git commit` when the devenv is active

## String Interpolation and Runtime File Staging

A few patterns and gotchas that come up whenever a flake renders shell commands or stages files into a runtime location.

### `lib.escapeShellArg` over manual `'…'`

Any time you interpolate an operator-supplied or option-supplied string into a shell command (typically inside `pkgs.writeShellScript` or `pkgs.runCommand`), use `lib.escapeShellArg`, NOT a hand-rolled `'…'` wrapper. The naive form looks safe but breaks on values containing a literal single quote:

```nix
# WRONG — handles whitespace / globs but breaks if the value
# contains a literal single quote: a path like `/foo'bar` closes
# the wrapper's quote and re-opens shell parsing on the rest.
"cat '${cfg.passwordFile}' | tr -d '\n'"

# RIGHT — `lib.escapeShellArg` produces the canonical `'…'`
# wrapper with embedded single quotes escaped via the `'\''`
# idiom: `'/foo'\''bar'`. Survives any byte sequence the value
# might contain.
"cat ${lib.escapeShellArg cfg.passwordFile} | tr -d '\n'"
```

For lists of strings (multiple args at once), use `lib.escapeShellArgs` (plural — note the trailing `s`); it produces the joined, escaped, space-separated form you'd want to interpolate after a command name.

This is the same hazard that makes shell-injection bugs in other languages so common; `lib.escapeShellArg` is the one-line fix and there's no good reason to roll the wrapper by hand.

#### `''$` escape inside indented strings

Related Nix-language gotcha: inside `''…''` indented strings, `${var}` is parsed as Nix antiquotation **everywhere** — including inside what would be shell `${VAR}` parameter expansions and even comment lines. To pass a literal `${...}` through to the rendered output (so the shell interpreter sees `${VAR}` not the antiquoted Nix value), escape with `''$`:

```nix
# WRONG — `${RELEASE_COOKIE:-}` parsed as Nix antiquotation; eval fails.
script = pkgs.writeShellScript "x" ''
  if [ -z "${RELEASE_COOKIE:-}" ]; then ...; fi
'';

# RIGHT — `''$` escapes the dollar sign so Nix leaves `${...}` alone.
script = pkgs.writeShellScript "x" ''
  if [ -z "''${RELEASE_COOKIE:-}" ]; then ...; fi
'';
```

The escape applies to comments inside the string too (a Nix-side comment in an indented string is part of the string, not a Nix-language comment). Worked WRONG/RIGHT example with the full failure mode in the [`nix-modules-hardening` skill](../nix-modules-hardening/SKILL.md) under "`''$` escape inside indented strings".

### `pkgs.writeText`-stage + `install -m 0600 -T` for non-secret operator-config files

For non-secret operator-config files (peer lists, static-node configs, allowlists) that need to land in a `StateDirectory` with specific permissions, the canonical pattern is two-step: stage at build time via `pkgs.writeText`, install at unit start via `coreutils install`.

```nix
ExecStartPre = lib.optional (cfg.staticNodes != null) (
  "${pkgs.coreutils}/bin/install -m 0600 -T "
  + "${pkgs.writeText "static-nodes.json" (builtins.toJSON cfg.staticNodes)} "
  + "\${STATE_DIRECTORY}/static-nodes.json"
);
```

The bytes are non-secret (enode URIs, peer hostnames, etc.) so store-residency is fine — they're public node-identity hints, not credentials. Why each piece matters:

- **`pkgs.writeText`** — produces a store path derived from the text contents (and the file name) so that any change to the JSON-serialised list yields a different store path. NOT to be confused with content-addressed (CA) derivations (`__contentAddressed = true`), which are a separate Nix mechanism — `pkgs.writeText` is input-addressed; the practical effect of "different bytes → different path" is what we rely on here. Rebuilds with a changed `cfg.staticNodes` therefore produce a different store path, and the install step on next start picks up the new bytes.
- **`install -m 0600 -T`** — copies the staged file into place at unit start. `-m 0600` sets target mode in one syscall (no race window between create and chmod). **`-T` treats DEST as a regular file rather than a directory**, so the destination doesn't have to exist beforehand and ambiguity-shadowing-a-dir doesn't apply (e.g. if the operator's `StateDirectory` already has a `static-nodes.json` directory by mistake, `install -T` errors loudly instead of silently writing inside it).
- **Why `install` not `cp` or `ln -s`**: `cp` doesn't atomically set mode (small race window between create and chmod). `ln -s` points the runtime path at a store-resident target which is read-only and immutable — a consumer that wants to update the file in-place can't, `chmod` on the runtime path follows the symlink and either errors or unsafely tries to mutate the store entry, and any sibling check that asserts the runtime path is off-store (e.g. the runtime secret-path check in `nix-modules-hardening`) correctly rejects it. `install` does create-set-mode-write in one pass and produces a real file the consumer can `open(O_RDWR)` and the operator can verify the perms of.
- **`lib.optional (cond)`** — collapses to `[]` when the option is null, so the `ExecStartPre` directive simply isn't emitted on null. Cleaner than nested `mkIf` for this shape.

Use this pattern for any "operator declares a list/config that the binary reads from a fixed file path" requirement that ISN'T a secret. For secrets, use `LoadCredential=` instead (see the `nix-modules-hardening` skill).

## Android SDK Provisioning

Use `pkgs.androidenv.composeAndroidPackages` to declaratively provision the Android SDK — no manual SDK Manager installs, fully reproducible across machines and CI.

### License Acceptance

Android SDK has an unfree license. Both `allowUnfree` and explicit license acceptance are required:

```nix
# In flake.nix
pkgs = import nixpkgs {
  inherit system;
  config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };
};
```

```nix
# In devenv.nix
nixpkgs.config.allowUnfree = true;
nixpkgs.config.android_sdk.accept_license = true;
```

### Composing the SDK

```nix
androidComposition = pkgs.androidenv.composeAndroidPackages {
  buildToolsVersions = [ "36.0.0" ];   # Android Build Tools version
  platformVersions = [ "36" ];          # API level — align with compileSdk/targetSdk
  includeNDK = false;                   # only if JNI native builds needed
  includeEmulator = false;              # not needed for CI or headless builds
  includeSources = false;
  includeSystemImages = false;
};
```

### Environment Variables

In Nix builds, export `ANDROID_SDK_ROOT` (preferred) and `ANDROID_HOME` (legacy fallback) so Gradle discovers the SDK without `local.properties`:

```nix
ANDROID_SDK_ROOT = "${androidComposition.androidsdk}/libexec/android-sdk";
ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";  # legacy fallback
```

### CI Integration (GitHub Actions)

Use `nix develop --command` to run Gradle inside the Nix environment. The dev shell provides JDK, Android SDK, and Gradle — no separate setup actions needed:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: DeterminateSystems/nix-installer-action@v14
  - uses: DeterminateSystems/magic-nix-cache-action@v8
  - run: nix develop --command ./gradlew lint test assembleDebug
```

This ensures CI uses the exact same SDK and JDK versions as local development.

### Version Alignment

Keep SDK versions consistent across all files:
- `buildToolsVersions` / `platformVersions` in `flake.nix` and `devenv.nix`
- `compileSdk` / `targetSdk` in `app/build.gradle.kts`
- See the [Android skill](../android/SKILL.md) for Gradle-side configuration

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
- Inventing a Makefile in a fork whose upstream has no Makefile (breaks upstream contribution — use upstream's native runner: `mix` aliases, `package.json` scripts, etc.)
- Mixing multiple task runners in one repo (Makefile + devenv scripts + `just`) — pick one per language and match upstream
- `devenv scripts` that duplicate upstream task-runner commands (e.g. `scripts.test.exec = "mix test"`) — unnecessary indirection, run upstream's runner directly
- Treating `nix build` as a task runner by wrapping arbitrary pre/post shell steps in its build phases — `nix build` is the hermetic artefact producer; put orchestration in a Makefile/mix/just target that invokes it
- Hiding the canonical hermetic entrypoints (`nix build`, `nix flake check`) — if the repo already has an idiomatic upstream task runner, expose them there; otherwise make them discoverable via `enterShell` messaging and/or the README
- String-valued `mix` aliases that attempt to shell out using bare shell commands (e.g. `"nix.build": "nix build .#default"`) — mix parses string aliases as mix-task invocations; shell-out tasks MUST use function references
- `Mix.shell().cmd/1` in `mix` aliases without exit-status handling — the call returns the exit status as an integer and does NOT raise; failing shell commands exit the alias with status 0 and CI reports success. Wrap in `case` + `Mix.raise/1` so non-zero propagates
- Not messaging Nix entrypoints in `enterShell` (developers enter the dev shell and never discover `nix build` exists)
- Manual `'…'` wrappers around interpolated values in shell commands (`"cat '${cfg.passwordFile}' | tr ..."`) — break on a literal single quote in the value. Use `lib.escapeShellArg` for single args, `lib.escapeShellArgs` for lists.
- `${VAR}` shell-style parameter expansions inside Nix `''…''` indented strings without the `''$` escape — Nix parses `${...}` as antiquotation everywhere in the string (including comment lines), so the shell never sees the literal expansion. See the "`''$` escape inside indented strings" subsection above.
- `cp` or `ln -s` to stage operator-config files into a `StateDirectory` — `cp` has a chmod race window between create and `chmod`. `ln -s` points the runtime path at a read-only / immutable store target, which means consumers can't update the file in-place, `chmod` on the runtime path follows the symlink and either errors or unsafely tries to mutate the store entry, and any sibling check that asserts the runtime path is off-store correctly rejects it. Use `${pkgs.coreutils}/bin/install -m <mode> -T <staged> <dest>` instead — produces a real off-store file with the right perms set atomically.
