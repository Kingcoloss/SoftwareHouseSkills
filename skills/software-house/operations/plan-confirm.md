# Operation: plan-confirm -- CEO reviews and confirms a draft plan

**Risk tier:** 3 (modifying -- updates plan.md status from draft to confirmed)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

The CEO reviews a draft plan and confirms it, transitioning its status from "draft" to "confirmed". This is the gate that must be passed before `plan-execute` can spawn sub-agents. Confirmation validates that all tasks have valid assignees and that the dependency graph is consistent. Once confirmed, the plan is locked for execution.

## Invocation patterns

| Command | Behavior |
|---|---|
| `plan confirm --plan <plan-id>` | Review and confirm a draft plan |
| `plan confirm --plan <plan-id> --assign <task-id> <agent-name>` | Assign a specific agent to an unassigned task during confirmation |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--plan` | yes | Must match `^plan-\d{3}$` and reference an existing plan directory |
| `--assign` | no | Repeatable; format `<task-id> <agent-name>`; agent must exist in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/` |

## Preconditions

1. `$TEAM_DIR` exists (project is initialized with a team). If not, refuse: `Error: project not initialized. Run /software-house init first.`
2. `$TEAM_PLANS/<plan-id>/plan.md` must exist. If not, refuse: `Error: plan <plan-id> not found.`
3. The plan's `status` frontmatter must be `draft`. If `confirmed`, refuse: `Error: plan <plan-id> is already confirmed. Use /software-house plan execute to run it.` If `completed` or `failed`, refuse: `Error: plan <plan-id> has status <status>. Cannot confirm a plan that has already been executed.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--plan` matches `^plan-\d{3}$`. Abort on mismatch: `Error: invalid plan ID format. Expected plan-NNN (e.g., plan-001).`

Check that `$TEAM_PLANS/<plan-id>/plan.md` exists. Abort if not found.

Read and parse the plan.md frontmatter. Extract: `status`, `name`, `tasks` list.

If `status` is not `draft`, abort with the appropriate message per Precondition 3.

### 2. Resolve assign assignments

If `--assign` flags are given, parse each as `<task-id> <agent-name>`. For each:

- Validate `<task-id>` exists in the plan's task list. Abort if not: `Error: task <task-id> not found in plan <plan-id>.`
- Validate `<agent-name>` exists in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/`. Abort if not: `Error: agent <agent-name> not found.`
- Check the agent's `status` field is `active`. Abort if not: `Error: agent <agent-name> has status <status>. Only active agents can be assigned.`
- Check the agent's `role` matches the task's `role` field. If not, warn: `Warning: agent <name> has role <agent-role> but task <task-id> expects role <task-role>. Proceeding with assignment.` (Warning only, not a blocker.)

Apply all assign updates to the in-memory task list. Each assignment updates the task's `assignee` field from `null` to `<agent-name>`.

### 3. Validate task assignees

After applying `--assign` updates, check all tasks in the plan for unassigned tasks (where `assignee` is `null`). List them:

```
Unassigned tasks:
  task-001: <title> (role: <role>)
  task-003: <title> (role: <role>)

Use --assign <task-id> <agent-name> to assign agents before confirming.
```

Abort if any task remains unassigned: `Error: cannot confirm plan with unassigned tasks. Assign all tasks before confirming.`

### 4. Validate dependency consistency

For each task, validate that its `dependencies` list references only task IDs that exist in the plan. If a dependency references a non-existent task, abort: `Error: task <task-id> depends on <dep-id>, which does not exist in this plan.`

Check for dependency cycles using topological sort (Kahn's algorithm or DFS-based cycle detection). If a cycle is detected, abort: `Error: dependency cycle detected involving tasks: <task-ids in cycle>. Remove cycles before confirming.`

### 5. Build confirmation display

Print the full plan review:

```
Plan: <plan-id> -- <name>
Status: draft -> confirmed

Tasks:
+----------+----------------------------+-----------------+-----------+---------------+
| Task     | Title                      | Assignee        | Role      | Dependencies  |
+----------+----------------------------+-----------------+-----------+---------------+
| task-001 | <title>                    | <assignee>      | <role>    | none          |
| task-002 | <title>                    | <assignee>      | <role>    | task-001      |
| ...      |                            |                 |           |               |
+----------+----------------------------+-----------------+-----------+---------------+

Execution order (topological):
  Wave 1: task-001 (<assignee>, <role>)
  Wave 2: task-002 (<assignee>, <role>)
  ...

Total tasks: <count>
```

If `--sprint` is set in plan frontmatter, also print: `Sprint: <sprint-id>`

### 6. Compute diff

Build the modification plan:

```
File: $TEAM_PLANS/<plan-id>/plan.md (frontmatter)
  field status: draft -> confirmed
  field updated_at: <old-date> -> <utc-date YYYY-MM-DD>

File: $TEAM_PLANS/<plan-id>/status.md (frontmatter)
  field status: draft -> confirmed
  field confirmed_at: null -> <utc-timestamp>
```

For each `--assign` update:

```
File: $TEAM_PLANS/<plan-id>/plan.md (frontmatter, task <task-id>)
  field assignee: null -> <agent-name>
```

Also update `$AUDIT_LOG` (append).

### 7. Tier-3 confirmation

Print the diff from Step 6. Print the paths that will be modified. Then print the Tier-3 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 8. Update plan.md

Using atomic write per `_shared.md section 6`, update the following frontmatter fields in `$TEAM_PLANS/<plan-id>/plan.md`:

```yaml
status: confirmed
updated_at: <utc-date YYYY-MM-DD>
```

For each `--assign` update, also update the corresponding task's `assignee` field from `null` to `<agent-name>`.

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Record `confirmed_at` in the plan frontmatter:

```yaml
confirmed_at: <utc-timestamp>
```

### 9. Update status.md

Using atomic write per `_shared.md section 6`, update `$TEAM_PLANS/<plan-id>/status.md`:

```yaml
---
plan_id: <plan-id>
status: confirmed
started_at: null
completed_at: null
wave: 0
confirmed_at: <utc-timestamp>
---
```

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"plan-confirm","scope":"team:<team-name>","args":{"plan_id":"<plan-id>","name":"<name-text>","task_count":<count>,"assignments":<list of task-id:agent-name pairs>},"diff":{"updated":["$TEAM_PLANS/<plan-id>/plan.md","$TEAM_PLANS/<plan-id>/status.md"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 11. Report to user

```
Confirmed plan <plan-id>: <name-text>
  Status:      draft -> confirmed
  Confirmed at: <utc-timestamp>
  Tasks:       <count>
  Plan file:   $TEAM_PLANS/<plan-id>/plan.md

Next steps:
  /software-house plan execute --plan <plan-id>              start execution
  /software-house plan execute --plan <plan-id> --max-parallel 3  limit parallel tasks
```

## Failure modes

- Plan not found -> abort, no log.
- Plan status not `draft` -> abort with status-specific message, no log.
- Unassigned tasks -> abort, suggest `--assign`, no log.
- Dependency cycle -> abort, list cycle tasks, no log.
- Dependency references non-existent task -> abort, no log.
- Agent not found -> abort, no log.
- Agent status not active -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Confirm a draft plan after review
/software-house plan confirm --plan plan-001

# Confirm and assign agents to unassigned tasks
/software-house plan confirm --plan plan-001 \
  --assign task-001 alice \
  --assign task-002 bob \
  --assign task-003 carol

# Confirm with single assignment
/software-house plan confirm --plan plan-002 --assign task-001 dave
```