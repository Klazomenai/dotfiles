---
name: terraform
description: Terraform lifecycle guidance, plan review, state operations, and safety checks. Use when working with .tf files, terraform commands, or infrastructure-as-code tasks.
---

# Terraform Skill

## Version Enforcement

Before any Terraform operation:

1. Run `terraform version` to check the installed version
2. Run `terraform version -json` and compare against `required_version` in `.tf` files
3. If there is a version mismatch or no `required_version` constraint, **flag it and stop**
4. Once per session, use `WebSearch` to check the latest stable Terraform release — flag if the installed version is more than one minor version behind
5. If `required_version` constraints are loose (e.g. `>= 1.0`), recommend tightening to pessimistic constraint (e.g. `~> 1.9.0`)

## Plan Review & Safety

### Before `terraform plan`

- Confirm which workspace/environment is targeted: `terraform workspace show`
- Verify backend is initialized: `terraform init -backend=true` if needed
- Check for uncommitted `.tf` changes — plan should reflect the code on disk

### Reviewing Plan Output

- **Always run `terraform plan` before `terraform apply`** — no exceptions
- Flag any resources marked for **destroy** or **replace** (force replacement)
- Flag any changes to critical resource types (extend per provider): `google_container_cluster`, `google_container_node_pool`, `google_sql_database_instance`, `google_project_iam_*`, `google_kms_key_ring`, `google_kms_crypto_key`, `kubernetes_namespace`
- Verify resource counts: additions, changes, and destructions should match expectations
- Look for unexpected changes caused by provider upgrades or state drift
- If the plan shows `0 to add, 0 to change, 0 to destroy`, confirm this is expected before proceeding

### Before `terraform apply`

- NEVER run `terraform apply -auto-approve` — always require interactive confirmation
- NEVER run `terraform apply` without showing the user the plan output first
- If applying a saved plan file, confirm the plan file was generated in the same session
- For destructive changes: ask the user to explicitly confirm each resource being destroyed

## Full Lifecycle Guidance

### init

- Always run `terraform init` when switching between environments or after pulling changes
- Check `.terraform.lock.hcl` is committed — provider versions must be pinned
- If `init` fails with backend errors, investigate — do NOT delete `.terraform/` as first resort

### plan

- Use `-out=tfplan` to save plan files for consistent applies
- Use `-var-file` to explicitly select the variable file for the target environment
- For large infrastructure, use `-target` to scope plans — but warn that targeted plans can miss dependencies

### apply

- Prefer applying from a saved plan file: `terraform apply tfplan`
- After apply, verify the output matches expectations

### destroy

- NEVER run `terraform destroy` without explicit user confirmation
- Always run `terraform plan -destroy` first to review what will be removed
- Prefer targeted destroys (`-target`) over full environment destroys

### import

- Before importing, verify the resource exists in the cloud provider
- Write the resource block in `.tf` FIRST, then run `terraform import`
- After import, run `terraform plan` to verify the imported state matches the config
- Fix any drift between config and actual state before proceeding

## State Operations

State operations are **dangerous and often irreversible**. Extra caution required.

### General State Rules

- ALWAYS back up state before any state operation: `terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate`
- NEVER edit state JSON manually
- NEVER run `terraform state rm` without understanding what depends on the resource
- After any state operation, immediately run `terraform plan` to verify consistency

### terraform state mv

- Use for renaming resources or moving between modules
- Verify both source and destination paths before executing
- Run `terraform plan` after to confirm no changes (move should be a no-op in plan)

### terraform state rm

- Only use when intentionally orphaning a resource (keeping the cloud resource but removing from Terraform management)
- Confirm the user understands the resource will NOT be destroyed — just unmanaged
- Document WHY the resource was removed from state

### terraform state replace-provider

- Required during provider namespace migrations
- Back up state first
- Run `terraform init` after replacement

### State Corruption Recovery

- Pull the current state: `terraform state pull > current.tfstate`
- If using a remote backend (GCS, S3), check for state lock issues: `terraform force-unlock <LOCK_ID>` (only after confirming no other operations are running)
- If state is corrupted beyond repair, consider importing resources back from cloud provider
- Check version history in the remote backend (GCS versioning, S3 versioning) for rollback options

## Safety Checklist

Before ANY Terraform command that modifies state:

- [ ] Correct workspace/environment?
- [ ] Correct variable file?
- [ ] Plan reviewed and understood?
- [ ] Destructive changes explicitly approved?
- [ ] State backed up (for state operations)?
- [ ] Changes committed to version control?

## Multiple Root Modules

When working with repositories that split Terraform into multiple root modules (separate working directories with independent backends, e.g. `terraform/bootstrap/`, `terraform/network/`, `terraform/cluster/`):

- Run `terraform init` separately in each root module directory — root modules do NOT share state (child modules called within a root module share that root module's state)
- Use `terraform output` or the `terraform_remote_state` data source to pass values between root modules — NEVER hardcode values from one into another
- Verify the backend state key/prefix is unique per root module to prevent state collisions
- Apply root modules in dependency order: bootstrap → kms → network → cluster → iam → dns
- When reviewing plans across root modules, check that referenced outputs from upstream modules actually exist

## Anti-Patterns to Flag

- `terraform apply -auto-approve` in any context
- Loose provider version constraints (`>=` without upper bound)
- Missing `required_version` block
- `.terraform/` or `.tfstate` files committed to git
- Secrets in `.tfvars` files (use environment variables or secret managers)
- `terraform taint` (deprecated — use `terraform apply -replace=<resource>`)
- Running `terraform init -reconfigure` without understanding why
