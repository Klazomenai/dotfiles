---
name: recipe-docs
description: >-
  Writer-vs-reader context discipline for runnable documentation: recipe
  variables, Markdown link paths, convention scope, and prose formatting.
  Use when writing markdown docs with shell snippets, runbooks, how-tos,
  operator ceremonies, or documentation conventions and guidelines.
---

# Recipe-Docs Skill

## The Pattern: Writer-Context vs Reader-Context Mismatch

Documentation is produced by an author who has full situational context and consumed by a reader who often does not. Whenever the reader's rendering or running context differs from the author's writing context, implicit context leaks become bugs.

Four practical layers where this happens:

| Layer | Symptom | Author's model | Reader's reality |
|---|---|---|---|
| **Recipe variables** | `${VAR}` used but never defined | "Of course — it's the obvious value" | Undefined; recipe can't run |
| **Markdown link paths** | Relative URL works in PR review, 404 when published | "I'm in `.github/release-notes/`; `..` resolves fine" | Content composed into a GitHub Release page — no current directory |
| **Convention scope** | Rule reads as universal; reader misapplies it | "Obviously this rule is about banter files" | No qualifier written; reader applies it everywhere |
| **Prose formatting** | Long absolute URL inline; wrapped prose breaks | "Rendered Release page doesn't care about line length" | In-repo authors see ~115-char line in a ~62-char wrap; re-flow is awkward |

In all four cases the fix has the same shape: **make the context layer explicit at the place the reader will land**.

## Three-Layer Model

Every executable recipe has three layers. Authors capture Layer 1 reliably and silently omit Layer 3.

| Layer | What it is | Example |
|---|---|---|
| 1 — Operation | The actual command | `gh api "repos/${REPO}/releases/${release_id}" -X PATCH -F body=@/tmp/body.md` |
| 2 — Inputs | Values the operation consumes | `${REPO}`, `${release_id}`, `/tmp/body.md` |
| 3 — Context establishment | How those inputs come to exist | The lookup, the upstream step, the user's prior setup |

When reviewing a draft recipe, walk each input in Layer 2 and ask: does the reader know where this comes from? If not, Layer 3 is missing.

## Description vs Recipe

A *description* is a memory aid for someone who already knows the situation. A *recipe* is a contract with a stranger.

Different artefacts; different obligations:

- **Description**: "The PATCH endpoint updates the release body." — assumes the reader already knows how to obtain `release_id`.
- **Recipe**: shows the lookup, shows the variables, shows the PATCH. Reader can copy-paste and run.

The mistake is writing a description when the artefact will be used as a recipe. "Compose the body, then PATCH" is a description pretending to be a recipe.

## Cold-Start Reader Test

Before publishing a recipe, runbook, or convention document, apply this check: *imagine the reader has never seen the project before. Open the doc. Try to run it.*

The first undefined `${VAR}`, broken link, or apparent contradiction is where context was implicit and needs to be made explicit.

**Different review surfaces catch different context-leaks:**

| Review surface | Context available | What it misses |
|---|---|---|
| PR review (file in repo) | Repo directory structure; relative links resolve | Content rendered elsewhere (Release page, copied excerpt) |
| Published-artefact review | Destination rendering context | In-repo prose wrap, relative link correctness in repo |
| Downstream-author review | Doc text only | Project history that scoped a convention |

"I checked the PR" is not a substitute for "I checked the published artefact." Multiple review surfaces are not redundancy — each surfaces a different class of leak.

## Hybrid Shell-Snippet Form

For chained multi-command recipes with shared state, the canonical form:

```bash
# Set these to match your context.
REPO="<owner>/<repo>"   # e.g. Klazomenai/deck-chat
TAG="<tag>"             # e.g. v0.1.0-alpha.7

# Look up derived values.
release_id="$(gh api "repos/${REPO}/releases/tags/${TAG}" --jq '.id')"

# Apply the operation.
gh api "repos/${REPO}/releases/${release_id}" -X PATCH -F body=@/tmp/new-body.md
```

This form balances three pressures:

- **Bash variables** link commands together (reader sees the chain, not isolated snippets)
- **Placeholder values inside quotes** (`"<owner>/<repo>"`) acknowledge the surrounding doc's placeholder style
- **Concrete examples in comments** show the operator the expected format
- **Section comments** (`# Set these`, `# Look up`, `# Apply`) delineate setup / lookup / operation — the three layers made visible

For one-shot independent commands with no shared state, placeholder-only style is lighter-weight and fine.

## Setup-Section Convention

Any recipe with shared state across multiple commands gets an explicit `### Setup` header listing required inputs before the first command block. This forces Layer 3 explicit at document-structure level, not just variable-naming level.

```markdown
### Setup

```bash
REPO="<owner>/<repo>"   # e.g. Klazomenai/deck-chat
TAG="<tag>"             # e.g. v0.1.0-alpha.7
release_id="$(gh api "repos/${REPO}/releases/tags/${TAG}" --jq '.id')"
```
```

All subsequent code blocks in the section can reference `${REPO}`, `${TAG}`, `${release_id}` without re-defining them — the reader knows to run Setup first.

## Markdown Link Conventions

### Absolute vs relative

| Artefact type | Link style | Why |
|---|---|---|
| Content rendered outside its repo location (Release pages, copied excerpts, banter files) | **Absolute URLs** | Relative paths assume the file's directory as resolution context; that context doesn't survive the copy |
| Content read only in its repo location (READMEs, in-repo runbooks) | Relative links fine | Shorter, rename-safe, PR-diff-friendly |

### Reference-style links for long absolute URLs

Inline long absolute URLs disrupt the in-repo prose wrap. Prefer reference-style:

```markdown
See the [Recovery runbook][recovery] for failure modes.

[recovery]: https://github.com/owner/repo/blob/main/.github/workflows/RELEASE-PLEASE.md#recovery
```

Renders identically in any context (Markdown reference definitions don't render visually). Keeps in-repo prose wrap clean. Makes URL updates a single-line edit.

## Convention-Scope Discipline

Conventions are recipes for future authors. They carry an implicit scope ("this applies to X") that the writer often doesn't write down.

Symptom: a rule reads as universal but applies only to a specific artefact class. Reader applies it beyond the intended scope, or reads it as contradicting neighbouring docs.

Fix: state the scope inline.

- ❌ "Links must be absolute URLs." (written in a directory README that itself uses relative links)
- ✅ "In banter files published to GitHub Releases, links must be absolute URLs."

If the scope qualifier seems obvious to the author, that is exactly when it needs to be written — the reader doesn't have the author's history.

## Skill Effectiveness Tracking

Measurement plan: for each PR that authors or reviews recipe-shaped docs after this skill is live, count context-leak findings by layer (recipe variables / link paths / convention scope / prose formatting) per Copilot review round.

Baseline (before this skill): `deck-chat#184` took 3 rounds to converge on the hybrid shell-snippet form; `deck-chat#186` took 3 rounds to converge on absolute URLs + reference-style links + scoped convention language. Target trend: zero recurring findings of the same shape after the first occurrence.

Log findings here when they recur so the anti-patterns list stays current.

## Anti-Patterns

- **Undefined `${VARS}` in shell snippets** — reader can't run the recipe without knowing where the value comes from
- **`${derived_id}` referenced without showing the lookup** — e.g. `${release_id}` used in a PATCH without the `gh api ... --jq '.id'` line
- **Prose-described composition without showing the code** — "compose the body, then PATCH" is a description, not a recipe
- **Relative Markdown links in artefacts whose content gets copied into another rendering context** — e.g. banter files, README excerpts embedded in Release notes
- **Long absolute URLs inline in wrapped prose** — disrupts in-repo wrap; use reference-style links
- **Convention statements with implicit scope** — "Links must be absolute URLs" in a doc that itself uses relative links; reader sees a contradiction
- **"Of course" / "obviously" as implicit context** — these words mark exactly where context is implicit; write it out instead
- **One-shot placeholder-only style for multi-command chained recipes** — placeholder values (`<release-id>`) don't compose across command boundaries; use Bash variables with a Setup section

## Worked Examples

### Layer 1 — Recipe variables (`klazomenai/deck-chat#184`)

PR *"docs(release): inaugurate Quartermaster's Log ceremony with alpha.7 banter and conventions 📝"* — three Copilot rounds, same shape each time:

| Round | Missing context |
|---|---|
| R1 (`r3157327655`) | `${release_id}` used; doc never shows the lookup |
| R3 (`r3159063352`) | `${REPO}` and `${TAG}` used; never defined |
| (next would catch) | `/tmp/new-body.md` referenced; composition step not shown |

Resolution (commit `6538622`): the hybrid shell-snippet form above — `# Set these` block with placeholders + examples, `# Look up` block for derived values, `# Apply` block for the operation.

### Layers 2, 3, 4 — Links, convention scope, prose formatting (`klazomenai/deck-chat#186`)

PR *"fix(release): use absolute URLs in release-notes banter for cross-context rendering 📝"*:

- **Layer 2 (R1)**: Banter file used `[Recovery runbook](../workflows/RELEASE-PLEASE.md#recovery)`. Worked in PR review (file in repo context). Broke when composed into a GitHub Release body (no resolution context). PR review didn't catch it — different review surface. Resolution: absolute URL.
- **Layer 3 (R2, `r3159378670`)**: Fix added directory README bullet "Links must be absolute URLs". README itself uses relative links. Reader sees an apparent contradiction. Resolution: "In banter files published to GitHub Releases, links must be absolute URLs."
- **Layer 4 (R3, `r3159480172`)**: Absolute URL inline → ~115-char line in a ~62-char wrap. Resolution: reference-style link — `[Recovery runbook][recovery]` inline + `[recovery]: https://...` at bottom of file.

## See Also

- [`kubernetes` skill](../kubernetes/SKILL.md) — operational runbooks and `kubectl` ceremony steps are canonical recipe-shaped docs; apply the three-layer model and Setup-section convention there
- [`helm` skill](../helm/SKILL.md) — Helm upgrade/rollback runbooks; apply absolute-URL and reference-style link conventions when publishing chart runbooks to Release pages
- [`release-please` skill](../release-please/SKILL.md) — CHANGELOG backfill ceremony and release PR body conventions are recipe-shaped; the hybrid shell-snippet form applies
