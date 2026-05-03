# Operation: off-board -- off-boarding checklist before removal

**Risk tier:** 3 (modifying -- updates agent state, creates handover document)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Prepare an agent for departure by running an off-boarding checklist. This operation generates a handover document summarizing the agent's role, active tasks, direct reports, and knowledge artifacts. It sets the agent's status to `transfer` (signaling that the agent is pending removal) and records an `offboard_status: pending` marker. The handover document is written alongside the canonical agent file. This is a preparatory step before `fire`; it does not remove any files or adapters.

## Invocation patterns

| Command | Behavior |
|---|---|
| `off-board <name>` | Off-board agent from current project team (auto-detected) |
| `off-board <name> --team <team>` | Off-board agent from a specific team |
| `off-board <name> --pool` | Off-board a freelance pool agent |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--team <team>` | no | Override team scope for agent resolution |
| `--pool` | no | Target freelance pool agent at `$AGENTS_GLOBAL/<name>.md` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active` or `status: onboarding`. Refuse for `status: alumni`: `Error: <name> is already archived (status: alumni). No off-boarding needed.`
4. The agent must not already have `offboard_status: pending` or `offboard_status: done`. If so, warn: `Warning: <name> already has offboard_status: <value>. Proceeding will overwrite the existing handover document.` and continue.

## Step-by-step protocol

### 1. Resolve scope and agent file

Determine canonical path:
- `--pool` flag -> `$AGENTS_GLOBAL/<name>.md`
- `--team <t>` override -> locate project root from `$PROJECTS_INDEX` by team name -> `<project>/.software-house/agents/<name>.md`
- Auto-detect from `pwd` via `$PROJECTS_INDEX` -> `$TEAM_AGENTS/<name>.md`

Read the canonical agent file. Parse frontmatter. Extract: `role`, `provider`, `model`, `team`, `department`, `status`, `reports_to`, `hired_by_teams`, `classification`, `employment`.

### 2. Gather agent context

Read the following files (skip any that do not exist -- non-fatal):

For project-scoped agents:
- `$TEAM_INDEX` -- team wiki index
- `$TEAM_ROSTER` -- current team roster
- `$WIKI_PEOPLE/<name>.md` -- wiki people page
- `<canonical-dir>/<name>.onboard.md` -- onboarding briefing (if exists)
- `$TEAM_DIR/okrs/` or `$TEAM_DIR/okrs.md` -- OKR files referencing this agent

For pool-scoped agents:
- `$COMPANY_INDEX` -- company-tier index
- `$WIKI_PEOPLE/<name>.md` -- wiki people page

Search `$WIKI_PEOPLE/` and `$TEAM_AGENTS/` (or `$AGENTS_GLOBAL/`) for agents with `reports_to: <name>` to find direct reports.

### 3. Generate handover document

Synthesize a handover document using the gathered context. The document is written to `<canonical-dir>/<name>.offboard.md` and contains the following sections:

```markdown
# Off-boarding Handover: <name>

Generated: <utc-timestamp>
Agent: <name>
Role: <role>
Team: <team | "Freelance Pool">
Department: <department | "none">
Status: transfer (pending removal)

## Role Summary

<One paragraph summarizing the agent's role, drawn from the role key, team context, and any onboarding briefing.>

## Active Tasks and Projects

<List of projects/teams the agent is associated with, drawn from team membership and hired_by_teams. If none found, write: "(No active project assignments found.)">

## Direct Reports

<List of agents with reports_to: <name>, drawn from wiki/people/ search. For each, show name, role, and suggested reassignment recommendation:
- <report-name> (<role>) -- recommend reassigning to <team lead or "the team lead for review">
If no direct reports: "(No direct reports.)">

## Knowledge Artifacts

- Onboarding briefing: <canonical-dir>/<name>.onboard.md <or "(not found)">
- Wiki people page: $WIKI_PEOPLE/<name>.md

## Recommended Actions

1. Reassign direct reports (see list above).
2. Review and transfer any ongoing OKRs owned by <name>.
3. Run /software-house fire <name> to complete removal.
4. After firing, consider /software-house second <replacement> --to <team> if a replacement is needed.
```

Do not hallucinate content. If a source file is missing, say so plainly in the relevant section.

### 4. Compute diff

Build the modification plan:

```
File: <canonical agent file> (frontmatter)
  field status: <current-status> -> transfer
  field offboard_at: <absent> -> <utc-date YYYY-MM-DD>
  field offboard_status: <absent | current-value> -> pending
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>

CREATE: <canonical-dir>/<name>.offboard.md

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  field status: <current-status> -> transfer
  field offboard_at: <absent> -> <utc-date YYYY-MM-DD>
  field offboard_status: <absent | current-value> -> pending
```

Also update `$AUDIT_LOG` (append) and `$COMPANY_INDEX` (rebuild).

### 5. Tier-3 confirmation

Print the full diff from Step 4. Print the handover document path. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Update canonical agent file

Using atomic write per `_shared.md §6`, update the following frontmatter fields:

```yaml
status: transfer
offboard_at: <utc-date YYYY-MM-DD>
offboard_status: pending
updated_at: <utc-date YYYY-MM-DD>
```

### 7. Write handover document

Write `<canonical-dir>/<name>.offboard.md` with the content generated in Step 3. Use Write (new file) or atomic write (if file already exists from a previous off-boarding attempt) per `_shared.md §6`.

### 8. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the following frontmatter fields using atomic write per `_shared.md §6`:

```yaml
status: transfer
offboard_at: <utc-date YYYY-MM-DD>
offboard_status: pending
```

### 9. Rebuild indexes

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"off-board","scope":"agent:<name>","args":{"name":"<name>","team":"<team|null>","pool":<bool>},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","$COMPANY_INDEX"],"created":["<canonical-dir>/<name>.offboard.md"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 11. Report to user

```
Off-boarding checklist prepared for <name>
  Status:        <current-status> -> transfer
  Handover:      <canonical-dir>/<name>.offboard.md
  Canonical:     <canonical agent path>
  Direct reports: <count or "none">

Recommended next steps:
  1. Review the handover document: <canonical-dir>/<name>.offboard.md
  2. Reassign any direct reports listed in the handover.
  3. Run /software-house fire <name> to complete removal.
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent already archived (status: alumni) -> refuse; no log.
- Agent already has offboard_status: pending/done -> warn, then continue (overwrites handover document).
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Off-board alice from the current project team
/software-house off-board alice

# Off-board bob from a specific team
/software-house off-board bob --team api-gateway

# Off-board a freelance pool agent
/software-house off-board dev-contractor --pool
```