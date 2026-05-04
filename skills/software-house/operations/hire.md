# Operation: hire -- create a new agent

**Risk tier:** 2 (additive -- creates new files only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Create a new agent (employee or freelance) with a canonical agent file, a wiki people page, and per-harness adapter shims. If the chosen provider is external, require a typed `EGRESS-CONSENT-<provider>` token before writing any file. Offer the local fallback from `$MODELS_CONFIG` `fallback_external` section when the user declines egress or when the external provider is unavailable.

## Invocation patterns

| Command | Behavior |
|---|---|
| `hire <name> --role <role>` | Hire into the current project team with role defaults from `$MODELS_CONFIG` |
| `hire <name> --role <role> --provider <p> --model <m>` | Override provider and model |
| `hire <name> --role <role> --effort low\|med\|high` | Override effort preset |
| `hire <name> --role <role> --dept <dept>` | Assign to a department at hire time |
| `hire <name> --role <role> --pool` | Hire into the freelance pool (`$AGENTS_GLOBAL`) not a project team |

`--pool` and `--dept` may be combined: hire into pool and pre-assign department.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--role` | yes | Must exactly match a key in `defaults_by_role` in `$MODELS_CONFIG` |
| `--provider` | no | Must exactly match a key in `$PROVIDERS_CONFIG`; defaults to role default from `$MODELS_CONFIG` |
| `--model` | no | Required if `--provider` is given without a model; must be a non-empty string |
| `--effort` | no | One of `low`, `med`, `high`; `med` maps to `medium` internally; defaults to role default |
| `--dept` | no | Must match an existing directory under `$DEPARTMENTS_HOME` |
| `--pool` | no | Flag; mutually exclusive with a detected project context only for scope; both may coexist |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. `$PROVIDERS_CONFIG` is readable. If not, refuse with lint-style error.
3. `$MODELS_CONFIG` is readable. If not, refuse.
4. No existing agent at the target canonical path (see Step 3). If one exists, refuse: `Error: agent <name> already exists. Use /software-house set-model to change config, or /software-house fire then re-hire.`

## Step-by-step protocol

### 1. Validate inputs

Read `$MODELS_CONFIG`. Check that `--role` matches a key in `defaults_by_role`. If not, list valid role keys and abort.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

Resolve provider and model:

- If `--provider` is not given, read `defaults_by_role[role].provider` and `defaults_by_role[role].model` from `$MODELS_CONFIG`.
- If `--provider` is given, use it. If `--model` is omitted, abort: `Error: --model is required when --provider is specified.`
- Validate `provider` key against `$PROVIDERS_CONFIG`. Abort if not found.

Resolve effort:
- `med` -> `medium` internally.
- If `--effort` is not given, use `defaults_by_role[role].effort`.

If `--dept` is given, check that `$DEPARTMENTS_HOME/<dept>/` exists. Abort if not: `Error: department <dept> not found. Run /software-house dept-create <dept> first.`

### 2. Determine scope and target paths

If `--pool` is given OR if no project is detected (per `_shared.md §4`):
- Scope: `freelance`
- Canonical agent file: `$AGENTS_GLOBAL/<name>.md`
- Adapter root: none (freelance pool agents do not get per-project harness adapters at hire time; adapters are written when the agent is first assigned to a project via `dept-assign` or a future `transfer` operation)

Otherwise (project detected):
- Scope: `team:<team-name>` (resolved from `$PROJECTS_INDEX` or `--team` flag)
- Canonical agent file: `$TEAM_AGENTS/<name>.md`
- Wiki people page: `$WIKI_PEOPLE/<name>.md`
- Adapter paths (generated per detected harness, per `_shared.md §3`):
  - Claude Code: `$PROJECT/.claude/agents/<name>.md` (if `~/.claude/` exists)
  - Codex CLI: `$PROJECT/.codex/agents/<name>.md` (if `~/.codex/` or `~/.agents/` exists)
  - Gemini CLI: `$PROJECT/.gemini/extensions/<name>/gemini-extension.json` + `GEMINI.md` (if `~/.gemini/` exists)

Detect installed harnesses using existence checks only (no contents read):

```
test -d ~/.claude  -> HAS_CLAUDE_CODE
test -d ~/.codex || test -d ~/.agents  -> HAS_CODEX
test -d ~/.gemini  -> HAS_GEMINI
```

### 3. Check for conflicts

Check whether the canonical agent file already exists. If so, abort per Precondition 4.

Check `$WIKI_PEOPLE/<name>.md` as well (project scope). If that exists but the agent file does not, warn: `Warning: wiki entry exists for <name> without a canonical agent file. Proceeding will create both.` and continue.

### 4. Egress consent gate (external providers only)

Classify the resolved `provider` using `$PROVIDERS_CONFIG`. If `class == "external"`:

Print the exact egress consent prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| WARNING -- External provider selected: <provider>        |
| When this agent runs, its conversations will be sent to: |
|   <default_endpoint from providers.json>                 |
| This egress is performed by the agent runtime, not by    |
| this skill. The skill itself never makes network calls.  |
|                                                          |
| To approve this egress, type the literal token:          |
|   EGRESS-CONSENT-<provider>                              |
| Anything else, or no response, will cancel the hire.     |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- If the token `EGRESS-CONSENT-<provider>` (exact case, exact spelling) appears in the message, record it and advance to Step 5.
- Otherwise, abort. Before aborting, print the local fallback for the role:

```
Hire cancelled -- egress consent not given.

Local fallback for role <role>:
  provider: <fallback_provider>
  model:    <fallback_model>
  effort:   <fallback_effort>

Run the same hire command without --provider to use the local fallback,
or re-run with the external provider and supply EGRESS-CONSENT-<provider>.
```

Do not write any file. Do not log anything.

If `class == "local"`, skip this step entirely. Set `egress_consent_required = false`.

### 5. Tier-2 confirmation

Build the full file list that will be created. Print it:

```
I will create the following for agent '<name>':
  Canonical: $TEAM_AGENTS/<name>.md (or $AGENTS_GLOBAL/<name>.md)
  Wiki:      $WIKI_PEOPLE/<name>.md
  Adapter (claude-code): $PROJECT/.claude/agents/<name>.md
  Adapter (codex):       $PROJECT/.codex/agents/<name>.md
  Adapter (gemini):      $PROJECT/.gemini/extensions/<name>/
  Index update:          $TEAM_INDEX (or $COMPANY_INDEX)
  Audit log:             $AUDIT_LOG
```

Omit adapter lines for harnesses not detected. Omit `Adapter` section entirely for freelance pool.

Print the Tier-2 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Write canonical agent file

Get the current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Write `$TEAM_AGENTS/<name>.md` (or `$AGENTS_GLOBAL/<name>.md` for pool) with YAML frontmatter per `_shared.md §7`:

```yaml
---
name: <name>
description: <role-key> agent
provider: <provider>
model: <model>
egress_consent: <none | external:<utc-date>>
employee_id: emp-<padded-next-id>
team: <team-name | null>
department: <dept | null>
role: <role>
position: <role-key human label>
reports_to: null
status: onboarding
hired_at: <utc-date YYYY-MM-DD>
level: 1
xp: 0
effort_preset: <effort>
classification: internal
buddy: null
employment: <permanent | freelance>
hired_by_teams: []
achievements: []
---

# <name>

Agent provisioned by software-house skill.
Role: <role>
Provider: <provider> [<class>]
```

For the `employee_id`: glob `$WIKI_PEOPLE/` and `$TEAM_AGENTS/` for existing `.md` files, count them, increment by one, zero-pad to 3 digits (e.g., `emp-004`).

`employment` is `freelance` when `--pool` flag is given; otherwise `permanent`.

`egress_consent` is:
- `none` if provider is local
- `external:<utc-date-of-consent>` if provider is external (date is the timestamp from Step 4)

### 7. Write wiki people page

Write `$WIKI_PEOPLE/<name>.md` with the same frontmatter (identical fields). Add a body section with onboarding instructions placeholder:

```markdown
---
<same frontmatter as canonical agent file>
---

# <name>

## Onboarding

Briefing not yet written. Run `/software-house onboard <name>` to generate.

## Notes

(empty)
```

Skip this step for freelance pool (no team context): the wiki entry is written to `$WIKI_PEOPLE` only when the agent is assigned to a team.

### 8. Write harness adapters

For each detected harness, write the adapter. Skip if the harness directory does not exist.

#### Claude Code adapter

`$PROJECT/.claude/agents/<name>.md`:

```yaml
---
name: <name>
description: <role-key> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to $TEAM_AGENTS/<name>.md>

Role: <role>
Provider: <provider>
Effort: <effort>
```

#### Codex CLI adapter

`$PROJECT/.codex/agents/<name>.md` (create `.codex/agents/` dir if missing):

```yaml
---
name: <name>
description: <role-key> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to $TEAM_AGENTS/<name>.md>
```

#### Gemini CLI adapter

Create `$PROJECT/.gemini/extensions/<name>/` directory.

Write `$PROJECT/.gemini/extensions/<name>/gemini-extension.json`:

```json
{
  "name": "<name>",
  "version": "1.0",
  "description": "<role-key> agent (software-house managed)",
  "canonicalPath": "<absolute path to $TEAM_AGENTS/<name>.md>"
}
```

Write `$PROJECT/.gemini/extensions/<name>/GEMINI.md`:

```markdown
# <name>

Managed by software-house skill.
Canonical definition: <absolute path to $TEAM_AGENTS/<name>.md>

Role: <role>
Provider: <provider>
Effort: <effort>
```

### 9. Update team roster and index

Append `<name>` to the `members` list in `$WIKI_TEAMS/<team>.md` using the atomic write pattern from `_shared.md §6`.

Rebuild `$TEAM_INDEX` per `_shared.md §8`.

Rebuild `$COMPANY_INDEX` if any company-tier wiki pages were changed.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"hire","scope":"<scope>","args":{"name":"<name>","role":"<role>","provider":"<provider>","model":"<model>","effort":"<effort>","dept":"<dept|null>","pool":<bool>},"diff":{"created":["<all created paths>"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":<bool>,"granted":"<token|null>","provider":"<provider|null>","ts":"<utc|null>"},"result":"ok"}
```

### 11. Report to user

```
Hired <name> (<role>)
  Canonical:    <canonical path>
  Wiki:         $WIKI_PEOPLE/<name>.md
  Adapters:     claude-code, codex, gemini  (or subset / none)
  Provider:     <provider> [<class>]
  Model:        <model>
  Effort:       <effort>
  Egress:       <none | consented at <utc-date>>
  Status:       onboarding

Next steps:
  /software-house onboard <name>    write personalized briefing
  /software-house show <name>       inspect the agent record
```

## Adapter behavior

Adapters are thin shims only. They contain the model field (required by each harness to route requests) and a pointer to the canonical agent file. The canonical file is the source of truth. Any change to provider, model, or effort must be made via `set-model` (Phase 3), which rewrites both canonical and adapters atomically.

## Failure modes

- Role not in `$MODELS_CONFIG` -> list valid roles, abort, no log.
- Provider not in `$PROVIDERS_CONFIG` -> list valid providers, abort, no log.
- Egress consent not given -> print local fallback, abort, no log.
- Canonical file already exists -> refuse, suggest `set-model` or `fire`+re-hire, no log.
- `mkdir` fails (permissions) -> report path, abort, no log.
- Partial write during adapter creation -> roll back `.tmp` files; canonical and wiki page are written before adapters so they are intact; log `result: failed` with error.
- `--dept` given but department does not exist -> abort before any consent gate.

## Examples

```
# Hire a backend developer on the current project using local defaults
/software-house hire alice --role backend-dev

# Hire a tech-lead with an explicit external provider (will trigger egress gate)
/software-house hire bob --role tech-lead --provider anthropic --model claude-opus-4-7 --effort high

# Hire a freelance linter into the pool
/software-house hire ci-linter --role linter --pool

# Hire a frontend developer assigned to the design department
/software-house hire carol --role frontend-dev --dept design
```
