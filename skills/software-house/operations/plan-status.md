# Operation: plan-status -- show current execution status of a plan

**Risk tier:** 1 (read-only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Display the current status of a plan including all task statuses, dependency graph visualization, and progress percentage. Reads plan.md and status.md. Never modifies any file.

## Invocation patterns

| Command | Behavior |
|---|---|
| `plan status --plan <plan-id>` | Show full status of a plan |
| `plan status --plan <plan-id> --verbose` | Show status with full task details and result summaries |
| `plan status --plan <plan-id> --json` | Output status as JSON for programmatic consumption |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--plan` | yes | Must match `^plan-\d{3}$` and reference an existing plan directory |
| `--verbose` | no | Flag; include task descriptions and result summaries |
| `--json` | no | Flag; output structured JSON instead of formatted text |

## Preconditions

1. `$TEAM_DIR` exists (project is initialized with a team). If not, refuse: `Error: project not initialized. Run /software-house init first.`
2. `$TEAM_PLANS/<plan-id>/plan.md` must exist. If not, refuse: `Error: plan <plan-id> not found.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--plan` matches `^plan-\d{3}$`. Abort on mismatch: `Error: invalid plan ID format. Expected plan-NNN (e.g., plan-001).`

Check that `$TEAM_PLANS/<plan-id>/plan.md` exists. Abort if not found: `Error: plan <plan-id> not found.`

### 2. Read plan data

Read and parse `$TEAM_PLANS/<plan-id>/plan.md` frontmatter. Extract:
- `id`, `name`, `status`, `sprint`, `created_at`, `updated_at`, `confirmed_at`, `started_at`, `completed_at`
- `tasks` list: each task's `id`, `title`, `assignee`, `role`, `dependencies`, `status`

Read and parse `$TEAM_PLANS/<plan-id>/status.md` frontmatter. Extract:
- `plan_id`, `status`, `started_at`, `completed_at`, `wave`, `confirmed_at`

### 3. Read result files

Scan `$TEAM_PLANS/<plan-id>/results/` for result files matching `task-NNN.md`.

For each result file found:
- Parse frontmatter: `task_id`, `status`, `assignee`, `completed_at`
- Read the body for a summary (first 3 lines or until first blank line)

### 4. Compute progress

Calculate overall progress:

```
total_tasks = count of all tasks in plan
done_tasks = count of tasks with status "done"
failed_tasks = count of tasks with status "failed"
running_tasks = count of tasks with status "running"
pending_tasks = count of tasks with status "pending"
progress_percentage = (done_tasks / total_tasks) * 100, rounded to nearest integer
```

If total_tasks is 0 (empty plan), progress is 0%.

### 5. Compute dependency graph

For each task, build a directed edge list:

```
task-001 -> (no outgoing edges, no dependencies)
task-002 -> depends on task-001
task-003 -> depends on task-001, task-002
```

Determine the wave (execution order) for each task:
- Wave 1: tasks with no dependencies or all dependencies are `done`
- Wave 2: tasks whose dependencies are all in wave 1
- Wave N: tasks whose dependencies are all in waves 1 through N-1

Tasks with `done` dependencies that are not yet assigned a wave get the lowest possible wave number.

### 6. Render output

#### Default (formatted text)

```
+==============================================================+
|  PLAN STATUS: <plan-id>                                       |
|  Name:       <name>                                          |
|  Status:     <draft | confirmed | running | completed | failed>
|  Sprint:     <sprint-id | none>                              |
|  Created:     <created_at>                                   |
|  Confirmed:   <confirmed_at | not yet>                       |
|  Started:     <started_at | not yet>                         |
|  Completed:   <completed_at | not yet>                       |
|  Current wave: <wave-number>                                 |
+==============================================================+

Progress: [====------] <percentage>% (<done>/<total> tasks)

Task Status:
+----------+----------------------------+-----------------+-----------+---------------+-----------+
| Task     | Title                      | Assignee        | Role      | Dependencies  | Status    |
+----------+----------------------------+-----------------+-----------+---------------+-----------+
| task-001 | <title>                    | <assignee>      | <role>    | none          | done      |
| task-002 | <title>                    | <assignee>      | <role>    | task-001      | running   |
| task-003 | <title>                    | <assignee>      | <role>    | task-001      | pending   |
| task-004 | <title>                    | <assignee>      | <role>    | task-002      | pending   |
+----------+----------------------------+-----------------+-----------+---------------+-----------+

Summary:
  Done:     <count>
  Running:  <count>
  Pending:  <count>
  Failed:   <count>

Dependency Graph:
  task-001 -----> task-002
  task-001 -----> task-003
  task-002 -----> task-004
```

#### Verbose mode (--verbose)

In addition to the default output, add:

```
Task Details:
  task-001: <title>
    Assignee: <assignee> (<role>)
    Dependencies: none
    Status: done
    Completed at: <timestamp>
    Result summary: <first 3 lines of result file body>

  task-002: <title>
    Assignee: <assignee> (<role>)
    Dependencies: task-001
    Status: running
    Started at: <timestamp>
    (no result yet)

  ...
```

If a result file has `status: failed`, include the error message:

```
  task-NNN: <title>
    Status: FAILED
    Error: <error message from result file>
```

#### JSON mode (--json)

Output a single JSON object:

```json
{
  "plan_id": "<plan-id>",
  "name": "<name>",
  "status": "<status>",
  "sprint": "<sprint-id | null>",
  "created_at": "<timestamp>",
  "confirmed_at": "<timestamp | null>",
  "started_at": "<timestamp | null>",
  "completed_at": "<timestamp | null>",
  "current_wave": <wave-number>,
  "progress": {
    "total": <count>,
    "done": <count>,
    "running": <count>,
    "pending": <count>,
    "failed": <count>,
    "percentage": <number>
  },
  "tasks": [
    {
      "id": "<task-id>",
      "title": "<title>",
      "assignee": "<name | null>",
      "role": "<role>",
      "dependencies": ["<dep-id>", ...],
      "status": "<status>",
      "wave": <wave-number>,
      "result_file": "<path | null>",
      "completed_at": "<timestamp | null>"
    }
  ],
  "dependency_edges": [
    {"from": "<task-id>", "to": "<task-id>"},
    ...
  ]
}
```

### 7. Report to user

After rendering the output, print a summary line:

```
Plan <plan-id> (<name>): <status> -- <percentage>% complete (<done>/<total> tasks done)
```

If the plan is `completed`, add:

```
All tasks completed. Use /software-house plan synthesize --plan <plan-id> to combine results.
```

If the plan is `failed`, add:

```
Plan execution failed. Check task results in $TEAM_PLANS/<plan-id>/results/ for details.
```

If the plan is `running`, add:

```
Plan is currently executing (wave <wave-number>). Use /software-house plan status --plan <plan-id> to check progress.
```

## Failure modes

- Plan not found -> refuse, no log (Tier 1, no state change).
- `status.md` missing or malformed -> display plan data from `plan.md` only, note: `(status.md not found or unreadable; showing plan data only)`.
- Result files missing for `done` tasks -> display task status from `plan.md` frontmatter, note: `(result file not found for task <task-id>)`.
- Empty task list -> display progress as 0%, note: `(no tasks defined; edit plan.md to add tasks)`.

## Examples

```
# Show plan status
/software-house plan status --plan plan-001

# Show detailed status with result summaries
/software-house plan status --plan plan-001 --verbose

# Output status as JSON for scripting
/software-house plan status --plan plan-001 --json

# Check status of a running plan
/software-house plan status --plan plan-003
```