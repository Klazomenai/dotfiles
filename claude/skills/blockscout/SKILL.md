---
name: blockscout
description: Blockscout blockchain explorer deployment safety, Helm chart configuration, database migration, microservice patterns, and operational troubleshooting. Use when working with Blockscout backend, frontend, Rust microservices, or blockscout-stack Helm charts.
---

# Blockscout Skill

## Version Compatibility

- Chart v4.x requires backend >= 9.2.0 (distributed Elixir, NFT storage restructured)
- Chart v3.x requires backend >= 8.0.0 (Docker registry moved to GHCR, API-only image removed)
- Stats chart image pinned to v2.4.0 by default — verify compatibility when overriding
- When enabling user-ops-indexer, frontend must include `NEXT_PUBLIC_USER_OPS_INDEXER_URL`
- ALWAYS check the chart CHANGELOG.md before upgrading chart versions

## Helm Deployment Safety

- Template before deploying: `helm template <release> blockscout-stack --version <ver> -n <ns> -f values.yaml`
- Default image tags for backend, frontend, and user-ops-indexer are `latest` — ALWAYS override with pinned tags
- Backend `terminationGracePeriodSeconds` defaults to 300 — do not reduce below 120 (indexer needs graceful shutdown for DB consistency)
- Backend liveness probe `initialDelaySeconds` is 100, readiness is 60 — these are intentionally high due to Elixir startup time. Do not reduce without testing.
- Verify rendered manifests for `APPLICATION_MODE`, `DISABLE_INDEXER`, and `RELEASE_COOKIE` values
- Resource defaults: backend 1-2 CPU / 2-4Gi, frontend 250-500m / 256Mi-1Gi, stats 250m / 512Mi

## Database Operations

- Migrations run automatically via init container: `Elixir.Explorer.ReleaseTasks.create_and_migrate()`
- ALWAYS back up the database before upgrades — Elixir migrations are forward-only, no automatic rollback
- When `separateApi.enabled`, migrations run as a Helm pre-install/pre-upgrade Job instead of init container
- Failed migration Jobs persist for debugging (`hook-delete-policy: hook-succeeded`) — check `kubectl get jobs -n <ns>` after upgrade failures
- Stats, user-ops-indexer, and other Rust services use separate databases — verify `STATS__DB_URL` and `USER_OPS_INDEXER__DATABASE__CONNECT__URL` point to different instances
- PostgreSQL 12-17 supported

## Separate API/Indexer Pattern

- Enable with `blockscout.separateApi.enabled: true` — splits into API (`APPLICATION_MODE=api`) and Indexer (`APPLICATION_MODE=indexer`) Deployments
- Requires backend >= 6.6.0 (chart >= 1.6.0)
- Indexer image uses `-indexer` tag suffix — when pinning tags, confirm both `<tag>` and `<tag>-indexer` exist
- Distributed Elixir activates automatically: `RELEASE_DISTRIBUTION=name`, inet_dist ports 9138-9139
- RELEASE_COOKIE defaults to `secret` — ALWAYS change in production (it is the Erlang distribution authentication cookie)
- Only ONE indexer replica is supported — do not set `blockscout.replicaCount > 1` on the indexer
- API replicas scale independently via `separateApi.replicaCount`

## Microservice Configuration

- Rust services use double-underscore env var pattern: `{SERVICE}__{SECTION}__{KEY}=value`
- Common ports: HTTP 8050, gRPC 8051, metrics 6060. Exception: sig-provider uses port 8043.
- Health endpoints: backend `/api/health/liveness` and `/api/health/readiness`, frontend `/api/healthz`, Rust services use gRPC health check protocol
- Stats requires `STATS__BLOCKSCOUT_API_URL` — auto-set by chart when ingress exists, must be set manually otherwise
- Stats conditional start: waits for backend indexing to reach `blocks_ratio >= 0.98` before computing charts

## Monitoring & Health

- Built-in Prometheus: `config.prometheus.enabled: true` creates ServiceMonitor for backend and stats
- Blackbox exporter probe: `config.prometheus.blackbox.enabled: true` probes `/api/health` externally
- PrometheusRule alerts: `BlockscoutNoNewBatches` fires when latest batch timestamp exceeds `batchTimeMultiplier * batch_average_time`
- Default `healthyBlockPeriod: 300` (5 minutes) — adjust per network's expected block time
- Metrics ingress whitelist (`config.prometheus.ingressWhitelist`) restricts `/metrics` to private subnets — do not disable in production
- When running separateApi: Prometheus rules target the indexer service specifically

## Secret Management

Four methods, in order of preference:

1. `envFrom` + `secretRef` — reference existing K8s Secret (preferred, lifecycle managed externally)
2. `extraEnv` + `secretKeyRef` — reference individual keys from existing Secrets
3. `envFromSecret` — chart creates a Secret from inline values (recoverable via `helm get values`)
4. `env` — plain env vars (visible in rendered manifests)

DATABASE_URL, NFT storage credentials, and RELEASE_COOKIE should ALWAYS use method 1 or 2.

## Upgrade & Rollback

- Rollback: `helm rollback <release> <revision> -n <ns>` — check `helm history` for last good revision
- Rolling back the Helm release does NOT roll back database schema — older app versions may be incompatible with newer schema
- For major version downgrades, restore from database backup
- NEVER use `--reuse-values` across blockscout-stack chart version bumps — new required env vars will be missed
- Breaking change gates: v4.0.0 (distributed Elixir + NFT), v3.0.0 (GHCR registry + API-only removed)

## Troubleshooting

- Backend not starting: check init container / migration Job logs first. Elixir startup is slow (60-100s) — do not restart prematurely.
- `CrashLoopBackOff`: check DATABASE_URL connectivity, missing required env vars, or schema version mismatch
- Stats not populating: verify `STATS__BLOCKSCOUT_API_URL` is reachable from stats pod, check conditional start thresholds
- Frontend 502: verify `NEXT_PUBLIC_API_HOST` points to the backend, verify backend readiness probe is passing
- Distributed Elixir issues (separateApi): verify inter-pod connectivity on ports 9138-9139, verify RELEASE_COOKIE matches, check NetworkPolicy

## Anti-Patterns to Flag

- Deploying with default image tags (`latest`) for backend, frontend, or user-ops-indexer
- Leaving RELEASE_COOKIE as `secret` in production (Erlang distribution authentication bypass)
- Using `envFromSecret` for DATABASE_URL or credentials (recoverable via `helm get values`)
- Upgrading chart major version without checking CHANGELOG.md
- Reducing backend liveness probe `initialDelaySeconds` below 60 (Elixir startup is slow — premature restarts)
- Enabling `separateApi` without verifying backend image >= 6.6.0
- Missing `STATS__BLOCKSCOUT_API_URL` when stats are enabled without ingress (stats silently fails)
- Upgrading chart without database backup (migrations are forward-only)
- Setting `blockscout.replicaCount > 1` on the indexer (only one indexer replica supported)
- `helm upgrade --reuse-values` across chart version bumps (misses new required env vars)
- Pinning backend tag without confirming `<tag>-indexer` variant exists when separateApi is enabled
- Disabling `config.prometheus.ingressWhitelist` in production (exposes metrics publicly)
- Running database-heavy operations (reindexing, stats force-update) without increasing resource limits
