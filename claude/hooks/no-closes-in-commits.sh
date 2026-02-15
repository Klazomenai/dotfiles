#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qi 'git commit'; then
  if echo "$COMMAND" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use \"Refs #N\" instead of \"Closes #N\" in commit messages. Closing issues is a merge-time decision after peer review."
      }
    }'
    exit 0
  fi
fi
exit 0
