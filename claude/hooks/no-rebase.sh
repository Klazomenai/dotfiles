#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# Normalize backslash-newline continuations.
COMMAND="${COMMAND//$'\\\n'/}"

if [[ "$TOOL" != "Bash" ]]; then
  exit 0
fi

# Detect 'git rebase' with shell-boundary anchoring to avoid matching
# quoted strings like 'echo "git rebase"'. Recognises common prefixes:
# sudo, command, exec, env, and inline VAR=val assignments.
if echo "$COMMAND" | grep -qE '(^|[;|&({])[[:space:]]*((sudo|command|exec)[[:space:]]+|(env[[:space:]]+)?([A-Z_][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)*)?git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]*))*[[:space:]]+rebase($|[^a-zA-Z0-9_-])'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "NEVER rebase — it rewrites history and requires force-push. Use git merge instead."
    }
  }'
  exit 0
fi
exit 0
