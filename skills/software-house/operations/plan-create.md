# Operation: plan-create -- create a plan with tasks and dependencies

**Risk tier:** 2 (additive -- creates new files only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Create a new plan directory with a plan.md containing YAML frontmatter, an empty status.md, and an empty results/ directory. The tech-lead agent (or user) generates the plan structure, then fills in tasks interactively or from stdin/file. A plan is a unit of work composed of tasks with optional dependencies between them, enabling ordered or parallel execution by `plan-execute`.

## Invocation patterns

| Command | Behavior |
|---|---|
| `plan create --name "<text>"` | Create a new plan in the current project team |
| `plan create --name "<text>" --sprint <sprint-id>` | Create a plan and link it to an existing sprint |
| `plan create --name "<text>" --from-file <path>` | Create a plan and populate tasks from a markdown file |
| `plan create --name "<text>" --from-stdin` | Read task definitions from stdin |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--name` | yes | Non-empty string, max 200 characters |
| `--sprint` | no | Must match `^[a-z][a-z0-9-]{0,63}$` and reference an existing sprint directory |
| `--from-file` | no | Must be a readable file path; content parsed as task definitions |
| `--from-stdin` | no | Flag; read task definitions from stdin until EOF |

## Preconditions

1. `$TEAM_DIR` exists (project is initialized with a team). If not, refuse: `Error: project not initialized. Run /software-house init first.`
2. `$TEAM_PLANS` directory must be creatable. If `$TEAM_DIR` exists but `$TEAM_PLANS` does not, create it (`mkdir -p $TEAM_PLANS`).
3. If `--sprint` is given, `$TEAM_DIR/sprints/<sprint-id>/` must exist. If not, refuse: `Error: sprint <sprint-id> not found. Create it first.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--name` is non-empty and does not exceed 200 characters. Abort on failure: `Error: --name must be a non-empty string, max 200 characters.`

If `--sprint` is given, validate it matches `^[a-z][a-z0-9-]{0,63}$` and check that `$TEAM_DIR/sprints/<sprint-id>/` exists. Abort if not found: `Error: sprint <sprint-id> not found.`

If `--from-file` is given, verify the file exists and is readable. Abort if not: `Error: file <path> not found or not readable.`

### 2. Determine plan ID

Scan `$TEAM_PLANS/` for existing plan directories matching the pattern `plan-NNN`. Determine the next available plan ID by finding the highest NNN and incrementing by 1.

If `$TEAM_PLANS/` does not exist or is empty, the first plan ID is `plan-001`.

Zero-pad the number to 3 digits (e.g., `plan-001`, `plan-012`, `plan-123`).

### 3. Determine scope

Resolve scope from `$PROJECTS_INDEX` or `--team` flag per `_shared.md section 4`:

- If a project is detected: `scope` is `team:<team-name>`.
- If no project is detected and `--team` is given: resolve that team.
- If neither: refuse: `Error: no project context detected. Run this command from a project directory or use --team.`

### 4. Build task list

If `--from-file` or `--from-stdin` is given, parse the input for task definitions. Each task definition is a markdown section with:

```
## Task: <title>
Assignee: <agent-name | null>
Role: <role-key>
Dependencies: <comma-separated task-ids or "none">
```

Parse each section. Assign task IDs as `task-001`, `task-002`, etc. (zero-padded to 3 digits within the plan). Validate:
- Each `Assignee` that is not `null` must match an existing agent in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/`. If not found, abort: `Error: assignee <name> not found in team agents or global pool.`
- Each `Role` must match a key in `defaults_by_role` in `$MODELS_CONFIG`. If not found, abort: `Error: role <role> not found in models-config defaults_by_role.`
- Each dependency must reference a task ID that exists within this plan. If not found, abort: `Error: dependency <task-id> not found in task list.`

If neither `--from-file` nor `--from-stdin` is given, create an empty task list. The user populates tasks interactively after creation or edits plan.md directly.

### 5. Tier-2 confirmation

Print the file list that will be created:

```
I will create the following for plan '<plan-id>':
  Plan dir:    $TEAM_PLANS/<plan-id>/
  Plan file:   $TEAM_PLANS/<plan-id>/plan.md
  Status file: $TEAM_PLANS/<plan-id>/status.md
  Results dir: $TEAM_PLANS/<plan-id>/results/
  Audit log:   $AUDIT_LOG
```

If `--sprint` is given, also print: `  Sprint link:  $TEAM_DIR/sprints/<sprint-id>/` (the plan_id will be written to the sprint frontmatter).

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 6. Create plan directory structure

Create the plan directory and subdirectories:

```
mkdir -p $TEAM_PLANS/<plan-id>/results
```

### 7. Write plan.md

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Write `$TEAM_PLANS/<plan-id>/plan.md` with YAML frontmatter:

```yaml
---
type: plan
id: <plan-id>
name: <name-text>
status: draft
sprint: <sprint-id | null>
created_at: <utc-date YYYY-MM-DD>
created_by: <user | agent-name>
updated_at: <utc-date YYYY-MM-DD>
tasks:
  - id: task-001
    title: "<task-title>"
    assignee: <agent-name | null>
    role: <role-key>
    dependencies: []
    status: pending
  - id: task-002
    title: "<task-title>"
    assignee: <agent-name | null>
    role: <role-key>
    dependencies: [task-001]
    status: pending
---
```

If no tasks were provided (empty task list), write `tasks: []` in the frontmatter.

The body of plan.md contains the task breakdown in markdown for human readability:

```markdown
# <plan-id>: <name-text>

## Overview

<name-text>

## Tasks

(No tasks defined yet. Edit this file or use --from-file to add tasks.)
```

If tasks were provided, render each task as a section:

```markdown
## Tasks

### task-001: <title>

- Assignee: <agent-name | unassigned>
- Role: <role-key>
- Dependencies: none | task-001, task-002
- Status: pending
```

### 8. Write status.md

Write `$TEAM_PLANS/<plan-id>/status.md`:

```yaml
---
plan_id: <plan-id>
status: draft
started_at: null
completed_at: null
wave: 0
---
```

Body:

```markdown
# Status: <plan-id>

No tasks running yet.
```

### 9. Link to sprint (if --sprint given)

If `--sprint` is given, read `$TEAM_DIR/sprints/<sprint-id>/sprint.md` and update its frontmatter to add or set `plan_id: <plan-id>`. Use atomic write per `_shared.md section 6`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"plan-create","scope":"team:<team-name>","args":{"name":"<name-text>","plan_id":"<plan-id>","sprint":"<sprint-id|null>","task_count":<count>,"source":"<cli|file|stdin>"},"diff":{"created":["$TEAM_PLANS/<plan-id>/plan.md","$TEAM_PLANS/<plan-id>/status.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 11. Report to user

```
Created plan <plan-id>: <name-text>
  Plan dir:    $TEAM_PLANS/<plan-id>/
  Plan file:   $TEAM_PLANS/<plan-id>/plan.md
  Status:      draft
  Tasks:       <count>
  Sprint:      <sprint-id | none>

Next steps:
  /software-house plan confirm --plan <plan-id>    review and confirm the plan
  /software-house plan status --plan <plan-id>     check plan status
```

If tasks list is empty, add:

```
  (No tasks yet. Edit $TEAM_PLANS/<plan-id>/plan.md to add tasks, then confirm.)
```

## Failure modes

- No project context detected -> refuse, no log.
- `--name` empty or too long -> abort, no log.
- `--sprint` references non-existent sprint -> abort, no log.
- `--from-file` path not found or not readable -> abort, no log.
- Assignee in task list not found in agents -> abort, no log.
- Role in task list not in `$MODELS_CONFIG` -> abort, no log.
- Dependency references a task ID not in the list -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- `mkdir` fails (permissions) -> report path, abort, no log.
- Partial write (atomic write failure) -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Create a plan with a name (empty tasks, filled in later)
/software-house plan create --name "Implement authentication module"

# Create a plan linked to a sprint
/software-house plan create --name "Sprint 3 deliverables" --sprint sprint-003

# Create a plan from a task definition file
/software-house plan create --name "API v2 migration" --from-file ./migration-tasks.md

# Create a plan from stdin
cat tasks.md | /software-house plan create --name "Bug fixes batch 1" --from-stdin
```