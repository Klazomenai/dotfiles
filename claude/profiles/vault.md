# Agent Operating Rules — Vault Domain

This file is the vault-domain agent profile addendum, written to
complement the universal rules in `claude/profiles/_universal.md`
and the workflow knowledge in `claude/skills/vault/SKILL.md`.
The rules below are the vault-specific additions for autonomous agents.

This file is intentionally not referenced from
`claude/skills/vault/SKILL.md` — Claude Code never auto-loads it.

## Seal / Unseal Operations

The vault SKILL.md treats `vault operator seal` as
user-confirmation-required and notes that GCP KMS auto-unseal handles
day-to-day unsealing. For autonomous agents, harden both:

- `vault operator unseal` is refused outright in autonomous mode.
  Agents never hold unseal keys, never enter them, and never invoke
  the command — regardless of operator confirmation. Manual unseal
  is an operator-only ceremony.
- `vault operator seal` is a high-risk mutation per `_universal.md`
  (makes all secrets inaccessible) — literal-description from the
  operator + per-target confirmation apply.
- If `vault status` reports the vault is sealed, surface the seal
  state to the operator and stop. Do not attempt KMS-connectivity
  diagnosis or any recovery action autonomously; that ceremony is
  operator-initiated.
- `vault operator step-down` is a high-risk mutation — it triggers
  leader election and can cause a brief unavailability window.
  Per-target confirmation applies.

## Token Handling

The universal redaction posture in `_universal.md` applies to all
vault tokens. Vault-specific reinforcement:

- Never echo, quote, or paste a Vault token value (any type — root,
  service, K8s-auth, AppRole) in your response, even if it appears
  in tool output. Refer to tokens indirectly by their accessor or
  context (the token returned by the generate-root decode step, the K8s
  auth token issued to a named ServiceAccount, and so on).
- Recovery key shards, unseal keys, and the generate-root OTP are
  treated the same as tokens — never quote, never paste, never
  enumerate.
- The `VAULT_TOKEN` environment variable and any `-token=<value>`
  flag are credential-bearing — never echo full command lines that
  carry the value back to the operator.
- `vault token revoke -self` is refused outright in autonomous
  mode — it ends the current session credential and breaks any
  in-flight operation. If the operator wants the current session
  token revoked, they invoke the self form in their own session,
  or invoke the accessor form
  `vault token revoke -accessor <accessor>` from any session.
  Neither path requires pasting the token value on a command line.
- The positional form `vault token revoke <token-value>` and the
  accessor form `vault token revoke -accessor <accessor>` are
  both high-risk mutations per `_universal.md` — downstream
  services authenticated with that token lose access. Per-target
  confirmation applies to each form; the CLI does not auto-detect
  between them, so the operator's literal description must name
  which form is being invoked.
- `vault token create` without an explicit `-ttl` is refused —
  unbounded non-root tokens defeat the lifecycle the SKILL.md
  prescribes.

## Policy Mutation Review

The vault SKILL.md lists the patterns to flag in any policy
(`capabilities = ["sudo"]`, wildcard paths, `bound_service_account_*=*`,
missing TTL, `max_ttl > 24h`). For autonomous agents, that review is
mandatory before any policy mutation:

- `vault policy write <name> <file>` requires the rendered policy
  to be presented to the operator for review before invocation.
  When a policy of that name already exists, the diff against the
  current policy must accompany the rendered text.
- `vault policy delete <name>` is a high-risk mutation —
  downstream services with that policy attached lose access.
  Per-target confirmation applies.
- K8s auth role writes via `vault write auth/kubernetes/role/<name>`
  (passing `bound_service_account_names`, `bound_service_account_namespaces`,
  `policies`, and `ttl` fields) are policy-equivalent mutations:
  same review requirement. Surface the bound ServiceAccount name,
  namespace, policies, and TTL before invoking.
- AppRole and other auth-method mutations via
  `vault write auth/approle/role/<name>` follow the same rule.
- Audit device mutations (`vault audit enable` or `vault audit disable`)
  require per-target confirmation regardless of operator request —
  disabling an audit device breaks compliance posture and loses the
  historical write trail.

## Secret Write Provenance

The universal write-intent rule in `_universal.md` applies to all
secret writes. Vault-specific reinforcement:

- `vault kv put <path> key=value [...]` requires the full key/value
  set to be presented to the operator before invocation when any
  value is sourced from tool output, generated mid-session, or read
  from a file the operator did not explicitly provide.
- Stdin-fed writes (`vault kv put <path> @-` with a heredoc, or
  `cat file | vault kv put <path> @-`) require the content to match
  operator-shown text byte-for-byte. The `@/dev/stdin` form
  (preferred by `claude/skills/vault/SKILL.md`) is equivalent.
- `vault kv patch` falls under the same provenance rule as `put`.
- `vault kv delete` and `vault kv metadata delete` are high-risk
  mutations (the metadata delete is unrecoverable); per-target
  confirmation applies.
- Never auto-rotate a secret value in Vault. Rotation is an
  operator-initiated ceremony with downstream coordination — even
  when a rotation tool exists, the trigger is not the agent's call.
- Cross-engine writes (`vault write database/config/<name>`,
  `vault write transit/keys/<name>`, etc.) follow the same
  provenance rule as `kv put`.

## Anti-Patterns

- Invoking `vault operator unseal` autonomously with any number of
  shards
- Holding, storing, or echoing unseal keys or recovery key shards
- Quoting a Vault token value (root, service, K8s-auth, AppRole) in
  your response
- Echoing a full command line containing `-token=<value>` or
  `VAULT_TOKEN=<value>` back to the operator
- `vault token revoke -self` in autonomous mode
- `vault token create` without an explicit `-ttl`
- `vault policy write` without surfacing the rendered policy and
  diff to the operator
- `vault audit disable` or `vault audit enable` without per-target confirmation
- `vault kv put` / `kv patch` to any path with values sourced from
  tool output without operator review
- Auto-rotating a Vault-stored secret
- Treating `vault operator step-down` as a routine maintenance step
- Attempting KMS-connectivity diagnosis or recovery when
  `vault status` reports sealed
