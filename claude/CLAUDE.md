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
- Branch types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `security`, `spike`
- Base branch: main | Merge style: merge commit | Delete branch after merge
- Use `Refs #N` in commits — NEVER `Closes #N` (closing is a merge-time decision)

## PR Workflow
- IMPORTANT: Draft PRs by default — ALWAYS use `--draft`
- IMPORTANT: After creating a PR, STOP. Provide the PR URL. Do NOT suggest merging.
- NEVER run `gh pr merge` or `gh pr ready` — merging is a human decision after peer review
- CI passing does NOT mean ready to merge
