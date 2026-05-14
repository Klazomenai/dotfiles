# Agent Operating Rules — Concourse Domain

This file is the concourse-domain agent profile addendum, written to
complement the universal rules in `claude/profiles/_universal.md`
and the workflow knowledge in `claude/skills/concourse/SKILL.md`.
The rules below are the concourse-specific additions for autonomous agents.

This file is intentionally not referenced from
`claude/skills/concourse/SKILL.md` — Claude Code never auto-loads it.

## Pipeline Allowlist

The universal allowlist posture in `_universal.md` applies to pipelines
and Concourse targets. Concourse-specific reinforcement:

- Write operations — `fly set-pipeline`, `fly unpause-pipeline`,
  `fly trigger-job`, `fly abort-build`, and `fly destroy-pipeline` —
  must target a pipeline in the configured allowlist. If you cannot
  confirm the target pipeline is allowlisted, refuse and surface the
  pipeline name and applicable allowlist to the operator.
- Read operations (`fly get-pipeline`, `fly jobs`, `fly builds`,
  `fly watch`) may be less restricted than write operations, but if a
  read allowlist is configured it must still be honoured. Every `fly`
  invocation must carry an explicit `-t TARGET` flag — never rely on
  the default target.
- Pipeline creation via `fly set-pipeline` on a pipeline name not
  already in the allowlist is a mutation against the allowlist itself —
  refuse until the operator explicitly adds the pipeline name to the
  allowlist. Operator confirmation alone does not substitute for an
  allowlist update.

## Destructive Operation Gating

- `fly destroy-pipeline` is a high-risk mutation per `_universal.md` —
  it permanently removes the pipeline and all its build history.
  Per-pipeline confirmation applies; surface the pipeline name to the
  operator before invoking. Never include in automation or propose it
  as a routine cleanup step.
- `fly pause-pipeline` and `fly unpause-pipeline` affect all jobs in
  the pipeline simultaneously — per-pipeline confirmation applies.
- `fly trigger-job` bypasses normal resource-trigger logic; surface
  the job name and pipeline to the operator before invoking.
- `fly abort-build` terminates a running build; surface the build
  reference to the operator before invoking.
- `fly prune-worker` removes a worker from the cluster — high-risk;
  per-target confirmation applies.
- `fly clear-task-cache` can force all tasks to re-download
  dependencies — surface the scope to the operator before invoking.

## Fly CLI Credential Handling

- Never pass a Concourse token or client secret inline in a `fly`
  command argument. If authentication is required, direct the operator
  to run `fly login` interactively in their own session. Any
  non-interactive authentication step that requires embedding a
  credential value in argv must be performed by the operator directly —
  never construct such a command line on their behalf.
- The `-t TARGET` value in `.flyrc` can reference a named target whose
  stored credentials include a token. Never echo the full contents of
  `.flyrc` or any `fly targets --json` output that includes token
  fields. Refer to targets by name only.
- If tool output from a `fly` command contains a field that appears
  token-shaped (long opaque string, `bearer`, `access_token`, or
  `token` key), redact it before including the output in your response.
  Apply the same treatment as Vault tokens per `_universal.md`.
- `fly login -t TARGET -c URL` is the correct form for target
  configuration — it prompts interactively and never requires a token
  on the command line. Never construct a non-interactive `fly login`
  invocation that embeds credential values in argv.

## Anti-Patterns

- `fly set-pipeline`, `fly unpause-pipeline`, `fly trigger-job`, or
  `fly abort-build` targeting a pipeline outside the configured allowlist
- `fly destroy-pipeline` without explicit per-pipeline operator
  confirmation
- `fly` invocations without an explicit `-t TARGET` flag
- Passing a token or client secret inline in a `fly` command argument
- Echoing `.flyrc` contents or `fly targets` output that includes token
  fields
- Including `fly destroy-pipeline` in automation or scripts
- `fly login` with credential values embedded in argv rather than
  supplied interactively
