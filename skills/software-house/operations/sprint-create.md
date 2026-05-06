# Operation: sprint-create -- create a new sprint

**Risk tier:** 2 (additive -- creates new directories and files only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Create a new sprint directory under `$TEAM_SPRINTS` (`$TEAM_DIR/sprints`) with sprint metadata file, kanban board, standup log, review file, and retrospective file. Sprint ID is auto-incremented as `sprint-NNN` (zero-padded to 3 digits). The sprint name is user-provided and validated per the name convention.

## Invocation patterns

| Command | Behavior |
|---|---|
| `sprint create --name "<text>" --duration <N>w` | Create sprint with required name and duration |
| `sprint create --name "<text>" --duration <N>w --goal "<text>"` | Create sprint with a goal statement |
| `sprint create --name "<text>" --duration <N>w --start-date YYYY-MM-DD` | Create sprint with explicit start date |

Any combination of `--goal` and `--start-date` may be used together.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md section 10` |
| `--duration` | yes | Positive integer followed by `w` (weeks); e.g., `2w`, `4w` |
| `--goal` | no | Free-form text; max 500 characters |
| `--start-date` | no | Must match `^\d{4}-\d{2}-\d{2}$` and be a valid calendar date; defaults to today (UTC) |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. `$TEAM_SPRINTS` directory exists or can be created. If `mkdir` fails, refuse: `Error: cannot create sprints directory at $TEAM_SPRINTS.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch: `Error: sprint name '<value>' is invalid. Must match ^[a-z][a-z0-9-]{0,63}$.`

Validate `--duration`: must match `^\d+w$`. Extract the integer part. It must be >= 1 and <= 26. Abort on mismatch: `Error: --duration must be a positive number of weeks (e.g., 2w, 4w). Got: <value>.`

If `--goal` is given, verify it is non-empty and under 500 characters.

If `--start-date` is given, validate against `^\d{4}-\d{2}-\d{2}$`. Verify it is a valid calendar date. Abort: `Error: --start-date must be a valid date in YYYY-MM-DD format. Got: <value>.`

### 2. Determine next sprint ID

Check if `$TEAM_SPRINTS` exists. If not, it will be created in Step 5.

Scan `$TEAM_SPRINTS` for existing sprint directories matching `sprint-NNN`. Find the highest NNN. Increment by 1 and zero-pad to 3 digits.

If no sprints exist, start at `sprint-001`.

### 3. Compute dates

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Determine start date:
- If `--start-date` is given, use it.
- If not, use today's UTC date.

Compute end date: `start_date + (duration_weeks * 7) days`. Format as `YYYY-MM-DD`.

### 4. Tier-2 confirmation

Build the full file list that will be created:

```
I will create the following for sprint '<name>':
  Sprint directory: $TEAM_SPRINTS/sprint-<NNN>/
  Sprint file:      $TEAM_SPRINTS/sprint-<NNN>/sprint.md
  Board file:       $TEAM_SPRINTS/sprint-<NNN>/board.md
  Standups file:    $TEAM_SPRINTS/sprint-<NNN>/standups.md
  Review file:      $TEAM_SPRINTS/sprint-<NNN>/review.md
  Retro file:       $TEAM_SPRINTS/sprint-<NNN>/retro.md
  Audit log:        $AUDIT_LOG
```

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 5. Create sprint directory

```
mkdir -p $TEAM_SPRINTS/sprint-<NNN>
```

If `mkdir` fails, abort: `Error: cannot create sprint directory. Recovery: check permissions on $TEAM_SPRINTS.` Do not log.

### 6. Write sprint.md

```markdown
---
type: sprint
sprint_id: sprint-<NNN>
name: <name>
goal: <goal | none>
status: planning
duration_weeks: <N>
start_date: <YYYY-MM-DD>
end_date: <YYYY-MM-DD>
created_at: <utc-date YYYY-MM-DD>
updated_at: <utc-date YYYY-MM-DD>
total_items: 0
total_story_points: 0
items_completed: 0
story_points_completed: 0
---

# Sprint sprint-<NNN>: <name>

## Goal

<goal text, or "(no goal set)">

## Timeline

- Start: <start_date>
- End:   <end_date>
- Duration: <N> week(s)

## Status: planning

Sprint is in planning. No items assigned yet.
Run /software-house sprint plan --sprint sprint-<NNN> to add backlog items.
```

### 7. Write board.md

```markdown
---
type: sprint-board
sprint_id: sprint-<NNN>
updated_at: <utc-date YYYY-MM-DD>
---

# Sprint Board -- sprint-<NNN>

## Todo

(none)

## In Progress

(none)

## Review

(none)

## Done

(none)
```

### 8. Write standups.md

```markdown
---
type: sprint-standups
sprint_id: sprint-<NNN>
---

# Standup Notes -- sprint-<NNN>

(No standups recorded yet. Run /software-house sprint standup --sprint sprint-<NNN> to add.)
```

### 9. Write review.md

```markdown
---
type: sprint-review
sprint_id: sprint-<NNN>
status: pending
---

# Sprint Review -- sprint-<NNN>

(Review not yet written. Run /software-house sprint review --sprint sprint-<NNN> to generate.)
```

### 10. Write retro.md

```markdown
---
type: sprint-retro
sprint_id: sprint-<NNN>
status: pending
---

# Sprint Retrospective -- sprint-<NNN>

(Retrospective not yet written. Run /software-house sprint retro --sprint sprint-<NNN> to generate.)
```

### 11. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-create","scope":"team:<team>","args":{"sprint_id":"sprint-<NNN>","name":"<name>","duration_weeks":<N>,"goal":"<goal|null>","start_date":"<YYYY-MM-DD>","end_date":"<YYYY-MM-DD>"},"diff":{"created":["$TEAM_SPRINTS/sprint-<NNN>/","$TEAM_SPRINTS/sprint-<NNN>/sprint.md","$TEAM_SPRINTS/sprint-<NNN>/board.md","$TEAM_SPRINTS/sprint-<NNN>/standups.md","$TEAM_SPRINTS/sprint-<NNN>/review.md","$TEAM_SPRINTS/sprint-<NNN>/retro.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 12. Report to user

```
Created sprint sprint-<NNN>: <name>
  Directory:  $TEAM_SPRINTS/sprint-<NNN>/
  Goal:       <goal | "(none)">
  Duration:   <N> week(s)
  Start:      <start_date>
  End:        <end_date>
  Status:     planning

Next steps:
  /software-house sprint plan --sprint sprint-<NNN> --add <item-id>  add backlog items
  /software-house sprint board --sprint sprint-<NNN>              view the board
  /software-house backlog list                                    find items to add
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- `--name` validation fails -> abort, no log.
- `--duration` invalid -> abort, no log.
- `--start-date` invalid -> abort, no log.
- `mkdir` failure -> report path, abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Partial write during file creation -> clean up created files, log `result: failed`.

## Examples

```
# Create a 2-week sprint with a goal
/software-house sprint create --name "auth-sprint" --duration 2w --goal "Ship user authentication MVP"

# Create a 1-week spike sprint starting on a specific date
/software-house sprint create --name "research-caching" --duration 1w --start-date 2026-05-12

# Create a 4-week sprint with no goal
/software-house sprint create --name "q2-delivery" --duration 4w
```