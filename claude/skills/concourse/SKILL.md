---
name: concourse
description: Concourse CI pipeline safety, validation, secret management, and fly CLI guidance. Use when working with Concourse pipeline YAML, fly commands, task definitions, or Vault-integrated CI workflows.
---

# Concourse Skill

## Pipeline Validation

Before setting any pipeline:

1. **Validate first**: `fly validate-pipeline -c pipeline.yml` — catches YAML syntax errors and structural issues
2. **Review the diff**: `fly set-pipeline -t <target> -p <name> -c pipeline.yml` shows a diff before confirmation — read it carefully
3. NEVER skip validation — a broken pipeline can silently stop deployments

## Trigger Safety

### `trigger: true` Rules

- `trigger: true` means a job runs automatically when its upstream resource or `passed:` constraint is satisfied
- NEVER set `trigger: true` on destructive or maintenance jobs — these must be manual-only
- Examples of jobs that must NOT have `trigger: true`:
  - Database wipe/fresh-install jobs (e.g. `cnpg-fresh`, `redis-fresh`)
  - `fly destroy-pipeline` tasks
  - Any job with `kubectl delete` on stateful resources
  - Rollback jobs (should be deliberate, not automatic)
- Deployment jobs MAY have `trigger: true` if they are idempotent (e.g. `helm upgrade --install`)

### Job Ordering

- Use `passed: [job-name]` to enforce dependency ordering — a job only runs after its dependencies succeed
- Verify `passed:` constraints match the intended dependency graph — a missing constraint means jobs can run in parallel when they shouldn't
- Use `serial: true` on jobs that modify shared state (Helm releases, database schemas, Vault config) — prevents concurrent runs
- Use `serial_groups` when multiple jobs must not run simultaneously (e.g. all Helm deploys to the same namespace)

## Secret Management

### Credential Manager (Vault)

- Concourse integrates with Vault as a credential manager — secrets are referenced as `((variable))` in pipeline YAML
- Vault path: secrets are looked up at `<path-prefix>/<team>/<pipeline>/<variable>` then `<path-prefix>/<team>/<variable>`
- The Concourse Vault policy should be **read-only** on scoped paths:
  ```hcl
  path "concourse/main/*" {
    capabilities = ["read"]
  }
  ```
- NEVER grant write, list, or delete capabilities to the Concourse Vault role

### Secret Anti-Patterns

- NEVER hardcode secrets in pipeline YAML — use `((variable))` syntax
- NEVER hardcode secrets in task scripts — pass via `params:` from `((variable))`
- NEVER echo or log secret values in task scripts — use `set +x` before handling secrets
- If a secret must be written to a file in a task, ensure the task container is ephemeral (it is by default in Concourse)

## Task Configuration

### Image Resources

- ALWAYS pin image versions — never use `tag: latest`:
  ```yaml
  image_resource:
    type: registry-image
    source:
      repository: alpine
      tag: "3.21"  # pinned, not "latest"
  ```
- Use digest pinning for maximum reproducibility (separate `digest` field, not appended to tag):
  ```yaml
  image_resource:
    type: registry-image
    source:
      repository: alpine
      tag: "3.21"
      digest: "sha256:..."  # pin to exact image digest
  ```

### Task Params

- Pass configuration via `params:` — never hardcode values in task scripts
- Use `((variable))` for secrets in params
- Document required params in the task YAML file

### Task Scripts

- Prefer inline `run:` for simple commands, external scripts for complex logic
- Scripts should be idempotent — safe to re-run without side effects
- Include `set -euo pipefail` at the top of all bash scripts
- Add timeouts to long-running operations to prevent stuck tasks

## Fly CLI Safety

### Target Management

- ALWAYS use `-t <target>` on every `fly` command — never rely on the default target
- Verify the target before destructive operations: `fly targets` shows all configured targets
- Use `fly login -t <target> -c <url>` to configure targets — never edit `.flyrc` manually

### Destructive Commands

- **`fly destroy-pipeline`** — permanently removes a pipeline and all its build history. ALWAYS confirm with the user before running. NEVER include in automation.
- **`fly clear-task-cache`** — can cause pipeline tasks to re-download all dependencies. Confirm intent.
- **`fly prune-worker`** — removes a worker from the cluster. Only use for decommissioned workers.

### Pipeline Management

- `fly pause-pipeline` / `fly unpause-pipeline` — useful for temporary maintenance windows
- `fly pause-job` / `fly unpause-job` — pause individual jobs without affecting the whole pipeline (useful as a circuit-breaker)
- `fly trigger-job -t <target> -j <pipeline>/<job>` — manually trigger a specific job
- `fly watch -t <target> -j <pipeline>/<job>` — stream logs from the latest build

## Pipeline Structure

### Resource Hygiene

- Pin resource versions where possible (Git branch, Docker tag, Helm chart version)
- Use `check_every: never` on resources that should only be checked when triggered by webhooks
- Name resources descriptively — `akeyra-repo` not `git` or `repo`
- Use lowercase for all resource names, pipeline names, and job names in YAML — reserve capitalised forms (e.g. `AKeyRA`) for documentation only

### Group Organisation

- Use `groups:` to organise jobs into logical sections (e.g. `deploy`, `maintenance`, `monitoring`)
- Put destructive jobs in a separate group to reduce accidental clicks in the UI

### Self-Update Pattern

- A Concourse pipeline can watch its own definition in Git and update itself
- The self-update job should use `fly set-pipeline` with the `--non-interactive` flag
- Ensure the self-update job has `serial: true` to prevent concurrent self-updates

## Vault Auth Configuration

- Use Kubernetes auth backend — no static tokens or AppRole secrets
- Set `authBackendMaxTTL` to a short duration (e.g. `15m`) — tokens auto-renew
- Verify the Vault role binds to the Concourse web ServiceAccount specifically, not a wildcard

## Anti-Patterns to Flag

- `trigger: true` on destructive or maintenance jobs
- Hardcoded secrets in pipeline YAML or task scripts
- `fly set-pipeline` without prior `fly validate-pipeline`
- `fly destroy-pipeline` in automation or scripts
- `image_resource` with `tag: latest` or missing tag
- Missing `serial: true` on jobs that modify shared state (Helm releases, databases, Vault)
- `((variable))` referenced but never stored in Vault (pipeline will stall waiting for secret)
- Missing `passed:` constraints that allow jobs to run out of order
- `fly` commands without `-t <target>` flag
- Vault policy with write/delete capabilities for Concourse role

## Local Reference Sources

When writing or reviewing Concourse pipelines, tasks, or configuration, **read local upstream clones first** before web searching. These repositories are available locally and cover all Concourse topics relevant to K8s-based projects.

### Lookup Protocol

1. Identify the topic (pipeline syntax, task config, Helm values, auth, etc.)
2. Find the matching repository from the table below
3. Read the relevant files directly
4. Only fall back to web search if local sources don't cover the topic

### Topic-to-Repository Mapping

| Topic | Repository | Key Paths Within Repo |
|-------|-----------|----------------------|
| Pipeline YAML syntax (steps, resources, jobs) | `docs` | `docs/docs/` (steps/, resources/, jobs.md, pipelines/) |
| Task configuration | `docs` + `ci` | `docs/docs/tasks.md`, `ci/tasks/` |
| Resource types (built-in + protocol) | `docs` + `semver-resource` | `docs/docs/resource-types/`, `semver-resource/check,in,out/` |
| Pipeline examples and templates | `examples` | `pipelines/`, `pipelines/templates/`, `pipelines/multi-branch/` |
| Helm chart values (K8s deployment) | `concourse-chart` | `values.yaml`, `templates/`, `Chart.yaml` |
| Variables and credential managers | `docs` | `docs/docs/vars.md` |
| Auth and identity (OIDC, LDAP) | `dex` + `docs` | `dex/docs/`, `docs/docs/auth-and-teams/` |
| Core internals (API, engine, scheduler) | `concourse` | `atc/api/`, `atc/engine/`, `atc/scheduler/`, `atc/worker/` |
| Design decisions and feature rationale | `rfcs` | Individual RFCs, `DESIGN_PRINCIPLES.md` |
| CI self-hosting patterns | `ci` | `concourse.yml`, `pr.yml`, `reconfigure.yml`, `tasks/` |
| Security hardening | `docs` | `docs/docs/operation/security-hardening.md` |
| Web security (auth, RBAC) | `concourse` | `atc/api/auth/`, `atc/api/accessor/roles.go` |

Two additional repos (`concourse-bosh-release`, `concourse-bosh-deployment`) are available locally but omitted — BOSH deployment model, not used in K8s-based projects.

Repository absolute paths are resolved via the private memory file (not stored in this public skill file).
