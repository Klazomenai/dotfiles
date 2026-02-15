#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qi 'git commit'; then
  if ! echo "$COMMAND" | grep -qE '(--gpg-sign|-S)'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "All commits MUST be signed. Add --gpg-sign flag to git commit."
      }
    }'
    exit 0
  fi
fi
exit 0
