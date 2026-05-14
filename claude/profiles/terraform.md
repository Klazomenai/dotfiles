# Agent Operating Rules — Terraform Domain

This file is the terraform-domain agent profile addendum, written to
complement the universal rules in `claude/profiles/_universal.md`
and the workflow knowledge in `claude/skills/terraform/SKILL.md`.
The rules below are the terraform-specific additions for autonomous agents.

This file is intentionally not referenced from
`claude/skills/terraform/SKILL.md` — Claude Code never auto-loads it.

## Apply Gating

The terraform SKILL.md prohibits `terraform apply -auto-approve` and
requires plan review before any apply. For autonomous agents, harden both:

- `terraform apply` requires an explicit operator go-ahead per the
  high-risk mutation gating in `_universal.md` — never invoke it
  autonomously based on plan output alone.
- `terraform apply -auto-approve` is refused outright in autonomous
  mode. No flag or argument bypasses the confirmation requirement.
- `terraform plan` output must be surfaced verbatim to the operator
  before any apply consideration. Do not summarise or paraphrase —
  the operator reviews the literal plan text.
- If applying from a saved plan file (`terraform apply tfplan`),
  confirm the plan file was generated in the current session before
  surfacing it for operator review.

## Destroy Refusal

- `terraform destroy` is refused outright in autonomous mode
  regardless of operator confirmation. Unlike other high-risk
  mutations, no per-target confirmation unlocks it — if the operator
  needs a destroy, they invoke it directly.
- `terraform destroy -target=<resource>` is refused on the same basis;
  the `-target` flag does not change the risk profile.
- `terraform plan -destroy -out=<plan>` is refused — it produces a
  saved plan whose only downstream use is a destroy apply. Running
  `terraform plan -destroy` without `-out` to surface the destroy scope
  for operator review is acceptable.

## State Mutation Gating

State operations are high-risk mutations per `_universal.md` — state
divergence can produce destructive plan output on the next run.
Per-target confirmation applies to every state command.

- `terraform state rm` — per-target confirmation required. Before
  invoking, surface the resource address and confirm the operator
  understands the cloud resource will NOT be destroyed, only removed
  from Terraform management.
- `terraform state mv` — per-target confirmation required. Surface
  source and destination addresses before invoking.
- `terraform import` — per-target confirmation required. The `.tf`
  resource block must exist before import; surface the resource address
  and cloud ID to the operator before invoking.
- `terraform taint` is deprecated — never propose it. Surface
  `terraform apply -replace=<resource>` as the correct path, with
  per-target confirmation.
- `terraform untaint` is deprecated — never propose it.
- State backup (`terraform state pull > backup-<timestamp>.tfstate`)
  must precede any state mutation in the same operator session. The
  agent does not perform the backup unilaterally — surface the
  requirement to the operator and wait for confirmation before
  proceeding to the mutation.
- `terraform force-unlock <lock-id>` is a high-risk state operation.
  Per-target confirmation applies; never invoke unless the operator has
  explicitly confirmed no other operation is in flight.

## Workspace Allowlist

The universal allowlist posture in `_universal.md` applies to
workspaces. Terraform-specific reinforcement:

- All operations must target a workspace in the configured allowlist.
  If you cannot confirm the target workspace is allowlisted, refuse and
  surface the workspace name and applicable allowlist to the operator.
- `terraform workspace new <name>` is a mutation against the workspace
  namespace — gated by the same allowlist and confirmation rules.
- `terraform workspace select <name>` is a session-state mutation.
  Carry the workspace name explicitly per operation rather than
  relying on ambient session state; do not assume the output of
  `terraform workspace show` at task-start reflects the intended target.
- Never infer the target workspace from `terraform workspace show`
  output alone. Require the operator's explicit description of the
  intended workspace.

## Anti-Patterns

- `terraform apply -auto-approve` in any context
- `terraform apply` without surfacing plan output verbatim to the operator
- `terraform apply` without explicit operator go-ahead
- `terraform destroy` in autonomous mode (any form — full or targeted)
- `terraform plan -destroy -out=<plan>` (produces a destroy-apply artefact)
- `terraform state rm`, `terraform state mv`, or `terraform import`
  without per-target operator confirmation
- `terraform force-unlock` without operator confirmation of no
  concurrent operations
- Proposing `terraform taint` or `terraform untaint` (deprecated)
- Performing the state backup step unilaterally, or skipping it
- Inferring the target workspace from ambient session state rather than
  the operator's explicit description
- Operating on a workspace outside the configured allowlist
