# Adapter -- Claude Code

Harness-specific notes for the software-house skill running under Claude Code.
For harness-neutral specification, see `manifest.yaml` and `policies/`.

---

## Install location

```
~/.claude/skills/software-house/
```

Verify install:

```bash
ls ~/.claude/skills/software-house/SKILL.md
```

`install.sh` detects `~/.claude` and symlinks (or copies) the skill source tree
into this path. The entry point is `SKILL.md` -- Claude Code reads its YAML
frontmatter fields `name` and `description` for skill registration.

---

## How Claude Code surfaces this skill

- `/software-house <command> [args]` -- primary invocation pattern.
- `/help` -- the skill appears in the skills section under its registered `name`.
- If the skill does not appear in `/help`, run `install.sh` or manually check
  that `~/.claude/skills/software-house/SKILL.md` is present and has valid YAML
  frontmatter.

---

## Tool availability

| Tool | Available | Notes |
|------|-----------|-------|
| Read | Yes | Used freely on local paths |
| Write | Yes | Used freely within allowed scope |
| Edit | Yes | Used for atomic in-place edits |
| Glob | Yes | Used for directory scans |
| Grep | Yes | Used for content searches |
| Bash | Yes | Subject to allowlist/denylist per policies/privacy.md |
| AskUserQuestion | Yes (optional) | See section below |
| Task | Yes (subagent) | Not used by skill operations |
| MCP tools | Yes (harness) | Forbidden inside skill per policies/privacy.md |

The skill uses only Read, Write, Edit, Glob, Grep, Bash, and optionally
AskUserQuestion. It never invokes Task or any MCP tool.

---

## AskUserQuestion -- optional UX enhancement

When `AskUserQuestion` is available, the skill MAY use it to render canonical
confirmation prompts from `policies/safety.md section 3`. This is an optional
enhancement only.

Fallback (always the safe path): print the boxed prompt text to the
conversation, then wait for the next user message. Affirmative parsing rules
are in `policies/safety.md section 9` -- identical whether AskUserQuestion is
used or not.

The audit log always records the verbatim prompt text and the user's verbatim
response regardless of which rendering path was used.

---

## Bypass flag behavior

Claude Code bypass flag: `--dangerously-skip-permissions`

This flag bypasses harness-level tool-call permission prompts. It does NOT
bypass the skill's own confirmation gates. Per `policies/safety.md section 2`:

- Tier 2, 3, 4 operations still print the boxed prompt and wait.
- Egress consent gates still fire for external-provider agent writes.
- No "yes-to-all" from a prior session or prior approval in this session
  substitutes for a per-operation response.

When `--dangerously-skip-permissions` is active, the skill's gates are the
ONLY safeguard remaining. They are not relaxed; they become more important.

---

## Agent adapters -- Claude Code format

### Project agents

Canonical agent definitions live at:

```
<project>/.software-house/agents/<name>.md
```

Claude Code expects agent files at:

```
<project>/.claude/agents/<name>.md
```

The skill auto-generates a thin shim at the Claude Code location. Shim format:

```markdown
---
name: <name>
description: <one-line from canonical>
model: <model from canonical>
---

Canonical definition at: <project>/.software-house/agents/<name>.md

Read that file before responding.
```

The shim is never hand-edited. The skill rewrites it whenever the canonical
agent definition changes (e.g., after `set-model`, `promote`, `transfer`).

### Tools field in agent adapters

Canonical agent files include a `tools` frontmatter field listing the
canonical tool names the agent is authorized to use (populated from
`tools-config.json` at hire time). When writing Claude Code adapters,
the `tools` field is not included in the adapter shim -- it lives only
in the canonical definition. The `plan execute` operation reads the
canonical `tools` field to determine which tools each spawned sub-agent
may use.

### Global (freelance pool) agents

Canonical: `~/.software-house/agents/<name>.md`
Adapter:   `~/.claude/agents/<name>.md`

Same thin-shim format as project agents. The `reports_to` field in the
canonical definition is `null` for freelance agents.

---

## Filesystem scope (Claude Code-specific paths)

The skill writes to these Claude Code-specific paths:

```
~/.claude/agents/<name>.md                    -- global freelance adapters
<project>/.claude/agents/<name>.md            -- project team adapters
```

It reads (but does not write) these Claude Code configuration files:

```
~/.claude/CLAUDE.md                           -- user global instructions
<project>/.claude/settings.json               -- harness permissions (read-only)
```

The skill never modifies `settings.json` or any pre-existing user file in
`~/.claude/` other than the auto-generated adapter files it owns.

---

## Reading order on first invocation per session

1. `policies/privacy.md`
2. `policies/safety.md`
3. `operations/_shared.md`
4. The specific operation file matching the user's command.

Do not re-read within the same session.

---

## Quick reference

| Action | Command |
|--------|---------|
| Invoke skill | `/software-house <command>` |
| Verify install | `ls ~/.claude/skills/software-house/SKILL.md` |
| View registered skills | `/help` |
| Check adapters | `ls ~/.claude/agents/` |
| View audit log | `cat ~/.software-house/company/audit.log` |
