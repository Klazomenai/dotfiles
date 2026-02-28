---
name: argocd
description: ArgoCD GitOps deployment patterns, Application configuration, sync wave ordering, multi-source Helm pattern, AppProject RBAC, and operational safety. Use when working with ArgoCD Application manifests, sync operations, or GitOps deployment workflows.
---

# ArgoCD Skill

## Application Configuration

- Declarative Applications via `argocd-apps` Helm chart — applications defined in `values-<env>.yaml` under `argocd-apps.applications`.
- Each Application specifies: `metadata.namespace` (typically `argocd`, where the Application CR lives), `project` (RBAC scope), `source`/`sources`, `destination`, `syncPolicy`, and optional `annotations`.
- `destination.server` is always the in-cluster API server (`https://kubernetes.default.svc`). `destination.namespace` targets the workload namespace — often different from `metadata.namespace`.
- `project` must reference an existing AppProject — never use `default` project in production (no RBAC boundaries).
- Environment-specific values: base `values.yaml` (defaults) with `values-<env>.yaml` (overrides) following Helm's values precedence; in ArgoCD this is expressed via `spec.source.helm.valueFiles` or `$values/...` in a multi-source Application.
- Chart version pinning: `targetRevision` on Helm chart sources must be an explicit version (e.g. `0.31.0`), never `*` or empty.

## Multi-Source Pattern

- Use `sources` (plural) to combine a Helm chart source with a Git-hosted values source.
- Pattern: first source is the chart (public Helm repo or Git path), second source is a Git ref providing values files.
- Values reference: `ref: values` on the Git source, then `$values/path/to/values.yaml` in `helm.valueFiles` of the chart source.
- Enables separating upstream charts from deployment-specific configuration — chart upgrades are independent of values changes.
- Example structure: chart from `https://prometheus-community.github.io/helm-charts`, values from `git@github.com:<org>/<repo>.git` with `$values/deployments/<app>/<env>/values.yaml`.
- Git-hosted charts: use `path` field pointing to the chart directory within the repository.
- Public Helm repos: use `repoURL` + `chart` + `targetRevision` (version string).

## Sync Waves

- Sync waves control deployment ordering via `argocd.argoproj.io/sync-wave` annotation.
- Wave `-1`: secrets and prerequisites (ExternalSecrets, ConfigMaps that other apps depend on).
- Wave `0`: CRD providers and operators (Grafana Operator, cert-manager, ESO) — must exist before custom resources.
- Wave `1`: core infrastructure (Prometheus, Grafana, Alertmanager, core monitoring stack).
- Wave `2-3`: dependent services (Loki, Promtail, log collection, secondary services).
- Wave `4`: custom resources that depend on operators (GrafanaDashboard, PrometheusRule, ServiceMonitor).
- Resources within the same wave deploy concurrently. Cross-wave dependencies are the primary ordering mechanism.
- Omitting the annotation defaults to wave `0` — only annotate when explicit ordering is required.

## Sync Policy

- `automated.selfHeal: true` always — revert manual drift back to Git state. No exceptions in GitOps.
- `automated.prune: false` for stateful workloads with PVCs (Prometheus, Loki, databases) — prevent accidental data loss when removing from Git.
- `automated.prune: true` for stateless workloads (DaemonSets, Deployments without PVCs, custom resources) — full GitOps lifecycle.
- `CreateNamespace=true` in `syncOptions` — let ArgoCD create target namespaces declaratively.
- `RespectIgnoreDifferences=true` in `syncOptions` — prevents automated sync from applying/overwriting fields listed in `ignoreDifferences`.
- Never enable `automated.prune` on infrastructure that manages secrets (Vault, ESO) — deletion cascades to dependent secrets. All `selfHeal`/`prune` settings require `spec.syncPolicy.automated` to be enabled.

## AppProject RBAC

- One project per domain: `infrastructure`, `monitoring`, `blockscout`, `autonity-nodes` — RBAC boundaries between teams/concerns.
- `sourceRepos`: explicit whitelist of allowed chart repositories (Helm repos, Git repos, OCI registries). Prevents accidental deployments from untrusted sources.
- `destinations`: restrict which namespaces each project can deploy to. Use namespace wildcards (e.g. `bs-*`, `api-*`) for related workloads.
- `clusterResourceWhitelist`: explicitly enumerate allowed cluster-scoped resources (Namespace, CRD, ClusterRole, ClusterRoleBinding, webhook configurations). Default is deny-all for cluster resources.
- Include both HTTPS and SSH variants of Git repo URLs in `sourceRepos` — ArgoCD treats them as distinct sources.
- OCI registry sources: use bare URL without `oci://` prefix (e.g. `ghcr.io/<org>/<repo>/helm/<chart>`) — ArgoCD adds the prefix internally.

## ignoreDifferences

- StatefulSet `volumeClaimTemplates`: ArgoCD detects drift on `volumeClaimTemplates` entries due to fields injected during reconciliation. Ignore with:
  ```
  group: apps
  kind: StatefulSet
  jsonPointers:
    - /spec/volumeClaimTemplates/0/status
  ```
- Webhook `caBundle`: admission webhooks with auto-injected CA bundles (cert-manager, Istio) drift on every reconciliation. Ignore the `caBundle` field.
- Always pair with `RespectIgnoreDifferences=true` in `syncOptions` — otherwise `ignoreDifferences` only affects diff status, and automated sync may still apply changes to ignored fields.
- Use `jsonPointers` for simple path-based ignoring. Use `jqPathExpressions` for complex matching (e.g. all containers matching a name pattern).
- Only ignore fields that are legitimately runtime-managed — never ignore fields to mask configuration drift.

## Operational Safety

- Port-forward for CLI access: `kubectl port-forward svc/argocd-server -n argocd 8080:443`. Access UI at `https://localhost:8080`.
- Initial admin password: `argocd admin initial-password -n argocd`. Avoid piping decoded secrets to stdout in shared terminals or CI — treat like any other secret per the kubernetes skill.
- CLI login: `argocd login localhost:8080 --insecure --grpc-web` — `--insecure` for self-signed certs on port-forward, `--grpc-web` for HTTP/1.1 compatibility.
- Backup before changes: export Applications and ConfigMaps to a local backup directory before upgrading ArgoCD or modifying app definitions.
- Confirmation prompts: destructive operations (uninstall, delete) must require interactive confirmation.
- Makefile targets: `sync`, `sync-status`, `sync-watch`, `backup`, `port-forward`, `get-admin-password` — standardise operational commands.
- `sync-status` with colour coding: green (Synced/Healthy), yellow (OutOfSync/Progressing), red (error states).

## Bootstrap Pattern

- Public Helm repos first: Vault deploys from `https://helm.releases.hashicorp.com` — no Git credentials needed at bootstrap.
- Once Vault is running, it provides secrets for private Git repo authentication and OCI registry access.
- ESO (External Secrets Operator) deploys from public `https://charts.external-secrets.io` — also no credentials needed.
- ESO then syncs secrets from Vault into Kubernetes Secrets, enabling subsequent apps to use private repos.
- Bootstrap order: Vault (public Helm) -> ESO (public Helm) -> ClusterSecretStore (Git) -> remaining apps (private Git).
- Never depend on private Git repos for the initial bootstrap — creates a circular dependency with credential provisioning.

## Secret Integration

- ESO (External Secrets Operator) with ClusterSecretStore for Vault backend — cluster-scoped, available to all namespaces.
- ExternalSecret resources in sync wave `-1` — secrets must exist before pods that reference them.
- `refreshInterval: 1h` for standard secrets. Not suitable for rapidly rotating credentials — use shorter intervals or push-based sync.
- `spec.target.creationPolicy: Owner` — ExternalSecret owns the generated Secret. Deletion of ExternalSecret deletes the Secret.
- `spec.target.deletionPolicy: Delete` — clean up Secrets when ExternalSecret is removed from Git.
- Vault path convention: `secret/data/<domain>/<environment>/<app>` (e.g. `secret/data/infra-monitoring/devnet/loki`).
- Never inline secrets in Helm values files — always reference via ExternalSecret or Kubernetes Secret.
- Template expansion: use `spec.data[].remoteRef` for single-field extraction, `spec.dataFrom` for multi-field JSON expansion.

## OCI Registry Authentication

- Credential templates with URL prefix matching: store credentials once, ArgoCD matches by URL prefix for all repos under that registry.
- GHCR authentication: requires GitHub Classic PAT with `read:packages` scope. Fine-grained PATs do not work with GHCR OCI.
- Credential URL: bare registry prefix (e.g. `ghcr.io/<org>`) without `oci://` — ArgoCD handles protocol internally.
- Rotation: delete and recreate credential template. Makefile targets: `setup-ghcr-creds`, `verify-ghcr-creds`, `rotate-ghcr-creds`.
- Verification: check Applications for `403` errors after credential changes — indicates auth failure.
- PAT expiration: 90 days recommended. Set calendar reminders for rotation.

## CI Validation

- Helm lint + template validation on every PR touching ArgoCD chart or values files.
- `helm dependency build` before `helm template` in CI — uses the committed `Chart.lock` without rewriting it. Fail CI if `Chart.lock` changes.
- Validate all environment-specific values files render without errors.
- Chart version bumps: update `Chart.yaml`, run `helm dependency update` locally to regenerate `Chart.lock`, and commit both.
- Commit both `Chart.yaml` and `Chart.lock` — missing or stale lock file causes non-reproducible deployments.

## Anti-Patterns to Flag

- `default` AppProject in production (no RBAC boundaries, full cluster access)
- `prune: true` on stateful workloads with PVCs (data loss risk on Git removal)
- `selfHeal: false` (allows manual drift to persist — defeats GitOps)
- Missing `RespectIgnoreDifferences=true` when `ignoreDifferences` is configured (ignored fields may still be applied/overwritten during sync)
- Secrets inlined in Helm values files (should use ExternalSecret or mounted Secrets)
- Private Git repos in bootstrap chain before Vault/ESO is available (circular dependency)
- `targetRevision: *` or empty on Helm chart sources (non-deterministic deployments)
- Missing sync wave annotations on resources with ordering dependencies (race conditions)
- `oci://` prefix in ArgoCD `repoURL` fields (ArgoCD adds it — double prefix causes failures)
- Fine-grained GitHub PATs for GHCR OCI authentication (not supported — use Classic PATs)
- `kubectl get secret argocd-initial-admin-secret -o yaml` or `-o jsonpath` to stdout (use `argocd admin initial-password` instead — see Operational Safety)
