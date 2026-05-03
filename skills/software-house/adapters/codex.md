# Adapter -- OpenAI Codex CLI

Harness-specific notes for the software-house skill running under OpenAI Codex CLI.
For harness-neutral specification, see `manifest.yaml` and `policies/`.

References:
- https://developers.openai.com/codex/skills
- https://developers.openai.com/codex/guides/agents-md
- https://github.com/openai/codex/blob/main/docs/skills.md

---

## Install locations

### User-level install (recommended)

```
~/.agents/skills/software-house/
```

`install.sh` detects `~/.codex` or `~/.agents` and installs here. The
`CODEX_HOME` environment variable overrides the default `~/.codex` location
if set.

### Project-level install

```
<repo>/.agents/skills/software-house/
```

Codex scans `.agents/skills` from the current working directory up to the
repository root. A project-level install takes precedence over the user-level
install for invocations from within that repo.

---

## Entry point

Same `SKILL.md` as Claude Code. Codex reads the YAML frontmatter fields
`name` and `description` for skill registration. The frontmatter is
compatible across both harnesses.

---

## Configuration registration

After install, register the skill in `~/.codex/config.toml` under the
`[skills]` array:

```toml
[[skills]]
path    = "~/.agents/skills/software-house"
enabled = true
```

Codex requires a restart after editing `config.toml`.

---

## Optional UI metadata -- agents/openai.yaml

`agents/openai.yaml` (shipped with the skill) provides Codex-specific
invocation policy and tool dependency metadata per Codex conventions.
This file is a next-step deliverable -- it is referenced here so the
adapter and the eventual file are consistent. Until it exists, Codex
falls back to its defaults.

---

## Project context -- AGENTS.md

Codex reads `AGENTS.md` at the root of the project being worked on as
project-level context. An optional `AGENTS.override.md` takes precedence
over `AGENTS.md` when present.

The skill does not auto-generate `AGENTS.md` -- that is the user's project
charter. The skill generates only the thin adapter files listed below.

---

## Tool availability

| Tool | Available | Notes |
|------|-----------|-------|
| Read | Yes | Used freely on local paths |
| Write | Yes | Used freely within allowed scope |
| Edit | Yes | Used for atomic in-place edits |
| Glob | Yes | Used for directory scans |
| Grep | Yes | Used for content searches |
| Shell tool | Yes (Bash equivalent) | Subject to allowlist/denylist per policies/privacy.md |
| AskUserQuestion | No | Not provided by Codex |
| confirm() | Yes (optional) | Codex equivalent of AskUserQuestion; same fallback semantics |

Codex does not provide `AskUserQuestion`. The skill uses the canonical
text-prompt protocol from `policies/safety.md section 3` as the primary
(and only) confirmation method -- this is not a fallback, it IS the protocol.

The Codex shell tool allowlist/denylist from `policies/privacy.md section 2`
applies identically to Codex's shell as to Claude Code's Bash tool.

---

## Bypass flag behavior

Codex bypass flags: `--dangerously-bypass-approvals-and-sandbox` and `--full-auto`

These flags bypass harness-level tool-call approval prompts. They do NOT
bypass the skill's own confirmation gates. Per `policies/safety.md section 2`:

- Tier 2, 3, 4 operations still print the boxed prompt and wait.
- Egress consent gates still fire for external-provider agent writes.
- No prior approval in this session substitutes for a per-operation response.

---

## Agent adapters -- Codex format

### Project agents

Canonical agent definitions live at:

```
<project>/.software-house/agents/<name>.md
```

Codex expects agent files at:

```
<project>/.codex/agents/<name>.md
```

The skill auto-generates a thin shim at the Codex location. Shim format
follows Codex AGENTS.md frontmatter spec:

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
agent definition changes.

### Global (freelance pool) agents

If the user-level Codex agents directory exists:

```
~/.codex/agents/<name>.md
```

Same thin-shim format. Canonical source is `~/.software-house/agents/<name>.md`.

---

## Filesystem scope (Codex-specific paths)

The skill writes to these Codex-specific paths:

```
~/.codex/agents/<name>.md                     -- global freelance adapters (if dir exists)
<project>/.codex/agents/<name>.md             -- project team adapters
```

It reads (but does not write):

```
~/.codex/config.toml                          -- harness configuration (read-only)
<project>/AGENTS.md                           -- project context (read-only)
<project>/AGENTS.override.md                  -- project context override (read-only)
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

| Action | Command / Path |
|--------|----------------|
| User install path | `~/.agents/skills/software-house/` |
| Project install path | `<repo>/.agents/skills/software-house/` |
| Config registration | `~/.codex/config.toml` `[[skills]]` array |
| CODEX_HOME override | `export CODEX_HOME=/path/to/.codex` |
| Verify install | `ls ~/.agents/skills/software-house/SKILL.md` |
| Project adapters | `ls <project>/.codex/agents/` |
| Audit log | `cat ~/.software-house/company/audit.log` |
