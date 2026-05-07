# handoff -- Inter-agent handoff briefs

Risk tier: 2 (non-destructive, creates state).

## Purpose

Manage inter-agent handoff briefs: list pending briefs, show brief detail, mark briefs complete (with wiki update), and generate briefs from a task description using the agent's role template handoff triggers.

## Invocation patterns

```
/software-house handoff list [--team <t>] [--status pending|in-progress|done] [--from <agent>] [--to <agent>]
/software-house handoff show <brief-id>
/software-house handoff complete <brief-id> [--summary "<text>"]
/software-house handoff generate <from-agent> <task> [--priority high|medium|low] [--context <page>...]
```

## Pre-conditions

- `~/.software-house/` must exist (init has been run).
- The `from-agent` must exist and be active.
- Handoff directories must exist (created by init or on first use).

## Operations

### handoff list

List handoff briefs, optionally filtered.

1. Read briefs from `$WIKI_HANDOFF_BRIEFS/` (company level) and `$TEAM_WIKI_HANDOFF_BRIEFS/` (team level).
2. If `--team <t>` is given, resolve the team path and read from team-level briefs only.
3. If `--status` is given, filter by frontmatter `status`.
4. If `--from` is given, filter by frontmatter `from`.
5. If `--to` is given, filter by frontmatter `to`.
6. Display results as a table: `BRIEF_ID | FROM | TO | PRIORITY | STATUS | CREATED_AT`.

### handoff show

Display a single brief in detail.

1. Find the brief file by ID (search both company and team level).
2. Print frontmatter fields.
3. Print body content.

### handoff complete

Mark a brief as done and update the receiving agent's wiki page.

1. Find the brief file by ID.
2. Read frontmatter, verify status is `pending` or `in-progress`.
3. Update frontmatter: `status: done`, `completed_at: <now>`.
4. If `--summary` is given, append the summary to the brief body.
5. Find the receiving agent's wiki page (company or team level).
6. Append a handoff history entry to the wiki page:
   ```
   - YYYY-MM-DD: Completed brief from <from> about <task summary> -> [brief_id]
   ```
7. Log the completion in the audit log.

### handoff generate

Analyze a task description and generate briefs for each role that needs to be involved, using the sending agent's role template `handoff_triggers`.

1. Validate `<from-agent>` exists and is active.
2. Read the agent's canonical file, get `role`.
3. Load `role-templates.json`, get the `handoff_triggers` for this role.
4. Analyze the task description for keywords matching trigger keys.
5. For each matching trigger, create a brief:
   a. Generate a brief ID: `<from>-<to>-<timestamp>`.
   b. Create the brief file at `$WIKI_HANDOFF_BRIEFS/<brief-id>.md`.
   c. Frontmatter: `from`, `to`, `task`, `priority`, `context_pages`, `created_at`, `status: pending`, `brief_id`.
   d. Body: task description, context excerpt, expected deliverables for the target role.
6. If no triggers match (no keywords found), present the trigger list and ask the user to specify which roles to hand off to.
7. Display created briefs as a table.
8. Log the generation in the audit log.

## Handoff directory structure

```
~/.software-house/
  company/wiki/handoffs/
    inbox/           # Task assignments (from delegate operation)
      <agent>-task-<ts>.md
    completed/       # Completed handoffs (moved after processing)
      <agent>-task-<ts>.md
    briefs/          # Inter-agent handoff briefs
      <from>-<to>-<ts>.md

<project>/.software-house/team/wiki/handoffs/
  inbox/
  completed/
  briefs/
```

## Brief file format

```yaml
---
from: <agent-name>
to: <agent-name>
task: "<task description>"
priority: high | medium | low
context_pages: [wiki/pages/to/read]
created_at: YYYY-MM-DDTHH:MM:SSZ
status: pending | in-progress | done
completed_at: null | YYYY-MM-DDTHH:MM:SSZ
deliverables: [<expected deliverables>]
dependencies: [<brief-ids>]
brief_id: <from>-<to>-<ts>
---

<Body: task context, specific deliverable expectations, relevant wiki excerpts, dependencies on other handoffs>
```

## Failure modes

| Condition | Response |
|-----------|----------|
| Agent not found | Print error, exit 1 |
| Agent not active | Print warning with status, exit 1 |
| Brief not found | Print error, exit 1 |
| Brief already done | Print warning, exit 1 |
| No matching triggers | Show trigger list, ask user |
| Handoff dirs not found | Create them, proceed |

## Audit log format

```
{"op":"handoff-list","agent":"<caller>","filters":{...},"ts":"<ISO8601>"}
{"op":"handoff-show","brief_id":"<id>","ts":"<ISO8601>"}
{"op":"handoff-complete","brief_id":"<id>","from":"<agent>","to":"<agent>","ts":"<ISO8601>"}
{"op":"handoff-generate","from":"<agent>","briefs_created":N,"brief_ids":["<id1>","<id2>"],"ts":"<ISO8601>"}
```