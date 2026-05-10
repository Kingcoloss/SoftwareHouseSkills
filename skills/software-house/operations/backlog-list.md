# Operation: backlog-list -- list backlog items

**Risk tier:** 1 (read-only)

**Required reading first:** `operations/_shared.md`

## Purpose

Render the product backlog as a filtered, sorted markdown table. No state changes, no confirmation, no audit log entry.

## Invocation patterns

| Command | Behavior |
|---|---|
| `backlog list` | List all open backlog items |
| `backlog list --status open` | List only open items (default) |
| `backlog list --status in-sprint` | List items currently in a sprint |
| `backlog list --status closed` | List completed/closed items |
| `backlog list --status all` | List items regardless of status |
| `backlog list --type <type>` | Filter by type: bug, feature, task, spike |
| `backlog list --assignee <name>` | Filter by assignee |
| `backlog list --status all --type feature` | Combine filters |

Any combination of `--status`, `--type`, and `--assignee` may be used together.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--status` | no | One of `open`, `in-sprint`, `closed`, `all`; default: `open` |
| `--type` | no | One of `bug`, `feature`, `task`, `spike` |
| `--assignee` | no | Must match `^[a-z][a-z0-9-]{0,63}$` if given |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. `$TEAM_BACKLOG` exists. If not, print: `No backlog found. Run /software-house backlog add to create the first item.` and stop.

## Step-by-step protocol

### 1. Validate inputs

If `--status` is given, validate it is one of `open`, `in-sprint`, `closed`, `all`. Abort on invalid value: `Error: --status must be one of: open, in-sprint, closed, all. Got: <value>.`

If `--type` is given, validate it is one of `bug`, `feature`, `task`, `spike`. Abort on invalid value: `Error: --type must be one of: bug, feature, task, spike. Got: <value>.`

If `--assignee` is given, validate against `^[a-z][a-z0-9-]{0,63}$`. Do not validate that the agent exists (the list may show items assigned to former agents).

### 2. Read backlog file

Read `$TEAM_BACKLOG`. Parse the markdown table rows. Each row has columns:

`| ID | Title | Type | Priority | Assignee | Story Points | Status | Created |`

Skip the header row and separator row (`|----|`).

### 3. Filter

Apply filters in order:

1. **Status filter**: If `--status` is not `all`, keep only rows whose Status column matches the filter value. `open` matches `open`, `in-sprint` matches `in-sprint`, `closed` matches `closed`.
2. **Type filter**: If `--type` is given, keep only rows whose Type column matches.
3. **Assignee filter**: If `--assignee` is given, keep only rows whose Assignee column matches the given name (or is empty if filtering for unassigned, though this is not a supported flag).

### 4. Sort

Sort filtered items by Priority descending (highest priority first), then by Created date ascending (oldest first within same priority).

### 5. Render

Print the table:

```
# Product Backlog -- <team-name> (filter: <status> | type: <type | all> | assignee: <name | all>)

| ID | Title | Type | Priority | Assignee | Story Pts | Status | Created |
|----|-------|------|----------|----------|-----------|--------|---------|
| item-001 | User authentication flow | feature | 5 | alice | 8 | open | 2026-05-01 |
| item-003 | Fix login crash on mobile | bug | 10 | bob | 3 | open | 2026-05-02 |
```

If no items match the filter, print the table headers with a single row: `(no items)`.

### 6. Summary line

End with a one-line summary:

```
<N> item(s) shown (of <total> total in backlog)
```

Where `<total>` is the total number of items in the backlog regardless of filter.

## Empty states

- `$TEAM_DIR` not found -> tell the user to run `/software-house init` first.
- `$TEAM_BACKLOG` does not exist -> tell the user to run `/software-house backlog add` to create the first item.
- Zero items match the filter -> print empty table with `(no items)` row.

## Performance

If the backlog has many items (>200), prefer reading only the table section rather than the entire file body. Skip any content before the first `|` table row.

## Output style

- Match the user's language (Thai or English).
- Use markdown tables.
- Truncate long titles to 50 characters -- the user can run `/software-house show` or inspect the backlog file for full detail.
- Unassigned items show `-` in the Assignee column.
- Unestimated items show `-` in the Story Points column.