# Operation: plan-synthesize -- synthesize all completed task results into a unified report

**Risk tier:** 2 (additive -- creates synthesis.md only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

The tech-lead agent (or user) reads all completed task result files from a plan's results/ directory and synthesizes them into a single unified report. This operation is the final step after `plan-execute` completes all tasks. It creates `synthesis.md` in the plan directory, combining all task outputs with analysis, cross-references, and a summary of what was accomplished. The synthesis is additive -- it never modifies existing result files.

## Invocation patterns

| Command | Behavior |
|---|---|
| `plan synthesize --plan <plan-id>` | Synthesize all completed task results into a unified report |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--plan` | yes | Must match `^plan-\d{3}$` and reference an existing plan directory |

## Preconditions

1. `$TEAM_DIR` exists (project is initialized with a team). If not, refuse: `Error: project not initialized. Run /software-house init first.`
2. `$TEAM_PLANS/<plan-id>/plan.md` must exist. If not, refuse: `Error: plan <plan-id> not found.`
3. All tasks in the plan must have `status: done`. If any task has a status other than `done`, refuse: `Error: plan <plan-id> has tasks that are not completed. Current statuses: <list of non-done task statuses>. Use /software-house plan status --plan <plan-id> to check progress.`

Exception: tasks with `status: failed` are allowed if the user explicitly acknowledges them. In this case, the synthesis includes the failure information with a warning.

## Step-by-step protocol

### 1. Validate inputs

Validate `--plan` matches `^plan-\d{3}$`. Abort on mismatch: `Error: invalid plan ID format. Expected plan-NNN (e.g., plan-001).`

Check that `$TEAM_PLANS/<plan-id>/plan.md` exists. Abort if not found: `Error: plan <plan-id> not found.`

### 2. Read plan data

Read and parse `$TEAM_PLANS/<plan-id>/plan.md` frontmatter. Extract:
- `id`, `name`, `status`, `sprint`, `created_at`, `confirmed_at`, `started_at`, `completed_at`
- `tasks` list: each task's `id`, `title`, `assignee`, `role`, `dependencies`, `status`

### 3. Validate task completion

Check every task's `status` field. If any task has a status other than `done`:

- If all non-done tasks have `status: failed`, print a warning and proceed with acknowledgment:

```
Warning: the following tasks failed:
  task-NNN: <title> (status: failed)

The synthesis will include failure information for these tasks.
```

- If any task has `status: pending` or `status: running`, abort: `Error: plan <plan-id> has incomplete tasks. All tasks must be done (or failed) before synthesis. Use /software-house plan status --plan <plan-id> to check progress.`

### 4. Read result files

For each task in the plan, read the corresponding result file at `$TEAM_PLANS/<plan-id>/results/<task-id>.md`.

For each result file:
- Parse frontmatter: `task_id`, `plan_id`, `assignee`, `status`, `completed_at`
- Read the full body content
- If a result file is missing for a `done` task, warn: `Warning: result file for task <task-id> not found. Synthesis will note this gap.`
- If a result file has `status: failed`, extract the error message from the body

Build a list of result summaries:

```
task-001: done, completed at <timestamp>, result length <N> lines
task-002: done, completed at <timestamp>, result length <N> lines
task-003: failed, error: <error message>
```

### 5. Tier-2 confirmation

Print what will be created:

```
I will create the following for plan '<plan-id>':
  Synthesis file: $TEAM_PLANS/<plan-id>/synthesis.md
  Audit log:       $AUDIT_LOG

Synthesis will combine results from <count> tasks:
  Done:   <count>
  Failed: <count>
```

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 6. Build synthesis content

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Construct the synthesis document. The synthesis combines all task results into a unified report with:

1. **Header and metadata** -- plan ID, name, timestamps, summary statistics
2. **Executive summary** -- brief overview of what the plan accomplished
3. **Task-by-task results** -- each task's output, organized in dependency order (topological)
4. **Cross-references** -- how task results relate to each other (where task B references task A's output)
5. **Issues and gaps** -- any failed tasks, missing result files, or incomplete outputs
6. **Recommendations** -- suggested next steps based on the combined results

The synthesis frontmatter:

```yaml
---
type: synthesis
plan_id: <plan-id>
name: <name-text>
status: <completed | partial-failure>
created_at: <utc-date YYYY-MM-DD>
tasks_total: <count>
tasks_done: <count>
tasks_failed: <count>
sprint: <sprint-id | null>
---
```

The synthesis body follows this structure:

```markdown
# Synthesis: <plan-id> -- <name-text>

## Executive Summary

<Auto-generated 2-3 sentence summary of what the plan accomplished. Based on task titles and completion status.>

## Plan Timeline

- Created: <created_at>
- Confirmed: <confirmed_at>
- Started: <started_at>
- Completed: <completed_at>
- Synthesized: <utc-timestamp>

## Task Results

### task-001: <title>

**Assignee:** <assignee> (<role>)
**Status:** done
**Completed at:** <completed_at>

<Body content from results/task-001.md, excluding frontmatter>

---

### task-002: <title>

**Assignee:** <assignee> (<role>)
**Status:** done
**Completed at:** <completed_at>

<Body content from results/task-002.md, excluding frontmatter>

---

(Continue for all tasks in dependency order)

## Cross-References

<Task B references Task A's output -- list any explicit or implicit cross-references between task results>

## Issues

<Any failed tasks, missing results, or gaps noted during synthesis>

## Recommendations

<Suggested next steps based on the combined results>
```

If a result file body is empty or missing, include a placeholder:

```markdown
### task-NNN: <title>

**Assignee:** <assignee> (<role>)
**Status:** done
**Completed at:** <completed_at>

*(No result content provided)*
```

For a failed task:

```markdown
### task-NNN: <title>

**Assignee:** <assignee> (<role>)
**Status:** FAILED
**Error:** <error message from result file>

*(Task failed -- see error above)*
```

### 7. Write synthesis.md

Write `$TEAM_PLANS/<plan-id>/synthesis.md` using the atomic write pattern from `_shared.md section 6`:

1. Write content to `$TEAM_PLANS/<plan-id>/synthesis.md.tmp`.
2. Verify the `.tmp` file parses correctly (valid YAML frontmatter).
3. Rename `$TEAM_PLANS/<plan-id>/synthesis.md.tmp` to `$TEAM_PLANS/<plan-id>/synthesis.md`.

### 8. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"plan-synthesize","scope":"team:<team-name>","args":{"plan_id":"<plan-id>","name":"<name-text>","tasks_total":<count>,"tasks_done":<count>,"tasks_failed":<count>},"diff":{"created":["$TEAM_PLANS/<plan-id>/synthesis.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 9. Report to user

```
Synthesized plan <plan-id>: <name-text>
  Synthesis file: $TEAM_PLANS/<plan-id>/synthesis.md
  Tasks included: <count> (<done> done, <failed> failed)
  Plan status:    <completed | partial-failure>

The synthesis report combines all task results into a unified document with:
  - Executive summary
  - Task-by-task results in dependency order
  - Cross-references between task outputs
  - Issues and recommendations

Next steps:
  /software-house plan status --plan <plan-id>    review full plan status
  /software-house show <agent-name>               check agent details
```

## Failure modes

- Plan not found -> abort, no log.
- Plan has tasks with `pending` or `running` status -> abort, suggest `plan status`, no log.
- Plan has no tasks (empty task list) -> abort: `Error: plan <plan-id> has no tasks. Nothing to synthesize.`
- Result file missing for a `done` task -> proceed with a placeholder in the synthesis; warn the user.
- Result file malformed (no frontmatter) -> treat the entire file as body content with unknown metadata; warn the user.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp` file; log `result: failed`.
- `$TEAM_PLANS/<plan-id>/synthesis.md` already exists -> abort: `Error: synthesis already exists for plan <plan-id>. Delete $TEAM_PLANS/<plan-id>/synthesis.md first if you want to regenerate.`

## Examples

```
# Synthesize a completed plan
/software-house plan synthesize --plan plan-001

# Synthesize after checking status
/software-house plan status --plan plan-003
/software-house plan synthesize --plan plan-003
```