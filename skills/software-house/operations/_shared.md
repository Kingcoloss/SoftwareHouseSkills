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

Per-project (team-scoped), given the current project root `$PROJECT`:

| Symbol | Path |
|---|---|
| `$TEAM_DIR` | `$PROJECT/.software-house/team` |
| `$TEAM_AGENTS` | `$PROJECT/.software-house/agents` (canonical agent definitions) |
| `$TEAM_INDEX` | `$PROJECT/.software-house/team/index.md` |
| `$TEAM_AUDIT` | `$PROJECT/.software-house/team/audit.log` |
| `$TEAM_ROSTER` | `$PROJECT/.software-house/team/wiki/roster.md` |
| `$TEAM_TRANSFERS` | `$PROJECT/.software-house/team/transfers.log` |

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
role: <role-key>                        # matches a key in models-config.json defaults_by_role
position: <human-readable>
reports_to: <name | null>
status: active                          # onboarding | active | transfer | alumni | freelance
hired_at: 2026-05-02
level: 1
xp: 0
effort_preset: medium                   # low | medium | high
classification: internal                # public | internal | confidential | restricted
buddy: <name | null>
employment: permanent                   # permanent | freelance
hired_by_teams: []                      # for freelance only
secondary_teams: []                     # for matrix assignment (second.md)
achievements: []
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
