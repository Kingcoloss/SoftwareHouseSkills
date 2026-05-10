# Operation: sprint-standup -- record a standup note

**Risk tier:** 2 (additive -- appends a timestamped entry to standups.md)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Record a daily standup entry for an agent on a sprint. Appends a timestamped block to the standups file (`$TEAM_SPRINTS/<sprint>/standups.md`). Each entry captures what the agent completed, what they are working on, and any blockers.

## Invocation patterns

| Command | Behavior |
|---|---|
| `sprint standup --sprint <id> --agent <name> --done "<text>" --doing "<text>" --blockers "<text>"` | Record a full standup entry |

All three content flags (`--done`, `--doing`, `--blockers`) are required for a complete standup entry.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--sprint` | yes | Must match `^sprint-\d{3}$` and exist under `$TEAM_SPRINTS` |
| `--agent` | yes | Must match `^[a-z][a-z0-9-]{0,63}$`; agent should exist in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/` |
| `--done` | yes | Non-empty string; max 1000 characters |
| `--doing` | yes | Non-empty string; max 1000 characters |
| `--blockers` | yes | Non-empty string; use "none" if no blockers; max 1000 characters |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. Sprint must exist. If not, refuse: `Error: sprint <id> not found. Run /software-house sprint create to create a sprint first.`
3. Sprint must not be `closed`. Refuse: `Error: sprint <id> is closed. Cannot add standup notes to a closed sprint.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--sprint` matches `^sprint-\d{3}$`. Check that `$TEAM_SPRINTS/<id>/sprint.md` exists. Abort if not found.

Validate `--agent` against `^[a-z][a-z0-9-]{0,63}$`. Warn (but do not abort) if the agent is not found in `$TEAM_AGENTS/` or `$AGENTS_GLOBAL/`: `Warning: agent <name> not found in team or global agents. Standup will still be recorded.`

Validate `--done`, `--doing`, and `--blockers` are all non-empty. Abort if any is empty: `Error: --done, --doing, and --blockers are all required. Use "none" for blockers if there are none.`

### 2. Tier-2 confirmation

Build the summary:

```
I will add the following standup entry:
  Sprint:    <sprint-id>
  Agent:     <name>
  Done:      <done text>
  Doing:     <doing text>
  Blockers:  <blockers text>
  Standups file: $TEAM_SPRINTS/<sprint>/standups.md
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

### 3. Append standup entry

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Read `$TEAM_SPRINTS/<sprint>/standups.md`. Using the atomic write pattern from `_shared.md section 6`, append the entry at the end of the file body (before the closing if any, otherwise at the very end):

```markdown
## <utc-date YYYY-MM-DD> -- <agent-name>

**Done:** <done text>

**Doing:** <doing text>

**Blockers:** <blockers text>

---
```

The `---` separator is placed between entries for visual clarity. Do not add a trailing separator after the last entry.

### 4. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-standup","scope":"team:<team>","args":{"sprint_id":"<id>","agent":"<name>","done":"<done>","doing":"<doing>","blockers":"<blockers>"},"diff":{"updated":["$TEAM_SPRINTS/<sprint>/standups.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 5. Report to user

```
Recorded standup for <agent-name> on <sprint-id>
  Date:      <utc-date YYYY-MM-DD>
  Done:      <done text>
  Doing:     <doing text>
  Blockers:  <blockers text>
  File:      $TEAM_SPRINTS/<sprint>/standups.md

Next steps:
  /software-house sprint board --sprint <sprint-id>     view the board
  /software-house sprint review --sprint <sprint-id>    write a review
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- Sprint not found -> abort, no log.
- Sprint is closed -> refuse, no log.
- `--agent` validation fails -> abort, no log.
- Any content flag empty -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Record a standup with no blockers
/software-house sprint standup --sprint sprint-001 --agent alice \
  --done "Completed user auth module, wrote tests" \
  --doing "Starting API endpoint for password reset" \
  --blockers "none"

# Record a standup with a blocker
/software-house sprint standup --sprint sprint-001 --agent bob \
  --done "Investigated login crash, found root cause" \
  --doing "Writing fix for mobile viewport handling" \
  --blockers "Waiting for design team to confirm layout spec"

# Record a standup for a spike
/software-house sprint standup --sprint sprint-002 --agent carol \
  --done "Evaluated Redis vs Memcached, wrote comparison notes" \
  --doing "Running load tests on Redis cluster" \
  --blockers "Redis cluster provisioning is delayed"
```