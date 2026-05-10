# Shared helpers — read once per session

This file is read once at the start of a session. Subsequent operations rely on the conventions defined here. If you have not read `policies/privacy.md` and `policies/safety.md` yet, read them now.

## 1. Canonical state location

State lives at `~/.software-house/` (harness-neutral). The same directory is read and written regardless of which agent CLI invokes the skill (Claude Code, OpenAI Codex CLI, Gemini CLI, etc.). One company, one source of truth.

## 2. Path constants

Use these names verbatim throughout operation files:

| Symbol | Path |
|---|---|
| `$SH_HOME` | `~/.software-house` |
| `$COMPANY_HOME` | `~/.software-house/company` |
| `$DEPARTMENTS_HOME` | `~/.software-house/departments` |
| `$AGENTS_GLOBAL` | `~/.software-house/agents` (freelance / outsource pool) |
| `$AUDIT_LOG` | `~/.software-house/company/audit.log` |
| `$COMPANY_INDEX` | `~/.software-house/company/index.md` |
| `$WIKI_PEOPLE` | `~/.software-house/company/wiki/people` |
| `$WIKI_TEAMS` | `~/.software-house/company/wiki/teams` |
| `$WIKI_DEPTS` | `~/.software-house/company/wiki/departments` |
| `$ALUMNI` | `~/.software-house/company/alumni` |
| `$OUTSOURCE_MANIFEST` | `~/.software-house/company/outsource/manifest.json` |
| `$PROJECTS_INDEX` | `~/.software-house/projects-index.json` |
| `$CONFIG_HOME` | `~/.software-house/config` |
| `$PROVIDERS_CONFIG` | `~/.software-house/config/providers.json` |
| `$MODELS_CONFIG` | `~/.software-house/config/models-config.json` |
| `$PROVIDERS_LOCAL` | `~/.software-house/config/providers.local.json` (user overlay, never overwritten) |
| `$MODELS_LOCAL` | `~/.software-house/config/models-config.local.json` (user overlay, never overwritten) |
| `$TOOLS_CONFIG` | `~/.software-house/config/tools-config.json` |
| `$TOOLS_LOCAL` | `~/.software-house/config/tools-config.local.json` (user overlay, never overwritten) |

Per-project (team-scoped), given the current project root `$PROJECT`:

| Symbol | Path |
|---|---|
| `$TEAM_DIR` | `$PROJECT/.software-house/team` |
| `$TEAM_AGENTS` | `$PROJECT/.software-house/agents` (canonical agent definitions) |
| `$TEAM_INDEX` | `$PROJECT/.software-house/team/index.md` |
| `$TEAM_AUDIT` | `$PROJECT/.software-house/team/audit.log` |
| `$TEAM_ROSTER` | `$PROJECT/.software-house/team/wiki/roster.md` |
| `$TEAM_TRANSFERS` | `$PROJECT/.software-house/team/transfers.log` |
| `$TEAM_SPRINTS` | `$PROJECT/.software-house/team/sprints` |
| `$TEAM_BACKLOG` | `$PROJECT/.software-house/team/backlog.md` |
| `$TEAM_PLANS` | `$PROJECT/.software-house/team/plans` |

Always expand `~` to `$HOME` in shell commands. Never write a literal `~` into a file.

## 3. Per-harness adapters

Canonical agent definitions live at `$TEAM_AGENTS/<name>.md` (project) or `$AGENTS_GLOBAL/<name>.md` (freelance). Each harness expects agent files in its own location, so the skill writes thin **adapter** files that point to the canonical:

| Harness | Adapter location | Adapter content |
|---|---|---|
| Claude Code | `$PROJECT/.claude/agents/<name>.md` | Frontmatter (`name`, `description`, `model`) + body referencing `$TEAM_AGENTS/<name>.md` |
| Codex CLI | `$PROJECT/.codex/agents/<name>.md` (or `$PROJECT/.agents/skills/<name>/SKILL.md` for Codex skill format) | Frontmatter per Codex AGENTS.md spec + body referencing canonical |
| Gemini CLI | `$PROJECT/.gemini/extensions/<name>/gemini-extension.json` + `GEMINI.md` | Manifest + context referencing canonical |

Adapters are auto-generated — never hand-edited. The skill rewrites them whenever the canonical changes.

If an adapter directory does not exist on the user's machine (e.g., user does not use Codex), skip writing that adapter. `init` and `hire` operations detect installed harnesses by checking for `~/.claude`, `~/.codex`, `~/.agents`, `~/.gemini` respectively.

## 4. Project detection

To find which team the current invocation is in:

1. Read `$PROJECTS_INDEX`. If the current `pwd` matches a key, use that team and department.
2. If no match, the invocation is **company-scoped** (not team-scoped). Operations that require a team must refuse with a clear message.
3. The user can override with `--team <name>` flags on most operations. The flag wins over auto-detection.

## 5. Audit log format (JSONL, append-only)

One self-contained JSON object per line. Never line-wrap. Never edit existing lines.

```json
{"ts":"2026-05-02T10:30:00Z","actor":"user","op":"hire","scope":"team:SoftwareHouseSkills","args":{"name":"alice","role":"backend-dev","provider":"ollama","model":"qwen3-coder:32b"},"diff":{"created":["~/.software-house/company/wiki/people/alice.md","~/some/project/.software-house/agents/alice.md","~/some/project/.claude/agents/alice.md"],"updated":["~/some/project/.software-house/team/wiki/roster.md"]},"confirmation":{"tier":2,"prompt":"I will create the following. Reply 'yes' to proceed.","response":"yes","ts":"2026-05-02T10:29:55Z"},"egress_consent":{"required":false,"granted":null},"result":"ok"}
```

Required fields:

- `ts` — UTC ISO-8601 with `Z` suffix
- `actor` — always `"user"` for now
- `op` — operation name (matches operation file name without `.md`)
- `scope` — one of `company`, `department:<dept>`, `team:<team>`, `agent:<name>`
- `args` — operation arguments, secrets stripped
- `diff` — `{"created":[...],"updated":[...],"archived":[...]}`. Omit empty arrays.
- `confirmation` — required for tier 2, 3, 4 per `policies/safety.md`. Omit for tier 1.
- `egress_consent` — required when the operation provisions an external-provider agent. `{"required":true,"granted":"EGRESS-CONSENT-<provider>","provider":"<provider>","ts":"<utc>"}` or `{"required":false}`.
- `result` — `"ok"` or `"failed"`. If failed, add `"error": "<short reason>"`.

Append by opening `$AUDIT_LOG` in append mode and writing one line ending with `\n`. Create the file if missing.

## 6. Atomic file writes

For any file that already exists, use the temp-file + atomic-rename pattern:

```
write content to <path>.tmp
verify <path>.tmp parses correctly (valid YAML/JSON/markdown frontmatter)
mv <path>.tmp <path>
```

If verification fails, `rm <path>.tmp` and abort. Never leave a `.tmp` behind. For new files, write directly.

## 7. Frontmatter conventions

All wiki and agent pages use YAML frontmatter delimited by `---`.

### Person (employee) page — `$WIKI_PEOPLE/<name>.md` and canonical agent files

```yaml
---
name: alice
description: <one-line role + specialty>
provider: ollama                       # ollama | lmstudio | vllm | llamacpp | localai | jan | anthropic | openai | google | vertex | azure | bedrock | groq | together | fireworks | deepseek | mistral | cohere | xai | perplexity | openrouter | replicate | huggingface | novita
model: qwen3-coder:32b                  # provider-specific model identifier
egress_consent: none                    # none | external:<utc-date-token-was-given>
employee_id: emp-001
team: <team-name>                       # null for outsource
department: <dept-name>                 # null for outsource
role: <role-key>                        # matches a key in models-config.json defaults_by_role (default, tech-lead, system-architect, code-reviewer, backend-dev, frontend-dev, doc-writer, linter, test-runner, researcher, business-analyst)
position: <human-readable>
reports_to: <name | null>
status: active                          # onboarding | active | transfer | alumni | freelance
hired_at: 2026-05-02
level: 1
xp: 0
effort_preset: medium                   # low | medium | high | xhigh
classification: internal                # public | internal | confidential | restricted
buddy: <name | null>
employment: permanent                   # permanent | freelance
hired_by_teams: []                      # for freelance only
secondary_teams: []                     # for matrix assignment (second.md)
achievements: []
responsibilities: []                   # populated from role-templates.json at hire time
deliverables: []                       # populated from role-templates.json at hire time
collaborates_with: []                  # role keys this agent works with regularly
handoff_triggers: {}                   # event -> [role-keys] mapping for inter-agent handoffs
confidence: 1.0                         # 0.0-1.0 wiki confidence score (Karpathy pattern)
lifecycle: draft                       # draft | reviewed | verified | stale | archived
last_compiled: null                     # YYYY-MM-DD when LLM last compiled this page
source_refs: []                        # paths to raw/ source documents
contract_type: null                     # retainer | hourly | project (freelance only)
contract_start: null                    # YYYY-MM-DD (freelance only)
contract_end: null                      # YYYY-MM-DD | null (freelance only)
rate: null                              # string (freelance only)
onboard_at: null                        # YYYY-MM-DD (added by onboard.md)
onboard_status: null                    # done (added by onboard.md)
offboard_at: null                       # YYYY-MM-DD (added by off-board.md)
offboard_status: null                   # pending | done (added by off-board.md)
promotion_at: null                      # YYYY-MM-DD (added by promote.md)
promotion_from_level: null              # integer (added by promote.md)
demotion_at: null                       # YYYY-MM-DD (added by demote.md)
demotion_from_level: null               # integer (added by demote.md)
fired_at: null                          # YYYY-MM-DD (added by fire.md)
updated_at: null                        # YYYY-MM-DD (added by any modifying op)
---
```

`provider` and `egress_consent` are required. If `provider` belongs to an external category (per `$PROVIDERS_CONFIG`), `egress_consent` MUST be `external:<date>` and the audit log MUST contain a matching `EGRESS-CONSENT-<provider>` token from the user. Lint enforces this.

### Team page — `$WIKI_TEAMS/<team>.md`

```yaml
---
name: <team-name>
description: <one-line>
department: <dept-name | null>
project_path: <absolute path | null>
lead: <employee-name>
members: [name1, name2]
contractors: []                          # freelance agents contracted to this team
seconded: []                             # agents matrix-assigned from other teams
status: active                          # active | disbanded
team_xp: 0
team_level: 1
classification: internal
created_at: 2026-05-02
---
```

### Department page — `$WIKI_DEPTS/<dept>.md`

```yaml
---
name: <dept-name>
description: <one-line>
head: <employee-name>
parent: <dept-name | null>
teams: [team1, team2]
status: active
classification: internal
created_at: 2026-05-02
---
```

## 8. Index.md rebuild

Several operations rebuild `$COMPANY_INDEX` or `$TEAM_INDEX`:

1. Glob the wiki directory.
2. Group by section (People, Teams, Departments, Synthesis).
3. Render `- [<name>](<relative-path>) — <description-from-frontmatter>` per entry.
4. Write atomically per §6.

The index is generated. If the user edits it directly, the next rebuild overwrites their changes.

## 9. Time

UTC ISO-8601 with `Z` suffix. Get current time:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Never use local time. Never use timezone offsets.

## 10. Name validation

Employee, team, and department names must match `^[a-z][a-z0-9-]{0,63}$`. Reject anything else with a message asking the user to choose a valid name.

## 11. Error reporting

When an operation fails:

1. Print: `Error: <what went wrong>`.
2. Print: `Recovery: <what the user can do>`.
3. Append an audit log entry with `"result":"failed"` and `"error":"<reason>"`.
4. Do not retry automatically.

## 12. Refusing to act

If a request would violate `policies/privacy.md` or `policies/safety.md`:

1. Refuse explicitly: `Refused: <which policy and why>`.
2. Suggest an alternative if there is one.
3. Do not log a failed operation (audit log records executions, not refusals).

## 13. Config overlay pattern

Config files under `$CONFIG_HOME` follow a two-layer pattern:

- **Skill-managed files** (`providers.json`, `models-config.json`) are overwritten on each `install.sh` run. They ship with the skill and contain baseline defaults.
- **User overlay files** (`*.local.json`, e.g. `providers.local.json`, `models-config.local.json`) are NEVER overwritten by `install.sh`. The user adds custom providers, role defaults, or model aliases here.

When reading config, merge the base file with the `.local.json` overlay if it exists. The overlay's keys override or extend the base. If a key exists in both, the overlay wins.

Overlay files are empty stubs by default:

```json
{
  "version": 1,
  "_comment": "User overlay -- never overwritten by install.sh",
  "providers": {}
}
```

Operations that modify config (e.g. `hire` adding a custom provider) should prefer writing to the `.local.json` overlay to preserve changes across updates.

## 14. Adapter re-sync

Adapter shims (per section 3) are generated once at hire time and stay stale if the canonical agent definition changes. To regenerate all adapter shims from canonical:

- Run `./install.sh --fix-adapters` from the skill source directory.
- This scans `$AGENTS_GLOBAL` and per-project `$TEAM_AGENTS` directories and regenerates adapter shims in all detected harness locations.
- Migration scripts may also invoke adapter regeneration when they modify agent frontmatter schema.

The `lint` operation (section 2 of `lint.md`) should flag stale adapters where the adapter's `model` or `description` does not match the canonical agent's current frontmatter. Use `--fix-adapters` to resolve these findings.

## 15. Version and migration

The skill ships a `VERSION` file containing the current semver (e.g. `0.4.0`). `install.sh` reads this and compares against the installed version:

- **Same version**: prompts to confirm re-install (or skips with `--force`).
- **Upgrade**: shows CHANGELOG entries between versions, runs pending migrations, then installs.
- **Downgrade**: warns and requires confirmation before proceeding.

Migrations are shell scripts in `migrations/NNN-<name>.sh`, run in sort order on version change. See `migrations/README.md` for the migration contract.

## 16. Tools configuration

Agent tool access is configured in `$TOOLS_CONFIG` (`~/.software-house/config/tools-config.json`). The config has three sections:

1. **`canonical_tools`** -- Maps harness-agnostic tool names to harness-specific names. Each key is a canonical name (e.g., `read`, `agent`, `web-search`). Each value maps to `claude-code`, `codex`, and `gemini` tool names. A `null` value means that harness does not support the tool.

2. **`shared_tools`** -- An array of canonical tool names that EVERY agent receives, regardless of role. Currently: `["read", "write", "edit", "bash", "glob", "grep"]`.

3. **`role_tools`** -- Per-role additional tools. Each key matches a `defaults_by_role` key from `$MODELS_CONFIG`. The value is an array of canonical tool names beyond the shared set. Roles with `agent` access can spawn sub-agents (used by `plan execute`).

### Tool resolution at hire time

When an agent is hired, its `tools` frontmatter field is populated by combining `shared_tools` + `role_tools[role]` from `$TOOLS_CONFIG`. For example, a `researcher` agent gets:

```
tools: [read, write, edit, bash, glob, grep, web-search, web-fetch]
```

A `tech-lead` agent gets:

```
tools: [read, write, edit, bash, glob, grep, agent]
```

### Harness adapter translation

When writing adapter files, canonical tool names are translated to harness-specific names using the `canonical_tools` mapping. For example, `agent` maps to `Agent` in Claude Code but is `null` (unsupported) in Codex and Gemini -- agents with `agent` in their tools can only spawn sub-agents on Claude Code.

### Config overlay

As with `$MODELS_CONFIG`, the `tools-config.json` has a `.local.json` overlay at `$TOOLS_LOCAL` (`~/.software-house/config/tools-config.local.json`). User customizations (additional tools, role overrides) go here and are never overwritten by `install.sh`.

### Path constants

| Symbol | Path |
|---|---|
| `$TOOLS_CONFIG` | `~/.software-house/config/tools-config.json` |
| `$TOOLS_LOCAL` | `~/.software-house/config/tools-config.local.json` (user overlay, never overwritten) |
| `$ROLE_TEMPLATES` | `~/.software-house/config/role-templates.json` |
| `$WIKI_CONCEPTS` | `~/.software-house/company/wiki/concepts` |
| `$WIKI_DECISIONS` | `~/.software-house/company/wiki/decisions` |
| `$WIKI_SYNTHESIS` | `~/.software-house/company/wiki/synthesis` |
| `$WIKI_HANDOFFS` | `~/.software-house/company/wiki/handoffs` |
| `$WIKI_HANDOFF_INBOX` | `~/.software-house/company/wiki/handoffs/inbox` |
| `$WIKI_HANDOFF_COMPLETED` | `~/.software-house/company/wiki/handoffs/completed` |
| `$WIKI_HANDOFF_BRIEFS` | `~/.software-house/company/wiki/handoffs/briefs` |
| `$WIKI_LOG` | `~/.software-house/company/wiki/log.md` |
| `$RAW_DIR` | `~/.software-house/company/raw` |

## 17. Sprint and Backlog data structures

### Sprint directory

Each sprint lives under `$TEAM_SPRINTS/<sprint-id>/` (e.g., `sprint-001/`):

| File | Purpose |
|---|---|
| `sprint.md` | Sprint frontmatter (id, name, goal, start_date, end_date, status, plan_id) + body with goal and board summary |
| `board.md` | Current sprint board state -- markdown table with columns: Todo, In Progress, Review, Done |
| `standups.md` | Chronological standup notes (append-only) |
| `review.md` | Sprint review / demo notes |
| `retro.md` | Retrospective notes |

Sprint IDs are auto-incremented: `sprint-001`, `sprint-002`, etc. The `next_sprint_id()` helper scans `$TEAM_SPRINTS/` for the highest existing ID and increments.

### Backlog file

The product backlog lives at `$TEAM_BACKLOG` (`$TEAM_DIR/backlog.md`). It uses YAML frontmatter with a `next_id` counter and a markdown table body:

```yaml
---
type: product-backlog
team: <team-name>
created_at: YYYY-MM-DD
next_id: 1
---

# Product Backlog

| ID | Title | Type | Priority | Points | Assignee | Status | Sprint |
|---|---|---|---|---|---|---|---|
```

Each backlog item has an `item-NNN` ID (auto-incremented from `next_id`). The `Sprint` column is empty when the item is in the backlog, or `sprint-NNN` when pulled into a sprint.

### Board columns

Sprint board items move through four columns:

| Column | Meaning |
|---|---|
| `todo` | Item is in the sprint but not yet started |
| `in-progress` | Item is being actively worked on |
| `review` | Item is under review (code review, QA) |
| `done` | Item is completed |

### Sprint lifecycle

| Status | Meaning |
|---|---|
| `planning` | Sprint created but not yet started |
| `active` | Sprint is in progress |
| `review` | Sprint review phase |
| `closed` | Sprint is complete |

## 18. Plan data structures

### Plan directory

Each plan lives under `$TEAM_PLANS/<plan-id>/` (e.g., `plan-001/`):

| File | Purpose |
|---|---|
| `plan.md` | Plan frontmatter (type, id, name, status, created_by, tasks array, sprint_id) + body with goal and task table |
| `status.md` | Execution status tracking -- which tasks are pending/running/done/failed |
| `results/` | Directory containing `<task-id>.md` output files from each sub-agent |
| `synthesis.md` | Tech-lead's synthesis of all completed task results |

Plan IDs are auto-incremented: `plan-001`, `plan-002`, etc. Task IDs within a plan are `task-NNN` (local to each plan).

### Plan lifecycle

| Status | Meaning |
|---|---|
| `draft` | Plan created but not yet confirmed |
| `confirmed` | CEO has reviewed and approved the plan |
| `executing` | Sub-agents are being spawned and tasks are running |
| `completed` | All tasks have completed successfully |
| `failed` | One or more tasks failed, blocking dependent tasks |

### Task status

| Status | Meaning |
|---|---|
| `pending` | Task not yet started |
| `running` | Sub-agent is working on this task |
| `done` | Task completed, result file exists |
| `failed` | Task failed, result file contains error details |

### Sub-agent spawning protocol (plan execute)

When `plan execute` spawns sub-agents:

1. The skill reads each task's `assignee` and `role` from the plan.
2. It looks up the agent's canonical file to find its `tools` frontmatter field.
3. The `tools` list is resolved from `shared_tools + role_tools[role]` via `$TOOLS_CONFIG`.
4. The sub-agent is spawned with a prompt containing: task description, output file path, tools constraint.
5. On Claude Code: uses the `Agent` tool. On Codex/Gemini: prints manual dispatch instructions.

The sub-agent writes its results to `<plan-dir>/results/<task-id>.md` with a completion marker `--- completed: true ---` at the end.

### Linking plans to sprints

A plan can be linked to a sprint via the `--sprint` flag on `plan create`. This sets `plan_id` in the sprint frontmatter and `sprint_id` in the plan frontmatter. When `sprint plan --from-plan <plan-id>` is used, the sprint board is auto-populated from the plan's task list.

## 19. Wiki-LLM conventions (Karpathy pattern)

The company wiki follows the "compile, don't re-derive" pattern (Karpathy, April 2026). Wiki pages are **compiled knowledge** -- LLM-generated structured pages derived from raw sources, not raw notes.

### Directory structure

```
~/.software-house/company/wiki/
  people/          # Agent wiki pages (per person)
  teams/           # Team wiki pages
  departments/     # Department wiki pages
  synthesis/       # Cross-cutting synthesis pages (project status, etc.)
  concepts/        # Concept pages (architectural concepts, patterns)
  decisions/       # Architecture Decision Records (ADRs)
  handoffs/
    inbox/         # Tasks waiting to be picked up by agents
    completed/     # Completed handoffs (moved after processing)
    briefs/        # Handoff briefs generated by agents
```

Per-project:
```
<project>/.software-house/team/wiki/
  roster.md        # Team roster
  people/          # Per-person pages (same frontmatter as company wiki)
  decisions/       # Project-level ADRs
  synthesis/       # Project synthesis pages
  handoffs/
    inbox/
    completed/
    briefs/
```

### Wikilink conventions

All wiki pages should use `[[page-name]]` wikilinks for cross-references. This makes the wiki compatible with Obsidian's graph view and backlink system:

- Person pages link to team pages: `Currently on [[development-team]]`
- Team pages link to members: `Members: [[tony]], [[alice]], ...`
- Decision pages link to people and concepts: `Proposed by [[tony]], affects [[api-design]]`
- Synthesis pages link to decisions: `See [[adr-001-provider-fallback]]`

When rebuilding `index.md`, include wikilinks in the entry descriptions.

### Confidence and lifecycle

Every wiki page (including person pages) has these frontmatter fields:

| Field | Type | Values | Purpose |
|---|---|---|---|
| `confidence` | float | 0.0-1.0 | How confident we are in this page's content. New pages start at 1.0, pages compiled from sources start at 0.7 |
| `lifecycle` | enum | draft, reviewed, verified, stale, archived | Knowledge maturity. `draft` = LLM-compiled but unreviewed; `reviewed` = CEO reviewed; `verified` = cross-validated; `stale` = older than 30 days; `archived` = superseded |
| `last_compiled` | date | YYYY-MM-DD or null | When the LLM last compiled/updated this page |
| `source_refs` | array | paths to raw/ docs | Which source documents this page was derived from |

### Raw sources

The `$RAW_DIR` (`~/.software-house/company/raw/`) stores immutable source documents. When a source is ingested via `wiki-ingest`, the original is copied here with a timestamp prefix. Source files are never modified -- they serve as the audit trail for compiled wiki pages.

### Handoff brief format

Each handoff brief in `$WIKI_HANDOFF_BRIEFS/` is a markdown file with frontmatter:

```yaml
---
from: <agent-name>
to: <agent-name>
task: <original task description>
priority: high | medium | low
context_pages: [wiki/pages/to/read]
created_at: <utc-timestamp>
status: pending | in-progress | done
---
```

Body contains: summary of what's being handed off, specific deliverable expected, relevant context excerpted from wiki, and dependencies on other handoffs.

### Wiki log

`$WIKI_LOG` (`~/.software-house/company/wiki/log.md`) is an append-only markdown log of wiki operations:

```markdown
- 2026-05-06T10:30:00Z | wiki-ingest | raw/meeting-notes-2026-05-06.md -> concepts/auth-pattern.md, decisions/adr-003.md
- 2026-05-06T11:00:00Z | wiki-lint | 3 broken wikilinks found, 2 orphan pages flagged
```

Each entry has: timestamp, operation, and a human-readable summary of what changed.

## 20. Role templates and delegation

### Role templates

`$ROLE_TEMPLATES` (`~/.software-house/config/role-templates.json`) contains structured role definitions with:

- `title`: Human-readable position title
- `summary`: One-line role description
- `responsibilities`: List of duty descriptions
- `deliverables`: List of expected output types
- `collaborates_with`: List of role keys this role regularly works with
- `escalates_to`: List of roles/identifiers this role escalates blockers to
- `handoff_triggers`: Map of event types to arrays of role keys that should receive a brief

When an agent is hired, the role template is loaded and its fields are written into the agent's canonical file and wiki page. The `hire` operation presents the template for CEO confirmation or customization.

### Provider fallback

When a local provider (Ollama, LM Studio, vLLM) is unavailable, the system falls back to Claude models based on role complexity. The fallback mapping is defined in `models-config.json` under `fallback_external`:

| Role complexity | Default local | Fallback Claude | Fallback effort |
|---|---|---|---|
| High (tech-lead, system-architect) | deepseek-v3:671b | claude-opus-4-7 | xhigh |
| Medium (backend-dev, frontend-dev, code-reviewer, researcher, business-analyst) | qwen3-coder:32b | claude-sonnet-4-6 | high |
| Low (linter, test-runner, doc-writer) | qwen3-coder:7b/14b | claude-haiku-4-5 | high |

Fallback to an external provider requires egress consent per `policies/safety.md` section 1 (special tier). The audit log records the fallback event with both the failed provider and the fallback model.
