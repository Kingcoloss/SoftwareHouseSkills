# Operation: init — bootstrap company state

**Risk tier:** 2 (additive — creates new files only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Create the initial company state under `~/.software-house/` (canonical, harness-neutral) and seed the minimum files required for other operations to work. Detect which agent CLIs (Claude Code, OpenAI Codex CLI, Gemini CLI) are present so future `hire` operations know where to write per-harness adapters. Idempotent — safe to run repeatedly; never overwrites existing content.

## Preconditions

None. The user can run `init` on a fresh machine.

## Step-by-step protocol

### 1. Detect existing state

Check whether `$COMPANY_HOME` (`~/.software-house/company`) already exists.

- If it exists and contains `index.md` -> tell the user the company is already initialized and stop. Suggest `list` instead. Do not re-init.
- If it exists but is missing key files -> treat as partial init; only create the missing ones (still requires confirmation).
- If it does not exist -> fresh init.

### 2. Detect installed harnesses

Inspect the user's home directory for harness install markers (existence checks only — no contents read):

| Harness | Marker(s) | If present, set |
|---|---|---|
| Claude Code | `~/.claude/` directory exists | `HAS_CLAUDE_CODE=1` |
| OpenAI Codex CLI | `~/.codex/` OR `~/.agents/` exists | `HAS_CODEX=1` |
| Gemini CLI | `~/.gemini/` exists | `HAS_GEMINI=1` |

Use Bash with allowlisted commands only: `test -d ~/.claude && echo yes`, etc.

If zero harnesses are detected, warn the user that no agent CLI was found and ask whether to proceed with company state only (no per-harness adapters will be writable). If they confirm, set all three flags to 0 and continue.

If at least one harness is detected, present the detected list and ask the user (text prompt) whether to install adapters into all detected harnesses, or only a subset. Default to all. Wait for next user message; parse response. (This pre-question is informational — the actual tier-2 confirmation comes at step 4.)

### 3. Compute the plan

Build the list of paths and files that will be created. Filter out any that already exist (idempotency).

Always:

```
~/.software-house/
~/.software-house/company/
~/.software-house/company/raw/
~/.software-house/company/wiki/
~/.software-house/company/wiki/people/
~/.software-house/company/wiki/teams/
~/.software-house/company/wiki/departments/
~/.software-house/company/wiki/synthesis/
~/.software-house/company/policies/
~/.software-house/company/alumni/
~/.software-house/company/outsource/
~/.software-house/departments/
~/.software-house/agents/
~/.software-house/config/
~/.software-house/company/CLAUDE.md
~/.software-house/company/index.md
~/.software-house/company/audit.log
~/.software-house/company/outsource/manifest.json
~/.software-house/projects-index.json
~/.software-house/config/providers.json
~/.software-house/config/models-config.json
```

Per detected harness (only those the user opted in to in step 2):

| Harness | Paths added to plan |
|---|---|
| Claude Code | `~/.claude/skills/software-house/` (if not already a symlink/copy from install.sh) |
| Codex CLI | `~/.agents/skills/software-house/` (or `~/.codex/skills/software-house/` per Codex config) |
| Gemini CLI | `~/.gemini/extensions/software-house/` |

The actual skill files at those install paths are normally created by `install.sh` at distribution time. `init` only creates the directory if missing and notes that the skill body is expected to be installed separately. `init` itself does NOT copy skill files between locations (that is `install.sh`'s job).

### 4. Confirm (tier 2)

Print the filtered plan, then print the canonical Tier-2 prompt from `policies/safety.md §3` and wait for the next user message:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Parse the response per `safety.md §9`. If non-affirmative, abort with no log entry.

### 5. Create the directories

Use `mkdir -p` for each directory in the plan. This is idempotent and matches the privacy allowlist.

### 6. Create the seed files

Use the atomic write pattern from `_shared.md §6` for any file that may already exist. For brand-new files, write directly.

#### 6.1 `$COMPANY_HOME/CLAUDE.md`

```markdown
---
type: company-schema
classification: internal
created_at: <utc-timestamp>
---

# Company Schema

This file defines how this company's state is structured. The
software-house skill maintains it. Edits here change company-wide
conventions. The same file is read by Claude Code, Codex CLI, and
Gemini CLI invocations of the skill.

## Tiers

1. Company — this directory (`~/.software-house/company/`)
2. Department — `~/.software-house/departments/<dept>/`
3. Team — `<project>/.software-house/team/`
4. Role — agent files at `<project>/.software-house/agents/<name>.md`
   (canonical) and `<project>/.<harness>/agents/<name>.md` (adapters);
   freelance pool at `~/.software-house/agents/<name>.md`

## Wiki layout per tier

- `raw/` — immutable source documents
- `wiki/` — compiled entity, concept, synthesis pages
- `index.md` — generated catalog (do not edit)
- `audit.log` — generated append-only log (do not edit)

## Page types

- People (employees), Teams, Departments — entity pages
- Concepts — non-entity knowledge (policies, standards, decisions)
- Synthesis — derived views (org chart, dashboards, retros)

## Classification

Every page declares one of: public | internal | confidential | restricted.
The skill enforces classification ceilings during reads.

## Provider awareness

Every employee page declares `provider` and `egress_consent` in
frontmatter. Providers are classified in
`~/.software-house/config/providers.json` as `local` (no egress) or
`external` (egress with typed consent). See `policies/privacy.md §7`.
```

#### 6.2 `$COMPANY_INDEX` (`~/.software-house/company/index.md`)

```markdown
# Company Wiki Index

This index is auto-generated by the software-house skill. Do not edit
directly — your changes will be overwritten on the next rebuild.

## People

(none yet — run `/software-house hire` to add employees)

## Teams

(none yet)

## Departments

(none yet — run `/software-house dept create` to add departments)

## Synthesis

(none yet)
```

#### 6.3 `$AUDIT_LOG`

Empty file. The `init` operation itself appends its own entry below at step 7.

#### 6.4 `$OUTSOURCE_MANIFEST` (`~/.software-house/company/outsource/manifest.json`)

```json
{
  "freelancers": []
}
```

#### 6.5 `$PROJECTS_INDEX` (`~/.software-house/projects-index.json`)

```json
{
  "projects": {}
}
```

#### 6.6 `$PROVIDERS_CONFIG` (`~/.software-house/config/providers.json`)

If the file does not already exist, copy the default catalog from the skill's bundled `config/providers.json`. The bundled file is the source of truth for the default provider list (~25 entries with `local` or `external` egress classification). Use `cp` (allowlisted), not network fetch.

If the bundled file is missing (skill install incomplete), write a minimal stub that contains only `ollama` (local) and abort the operation with `result: failed, error: providers.json template missing — reinstall skill`.

#### 6.7 `$MODELS_CONFIG` (`~/.software-house/config/models-config.json`)

If the file does not already exist, copy the default from the skill's bundled `config/models-config.json`. The default `defaults_by_role` MUST point at local providers per `policies/privacy.md §7.3`.

If the bundled file is missing, write a minimal stub:

```json
{
  "defaults_by_role": {
    "default": {"provider": "ollama", "model": "qwen3-coder:32b", "effort": "medium"}
  },
  "effort_presets": {
    "low":    {"max_tokens": 4096,  "thinking": false},
    "medium": {"max_tokens": 16384, "thinking": false},
    "high":   {"max_tokens": 65536, "thinking": true}
  },
  "model_aliases": {}
}
```

#### 6.8 `$TOOLS_CONFIG` (`~/.software-house/config/tools-config.json`)

If the file does not already exist, copy the default from the skill's bundled `config/tools-config.json`. The default `shared_tools` and `role_tools` MUST include the mandatory tool set and per-role additions.

If the bundled file is missing, write a minimal stub:

```json
{
  "version": 1,
  "shared_tools": ["read", "write", "edit", "bash", "glob", "grep"],
  "role_tools": { "default": [] },
  "metadata": { "schema_version": 1 }
}
```

### 7. Append the audit log entry

```json
{"ts":"<utc>","actor":"user","op":"init","scope":"company","args":{"harnesses":["claude-code","codex","gemini"]},"diff":{"created":["...all paths actually created..."]},"confirmation":{"tier":2,"prompt":"<exact box prompt text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

`args.harnesses` is the list of harness keys the user opted in to in step 2. Empty list if the user opted out of all harnesses.

### 8. Report to the user

Print (substituting actual counts and detected harnesses):

```
Company initialized at ~/.software-house/
  Created N files and M directories.
  Harness adapters: claude-code, codex, gemini
  Provider config:  ~/.software-house/config/providers.json (K providers, J external)
  Default model:    <provider>:<model> (effort: <preset>)

  Next steps:
    /software-house dept create <name>                       create a department
    /software-house hire <name> --team <t> --role <r>        hire your first employee
    /software-house list                                     show what is in the company
```

## Failure modes

- `mkdir` failure (permission denied) -> report which path failed, no audit log entry, suggest the user check `~/.software-house/` and the harness install paths for permissions.
- Disk full during file creation -> roll back any temp files, report which file failed, no audit log entry.
- Bundled `providers.json` or `models-config.json` missing -> report skill install incomplete, suggest re-running `install.sh`. Audit log entry with `result: failed`.
- User cancels at step 4 -> no changes, no log entry, print "Cancelled. No changes made."
- User opts out of all harnesses at step 2 -> proceed with company state only, no harness adapter directories created. Print a warning that future `hire` operations will write canonical agent files but no harness adapters until at least one harness is installed.
