---
name: gh-actions
description: GitHub Actions workflow safety — untrusted-context handling, safe interpolation patterns, override-gate design, and workflow lint guards. Use when writing or reviewing GitHub Actions workflows, handling pull_request events, or designing permission-relevant CI gates.
---

# GitHub Actions Skill

## Untrusted Context Handling

`${{ }}` is **text substitution** into the rendered shell script source — it is not a data binding or a safe parameter expansion. Before any `${{ }}` expression reaches a `run:` block, understand which contexts contain user-authored content.

### User-authored contexts (treat as untrusted)

- `github.event.pull_request.body` — PR description, editable by any contributor
- `github.event.pull_request.title` — PR title, same
- `github.event.issue.body` / `github.event.comment.body` — issue and comment text
- `github.head_ref` — branch name from a fork author (can contain shell metacharacters)
- `github.event.label.name` — label names set by external contributors on public repos
- Any `github.event.*` field that reflects contributor-supplied content

### GHA-internal contexts (generally safe)

- `github.sha` — commit SHA set by GitHub infrastructure
- `github.event_name` — the event type string (a GHA constant)
- `github.actor` — the triggering username (safe for logging, not for auth decisions)
- `github.token` — the workflow token (never echo; treat as secret)
- `secrets.*` — vault values (never echo; treat as secret)
- `github.repository` — `owner/repo` string set by GitHub infrastructure

### Why body/title interpolation is dangerous

`${{ github.event.pull_request.body }}` is resolved to its literal string value and spliced into the workflow YAML before the shell sees it. A body containing:

```
foo" ; malicious-command #
```

can produce syntactically valid but attacker-controlled shell. A body containing a lone `#` after a `"` can eat everything that follows as a shell comment, producing a syntax error or — worse — silently omitting a command.

Source: klazomenai/bridge#163, remediated in klazomenai/bridge#164.

## Safe Interpolation Patterns

### Env-var indirection (canonical pattern)

Never interpolate untrusted `${{ }}` directly into a `run:` block. Pass via an environment variable instead:

```yaml
- name: Use PR body safely
  env:
    PR_BODY: ${{ github.event.pull_request.body }}
  run: |
    # $PR_BODY is a shell variable — no text substitution into script source
    echo "$PR_BODY" | grep -qF "[allow-coverage-drop]"
```

The `env:` key receives the `${{ }}` substitution; the shell sees a quoted variable reference, not inline text. This prevents metacharacter injection.

### Regex-validate action outputs before use

Action outputs (e.g. from `release-please-action`) are not sanitised at source. If an output reaches a `run:` block or a downstream step, validate it first:

```yaml
- name: Validate version output
  env:
    VERSION: ${{ steps.release.outputs.version }}
  run: |
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Unexpected version format: $VERSION" >&2
      exit 1
    fi
    echo "tag_name=v$VERSION" >> "$GITHUB_OUTPUT"
```

Do not construct `tag_name` by consuming the action's `tag_name` output directly — reconstruct it locally after validating `version`.

### Heredoc / here-string sensitivity

Avoid `<<< "${{ ... }}"` (here-string) and `<<EOF ... ${{ ... }} ... EOF` (heredoc) when the interpolated value is user-authored. The `${{ }}` substitution happens before shell parsing; the resulting here-string is re-parsed as shell input, where `#` can start comments and `"` can terminate the string.

Use env-var indirection and read the env var inside the heredoc/here-string:

```yaml
env:
  PR_BODY: ${{ github.event.pull_request.body }}
run: |
  grep -qF "[marker]" <<< "$PR_BODY"
```

## Override-Gate Design

### Labels over PR-body markers

For permission-relevant overrides (e.g. "allow coverage to drop on this PR"), prefer **labels** over PR-body text markers:

| Property | Label gate | PR-body marker |
|---|---|---|
| RBAC | Only maintainers with triage+ can add labels | Any contributor can edit the PR body |
| Audit trail | Label addition appears in the timeline | PR body edits may not be surfaced |
| Injection surface | Label name is a fixed identifier | Body text reaches `run:` blocks as unstructured text |
| Machine check | `contains(github.event.pull_request.labels.*.name, 'foo')` | grep against `${{ github.event.pull_request.body }}` |

```yaml
# Label-based gate (preferred)
- name: Check for coverage override
  if: contains(github.event.pull_request.labels.*.name, 'allow-coverage-drop')
  run: echo "Coverage drop allowed"
```

### `on.pull_request.types` — listing types replaces defaults

The default `pull_request` trigger fires on `[opened, synchronize, reopened]`. If you add `labeled` to `types:`, you **must** also list the defaults — otherwise PRs no longer trigger on push:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled]  # all four required
```

Omitting `synchronize` means the workflow only fires when the PR is first opened or when a label is added — not on subsequent commits.

### `pull_request` vs `pull_request_target`

`pull_request_target` runs the base-branch workflow with **write tokens** against fork-author HEAD content. Any `actions/checkout` step that checks out the PR HEAD (`ref: ${{ github.event.pull_request.head.sha }}`) in a `pull_request_target` context is a supply-chain risk: attacker-controlled code runs with write token. Use `pull_request` (which demotes tokens on forks) unless you explicitly need base-branch context with write access and understand the trust boundary.

## Workflow Lint Guards

### actionlint

Pin via the `docker://` image reference to avoid version drift:

```yaml
- name: Lint workflows
  uses: docker://rhysd/actionlint:1.7.7
  with:
    args: -color
```

actionlint catches: undefined expressions, unknown action inputs, shell syntax errors (it runs shellcheck internally), incorrect `on:` event types, and string/number type mismatches.

### shellcheck

Pre-installed on `ubuntu-latest`. Add an explicit shell-script lint step for any scripts under `.github/scripts/`:

```yaml
- name: Lint shell scripts
  run: shellcheck .github/scripts/*.sh
```

### Action version pinning

Prefer pinning to a commit SHA for security-sensitive actions:

```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

Tag-based pinning (`@v4`) is acceptable for trusted first-party actions; avoid `@latest` entirely. Third-party actions from untrusted authors should always be SHA-pinned.

## Anti-Patterns to Flag

- Interpolating `${{ github.event.pull_request.body }}` / `.title` / `.head.ref` / comment text directly into a `run:` block (injection surface — use env-var indirection)
- `<<< "${{ github.event.pull_request.body }}"` here-string — `${{ }}` is resolved before shell parsing; use `<<< "$PR_BODY"` after setting `PR_BODY` in `env:`
- PR-body markers for permission-relevant overrides (use labels — RBAC-gated, audit-trailed, injection-free)
- `on.pull_request.types: [labeled]` without also listing `[opened, synchronize, reopened]` — silently stops triggering on PR commits
- `pull_request_target` with `actions/checkout` of the PR HEAD — write tokens + fork code = supply-chain risk
- `@latest` action version pins — unpinned, can pull breaking changes or malicious updates silently
- Consuming action outputs (e.g. `release-please-action`'s `tag_name`) without regex-validating format first
- Hardcoded line-number references in code comments within workflow `run:` blocks — drift on the same PR that introduces them
- Missing `issues: write` permission when using `gh api` to post issue comments — `pull-requests: write` does not cover the issue-comments endpoint
