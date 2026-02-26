#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qE '^\s*helm\s+(upgrade|install)\b'; then
  if ! echo "$COMMAND" | grep -qE '--version[ =]'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "helm upgrade/install requires --version flag. Pin chart version explicitly."
      }
    }'
    exit 0
  fi
fi
exit 0
