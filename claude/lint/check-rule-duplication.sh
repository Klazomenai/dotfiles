#!/usr/bin/env bash
# check-rule-duplication.sh
#
# Scans for load-bearing rule strings appearing in 3+ files across four
# conceptual rule layers (scanned as five roots — hooks/ and
# settings.json are both enforcement):
#   - claude/CLAUDE.md           — behaviour
#   - claude/hooks/              — enforcement (PreToolUse scripts)
#   - claude/settings.json       — enforcement (permission rules)
#   - claude/skills/             — workflow knowledge
#   - claude/profiles/           — agent constraints
# Warns (does not fail CI).
#
# The dedup pass (Phase 3 of the skills-architecture redesign,
# klazomenai/dotfiles#99) will gradually move each duplicated rule
# toward its canonical layer:
#   - Behaviour          → claude/CLAUDE.md
#   - Enforcement        → claude/hooks/ + claude/settings.json
#   - Workflow knowledge → claude/skills/<name>/SKILL.md
#   - Agent constraints  → claude/profiles/
#
# Adding patterns is safe — false positives surface as warnings, not
# failures. To add a pattern, append it to the PATTERNS array below.

set -euo pipefail

cd "$(dirname "$0")/../.."

LAYERS=(
    "claude/CLAUDE.md"
    "claude/hooks"
    "claude/settings.json"
    "claude/skills"
    "claude/profiles"
)

PATTERNS=(
    "Refs #N"
    "Closes #N"
    "Fixes #N"
    "Resolves #N"
    "--gpg-sign"
    "Co-Authored-By"
    "NEVER push to \"main\""
    "NEVER push to main"
    "NEVER amend commits"
    "ALWAYS create PRs as draft"
    "gh pr merge"
    "gh pr ready"
    "no-coauthor-private"
    "no-push-to-main"
    "no-rebase"
)

duplications=0

for pattern in "${PATTERNS[@]}"; do
    files_matching=()
    for layer in "${LAYERS[@]}"; do
        if [[ -d "$layer" ]]; then
            while IFS= read -r match; do
                [[ -n "$match" ]] && files_matching+=("$match")
            done < <(grep -rlF -- "$pattern" "$layer" 2>/dev/null || true)
        elif [[ -f "$layer" ]]; then
            if grep -qF -- "$pattern" "$layer" 2>/dev/null; then
                files_matching+=("$layer")
            fi
        fi
    done

    if [[ ${#files_matching[@]} -ge 3 ]]; then
        echo "::warning::Rule pattern \"$pattern\" appears in ${#files_matching[@]} files (3+ duplication):"
        for f in "${files_matching[@]}"; do
            echo "  - $f"
        done
        duplications=$((duplications + 1))
    fi
done

if [[ $duplications -gt 0 ]]; then
    cat <<'EOF'

Found rule patterns duplicated across 3+ files.

This lint is a Phase 3 transition aid (see klazomenai/dotfiles#99). The
dedup pass will move each rule toward its canonical layer; until then,
duplication warnings are informational, not blocking.

To add or refine patterns, edit claude/lint/check-rule-duplication.sh.
EOF
fi

# Always exit 0 — this is a warning lint, not a gate.
exit 0
