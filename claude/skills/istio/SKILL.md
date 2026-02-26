---
name: istio
description: Istio service mesh operational safety, ambient mode patterns, mTLS enforcement, Gateway API usage, and AuthorizationPolicy guidance. Use when working with Istio configuration, mesh policies, or service mesh troubleshooting.
---

# Istio Skill

## Ambient Mode

Istio ambient mode uses ztunnel (L4 proxy per node) instead of sidecar proxies. These two modes are mutually exclusive per namespace.

### Enabling Ambient Mode

- Label the namespace: `istio.io/dataplane-mode=ambient`
- Do NOT use `istio-injection=enabled` or `sidecar.istio.io/inject` annotations — these are sidecar mode only
- Ambient mode provides L4 mTLS automatically via ztunnel — no sidecar injection needed
- For L7 features (HTTP routing, header-based auth, retries), deploy waypoint proxies

### Namespaces That Should NOT Be Ambient

- `kube-system` — core cluster components
- `istio-system` — Istio control plane manages itself

### Verifying Ambient Enrollment

- Check namespace label: `kubectl get ns <name> --show-labels | grep dataplane-mode`
- Verify ztunnel is running: `kubectl get pods -n istio-system -l app=ztunnel`
- Check ambient dataplane connectivity: `istioctl proxy-status` shows ztunnel and waypoint proxies as connected; ambient workload pods themselves do not appear individually (no sidecar proxy)

## mTLS Enforcement

### STRICT by Default

- Use `PeerAuthentication` with `mode: STRICT` mesh-wide — all traffic must be mTLS
- Apply mesh-wide: namespace `istio-system`, no `selector` field
- NEVER set `mode: PERMISSIVE` unless actively migrating a service that cannot yet support mTLS — document the exception and set a deadline
- NEVER set `mode: DISABLE` — this turns off mTLS entirely for the target

### Verifying mTLS

- Check mesh-wide policy: `kubectl get peerauthentication -A`
- Verify traffic is encrypted: `istioctl x describe pod <pod-name>.<namespace>`
- Test enforcement: attempt a plaintext connection from outside the mesh — should be rejected

## Gateway API

### Use Gateway API, Not Legacy

- Use `gateway.networking.k8s.io/v1` resources (`Gateway`, `HTTPRoute`, `ReferenceGrant`)
- Do NOT use legacy `networking.istio.io/v1beta1` `Gateway` or `VirtualService` — these are deprecated for new deployments
- Do NOT mix legacy and Gateway API resources for the same hostname — behaviour is undefined

### Gateway Patterns

- Prefer a single `Gateway` with multiple listeners over separate Gateways per service — each Gateway creates a separate load balancer (cost implication)
- Use `ReferenceGrant` to allow `HTTPRoute` in one namespace to reference a `Gateway` in another
- Use `parentRefs` in `HTTPRoute` to bind to specific Gateway listeners
- TLS termination: configure `tls.mode: Terminate` on the Gateway listener with a `certificateRefs` pointing to a cert-manager Certificate secret

### HTTP to HTTPS Redirect

- Add a port 80 listener with an `HTTPRoute` that returns a 301 redirect to HTTPS
- Do NOT expose port 80 for application traffic — HTTP-01 ACME challenges are not needed if using DNS-01

## AuthorizationPolicy

### Scoping Rules

- ALWAYS specify a `selector` or `targetRefs` — an AuthorizationPolicy with no selector applies to ALL workloads in the namespace. The only exception is an intentional namespace-wide default policy (document it as such).
- ALWAYS require at least one `from` or `when` condition — an `ALLOW` policy with empty `rules` is an implicit allow-all
- Use `principals` (mTLS identity) or `namespaces` to restrict which services can call the target
- For JWT validation, use `requestPrincipals` with `when` conditions on JWT claims

### Common Patterns

- Default deny per namespace: define explicit `action: ALLOW` policies with specific `rules` for permitted traffic — Istio implicitly denies everything not matched once any ALLOW policy exists. Do NOT use `action: DENY` with empty `rules` (DENY is evaluated before ALLOW and cannot be overridden).
- Service-to-service: `action: ALLOW` with `from.source.principals: ["cluster.local/ns/<ns>/sa/<sa>"]`
- External traffic via Gateway: `action: ALLOW` with `from.source.namespaces: ["istio-system"]` (or the gateway namespace)

### Audit Before Deploy

- Run `istioctl analyze -n <namespace>` before and after applying AuthorizationPolicy changes
- Check for `IST0001` (conflicting policies) and `IST0118` (unused policies) warnings
- Test the policy by attempting the denied action and confirming a 403 response

## Version Management

### Skew Policy

- istiod and data plane (ztunnel/sidecars) must be within one minor version of each other
- Check versions: `istioctl version` shows client, control plane, and data plane versions
- After upgrading istiod, verify data plane is compatible: `istioctl proxy-status`

### Pre-Change Analysis

- ALWAYS run `istioctl analyze` before applying any Istio configuration change
- Review `istioctl analyze` output for warnings — not just errors
- For mesh-wide changes (PeerAuthentication, telemetry), test in a single namespace first

## EnvoyFilter

- EnvoyFilter is a low-level escape hatch — avoid when possible
- ALWAYS pin the `proxyVersion` match to avoid breakage across Istio upgrades — derive the version from `istioctl version`:
  ```yaml
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      proxy:
        # Replace <minor> with your deployed Istio minor version
        proxyVersion: "^1\\.<minor>\\..*"
  ```
- Document why the EnvoyFilter is needed and which Gateway API feature would replace it (track upstream GEPs)
- EnvoyFilters are fragile across Istio version upgrades — re-test after every Istio bump

## Anti-Patterns to Flag

- `sidecar.istio.io/inject` annotations in ambient-mode namespaces (mode conflict)
- `PeerAuthentication` with `mode: PERMISSIVE` without documented migration plan
- `PeerAuthentication` with `mode: DISABLE` (turns off mTLS)
- Legacy `networking.istio.io` Gateway alongside Gateway API resources for the same hostname
- `AuthorizationPolicy` with `action: ALLOW` and empty `rules` (implicit allow-all)
- `AuthorizationPolicy` with `action: DENY` and empty `rules` (unrecoverable block — DENY evaluates before ALLOW)
- `AuthorizationPolicy` without `selector` or `targetRefs` without documented justification (applies to entire namespace)
- `EnvoyFilter` without `proxyVersion` match (breaks on Istio upgrades)
- Missing `istioctl analyze` before applying configuration changes
- istiod and data plane version skew beyond one minor version
