#!/usr/bin/env sh
# check-skill-structure.sh
#
# L0 static-structure fixture for the Chips skills architecture (see
# klazomenai/dotfiles#99). Asserts that the dotfiles repo's skills +
# profiles directories are structurally correct so downstream consumers
# (Bridge orchestrator, autonomous agents) can rely on them.
#
# What it checks:
#   1. Every directory under claude/skills/ contains a SKILL.md
#   2. claude/profiles/_universal.md exists with the required H2 sections
#   3. claude/profiles/github.md exists with the required H2 sections
#   4. No claude/skills/<name>/SKILL.md references _universal.md
#      (negative claim — the asymmetric reference graph is deliberate;
#      Claude Code must not auto-load universal content via a sibling
#      link from a SKILL.md, since that would pollute human-CC users
#      with orchestrator-only constraints)
#
# Exits 0 on success, non-zero on the first failure with a clear message.
# Designed for CI-friendly output; uses ::error:: workflow-command format
# when running under GitHub Actions (detected via $GITHUB_ACTIONS).
#
# POSIX shell — no jq, no yq, no bash-only constructs.

set -eu

# Locate repo root (script lives at <repo>/scripts/).
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"

# Output helpers — surface as GitHub Actions annotations when possible.
fail() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        printf '::error::%s\n' "$1"
    else
        printf 'FAIL: %s\n' "$1" >&2
    fi
    exit 1
}

info() {
    printf '%s\n' "$1"
}

# ------------------------------------------------------------------
# Check 1 — every claude/skills/<name>/ has a SKILL.md
# ------------------------------------------------------------------
info "Checking claude/skills/*/SKILL.md presence..."
missing=0
for dir in claude/skills/*/; do
    [ -d "$dir" ] || continue
    if [ ! -f "${dir}SKILL.md" ]; then
        fail "skill directory ${dir} is missing SKILL.md"
        missing=$((missing + 1))
    fi
done
[ "$missing" -eq 0 ] || exit 1

# ------------------------------------------------------------------
# Check 2 — _universal.md required H2 sections
# ------------------------------------------------------------------
UNIVERSAL_PATH="claude/profiles/_universal.md"
info "Checking ${UNIVERSAL_PATH} sections..."
[ -f "${UNIVERSAL_PATH}" ] || fail "${UNIVERSAL_PATH} does not exist"

# Required H2 section headings (must appear at the start of a line as `## `).
# Stored newline-separated for POSIX iteration.
universal_required="Repo / Resource Allowlist Enforcement
Token & Secret Redaction
Write Operations — Operator Intent Required
High-Risk Mutations — Additional Confirmation Required
Audit Trail
Refusal Policy
Anti-Patterns"

printf '%s\n' "$universal_required" | while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qF "## ${section}" "${UNIVERSAL_PATH}"; then
        fail "${UNIVERSAL_PATH} missing required section: ## ${section}"
    fi
done

# ------------------------------------------------------------------
# Check 3 — github.md required H2 sections
# ------------------------------------------------------------------
GITHUB_PROFILE_PATH="claude/profiles/github.md"
info "Checking ${GITHUB_PROFILE_PATH} sections..."
[ -f "${GITHUB_PROFILE_PATH}" ] || fail "${GITHUB_PROFILE_PATH} does not exist"

github_profile_required="PR Lifecycle Gates
Pushing Code
Copilot Review Threads
Branch Operations
Anti-Patterns"

printf '%s\n' "$github_profile_required" | while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qF "## ${section}" "${GITHUB_PROFILE_PATH}"; then
        fail "${GITHUB_PROFILE_PATH} missing required section: ## ${section}"
    fi
done

# ------------------------------------------------------------------
# Check 4 — no SKILL.md references _universal.md (negative claim)
# ------------------------------------------------------------------
info "Checking no SKILL.md references _universal.md..."
violators=$(grep -rlF "_universal.md" claude/skills/ 2>/dev/null || true)
if [ -n "$violators" ]; then
    fail "claude/skills/ files reference _universal.md (would auto-load orchestrator content for human Claude Code users — see #99 architecture decision):
${violators}"
fi

# ------------------------------------------------------------------
info "All L0 skill-structure checks passed."
exit 0
