---
name: helm
description: Helm deployment safety, version pinning, upgrade checks, rollback guidance, and CRD handling. Use when working with helm commands, chart values, or Helm-based deployments.
---

# Helm Skill

## Version Pinning

- ALWAYS use `--version` on `helm install` and `helm upgrade` — omitting it silently pulls the latest chart version
- Pin chart versions in values files, CI pipelines, and documentation — never assume "latest" is stable
- After adding a repo, check available versions: `helm search repo <chart> --versions`
- Verify the installed chart version matches expectations: `helm list -n <namespace>`

## Pre-Upgrade Checks

Before running `helm upgrade`:

1. **Check release status**: `helm status <release> -n <namespace>` — if status is `pending-upgrade` or `pending-install`, the previous operation failed. Run `helm rollback <release> <revision> -n <namespace>` first.
2. **Preview changes**: `helm diff upgrade <release> <chart> --version <ver> -n <namespace> -f values.yaml` (requires helm-diff plugin)
3. **Template locally**: `helm template <release> <chart> --version <ver> -n <namespace> -f values.yaml` — review rendered manifests for correctness
4. **Check for immutable field changes**: StatefulSet `volumeClaimTemplates`, Deployment `selector`, Job `spec` — these cannot be updated in-place. If changed, the upgrade will fail. Plan for delete+recreate with data migration.

## Upgrade Safety

### Required Flags

- `--version <version>` — pin the chart version (enforced by hook)
- `--namespace <namespace>` — explicit target namespace
- `--wait` — wait for all resources to be ready before marking success
- `--timeout <duration>` — set a timeout (e.g. `10m`) to avoid hanging indefinitely

### Dangerous Flags

- **`--force`** — deletes and recreates changed resources instead of patching. Causes downtime and can destroy PVC data if the resource has a PVC. NEVER use without explicit user confirmation.
- **`--reset-values`** — discards all previously set values. Only use when intentionally starting fresh.
- **`--reuse-values`** — reuses values from the previous release. Dangerous when chart defaults have changed between versions — can silently miss new required values.

## Rollback

- Use `helm rollback <release> <revision> -n <namespace>` — always specify the target revision
- Check history first: `helm history <release> -n <namespace>` — identify the last known-good revision
- NEVER delete and reinstall a release as a rollback strategy — this destroys PVCs and loses release history
- After rollback, verify: `helm status <release> -n <namespace>` and `kubectl get pods -n <namespace>`

## CRD Handling

- CRDs installed by `helm install` (via `installCRDs: true` or `crds/` directory) are NOT removed by `helm uninstall` — this is by design
- Before upgrading a chart that manages CRDs, check for CRD API version changes in the chart's changelog
- To remove CRDs manually: `kubectl delete crd <name>` — but this deletes ALL custom resources of that type cluster-wide
- Some charts (cert-manager, external-secrets) require `--set installCRDs=true` explicitly — verify the chart's CRD installation method

## Values Files

### Security

- NEVER put secrets (passwords, tokens, API keys) in values files — use Vault, ESO, or `--set` from environment variables
- Review values files before committing — check for accidentally included credentials
- Use `existingSecret` patterns where charts support them (reference a K8s secret by name instead of embedding values)

### Best Practices

- Keep one values file per environment (e.g. `values-dev.yaml`, `values-prod.yaml`)
- Use `helm show values <chart> --version <ver>` to see all available options before customising
- Document non-obvious value choices with inline comments

## Repository Management

- After `helm repo add`, verify with `helm repo list`
- Run `helm repo update` before installs to get the latest index
- For OCI registries, use `helm pull oci://` to verify chart availability before deploying
- Verify chart integrity: `helm pull <chart> --version <ver> --verify` (if chart is signed)

## Release Inspection

- `helm list -n <namespace>` — check deployed releases and their status
- `helm get values <release> -n <namespace>` — see currently applied values
- `helm get manifest <release> -n <namespace>` — see rendered manifests as deployed
- `helm history <release> -n <namespace>` — see revision history for rollback planning

## Anti-Patterns to Flag

- `helm upgrade` or `helm install` without `--version` (floats to latest)
- `helm upgrade` without `--namespace` (targets default namespace)
- `helm delete` / `helm uninstall` on releases with PVCs without confirming backup exists
- `helm upgrade --force` (deletes and recreates resources — downtime + data loss risk)
- Secrets in values files (passwords, tokens, connection strings)
- `helm repo update` followed immediately by unversioned install (race condition with upstream)
- Missing `--wait` on upgrades with post-install hooks (hooks may run before resources are ready)
- `helm upgrade --reuse-values` across chart version bumps (misses new defaults)
- `helm template` without `--version` (renders latest, not what's deployed)
