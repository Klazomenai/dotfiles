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

## Write Operations — Operator Intent Required (Universal Layer)

Every write operation must reflect intent in the operator's most recent
message. The user's request itself is the consent for that operation —
e.g. "Chips, file an issue against bridge titled X" is sufficient consent
to create the issue, no separate confirm step needed.

Applies to ALL writes without exception: issue create / comment / edit,
PR create / comment / review-reply, label add, milestone change, etc.

Rules:

- Don't infer write consent from earlier conversation. The relevant
  message is the most recent operator turn.
- Don't broaden scope ("close all open issues") without explicit
  confirmation on each target — a literal request is per-target consent;
  set-quantified requests are not.
- Ambiguity = ask, don't act.

If the operator's most recent message does not literally describe the
write you're considering, refuse and ask.

## High-Risk Mutations — Additional Confirmation Required

Even when the operator's most recent message describes the action,
high-risk mutations require a separate confirmation field/utterance
because the consequences are unrecoverable, compound, or affect other
people's expectations:

- Closing or reopening an issue
- Pushing code (even to a feature branch the orchestrator has been
  working on)
- Resolving a review thread
- Editing or deleting issue / PR / comment content already published
- Calling `gh pr ready` (also universally forbidden in `SKILL.md`) —
  refuse outright
- Calling `gh pr merge` (also universally forbidden in `SKILL.md`) —
  refuse outright

For tools that support it, prefer a `confirm` boolean in the input
schema that the persona must extract from the operator's words (not
auto-fill). For tools listed as "refuse outright", the persona must
not register them as callable at all, regardless of operator
confirmation.

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
