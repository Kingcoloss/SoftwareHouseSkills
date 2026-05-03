# Adapter -- Gemini CLI

Harness-specific notes for the software-house skill running under Gemini CLI.
For harness-neutral specification, see `manifest.yaml` and `policies/`.

Reference: https://geminicli.com/docs/extensions/reference/

---

## Install locations

### User-level install (recommended)

```
~/.gemini/extensions/software-house/
```

`install.sh` detects `~/.gemini` and installs here.

### Workspace install

```
<workspace>/.gemini/extensions/software-house/
```

A workspace-level install applies only when Gemini CLI is invoked from within
that workspace. It takes precedence over the user-level install.

---

## Entry point -- gemini-extension.json (REQUIRED)

Gemini CLI extensions require a `gemini-extension.json` manifest in the
extension root directory. Without this file, the extension is not loaded.

Expected fields for this skill:

```json
{
  "name": "software-house",
  "version": "0.1.0",
  "mcpServers": {},
  "contextFileName": "GEMINI.md",
  "excludeTools": []
}
```

- `mcpServers` -- empty: this skill does not expose MCP servers.
- `contextFileName` -- `GEMINI.md`: Gemini CLI loads this file as context
  when the extension is active, equivalent to how Claude Code uses SKILL.md.
- `excludeTools` -- empty: the skill uses all standard Gemini CLI tools.

---

## Context file -- GEMINI.md

When `contextFileName` is set to `GEMINI.md`, Gemini CLI reads that file and
injects its contents as context for the session. The `GEMINI.md` file shipped
with this skill has the same content posture as `SKILL.md` -- it describes
the skill's purpose, constraints C1-C4, state layout, and operation routing --
but is formatted for Gemini CLI's extension context format rather than as a
Claude Code skill frontmatter document.

Both `SKILL.md` and `GEMINI.md` are authoritative within their respective
harnesses. The canonical policies remain `policies/privacy.md` and
`policies/safety.md`, which are harness-neutral.

---

## Custom commands -- commands/*.toml

Gemini CLI extensions may define custom slash commands via TOML files under
the `commands/` directory. Each TOML file defines one command or command group.
Nested directories form command groups.

For this skill, `commands/software-house.toml` (and optional per-operation
files such as `commands/software-house/init.toml`, `commands/software-house/list.toml`,
etc.) define the `/software-house` command and its subcommands:

```
/software-house init
/software-house list [team]
/software-house show <name>
/software-house org-chart [team]
/software-house lint
```

The actual TOML command files are created by a separate task. This adapter
documents their location so the install path is consistent. The `commands/`
directory is at:

```
~/.gemini/extensions/software-house/commands/
```

---

## Tool availability

| Tool | Available | Notes |
|------|-----------|-------|
| Read | Yes | Used freely on local paths |
| Write | Yes | Used freely within allowed scope |
| Edit | Yes | Used for atomic in-place edits |
| Glob | Yes | Used for directory scans |
| Grep | Yes | Used for content searches |
| Shell | Yes (Bash equivalent) | Subject to allowlist/denylist per policies/privacy.md |
| AskUserQuestion | No | Not available in Gemini CLI |

Gemini CLI does not provide an `AskUserQuestion` equivalent. The skill uses
the canonical text-prompt protocol from `policies/safety.md section 3` as the
primary (and only) confirmation method -- this is not a fallback, it IS the
protocol.

Gemini CLI also provides its own model integrations (Gemini model family).
The skill does not use these directly; they are the harness runtime's concern.

The shell tool allowlist/denylist from `policies/privacy.md section 2`
applies identically to Gemini CLI's shell as to Claude Code's Bash tool.

---

## Bypass flag behavior

Gemini CLI bypass flags: `--yolo` or `--approval-mode yolo`

These flags bypass harness-level tool-call approval prompts. They do NOT
bypass the skill's own confirmation gates. Per `policies/safety.md section 2`:

- Tier 2, 3, 4 operations still print the boxed prompt and wait.
- Egress consent gates still fire for external-provider agent writes.
- No prior approval in this session substitutes for a per-operation response.

---

## Agent adapters -- Gemini CLI format

Gemini CLI's extension model treats each agent as its own extension. This is
heavier than the Claude Code or Codex adapter formats, which use a single
markdown shim file per agent.

### Project agents

Canonical agent definitions live at:

```
<project>/.software-house/agents/<name>.md
```

Gemini CLI expects each agent as an extension directory:

```
<project>/.gemini/extensions/<name>/
    gemini-extension.json
    GEMINI.md
```

The skill auto-generates both files for each agent. The `GEMINI.md` points at
the canonical agent definition and instructs Gemini CLI to read it before
responding. The `gemini-extension.json` contains the agent's metadata.

Example `gemini-extension.json` for an agent named `alice`:

```json
{
  "name": "alice",
  "version": "1.0.0",
  "mcpServers": {},
  "contextFileName": "GEMINI.md"
}
```

Example `GEMINI.md` for the same agent:

```markdown
Canonical definition at: <project>/.software-house/agents/alice.md

Read that file before responding.
```

Because Gemini's extension model requires a full directory per agent (not a
single shim file), the skill auto-generates both files whenever an agent is
hired, updated via `set-model` or `promote`, or transferred. The directories
are owned by the skill and are never hand-edited.

### Global (freelance pool) agents

```
~/.gemini/extensions/<name>/
    gemini-extension.json
    GEMINI.md
```

Same structure as project agents. Canonical source is
`~/.software-house/agents/<name>.md`.

---

## Filesystem scope (Gemini CLI-specific paths)

The skill writes to these Gemini CLI-specific paths:

```
~/.gemini/extensions/<name>/                  -- global freelance agent extensions
<project>/.gemini/extensions/<name>/          -- project team agent extensions
~/.gemini/extensions/software-house/commands/ -- skill command TOML files (auto-generated)
```

It reads (but does not write):

```
~/.gemini/GEMINI.md                           -- user global context (read-only)
```

---

## Reading order on first invocation per session

1. `policies/privacy.md`
2. `policies/safety.md`
3. `operations/_shared.md`
4. The specific operation file matching the user's command.

Do not re-read within the same session.

---

## Quick reference

| Action | Path / Command |
|--------|----------------|
| User install path | `~/.gemini/extensions/software-house/` |
| Workspace install | `<workspace>/.gemini/extensions/software-house/` |
| Required entry point | `gemini-extension.json` in install root |
| Context file | `GEMINI.md` (loaded via contextFileName) |
| Custom commands | `commands/*.toml` in install root |
| Project agent adapters | `<project>/.gemini/extensions/<name>/` |
| Global agent adapters | `~/.gemini/extensions/<name>/` |
| Audit log | `cat ~/.software-house/company/audit.log` |
