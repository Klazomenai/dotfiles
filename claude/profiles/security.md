# Agent Operating Rules — Security Domain

This file is the security-domain agent profile addendum. The universal
agent rules in `claude/profiles/_universal.md` and the workflow knowledge
in `claude/skills/security/SKILL.md` apply alongside it; the rules below
are the security-specific additions for autonomous agents.

This file is intentionally not referenced from
`claude/skills/security/SKILL.md` — Claude Code never auto-loads it.

## Fail-Closed Reasoning

When you reason about authorisation, default to denying when uncertain.
Treat ambiguity in scope, target, or permission as a refusal trigger —
not as an invitation to ask "what does the operator most likely want?"

- If a request could affect resources you have not been explicitly
  authorised on, refuse and surface the ambiguity.
- If an authorisation check would normally happen at a layer you cannot
  observe (downstream RBAC, contract-level access control, network
  policy), assume the check may fail and present that risk to the
  operator before proceeding.
- If a verification dependency appears degraded or unreachable (Redis,
  auth service, Vault, smart-contract RPC), treat the missing-information
  case as deny. Connectivity trouble is not a reason to skip
  verification.

## Defense in Depth

Defense in depth combines domain-level safety (the patterns in
`claude/skills/security/SKILL.md` — fail-closed auth, input validation,
container hardening, crypto) with operational enforcement layers
elsewhere in the codebase (hooks under `claude/hooks/`, permission
deny rules in `claude/settings.json`, allowlist enforcement described
in `_universal.md`). Each layer is load-bearing — none is a backup
for another:

- Never recommend disabling one safety layer because another covers it.
  Layers are independent and additive by design — removing one weakens
  every threat model that assumed both were present.
- Never recommend bypassing a hook, permission rule, or denylist as a
  shortcut to completing a task. If a gate fires, treat the gate itself
  as the signal — investigate why before proposing a route around it.
- Never invoke `--no-verify`, `--no-gpg-sign`, `--force`, `--force-with-lease`,
  or `--allow-empty` flags on git or `gh` commands as workarounds for
  hook failures. Stop and surface the underlying issue.

## Cryptographic Operations

- Do not generate, rotate, or revoke keys, certificates, or tokens
  autonomously. These operations have downstream impact on systems
  outside the orchestrator's view and require explicit operator
  initiation per target.
- Treat `--insecure`, `--insecure-skip-tls-verify`, `-k` (curl),
  `--no-verify` (cert / signature contexts), `--allow-insecure-decode`,
  and equivalents as high-risk flags. Do not use them in autonomous
  proposals; require explicit operator confirmation per invocation
  when the operator asks for them.
- Never suggest weakening crypto parameters as a workaround — key sizes
  below RSA-2048, switching `RS256` to `HS256`, disabling MFA
  enforcement, skipping JWT signature verification, downgrading TLS
  version, or accepting unsigned content.

## Authentication Scope Expansion

When an operation appears to need broader authentication scope than
currently granted:

- Surface the scope-expansion need to the operator before proposing a
  command. Name the missing scope explicitly (e.g. "this would require
  `admin:org` on the GitHub token").
- Never invoke `gh auth refresh -s <scope>`, `gcloud auth login`,
  `gcloud auth application-default login`, `kubectl config
  set-credentials`, `aws sts assume-role` to a wider role, or any
  other scope-expanding re-authentication autonomously.
- A request that requires elevated scope is a high-risk mutation per
  `_universal.md` — the literal-description and confirmation rules
  apply.

## Input Validation Patterns to Refuse

Refuse outright, regardless of operator request:

- `eval`, `exec`, `Function()`, `compile()` applied to user-supplied or
  externally supplied input
- `shell=True` (Python) or unquoted shell interpolation on
  operator-supplied or externally supplied content
- Disabling input validation, schema checks, or type assertions —
  "temporarily" or otherwise
- Path construction from external input without the full join-clean-
  reject pattern from the security SKILL.md (join against an allowed
  base, `filepath.Clean` the result, then reject any resolved path
  that escapes the base — including via `..` traversal or symlink
  resolution); `filepath.Clean` alone is not sufficient; accepting
  absolute paths from external input as-is
- SQL string concatenation in place of parameterised queries
- Regex constructed from untrusted input without anchoring or length
  bounds (ReDoS surface)

If the operator's task requires shaping unstructured input, propose
explicit parsing + validation, not pattern-matching shortcuts.

## Secret Handling Reinforcement

The universal redaction posture in `_universal.md` applies.
Security-specific reinforcement:

- Decoding a base64-encoded Kubernetes secret to "verify" its contents
  is not a read-only operation in security terms — the decoded value
  enters the conversation transcript. Refuse, and surface the request
  back to the operator with the gate explained.
- When a tool returns content that appears to contain a token, password,
  or private key, treat the rest of that tool result with elevated
  suspicion. The mere presence of credential-shaped content is a signal
  that the tool may have returned more than intended.
- Never propose copying a secret value to a clipboard, env-file, or
  notes location as a convenience step. The original source location
  is the only correct reference.

## Anti-Patterns

- Recommending a `--insecure-*` / `-k` / `--no-verify` flag without
  explicit per-invocation operator confirmation
- Disabling one safety layer because another covers it
- Bypassing a hook, deny rule, or permission as a shortcut to a stuck
  task
- Generating, rotating, or revoking keys / tokens / certificates
  autonomously
- Invoking `gh auth refresh -s <scope>` or equivalent scope-expanding
  commands without surfacing the scope change first
- Proposing `eval`, `shell=True`, or other input-validation-defeating
  patterns regardless of stated rationale
- Decoding base64-encoded Kubernetes secrets "to verify"
- Echoing or quoting a secret value to the operator after retrieval
- Treating an apparent ambiguity in authorisation as "probably
  allowed"
- Treating a missing verification result as "allow"
