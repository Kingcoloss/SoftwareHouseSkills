# Operation: contract -- attach freelance agent to a project team

**Risk tier:** 3 (modifying -- updates agent frontmatter, team roster, and writes adapters)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Contract a freelance/outsource agent to a specific project team. The agent's canonical file must have `employment: freelance` and `status: active` or `status: freelance`. This operation writes harness adapters in the target project's directories (first time the freelance agent gets adapters for this project), adds the agent to the team's roster with a `(contract)` marker, and updates the agent's `hired_by_teams` list and status. If the agent already has adapters for the target project, the operation refuses (suggest `show` to inspect).

## Invocation patterns

| Command | Behavior |
|---|---|
| `contract <name> --team <team>` | Contract freelance agent to a specific team |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--team <team>` | yes | Must match `^[a-z][a-z0-9-]{0,63}$`; must exist in `$WIKI_TEAMS` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist at `$AGENTS_GLOBAL/<name>.md`. If not, refuse: `Error: agent <name> not found in freelance pool. Use /software-house outsource-hire first.`
3. The agent must have `employment: freelance`. Refuse for permanent employees: `Error: <name> is a permanent employee (employment: permanent). Use /software-house transfer instead.`
4. The agent must have `status: active` or `status: freelance`. Refuse for `status: alumni`: `Error: <name> is archived (status: alumni). Cannot contract.`
5. The target team must exist in `$WIKI_TEAMS`. If not, refuse: `Error: team <team> not found. Run /software-house list teams to see available teams.`
6. The agent must not already be contracted to the same team. If `hired_by_teams` already contains `<team>`, refuse: `Error: <name> is already contracted to team <team>.`

## Step-by-step protocol

### 1. Validate inputs

Read the canonical agent file at `$AGENTS_GLOBAL/<name>.md`. Parse frontmatter. Extract: `role`, `provider`, `model`, `effort_preset`, `employment`, `status`, `hired_by_teams`, `team`, `classification`.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

Validate `--team <team>` exists in `$WIKI_TEAMS/<team>.md`. Abort if not found.

Check preconditions 3, 4, and 6. Abort if any fail.

### 2. Resolve target project

Read `$WIKI_TEAMS/<team>.md`. Parse frontmatter. Extract `project_path`, `department`, `lead`, `members`.

Determine the target project root from `$PROJECTS_INDEX` using the team name or from the `project_path` field in the team's wiki page.

If no project root can be resolved, refuse: `Error: team <team> has no associated project path. Use /software-house init to set up the project, or check $PROJECTS_INDEX.`

### 3. Compute diff

Build the modification plan:

```
File: $AGENTS_GLOBAL/<name>.md (frontmatter)
  field hired_by_teams: [<existing...>] -> [<existing..., <team>]
  field status: <current-status> -> active
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  field hired_by_teams: [<existing...>] -> [<existing..., <team>]
  field status: <current-status> -> active
  <If wiki page does not exist for this team context:>
  CREATE: $WIKI_PEOPLE/<name>.md

File: $WIKI_TEAMS/<team>.md (frontmatter)
  members list: add <name> (contract)

Adapters to WRITE (target project):
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

Using atomic write per `_shared.md §6`, update the following frontmatter fields:

```yaml
hired_by_teams: [<existing..., <team>]
status: active
updated_at: <utc-date YYYY-MM-DD>
```

If the agent's `status` was `freelance`, update it to `active`.

### 6. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the same frontmatter fields as Step 5 (mirroring canonical agent file). Use atomic write per `_shared.md §6`.

If `$WIKI_PEOPLE/<name>.md` does not exist, create it with the same frontmatter as the canonical agent file plus a body section:

```markdown
---
<same frontmatter as canonical agent file>
---

# <name>

## Contracted to: <team>

Contract agent assigned from the freelance pool.

## Onboarding

Briefing not yet written. Run `/software-house onboard <name>` to generate.

## Notes

(empty)
```

### 7. Add agent to team roster with contract marker

Read `$WIKI_TEAMS/<team>.md`. Append `<name> (contract)` to the `members` list in the frontmatter. Update `updated_at: <utc-date>` field. Write atomically per `_shared.md §6`.

### 8. Write adapters in target project

Detect installed harnesses under the target project root. For each detected harness, write the adapter per `_shared.md §3`:

#### Claude Code adapter

`<target-project>/.claude/agents/<name>.md`:

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to $AGENTS_GLOBAL/<name>.md>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

#### Codex CLI adapter

`<target-project>/.codex/agents/<name>.md` (create `.codex/agents/` dir if missing):

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to $AGENTS_GLOBAL/<name>.md>
```

#### Gemini CLI adapter

Create `<target-project>/.gemini/extensions/<name>/` directory.

Write `<target-project>/.gemini/extensions/<name>/gemini-extension.json`:

```json
{
  "name": "<name>",
  "version": "1.0",
  "description": "<role> agent (software-house managed)",
  "canonicalPath": "<absolute path to $AGENTS_GLOBAL/<name>.md>"
}
```

Write `<target-project>/.gemini/extensions/<name>/GEMINI.md`:

```markdown
# <name>

Managed by software-house skill.
Canonical definition: <absolute path to $AGENTS_GLOBAL/<name>.md>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

### 9. Rebuild indexes

Rebuild `$TEAM_INDEX` for the target project and `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"contract","scope":"agent:<name>","args":{"name":"<name>","team":"<team>","contract_to_team":"<team>"},"diff":{"updated":["$AGENTS_GLOBAL/<name>.md","$WIKI_PEOPLE/<name>.md","$WIKI_TEAMS/<team>.md","$COMPANY_INDEX"],"created":["<adapter paths>"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 11. Report to user

```
Contracted <name> to team <team>
  Canonical:    $AGENTS_GLOBAL/<name>.md
  Wiki:         $WIKI_PEOPLE/<name>.md
  Team roster:  <team> (contract)
  Adapters:     <list or "none detected">
  Status:       active (contract)

Next steps:
  /software-house onboard <name>       write personalized briefing for team context
  /software-house show <name>           inspect the agent record
```

## Failure modes

- Agent not found in freelance pool -> refuse; no log.
- Agent is permanent employee -> refuse; suggest `transfer` instead; no log.
- Agent status is alumni -> refuse; no log.
- Target team not found -> refuse; no log.
- Agent already contracted to same team -> refuse; no log.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.
- Adapter write failure -> log warning but continue; report the path that could not be written.

## Examples

```
# Contract a freelance backend developer to the api-gateway team
/software-house contract dev-contractor --team api-gateway

# Contract a freelance QA tester to the platform team
/software-house contract qa-outsourced --team platform
```