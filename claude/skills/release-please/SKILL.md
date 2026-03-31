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
```json
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

The bump regex `/(?<number>\d+)(?=\D*$)/` finds the last digits in the suffix:
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

The `.release-please-manifest.json` tracks the current released version. For a new repo:

```json
{
  ".": "0.0.1"
}
```

With `bump-minor-pre-major: true` and `versioning: "prerelease"`, the first `feat:` commit
produces `0.1.0-alpha` (minor bump from `0.0.1` + prerelease suffix).

**Do NOT set `bump-patch-for-minor-pre-major: true`** — this overrides `bump-minor-pre-major`
for features, making `feat:` produce patch bumps (`0.0.2-alpha` instead of `0.1.0-alpha`).

## PR Customisation

### Title Pattern

```json
"pull-request-title-pattern": "chore${scope}: release${component} ${version} 🗺️"
```

Available variables: `${scope}` (branch name in parens), `${component}` (package name),
`${version}` (semver), `${branch}` (branch name).

### Header and Footer

Static strings — no variable interpolation available:

```json
"pull-request-header": "🏴‍☠️ All hands on deck! New cargo manifest ready for inspection",
"pull-request-footer": "🏴‍☠️ Logged by the [Quartermaster](../../.github/workflows/RELEASE-PLEASE.md). All hands review before we set sail."
```

The relative link above is an example for use in a **target repo's** config — it resolves
relative to the release PR, not this skill file. Use relative links in the footer to point
to repo-local documentation (e.g., a `RELEASE-PLEASE.md` in the repo's workflows directory).

### Changelog Sections

```json
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

```json
"label": "release:pending",
"release-label": "release:published"
```

## Post-Release Patterns

### Docker (Go/Python Services)

Two-job workflow: release-please creates the release, then a conditional Docker job builds
and pushes. Tag `latest` only for stable releases:

```yaml
docker:
  needs: release-please
  if: ${{ needs.release-please.outputs.release_created }}
  steps:
    - uses: docker/build-push-action@v6
      with:
        push: true
        tags: ghcr.io/org/repo:${{ needs.release-please.outputs.version }}

    - name: Push latest (stable only)
      if: ${{ !contains(needs.release-please.outputs.version, 'alpha') && !contains(needs.release-please.outputs.version, 'beta') && !contains(needs.release-please.outputs.version, 'rc') }}
      uses: docker/build-push-action@v6
      with:
        push: true
        tags: ghcr.io/org/repo:latest
```

### APK (Android)

Use `gh release upload` to attach the APK directly as a release asset. Do NOT use
`actions/upload-artifact` — it wraps files in a zip that Android cannot extract:

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

## GitHub Actions Setup

Before the first run, enable in repo settings:

**Settings → Actions → General → Workflow permissions:**
- "Allow GitHub Actions to create and approve pull requests" must be checked

Without this, release-please creates the branch and commit but fails to open the PR
with: `GitHub Actions is not permitted to create or approve pull requests`.

## Anti-Patterns

- **`"versioning-strategy"` instead of `"versioning"`** — silently ignored. release-please
  falls back to the default versioning strategy (simple patch bumps, no prerelease suffix).
  The correct field is `"versioning"`. Confirmed: `schemas/config.json` line 27, read at
  `src/manifest.ts` line 1394.

- **`"bump-patch-for-minor-pre-major": true`** — makes `feat:` commits produce **patch**
  bumps instead of minor bumps while the major version is 0. This overrides
  `bump-minor-pre-major` for features. Remove it unless you explicitly want features to
  produce patch bumps pre-1.0. Confirmed: `src/versioning-strategies/prerelease.ts` line 225.

- **Expecting `alpha.0` as first prerelease** — the native sequence starts at `alpha`
  (no `.0`), then `alpha.1`, `alpha.2`. Repos that show `alpha.0` were manually seeded
  with that value in the manifest.

- **Using `actions/upload-artifact` for mobile APKs** — wraps files in a zip archive.
  Android phones cannot extract zips from the browser. Use `gh release upload` to attach
  the `.apk` directly as a GitHub Release asset.

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
