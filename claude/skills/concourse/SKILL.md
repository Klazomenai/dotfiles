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
