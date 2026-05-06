# Operation: plan-execute -- execute a confirmed plan by spawning sub-agents

**Risk tier:** 3 (modifying -- spawns sub-agents, updates plan status and task results)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Execute a confirmed plan by spawning sub-agents for each task in dependency order. Performs a topological sort on the task dependency graph, then executes tasks in waves: all tasks in a wave have their dependencies satisfied by completed tasks in prior waves. On Claude Code, sub-agents are spawned using the Agent tool. On Codex and Gemini (which lack the Agent tool), manual dispatch instructions are printed for each task. The operation tracks progress in status.md and writes per-task results to the results/ directory.

## Invocation patterns

| Command | Behavior |
|---|---|
| `plan execute --plan <plan-id>` | Execute a confirmed plan with default parallelism |
| `plan execute --plan <plan-id> --max-parallel N` | Limit concurrent sub-agents to N (default: unlimited) |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--plan` | yes | Must match `^plan-\d{3}$` and reference an existing plan directory |
| `--max-parallel` | no | Positive integer; default 0 (unlimited parallelism within each wave) |

## Preconditions

1. `$TEAM_DIR` exists (project is initialized with a team). If not, refuse: `Error: project not initialized. Run /software-house init first.`
2. `$TEAM_PLANS/<plan-id>/plan.md` must exist. If not, refuse: `Error: plan <plan-id> not found.`
3. The plan's `status` frontmatter must be `confirmed`. If `draft`, refuse: `Error: plan <plan-id> is still in draft status. Run /software-house plan confirm --plan <plan-id> first.` If `completed`, refuse: `Error: plan <plan-id> has already been completed. Create a new plan to execute again.` If `running`, refuse: `Error: plan <plan-id> is already running. Use /software-house plan status --plan <plan-id> to check progress.`
4. All tasks must have a non-null `assignee`. If any task has `assignee: null`, refuse: `Error: plan has unassigned tasks. Run /software-house plan confirm --plan <plan-id> --assign <task-id> <agent-name> first.`
5. The dependency graph must be acyclic. If cycles are detected, refuse with the cycle listed.

## Step-by-step protocol

### 1. Validate inputs

Validate `--plan` matches `^plan-\d{3}$`. Abort on mismatch: `Error: invalid plan ID format. Expected plan-NNN (e.g., plan-001).`

If `--max-parallel` is given, validate it is a positive integer or 0. Abort if not: `Error: --max-parallel must be a positive integer or 0 (unlimited).`

Read and parse `$TEAM_PLANS/<plan-id>/plan.md`. Extract: `status`, `name`, `tasks` list.

Validate `status` is `confirmed`. Abort per Precondition 3 if not.

Validate all tasks have a non-null `assignee`. Abort per Precondition 4 if any are null.

### 2. Topological sort and cycle detection

Build the dependency graph from the tasks list. Each task has an `id` and a `dependencies` list (which references other task IDs in this plan).

Perform a topological sort using Kahn's algorithm:

1. Compute in-degree for each task (number of dependencies).
2. Initialize queue with all tasks that have in-degree 0 (no dependencies).
3. While queue is not empty:
   a. Dequeue a task. Add it to the current wave.
   b. For each task that depends on this task, decrement its in-degree.
   c. If any task's in-degree becomes 0, add it to the queue for the next wave.
4. If not all tasks were processed, a cycle exists.

If a cycle is detected, list the tasks involved and abort: `Error: dependency cycle detected involving tasks: <task-ids>. Resolve cycles before executing.`

Assign wave numbers to tasks based on the topological order. Wave 1 contains tasks with no dependencies. Wave N contains tasks whose dependencies are all in waves 1 through N-1.

### 3. Detect harness capabilities

Determine which harness is running and whether it supports sub-agent spawning:

- Claude Code: supports the `Agent` tool for sub-agent spawning.
- Codex CLI: does not support sub-agent spawning natively. Execution mode is `manual-dispatch`.
- Gemini CLI: does not support sub-agent spawning natively. Execution mode is `manual-dispatch`.

Detection heuristic:

```
Check for ~/.claude -> HAS_CLAUDE_CODE (and this is likely the running harness)
Check for ~/.codex || ~/.agents -> HAS_CODEX
Check for ~/.gemini -> HAS_GEMINI
```

The execution mode is:
- `auto-spawn` if the current harness supports the Agent tool (Claude Code).
- `manual-dispatch` otherwise (Codex, Gemini, or undetected harness).

### 4. Resolve task-agent-tool mapping

For each task, resolve the tools available to the assigned agent:

1. Read the agent's canonical file from `$TEAM_AGENTS/<assignee>.md` (or `$AGENTS_GLOBAL/<assignee>.md` for freelance).
2. Extract the `tools` list from the frontmatter.
3. If the agent has `agent` in their tools list AND the harness is Claude Code, the sub-agent can spawn its own sub-agents (recursive execution).
4. If the agent does not have `agent` in their tools, the sub-agent runs with the restricted tool set.

### 5. Build execution plan display

Print the execution plan:

```
Plan: <plan-id> -- <name>
Execution mode: <auto-spawn | manual-dispatch>

Execution waves:
  Wave 1 (no dependencies):
    task-001: <title>
      Assignee: <agent-name> (<role>)
      Tools: <resolved tool list>
    task-002: <title>
      Assignee: <agent-name> (<role>)
      Tools: <resolved tool list>

  Wave 2 (depends on wave 1):
    task-003: <title>
      Assignee: <agent-name> (<role>)
      Tools: <resolved tool list>

Total waves: <count>
Total tasks: <count>
Max parallelism per wave: <N | unlimited>
```

For `manual-dispatch` mode, add:

```
NOTE: Current harness does not support auto-spawning sub-agents.
Each task will print manual dispatch instructions for you to run.
```

### 6. Tier-3 confirmation

Print the diff (what will change):

```
Files to be modified:
  $TEAM_PLANS/<plan-id>/plan.md (status: confirmed -> running)
  $TEAM_PLANS/<plan-id>/status.md (status: confirmed -> running)

Files to be created (per task):
  $TEAM_PLANS/<plan-id>/results/task-001.md
  $TEAM_PLANS/<plan-id>/results/task-002.md
  ...

Audit log: $AUDIT_LOG
```

Print the Tier-3 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 7. Begin execution

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Update plan.md frontmatter using atomic write per `_shared.md section 6`:

```yaml
status: running
started_at: <utc-timestamp>
updated_at: <utc-date YYYY-MM-DD>
```

Update status.md frontmatter:

```yaml
---
plan_id: <plan-id>
status: running
started_at: <utc-timestamp>
confirmed_at: <confirmed-at-from-plan>
wave: 1
---
```

Update status.md body:

```markdown
# Status: <plan-id>

Started at: <utc-timestamp>
Current wave: 1

| Task | Assignee | Role | Dependencies | Status |
|------|----------|------|-------------|--------|
| task-001 | <assignee> | <role> | none | pending |
| task-002 | <assignee> | <role> | none | pending |
| ... | | | | |
```

### 8. Execute each wave

For each wave (starting from wave 1):

#### 8a. Identify wave tasks

List all tasks in the current wave. These are tasks whose `dependencies` are all marked as `done` (or have no dependencies for wave 1).

If `--max-parallel N` is set and the wave has more than N tasks, process tasks in batches of N. Wait for each batch to complete before starting the next batch within the same wave.

#### 8b. Spawn sub-agents (auto-spawn mode)

For each task in the current wave (up to `--max-parallel` limit):

Build the sub-agent prompt:

```
You are <agent-name>, a <role> agent on the team.
Your task: <task-title>

Task ID: <task-id>
Plan ID: <plan-id>

Instructions:
1. Read the plan file at $TEAM_PLANS/<plan-id>/plan.md for full context.
2. Complete the task described above.
3. Write your results to $TEAM_PLANS/<plan-id>/results/<task-id>.md with the following format:

   ---
   task_id: <task-id>
   plan_id: <plan-id>
   assignee: <agent-name>
   status: done
   completed_at: <utc-timestamp>
   ---

   # Results: <task-title>

   <your work output>

4. If you cannot complete the task, write results with status: failed and include an error message.
5. Do NOT modify any file outside the results directory unless the task explicitly requires it.

Tools available: <resolved tool list from step 4>
```

Spawn the sub-agent using the Agent tool (Claude Code harness):

```
Agent(
  name: <agent-name>,
  prompt: <built prompt>,
  tools: <resolved tool list>
)
```

Mark the task as `running` in status.md.

#### 8c. Manual dispatch instructions (manual-dispatch mode)

For each task in the current wave, print:

```
--- Task: task-001 (<title>) ---
Assignee: <agent-name> (<role>)
Harness: <codex | gemini> (manual dispatch required)

Manual dispatch instructions:
1. Open a new session with agent '<agent-name>'.
2. Provide the following prompt:

   <full sub-agent prompt from 8b>

3. After the agent completes, write results to:
   $TEAM_PLANS/<plan-id>/results/<task-id>.md

4. Confirm task completion before proceeding to the next task.
---
```

Mark the task as `manual-dispatch` in status.md.

#### 8d. Poll for task completion

For auto-spawn mode: poll the results directory for each task in the current wave.

- Check if `$TEAM_PLANS/<plan-id>/results/<task-id>.md` exists.
- If it exists, parse the frontmatter. Check `status` field:
  - `done`: mark task as completed.
  - `failed`: mark task as failed. Halt execution.
- If it does not exist after a reasonable timeout (or the Agent tool returns), check the Agent tool result for success/failure.

For manual-dispatch mode: wait for the user to confirm each task is done. After user confirmation, check for the result file.

Polling interval: check every 5 seconds, up to a maximum of 60 checks (5 minutes) per task. If a task does not complete within the timeout, mark it as `timed-out` and halt execution.

#### 8e. Update status.md after wave completion

After all tasks in a wave complete (or fail):

Update status.md body with current task statuses:

```markdown
| Task | Assignee | Role | Dependencies | Status |
|------|----------|------|-------------|--------|
| task-001 | <assignee> | <role> | none | done |
| task-002 | <assignee> | <role> | none | done |
| task-003 | <assignee> | <role> | task-001, task-002 | pending |
| ... | | | | |
```

Update status.md frontmatter:

```yaml
wave: <current-wave-number>
```

#### 8f. Compute next wave

Identify tasks whose all dependencies are now `done`. These form the next wave.

If no more tasks remain (all done), proceed to Step 9.

If some tasks remain but none can execute (blocked by failed or timed-out tasks), mark the plan as `failed` and proceed to Step 9 with failure handling.

### 9. Finalize execution

After all tasks complete (or a task fails):

If all tasks completed successfully:

Update plan.md frontmatter using atomic write:

```yaml
status: completed
updated_at: <utc-date YYYY-MM-DD>
completed_at: <utc-timestamp>
```

Update status.md:

```yaml
status: completed
completed_at: <utc-timestamp>
```

If any task failed or timed out:

Update plan.md frontmatter:

```yaml
status: failed
updated_at: <utc-date YYYY-MM-DD>
completed_at: <utc-timestamp>
failed_task: <task-id>
failure_reason: <error-message | timeout>
```

Update status.md similarly.

### 10. Append audit log entry

For successful completion:

```json
{"ts":"<utc>","actor":"user","op":"plan-execute","scope":"team:<team-name>","args":{"plan_id":"<plan-id>","name":"<name-text>","task_count":<count>,"wave_count":<count>,"execution_mode":"<auto-spawn|manual-dispatch>","max_parallel":<N|null>},"diff":{"updated":["$TEAM_PLANS/<plan-id>/plan.md","$TEAM_PLANS/<plan-id>/status.md"],"created":["$TEAM_PLANS/<plan-id>/results/task-001.md","$TEAM_PLANS/<plan-id>/results/task-002.md",...]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

For partial failure:

```json
{"ts":"<utc>","actor":"user","op":"plan-execute","scope":"team:<team-name>","args":{"plan_id":"<plan-id>","name":"<name-text>","task_count":<count>,"completed_tasks":<count>,"failed_task":"<task-id>","failure_reason":"<reason>"},"diff":{"updated":["$TEAM_PLANS/<plan-id>/plan.md","$TEAM_PLANS/<plan-id>/status.md"],"created":["$TEAM_PLANS/<plan-id>/results/task-001.md",...]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"failed","error":"task <task-id> failed: <reason>"}
```

### 11. Report to user

For successful completion:

```
Plan <plan-id> completed: <name-text>
  Status:      confirmed -> completed
  Completed at: <utc-timestamp>
  Tasks:       <count> total, <count> done
  Waves:       <count>
  Results dir:  $TEAM_PLANS/<plan-id>/results/

Next steps:
  /software-house plan status --plan <plan-id>      view full status
  /software-house plan synthesize --plan <plan-id>  combine all task results
```

For partial failure:

```
Plan <plan-id> failed: <name-text>
  Status:          confirmed -> failed
  Failed task:     <task-id> (<title>)
  Failure reason:  <reason>
  Completed tasks: <count> of <count>
  Results dir:     $TEAM_PLANS/<plan-id>/results/

Recovery:
  Fix the failed task manually and re-write the result file at
  $TEAM_PLANS/<plan-id>/results/<task-id>.md with status: done
  Then run /software-house plan status --plan <plan-id> to check progress.
```

For manual-dispatch mode:

```
Plan <plan-id> in manual-dispatch mode: <name-text>
  Status:       running
  Current wave:  1
  Tasks:        <count>

  IMPORTANT: You must manually dispatch each task to the assigned agent
  and write result files to $TEAM_PLANS/<plan-id>/results/<task-id>.md

  After completing each task, run:
  /software-house plan status --plan <plan-id>
```

## Failure modes

- Plan not found -> abort, no log.
- Plan status not `confirmed` -> abort with status-specific message, no log.
- Unassigned tasks -> abort, suggest `plan confirm --assign`, no log.
- Dependency cycle -> abort, list cycle, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Agent tool unavailable (Claude Code) -> fall back to manual-dispatch mode; print instructions; proceed.
- Sub-agent fails -> mark task as failed; halt execution; update plan status to `failed`.
- Task timeout (5 minutes) -> mark task as timed-out; halt execution; update plan status to `failed`.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.
- Result file missing or malformed -> treat as task failure; mark task as `failed` with reason `result file not found or malformed`.

## Examples

```
# Execute a confirmed plan with auto-spawning
/software-house plan execute --plan plan-001

# Execute with limited parallelism (max 3 concurrent sub-agents)
/software-house plan execute --plan plan-001 --max-parallel 3

# Execute on Codex/Gemini (manual dispatch mode)
/software-house plan execute --plan plan-002
```