#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$TOOL" != "Bash" ]]; then
  exit 0
fi

# Case-sensitive, token-boundary anchored — 'git' must follow start-of-line or a real
# shell delimiter (;|&(){), with optional whitespace between delimiter and 'git'.
# Whitespace alone is NOT a valid boundary: prevents 'echo git push ...' from being
# treated as a real push. Known command-runners (sudo, command, exec, env) are
# recognised as wrappers so 'sudo git push ...' is still caught.
# Note: 'bash -c "git push ..."' is not parsed — inner quoted content is out of scope.
if ! echo "$COMMAND" | grep -qE '(^|[;|&({])[[:space:]]*((sudo|command|exec|env)[[:space:]]+)?git[[:space:]]+push($|[[:space:]])'; then
  exit 0
fi

deny() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "NEVER push to main or master. Push to a feature branch instead."
    }
  }'
  exit 0
}

is_protected_target() {
  local t="$1"
  t="${t##*:}"          # refspec: take target (after colon)
  t="${t//\"/}"         # strip double quotes
  t="${t//\'/}"         # strip single quotes
  t="${t#\+}"           # strip force-push prefix (+main → main)
  t="${t#refs/heads/}"  # strip refs/heads/ prefix
  t="${t#refs/}"        # strip remaining refs/ prefix
  # Deny protected branch names and symbolic refs that may resolve to main/master:
  # HEAD, @, @{u}, @{upstream}, @{push} — any of these could be tracking main.
  # Use [{}] character classes for literal brace matching (avoids ERE interval ambiguity).
  echo "$t" | grep -qE '^(main|master|HEAD|@([{][^}]*[}])?)$'
}

# Extract ALL 'git push ...' segments, each stopped at the next shell operator
# or redirection (> < >> 2> &>). The anchored pattern prevents substring matches.
# Looping all matches catches multiple pushes in one compound command.
while IFS= read -r push_segment; do
  [[ -z "$push_segment" ]] && continue

  # Strip leading whitespace/operators/grouping delimiters left by the anchor group.
  push_segment=$(echo "$push_segment" | sed 's/^[[:space:];|&({]*//')

  # Strip everything up to and including 'git push', consuming any wrapper prefix
  # (sudo, command, exec, env) that precedes 'git'. Greedy '.*' ensures the wrapper
  # is removed even with arbitrary whitespace or env-var assignments before 'git'.
  after_push=$(echo "$push_segment" | sed 's/.*git[[:space:]][[:space:]]*push//')

  # Extract positionals, splitting on any whitespace (tr -s handles tabs and
  # multi-space runs consistently with the [[:space:]]+ detector pattern).
  # Skip flags and values of known options-with-args.
  # Known git push options that consume the next token: -o/--push-option, --repo, --receive-pack/--exec
  positionals=""
  skip_next=0
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    case "$token" in
      -o|--push-option|--repo|--receive-pack|--exec) skip_next=1; continue ;;
      -*) continue ;;
    esac
    # Skip bare numeric tokens — these are file descriptor numbers from
    # fd-prefixed redirections (e.g. '2' from '2>&1', '1' from '1>/dev/null')
    # that slip through when the extractor stops at '>'.
    [[ "$token" =~ ^[0-9]+$ ]] && continue
    positionals="${positionals}${token}"$'\n'
  done < <(echo "$after_push" | tr -s '[:space:]' '\n')

  count=$(echo "$positionals" | grep -c '[^[:space:]]' || true)

  # No branch/refspec specified (bare push or remote-only push) → deny
  if [[ "$count" -lt 2 ]]; then
    deny
  fi

  # Check ALL refspecs (every positional after the remote).
  # Deny if any refspec target resolves to main/master — catches
  # multi-refspec pushes like 'git push origin main feat/foo'.
  refspecs=$(echo "$positionals" | grep '[^[:space:]]' | tail -n +2)
  while IFS= read -r refspec; do
    [[ -z "$refspec" ]] && continue
    if is_protected_target "$refspec"; then
      deny
    fi
  done <<< "$refspecs"

done < <(echo "$COMMAND" | grep -oE '(^|[;|&({])[[:space:]]*((sudo|command|exec|env)[[:space:]]+)?git[[:space:]]+push[^;&|><)]*')

exit 0
