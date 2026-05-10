# Operation: sprint-retro -- write sprint retrospective

**Risk tier:** 2 (additive -- writes or overwrites retro.md)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Write or overwrite the sprint retrospective file for a sprint. Captures what went well, what could be improved, and action items for the next sprint. This is the team's reflection step. The retro file is overwritten on each invocation (a retrospective represents the team's latest assessment, not an append-only log).

## Invocation patterns

| Command | Behavior |
|---|---|
| `sprint retro --sprint <id> --went-well "<text>" --improve "<text>" --action-items "<text>"` | Write a full retrospective |

All three content flags are required. A retrospective without any of the three sections is incomplete and will be refused.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--sprint` | yes | Must match `^sprint-\d{3}$` and exist under `$TEAM_SPRINTS` |
| `--went-well` | yes | Non-empty string; max 5000 characters |
| `--improve` | yes | Non-empty string; max 5000 characters |
| `--action-items` | yes | Non-empty string; max 5000 characters |

## Preconditions

1. `$TEAM_DIR` exists (project team is initialized). If not, refuse: `Error: team directory not found. Run /software-house init first or navigate to a project with a team.`
2. Sprint must exist. If not, refuse: `Error: sprint <id> not found. Run /software-house sprint create to create a sprint first.`

## Step-by-step protocol

### 1. Validate inputs

Validate `--sprint` matches `^sprint-\d{3}$`. Check that `$TEAM_SPRINTS/<id>/sprint.md` exists. Abort if not found.

Validate `--went-well`, `--improve`, and `--action-items` are all non-empty. Abort if any is empty: `Error: --went-well, --improve, and --action-items are all required.`

### 2. Tier-2 confirmation

Build the summary:

```
I will write the sprint retrospective for <sprint-id>:
  Went well:     <went-well text (first 80 chars)>
  Improve:       <improve text (first 80 chars)>
  Action items:  <action-items text (first 80 chars)>
  Retro file:    $TEAM_SPRINTS/<sprint>/retro.md
  Audit log:     $AUDIT_LOG
```

If retro.md already exists, add: `(This will overwrite the existing retrospective.)`

Print the Tier-2 prompt from `safety.md section 3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md section 9`. If non-affirmative, abort. Do not log.

### 3. Write retro.md

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Write `$TEAM_SPRINTS/<sprint>/retro.md`. If the file already exists, use the atomic write pattern from `_shared.md section 6`. If new, write directly.

```markdown
---
type: sprint-retro
sprint_id: <sprint-id>
status: completed
retro_at: <utc-date YYYY-MM-DD>
---

# Sprint Retrospective -- <sprint-id>

## What went well

<went-well text>

## What could be improved

<improve text>

## Action items for next sprint

<action-items text>
```

### 4. Update sprint status

Using the atomic write pattern from `_shared.md section 6`, update `$TEAM_SPRINTS/<sprint>/sprint.md` frontmatter:

```yaml
status: retrospective
updated_at: <utc-date YYYY-MM-DD>
```

Note: if the review has not been written yet, set status to `retrospective` anyway. The full sprint lifecycle is: `planning -> active -> review -> retrospective -> closed`. Operations may be run out of order.

### 5. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"sprint-retro","scope":"team:<team>","args":{"sprint_id":"<id>","went_well":"<went-well>","improve":"<improve>","action_items":"<action-items>"},"diff":{"updated":["$TEAM_SPRINTS/<sprint>/retro.md","$TEAM_SPRINTS/<sprint>/sprint.md"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

If `retro.md` was newly created, use `"diff":{"created":["$TEAM_SPRINTS/<sprint>/retro.md"],"updated":["$TEAM_SPRINTS/<sprint>/sprint.md"]}`.

### 6. Report to user

```
Sprint retrospective written for <sprint-id>
  Went well:     <went-well text (first 80 chars)>
  Improve:       <improve text (first 80 chars)>
  Action items:  <action-items text (first 80 chars)>
  Retro file:    $TEAM_SPRINTS/<sprint>/retro.md

Next steps:
  /software-house sprint create --name <name> --duration Nw   start next sprint
  /software-house sprint plan --sprint <next-sprint> --add <item-id>  plan next sprint
  /software-house backlog list    review backlog for next sprint
```

## Failure modes

- `$TEAM_DIR` not found -> refuse, no log.
- Sprint not found -> abort, no log.
- Any content flag empty -> abort, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Write a retrospective with all sections
/software-house sprint retro --sprint sprint-001 \
  --went-well "Team velocity improved. Auth module delivered on time. Good collaboration on code reviews." \
  --improve "Too many items in progress at once. Need better sprint planning. Standup attendance inconsistent." \
  --action-items "Limit WIP to 2 items per person. Add estimation to all backlog items before sprint planning. Set standup reminder."

# Write a brief retrospective
/software-house sprint retro --sprint sprint-002 \
  --went-well "Research spike completed. Clear decision on caching strategy." \
  --improve "Spike took longer than estimated. Should have broken it into smaller pieces." \
  --action-items "Break spikes into smaller time-boxed investigations. Update story point guidance for spikes."
```