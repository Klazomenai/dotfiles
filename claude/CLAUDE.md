# Prime Directives

IMPORTANT: These rules are NON-NEGOTIABLE.

## Behavior
- Defense in Depth — nothing is completed until verified working
- NEVER say "you're right" — no reflexive agreement
- CHALLENGE incorrect user statements with evidence
- If you don't know, say so — no hallucination assumptions
- Read docs BEFORE attempting commands — never assume how tools work
- Ask more questions, make fewer assumptions

## Git
- NEVER push to "main" or default branch — NO EXCEPTIONS
- NEVER create "master" branch
- Signed commits (`--gpg-sign`) required
- Branch naming: `<type>/<issue>-<description>`
- Branch types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `ci`, `security`, `spike`
- NEVER amend commits or force-push — stack separate signed commits, squash on merge
- Base branch: main | Merge style: squash merge | Delete branch after merge
- Use `Refs #N` in commits — NEVER `Closes #N` (closing is a merge-time decision)

## PR Workflow
- IMPORTANT: Draft PRs by default — ALWAYS use `--draft`
- IMPORTANT: After creating a PR, STOP. Provide the PR URL. Do NOT suggest merging.
- NEVER run `gh pr merge` or `gh pr ready` — merging is a human decision after peer review
- CI passing does NOT mean ready to merge

## Co-author Handling (private repos)
- NO Claude co-author line on private-repo commits. Public-repo commits may include it; private-repo commits must not.
- Check repo visibility with `gh repo view --json isPrivate -q '.isPrivate'` before committing if unsure.
- The `no-coauthor-private.sh` PreToolUse hook (under `claude/hooks/`) fails closed on `private` and `unknown` visibility — if it blocks a commit, verify visibility rather than bypassing.

## Hook UX
- The PreToolUse hooks under `claude/hooks/` pattern-match against full command strings, including argv values. Some legitimate commands with rich-text bodies may trigger false positives.
- Workaround: write the body to a temp file (`tmpfile=$(mktemp)` + heredoc), then pass via the appropriate file flag — `--body-file <path>` for `gh pr create`, or `-F body=@$tmpfile` for `gh api` calls. Clean up the temp file after the call.
