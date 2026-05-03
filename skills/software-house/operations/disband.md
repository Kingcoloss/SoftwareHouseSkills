# Operation: disband -- remove an entire team (archive, never delete)

**Risk tier:** 4 (destructive -- archives entire team, removes adapters, updates multiple agents)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Archive an entire team. The team directory, wiki page, and all associated adapters are moved to archive paths. Every agent that has `team: <team>` is updated to `team: null` and `status: transfer`. The team is removed from its department's teams list. Per `safety.md §6` and `safety.md §9`, a two-step typed confirmation is required: Step 1 discloses the full impact and asks for an affirmative, Step 2 requires the literal token `CONFIRM <team-name>`.

Bypass flags (`--dangerously-skip-permissions`, `--yolo`, etc.) do NOT bypass the Tier-4 confirmation gate. The two-step typed token is the only valid authorization path.

## Invocation patterns

| Command | Behavior |
|---|---|
| `disband <team>` | Disband team with two-step confirmation |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `team` | yes | Must match `^[a-z][a-z0-9-]{0,63}$`; must exist in `$WIKI_TEAMS` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The team must exist in `$WIKI_TEAMS/<team>.md`. If not, refuse: `Error: team <team> not found. Run /software-house list teams to see available teams.`
3. The team's `status` must be `active`. If `status: disbanded`, refuse: `Error: team <team> is already disbanded.`

## Archive paths

Per `safety.md §6`, tier-4 operations use these standard archive paths:

| Artifact | Archive path |
|---|---|
| Team directory | `$TEAM_DIR/../archive/teams/<team>-<utc-timestamp>/` |
| Team wiki page | `$WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md` |

The timestamp format is `YYYYMMDDTHHMMSSZ` (compact UTC, safe for filenames).

Restore command (printed during impact disclosure):

```
# To restore a disbanded team:
mv '<team-dir-archive-path>' '<original-team-dir-path>'
mv '$WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md' '$WIKI_TEAMS/<team>.md'
# Then for each affected agent, restore team field:
# /software-house transfer <agent> --to <team>
# Then rebuild indexes:
# /software-house list
```

## Step-by-step protocol

### 1. Validate inputs and locate team

Validate `team` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

Read `$WIKI_TEAMS/<team>.md`. Parse frontmatter. Extract: `department`, `project_path`, `lead`, `members`, `status`.

Check preconditions. Abort if team not found or already disbanded.

Determine the project root from `$PROJECTS_INDEX` or from the `project_path` field in the team's wiki page.

### 2. Collect all affected agents

For each agent name in the `members` list:

1. Find the canonical agent file:
   - Check `$TEAM_AGENTS/<member>.md` (project scope).
   - If not found, check `$AGENTS_GLOBAL/<member>.md` (freelance scope).

2. Read each agent's frontmatter. Extract: `role`, `provider`, `model`, `status`, `employment`, `hired_by_teams`, `secondary_teams`, `reports_to`.

3. Collect adapter paths for each member:
   - Claude Code: `$PROJECT/.claude/agents/<member>.md`
   - Codex CLI: `$PROJECT/.codex/agents/<member>.md`
   - Gemini CLI: `$PROJECT/.gemini/extensions/<member>/` (directory)

Also search `$WIKI_PEOPLE/` and `$TEAM_AGENTS/` for agents with `reports_to: <lead>` or `reports_to: <member>` for any member -- these are direct reports that may be affected.

### 3. Compute full impact

Collect all impact items:

```
FILES TO ARCHIVE (recoverable):
  $TEAM_DIR (entire team directory)
    -> $TEAM_DIR/../archive/teams/<team>-<utc-timestamp>/
  $WIKI_TEAMS/<team>.md
    -> $WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md

ADAPTERS TO REMOVE (auto-generated, recreated by re-hire):
  <for each member, list adapter paths, one per line>
  <or "(none detected)">

AGENTS TO UPDATE (team field set to null, status set to transfer):
  <for each member:>
    <member> (<role>) -- team: <team> -> null, status: <current> -> transfer
    <adapter paths for this member>

DEPARTMENT UPDATES:
  $WIKI_DEPTS/<department>.md -- remove <team> from teams list
  <or "(no department assigned)">

PROJECT INDEX UPDATE:
  $PROJECTS_INDEX -- remove project mapping for <team>
```

Compute the `<utc-timestamp>` for archive filenames:

```
date -u +"%Y%m%dT%H%M%SZ"
```

### 4. Tier-4 step 1 -- impact disclosure

Print the full impact summary from Step 3:

```
Impact of disbanding team <team>:

  FILES TO ARCHIVE (recoverable):
    <list of archive source -> destination>

  ADAPTERS TO REMOVE (auto-generated, recreated by re-hire):
    <list or "(none detected)">

  AGENTS TO UPDATE (team -> null, status -> transfer):
    <list of all affected members with current role and status>

  BROKEN REFERENCES (require manual fix after disbanding):
    <list of agents with reports_to pointing to team members, or "(none)">
    <list of department references, or "(none)">

  RESTORE COMMAND:
    mv '<team-dir-archive-path>' '<original-team-dir-path>'
    mv '$WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md' '$WIKI_TEAMS/<team>.md'
    # Then for each affected agent, restore team field:
    # /software-house transfer <agent> --to <team>
    # Then rebuild indexes:
    # /software-house list
```

Print the Tier-4 step-1 prompt (exact wording from `safety.md §3`):

```
+----------------------------------------------------------+
| Destructive operation on <team>.                          |
| Files will be MOVED to archive (recovery path printed).  |
| Reply 'yes' to advance to the typed-token step.          |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. No log entry. No changes.

### 5. Tier-4 step 2 -- typed token

Print the Tier-4 step-2 prompt (exact wording from `safety.md §3`):

```
+----------------------------------------------------------+
| To proceed, type the literal token on the next line:     |
|   CONFIRM <team>                                         |
| Anything else, or no response, will cancel.              |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- The literal string `CONFIRM <team>` (case-sensitive, exact spacing) must appear in the message.
- `CONFIRM MyTeam` instead of `CONFIRM my-team` -> REJECTED.
- Extra surrounding text is permitted; the token presence alone suffices.

If token absent, abort. Tell the user nothing happened. Do not log.

If token present, proceed to Step 6.

### 6. Update all affected agents

For each member of the disbanded team:

1. Read the canonical agent file.
2. Using atomic write per `_shared.md §6`, update frontmatter:
   ```yaml
   team: null
   status: transfer
   updated_at: <utc-date YYYY-MM-DD>
   ```
   For freelance agents (employment: freelance), also remove `<team>` from `hired_by_teams` if present.
3. If `$WIKI_PEOPLE/<member>.md` exists, update the same frontmatter fields there using atomic write.

### 7. Update department

If the team has a `department` field that is not `null`:

Read `$WIKI_DEPTS/<department>.md`. Remove `<team>` from the `teams` list in the frontmatter. Update `updated_at: <utc-date>`. Write atomically per `_shared.md §6`.

### 8. Remove all per-harness adapters

For each member of the disbanded team, remove all adapter paths that exist:

- Claude Code adapter: `rm $PROJECT/.claude/agents/<member>.md`
- Codex CLI adapter: `rm $PROJECT/.codex/agents/<member>.md`
- Gemini CLI extension dir: `rm -rf $PROJECT/.gemini/extensions/<member>/`

These are auto-generated shims with no unique content. Removal is safe.

### 9. Create archive directories

```
mkdir -p $TEAM_DIR/../archive/teams/
mkdir -p $WIKI_TEAMS/_archived/
```

This is idempotent and local.

### 10. Archive team directory

Update the team wiki page frontmatter before archiving:

```yaml
status: disbanded
disbanded_at: <utc-date YYYY-MM-DD>
```

Write atomically, then move:

```
mv $TEAM_DIR <TEAM_DIR/../archive/teams/<team>-<utc-timestamp>/
```

### 11. Archive team wiki page

Move the team wiki page:

```
mv $WIKI_TEAMS/<team>.md $WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md
```

### 12. Update projects index

Read `$PROJECTS_INDEX`. Remove the entry mapping the disbanded team to its project. Write atomically per `_shared.md §6`.

### 13. Rebuild company index

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 14. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"disband","scope":"team:<team>","args":{"team":"<team>","members_affected":<count>,"department":"<department|null>"},"diff":{"archived":["<team-dir-archive-path>","<wiki-archive-path>"],"updated":["<list of agent canonical paths>","<list of wiki people paths>","$WIKI_DEPTS/<department>.md","$PROJECTS_INDEX","$COMPANY_INDEX"],"removed":["<list of adapter paths>"]},"confirmation":{"tier":4,"prompt":"<exact step-1 box text>","response":"<user step-1 verbatim>","ts":"<utc-step-1>","token":"CONFIRM <team>","token_ts":"<utc-step-2>"},"egress_consent":{"required":false},"result":"ok"}
```

The `confirmation.token` field records the verbatim typed CONFIRM token per `safety.md §8`.

### 15. Report to user

```
Disbanded team <team>
  Archived team dir:   <team-dir-archive-path>
  Archived wiki page:  $WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md
  Agents updated:      <count> members (team -> null, status -> transfer)
  Adapters removed:    <count> adapter paths
  Department:          <department | "(none)"> updated

Affected agents (status: transfer):
  <member-1> (<role>)
  <member-2> (<role>)
  ...

To restore:
  mv '<team-dir-archive-path>' '<original-team-dir-path>'
  mv '$WIKI_TEAMS/_archived/<team>-<utc-timestamp>.md' '$WIKI_TEAMS/<team>.md'
  # Then for each affected agent, restore team field:
  # /software-house transfer <agent> --to <team>
  # Then rebuild indexes:
  # /software-house list
```

## Failure modes

- Team not found -> refuse before any gate; no log.
- Team already disbanded -> refuse before any gate; no log.
- Step-1 non-affirmative -> abort; no log; no changes.
- Step-2 token absent or malformed -> abort; no log; no changes. The step-1 affirmative is consumed and cannot be reused; user must restart the `disband` command from the beginning.
- `mv` failure (permissions) -> print which command failed; roll back any partial moves by reversing the `mv` commands already done; log `result: failed`.
- `rm` failure on adapter -> log warning in audit entry but do not abort the overall operation; report the path that could not be removed.
- Agent canonical file not found for a listed member -> skip that member with a warning; do not abort the operation.

## Examples

```
# Disband the api-gateway team (two-step confirmation required)
/software-house disband api-gateway

# Disband the legacy-backend team
/software-house disband legacy-backend
```