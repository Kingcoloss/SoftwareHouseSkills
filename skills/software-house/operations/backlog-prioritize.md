# Operation: backlog-prioritize -- reprioritize a backlog item

**Risk tier:** 3 (modifying -- changes priority field and re-sorts backlog rows)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Change the priority of a backlog item and re-sort the backlog table so that higher-priority items appear first. Shows a diff of the changes, confirms per Tier-3 protocol, then updates the backlog file and appends an audit log entry.

## Invocation patterns

| Command | Behavior |
|---|---|
| `backlog prioritize --item <id> --priority N` | Set item priority to N and re-sort backlog |

Only the priority field can be changed with this operation. To change other fields, edit the backlog file directly or remove and re-add the item.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--item` | yes | Must match `^item-\d{3}$` and exist in `$TEAM_BACKLOG` |
| `--priority` | yes | Integer (0 or higher) |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. `$TEAM_BACKLOG` exists. If not, refuse: `Error: backlog not found. Run /software-house backlog add to create the first item.`
3. The item ID must exist in the backlog. If not, refuse: `Error: item <id> not found in backlog.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--item` matches `^item-\d{3}$`. Abort on mismatch: `Error: invalid item ID '<value>'. Expected format: item-NNN (e.g., item-001).`

Validate `--priority` is an integer >= 0. Abort: `Error: --priority must be a non-negative integer. Got: <value>.`

### 2. Read backlog and locate item

Read `$TEAM_BACKLOG`. Parse the markdown table. Locate the row with the matching item ID.

If the item is not found, abort: `Error: item <id> not found in backlog.`

Extract the current priority value from the matching row. Also extract the item title and type for the diff display.

### 3. Compute diff

Build the modification plan:

```
File: $TEAM_BACKLOG
  Row: item-<NNN>
    field priority: <old-priority> -> <new-priority>

  Table will be re-sorted by priority (descending), then created date (ascending).
  Affected rows: <count of rows whose position changes>
```

If the new priority is the same as the old priority, warn: `Note: item <id> already has priority <N>. No change needed.` and ask the user if they want to proceed anyway.

### 4. Tier-3 confirmation

Print the diff from Step 3. Print all file paths that will be modified:

```
I will update the following:
  Backlog file: $TEAM_BACKLOG
  Audit log:    $AUDIT_LOG
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

Using the atomic write pattern from `_shared.md section 6`:

1. Update the priority field in the matching row.
2. Update the frontmatter `updated_at` field.
3. Re-sort all table rows by priority descending (highest first), then by Created date ascending (oldest first within same priority).
4. Write to `$TEAM_BACKLOG.tmp`, verify the markdown table parses correctly, then `mv $TEAM_BACKLOG.tmp $TEAM_BACKLOG`.

### 6. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"backlog-prioritize","scope":"team:<team>","args":{"item_id":"<id>","old_priority":<old>,"new_priority":<new>},"diff":{"updated":["$TEAM_BACKLOG"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 7. Report to user

```
Updated priority for item-<NNN>
  Title:        <title>
  Priority:     <old-priority> -> <new-priority>
  Backlog file: $TEAM_BACKLOG

Next steps:
  /software-house backlog list                 view re-sorted backlog
  /software-house sprint plan --sprint <id> --add item-<NNN>  add to sprint
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- `$TEAM_BACKLOG` does not exist -> refuse, suggest `backlog add`, no log.
- Invalid item ID format -> abort, no log.
- Item ID not found in backlog -> abort, no log.
- `--priority` not a non-negative integer -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Set item-003 to highest priority
/software-house backlog prioritize --item item-003 --priority 20

# Lower priority of a bug
/software-house backlog prioritize --item item-001 --priority 2

# Set a spike to medium priority
/software-house backlog prioritize --item item-007 --priority 5
```