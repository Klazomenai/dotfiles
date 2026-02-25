---
name: github
description: Git and GitHub workflow guidance, including commits, branches, PRs, issues, reviews, and labels. Use when working with git commands, GitHub issues, pull requests, or code reviews.
---

# Git + GitHub Skill

## Commit Conventions

- Conventional commits format: `<type>(scope): description`
- Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `security`
- Signed commits required: always use `--gpg-sign`
- Use `Refs #N` in commit body — NEVER `Closes #N`, `Fixes #N`, or `Resolves #N` (closing is a merge-time decision)
- NO Claude co-author line on private repos — check repo visibility with `gh repo view --json isPrivate -q '.isPrivate'` before committing
- Lean workflow: `git commit --amend --no-edit && git push --force-with-lease`
- Commit emoji prefixes (in commit message, not branch): ✨ feat | 🐛 fix | 📝 docs | ♻️ refactor | 🧪 test | ⚙️ chore | 🔐 security | 🏗️ ci | ⚡ perf

## Branch Conventions

- NEVER push to "main" or default branch — NO EXCEPTIONS
- NEVER create "master" branch
- Naming: `<type>/<issue>-<description>` e.g. `feat/595-jaeger-tracing`, `fix/784-terraform-exit-code`
- Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `security`, `spike`
- Base branch: main | Merge style: merge commit | Delete branch after merge
- No emojis in branch names

## PR Workflow

- ALWAYS create PRs as draft: `gh pr create --draft`
- After creating a PR, STOP. Provide the PR URL. Do NOT suggest merging or next steps.
- NEVER run `gh pr merge` or `gh pr ready` — merging is a human decision after peer review
- CI passing does NOT mean ready to merge
- Conventional commit format for PR titles: `<type>(scope): description`
- PR title emojis go at the END of the title
- PR body format:
  ```
  ## Summary
  <1-3 bullet points>

  ## Test plan
  - [ ] Bulleted checklist of testing TODOs
  ```
- Use temp files for PR bodies to avoid hook false positives: write body to file, use `-F "body=@file"`

## Issue Conventions

- Conventional prefix on issue titles: `feat:`, `fix:`, `chore:`, etc.
- Emojis go at the END of issue titles
- Type emojis: 🐙 Epic | 🔍 Spike | 📊 Dashboard | 🔔 Alert | 🚪 Gateway | 🔐 Security | 🪦 Decommission
- Status emojis: ✅ Done | ❌ Blocked | ⏸️ Paused | 🚧 WIP | 📋 Planned

## Labels

- Standard: `epic`, `spike`, `bug`, `enhancement`, `refactor`, `techdebt`
- Namespaced: `app:*`, `env:*`, `fun:*`, `ws:*`, `depth:*`, `priority:*`, `provider:*`

## Copilot Review Workflow

When handling Copilot PR review comments, follow this process:

1. **Read** — `gh api repos/{owner}/{repo}/pulls/{pr}/comments`, filter top-level only (where `in_reply_to_id` is null)
2. **Discuss** — present each comment with assessment (agree/disagree/partial), explain reasoning with technical justification
3. **User decides** — wait for explicit confirmation on which comments to address
4. **Fix locally** — make the code changes
5. **Test locally before pushing** — run changed code from working tree (e.g. `bash -n`, `bash -x` with timeout). Reduce pipeline waste.
6. **Commit and push** — amend-push to same branch
7. **Reply inline** — write body to temp file, then `gh api repos/{owner}/{repo}/pulls/{pr}/comments -X POST -F "body=@$tmpfile" -F in_reply_to=<id>`, reference commit SHA

Rules:
- Push back on wrong suggestions with technical reasoning — not every comment is correct
- Reply to EVERY top-level comment, even when disagreeing
- Reference the fix commit SHA in replies where changes were made

## PR Review Replies

When replying to PR review comments:

- Write reply body to a temp file first to avoid hook false positives on `gh api` body content
- Pattern: `tmpfile=$(mktemp) && cat <<'EOF' > "$tmpfile" ... EOF` then `gh api ... -F "body=@$tmpfile" -F in_reply_to=<id> && rm -f "$tmpfile"`
- Always reply inline to the specific comment thread, not as a standalone comment

## Public Repo Security

CRITICAL — applies to ALL public-facing text in public repositories:

- NEVER reference private org names, private repo names, or internal infrastructure
- Sanitization applies to EVERYTHING: PR titles, PR bodies, commit messages, branch names — not just file contents
- Before creating a PR on a public repo: review title and body for any private/internal references
- `gh repo create --push` pushes straight to main — NEVER use `--push` flag

## File Hygiene

- Newlines at EOF
- No trailing whitespace
- LF line endings (no CRLF)
- Never commit secrets (.env, credentials, keys, tokens)
- Never commit `.terraform/`, `.tfstate`, `node_modules/`, or other generated artifacts

## Anti-Patterns to Flag

- Pushing directly to main or default branch
- Creating "master" branches
- Using `Closes #N`, `Fixes #N`, or `Resolves #N` in commit messages (use `Refs #N`)
- Adding Claude co-author to private repo commits
- Using `gh pr merge` or `gh pr ready` (merging is a human decision)
- Creating non-draft PRs
- Committing secrets or credentials
- Using `gh repo create --push` (pushes to main)
- Emojis in branch names or code
