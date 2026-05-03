# Operation: second -- matrix-assign agent to a second team

**Risk tier:** 3 (modifying -- updates agent frontmatter, adds to secondary team roster, writes adapters)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Add a secondary team assignment to an agent (matrix management). The agent keeps their primary team and gains an additional team assignment. For permanent employees, a `secondary_teams` list is added or appended to in the canonical frontmatter. For freelance employees, the team is appended to `hired_by_teams`. Adapters are written in the secondary team's project directory for all detected harnesses. The agent is added to the secondary team's roster with a `(seconded)` marker.

## Invocation patterns

| Command | Behavior |
|---|---|
| `second <name> --to <team>` | Matrix-assign agent to secondary team |
| `second <name> --to <team> --team <primary>` | Override primary team resolution |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--to <team>` | yes | Must match `^[a-z][a-z0-9-]{0,63}$`; must exist in `$WIKI_TEAMS` |
| `--team <primary>` | no | Override primary team resolution |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active` or `status: onboarding`. Refuse for `status: alumni` or `status: transfer`: `Error: <name> has status <status>. Second-team assignment requires active or onboarding status.`
4. The destination team `<team>` (from `--to`) must exist in `$WIKI_TEAMS`. If not, refuse: `Error: team <team> not found.`
5. The agent must not already be seconded to the same team. If already assigned, refuse: `Error: <name> is already assigned to team <team> (primary or secondary). No action needed.`

## Step-by-step protocol

### 1. Resolve agent and teams

Read the canonical agent file. Parse frontmatter. Extract: `team`, `role`, `provider`, `model`, `effort_preset`, `department`, `status`, `employment`, `hired_by_teams`, `secondary_teams`.

Resolve the primary team:
- If `--team <primary>` is given, use it.
- Otherwise, use the `team` field from the agent frontmatter.
- If `team` is `null` and `--team` is not given, refuse: `Error: <name> has no primary team. Assign to a primary team first via /software-house hire or /software-house transfer.`

Read `$WIKI_TEAMS/<team>.md` (destination). Parse frontmatter. Extract `project_path`, `members`.

Determine the destination project root from `$PROJECTS_INDEX` using the destination team name or from the `project_path` field in the team's wiki page.

### 2. Check for duplicate assignment

Determine if the agent is already assigned to the destination team:

- If the agent's `team` (primary) equals the destination team name, refuse per Precondition 5.
- If the agent's `secondary_teams` list (permanent employee) contains the destination team name, refuse per Precondition 5.
- If the agent's `hired_by_teams` list (freelance employee) contains the destination team name, refuse per Precondition 5.

### 3. Compute diff

Build the modification plan:

```
File: <canonical agent file> (frontmatter)
  <If permanent employee:>
    field secondary_teams: <current list | "absent"> -> [<existing..., <team>]
  <If freelance employee:>
    field hired_by_teams: [<existing..., <team>]

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  <If permanent employee:>
    field secondary_teams: <current list | "absent"> -> [<existing..., <team>]
  <If freelance employee:>
    field hired_by_teams: [<existing..., <team>]

File: $WIKI_TEAMS/<team>.md (frontmatter)
  members list: add <name> (seconded)

Adapters to WRITE (secondary team project):
  <list each adapter path, one per line, or "(none detected)">
```

Also update `$AUDIT_LOG` (append) and `$COMPANY_INDEX` (rebuild).

### 4. Tier-3 confirmation

Print the full diff from Step 3. Print the paths that will be modified. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 5. Update canonical agent file

Using atomic write per `_shared.md §6`:

For permanent employees:
- Add or append to `secondary_teams` field: `<team>`
- Update `updated_at: <utc-date YYYY-MM-DD>`

For freelance employees:
- Append `<team>` to `hired_by_teams` list
- Update `updated_at: <utc-date YYYY-MM-DD>`

### 6. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the same frontmatter fields as Step 5 (mirroring canonical agent file). Use atomic write per `_shared.md §6`.

### 7. Add agent to secondary team roster

Read `$WIKI_TEAMS/<team>.md`. Append `<name> (seconded)` to the `members` list in the frontmatter. Update `updated_at: <utc-date>` field. Write atomically per `_shared.md §6`.

### 8. Write adapters in secondary team project

Detect installed harnesses under the destination project root. For each detected harness, write the adapter per `_shared.md §3`:

#### Claude Code adapter

`<dest-project>/.claude/agents/<name>.md`:

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

#### Codex CLI adapter

`<dest-project>/.codex/agents/<name>.md` (create `.codex/agents/` dir if missing):

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>
```

#### Gemini CLI adapter

Create `<dest-project>/.gemini/extensions/<name>/` directory.

Write `<dest-project>/.gemini/extensions/<name>/gemini-extension.json`:

```json
{
  "name": "<name>",
  "version": "1.0",
  "description": "<role> agent (software-house managed)",
  "canonicalPath": "<absolute path to canonical agent file>"
}
```

Write `<dest-project>/.gemini/extensions/<name>/GEMINI.md`:

```markdown
# <name>

Managed by software-house skill.
Canonical definition: <absolute path to canonical agent file>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

### 9. Rebuild indexes

Rebuild `$TEAM_INDEX` for the secondary team's project (if applicable) and `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"second","scope":"agent:<name>","args":{"name":"<name>","team":"<primary-team>","secondary_team":"<team>","employment":"<permanent|freelance>"},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","$WIKI_TEAMS/<team>.md","$COMPANY_INDEX"],"created":["<adapter paths>"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 11. Report to user

```
Matrix-assigned <name> to team <team> (secondary)
  Primary team:   <primary-team>
  Secondary team: <team>
  Canonical:      <canonical agent path>
  Wiki:           $WIKI_PEOPLE/<name>.md
  Adapters:       <list or "none detected">
  Employment:     <permanent | freelance>

Next steps:
  /software-house show <name>           verify the updated agent record
  /software-house onboard <name>        regenerate briefing with new team context
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent status not active/onboarding -> refuse; no log.
- Destination team not found -> refuse before any gate; no log.
- Agent already on destination team (primary or secondary) -> refuse; no log.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.
- Adapter write failure -> log warning but continue; report the path that could not be written.

## Examples

```
# Second alice to the platform team (permanent employee)
/software-house second alice --to platform

# Second bob to the frontend team with explicit primary team
/software-house second bob --to frontend --team backend

# Second a freelance agent to an additional project team
/software-house second dev-contractor --to api-gateway
```