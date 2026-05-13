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
#   4. claude/profiles/security.md exists with the required H2 sections
#   5. claude/profiles/kubernetes.md exists with the required H2 sections
#   6. No claude/skills/<name>/SKILL.md references _universal.md
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

# Locate repo root (script lives at <repo>/scripts/). The `$0` value is
# the script's own path; it cannot start with `-`, so the `--` end-of-
# options marker isn't needed and is dropped here for portability with
# non-GNU userlands where `dirname --` / `cd --` may not be supported.
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"

# Output helpers — surface as GitHub Actions annotations when possible.
# fail emits a single-line ::error:: annotation under GHA so the workflow
# command parses correctly. Multi-line context (file lists, etc.) goes to
# stderr separately to preserve the annotation while still surfacing
# diagnostic data in the run log.
fail() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        printf '::error::%s\n' "$1"
    else
        printf 'FAIL: %s\n' "$1" >&2
    fi
    # Optional second argument: multi-line diagnostic to print to stderr
    # (e.g. list of violating files) without breaking the annotation.
    if [ "$#" -ge 2 ] && [ -n "$2" ]; then
        printf '%s\n' "$2" >&2
    fi
    exit 1
}

info() {
    printf '%s\n' "$1"
}

# ------------------------------------------------------------------
# Check 1 — every claude/skills/<name>/ has a SKILL.md
# ------------------------------------------------------------------
# Pre-flight: claude/skills/ must exist. Beyond that, we enumerate
# child directories via a POSIX glob (`claude/skills/*/`) — `find` with
# -mindepth/-maxdepth is GNU/BSD-only, not POSIX. The `[ -d "$dir" ]`
# guard handles the unmatched-glob-stays-literal case (POSIX sh leaves
# the pattern unchanged when no files match), and `found_any` catches
# the empty-directory case explicitly so a deleted skills/ still fails
# CI rather than silently passing.
info "Checking claude/skills/*/SKILL.md presence..."
[ -d "claude/skills" ] || fail "claude/skills/ directory does not exist"

# Collect ALL missing SKILL.md files first, then fail once with the full
# list — operator-friendly: see every problem in a single run rather
# than fix-one-rerun loops.
missing_skills=""
found_any=0
for dir in claude/skills/*/; do
    [ -d "$dir" ] || continue
    found_any=1
    skill_md="${dir}SKILL.md"
    if [ ! -f "$skill_md" ]; then
        missing_skills="${missing_skills}${skill_md}
"
    fi
done

[ "$found_any" -eq 1 ] || fail "claude/skills/ contains no skill directories"

if [ -n "$missing_skills" ]; then
    fail "one or more skill directories are missing SKILL.md" "missing files:
${missing_skills}"
fi

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

# Loop over required sections in the parent shell (no pipeline subshell —
# `printf | while` runs in a subshell on POSIX sh, so `fail`/`exit` would
# only kill the subshell and the outer script would silently succeed).
# Here-doc redirect keeps the loop in the parent shell.
while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qxF "## ${section}" "${UNIVERSAL_PATH}"; then
        fail "${UNIVERSAL_PATH} missing required section: ## ${section}"
    fi
done <<EOF
${universal_required}
EOF

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

while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qxF "## ${section}" "${GITHUB_PROFILE_PATH}"; then
        fail "${GITHUB_PROFILE_PATH} missing required section: ## ${section}"
    fi
done <<EOF
${github_profile_required}
EOF

# ------------------------------------------------------------------
# Check 4 — security.md required H2 sections
# ------------------------------------------------------------------
SECURITY_PROFILE_PATH="claude/profiles/security.md"
info "Checking ${SECURITY_PROFILE_PATH} sections..."
[ -f "${SECURITY_PROFILE_PATH}" ] || fail "${SECURITY_PROFILE_PATH} does not exist"

security_profile_required="Fail-Closed Reasoning
Defense in Depth
Cryptographic Operations
Authentication Scope Expansion
Input Validation Patterns to Refuse
Secret Handling Reinforcement
Anti-Patterns"

while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qxF "## ${section}" "${SECURITY_PROFILE_PATH}"; then
        fail "${SECURITY_PROFILE_PATH} missing required section: ## ${section}"
    fi
done <<EOF
${security_profile_required}
EOF

# ------------------------------------------------------------------
# Check 5 — kubernetes.md required H2 sections
# ------------------------------------------------------------------
KUBERNETES_PROFILE_PATH="claude/profiles/kubernetes.md"
info "Checking ${KUBERNETES_PROFILE_PATH} sections..."
[ -f "${KUBERNETES_PROFILE_PATH}" ] || fail "${KUBERNETES_PROFILE_PATH} does not exist"

kubernetes_profile_required="Context Pinning
Namespace Allowlist
Destructive Command Gating
Manifest Provenance
Anti-Patterns"

while IFS= read -r section; do
    [ -n "$section" ] || continue
    if ! grep -qxF "## ${section}" "${KUBERNETES_PROFILE_PATH}"; then
        fail "${KUBERNETES_PROFILE_PATH} missing required section: ## ${section}"
    fi
done <<EOF
${kubernetes_profile_required}
EOF

# ------------------------------------------------------------------
# Check 6 — no SKILL.md references _universal.md (negative claim)
# ------------------------------------------------------------------
# Restricted to SKILL.md files specifically. Future README.md or notes
# under a skill directory may legitimately mention _universal.md (e.g.
# a "this skill has no profile addendum" note); only SKILL.md must
# avoid the link, since those are the files Claude Code parses for
# the auto-loaded reference graph.
#
# Per-file grep -q (in an `if` clause, so its non-zero "no match" exit
# is consumed by the conditional rather than tripping `set -e`).
# `find` errors still propagate naturally — only the grep "no match"
# case is consumed.
info "Checking no SKILL.md references _universal.md..."
violators=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qF "_universal.md" "$f"; then
        violators="${violators}${f}
"
    fi
done <<EOF
$(find claude/skills -type f -name SKILL.md)
EOF
if [ -n "$violators" ]; then
    fail "claude/skills/ SKILL.md files reference _universal.md (would auto-load orchestrator content for human Claude Code users — see #99 architecture decision)" "violating files:
${violators}"
fi

# ------------------------------------------------------------------
info "All L0 skill-structure checks passed."
exit 0
