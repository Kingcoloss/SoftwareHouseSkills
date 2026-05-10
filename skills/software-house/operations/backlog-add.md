# Operation: backlog-add -- add an item to the product backlog

**Risk tier:** 2 (additive -- appends a new row to the backlog table)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Add a new item to the product backlog file (`$TEAM_BACKLOG` = `$TEAM_DIR/backlog.md`). Auto-increments the item ID (`item-NNN`, zero-padded). Appends the item as a new row in the backlog markdown table. Sets the item status to `open` by default.

## Invocation patterns

| Command | Behavior |
|---|---|
| `backlog add --title "<text>"` | Add item with required title, all other fields defaulted |
| `backlog add --title "<text>" --description "<text>"` | Add item with a description |
| `backlog add --title "<text>" --priority N` | Add item with explicit priority (default: 0) |
| `backlog add --title "<text>" --assignee <name>` | Add item pre-assigned to an agent |
| `backlog add --title "<text>" --story-points N` | Add item with story-point estimate |
| `backlog add --title "<text>" --type bug\|feature\|task\|spike` | Add item with type (default: task) |

Any combination of the optional flags may be used together.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--title` | yes | Non-empty string; max 200 characters |
| `--description` | no | Free-form text; max 2000 characters |
| `--priority` | no | Integer (0 or higher); default: 0 |
| `--assignee` | no | Must match `^[a-z][a-z0-9-]{0,63}$`; agent must exist in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/` |
| `--story-points` | no | Positive integer (1 or higher); default: null (unestimated) |
| `--type` | no | One of `bug`, `feature`, `task`, `spike`; default: `task` |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. If `--assignee` is given, the agent must exist. If not, refuse: `Error: agent <name> not found. Run /software-house list people to see available agents.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--title` is non-empty and under 200 characters. Abort if empty: `Error: --title is required and must not be empty.`

If `--priority` is given, validate it is an integer >= 0. Abort if invalid: `Error: --priority must be a non-negative integer. Got: <value>.`

If `--assignee` is given, validate against `^[a-z][a-z0-9-]{0,63}$`. Then check that the agent file exists at `$TEAM_AGENTS/<name>.md` or `$AGENTS_GLOBAL/<name>.md`. Abort if not found.

If `--story-points` is given, validate it is a positive integer. Abort: `Error: --story-points must be a positive integer. Got: <value>.`

If `--type` is given, validate it is one of `bug`, `feature`, `task`, `spike`. Abort on mismatch: `Error: --type must be one of: bug, feature, task, spike. Got: <value>.`

### 2. Resolve or create backlog file

Check if `$TEAM_BACKLOG` exists:

- If it exists, read it and parse the existing table to determine the next item ID.
- If it does not exist, create it with the standard header and empty table. The first item ID will be `item-001`.

### 3. Determine next item ID

Scan existing backlog rows for item IDs matching `item-NNN`. Find the highest NNN. Increment by 1 and zero-pad to 3 digits (e.g., if last was `item-005`, next is `item-006`).

If no items exist, start at `item-001`.

### 4. Get current timestamp

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

### 5. Tier-2 confirmation

Build the summary of what will be created:

```
I will add the following to the product backlog:
  ID:           item-<NNN>
  Title:        <title>
  Type:         <type>
  Priority:     <priority>
  Assignee:     <assignee | unassigned>
  Story points: <story-points | unestimated>
  Status:       open
  Backlog file: $TEAM_BACKLOG
  Audit log:    $AUDIT_LOG
```

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 6. Append item to backlog

If `$TEAM_BACKLOG` does not exist yet, write it with the standard structure:

```markdown
---
type: backlog
team: <team-name>
created_at: <utc-date YYYY-MM-DD>
updated_at: <utc-date YYYY-MM-DD>
---

# Product Backlog

| ID | Title | Type | Priority | Assignee | Story Points | Status | Created |
|----|-------|------|----------|----------|--------------|--------|---------|
| item-<NNN> | <title> | <type> | <priority> | <assignee \| -> | <story-points \| -> | open | <utc-date> |
```

If `$TEAM_BACKLOG` already exists, append a new row to the table. Use the atomic write pattern from `_shared.md section 6` (write to `.tmp`, verify markdown table parses, `mv`).

Update the frontmatter `updated_at` field to the current UTC date.

### 7. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"backlog-add","scope":"team:<team>","args":{"item_id":"item-<NNN>","title":"<title>","type":"<type>","priority":<priority>,"assignee":"<assignee|null>","story_points":<story_points|null>},"diff":{"created":["$TEAM_BACKLOG"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

If backlog already existed, use `"diff":{"updated":["$TEAM_BACKLOG"]}` instead.

### 8. Report to user

```
Added item item-<NNN> to backlog
  Title:        <title>
  Type:         <type>
  Priority:     <priority>
  Assignee:     <assignee | unassigned>
  Story points: <story-points | unestimated>
  Status:       open
  Backlog file: $TEAM_BACKLOG

Next steps:
  /software-house backlog list                 view the backlog
  /software-house backlog prioritize --item item-<NNN> --priority N   set priority
  /software-house sprint plan --sprint <id> --add item-<NNN>  add to sprint
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- `--title` empty or too long -> abort, no log.
- `--type` invalid -> abort, no log.
- `--priority` not a non-negative integer -> abort, no log.
- `--story-points` not a positive integer -> abort, no log.
- `--assignee` agent not found -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Add a feature to the backlog
/software-house backlog add --title "User authentication flow" --type feature --story-points 8

# Add a bug with high priority
/software-house backlog add --title "Login page crashes on mobile" --type bug --priority 10 --assignee alice

# Add a spike for research
/software-house backlog add --title "Evaluate caching strategies" --type spike --description "Research Redis vs Memcached for session storage" --story-points 3

# Add a simple task
/software-house backlog add --title "Update README with setup instructions" --type task
```