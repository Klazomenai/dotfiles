# Agent Operating Rules — Kubernetes Domain

This file is the kubernetes-domain agent profile addendum. The universal
agent rules in `claude/profiles/_universal.md` and the workflow knowledge
in `claude/skills/kubernetes/SKILL.md` apply alongside it; the rules
below are the kubernetes-specific additions for autonomous agents.

This file is intentionally not referenced from
`claude/skills/kubernetes/SKILL.md` — Claude Code never auto-loads it.

## Context Pinning

The kubernetes SKILL.md requires `--context` on mutating commands. For
autonomous agents, harden this to **every** `kubectl` invocation —
including reads.

- Always pass `--context=<name>` explicitly. Do not rely on the
  current-context entry in kubeconfig; that is operator state you
  cannot observe and may be wrong.
- Treat a missing `--context` flag in a tool invocation as a high-risk
  gate failure: refuse and ask the operator to confirm the intended
  context before running the command.
- Do not run `kubectl config use-context <name>` autonomously to "fix"
  a context mismatch. Context selection is a per-invocation decision
  carried on the command line, not a session-state mutation.
- Cross-cluster operations (one read in cluster A, one write in cluster
  B in the same task) must each carry their own `--context`. Never
  assume a default context is "safe to omit because we just used it".

## Namespace Allowlist

The universal allowlist posture in `_universal.md` applies to
namespaces. Kubernetes-specific reinforcement:

- All writes must target a namespace in the configured allowlist. If
  you cannot confirm the target namespace is allowlisted, refuse and
  surface the namespace + applicable allowlist to the operator.
- Never use `--all-namespaces` / `-A` on a write or destructive
  command. Reads with `-A` are acceptable when the operator has asked
  for cross-namespace visibility.
- Control-plane namespaces (`kube-system`, `kube-public`,
  `kube-node-lease`, `istio-system`, `cert-manager`, `external-secrets`,
  and similar cluster-infrastructure namespaces) are not writable by
  autonomous agents regardless of operator request. These belong to
  cluster operators; touching them is a high-risk mutation that
  requires the operator to issue the command directly.
- Namespace creation is itself a mutation against the cluster control
  plane — gated by the same allowlist + confirmation rules.
- Inferring namespace from `kubeconfig`'s current-namespace setting is
  not allowed. Always pass `-n <namespace>` explicitly, matching the
  operator's literal description.

## Destructive Command Gating

The kubernetes SKILL.md lists high-risk operations (delete namespace /
pvc / force-killed StatefulSet pods, drain, scale 0, CRD cascade
deletion). For autonomous agents, these bind to the high-risk-mutation
gating in `_universal.md`:

- `kubectl delete` on any resource is a high-risk mutation —
  literal-description from the operator + per-target confirmation
  apply.
- `kubectl patch` and `kubectl edit` on stateful resources
  (StatefulSet, PersistentVolumeClaim, PersistentVolume, ConfigMap
  referenced by a running workload, Secret) are high-risk regardless
  of the patch content; treat the outcome as if it were a delete.
- `kubectl scale --replicas=0` is destructive — it terminates running
  pods. Same gate as `delete`.
- `kubectl drain` and `kubectl cordon` affect node availability and
  pending workloads; require per-node operator confirmation. `drain`
  with `--force` or `--disable-eviction` is refused outright in
  autonomous mode.
- `kubectl rollout restart` and `kubectl rollout undo` are mutations
  even though they take no manifest; gated the same way as `delete`.
- Cascading deletion of namespaced resources via CRD removal: refuse
  outright in autonomous mode. Surface the implied cascade to the
  operator and let them issue the `kubectl delete crd` directly.
- Set-quantified deletes (`--all`, `-l label=value`, `--field-selector`)
  require per-target enumeration in the operator's confirmation —
  list what would be deleted before proceeding.
- `kubectl delete pod --force --grace-period=0` on StatefulSet pods is
  refused outright; let the StatefulSet controller handle recreation
  via normal `kubectl delete pod`.

## Manifest Provenance

Manifests applied via `kubectl apply` shape cluster state durably.
Their provenance matters as much as their content.

- Never `kubectl apply -f <url-or-file>` from a source you fetched
  mid-session without explicit operator review of the rendered YAML.
- `kubectl apply -f -` (stdin) is acceptable only when the YAML
  presented to the operator matches the YAML applied byte-for-byte.
  Do not synthesise a stdin manifest from operator instructions
  without showing the full text first.
- `kubectl create -f` and `kubectl replace -f` share the same
  provenance requirement.
- `kustomize build | kubectl apply -f -` is one operation in
  provenance terms — the build output is the operator-reviewed
  artefact, not the kustomization sources. Render with
  `kustomize build` and present the output before piping.
- `helm install` / `helm upgrade` is a multi-resource apply by proxy
  — the same provenance rule applies to the merged values and the
  resulting manifests. When values resolution is non-trivial,
  `helm template` first and present the output for review.
- Server-side apply (`--server-side`) does not change provenance
  requirements; field-manager conflict resolution is not consent
  for autonomous application.

## Anti-Patterns

- Invoking `kubectl` without an explicit `--context` flag
- Running `kubectl config use-context` autonomously to "fix" a context
  mismatch instead of carrying `--context` per invocation
- Inferring namespace from `kubeconfig` current-namespace rather than
  from the operator's literal description
- Using `--all-namespaces` / `-A` on a write or destructive command
- Writing to control-plane namespaces (`kube-system`, `istio-system`,
  `cert-manager`, etc.) autonomously
- Cascading delete via CRD removal in autonomous mode
- Set-quantified delete (`--all`, `-l label=value`, `--field-selector`)
  without per-target enumeration in the confirmation
- Applying a manifest sourced from tool output without operator review
  of the rendered YAML
- `helm install` / `helm upgrade` without `helm template` review when
  values resolution is non-trivial
- Treating `kubectl scale --replicas=0` as a "safe pause"
- Treating `kubectl rollout restart` / `rollout undo` as non-mutations
- `kubectl delete pod --force --grace-period=0` on StatefulSet pods
- `kubectl drain --force` or `--disable-eviction` in autonomous mode
