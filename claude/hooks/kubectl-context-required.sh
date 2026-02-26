#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qE '^\s*kubectl\s+(apply|delete|patch|edit|create|replace|scale|drain|cordon|uncordon|exec|rollout|label|annotate|taint)\b'; then
  if ! echo "$COMMAND" | grep -qE '--context[ =]'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "kubectl mutating commands require --context flag. Verify target cluster before proceeding."
      }
    }'
    exit 0
  fi
fi
exit 0
