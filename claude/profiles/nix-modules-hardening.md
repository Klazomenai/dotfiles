# Agent Operating Rules — Nix Modules Hardening Domain

This file is the nix-modules-hardening agent profile addendum, written to
complement the universal rules in `claude/profiles/_universal.md`
and the workflow knowledge in
`claude/skills/nix-modules-hardening/SKILL.md`.
The rules below are the nix-modules-hardening-specific additions for
autonomous agents.

This file is intentionally not referenced from
`claude/skills/nix-modules-hardening/SKILL.md` — Claude Code never
auto-loads it.

## Hardening Matrix Preservation

When authoring or modifying a `systemd.services.<name>.serviceConfig`
block, never remove or weaken a hardening directive without explicit
operator justification. Directives in scope: `ProtectSystem`,
`ProtectHome`, `PrivateTmp`, `PrivateDevices`, `NoNewPrivileges`,
`RestrictAddressFamilies`, `SystemCallFilter`, `LockPersonality`,
`RestrictNamespaces`, `RestrictRealtime`, `ProtectKernelTunables`,
`ProtectControlGroups`, `ProtectKernelModules`, `MemoryDenyWriteExecute`,
`CapabilityBoundingSet`.

- "This test is failing" or "service startup is failing" is not
  sufficient justification. Surface the specific failure mode to the
  operator and investigate root cause — the hardening directive may be
  correct and the service configuration needs adjustment, not the
  directive.
- Never weaken a hardening directive as a workaround for an undiagnosed
  failure. Removing `SystemCallFilter` because a service crashes on
  startup is an anti-pattern, not a fix.
- The as-shipped hardening matrix (encoded in `tests/hardening-matrix.nix`
  or an equivalent per-repo fixture) is the authoritative record of each
  service's accepted hardening posture. Drift from this matrix — even
  ostensibly safer additions — requires operator confirmation.
- When reviewing a module for hardening completeness, flag any directive
  that falls below the baseline tier for the service class. The SKILL.md
  defense-in-depth matrix and Quick-Reference Baseline Template define
  the tiers.

## DynamicUser vs Static UID

`DynamicUser = true` and `DynamicUser = false` are not symmetric.
Do not flip either direction without surfacing the reason to the operator.

- Some upstream nixpkgs units use static UIDs for load-bearing reasons.
  PostgreSQL uses a static `postgres` UID because the data directory must
  survive across system rebuilds with stable ownership. Redis uses a
  static `redis-<serverName>` group so other services can join via
  `SupplementaryGroups`. Flipping these to `DynamicUser` silently breaks
  socket access or ownership invariants.
- Before recommending `DynamicUser = true` for a service currently using
  a static UID: check whether `SupplementaryGroups` references the static
  group anywhere in the module tree. If it does, the flip is unsafe
  without coordinated changes across all dependent modules.
- Before recommending `DynamicUser = false` for a service currently using
  `DynamicUser`: name the specific on-disk persistence or socket-group
  requirement that demands it. "More convenient" or "avoids the chown
  dance" is not sufficient.
- `PrivateUsers = false` is load-bearing when a `DynamicUser` service
  shares sockets owned by a statically-allocated group — host GID
  remapping inside the user namespace breaks socket access. Removing it
  silently breaks cross-service communication; require operator
  confirmation before touching it.

## MemoryDenyWriteExecute Opt-outs

Baseline: `MemoryDenyWriteExecute = true`. Never set it to `false`
without naming the specific JIT or runtime that requires the relaxation.

- Accepted named justifications (per SKILL.md): BEAM (Elixir/Erlang),
  V8 (Node.js), LuaJIT, JVM (OpenJDK/Temurin/Graal), ONNX runtime
  (Piper, Sherpa-ONNX), PyPy.
- "Tests pass with `false`" or "service crashes with `true`" is not a
  justification — it is a symptom. Surface the failure to the operator;
  investigate whether the JIT requirement is real or whether a different
  directive is the true cause.
- Use `lib.mkDefault false` rather than a bare `false` so operators can
  re-enable the protection without `mkForce`. Accompany with an inline
  comment naming the JIT (e.g. `# BEAM JIT`, `# V8 JIT`).
- Never recommend disabling `MemoryDenyWriteExecute` for services that
  do not use a JIT — interpreted languages (Python, pure shell) do not
  require the relaxation.

## Hardening Matrix Tests

Changes to `tests/hardening-matrix.nix` (or the equivalent per-repo
hardening matrix fixture) are high-risk mutations per `_universal.md` —
they redefine the authoritative record of accepted hardening posture.

- Per-service per-key changes require operator confirmation. Surface the
  before-and-after diff for each affected service and each modified key
  before invoking any edit.
- Never update the hardening matrix test to make it pass after a
  hardening regression. The test is the signal; the fix belongs in the
  module. If the module change is intentional (e.g. adding a JIT
  dependency that requires `MemoryDenyWriteExecute = false`), surface the
  justification first and update the module and the matrix in lockstep.
- Changes that loosen a constraint (remove a key, or move a value to a
  less restrictive setting) carry higher risk than those that tighten.
  Apply per-key scrutiny proportionally.

## Anti-Patterns

- Removing or weakening a hardening directive without naming the specific
  failure mode and obtaining operator justification
- "This fixes the test" or "service starts now" as justification for a
  hardening relaxation
- Flipping `DynamicUser` without checking `SupplementaryGroups`
  references in the module tree
- Removing `PrivateUsers = false` from a `DynamicUser` service that
  shares sockets via group membership
- `MemoryDenyWriteExecute = false` without naming the specific JIT
  (BEAM, V8, LuaJIT, JVM, etc.)
- Updating the hardening matrix test to match a regression rather than
  fixing the regression in the module
- Loosening the hardening matrix test without per-key operator
  confirmation
- `MemoryDenyWriteExecute = false` for a service that does not use a JIT
- Bare `false` instead of `lib.mkDefault false` for JIT opt-outs
  (prevents operator re-enable without `mkForce`)
