---
name: nix-modules-hardening
description: NixOS service module authoring — option conventions (mkEnableOption, mkPackageOption, settings), DynamicUser vs static UID, StateDirectory / RuntimeDirectory / LoadCredential wiring, defense-in-depth systemd hardening (ProtectSystem, RestrictAddressFamilies, SystemCallFilter, MemoryDenyWriteExecute), and SupplementaryGroups for cross-service UNIX socket access. Use when writing or reviewing files under `nixos/modules/services/` or any systemd service declared via `systemd.services.<name>` in a NixOS module.
---

# Nix Modules Hardening Skill

Scope: authoring NixOS service modules with defense-in-depth systemd hardening. Complements the [`nix` skill](../nix/SKILL.md) which covers flake-level concerns (build hygiene, OCI images, task-runner layering). Where the `nix` skill stops at "how to produce an artefact", this one starts at "how to run that artefact as a hardened systemd service".

### A note on `lib.*` qualifiers in the snippets

Many reference excerpts in this skill are quoted verbatim from `nixpkgs/nixos/modules/services/`, where the surrounding module evaluates under `with lib;` or has `inherit (lib) ...` — so calls like `mkIf`, `mkDefault`, `optional`, `getExe` appear unqualified. Snippets marked as **copy-paste templates** (the LoadCredential wiring and the Quick-Reference Baseline Template at the end) use the explicit `lib.` qualifier so they can be dropped into any module context without assuming `lib` is in scope. If you copy a verbatim-upstream snippet elsewhere, either wrap it in `with lib; { ... }` or prefix each `lib.*` call accordingly.

## Module Option Conventions

### `mkEnableOption`

Canonical form — the same function in both idioms; the second variant is just fully qualified:

```nix
enable = mkEnableOption "PostgreSQL Server";   # with `with lib;` in scope
enable = lib.mkEnableOption "Redis server";    # explicit qualifier
```

The argument is a short human-readable noun phrase. Do NOT use "the <name>" or full sentences.

### `mkPackageOption` over explicit `mkOption`

Preferred form when the default is a simple nixpkgs attribute path:

```nix
package = lib.mkPackageOption pkgs "redis" { };
```

Use explicit `mkOption { type = types.package; ... }` only when the default depends on config-time logic (state-version-aware version selection, feature-flag branching). Example:

```nix
# Only needed for version-selection logic
package = mkOption {
  type = types.package;
  defaultText = literalExpression ''
    if versionAtLeast config.system.stateVersion "25.11" then
      pkgs.postgresql_17
    else if versionAtLeast config.system.stateVersion "24.11" then
      pkgs.postgresql_16
    else ...
  '';
  description = "The PostgreSQL package to use.";
};
```

### `settings` vs `extraArgs` vs `extraConfig` vs `extraFlags`

Convention hierarchy (preference, top to bottom):

1. **`settings`** — attrset, converted to config file at module init. Modern idiom, used across ~380 services.
2. **`extraArgs`** — list of strings, for CLI-only programs where settings don't apply (Go, Rust binaries). ~250 services.
3. **`extraFlags`** — used when `settings` + `extraArgs` are insufficient; prefer `extraArgs` when possible.
4. **`extraConfig`** — deprecated; being phased out in favor of `settings`. ~415 legacy occurrences.

Example (Geth uses `extraArgs` because it's a Go CLI):

```nix
extraArgs = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  description = "Additional arguments passed to Go Ethereum.";
  default = [ ];
};
```

Example (PostgreSQL uses `settings` with a submodule + freeform type):

```nix
settings = mkOption {
  type = with types; submodule {
    freeformType = attrsOf (oneOf [ bool float int str ]);
    options = { /* specific known options */ };
  };
  default = { };
  description = "PostgreSQL configuration, written to `postgresql.conf`.";
};
```

Every module accepting config SHOULD expose `settings` (or `extraArgs` for CLI-only programs) as the escape hatch — operators must never have to fork the module to set a config value.

### Opt-in escape hatches for known-bad workarounds (`extra*` variants)

Sometimes the upstream binary has a known bug that needs a workaround for ANY deployment to function. The naive shape is to bake the workaround into the wrapper as default behaviour, but that pattern silently bypasses the upstream fix forever once it ships — the workaround keeps firing because nobody remembers to remove it. The disciplined alternative is an **opt-in** escape hatch:

- Default to off (empty string, `null`, etc.).
- The integration-test fixture sets it to the workaround SQL/script value and explains why inline.
- Production deployments get clean default behaviour and only opt in when they need to.
- The unit logs a stderr line every time the option fires, so the workaround leaves an audit trail in `journalctl`.
- Mutually-exclusive store-vs-tmpfs variants (`extraPostMigrate` accepting a string baked into `pkgs.writeText`, `extraPostMigrateFile` accepting a path ingested via `LoadCredential=`) cover both non-secret and secret cases.

```nix
extraPostMigrate = mkOption {
  type = types.lines;
  default = "";
  description = ''
    SQL block run by `psql` after migrations and before the BEAM
    supervisor starts. Empty by default — operators opt in
    explicitly.

    WARNING: rendered into `pkgs.writeText` → world-readable file
    in `/nix/store/`. MUST NOT contain sensitive values; for SQL
    that has to carry secrets, use `extraPostMigrateFile` instead.

    WARNING: SQL run here can silently bypass data-fix migrations.
    The wrapper logs `applying ... extraPostMigrate{,File} SQL` to
    stderr every invocation so the bypass is visible in journalctl.
    Document each statement's reason in the value, and revisit on
    every upstream version bump.

    Mutually exclusive with `extraPostMigrateFile`.
  '';
};

extraPostMigrateFile = mkOption {
  # `types.strMatching "^/"` rejects relative paths at the type level,
  # before assertions run. Pair with the same eval-time
  # `lib.hasPrefix "/nix/store/"` rejection + runtime `realpath -e`
  # check used for every other path-typed secret option in this skill
  # (see "Two-layer off-store path enforcement" above).
  type = types.nullOr (types.strMatching "^/");
  default = null;
  description = ''
    Off-store alternative to `extraPostMigrate`. Absolute path to
    a SQL file ingested via `LoadCredential=POST_MIGRATE_SQL:<path>`
    (note the `NAME:PATH` colon — NOT `NAME=PATH`; systemd rejects
    the `=` form). Two-layer off-store enforced (eval + runtime).
  '';
};
```

Wire-up:

```nix
${lib.optionalString (cfg.extraPostMigrate != "" || cfg.extraPostMigrateFile != null) ''
  echo "my-service: applying services.my-service.extraPostMigrate{,File} SQL" >&2
  ${pkgs.postgresql}/bin/psql ... -f ${
    if cfg.extraPostMigrate != "" then
      "${pkgs.writeText "post-migrate.sql" cfg.extraPostMigrate}"
    else
      ''"$CREDENTIALS_DIRECTORY/POST_MIGRATE_SQL"''
  }
''}
```

Plus a `config.assertions` entry asserting only one of the two is set.

### SQL identifier case-folding hazard

Options whose values land in BOTH unquoted SQL (where PostgreSQL folds to lowercase) AND double-quoted SQL (case-sensitive) MUST be constrained to lowercase identifiers. The most common pattern: a wrapper that uses nixpkgs' `services.postgresql.ensureUsers` (which issues unquoted `CREATE ROLE <name>`) AND then issues `ALTER ROLE "${cfg.username}" WITH PASSWORD …` with double quotes. If the operator sets `username = "Blockscout"`:

1. `ensureUsers` runs `CREATE ROLE Blockscout` (unquoted) → folded to `blockscout`.
2. The wrapper runs `ALTER ROLE "Blockscout" WITH PASSWORD …` (quoted) → looks for the exact identifier `Blockscout`.
3. PostgreSQL: `role "Blockscout" does not exist`. Unit fails at start.

```nix
# WRONG — allows uppercase, lets the case-folding hazard through.
username = mkOption {
  type = types.strMatching "^[a-zA-Z_][a-zA-Z0-9_]*$";
  default = "myservice";
};

# RIGHT — lowercase-only, matches what `ensureUsers` actually creates.
username = mkOption {
  type = types.strMatching "^[a-z_][a-z0-9_]*$";
  default = "myservice";
};
```

Same constraint applies to `databaseName` and any other SQL identifier the wrapper double-quotes downstream. Add an inline comment on the option type explaining the case-folding rationale so future relaxations don't reintroduce the bug.

## Static vs Dynamic Users

### When to use `DynamicUser = true`

Stateless services, or services whose state is fully managed via `StateDirectory` / `RuntimeDirectory`:

- Application servers (backends, reverse proxies — where supported)
- Caches (Redis, Memcached)
- Indexers, schedulers, one-shot jobs
- Any service that doesn't own persistent files outside `StateDirectory`

systemd allocates a random UID at service start. File ownership is handled transparently via `StateDirectory` (chowned each start) and `LoadCredential` (no file ownership at all — see below).

### When to use a static user

Services whose persistent on-disk state must survive rebuilds with stable ownership:

- **PostgreSQL** — data directory files must be owned by a consistent UID across host rebuilds
- **Nginx** — log rotation, shared cache directories with other tools
- **Databases generally** — stateful, long-lived data

Static UIDs are allocated via `config.ids.uids.<name>` in `nixos/modules/misc/ids.nix`. Never allocate a static UID ad-hoc — use the central registry.

### Anti-pattern mischaracterisation

"Static UID when `DynamicUser` would work" is **not** a blanket anti-pattern — PostgreSQL using static UID is correct. The anti-pattern is using static UID **without a stateful-data justification**. If you can't name a specific reason tied to on-disk persistence, use `DynamicUser`.

## `StateDirectory`, `RuntimeDirectory`, `LoadCredential`

Three orthogonal systemd mechanisms that let `DynamicUser` services manage state without ownership headaches. All three produce paths under `/var/lib/`, `/run/`, or the systemd credential directory — and systemd handles chown transparently.

### `StateDirectory`

Persistent state across reboots, lives under `/var/lib/<name>`. Multi-level paths create nested directories:

```nix
# Creates /var/lib/postgresql AND /var/lib/postgresql/15
StateDirectory = "postgresql postgresql/${cfg.package.psqlSchema}";
StateDirectoryMode = if groupAccessAvailable then "0750" else "0700";
```

Mode defaults to 0700. Use 0750 only when another service (via `SupplementaryGroups`) needs read access.

### `RuntimeDirectory`

Transient state lost on restart, lives under `/run/<name>`. Used for PID files, UNIX sockets, temp files:

```nix
RuntimeDirectory = "nginx";
RuntimeDirectoryMode = "0750";
```

### `LoadCredential`

Secrets ingestion that works with `DynamicUser`. The service **never reads the source file directly** — systemd reads it (with root privileges) and exposes the content via a credential name under `$CREDENTIALS_DIRECTORY` (a read-only tmpfs the service process can read). The shared option declaration looks like:

```nix
# Option declaration — top-level for this flattened example.
# (Upstream Umami nests env-var-mirroring options under a `settings` submodule;
# see "Module Option Conventions" above for that pattern. The flattened form
# here keeps the LoadCredential lesson self-contained and directly copy-pasteable.)
APP_SECRET_FILE = mkOption {
  type = types.nullOr types.str;
  default = null;
  example = "/run/secrets/appSecret";
  description = ''
    A file containing a secure random string. The contents of the file are read
    through systemd credentials; the user running the service does not need
    permissions to read the file.
  '';
};

# serviceConfig wiring (copy-paste template — qualifiers explicit)
serviceConfig = {
  DynamicUser = true;
  LoadCredential =
    lib.optional (cfg.APP_SECRET_FILE != null)
      "appSecret:${cfg.APP_SECRET_FILE}";
  # ... (+ ExecStart or script, see below)
};
```

Credential names (`appSecret` above) are arbitrary — they only have to match between `LoadCredential=name:path` and the consumer. The source file path at `/run/secrets/appSecret` is the concern of the secrets manager (sops-nix / agenix), orthogonal to `LoadCredential`.

### How the service consumes the credential — three patterns, in preference order

**Pattern 1 — preferred: application reads `$CREDENTIALS_DIRECTORY/<name>` directly** (file stays inside systemd's tmpfs, never enters process env):

```nix
# The service binary takes a --secret-file flag pointing at an existing path
serviceConfig.ExecStart = "${lib.getExe cfg.package} --secret-file \${CREDENTIALS_DIRECTORY}/appSecret";
```

**Pattern 2 — good: app accepts a config-file path, compose at ExecStartPre**:

```nix
# ExecStartPre templates a config file into $RUNTIME_DIRECTORY, substituting
# the credential path (not its contents) — the secret never leaves the tmpfs
serviceConfig = {
  RuntimeDirectory = "my-service";
  ExecStartPre = "${pkgs.writeShellScript "render-config" ''
    ${pkgs.envsubst}/bin/envsubst < ${configTemplate} > $RUNTIME_DIRECTORY/config
  ''}";
  ExecStart = "${lib.getExe cfg.package} --config $RUNTIME_DIRECTORY/config";
};
```

**Pattern 3 — last resort: env-only apps (Node.js process.env, Elixir `System.get_env`, many legacy tools)**:

```nix
# The application only accepts secrets via env vars. Export from
# $CREDENTIALS_DIRECTORY just before exec. Secret IS now in process env —
# visible in /proc/<pid>/environ, inherited by child processes, and at risk
# of leaking into coredumps or crash-reporter logs. Use only when the app
# gives no file-path alternative.
script = ''
  export APP_SECRET="$(cat "$CREDENTIALS_DIRECTORY/appSecret")"
  exec ${lib.getExe cfg.package}
'';
```

**Residual-risk note**: the critical boundary is between "secret inside systemd's credential tmpfs" (isolated to the service process) and "secret in process env / a writable file" (multiple leak paths — `/proc/<pid>/environ`, coredumps, child inheritance, accidental logging). Pattern 1 keeps the secret inside the tmpfs for its entire lifetime; Pattern 3 crosses the boundary and should be a conscious choice, not a default. If an app gives you a `--secret-file` or `--config` option, always prefer it over setting an env var.

**Rule**: never put secrets in `Environment=`, `EnvironmentFile=`, or the Nix store. `LoadCredential=` + Pattern 1 is the correct ingestion path for `DynamicUser` services; Pattern 3 is the documented compromise when an app can't be changed.

### Two-layer off-store path enforcement

Every path-typed secret option (`*File` / `*.path`) takes a path that MUST resolve outside `/nix/store/`. A single layer of `lib.hasPrefix "/nix/store/" path` at evaluation time is necessary but **not sufficient**:

```nix
# WRONG — single layer, lets symlinks-into-store through.
{
  assertion =
    lib.hasPrefix "/" cfg.secretFile
    && !lib.hasPrefix "/nix/store/" cfg.secretFile;
  message = "...";
}
```

The eval-time check catches Nix-path literals (`./secret` auto-copying to the store) and hand-written `/nix/store/...` paths, but **`environment.etc."<name>".text = …` slips through**: NixOS realises the bytes into a content-addressed store path and bind-mounts it at `/etc/<name>`. The consumer-visible path (`/etc/<name>`) is not literally under `/nix/store/`, so the eval-time assertion passes — but the bytes ARE in the world-readable store, defeating the secrets contract.

The fix is two layers:

1. **Eval-time** `lib.hasPrefix` (fast, fails the build on the obvious mistakes).
2. **Runtime** `realpath -e` `ExecStartPre=+<helper>` script (resolves symlinks, fails the unit if the resolved target is under `/nix/store/`).

```nix
# In `let`:
checkSecretPathsScript = pkgs.writeShellScript "my-service-check-secret-paths" ''
  set -u
  fail=0

  check() {
    local name="$1" path="$2"
    local resolved
    if ! resolved=$(${pkgs.coreutils}/bin/realpath -e -- "$path" 2>/dev/null); then
      echo "ERROR: services.my-service.''${name} = '$path' — does not exist, or has an unreadable parent directory at unit-start time." >&2
      fail=1
      return
    fi
    case "$resolved" in
      /nix/store/*)
        echo "ERROR: services.my-service.''${name} = '$path' resolves to '$resolved' which is under /nix/store/." >&2
        echo "       Secrets in the world-readable Nix store defeat the module's secrets contract." >&2
        echo "       Source from sops-nix / agenix into a tmpfs path (e.g. /run/secrets/...) instead." >&2
        fail=1
        ;;
    esac
  }

  check secretFile ${lib.escapeShellArg cfg.secretFile}
  ${lib.optionalString (cfg.cookieFile != null)
    "check cookieFile ${lib.escapeShellArg cfg.cookieFile}"}

  exit $fail
'';

# In serviceConfig:
ExecStartPre = [ "+${checkSecretPathsScript}" ];
```

The leading `+` runs the helper as root regardless of `User=` / `DynamicUser=` — needed because operator-supplied secret paths under `/run/secrets/...` (sops-nix / agenix typical setup) are often locked down to mode 0700 root and the dynamic user can't `realpath -e` them. See "ExecStartPre privilege escalation" below for the full rationale.

#### Third validation step: readability as the consuming user

If the file will be read by something other than the unit's `User=` (a setup script invoked from the unit's main script that drops to a different user, a downstream `psql` heredoc that runs in postgres's `User=`), the runtime check must ALSO verify the consuming user can read the file. Otherwise a path that `realpath -e`s cleanly and is off-store can still fail downstream:

```nix
# In the check script, after the /nix/store/ check:
if ! ${pkgs.util-linux}/bin/runuser -u postgres -- ${pkgs.coreutils}/bin/test -r "$resolved"; then
  echo "ERROR: services.my-service.passwordFile = '$path' (resolved to '$resolved') is not readable as user 'postgres'." >&2
  echo "       This file is consumed by a step running as User=postgres — it must own or have group-read on the file." >&2
  echo "       Typical sops-nix shape: \`sops.secrets.<name>.owner = \"postgres\"\` with mode 0400 OR group-readable mode 0440." >&2
  exit 1
fi
```

Without this third step, a file mode 0400 root-owned passes the runtime check (root reads anything via the `+` prefix) but fails when later consumed by a non-root user — and **the failure is silent** if the consumer is a shell pipeline like `cat … | tr -d '\n'` (the `tr` exit status hides the `cat` failure). See the silent-empty-pipeline entry in Anti-Patterns.

#### Assertion message wording

Both layers' error messages should:

- Name the **option** that's misconfigured (`services.<module>.<option>`).
- Name the **resolved target path** at runtime, separately from the input path. The operator may not realise their `/etc/foo` resolved into the store; spelling out the resolved path is the bridge between symptom and cause.
- Point at the canonical fix: sops-nix / agenix into a tmpfs path.

### `ExecStartPre=+<path>` privilege escalation

systemd allows prefixes on `ExecStart*` directives that change how the command is run. The `+` prefix runs the command as **root, ignoring `User=` / `DynamicUser=`**. Two situations where it's the right tool:

1. **Runtime checks that need to traverse root-only directories.** `realpath -e` on `/run/secrets/blockscout/db_password` requires search access on `/run/secrets/blockscout/` — usually mode 0700 root via sops-nix. The unit's `DynamicUser` can't traverse that directory; root can.
2. **One-shot setup tasks before the main exec.** Things like `install -m 0600 -T <staged> <runtime-path>` that need to write into a state directory the unit's user will own once it's running, but currently has root-managed permissions.

The cost is **not** just a temporary UID change. Per `systemd.exec(5)`, the `+` prefix runs the command with **full privileges** for that exec line: `ProtectSystem`, `RestrictAddressFamilies`, `SystemCallFilter`, capability bounds, namespace isolation, and most other sandboxing restrictions are bypassed. The main `ExecStart` still drops back to the unit's configured user, but the `+` step itself runs essentially uncontained — treat it as a narrowly-scoped privileged escape hatch.

Practical guidance:

- **Prefer designs that avoid `+` entirely.** If a runtime check can be expressed as a `config.assertions` entry at evaluation time, do that instead.
- **If the intent is "run as root for startup credential / permission handling" without losing the sandbox**, consider `PermissionsStartOnly=true` (which keeps `ProtectSystem`, `SystemCallFilter`, etc. on while only granting root to `ExecStartPre`/`ExecStartPost` lines). It's narrower than `+` and worth reaching for first.
- **If `+` is unavoidable** (e.g. the helper genuinely needs to traverse a `/run/secrets/` dir locked to mode 0700 root), keep it to a tiny purpose-built helper that does the minimum necessary work and exits. The smaller the privileged window, the less your security posture depends on the `+` step staying simple.

```nix
serviceConfig = {
  DynamicUser = true;
  # ...
  ExecStartPre = [
    # Root-elevated check — verifies operator-supplied secret paths
    # before the main exec drops to DynamicUser.
    "+${checkSecretPathsScript}"
    # Non-root setup that runs as the eventual DynamicUser, no `+`.
    "${pkgs.coreutils}/bin/install -d -m 0700 \${STATE_DIRECTORY}/cache"
  ];
  ExecStart = "${lib.getExe cfg.package}";
};
```

Use the `+` prefix sparingly — every elevation is a small departure from the principle of least privilege. But **for runtime checks specifically, it's the correct tool**: the alternative is leaving the check unable to validate paths that genuinely need root traversal.

## Defense-in-Depth Hardening Matrix

Baseline systemd hardening options, grouped by concern. Every new service module should consider each of these.

### Filesystem protection

| Option | Purpose | Default to |
|---|---|---|
| `ProtectSystem = "strict"` | Whole filesystem remounted read-only except API FS (`/dev`, `/proc`, `/sys`) and explicitly writable dirs (e.g. via `StateDirectory=` / `RuntimeDirectory=`) | all services |
| `ProtectSystem = "full"` | `/usr`, `/boot`, `/efi`, and `/etc` remounted read-only; less restrictive than `strict` | if `strict` causes startup failure |
| `ProtectHome = true` | `/home`, `/root`, `/run/user` inaccessible | all services |
| `PrivateTmp = true` | Private `/tmp`, `/var/tmp` namespace | all services |
| `PrivateDevices = true` | No `/dev/*` except baseline | all services that don't need hardware |

### Process isolation

| Option | Purpose | Default to |
|---|---|---|
| `NoNewPrivileges = true` | No setuid, no capability gain | all services |
| `LockPersonality = true` | No `personality(2)` changes | all services |
| `RemoveIPC = true` | Remove SysV IPC on exit | services without SysV IPC deps |
| `RestrictNamespaces = true` | No user/mount/pid/etc namespace creation | all services |
| `RestrictRealtime = true` | No `SCHED_FIFO`/`SCHED_RR` | services not doing realtime |
| `RestrictSUIDSGID = true` | No creation of setuid/setgid files | all services |
| `PrivateMounts = true` | Private mount namespace | all services |

### Kernel protection

| Option | Purpose | Default to |
|---|---|---|
| `ProtectClock = true` | No `clock_settime` | all services |
| `ProtectControlGroups = true` | No cgroup writes | all services |
| `ProtectHostname = true` | No `sethostname` | all services |
| `ProtectKernelLogs = true` | No `/dev/kmsg`, no `syslog(2)` | all services |
| `ProtectKernelModules = true` | No `init_module`, no `finit_module` | all services |
| `ProtectKernelTunables = true` | No `/proc/sys`, `/sys` writes | all services |
| `ProtectProc = "invisible"` | Other users' processes invisible in `/proc` | all services |

### Capabilities

| Option | Purpose | Default to |
|---|---|---|
| `CapabilityBoundingSet = [ "" ]` | Drop all capabilities | services that don't need any |
| `AmbientCapabilities = [ ... ]` | Grant specific caps at exec | only if required |

Ambient caps MUST be a subset of `CapabilityBoundingSet`. nginx needs to bind port 80/443, so both sets contain `CAP_NET_BIND_SERVICE`:

```nix
AmbientCapabilities = [
  "CAP_NET_BIND_SERVICE"
  "CAP_SYS_RESOURCE"
];
CapabilityBoundingSet = [
  "CAP_NET_BIND_SERVICE"
  "CAP_SYS_RESOURCE"
];
```

### Reference hardening block (PostgreSQL — copy-paste baseline)

From `nixpkgs/nixos/modules/services/databases/postgresql.nix` — the gold standard:

```nix
serviceConfig = {
  User = "postgres";
  Group = "postgres";
  RuntimeDirectory = "postgresql";
  StateDirectory = "postgresql postgresql/${cfg.package.psqlSchema}";
  StateDirectoryMode = "0750";

  # Hardening
  CapabilityBoundingSet = [ "" ];
  DevicePolicy = "closed";
  PrivateTmp = true;
  ProtectHome = true;
  ProtectSystem = "strict";
  MemoryDenyWriteExecute = lib.mkDefault (
    cfg.settings.jit == "off" && (!any extensionInstalled [ "plv8" ])
  );
  NoNewPrivileges = true;
  LockPersonality = true;
  PrivateDevices = true;
  PrivateMounts = true;
  ProcSubset = "pid";
  ProtectClock = true;
  ProtectControlGroups = true;
  ProtectHostname = true;
  ProtectKernelLogs = true;
  ProtectKernelModules = true;
  ProtectKernelTunables = true;
  ProtectProc = "invisible";
  RemoveIPC = true;
  RestrictAddressFamilies = [
    "AF_INET"
    "AF_INET6"
    "AF_NETLINK" # used for network interface enumeration
    "AF_UNIX"
  ];
  RestrictNamespaces = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  UMask = "0027";
};
```

## `RestrictAddressFamilies`

The allowlist of socket address families. Narrow this aggressively — it's one of the highest-leverage options.

### Common families

| Family | Purpose | When needed |
|---|---|---|
| `AF_INET` | IPv4 | Network services |
| `AF_INET6` | IPv6 | Network services |
| `AF_UNIX` | UNIX sockets | IPC, local socket activation |
| `AF_NETLINK` | Kernel event sockets | Network interface enumeration, routing sockets, rare |
| `AF_PACKET` | Raw ethernet | Packet sniffers only — avoid |

### When `AF_NETLINK` is actually needed

PostgreSQL includes it with an explicit comment:

```nix
RestrictAddressFamilies = [
  "AF_INET"
  "AF_INET6"
  "AF_NETLINK" # used for network interface enumeration
  "AF_UNIX"
];
```

Redis does NOT need it — in-memory cache doesn't enumerate interfaces:

```nix
RestrictAddressFamilies = [
  "AF_INET"
  "AF_INET6"
  "AF_UNIX"
];
```

**Rule**: include `AF_NETLINK` only if a specific syscall demands it. If you're unsure, omit it and see if the service starts — kernels return `EAFNOSUPPORT` on denied families, and the service will fail fast.

### Decision tree

- Loopback-only TCP service: `[ "AF_INET" "AF_UNIX" ]` (or `AF_UNIX` alone if you disabled TCP)
- Dual-stack network service: `[ "AF_INET" "AF_INET6" "AF_UNIX" ]`
- Service that enumerates interfaces: add `AF_NETLINK` with an inline comment
- P2P service doing UDP broadcast discovery: may also need `AF_NETLINK`

## `SystemCallFilter`

Allowlist (or deny-list) of syscalls the service may invoke. Three syntactic forms seen in nixpkgs — use whichever matches the surrounding module.

### Single deny string (Redis)

```nix
SystemCallFilter = "~@cpu-emulation @debug @keyring @memlock @mount @obsolete @privileged @resources @setuid";
```

The leading `~` applies to the whole expression — all listed groups are denied.

### List-of-strings (nginx, Prometheus)

```nix
SystemCallFilter = [
  "~@cpu-emulation @debug @keyring @mount @obsolete @privileged @setuid"
] ++ lib.optional cfg.enableQuicBPF "bpf";
```

Appending allows extra syscalls (`bpf` here) while the primary deny-list stays intact. Note: `lib.optional` takes a **single element** (`"bpf"`), not a list — using `lib.optional cond [ "bpf" ]` produces a nested list and breaks the concatenation. Use `lib.optionals cond [ "bpf" ]` only if the optional portion is already a list.

### Attrset with priority (PostgreSQL, advanced)

PostgreSQL uses `systemCallFilter` as an option whose value is an attrset of `{ name, enable, priority }`:

```nix
systemCallFilter = {
  "@system-service" = { enable = true; priority = 1; };
  "~@privileged" = { enable = true; priority = 2; };
  "~@resources" = { enable = true; priority = 2; };
};
```

The module then sorts by priority and serialises. Use this pattern only if operators need to toggle individual groups via `mkForce` — otherwise the list form is simpler.

### Common deny groups

| Group | Covers |
|---|---|
| `@privileged` | mount, chroot, ptrace, bpf, kexec_load, reboot |
| `@resources` | getpriority, setpriority, setrlimit, sched_setscheduler |
| `@mount` | mount, umount2, pivot_root, move_mount |
| `@obsolete` | Deprecated syscalls (ioperm, afs_syscall, vserver) |
| `@cpu-emulation` | modify_ldt, vm86, vm86old |
| `@debug` | ptrace, process_vm_readv, process_vm_writev |
| `@keyring` | keyctl, add_key, request_key |
| `@setuid` | setuid, setreuid, setresuid (block after-fork privilege changes) |
| `@memlock` | mlock, munlock, mlockall (avoid DoS via memory pinning) |

### Baseline recommendation

For new services, start with:

```nix
SystemCallFilter = [
  "~@cpu-emulation @debug @keyring @memlock @mount @obsolete @privileged @resources @setuid"
];
SystemCallArchitectures = "native";
```

Loosen only when a specific syscall is required and diagnosed (e.g. `bpf` for nginx QUIC, `mlock` for gpg-agent). `@memlock` is included by default — services rarely need to pin memory, and blocking it prevents a trivial DoS vector.

## `SupplementaryGroups` for Cross-Service UNIX Socket Access

When a `DynamicUser` service needs to read another service's UNIX socket, grant group membership via `SupplementaryGroups` rather than widening filesystem visibility. Immich (web app reading Redis socket):

```nix
serviceConfig = {
  DynamicUser = true;
  # ...
  SupplementaryGroups = lib.optionals (cfg.redis.enable && isRedisUnixSocket) [
    config.services.redis.servers.immich.group
  ];
};
```

Upstream Immich uses `mkIf` here; inside a full NixOS module evaluation the module system processes the `mkIf` marker and both produce the same final list. `lib.optionals` is strictly simpler — a pure list expression that returns the list or `[]` without module-system magic, safer when the snippet is copied into unfamiliar contexts.

Mechanism:

1. Redis creates `/run/redis-immich/redis.sock` with group `redis-immich` and mode 0660.
2. Immich's dynamic UID is added to group `redis-immich` for the service's lifetime.
3. Immich opens the socket — group read/write granted via POSIX permissions.

This is strictly preferable to `BindReadOnlyPaths=/run/redis-immich/` (which exposes the directory, not just the socket) or running Immich under Redis's static UID (which conflates services).

Example for a backend that talks to both PostgreSQL and Redis:

```nix
SupplementaryGroups = [
  "postgres"             # read /run/postgresql/.s.PGSQL.5432
  "redis-blockscout"     # read /run/redis-blockscout/redis.sock
];
```

## `MemoryDenyWriteExecute` — JIT Opt-outs

Baseline: `MemoryDenyWriteExecute = true`. This blocks the service from `mprotect(PROT_EXEC)`-ing writable memory pages, which is the primary escape hatch for code-injection exploits.

**Exceptions** — services that JIT-compile code to memory and execute it:

| Runtime | Service | Opt-out |
|---|---|---|
| V8 | Node.js apps (bluesky-pds) | `MemoryDenyWriteExecute = false; # required by V8 JIT` |
| BEAM | Elixir/Erlang (Blockscout backend, Mastodon) | `MemoryDenyWriteExecute = false; # BEAM JIT` |
| LuaJIT | Pomerium, OpenResty-adjacent tools | `MemoryDenyWriteExecute = false; # breaks LuaJIT` |
| ONNX runtime | ML inference (Piper, Sherpa-ONNX) | `MemoryDenyWriteExecute = false; # required for onnxruntime` |
| PyPy | Python JIT (rare in server contexts) | `MemoryDenyWriteExecute = false;` |
| JVM | Any OpenJDK/Temurin/Graal service | `MemoryDenyWriteExecute = false;` |

**Go does NOT need opt-out** — Go's compiler produces an ELF with static code pages; there is no runtime JIT for application code.

**Rust does NOT need opt-out** — same rationale.

### Gold standard: conditional opt-out

PostgreSQL's approach — enabled unless JIT/plv8 is active:

```nix
MemoryDenyWriteExecute = lib.mkDefault (
  cfg.settings.jit == "off" && (!any extensionInstalled [ "plv8" ])
);
```

Use this pattern when the JIT is a configurable feature. When the runtime inherently JITs (BEAM, V8), just set `false` with an inline comment explaining why.

## Reference Service Configs

Three more canonical blocks worth having side-by-side.

### Redis (DynamicUser, cache-class hardening)

`nixpkgs/nixos/modules/services/databases/redis.nix`:

```nix
serviceConfig = {
  ExecStart = "${cfg.package}/bin/redis-server /var/lib/${redisName name}/redis.conf ...";
  User = conf.user;
  Group = conf.group;
  DynamicUser = true;
  Restart = "always";

  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;
  PrivateUsers = true;
  ProtectClock = true;
  ProtectHostname = true;
  ProtectKernelLogs = true;
  ProtectKernelModules = true;
  ProtectKernelTunables = true;
  ProtectControlGroups = true;
  RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
  RestrictNamespaces = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  PrivateMounts = true;
  SystemCallArchitectures = "native";
  SystemCallFilter = "~@cpu-emulation @debug @keyring @memlock @mount @obsolete @privileged @resources @setuid";
};
```

### nginx (static user, `AmbientCapabilities`)

`nixpkgs/nixos/modules/services/web-servers/nginx/default.nix`:

```nix
serviceConfig = {
  User = cfg.user;
  Group = cfg.group;
  RuntimeDirectory = "nginx";
  CacheDirectory = "nginx";
  LogsDirectory = "nginx";
  UMask = "0027";

  AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_SYS_RESOURCE" ];
  CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SYS_RESOURCE" ];

  NoNewPrivileges = true;
  ProtectSystem = "strict";
  ProtectHome = mkDefault true;
  PrivateTmp = true;
  PrivateDevices = true;
  # ... (same kernel-protection set as PostgreSQL)
  RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
  MemoryDenyWriteExecute =
    !(builtins.any (mod: mod.allowMemoryWriteExecute or false) cfg.package.modules);
  SystemCallFilter = [ "~@cpu-emulation @debug @keyring @mount @obsolete @privileged @setuid" ];
};
```

### Geth (P2P, `DynamicUser`, minimal hardening)

`nixpkgs/nixos/modules/services/blockchain/ethereum/geth.nix`:

```nix
serviceConfig = {
  ExecStart = "${lib.getExe cfg.package} ${args} ${lib.escapeShellArgs cfg.extraArgs}";
  DynamicUser = true;
  Restart = "always";
  StateDirectory = stateDir;

  PrivateTmp = true;
  ProtectSystem = "full";
  NoNewPrivileges = true;
  PrivateDevices = true;
  MemoryDenyWriteExecute = true;
};
```

Upstream geth uses string-valued booleans (`"true"`) here for historical reasons; systemd accepts them but bare Nix booleans (`true`/`false`) are the preferred form for new modules — normalised in the snippet above.

Note the sparseness: geth is a P2P service whose workload is hard to box in with `SystemCallFilter` or `RestrictAddressFamilies` without breaking discovery. For Autonity (Go, similar P2P profile) the same minimalism is a safe starting point — add `RestrictAddressFamilies` with `AF_NETLINK` if interface enumeration is needed.

## Unit Ordering: `after=`, `wants=`, `requires=`

- **`after =`**: start ordering — this unit starts AFTER the listed units become active. Does NOT force them to start.
- **`wants =`**: weak dependency — if a listed unit fails, this unit still starts.
- **`requires =`**: strong dependency — if a listed unit fails or stops, this unit stops too.

Pattern for a backend depending on PostgreSQL + Redis:

```nix
systemd.services.blockscout-backend = {
  after = [ "postgresql.service" "redis-blockscout.service" "network.target" ];
  requires = [ "postgresql.service" "redis-blockscout.service" ];
  wants = [ "autonity.service" ];  # weak — backend degrades gracefully if Autonity restarts
  # ...
};
```

**Rule**: use `after=` for everything you depend on. Add `requires=` only when the dependency failing should propagate. Use `wants=` for soft dependencies that can be restarted independently.

`network.target` is a systemd target meaning "networking is configured"; `network-online.target` is stronger (routes up). Use the weaker `network.target` unless the service needs outbound connections at startup.

### Conditional ordering when an option can be local OR remote

A common shape: an option whose value can point at either a local-loopback service (where the corresponding wrapper unit lives on this host) OR a remote host (where there is no local unit to order against). Hardcoded `requires=postgresql.service` on the consumer fails immediately on remote-host configs — the local `postgresql.service` doesn't exist, systemd reports "missing required unit", the consumer never starts.

The pattern: a `loopbackHosts` predicate gates BOTH `after=`/`requires=` AND any local-vs-remote-different env-var defaults:

```nix
let
  cfg = config.services.my-service;

  # `localhost` covers IPv4 + IPv6 loopback via /etc/hosts;
  # `127.0.0.1` is the IPv4 literal. The host regex on databaseHost
  # (^[a-zA-Z0-9.-]+$) forbids `:`, so IPv6 literals like `::1`
  # cannot be configured against this option type and would be
  # unreachable defensive code if added here.
  loopbackHosts = [ "localhost" "127.0.0.1" ];
  postgresLocal = lib.elem cfg.databaseHost loopbackHosts;
in {
  systemd.services.my-service = {
    after = [ "network-online.target" ]
      ++ lib.optional postgresLocal "postgresql.service";
    requires = lib.optional postgresLocal "postgresql.service";

    environment = {
      # Same predicate gates env-var defaults. ECTO_USE_SSL must
      # be false against a plaintext loopback Postgres (the wrapper
      # ships no certs); cloud-managed Postgres (RDS, Cloud SQL,
      # Aurora) typically REQUIRES SSL, so non-loopback hosts get
      # the safer default. Operators can always override via
      # extraEnv.
      ECTO_USE_SSL = if postgresLocal then "false" else "true";
    };
  };
}
```

The predicate becomes the single source of truth for "is this dependency local". If the unit gains another flag whose default depends on the same question (timeouts, hostname-vs-IP forms, etc.), gate it on the same `postgresLocal` rather than re-deriving.

**Edge case worth documenting on the option**: when the upstream binding option (e.g. `services.postgresql.settings.listen_addresses = "localhost"`) resolves the name and binds every returned address, leaving `databaseHost = "localhost"` is fine because both v4 + v6 loopback are reachable. When the upstream binds only the literal value (e.g. `services.redis.servers.<name>.bind = "127.0.0.1"`), the consumer's default should match the literal so `getaddrinfo("localhost")` returning `::1` first on dual-stack systems doesn't pick an unreachable address. Asymmetric defaults across two consumers reflect asymmetric upstream behaviour, not a bug.

### Operator `extraEnv` precedence — gate hardcoded fallbacks

The module-wide convention is "operator wins on key collision" — `extraEnv` is the operator's escape hatch and any hardcoded value the wrapper sets should not silently clobber it. The naive shape is to `export VAR="..."` unconditionally in the start script, which loses to whatever systemd `Environment=` set first and clobbers it BEFORE the BEAM/Node.js/Go process inherits the env. Gate the hardcoded fallback on `[ -z "${VAR:-}" ]`:

```nix
# WRONG — operator's extraEnv.RELEASE_COOKIE is silently clobbered.
export RELEASE_COOKIE="$(openssl rand -hex 24)"
exec ${cfg.package}/bin/server start

# RIGHT — precedence chain: file > extraEnv > random fallback.
${lib.optionalString (cfg.cookieFile != null) ''
  export RELEASE_COOKIE="$(cat "$CREDENTIALS_DIRECTORY/RELEASE_COOKIE")"
''}
${lib.optionalString (cfg.cookieFile == null) ''
  if [ -z "''${RELEASE_COOKIE:-}" ]; then
    export RELEASE_COOKIE="$(${pkgs.openssl}/bin/openssl rand -hex 24)"
  fi
''}
exec ${cfg.package}/bin/server start
```

Document the precedence chain in the option's docstring (`cookieFile` > `extraEnv.RELEASE_COOKIE` > random per-restart) so future reviewers don't reintroduce the unconditional export. Note the `''$` escape on `''${RELEASE_COOKIE:-}` — see "`''$` escape inside indented strings" below.

### `''$` escape inside indented strings

Indented `''…''` Nix strings parse `${var}` as antiquotation **everywhere inside the string**, including comment lines and shell `${VAR}` parameter expansions. To pass a literal `${...}` through to the rendered script body, escape with `''$`:

```nix
# WRONG — `${RELEASE_COOKIE:-}` parsed as Nix antiquotation; eval fails.
startScript = pkgs.writeShellScript "start" ''
  # Use `${RELEASE_COOKIE:-}` to test if it's set
  if [ -z "${RELEASE_COOKIE:-}" ]; then ...; fi
'';

# RIGHT — `''$` escapes the dollar sign so Nix leaves `${...}` alone.
startScript = pkgs.writeShellScript "start" ''
  # Use `''${RELEASE_COOKIE:-}` to test if it's set
  if [ -z "''${RELEASE_COOKIE:-}" ]; then ...; fi
'';
```

The escape applies to comments too — a Nix-side comment inside an indented string is part of the string, not a Nix-language comment. If `${...}` appears in your prose, escape it with `''$` even if you don't intend it as an interpolation.

## Anti-Patterns

- Using a static UID without a stateful-data justification — if you can't name a specific reason tied to on-disk persistence (e.g. PostgreSQL data directory ownership), use `DynamicUser = true`
- Storing secrets in `Environment=` or in the Nix store — always ingest via `LoadCredential=name:/path`; service reads from `$CREDENTIALS_DIRECTORY/name`, never from the source path
- Loading a credential via `LoadCredential=` and then `export`-ing it into the process environment as the **default** pattern — exposure via `/proc/<pid>/environ`, coredumps, child-process inheritance. Prefer passing `$CREDENTIALS_DIRECTORY/<name>` as a file-path CLI flag or config path; fall back to `export` only when the app truly has no file-path option
- `EnvironmentFile=` pointing to a file in the Nix store — the store is world-readable; anything in a file path inside the store leaks to all system users
- Binding a service to `0.0.0.0` by default — default to `127.0.0.1` unless the service's role is explicitly externally-facing (nginx, reverse proxies). Operators opt in to exposure
- Missing `after = [ "network.target" ]` (or equivalent) on a network-using service — causes intermittent startup failures before networking is configured
- `BindReadOnlyPaths = [ "/nix/store" ]` — redundant with `ProtectSystem = "strict"` (which makes the entire filesystem read-only except `/dev`, `/proc`, `/sys`). Note: `ProtectSystem = "full"` only remounts `/usr`, `/boot`, `/efi`, `/etc` read-only, so `BindReadOnlyPaths = [ "/nix/store" ]` IS useful there if the service must not write under `/nix/store`
- Omitting `CapabilityBoundingSet = [ "" ]` — the default is full capabilities; modern nixpkgs modules always drop to empty unless specific caps are needed
- Setting `AmbientCapabilities` without matching `CapabilityBoundingSet` — ambient caps are effective only if the bounding set permits them; mismatch silently drops the capability
- Hard-coding a UNIX socket path in a service option instead of deriving from `RuntimeDirectory` — the path changes with the service name, and hard-coded paths break consumers that use `SupplementaryGroups`
- `SupplementaryGroups = [ "wheel" ]` or any privileged group — group membership is a grant, not an isolation; use narrow service-specific groups only
- `MemoryDenyWriteExecute = true` on a JIT runtime (BEAM, V8, LuaJIT, JVM, ONNX, PyPy) — service fails at first JIT compilation; opt out with an inline comment explaining the runtime
- `RestrictAddressFamilies` with `AF_NETLINK` included by default — include only when a specific syscall needs it (interface enumeration, routing). Default should be `AF_INET AF_INET6 AF_UNIX`
- `SystemCallFilter` that blanket-allows `@system-service` without `~@privileged ~@resources` — defeats most of the hardening; always pair the baseline group with explicit subtractions
- Writing a new module that doesn't expose `extraArgs` / `settings` / `extraConfig` — operators will eventually need to pass a flag; if there's no escape hatch they must fork the module
- Defining a service with `User =` and `Group =` but also `DynamicUser = true` — contradictory; systemd uses the dynamic allocation and ignores the static names, but the declaration is confusing and review-hostile
- **Silent-empty-pipeline on secret reads** — `cat <file> | tr -d '\n'` (or any pipe with `cat` first) inherits the LAST stage's exit status, not `cat`'s. If `cat` fails (Permission denied, file missing) the trailing `tr` succeeds on empty input and the pipeline returns 0 with empty stdout. Catastrophic when the captured value drives `ALTER ROLE … WITH PASSWORD '<empty>'` (silently clears the password) or any other "pass empty string when secret is missing" downstream. Fix: preflight `cat <file> > /dev/null` (gets `cat`'s real exit status), `[ -s <file> ]` (rejects empty files), AND the `runuser -u <user> -- test -r` runtime check on the secrets path so unreadability fails the unit at unit-start before any consumer can see empty output. Defense-in-depth: ship all three, so losing one doesn't reintroduce the silent-clearing path.
- **Mixed-case PostgreSQL identifiers** — letting `databaseName` / `username` accept uppercase (`^[a-zA-Z_]...`) breaks `ensureUsers` + double-quoted `ALTER ROLE` interaction. nixpkgs creates the role with unquoted CREATE (folds to lowercase); the wrapper later targets the exact-case identifier with double quotes and gets `role "Capitalized" does not exist`. Constrain to `^[a-z_][a-z0-9_]*$` — see "SQL identifier case-folding hazard" above.
- **Operator `extraEnv` clobbered by hardcoded wrapper export** — module-wide rule is "operator wins on `extraEnv` key collision". Unconditional `export VAR="..."` in the start script clobbers whatever systemd `Environment=` set first. Gate the hardcoded fallback on `[ -z "''${VAR:-}" ]` (precedence chain: cookieFile/secretFile > extraEnv > random/computed fallback) and document the chain in the option's docstring.

## Quick-Reference Baseline Template

Copy-paste block for a new stateless service that binds a loopback TCP port:

```nix
systemd.services.my-service = {
  description = "My service";
  after = [ "network.target" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    ExecStart = "${lib.getExe cfg.package}";
    Restart = "on-failure";
    RestartSec = "5s";

    DynamicUser = true;
    StateDirectory = "my-service";
    RuntimeDirectory = "my-service";

    # Hardening
    CapabilityBoundingSet = [ "" ];
    NoNewPrivileges = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;              # false for BEAM/V8/LuaJIT/JVM/ONNX
    PrivateDevices = true;
    PrivateMounts = true;
    PrivateTmp = true;
    PrivateUsers = true;
    ProcSubset = "pid";
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProtectSystem = "strict";
    RemoveIPC = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];   # add AF_INET6 if dual-stack
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "~@cpu-emulation @debug @keyring @mount @obsolete @privileged @resources @setuid"
    ];
    UMask = "0077";

    # LoadCredential pattern (fill in as needed)
    LoadCredential = lib.optional (cfg.secretFile != null) "my-secret:${cfg.secretFile}";
  };
};
```

Adjust:
- Add `SupplementaryGroups` if the service reads another service's UNIX socket
- Flip `MemoryDenyWriteExecute` to `false` with a comment if the runtime JITs
- Set `AmbientCapabilities` + matching `CapabilityBoundingSet` if the service binds a privileged port
- Static user + `config.ids.uids.<name>` if the service owns persistent state on disk

See the `nix` skill for the flake-level concerns (package definition, task-runner exposure) that bracket this skill's module-level guidance.
