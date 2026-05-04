# Git + GitHub Skill — Orchestrator Addendum

This file contains rules that only apply when this skill is consumed by an
autonomous agent — a Claude persona embedded in a long-running orchestrator
(e.g. an Anthropic API tool-use loop) that operates on GitHub via `gh` or
the GitHub REST/GraphQL APIs.

This file is **intentionally not referenced from `SKILL.md`** — Claude Code
will not auto-load it for human users. The orchestrator is expected to fetch
this file by path at boot and concatenate it onto the persona's system
prompt alongside the universal `SKILL.md` body.

The universal workflow rules in `SKILL.md` apply equally to both audiences.
The rules below are layered on top.

## Repo Allowlist Enforcement

Every write operation (issue create, edit, comment, PR create, PR comment,
review reply, push) must verify the target repository is in the
orchestrator's allowlist before invoking the underlying tool.

- Allowlist is fail-closed: empty list = refuse all writes.
- Refusal must be visible to the operator with a clear explanation —
  which repo, why refused.
- Read-only operations (issue view, PR view, etc.) may have a wider or
  empty allowlist depending on the orchestrator's configuration — but
  writes are always gated.

## Token & Secret Redaction

- Tool output returned to the model must be sanitised for tokens, secrets,
  and other sensitive values before the model sees it.
- Use the orchestrator's shared redaction layer (e.g. a project-level
  redaction package) — do not write per-tool ad-hoc filters.
- Command lines logged for audit purposes must be token-redacted at log
  time, not at display time.

## Mutation Gating — Explicit Confirmation

State-change mutations require explicit confirmation in the operator's
most recent message:

- Closing or reopening an issue
- Marking a PR ready for review (already universally forbidden by
  `SKILL.md`, but reinforced here)
- Pushing code, even to a feature branch
- Resolving a review thread
- Editing or deleting issue / PR / comment content

Rules:

- Don't infer consent from earlier conversation.
- Ambiguity = ask, don't act.
- A separate `confirm` boolean (extracted from the operator's words, not
  auto-filled) is the preferred shape for tool input schemas where
  applicable.

## Copilot Review Threads

The universal Copilot Review Workflow in `SKILL.md` applies, with an
additional gate:

- NEVER autonomously resolve Copilot review threads. Always reply with a
  fix-commit reference; the operator resolves.
- "Apply all suggestions" is not a valid action without explicit operator
  consent on each comment.

## PR Lifecycle Gates

- Never call `gh pr merge`. CI green is not consent.
- Never call `gh pr ready`. The operator decides when a draft becomes ready.
- Never push code without explicit operator confirmation in the most recent
  message — even on a feature branch the orchestrator has been working on.

## Audit Trail

Every write tool invocation should leave an audit record containing:

- The command and (token-redacted) arguments
- The target repository and resource (issue / PR number, branch, etc.)
- The result (success / error, response status, response body summary)
- The timestamp

Audit records should be observable by the operator (Loki, structured
stderr, file). Tool output returned to the model is not sufficient — it
disappears from the conversation.

## Anti-Patterns (orchestrator-only)

- Acting on a write request without checking the repo allowlist first
- Returning unredacted tool output to the model
- Inferring mutation consent from earlier conversation rather than the
  most recent operator message
- Resolving Copilot review threads autonomously
- Calling `gh pr merge` / `gh pr ready` even on a green PR
- Pushing code without explicit operator confirmation
- Logging full command lines (including token values) for audit
