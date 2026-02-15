#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" == "Bash" ]] && echo "$COMMAND" | grep -qi 'gh pr create'; then
  if echo "$COMMAND" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use \"Refs #N\" or \"Part of #N\" instead of \"Closes #N\" in PR bodies. Closing issues is a merge-time decision after peer review."
      }
    }'
    exit 0
  fi
fi
exit 0
