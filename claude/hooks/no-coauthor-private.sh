#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qi 'git commit'; then
  if echo "$COMMAND" | grep -qi 'Co-Authored-By'; then
    IS_PRIVATE=$(gh repo view --json isPrivate -q '.isPrivate' 2>/dev/null || echo "unknown")
    if [[ "$IS_PRIVATE" == "true" || "$IS_PRIVATE" == "unknown" ]]; then
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "NO Claude co-author on private or visibility-unknown repos. Remove the Co-Authored-By line."
        }
      }'
      exit 0
    fi
  fi
fi
exit 0
