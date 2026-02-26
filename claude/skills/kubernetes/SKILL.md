---
name: kubernetes
description: Kubernetes operational safety, context verification, destructive command guards, and secret handling. Use when working with kubectl commands, manifests, RBAC, or cluster operations.
---

# Kubernetes Skill

## Context Verification

Before ANY mutating `kubectl` command:

1. Verify the target cluster: `kubectl config current-context`
2. Use `--context <name>` explicitly on all mutating commands — NEVER rely on the current context being correct
3. Use `-n <namespace>` explicitly — NEVER rely on the default namespace
4. Read-only commands (`get`, `describe`, `logs`, `top`) are lower risk but still benefit from explicit context

### Mutating Commands (require `--context`)

`apply`, `delete`, `patch`, `edit`, `create`, `replace`, `scale`, `drain`, `cordon`, `uncordon`, `exec`, `rollout`, `label`, `annotate`, `taint`

## Destructive Command Safety

### High-Risk Operations (always confirm with user)

- **`kubectl delete namespace`** — deletes ALL resources in the namespace including PVCs, secrets, and running workloads. Almost never the right approach. Prefer deleting specific resources.
- **`kubectl delete pvc`** — permanent data loss. Always confirm a backup exists (Raft snapshot, CNPG WAL archive, Redis dump) before proceeding.
- **`kubectl delete pod --force --grace-period=0`** on StatefulSet pods — bypasses graceful shutdown. Can corrupt data on stateful workloads (databases, Vault, message queues). Use normal `kubectl delete pod` instead and let the StatefulSet controller handle recreation.
- **`kubectl drain`** — evicts all pods from a node. Confirm PDBs are in place and that the workload can tolerate the disruption.
- **`kubectl scale --replicas=0`** — equivalent to taking a service offline. Confirm intent.
- **`kubectl replace --force`** — deletes and recreates the resource. Prefer `kubectl apply` for updates.

### CRD Cascade Deletion

- Deleting a CRD deletes ALL custom resources of that type across ALL namespaces
- Before deleting a CRD, list all instances: `kubectl get <crd-kind> -A`
- Prefer removing the operator/controller first, then cleaning up CRs individually

## Apply Safety

### Idempotent Create Pattern

For resources that should be created if missing but not modified if existing:

```bash
kubectl create <resource> --dry-run=client -o yaml | kubectl apply --context <ctx> -f -
```

### Apply Best Practices

- Always use `--context` and `-n` on `kubectl apply`
- Use `--dry-run=server` to validate before applying: `kubectl apply --dry-run=server -f manifest.yaml`
- For large changes, review the diff first: `kubectl diff -f manifest.yaml`
- Prefer declarative `kubectl apply -f` over imperative `kubectl create` for reproducibility

## RBAC Scoping

When reviewing or creating RBAC resources, flag these patterns:

- **`ClusterRoleBinding` with `system:authenticated`** — grants permissions to every authenticated user/SA in the cluster. Almost never appropriate.
- **`ClusterRole` with `*` verbs or `*` resources** — overly broad. Scope to specific API groups, resources, and verbs.
- **`RoleBinding` referencing a `ClusterRole`** in a sensitive namespace — understand that this grants the ClusterRole's permissions within that namespace.
- **ServiceAccount tokens mounted in pods that don't need API access** — set `automountServiceAccountToken: false` on pods that don't talk to the K8s API.

## Secret Handling

- NEVER decode secrets and display them in terminal output: avoid `kubectl get secret -o jsonpath='{.data.password}' | base64 -d`
- If you must verify a secret exists, check metadata only: `kubectl get secret <name> -n <ns>` (no `-o yaml` or `-o json`)
- When creating secrets, prefer `--from-file` over `--from-literal` — literal values appear in shell history
- For secret rotation, create a new secret and update references — don't `kubectl edit` secrets in place
- NEVER pipe decoded secret values through commands that may log (curl, wget, etc.)

## Namespace Management

- Create namespaces with labels from the start — retrofitting labels is error-prone
- Pod Security Standards labels should be set at namespace creation:
  - `pod-security.kubernetes.io/enforce=restricted` (default)
  - `pod-security.kubernetes.io/enforce=baseline` (workloads needing hostPath, etc.)
  - `pod-security.kubernetes.io/enforce=privileged` (CI workers, debugging only)
- Every namespace should have a default-deny NetworkPolicy — add explicit allow rules per service

## Resource Verification

After applying changes, verify the result:

- `kubectl get <resource> -n <ns>` — confirm it exists
- `kubectl describe <resource> -n <ns>` — check events for errors
- `kubectl rollout status deployment/<name> -n <ns>` — wait for rollout completion
- `kubectl get events -n <ns> --sort-by='.lastTimestamp'` — check for warnings

## Anti-Patterns to Flag

- `kubectl apply` or `kubectl delete` without `--context` flag
- `kubectl exec` without `--context` flag (could exec into wrong cluster)
- `kubectl delete namespace` (nuclear option — prefer targeted deletes)
- `kubectl delete pvc` without confirming backup exists
- `kubectl create secret generic --from-literal=password=actualValue` (visible in history)
- `kubectl delete pod --force --grace-period=0` on stateful pods (data corruption risk)
- `kubectl get secret -o yaml` or `-o json` (exposes encoded secret values)
- `kubectl apply -f` from a URL without reviewing the manifest first
- Missing `-n <namespace>` on commands (relies on default namespace)
- `kubectl edit` on secrets or configmaps in production (no audit trail, no review)
