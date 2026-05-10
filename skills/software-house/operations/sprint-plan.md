# Operation: sprint-plan -- add/remove backlog items to/from a sprint

**Risk tier:** 3 (modifying -- updates backlog item status and sprint board)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Add backlog items to a sprint (places them on the board in the "todo" column) or remove them from a sprint (moves them back to the backlog as "open"). Updates both the sprint board and the backlog file. Optionally import tasks from a linked plan file via `--from-plan`.

## Invocation patterns

| Command | Behavior |
|---|---|
| `sprint plan --sprint <id> --add <backlog-item-id>` | Add one backlog item to the sprint |
| `sprint plan --sprint <id> --add <id1> --add <id2>` | Add multiple backlog items |
| `sprint plan --sprint <id> --remove <item-id>` | Remove an item from the sprint |
| `sprint plan --sprint <id> --add <id> --from-plan <plan-id>` | Import tasks from a linked plan file |

`--add` and `--remove` may be combined in a single invocation.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--sprint` | yes | Must match `^sprint-\d{3}$` and exist under `$TEAM_SPRINTS` |
| `--add` | no (at least one of --add or --remove required) | Must match `^item-\d{3}$` and exist in `$TEAM_BACKLOG` |
| `--remove` | no (at least one of --add or --remove required) | Must match `^item-\d{3}$` and exist on the sprint board |
| `--from-plan` | no | Plan file identifier; must resolve to an existing plan file under `$TEAM_DIR/plans/` |

At least one of `--add` or `--remove` must be given. If neither is provided, abort: `Error: at least one --add or --remove is required.`

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. `$TEAM_BACKLOG` exists. If not, refuse: `Error: backlog not found. Run /software-house backlog add to create the first item.`
3. The sprint directory and sprint.md must exist. If not, refuse: `Error: sprint <id> not found. Run /software-house sprint create to create a sprint first.`
4. Sprint must not be in `closed` status. Refuse: `Error: sprint <id> is closed. Cannot modify a closed sprint.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--sprint` matches `^sprint-\d{3}$`. Check that `$TEAM_SPRINTS/<id>/sprint.md` exists. Abort if not found: `Error: sprint <id> not found.`

Validate each `--add` item ID matches `^item-\d{3}$`. For each, check it exists in `$TEAM_BACKLOG`. Abort if any not found: `Error: backlog item <id> not found.`

Validate each `--remove` item ID matches `^item-\d{3}$`. For each, check it exists on the sprint board (`$TEAM_SPRINTS/<sprint>/board.md`). Abort if any not found: `Error: item <id> is not on the sprint board for <sprint-id>.`

If `--from-plan` is given, resolve the plan file. Check `$TEAM_DIR/plans/<plan-id>.md` or `$TEAM_DIR/plans/<plan-id>/plan.md`. If not found, abort: `Error: plan <plan-id> not found under $TEAM_DIR/plans/.`

### 2. Read current state

Read `$TEAM_BACKLOG` -- parse the backlog table to find rows for items being added or removed.

Read `$TEAM_SPRINTS/<sprint>/board.md` -- parse current board state (which items are in each column).

Read `$TEAM_SPRINTS/<sprint>/sprint.md` -- parse sprint metadata (status, item counts, story points).

### 3. Compute diff

Build the modification plan. For each `--add` item:

```
$TEAM_BACKLOG (table row)
  field Status: open -> in-sprint

$TEAM_SPRINTS/<sprint>/board.md
  + item <id> added to "Todo" column: <title> [<type>] (<story-points> pts)

$TEAM_SPRINTS/<sprint>/sprint.md (frontmatter)
  field total_items: <old> -> <old + 1>
  field total_story_points: <old> -> <old + item-story-points or old if unestimated>
  field updated_at: <old> -> <utc-date>
```

For each `--remove` item:

```
$TEAM_BACKLOG (table row)
  field Status: in-sprint -> open

$TEAM_SPRINTS/<sprint>/board.md
  - item <id> removed from "<column>" column: <title>

$TEAM_SPRINTS/<sprint>/sprint.md (frontmatter)
  field total_items: <old> -> <old - 1>
  field total_story_points: <old> -> <old - item-story-points or old if unestimated>
  field updated_at: <old> -> <utc-date>
```

If `--from-plan` is given, list the plan tasks that will be imported as new backlog items first, then added to the sprint. Each plan task becomes a backlog item with `--type task`, the plan title as the `--title`, and story points from the plan if available.

### 4. Tier-3 confirmation

Print the full diff from Step 3. Print all file paths that will be modified:

```
I will update the following:
  Backlog file:  $TEAM_BACKLOG
  Board file:    $TEAM_SPRINTS/<sprint>/board.md
  Sprint file:   $TEAM_SPRINTS/<sprint>/sprint.md
  Audit log:     $AUDIT_LOG
```

Print the Tier-3 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 5. Update backlog file

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

For each `--add` item: update its Status column from `open` to `in-sprint`.

For each `--remove` item: update its Status column from `in-sprint` to `open`.

Update the frontmatter `updated_at` field.

Use the atomic write pattern from `_shared.md section 6`.

If `--from-plan` is given: first create backlog items (using `backlog-add` logic -- append rows to the backlog table with auto-incremented IDs), then set their status to `in-sprint`.

### 6. Update sprint board

Using the atomic write pattern from `_shared.md section 6`:

For each `--add` item: append the item under the `## Todo` section in `board.md`. Format:

```
- [<id>] <title> [<type>] (<story-points> pts | unestimated) -- assigned: <assignee | unassigned>
```

For each `--remove` item: locate and remove the item from its current column section. If the item was not in "todo" (e.g., it was "in-progress"), note this in the audit log.

Update the frontmatter `updated_at` field.

### 7. Update sprint metadata

Using the atomic write pattern from `_shared.md section 6`, update `$TEAM_SPRINTS/<sprint>/sprint.md` frontmatter:

```yaml
total_items: <new count>
total_story_points: <new total>
updated_at: <utc-date YYYY-MM-DD>
```

If sprint status was `planning` and items are now added, change status to `active`:

```yaml
status: active
```

### 8. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-plan","scope":"team:<team>","args":{"sprint_id":"<id>","add":["<item-id-1>","<item-id-2>"],"remove":["<item-id-3>"],"from_plan":"<plan-id|null>"},"diff":{"updated":["$TEAM_BACKLOG","$TEAM_SPRINTS/<sprint>/board.md","$TEAM_SPRINTS/<sprint>/sprint.md"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

If new backlog items were created from `--from-plan`, include their IDs in the `diff.created` array.

### 9. Report to user

```
Updated sprint <sprint-id> plan
  Added:    <item-id-list>  (or "(none)")
  Removed:  <item-id-list>  (or "(none)")
  From plan: <plan-id>  (or "(none)")

  Board:  $TEAM_SPRINTS/<sprint>/board.md
  Backlog: $TEAM_BACKLOG

Next steps:
  /software-house sprint board --sprint <sprint-id>   view the updated board
  /software-house sprint standup --sprint <sprint-id>  record a standup
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- Sprint not found -> abort, no log.
- Sprint is closed -> refuse, no log.
- Backlog item not found (for --add) -> abort, no log.
- Board item not found (for --remove) -> abort, no log.
- Item already in sprint (for --add) -> warn and skip that item, continue with others.
- Item not in sprint (for --remove) -> warn and skip that item, continue with others.
- `--from-plan` plan file not found -> abort, no log.
- Neither --add nor --remove given -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp` files, log `result: failed`.

## Examples

```
# Add a single backlog item to a sprint
/software-house sprint plan --sprint sprint-001 --add item-001

# Add multiple items
/software-house sprint plan --sprint sprint-001 --add item-001 --add item-003 --add item-007

# Remove an item from a sprint
/software-house sprint plan --sprint sprint-001 --remove item-003

# Add and remove in one command
/software-house sprint plan --sprint sprint-001 --add item-005 --remove item-002

# Import tasks from a plan file
/software-house sprint plan --sprint sprint-002 --add item-010 --from-plan phase-3-plan
```