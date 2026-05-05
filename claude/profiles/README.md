# claude/profiles/ — agent-only constraints

This directory holds agent-only constraints for autonomous orchestrators
that consume our skill set. It is **deliberately outside the documented
Claude Code skill loader's scope** — Claude Code never reads this
directory.

## Layout

- `_universal.md` — cross-cutting agent rules (allowlist enforcement,
  redaction, mutation gating with operator-intent + pending-confirmation
  exception, audit trail, refusal policy). Applied to every persona by
  any consumer.
- `<skill-name>.md` — selective per-skill agent addendum. Only present
  for skills that have substantive agent-specific concerns beyond the
  universal rules. Skills without an entry here have no addendum (the
  universal profile still applies).

## Consumers

Today's known consumer: `klazomenai/bridge` — a Go Anthropic-API
orchestrator that fetches these files via filesystem path at boot and
concatenates them into each persona's system prompt.

Future consumers (other agent frameworks, hypothetical CI bots, etc.)
read this directory the same way. The file naming convention
(`_universal.md` + `<skill-name>.md`) and the contents are stable.

## Authoring

When you find yourself wanting to add a per-skill profile, sense-check:

- Is the rule cross-cutting (applies to multiple or all skills)? Goes
  in `_universal.md`, not a per-skill file.
- Is the rule a universal workflow rule that humans need too? Goes in
  `claude/skills/<name>/SKILL.md`, not here.
- Is the rule operator-only (Claude Code human user concerns —
  co-author handling, hook UX)? Goes in `claude/CLAUDE.md`, not here.
- Is the rule a hard enforcement that a tool registration / hook /
  permission can express? Use those layers, not this one.

This directory is for what's left: agent behaviour constraints that
aren't universal workflow knowledge and can't be machine-enforced.

## What this directory is NOT

- It is NOT a Claude Code skill — no frontmatter, no auto-invoke, no
  `~/.claude/skills/` symlink.
- It is NOT a place for human-operator UX concerns — those live in
  `claude/CLAUDE.md`.
- It is NOT a place for runtime infrastructure details — those live in
  the consumer (e.g. Bridge's deployment Dockerfile + skill loader).
