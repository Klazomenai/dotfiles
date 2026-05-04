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

## Anti-Patterns (operator-only)

- Adding Claude co-author to private-repo commits
- Bypassing the `no-coauthor-private.sh` hook on visibility=unknown

## Universal Rules That Used To Live Here

The following rules previously lived in this file but were promoted to the
universal `SKILL.md` after a Copilot review on dotfiles PR #98 noted that
they apply equally to autonomous agents:

- **Public Repo Security** — sanitisation of public-repo artefacts now
  lives in `SKILL.md`. Generated text from any source (operator, tool
  output, prior conversation) gets the same scrutiny.
- **Sensitive Values in Command Arguments** — secret-handling in argv now
  lives in `SKILL.md`. Audit-log leakage applies to agents as much as
  shell history applies to humans.

If you find yourself wanting to put a "this applies to humans only" rule
in this file, sense-check whether an autonomous agent could trigger the
same failure mode. If yes, the rule belongs in `SKILL.md`.
