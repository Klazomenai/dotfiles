# Git + GitHub Skill — Operator Addendum

This file contains rules that only apply when this skill is consumed by a
human at a Claude Code CLI (the "operator"). Autonomous agents that vendor
or link this skill should ignore this file — they have their own constraints
encoded in `orchestrator.md`.

The universal workflow rules live in [SKILL.md](SKILL.md) and apply to both
audiences.

## Co-author Handling

- NO Claude co-author line on private repos. Public-repo commits may include
  it; private-repo commits must not.
- Check repo visibility with `gh repo view --json isPrivate -q '.isPrivate'`
  before committing if unsure.
- The `no-coauthor-private.sh` PreToolUse hook fails closed on `private` and
  on `unknown` visibility — if the hook blocks a commit, verify visibility
  rather than bypassing.

## Hook False-Positive Workarounds

Claude Code's guardrail hooks pattern-match against full command strings,
including argument values. Some legitimate `gh api` invocations (review-thread
replies with rich-text bodies, PR creation with sample shell snippets in the
body) trigger false positives on the body content.

Workaround pattern:

- Write the body to a temp file (`tmpfile=$(mktemp)` + heredoc)
- Pass `-F "body=@$tmpfile"` to `gh api` (or `--body-file $tmpfile` to
  `gh pr create`) so the body content never appears in the command string
  the hook inspects
- Clean up the temp file after the call

This is the same temp-file pattern documented in the universal PR Review
Replies section of `SKILL.md`, but the *reason* (hook false positives) is
operator-specific. Autonomous agents have different (or no) hook layers and
use the temp-file pattern for shell-escaping reasons instead.

## Public Repo Security

CRITICAL — applies to ALL public-facing text in public repositories:

- NEVER reference private org names, private repo names, or internal
  infrastructure
- Sanitization applies to EVERYTHING: PR titles, PR bodies, commit messages,
  branch names — not just file contents
- Before creating a PR on a public repo: review title and body for any
  private/internal references
- `gh repo create --push` pushes straight to main — NEVER use `--push` flag

These rules exist because the operator's local environment may contain
private context (org names, internal hostnames, customer references) that
must not leak into public-facing text. Autonomous agents have controlled
inputs and a separate redaction layer — see `orchestrator.md` for the
agent-side equivalents.

## Sensitive Values in Command Arguments

- NEVER inline sensitive values (emails, keys, passwords) in command
  arguments — they leak into shell history, process tables, and conversation
  logs.
- Use `export VAR=value` as a separate step before invoking the command, or
  prompt the operator to set the env var themselves.
- Applies to all CLIs: `gh`, `terraform`, `gcloud`, `kubectl`, etc.

## Anti-Patterns (operator-only)

- Adding Claude co-author to private-repo commits
- Bypassing the `no-coauthor-private.sh` hook on visibility=unknown
- Inlining sensitive values in command arguments
- Pushing private content (private org / repo / hostname references) into
  public PR titles, bodies, or commit messages
