#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qi 'git push'; then
  if echo "$COMMAND" | grep -qiE 'git push.*(origin|upstream)\s+(main|master)\b'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "NEVER push to main or master. Push to a feature branch instead."
      }
    }'
    exit 0
  fi
fi
exit 0
