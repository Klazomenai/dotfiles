---
name: vault
description: HashiCorp Vault lifecycle guidance, safety checks, and operational patterns. Use when working with Vault commands, policies, Kubernetes auth roles, seal/unseal operations, or secret management.
---

# Vault Skill

## Pre-Flight Checks

Before any Vault operation:

1. Verify `VAULT_ADDR` is set and points to the correct instance — confirm protocol (`https://` for TLS-enabled, `http://` only for dev)
2. Check seal status: `vault status` — NEVER proceed if sealed (auto-unseal should handle this; if sealed, investigate KMS connectivity)
3. Confirm target environment — verify via port-forward target or service URL, not assumptions
4. If using port-forward, verify it is active: `lsof -i :8200`

## Initialization Safety

### Recovery Key Configuration

- NEVER use `-recovery-shares=1 -recovery-threshold=1` outside of throwaway dev environments
- Minimum for any persistent environment: `-recovery-shares=3 -recovery-threshold=2`
- Production recommendation: `-recovery-shares=5 -recovery-threshold=3`
- Recovery keys are only needed for root token generation and disaster recovery — NOT for day-to-day unsealing (GCP KMS auto-unseal handles that)

### Init Output Handling

- `vault operator init` outputs recovery keys and a root token — this is the ONLY time these are shown
- Redirect to file with restricted permissions: `vault operator init -format=json > vault-init-keys.json && chmod 600 vault-init-keys.json`
- NEVER pipe init output to stdout in a shared terminal or CI log
- After securely storing keys, delete the local file: `rm -f vault-init-keys.json`

## Root Token Lifecycle

Root tokens have UNLIMITED privileges and NO TTL by default. Treat as critical secrets.

### Generation (via recovery keys)

Three-step process — all via `kubectl exec` (no external network required):

1. **Init**: `vault operator generate-root -init` → save the OTP
2. **Keys**: `vault operator generate-root` → provide recovery keys (repeat until threshold met)
3. **Decode**: `vault operator generate-root -decode=<encoded> -otp=<otp>` → root token

### Revocation (MANDATORY after every use)

- ALWAYS revoke root tokens immediately after completing the operation that required them
- Revoke: `vault token revoke <token>`
- Verify revocation: `vault token lookup <token>` — must return error (permission denied)
- If `token lookup` succeeds, the token is STILL VALID — revoke again
- NEVER leave a session with a live root token

### Anti-Patterns

- NEVER store root tokens in environment variables beyond the current operation
- NEVER create tokens without `-ttl` — all non-root tokens must have a bounded TTL
- NEVER pass tokens as command-line arguments where visible in process lists — use `VAULT_TOKEN` env var or `-` for stdin

## Seal Operations

- NEVER run `vault operator seal` without explicit user confirmation — sealing makes ALL secrets inaccessible
- If Vault is sealed unexpectedly, check GCP KMS connectivity before attempting manual unseal
- `vault operator step-down` is safer than seal for maintenance — it triggers leader election without sealing

## Policy Review

When reviewing or writing Vault policies, flag these patterns:

- **`capabilities = ["sudo"]`** — grants root-equivalent access on that path. Require justification.
- **Wildcard paths** (`path "*"` or `path "secret/*"`) — overly broad. Scope to specific subpaths.
- **`bound_service_account_names=*`** in K8s auth roles — allows ANY ServiceAccount to authenticate. ALWAYS bind to a specific SA name.
- **`bound_service_account_namespaces=*`** — allows ANY namespace. ALWAYS bind to a specific namespace.
- **Missing `ttl`** on K8s auth roles — defaults to system max. Always set explicit TTL (e.g. `ttl=1h`, `ttl=15m`).
- **`max_ttl` > 24h** on K8s auth roles — tokens should not live longer than a day. Flag and justify.

### Good Policy Pattern

```hcl
# Scoped to specific path, read-only, no wildcards
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
```

### Good K8s Auth Role Pattern

```
vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=myapp-ns \
  policies=myapp-policy \
  ttl=1h
```

## Audit Logging

- ALWAYS enable audit logging before any production traffic: `vault audit enable file file_path=/vault/audit/audit.log`
- Verify audit is enabled: `vault audit list` — must show at least one device
- Audit logs contain request/response metadata (not secret values) — safe to forward to log aggregation
- If audit device fails (e.g. disk full), Vault will STOP responding to ALL requests — monitor audit log volume

## Backup Operations

- ALWAYS take a Raft snapshot before any state-changing operation (policy updates, auth config, secret engine changes):
  `vault operator raft snapshot save /tmp/raft-snapshot.snap`
- Copy snapshots off-cluster immediately — PVC loss = snapshot loss
- Verify snapshot is non-empty: `ls -la /tmp/raft-snapshot.snap`
- Backup retention: keep at minimum 7 daily snapshots

## Secret Engine Management

- ALWAYS use `kv-v2` (versioned): `vault secrets enable -path=secret kv-v2`
- NEVER use `vault secrets enable kv` without specifying version — defaults to v1 (no versioning, no soft-delete)
- Check existing engines before enabling: `vault secrets list` — enabling twice on same path fails

## Port-Forward Hygiene

- After completing Vault operations, ALWAYS kill the port-forward: `kill $(lsof -ti :8200)` or dedicated cleanup
- Stale port-forwards cause confusing connection errors in subsequent sessions
- Verify port-forward is dead: `lsof -i :8200` should return nothing

## TLS Verification

- For TLS-enabled Vault, set `VAULT_CACERT` to the CA certificate path
- NEVER use `VAULT_SKIP_VERIFY=true` or `-tls-skip-verify` — defeats the purpose of TLS
- If cert-manager issues the certificate, the CA is in the issuer's secret

## Anti-Patterns to Flag

- `vault token create` without `-ttl` (creates non-expiring token)
- `vault write auth/kubernetes/role/*` with `bound_service_account_names=*` (any SA can authenticate)
- `vault kv put secret/path key=visibleValue` (value visible in shell history — use `@/dev/stdin` or file reference)
- `vault secrets enable kv` without `-version=2` (no versioning)
- `VAULT_SKIP_VERIFY=true` in any non-dev context
- Leaving root tokens alive after operations complete
- Missing audit device on any persistent Vault instance
- `vault operator seal` without explicit confirmation
- Port-forward processes left running after session ends
