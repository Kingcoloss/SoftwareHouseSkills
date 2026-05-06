# Operation: sprint-board -- view or modify the sprint board

**Risk tier:** 1 (view) / 3 (modify -- when --move is used)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

View the sprint kanban board or move items between columns. When invoked without `--move`, renders the board as a read-only table (Tier 1). When invoked with `--move`, updates the board by moving an item to a different column (Tier 3, requires confirmation).

## Invocation patterns

| Command | Behavior | Tier |
|---|---|---|
| `sprint board --sprint <id>` | View the sprint board | 1 (read-only) |
| `sprint board --sprint <id> --move <item-id> --to <column>` | Move item to a different column | 3 (modifying) |

If `--sprint` is omitted, auto-detect the active (most recent non-closed) sprint.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--sprint` | no (auto-detected if omitted) | Must match `^sprint-\d{3}$` and exist under `$TEAM_SPRINTS` |
| `--move` | no | Must match `^item-\d{3}$` and exist on the sprint board |
| `--to` | required if `--move` is given | One of `todo`, `in-progress`, `review`, `done` |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. Sprint board file must exist. If not, refuse: `Error: sprint <id> board not found.`
3. When modifying: sprint must not be `closed`. Refuse: `Error: sprint <id> is closed. Cannot modify a closed sprint.`

## Step-by-step protocol

### VIEW MODE (Tier 1)

#### 1. Resolve sprint

If `--sprint` is given, validate and use it. If omitted, find the most recent sprint directory under `$TEAM_SPRINTS/` that does not have `status: closed` in its `sprint.md` frontmatter. If no active sprint found, refuse: `Error: no active sprint found. Run /software-house sprint create to create one.`

#### 2. Read board

Read `$TEAM_SPRINTS/<sprint>/board.md`. Parse each column section (`## Todo`, `## In Progress`, `## Review`, `## Done`).

#### 3. Render board

Print the board as a table:

```
# Sprint Board -- <sprint-id>

## Todo
| ID | Title | Type | Story Pts | Assignee |
|----|-------|------|-----------|----------|
| item-001 | User authentication flow | feature | 8 | alice |

## In Progress
| ID | Title | Type | Story Pts | Assignee |
|----|-------|------|-----------|----------|
| item-003 | Fix login crash on mobile | bug | 3 | bob |

## Review
(none)

## Done
| ID | Title | Type | Story Pts | Assignee |
|----|-------|------|-----------|----------|
| item-002 | Setup CI pipeline | task | 5 | carol |
```

If a column has no items, print `(none)` below the column heading.

#### 4. Summary line

```
Total: <N> items | <X> story points | Todo: <n> | In Progress: <n> | Review: <n> | Done: <n>
```

No audit log entry for view mode. Stop here.

### MOVE MODE (Tier 3)

#### 5. Validate move inputs

Validate `--move` matches `^item-\d{3}$`. Locate the item on the sprint board. If not found on any column, abort: `Error: item <id> not found on the sprint board for <sprint-id>.`

Validate `--to` is one of `todo`, `in-progress`, `review`, `done`. Abort on invalid value: `Error: --to must be one of: todo, in-progress, review, done. Got: <value>.`

If the item is already in the target column, warn: `Note: item <id> is already in <column>. No change needed.` and ask the user if they want to proceed anyway.

#### 6. Compute diff

Determine the current column and target column:

```
File: $TEAM_SPRINTS/<sprint>/board.md
  Move: item-<NNN> "<title>"
    From: <current-column>
    To:   <target-column>

File: $TEAM_SPRINTS/<sprint>/sprint.md (frontmatter)
  field updated_at: <old> -> <utc-date>
  <If moving to "done":>
  field items_completed: <old> -> <old + 1>
  field story_points_completed: <old> -> <old + item-story-points or old>
  <If moving FROM "done":>
  field items_completed: <old> -> <old - 1>
  field story_points_completed: <old> -> <old - item-story-points or old>
```

Also update the backlog file if the status change affects the backlog:

```
File: $TEAM_BACKLOG (if moving to "done")
  Row item-<NNN> field Status: in-sprint -> closed

File: $TEAM_BACKLOG (if moving FROM "done" to a non-done column)
  Row item-<NNN> field Status: closed -> in-sprint
```

#### 7. Tier-3 confirmation

Print the diff. Print all modified file paths:

```
I will update the following:
  Board file:    $TEAM_SPRINTS/<sprint>/board.md
  Sprint file:   $TEAM_SPRINTS/<sprint>/sprint.md
  Backlog file:  $TEAM_BACKLOG  (if status changed)
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

#### 8. Update board file

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Using the atomic write pattern from `_shared.md section 6`:

1. Remove the item from its current column section.
2. Add the item to the target column section.
3. Update frontmatter `updated_at`.

#### 9. Update sprint metadata

Using the atomic write pattern from `_shared.md section 6`, update `$TEAM_SPRINTS/<sprint>/sprint.md` frontmatter:

If moving to `done`:
```yaml
items_completed: <old + 1>
story_points_completed: <old + item-story-points or old>
updated_at: <utc-date YYYY-MM-DD>
```

If moving from `done` to any other column:
```yaml
items_completed: <old - 1>
story_points_completed: <old - item-story-points or old>
updated_at: <utc-date YYYY-MM-DD>
```

Otherwise (not involving `done`):
```yaml
updated_at: <utc-date YYYY-MM-DD>
```

#### 10. Update backlog (if applicable)

If the item moved to `done`, update `$TEAM_BACKLOG` -- change the item's Status from `in-sprint` to `closed`.

If the item moved from `done` to another column, change the item's Status from `closed` to `in-sprint`.

Use the atomic write pattern from `_shared.md section 6`.

#### 11. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-board","scope":"team:<team>","args":{"sprint_id":"<id>","item_id":"<item-id>","from_column":"<current>","to_column":"<target>"},"diff":{"updated":["$TEAM_SPRINTS/<sprint>/board.md","$TEAM_SPRINTS/<sprint>/sprint.md","$TEAM_BACKLOG"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

Omit `$TEAM_BACKLOG` from `diff.updated` if no backlog status change occurred.

#### 12. Report to user

```
Moved item-<NNN> on sprint <sprint-id>
  From:     <current-column>
  To:       <target-column>
  Title:    <title>
  Board:    $TEAM_SPRINTS/<sprint>/board.md

Next steps:
  /software-house sprint board --sprint <sprint-id>   view updated board
  /software-house sprint standup --sprint <sprint-id>  record a standup
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- Sprint not found -> abort, no log.
- Sprint board file missing -> abort, no log.
- Sprint is closed (for move) -> refuse, no log.
- Item not found on board (for move) -> abort, no log.
- Invalid `--to` column -> abort, no log.
- Item already in target column -> warn, continue or abort based on user choice.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp` files, log `result: failed`.

## Examples

```
# View the current sprint board
/software-house sprint board

# View a specific sprint board
/software-house sprint board --sprint sprint-001

# Move an item to in-progress
/software-house sprint board --sprint sprint-001 --move item-001 --to in-progress

# Move an item to done
/software-house sprint board --sprint sprint-001 --move item-003 --to done

# Move an item back from review to in-progress
/software-house sprint board --sprint sprint-001 --move item-005 --to in-progress
```