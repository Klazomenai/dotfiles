---
name: nix-modules-hardening
description: NixOS service module authoring — option conventions (mkEnableOption, mkPackageOption, settings), DynamicUser vs static UID, StateDirectory / RuntimeDirectory / LoadCredential wiring, defense-in-depth systemd hardening (ProtectSystem, RestrictAddressFamilies, SystemCallFilter, MemoryDenyWriteExecute), and SupplementaryGroups for cross-service UNIX socket access. Use when writing or reviewing files under `nixos/modules/services/` or any systemd service declared via `systemd.services.<name>` in a NixOS module.
---

# Nix Modules Hardening Skill

Scope: authoring NixOS service modules with defense-in-depth systemd hardening. Complements the [`nix` skill](../nix/SKILL.md) which covers flake-level concerns (build hygiene, OCI images, task-runner layering). Where the `nix` skill stops at "how to produce an artefact", this one starts at "how to run that artefact as a hardened systemd service".

## Module Option Conventions

### `mkEnableOption`

Universal form — no variations observed across nixpkgs:

```nix
enable = mkEnableOption "PostgreSQL Server";
enable = lib.mkEnableOption "Redis server";
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

Secrets ingestion that works with `DynamicUser`. The service **never reads the source file directly** — systemd reads it (with root privileges) and exposes the content via a credential name under `$CREDENTIALS_DIRECTORY`. Service reads via `systemd-creds cat <name>` or `cat $CREDENTIALS_DIRECTORY/<name>`.

Umami (Node.js analytics) wires this end-to-end:

```nix
# Option declaration (what the operator configures)
APP_SECRET_FILE = mkOption {
  type = types.nullOr types.str;
  default = null;
  example = "/run/secrets/umamiAppSecret";
  description = ''
    A file containing a secure random string. The contents of the file are read
    through systemd credentials, therefore the user running umami does not need
    permissions to read the file.
  '';
};

# serviceConfig wiring
serviceConfig = {
  DynamicUser = true;
  LoadCredential =
    optional (cfg.settings.APP_SECRET_FILE != null)
      "appSecret:${cfg.settings.APP_SECRET_FILE}";
  # ...
};

# Script reads the credential via systemd-creds (NOT via the source path)
script = ''
  export APP_SECRET="$(systemd-creds cat appSecret)"
  exec ${getExe cfg.package}
'';
```

Credential names (`appSecret` above) are arbitrary — they only have to match between `LoadCredential=name:path` and the consumer. The source file path at `/run/secrets/umamiAppSecret` is the concern of the secrets manager (sops-nix / agenix), orthogonal to `LoadCredential`.

**Rule**: never put secrets in `Environment=`, `EnvironmentFile=`, or the Nix store. `LoadCredential=` is the correct ingestion path for `DynamicUser` services.

## Defense-in-Depth Hardening Matrix

Baseline systemd hardening options, grouped by concern. Every new service module should consider each of these.

### Filesystem protection

| Option | Purpose | Default to |
|---|---|---|
| `ProtectSystem = "strict"` | `/usr`, `/boot`, `/efi`, `/etc` read-only, rest of `/` inaccessible | all services |
| `ProtectSystem = "full"` | Slightly relaxed (parts of `/etc` still accessible) | if `strict` causes startup failure |
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
] ++ optional cfg.enableQuicBPF [ "bpf" ];
```

Appending allows extra syscalls (`bpf` here) while the primary deny-list stays intact.

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
  "~@cpu-emulation @debug @keyring @mount @obsolete @privileged @resources @setuid"
];
SystemCallArchitectures = "native";
```

Loosen only when a specific syscall is required and diagnosed (e.g. `bpf` for nginx QUIC).

## `SupplementaryGroups` for Cross-Service UNIX Socket Access

When a `DynamicUser` service needs to read another service's UNIX socket, grant group membership via `SupplementaryGroups` rather than widening filesystem visibility. Immich (web app reading Redis socket):

```nix
serviceConfig = {
  DynamicUser = true;
  # ...
  SupplementaryGroups = mkIf (cfg.redis.enable && isRedisUnixSocket) [
    config.services.redis.servers.immich.group
  ];
};
```

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

  PrivateTmp = "true";
  ProtectSystem = "full";
  NoNewPrivileges = "true";
  PrivateDevices = "true";
  MemoryDenyWriteExecute = "true";
};
```

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

## Anti-Patterns

- Using a static UID without a stateful-data justification — if you can't name a specific reason tied to on-disk persistence (e.g. PostgreSQL data directory ownership), use `DynamicUser = true`
- Storing secrets in `Environment=` or in the Nix store — always ingest via `LoadCredential=name:/path`, service reads via `systemd-creds cat name`; never via the source path
- `EnvironmentFile=` pointing to a file in the Nix store — the store is world-readable; anything in a file path inside the store leaks to all system users
- Binding a service to `0.0.0.0` by default — default to `127.0.0.1` unless the service's role is explicitly externally-facing (nginx, reverse proxies). Operators opt in to exposure
- Missing `after = [ "network.target" ]` (or equivalent) on a network-using service — causes intermittent startup failures before networking is configured
- `BindReadOnlyPaths = [ "/nix/store" ]` — redundant with `ProtectSystem = "strict"` / `"full"` which already makes `/usr` (the systemd-visible Nix store link) read-only
- Omitting `CapabilityBoundingSet = [ "" ]` — the default is full capabilities; modern nixpkgs modules always drop to empty unless specific caps are needed
- Setting `AmbientCapabilities` without matching `CapabilityBoundingSet` — ambient caps are effective only if the bounding set permits them; mismatch silently drops the capability
- Hard-coding a UNIX socket path in a service option instead of deriving from `RuntimeDirectory` — the path changes with the service name, and hard-coded paths break consumers that use `SupplementaryGroups`
- `SupplementaryGroups = [ "wheel" ]` or any privileged group — group membership is a grant, not an isolation; use narrow service-specific groups only
- `MemoryDenyWriteExecute = true` on a JIT runtime (BEAM, V8, LuaJIT, JVM, ONNX, PyPy) — service fails at first JIT compilation; opt out with an inline comment explaining the runtime
- `RestrictAddressFamilies` with `AF_NETLINK` included by default — include only when a specific syscall needs it (interface enumeration, routing). Default should be `AF_INET AF_INET6 AF_UNIX`
- `SystemCallFilter` that blanket-allows `@system-service` without `~@privileged ~@resources` — defeats most of the hardening; always pair the baseline group with explicit subtractions
- Writing a new module that doesn't expose `extraArgs` / `settings` / `extraConfig` — operators will eventually need to pass a flag; if there's no escape hatch they must fork the module
- Defining a service with `User =` and `Group =` but also `DynamicUser = true` — contradictory; systemd uses the dynamic allocation and ignores the static names, but the declaration is confusing and review-hostile

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
    LoadCredential = optional (cfg.secretFile != null) "my-secret:${cfg.secretFile}";
  };
};
```

Adjust:
- Add `SupplementaryGroups` if the service reads another service's UNIX socket
- Flip `MemoryDenyWriteExecute` to `false` with a comment if the runtime JITs
- Set `AmbientCapabilities` + matching `CapabilityBoundingSet` if the service binds a privileged port
- Static user + `config.ids.uids.<name>` if the service owns persistent state on disk

See the `nix` skill for the flake-level concerns (package definition, task-runner exposure) that bracket this skill's module-level guidance.
