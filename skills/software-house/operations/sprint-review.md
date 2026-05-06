# Operation: sprint-review -- write sprint review

**Risk tier:** 2 (additive -- writes or overwrites review.md with computed stats)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Write or overwrite the sprint review file for a sprint. Computes statistics from the sprint board (items done vs. total, story points completed vs. total) and writes a structured review. Optionally includes demo notes and stakeholder feedback. The review captures the quantitative outcome of the sprint.

## Invocation patterns

| Command | Behavior |
|---|---|
| `sprint review --sprint <id>` | Generate review with computed stats only |
| `sprint review --sprint <id> --demo "<text>"` | Include demo/presentation notes |
| `sprint review --sprint <id> --feedback "<text>"` | Include stakeholder feedback |
| `sprint review --sprint <id> --demo "<text>" --feedback "<text>"` | Include both |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--sprint` | yes | Must match `^sprint-\d{3}$` and exist under `$TEAM_SPRINTS` |
| `--demo` | no | Free-form text; max 5000 characters |
| `--feedback` | no | Free-form text; max 5000 characters |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. Sprint must exist. If not, refuse: `Error: sprint <id> not found. Run /software-house sprint create to create a sprint first.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--sprint` matches `^sprint-\d{3}$`. Check that `$TEAM_SPRINTS/<id>/sprint.md` exists. Abort if not found.

If `--demo` is given, verify it is non-empty.

If `--feedback` is given, verify it is non-empty.

### 2. Compute sprint statistics

Read `$TEAM_SPRINTS/<sprint>/board.md`. Count items in each column:

- `todo_count` -- items in Todo
- `in_progress_count` -- items in In Progress
- `review_count` -- items in Review
- `done_count` -- items in Done

Read `$TEAM_SPRINTS/<sprint>/sprint.md` frontmatter for:

- `total_items`
- `total_story_points`

Compute:

```
completion_pct = (done_count / total_items) * 100  (rounded to 1 decimal)
story_points_done = sum of story points for items in Done column
story_points_pct = (story_points_done / total_story_points) * 100  (if total > 0, else 0)
velocity = story_points_done  (simple story-point velocity for this sprint)
```

If any items lack story point estimates, note: `(N items unestimated)`.

### 3. Tier-2 confirmation

Build the summary:

```
I will write the sprint review for <sprint-id>:
  Items completed:  <done_count> / <total_items> (<completion_pct>%)
  Story points:    <story_points_done> / <total_story_points> (<story_points_pct>%)
  Velocity:        <story_points_done> pts
  Demo notes:      <provided | "(none)">
  Feedback:        <provided | "(none)">
  Review file:     $TEAM_SPRINTS/<sprint>/review.md
  Audit log:       $AUDIT_LOG
```

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 4. Write review.md

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Write `$TEAM_SPRINTS/<sprint>/review.md`. If the file already exists, use the atomic write pattern from `_shared.md section 6`. If new, write directly.

```markdown
---
type: sprint-review
sprint_id: <sprint-id>
status: completed
reviewed_at: <utc-date YYYY-MM-DD>
total_items: <total>
items_completed: <done_count>
completion_pct: <completion_pct>
total_story_points: <total_sp>
story_points_completed: <sp_done>
story_points_pct: <sp_pct>
velocity: <sp_done>
---

# Sprint Review -- <sprint-id>

## Summary

- Items completed: <done_count> / <total_items> (<completion_pct>%)
- Story points completed: <sp_done> / <total_sp> (<sp_pct>%)
- Sprint velocity: <sp_done> story points
- Items remaining: <total_items - done_count> (<todo_count> todo, <in_progress_count> in-progress, <review_count> in review)

## Completed Items

<List each item in the Done column>
- [<item-id>] <title> [<type>] (<story-points> pts)

## Incomplete Items

<List each item NOT in the Done column with its current status>
- [<item-id>] <title> [<type>] -- status: <column>

## Demo

<demo text, or "(No demo notes provided.)">

## Stakeholder Feedback

<feedback text, or "(No feedback provided.)">

## Recommendations

- <If items remain in todo>: Consider whether incomplete items should roll over to the next sprint or return to the backlog.
- <If items remain in in-progress>: Review blocked items and address carry-over.
- <If velocity is 0>: Sprint produced no completed work. Conduct a retrospective to identify systemic issues.
```

### 5. Update sprint status

Using the atomic write pattern from `_shared.md section 6`, update `$TEAM_SPRINTS/<sprint>/sprint.md` frontmatter:

```yaml
status: review
items_completed: <done_count>
story_points_completed: <sp_done>
updated_at: <utc-date YYYY-MM-DD>
```

### 6. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-review","scope":"team:<team>","args":{"sprint_id":"<id>","items_completed":<done_count>,"total_items":<total>,"story_points_completed":<sp_done>,"total_story_points":<total_sp>,"velocity":<sp_done>,"has_demo":<bool>,"has_feedback":<bool>},"diff":{"updated":["$TEAM_SPRINTS/<sprint>/review.md","$TEAM_SPRINTS/<sprint>/sprint.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

If `review.md` was newly created (not overwriting), use `"diff":{"created":["$TEAM_SPRINTS/<sprint>/review.md"],"updated":["$TEAM_SPRINTS/<sprint>/sprint.md"]}`.

### 7. Report to user

```
Sprint review written for <sprint-id>
  Items completed:  <done_count> / <total_items> (<completion_pct>%)
  Story points:     <sp_done> / <total_sp> (<sp_pct>%)
  Velocity:         <sp_done> pts
  Review file:      $TEAM_SPRINTS/<sprint>/review.md

Next steps:
  /software-house sprint retro --sprint <sprint-id>    write the retrospective
  /software-house sprint board --sprint <sprint-id>    review final board state
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- Sprint not found -> abort, no log.
- Board file missing or malformed -> abort: `Error: cannot read board for sprint <id>. Verify $TEAM_SPRINTS/<sprint>/board.md exists and is valid.`, no log.
- `--demo` or `--feedback` empty -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Generate a review with computed stats only
/software-house sprint review --sprint sprint-001

# Generate a review with demo notes
/software-house sprint review --sprint sprint-001 \
  --demo "Demonstrated user authentication flow and password reset. All core paths working."

# Generate a review with both demo and feedback
/software-house sprint review --sprint sprint-001 \
  --demo "Showed completed auth module, login, and registration flows." \
  --feedback "Stakeholders approved the auth flow. Requested MFA support in next sprint."
```