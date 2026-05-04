# Operation: fire -- remove an agent (archive, never delete)

**Risk tier:** 4 (destructive -- moves files to archive, removes adapters, updates org-chart)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Remove an agent from active service. Per `safety.md §6` and `safety.md §9`, a two-step typed confirmation is required: Step 1 discloses the full impact and asks for an affirmative, Step 2 requires the literal token `CONFIRM <name>`. Files are never deleted -- the canonical agent file is moved to an archive path with a timestamp suffix. All per-harness adapters are moved to `$SH_HOME/.trash/` with a timestamp suffix (mv-to-temp pattern) instead of being removed outright. Org-chart and roster are updated. An audit line is appended including the verbatim typed token.

Bypass flags (`--dangerously-skip-permissions`, `--yolo`, etc.) do NOT bypass the Tier-4 confirmation gate. The two-step typed token is the only valid authorization path.

## Invocation patterns

| Command | Behavior |
|---|---|
| `fire <name>` | Fire agent from project team (auto-detected scope) |
| `fire <name> --team <team>` | Fire agent from a specific team |
| `fire <name> --pool` | Fire agent from the freelance pool |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` |
| `--team` | no | Override team scope |
| `--pool` | no | Target freelance pool agent |

## Preconditions

1. `$COMPANY_HOME` exists.
2. The canonical agent file must exist at the resolved path. If not: `Error: agent <name> not found.`
3. The agent must have `status: active`, `status: onboarding`, or `status: transfer`. If `status: alumni`, refuse: `Error: <name> is already archived (status: alumni). Use /software-house list --alumni to inspect.`

## Archive paths

Per `safety.md §6`, tier-4 operations use these standard archive paths:

| Artifact | Archive path |
|---|---|
| Canonical agent file (project scope) | `$TEAM_DIR/archive/agents/<name>-<utc-timestamp>.md` |
| Canonical agent file (freelance pool) | `$AGENTS_GLOBAL/_archived/<name>-<utc-timestamp>.md` |
| Onboard briefing sidecar | Same archive dir: `<name>-<utc-timestamp>.onboard.md` |
| Wiki people page | `$ALUMNI/<name>.md` (standard alumni path per safety.md §6) |

The timestamp format is `YYYYMMDDTHHMMSSZ` (compact UTC, safe for filenames).

Restore command (printed during impact disclosure):

```
# To restore a fired agent:
mv '<archive-path>' '<original-canonical-path>'
mv '$ALUMNI/<name>.md' '$WIKI_PEOPLE/<name>.md'
# Then re-run: /software-house onboard <name>
```

## Step-by-step protocol

### 1. Resolve scope and locate files

Determine canonical path (same logic as `hire` scope resolution):
- `--pool` -> `$AGENTS_GLOBAL/<name>.md`
- `--team <t>` -> `<project>/.software-house/agents/<name>.md`
- Auto-detect from `pwd`

Read the canonical agent file. Parse frontmatter to extract: `role`, `provider`, `model`, `team`, `department`, `status`, `classification`, `hired_at`.

Check preconditions. Abort if not met.

Determine which adapters exist. For each harness directory present under the project root:
- Claude Code: `$PROJECT/.claude/agents/<name>.md`
- Codex CLI: `$PROJECT/.codex/agents/<name>.md`
- Gemini CLI: `$PROJECT/.gemini/extensions/<name>/` (directory)

Collect any sidecar file: `<canonical-dir>/<name>.onboard.md`.

### 2. Compute full impact

Collect:
- Files to archive (canonical, wiki page, sidecar)
- Adapter files to move to `$SH_HOME/.trash/` with timestamp suffix (mv-to-temp pattern, not rm)
- Roster entries to remove (`$TEAM_ROSTER` member line)
- Team wiki entry to update (`$WIKI_TEAMS/<team>.md`: remove from `members` list)
- Department index to update (if `department` field is set)
- OKR assignments: Grep `$TEAM_DIR/okrs/` for `owner: <name>`; list any found as broken references
- `reports_to` references: Grep `$WIKI_PEOPLE/` and `$TEAM_AGENTS/` for `reports_to: <name>`; list any found

Compute the `<utc-timestamp>` for archive filenames:

```
date -u +"%Y%m%dT%H%M%SZ"
```

Build archive paths:
- Canonical archive: `$TEAM_DIR/archive/agents/<name>-<utc-timestamp>.md`
  (For pool: `$AGENTS_GLOBAL/_archived/<name>-<utc-timestamp>.md`)
- Sidecar archive: `$TEAM_DIR/archive/agents/<name>-<utc-timestamp>.onboard.md`
  (only if sidecar exists)
- Wiki archive: `$ALUMNI/<name>.md`

### 3. Tier-4 step 1 -- impact disclosure

Print the full impact summary:

```
Impact of firing <name>:

  FILES TO ARCHIVE (recoverable):
    <canonical path>
      -> <archive path>
    $WIKI_PEOPLE/<name>.md
      -> $ALUMNI/<name>.md
    <sidecar path if exists>
      -> <sidecar archive path>

  ADAPTERS TO MOVE TO TRASH (auto-generated, recoverable from $SH_HOME/.trash/):
    <list each adapter path, one per line, or "(none detected)">

  ROSTER UPDATES:
    $TEAM_ROSTER: remove member line for <name>
    $WIKI_TEAMS/<team>.md: remove <name> from members list

  BROKEN REFERENCES (require manual fix after firing):
    <list of OKR files with owner: <name>, or "(none)">
    <list of agent files with reports_to: <name>, or "(none)">

  RESTORE COMMAND:
    mv '<archive path>' '<canonical path>'
    mv '$ALUMNI/<name>.md' '$WIKI_PEOPLE/<name>.md'
    # Then re-run: /software-house onboard <name>
```

Print the Tier-4 step-1 prompt (exact wording from `safety.md §3`):

```
+----------------------------------------------------------+
| Destructive operation on <name>.                         |
| Files will be MOVED to archive (recovery path printed).  |
| Reply 'yes' to advance to the typed-token step.          |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. No log entry. No changes.

### 4. Tier-4 step 2 -- typed token

Print the Tier-4 step-2 prompt (exact wording from `safety.md §3`):

```
+----------------------------------------------------------+
| To proceed, type the literal token on the next line:     |
|   CONFIRM <name>                                         |
| Anything else, or no response, will cancel.              |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- The literal string `CONFIRM <name>` (case-sensitive, exact spacing) must appear in the message.
- `CONFIRM Alice` instead of `CONFIRM alice` -> REJECTED.
- Extra surrounding text is permitted; the token presence alone suffices.

If token absent, abort. Tell the user nothing happened. Do not log.

If token present, proceed to Step 5.

### 5. Create archive directories

```
mkdir -p $TEAM_DIR/archive/agents/   (or $AGENTS_GLOBAL/_archived/)
```

This is idempotent and local.

### 6. Archive canonical agent file

Update the canonical agent file's frontmatter using the atomic write pattern before moving:

```yaml
status: alumni
fired_at: <utc-date YYYY-MM-DD>
```

Then move:

```
mv <canonical path> <archive path>
```

### 7. Archive wiki people page

If `$WIKI_PEOPLE/<name>.md` exists:
- Update frontmatter: `status: alumni`, `fired_at: <utc-date>` (atomic write)
- Move: `mv $WIKI_PEOPLE/<name>.md $ALUMNI/<name>.md`

### 8. Archive onboard sidecar

If `<canonical-dir>/<name>.onboard.md` exists:

```
mv <canonical-dir>/<name>.onboard.md <sidecar archive path>
```

### 9. Remove harness adapters (mv-to-temp pattern)

Adapters are auto-generated shims with no unique content, but they may be needed for accidental-deletion recovery. Instead of immediate removal, move adapter files to a temp/trash directory with a timestamp suffix.

Create the trash directory if it does not exist:

```
mkdir -p $SH_HOME/.trash/
```

For each adapter path that exists:

- Claude Code adapter: `mv $PROJECT/.claude/agents/<name>.md $SH_HOME/.trash/<name>.claude.md-<utc-timestamp>`
- Codex CLI adapter: `mv $PROJECT/.codex/agents/<name>.md $SH_HOME/.trash/<name>.codex.md-<utc-timestamp>`
- Gemini CLI extension dir: `mv $PROJECT/.gemini/extensions/<name>/ $SH_HOME/.trash/<name>.gemini-<utc-timestamp>/`

The `<utc-timestamp>` format is `YYYYMMDDTHHMMSSZ` (same compact UTC format used for archive filenames).

The `$SH_HOME/.trash/` directory can be periodically cleaned by the user. It is not managed by any operation -- the user may delete its contents at any time. Adapters in `.trash/` are no longer active and will not be picked up by any harness. Moving adapters to `.trash/` instead of removing them enables accidental-deletion recovery: if a fired agent is restored, the adapters can be moved back from `.trash/` to their original locations.

**Note:** If the `$SH_HOME/.trash/` directory already contains entries for the same agent name, the timestamp suffix ensures no collision.

### 10. Update roster and team wiki

Using atomic write pattern:
- Remove the member line for `<name>` from `$TEAM_ROSTER`.
- Remove `<name>` from the `members` list in `$WIKI_TEAMS/<team>.md`.
- Update the `updated_at` field in `$WIKI_TEAMS/<team>.md` frontmatter to the current UTC date.

If `department` field was set on the agent, also update `$DEPARTMENTS_HOME/<dept>/agents/` index if it exists (remove agent entry).

### 11. Rebuild indexes

Rebuild `$TEAM_INDEX` and `$COMPANY_INDEX` per `_shared.md §8`.

### 12. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"fire","scope":"team:<team>","args":{"name":"<name>","team":"<team|null>","pool":<bool>},"diff":{"archived":["<canonical archive path>","<wiki archive path>","<sidecar archive path if any>"],"updated":["$TEAM_ROSTER","$WIKI_TEAMS/<team>.md","$TEAM_INDEX","$COMPANY_INDEX"],"trashed":["<adapter trash paths>"]},"confirmation":{"tier":4,"prompt":"<exact step-1 box text>","response":"<user step-1 verbatim>","ts":"<utc-step-1>","token":"CONFIRM <name>","token_ts":"<utc-step-2>"},"egress_consent":{"required":false},"result":"ok"}
```

The `confirmation.token` field records the verbatim typed CONFIRM token per `safety.md §8`.

### 13. Report to user

```
Fired <name>
  Archived canonical:  <archive path>
  Archived wiki page:  $ALUMNI/<name>.md
  Adapters trashed:   <list or none>
  Roster:              updated (removed from <team>)
  Broken refs:         <list or none -- manual fix required>

To restore:
  mv '<archive path>' '<canonical path>'
  mv '$ALUMNI/<name>.md' '$WIKI_PEOPLE/<name>.md'
  # Restore adapters from trash if needed:
  mv '$SH_HOME/.trash/<name>.claude.md-<timestamp>' '$PROJECT/.claude/agents/<name>.md'
  /software-house onboard <name>

Note: $SH_HOME/.trash/ can be periodically cleaned. Trashed adapters are not active.
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent already alumni -> refuse before any gate; no log.
- Step-1 non-affirmative -> abort; no log; no changes.
- Step-2 token absent or malformed -> abort; no log; no changes. The step-1 affirmative is consumed and cannot be reused; user must restart the `fire` command from the beginning.
- `mv` failure (permissions) -> print which command failed; roll back any partial moves by reversing the `mv` commands already done; log `result: failed`.
- `mv` failure on adapter (to trash) -> log warning in audit entry but do not abort the overall operation; report the path that could not be moved.

## Examples

```
# Fire alice from the current project team (two-step confirmation required)
/software-house fire alice

# Fire bob from a specific team
/software-house fire bob --team api-gateway

# Fire a freelance pool agent
/software-house fire ci-linter --pool
```
