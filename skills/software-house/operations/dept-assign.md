# Operation: dept-assign -- assign an agent to a department

**Risk tier:** 3 (modifying -- changes existing frontmatter in agent file and department index; no data loss)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Assign an existing agent to a department. Updates the `department` field in the agent's canonical frontmatter and appends the agent to the department's `agents/` index file. If the agent is already assigned to a different department, show a Tier-3 diff and ask for confirmation before reassigning (this is a modifying operation, not destructive -- old department's index is also updated). Logs an audit line including from-dept and to-dept.

## Invocation patterns

| Command | Behavior |
|---|---|
| `dept-assign <agent-name> <dept-name>` | Assign agent to department |
| `dept-assign <agent-name> <dept-name> --team <team>` | Explicit team scope for agent resolution |
| `dept-assign <agent-name> <dept-name> --pool` | Assign a freelance pool agent |

The command may also be invoked as `dept assign` (space-separated) per Phase 2 routing.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `agent-name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` |
| `dept-name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` and exist in `$DEPARTMENTS_HOME` |
| `--team` | no | Override team scope for agent resolution |
| `--pool` | no | Resolve agent from freelance pool |

## Preconditions

1. `$COMPANY_HOME` exists.
2. The canonical agent file must exist. If not: `Error: agent <agent-name> not found. Run /software-house hire <agent-name> first.`
3. The target department must exist at `$DEPARTMENTS_HOME/<dept-name>/`. If not: `Error: department <dept-name> not found. Run /software-house dept-create <dept-name> first.`
4. The agent must have `status: active`, `status: onboarding`, or `status: transfer`. Refuse for `status: alumni`.

## Step-by-step protocol

### 1. Resolve agent and department

Resolve canonical agent path (same scope logic as `hire` and `fire`):
- `--pool` -> `$AGENTS_GLOBAL/<agent-name>.md`
- `--team <t>` -> `<project>/.software-house/agents/<agent-name>.md`
- Auto-detect from `pwd` via `$PROJECTS_INDEX`

Read canonical agent frontmatter. Extract `department` (current value, may be `null`).

Read `$WIKI_DEPTS/<dept-name>.md`. Extract current `teams` list and `head` field.

Check `$DEPARTMENTS_HOME/<dept-name>/agents/` directory exists. If not, create it: `mkdir -p $DEPARTMENTS_HOME/<dept-name>/agents/`.

### 2. Detect current assignment

Set `from_dept` to the current `department` value from agent frontmatter (may be `null`).

If `from_dept == dept-name` (same department), abort:

```
Error: <agent-name> is already assigned to department <dept-name>. No changes needed.
```

No log entry.

### 3. Compute diff

Build the modification plan:

```
File: <canonical agent file> (frontmatter)
  field department: <from_dept | "null"> -> <dept-name>
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>

File: $DEPARTMENTS_HOME/<dept-name>/agents/index.md
  + <agent-name> | <role> | <provider> | active

<If from_dept is not null:>
File: $DEPARTMENTS_HOME/<from_dept>/agents/index.md
  - <agent-name> | <role> | <provider> | active

File: $WIKI_PEOPLE/<agent-name>.md (frontmatter)
  field department: <from_dept | "null"> -> <dept-name>
```

Also update `$AUDIT_LOG` (append) and `$COMPANY_INDEX` (rebuild).

### 4. Tier-3 confirmation

If `from_dept` is not `null` (agent is moving between departments), print:

```
Note: <agent-name> is currently in department <from_dept>.
      This will reassign them to <dept-name>.
```

Print the full diff from Step 3. Print the paths that will be modified. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

Note: the Tier-3 affirmative protocol (reply `yes`, `y`, `proceed`, `ok`, or `Yes, proceed`) is used here, NOT the Tier-4 typed CONFIRM. Reassigning a department is a modifying operation, not destructive; no data is lost.

### 5. Update canonical agent file

Using atomic write per `_shared.md §6`:
- Update `department: <dept-name>` in frontmatter.
- Update `updated_at: <utc-date YYYY-MM-DD>` (add field if missing).

### 6. Update wiki people page

If `$WIKI_PEOPLE/<agent-name>.md` exists, update `department: <dept-name>` there as well using atomic write.

### 7. Update destination department agents index

Read `$DEPARTMENTS_HOME/<dept-name>/agents/index.md`. If the file does not exist, create it with a skeleton header:

```markdown
# Agents -- <dept-name>

| Name | Role | Provider | Status | Assigned At |
|---|---|---|---|---|
```

Append a row:

```
| <agent-name> | <role> | <provider> [<class>] | active | <utc-date> |
```

Use atomic write if file exists.

### 8. Update source department agents index (if from_dept is not null)

Read `$DEPARTMENTS_HOME/<from_dept>/agents/index.md`. Remove the row for `<agent-name>`. Use atomic write.

### 9. Rebuild indexes

Rebuild `$TEAM_INDEX` (if project-scoped) and `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"dept-assign","scope":"agent:<agent-name>","args":{"agent":"<agent-name>","dept":"<dept-name>","from_dept":"<from_dept|null>","pool":<bool>},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<agent-name>.md","$DEPARTMENTS_HOME/<dept-name>/agents/index.md","<$DEPARTMENTS_HOME/<from_dept>/agents/index.md if applicable>","$COMPANY_INDEX"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

`from_dept` is the value before the update (`null` if agent had no department).

### 11. Report to user

```
Assigned <agent-name> to department <dept-name>
  Agent:      <canonical agent path>
  Department: $DEPARTMENTS_HOME/<dept-name>/
  From dept:  <from_dept | "(none)">
  Updated:    <canonical agent file>, <wiki people page if applicable>
              $DEPARTMENTS_HOME/<dept-name>/agents/index.md

Next steps:
  /software-house show <agent-name>       verify the updated agent record
  /software-house show dept <dept-name>   see the department roster
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Department not found -> refuse before any gate; no log.
- Agent already in same department -> refuse with informational message; no log.
- Agent status is alumni -> refuse; no log.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.
- Source department index does not exist (from_dept set but index file missing) -> warn in output but continue; note in audit entry `"error": "from_dept index missing"` alongside `"result": "ok"`.

## Examples

```
# Assign alice to the engineering department
/software-house dept-assign alice engineering

# Assign bob (in another department) to the platform department
/software-house dept-assign bob platform

# Assign a freelance pool agent to a department
/software-house dept-assign ci-linter infra --pool
```
