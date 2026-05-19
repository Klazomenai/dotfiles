---
name: release-please
description: >-
  release-please configuration, prerelease versioning strategy, post-release
  patterns (Docker, APK), PR customisation, and changelog management. Use when
  working with release-please-config.json, .release-please-manifest.json,
  release-please workflow files, or release automation.
---

# release-please Skill

## Config Field Reference

release-please silently ignores unknown config fields. The **only** authoritative reference
is `schemas/config.json` in the release-please source. Always verify field names against
the schema before assuming they work.

### Critical Fields (correct names)

| Config JSON Key | Internal Name | Default | Purpose |
|----------------|---------------|---------|---------|
| `release-type` | `releaseType` | — | Strategy: `simple`, `go`, `python`, `node`, etc. |
| `versioning` | `versioning` | `"default"` | Versioning strategy: `default`, `prerelease`, `always-bump-patch`, etc. |
| `prerelease` | `prerelease` | `false` | Mark GitHub Release as prerelease; stay in prerelease mode |
| `prerelease-type` | `prereleaseType` | — | Suffix type: `alpha`, `beta`, `rc` |
| `bump-minor-pre-major` | `bumpMinorPreMajor` | `false` | Breaking changes bump minor (not major) when version < 1.0.0 |
| `bump-patch-for-minor-pre-major` | `bumpPatchForMinorPreMajor` | `false` | Features bump patch (not minor) when version < 1.0.0 |
| `include-v-in-tag` | `includeVInTag` | `true` | Prefix tags with `v` (e.g., `v0.1.0-alpha`) |
| `include-component-in-tag` | `includeComponentInTag` | `true` | Include component name in tag |
| `pull-request-title-pattern` | `pullRequestTitlePattern` | `chore${scope}: release${component} ${version}` | PR title template |
| `pull-request-header` | `pullRequestHeader` | `:robot: I have created a release *beep* *boop*` | First line of PR body |
| `pull-request-footer` | `pullRequestFooter` | `This PR was generated with [Release Please]...` | Last line of PR body |
| `changelog-path` | `changelogPath` | `CHANGELOG.md` | Path to changelog file |
| `changelog-sections` | `changelogSections` | Default mappings | Commit type → section name mapping |
| `label` | `labels` | `["autorelease: pending"]` | Label added when release PR opens |
| `release-label` | `releaseLabels` | `["autorelease: tagged"]` | Label added after release |
| `extra-files` | `extraFiles` | — | Additional files to update (per-package) |
| `draft-pull-request` | `draftPullRequest` | `false` | Create release PR as draft |

## Release Types

| Type | Version File | When to Use |
|------|-------------|-------------|
| `simple` | `version.txt` | Language-agnostic; use `extra-files` with generic updater for other files |
| `go` | None (tags only) | Go projects; no version file updates needed |
| `python` | `pyproject.toml`, `setup.py`, `setup.cfg` | Python projects |
| `node` | `package.json`, `package-lock.json` | Node.js projects |

### Generic Updater for Extra Files

The `simple` type can update any file using inline version markers:

```kotlin
// In build.gradle.kts:
versionName = "0.1.0" // x-release-please-version
```

Config:
```jsonc
"extra-files": [
  {
    "type": "generic",
    "path": "app/build.gradle.kts"
  }
]
```

The generic updater finds `x-release-please-version` comments and replaces the adjacent
version string. Also supports `x-release-please-major`, `x-release-please-minor`,
`x-release-please-patch`, and block markers `{x-release-please-start-version}...{x-release-please-end}`.

## Prerelease Versioning

### Configuration

Three fields work together:
```json
{
  "versioning": "prerelease",
  "prerelease": true,
  "prerelease-type": "alpha"
}
```

- `versioning: "prerelease"` — selects the `PrereleaseVersioningStrategy`
- `prerelease: true` — stay in prerelease mode (don't strip suffix)
- `prerelease-type: "alpha"` — the suffix to append when creating a new prerelease

### Native Sequence

The first prerelease from a stable version appends the type **without** a number:

```
0.0.1 + feat: → 0.1.0-alpha        (first prerelease, no .0)
0.1.0-alpha + fix: → 0.1.0-alpha.1  (increment, appends .1)
0.1.0-alpha.1 + fix: → 0.1.0-alpha.2
```

The bump logic finds the last number in the prerelease suffix and increments it:
- `alpha` — no digits → appends `.1`
- `alpha.1` — finds `1` → increments to `alpha.2`

There is **no** `alpha.0` in the natural flow.

### Promotion to Stable

Set `"prerelease": false` in the config. The next release strips the suffix:
```
0.1.0-alpha.3 → 0.1.0
```

### Transition Between Types

Change `prerelease-type` from `alpha` to `beta`:
```
0.1.0-alpha.3 + feat: → 0.2.0-beta
```

## Manifest Bootstrap

The `.release-please-manifest.json` tracks the current released version. For a new repo with full prerelease config (`versioning: "prerelease"` + `prerelease: true` + `prerelease-type: "alpha"` + `bump-minor-pre-major: true`):

```json
{
  ".": "0.0.1"
}
```

The first `feat:` commit produces `0.1.0-alpha` (minor bump from `0.0.1` + prerelease suffix). **All four config fields must be present** — missing `versioning: "prerelease"` means no prerelease suffix on first release (you get `0.1.0`, not `0.1.0-alpha`).

**Do NOT set `bump-patch-for-minor-pre-major: true`** — this overrides `bump-minor-pre-major`
for features, making `feat:` produce patch bumps (`0.0.2-alpha` instead of `0.1.0-alpha`).

## First Release Bootstrap

### Default first-release behaviour

release-please calculates the first version by bumping from the manifest value. With no version override, the output depends entirely on your config flags:

| Config | First `feat:` from `0.0.1` | First `feat!:` from `0.0.1` |
|---|---|---|
| No flags | `0.1.0` | `1.0.0` |
| `bump-minor-pre-major: true` only | `0.1.0` | `0.2.0` |
| Full prerelease config (all four fields) | `0.1.0-alpha` | `0.2.0-alpha` |

**If you land a breaking-change commit before the config is complete, you may get `1.0.0` before you intended it.**

### Override paths

When the default bump would produce the wrong version, three escape hatches exist:

1. **`Release-As:` commit footer** (one-shot) — add `Release-As: 0.1.0-alpha.0` to any commit message; release-please uses this as the exact version for the next release PR, then returns to normal bump logic.

2. **`release-as` config field** (persistent) — set `"release-as": "0.1.0-alpha.0"` in `.release-please-config.json`; release-please pins every subsequent release PR to this version until the field is removed.

3. **Manifest seed** — write the target starting version directly into `.release-please-manifest.json` before the first push to main; release-please bumps from this value on the first run.

### CHANGELOG.md bootstrap structure (F3)

release-please's `adjustHeaders` (`src/updaters/changelog.ts:63-65`) regex-replaces every `^# ` line with `## ` when no conforming `## <version>` heading exists yet. Any prose preamble below the `# Changelog` H1 in a bootstrap CHANGELOG.md will be **demoted to H2 on the first release run**, producing duplicate headings and corrupted structure.

Bootstrap with one of:
- **Empty H1 only**: `# Changelog\n` (safe for all cases)
- **H1 + preamble above the first version anchor**: content placed between `# Changelog` and where the first `## <version>` will land — matches release-please's canonical fixture (`__snapshots__/changelog.js:1-54`)

This `adjustHeaders` fires only once; from release #2 onward, the existing `## <version>` heading anchors the conforming-content path (`src/updaters/changelog.ts:49-53`), which preserves surrounding content verbatim.

## PR Customisation

### Title Pattern

```jsonc
"pull-request-title-pattern": "chore${scope}: release${component} ${version} 🗺️"
```

Available variables: `${scope}` (branch name in parens), `${component}` (package name),
`${version}` (semver), `${branch}` (branch name).

### Header and Footer

Static strings — no variable interpolation available:

```jsonc
"pull-request-header": "🏴‍☠️ All hands on deck! New cargo manifest ready for inspection",
"pull-request-footer": "🏴‍☠️ Logged by the [Quartermaster](../../.github/workflows/RELEASE-PLEASE.md). All hands review before we set sail."
```

The relative link above is an example for use in a **target repo's** config — it resolves
relative to the release PR, not this skill file. Use relative links in the footer to point
to repo-local documentation (e.g., a `RELEASE-PLEASE.md` in the repo's workflows directory).

### Changelog Sections

```jsonc
"changelog-sections": [
  {"type": "feat", "section": "⛵ New Rigging", "hidden": false},
  {"type": "fix", "section": "🔧 Hull Repairs", "hidden": false},
  {"type": "perf", "section": "⚡ Trimmed the Sails", "hidden": false},
  {"type": "refactor", "section": "♻️ Refitted", "hidden": false},
  {"type": "revert", "section": "↩️ Struck from the Log", "hidden": false},
  {"type": "security", "section": "🔐 Battened Hatches", "hidden": false},
  {"type": "docs", "section": "Documentation", "hidden": true},
  {"type": "chore", "section": "Miscellaneous", "hidden": true},
  {"type": "test", "section": "Tests", "hidden": true},
  {"type": "build", "section": "Build", "hidden": true},
  {"type": "ci", "section": "CI", "hidden": true}
]
```

Hidden sections are parsed (affect version bumps) but excluded from the changelog output.

### Labels

```jsonc
"label": "release:pending",
"release-label": "release:published"
```

## Post-Release Patterns

### Docker (Go/Python Services)

Two-job workflow: release-please creates the release, then a conditional Docker job builds
and pushes. Compute tags once and push in a single build to avoid duplicate work. Tag
`latest` only for stable releases:

```yaml
docker:
  needs: release-please
  if: ${{ needs.release-please.outputs.release_created }}
  steps:
    - name: Compute Docker tags
      id: docker-tags
      run: |
        TAGS="ghcr.io/org/repo:${{ needs.release-please.outputs.version }}"
        if [[ "${{ needs.release-please.outputs.version }}" != *alpha* && \
              "${{ needs.release-please.outputs.version }}" != *beta* && \
              "${{ needs.release-please.outputs.version }}" != *rc* ]]; then
          TAGS="$TAGS,ghcr.io/org/repo:latest"
        fi
        echo "tags=$TAGS" >> "$GITHUB_OUTPUT"

    - uses: docker/build-push-action@v6
      with:
        push: true
        tags: ${{ steps.docker-tags.outputs.tags }}
```

### APK (Android)

Use `gh release upload` to attach the APK directly as a release asset. Do NOT use
`actions/upload-artifact` — it wraps files in a zip and does not publish them as a
first-class release asset, making them less accessible for end users (especially on mobile):

```yaml
build-apk:
  needs: release-please
  if: ${{ needs.release-please.outputs.release_created }}
  steps:
    - name: Build release APK
      env:
        RELEASE_KEYSTORE_FILE: ${{ runner.temp }}/release.keystore
      run: ./gradlew assembleRelease

    - name: Attach APK to release
      run: |
        gh release upload ${{ needs.release-please.outputs.tag_name }} \
          app/build/outputs/apk/release/app-release.apk --clobber
```

### Workflow Permissions

```yaml
permissions:
  contents: write        # Create releases and tags
  pull-requests: write   # Create and update release PRs
  packages: write        # Push to container registry (Docker only)
```

## Release PR Lifecycle

### Action branch ownership

release-please-action maintains a branch named `release-please--branches--<base>--components--<component>` and **force-pushes to it on every run**. Hand commits on top of this branch are possible (e.g. CHANGELOG backfill, structural fixes) but you are racing the action: any push to main between your edit and the release-PR merge triggers a regen that overwrites your commits.

### PR body regeneration

The release PR body is **regenerated from scratch on every push to main**. Manual `gh pr edit --body` edits are ephemeral. Only three config fields survive regen:
- `pull-request-header`
- `pull-request-footer`
- `pull-request-title-pattern`

All other body content (backfilled `closes [#N]` references, operator notes) must be committed to the action's branch before the release PR is merged — and even then you are racing the next push to main.

## Convention Collisions

### `Refs #N` is invisible to release-please's parser (F4)

release-please's commit-message parser only recognises `Closes`, `Fixes`, and `Resolves` as issue-link keywords. It does **not** recognise `Refs #N`. When commits use `Refs #N` (as required by the klazomenai `no-closes-in-commits` hook), changelog entries land without `closes [#N]` references.

Workflow when you need `closes [#N]` in the changelog:
1. Let release-please generate the release PR as normal
2. Backfill `closes [#N]` manually via a commit directly onto the action's branch
3. Merge the release PR before the next push to main triggers a regen that overwrites your backfill

### Hook collision with release-process commits (F6)

`claude/hooks/no-closes-in-commits.sh` (lines 7-8) denies any `git commit` whose **argv** contains `(Closes|Fixes|Resolves) #[0-9]+`. This fires on legitimate release-process commits whose body mentions these keywords — for example, a `Release-As:` override commit that explains why the override exists, or a CHANGELOG backfill commit listing `closes` mappings.

The escape: `git commit -F <tempfile>` — the hook matches argv only, not file contents. Write the commit message to a temp file and pass it via `-F`:

```bash
tmpfile=$(mktemp)
# write message to $tmpfile
git commit --gpg-sign -F "$tmpfile"
rm -f "$tmpfile"
```

This is the same escape used for `gh pr create --body-file` and `gh api -F body=@file` (documented in `claude/CLAUDE.md` Hook UX).

> See also: `klazomenai/dotfiles#111` tracks a dedicated hook-exception mechanism for release-please-managed flows, where a structural escape is preferable to a per-call workaround.

## GitHub Actions Setup

Before the first run, enable in repo settings:

**Settings → Actions → General → Workflow permissions:**
- "Allow GitHub Actions to create and approve pull requests" must be checked

Without this, release-please creates the branch and commit but fails to open the PR
with: `GitHub Actions is not permitted to create or approve pull requests`.

**Verify after the first push**: check the Actions tab for this exact error string. A workflow run that completes green but produces no release PR is the silent failure mode — the branch update succeeds but the PR-creation step fails quietly. This setting is OFF by default on new repos and has been observed failing silently for 18+ consecutive runs before being noticed.

## Anti-Patterns

- **Assuming a `0.0.0`/`0.0.1` manifest produces the expected version on first release without explicit override** — without `bump-minor-pre-major: true`, a breaking-change commit (`feat!:`) from `0.0.1` produces `1.0.0`; without the full four-field prerelease config, `feat:` produces `0.1.0` with no suffix. Any mismatch between config flags and commit history can land an unintended major bump. Use `Release-As:` footer, `release-as` config, or manifest seed to pin the first version explicitly.

- **Bootstrapping CHANGELOG.md with prose below `# Changelog`** — release-please's `adjustHeaders` (`src/updaters/changelog.ts:63-65`) demotes every `^# ` line to `## ` on the first release run when no conforming `## <version>` heading exists. Bootstrap with `# Changelog\n` only (no preamble), or place preamble between `# Changelog` and the first `## <version>` anchor (matches release-please's canonical fixture — see § CHANGELOG.md bootstrap structure).

- **Expecting `Refs #N` to populate `closes [#N]` in the changelog** — release-please only recognises `Closes`, `Fixes`, and `Resolves`. `Refs #N` is silently ignored. Backfill `closes [#N]` manually on the action's branch before the release PR is merged.

- **Hand-editing a release PR body via `gh pr edit --body`** — the body is regenerated from scratch on every push to main. Only `pull-request-header`, `pull-request-footer`, and `pull-request-title-pattern` survive regen. Commit backfill content to the action's branch instead.

- **`"versioning-strategy"` instead of `"versioning"`** — silently ignored. release-please
  falls back to the default versioning strategy (simple patch bumps, no prerelease suffix).
  The correct field is `"versioning"`. Confirmed in the release-please JSON schema
  (`schemas/config.json`) and manifest config reader (`src/manifest.ts`).

- **`"bump-patch-for-minor-pre-major": true`** — makes `feat:` commits produce **patch**
  bumps instead of minor bumps while the major version is 0. This overrides
  `bump-minor-pre-major` for features. Remove it unless you explicitly want features to
  produce patch bumps pre-1.0. Confirmed in the prerelease versioning strategy
  (`src/versioning-strategies/prerelease.ts`).

- **Expecting `alpha.0` as first prerelease** — the native sequence starts at `alpha`
  (no `.0`), then `alpha.1`, `alpha.2`. Repos that show `alpha.0` were manually seeded
  with that value in the manifest.

- **Using `actions/upload-artifact` for mobile APKs** — wraps files in a zip and does not
  publish them as a first-class release asset, making them less accessible for end users
  (especially on mobile). Use `gh release upload` to attach the `.apk` directly as a
  GitHub Release asset.

- **Missing `permissions: pull-requests: write`** — release-please cannot create the
  release PR without this permission in the workflow file.

- **Missing repo Actions setting** — even with correct permissions, the repo must have
  "Allow GitHub Actions to create and approve pull requests" enabled in Settings → Actions.
  This is a per-repo setting, not a workflow setting.

- **Copying config from another repo without verifying field names** — release-please has
  no config validation warnings. An unknown field is silently ignored. Always verify field
  names against `schemas/config.json` in the release-please source.

- **No config validation exists** — release-please does not warn about unknown or misspelled
  fields. The JSON schema is the only reference. When something doesn't work, check field
  names against the schema before investigating behaviour.

## See Also

- [`gh-actions` skill](../gh-actions/SKILL.md) — action-output validation (regex-validate `release-please-action`'s `version` output before constructing `tag_name`; never consume `tag_name` directly from action outputs)
