---
name: github
description: Git and GitHub workflow guidance, including commits, branches, PRs, issues, reviews, and labels. Use when working with git commands, GitHub issues, pull requests, or code reviews.
---

# Git + GitHub Skill

This skill encodes the universal git + GitHub workflow rules — they apply
wherever this skill is loaded, including by autonomous agents that vendor
or link this file. Operator-specific concerns (Claude co-author handling on
private repos, hook UX) live in `claude/CLAUDE.md`. Agent-specific
constraints (allowlist enforcement, mutation gating, no-autonomous-merge)
live in `claude/profiles/` for orchestrator consumers — Claude Code never
loads that directory.

## Commit Conventions

- Conventional commits format: `<type>(scope): description`
- Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `ci`, `perf`, `security`
- Signed commits required: always use `--gpg-sign`
- Use `Refs #N` in commit body — NEVER `Closes #N`, `Fixes #N`, or `Resolves #N` (closing is a merge-time decision). Note: release-please's changelog parser only recognises `Closes`/`Fixes`/`Resolves` for `closes [#N]` backlinks — using `Refs #N` means changelog entries land without issue links; see [`release-please` skill](../release-please/SKILL.md) for the manual backfill workflow.
- NEVER amend commits or force-push — stack separate signed commits, squash on merge
- Commit emoji prefixes (in commit message, not branch): ✨ feat | 🐛 fix | 📝 docs | ♻️ refactor | 🧪 test | ⚙️ chore | 🔐 security | 🏗️ ci | ⚡ perf

## Branch Conventions

- NEVER push to "main" or default branch — NO EXCEPTIONS
- NEVER create "master" branch
- Naming: `<type>/<issue>-<description>` e.g. `feat/595-jaeger-tracing`, `fix/784-terraform-exit-code`
- Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `ci`, `security`, `spike`
- Base branch: main | Merge style: squash merge | Delete branch after merge
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
- Write PR bodies to temp files for safe escaping of complex content: `gh pr create --body-file path/to/file --draft ...`. (Note: `--body-file <path>` is the `gh pr create` flag; the `-F body=@file` form-field syntax is for `gh api` calls only — see PR Review Replies below.)

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
6. **Commit and push** — new commit on same branch (never amend)
7. **Reply inline** — write body to temp file, then `gh api repos/{owner}/{repo}/pulls/{pr}/comments -X POST -F "body=@$tmpfile" -F in_reply_to=<id>`, reference commit SHA

Rules:
- Push back on wrong suggestions with technical reasoning — not every comment is correct
- Reply to EVERY top-level comment, even when disagreeing
- Reference the fix commit SHA in replies where changes were made

> **Why stack, not amend**: squash merge collapses all commits at merge time. Amending rewrites history reviewers already inspected, and force-push triggers guardrail hooks — for zero benefit.

## PR Review Replies

When replying to PR review comments:

- Write reply body to a temp file for safe escaping of complex content
- Pattern: `tmpfile=$(mktemp) && cat <<'EOF' > "$tmpfile" ... EOF` then `gh api ... -F "body=@$tmpfile" -F in_reply_to=<id> && rm -f "$tmpfile"`
- Always reply inline to the specific comment thread, not as a standalone comment

## Issue Acceptance-Criteria Verification at Close

When a PR merges and references an issue via `Refs #N`, the close decision is operator-driven — never automatic. Walk every AC checkbox against evidence from the merged state; the issue closes only when 100% of AC are demonstrably met.

1. **List** — read the issue's AC section in full; enumerate every sub-criterion as a discrete row
2. **Classify** — for each AC, decide which evidence type applies (see below)
3. **Verify** — gather the evidence from the merged state (commit SHA on `main`, CI run, file contents)
4. **Decide** — if all AC verified, close with the verification table; if partial, post a progress comment and leave open
5. **Comment** — post the verification (or progress) table citing the merge commit SHA

### Evidence types

- **Code-state-verifiable** — file presence (`ls`), grep for expected patterns or function names, config-field presence (`yq`, `jq`), commit-content check (`git show <sha>`). Evidence column: file path + line range + commit SHA.
- **CI-state** — workflow run conclusion (`gh pr checks <N>`, `gh run view <id>`), named job result. Evidence column: workflow name + run URL + conclusion.
- **Operational-test** — forward-looking AC that requires runtime confirmation (first release run, adversarial-input PR, scratch staging deploy). Two valid resolutions: (1) leave deferred when the implementation makes the failure mode impossible by construction, citing the implementation invariant; (2) execute the test and cite output. Evidence column: either the deferral reason + invariant, or the test invocation + output excerpt.

### Verification table format

Post the table as the close-comment body. One row per AC sub-criterion:

| AC | Evidence | Commit / Run |
|----|----------|--------------|
| New section in `claude/skills/<name>/SKILL.md` | `grep -n "## <section>" claude/skills/<name>/SKILL.md` → line N | `<sha>` |
| Anti-Patterns gains two entries | Anti-pattern bullet count: N → N+2 | `<sha>` |
| Worked example present | Section "### Worked example" present at line N | `<sha>` |

Each row stands on its own — the table is auditable later without re-running the same checks.

### The 100%-or-don't-close rule

Partial completion → progress comment, issue stays open. Never close with un-walked AC. The rationale: a closed-with-gaps issue gets buried in the closed-issue list and the gaps are forgotten; an open-with-progress issue stays visible in the open-issue list until completed. Open is the load-bearing signal.

Progress comments take the same table form but tag each row `done` / `partial` / `deferred` / `pending`. The `pending` rows are what the issue stays open for.

### Auto-close keyword discipline

Even when the close decision is authorised, the auto-close keywords (`Closes #N`, `Fixes #N`, `Resolves #N`) must not appear in commit messages or PR bodies — closure is taken explicitly via `gh issue close <N> --body-file <verification>` after the verification table is satisfied. Use `Refs #N` in commit text always.

The reason: `Closes #N` in a merged PR auto-closes the issue at merge time, before the AC walk happens. That defeats the walk-and-decide discipline entirely.

### Worked example

After merging a skill-extension PR that landed three of four ACs:

```
## Progress (post-merge)

| AC | Status | Evidence | Commit |
|----|--------|----------|--------|
| New section in SKILL.md | done | `grep -n "## New Section" .../SKILL.md` → line 94 | `abc1234` |
| Two anti-pattern entries | done | Anti-pattern bullet count: 12 → 14 | `abc1234` |
| Worked example present | done | Section "### Worked example" at line 138 | `abc1234` |
| `make install-claude` verification | pending | Not yet executed in operator environment | — |

Issue stays open pending operator `make install-claude` + symlink verification.
```

### See also

- [Copilot Review Workflow](#copilot-review-workflow) — same walk-and-decide pattern applied at PR-review time
- Future: `diagnostics` skill (tracked in dotfiles#114) for verify-before-iterate meta-discipline

## Deployment Sign-Off Conventions

When writing runbooks or asking operators to sign off on a deployment:

- **Request image tag, image digest, and git SHA separately** — `image.tag` (or chart `appVersion`) is a mutable, free-form string that does not uniquely identify a source commit. Tags are human-friendly identifiers, not content addresses — they can be overwritten and may not follow semver. A complete sign-off comment should ask for all three: (1) image tag, (2) image digest from the release pipeline's build logs or the running pod's `imageID` field (`kubectl get pod <name> -n <ns> -o jsonpath='{.status.containerStatuses[?(@.name=="<container-name>")].imageID}'`) — prefer these over resolving by tag at sign-off time, since `gcrane digest <image>:<tag>` returns the registry's current digest, which differs from the running deployment's digest if the tag was overwritten between build and sign-off; (3) source git SHA from the release pipeline's build logs or release metadata. Source: AKeyRA PR #158 round 5.
- **Name the `yq` variant and major version explicitly in runbook prerequisites** — mikefarah/yq (Go) and kislyuk/yq (Python wrapper around jq) have incompatible filter syntax, and mikefarah/yq v3 and v4 also have incompatible CLIs (`eval-all` is v4 syntax, not present in v3). Runbook prerequisites must specify **mikefarah/yq v4** and provide install instructions. Source: AKeyRA PR #158 rounds 6–7.

## Public Repo Security

CRITICAL — applies to ALL public-facing text in public repositories,
regardless of who or what is generating that text:

- NEVER reference private org names, private repo names, or internal
  infrastructure
- Sanitisation applies to EVERYTHING: PR titles, PR bodies, commit messages,
  branch names, issue titles, issue bodies, review-comment replies — not
  just file contents
- Before creating or editing a public-repo artefact: review the artefact in
  full — every surface listed above (PR title, PR body, commit message,
  branch name, issue title, issue body, review-comment reply) for any
  private/internal references, regardless of where the source text came
  from (operator instruction, tool output, prior conversation context)
- `gh repo create --push` pushes straight to main — NEVER use `--push` flag

The risk is the same whether the source is a human's local environment
(private hostnames, customer references, internal service names) or an
autonomous agent's tool output (e.g. a `kubectl` result mentioning a
private internal service that gets transcribed into an issue body).
Generated text bound for public surfaces gets the same scrutiny as
hand-typed text.

## Sensitive Values in Command Arguments

CRITICAL — applies to all command invocations, whether by a human at a
shell or by an autonomous agent invoking subprocesses:

- NEVER inline sensitive values (emails, keys, passwords, tokens) in
  command arguments — they leak into shell history, process tables, audit
  logs, and conversation logs
- Set env vars out-of-band (login env, restricted-perm `.env` file, secrets
  manager); pass via file paths (`gh auth login --with-token < tokenfile`,
  `kubectl create secret generic --from-file=key=/dev/stdin`); or pipe via
  stdin where the tool supports it (`docker login --password-stdin`,
  `helm registry login --password-stdin`)
- Don't recommend any pattern where the secret value appears in a logged
  command line — `export VAR=value` typed at a shell still ends up in
  history; prefer mechanisms that never put the value in argv at all
- Applies to all CLIs: `gh`, `terraform`, `gcloud`, `kubectl`, `vault`,
  `aut`, etc.
- Audit logs are persistent — agents that log full command lines for
  audit purposes are a particular leak risk; redact at log-time, not
  display-time

## File Hygiene

- Newlines at EOF
- No trailing whitespace
- LF line endings (no CRLF)
- Never commit secrets (.env, credentials, keys, tokens)
- Never commit `.terraform/`, `.tfstate`, `node_modules/`, or other generated artifacts

## Anti-Patterns to Flag

- Pushing directly to main or default branch
- Creating "master" branches
- Using `Closes #N`, `Fixes #N`, or `Resolves #N` in commit messages (use `Refs #N`). Note: `Refs #N` is invisible to release-please's changelog parser — see [`release-please` skill](../release-please/SKILL.md) for the manual backfill workflow when `closes [#N]` references are needed in the changelog.
- Using `gh pr merge` or `gh pr ready` (merging is a human decision)
- Creating non-draft PRs
- Committing secrets or credentials
- Using `gh repo create --push` (pushes to main)
- Amending commits during PR review (`--amend`) — stack new signed commits; squash merge makes amend pointless
- Force-pushing (`--force`, `--force-with-lease`) — breaks reviewer context, blocked by guardrail hooks
- Emojis in branch names or code
- Deployment sign-off that asks only for image tag — omits digest + git SHA, insufficient for provenance
- Runbook prerequisites that mention `yq` without naming the variant and major version (must specify mikefarah/yq **v4** — kislyuk/Python and mikefarah/yq v3 both have incompatible syntax; `eval-all` is v4-only)
- Closing an issue without walking each AC against evidence — closure must follow the verification-table workflow, not the merge event
- Using `Closes #N`, `Fixes #N`, or `Resolves #N` in commit messages or PR bodies even when authorised to close — closure must be explicit via `gh issue close` after the AC walk, never implicit via merge-time auto-close

## See Also

- [`gh-actions` skill](../gh-actions/SKILL.md) — label-based override gates (RBAC-safe replacement for PR-body text markers), untrusted-context handling, and workflow lint guards
