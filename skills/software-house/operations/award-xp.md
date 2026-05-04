# Operation: award-xp -- grant XP and trigger level checks

**Risk tier:** 3 (modifying -- updates agent frontmatter xp, level, achievements, and team stats)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Grant XP points to an agent. Add the specified amount to the agent's current `xp` total. After adding XP, check if the agent has crossed a level threshold. If so, auto-level-up: increment `level` by 1 and add an achievement like `level-<N>-reached`. Optionally grant an achievement string. Update the canonical agent file frontmatter and the wiki people page. If team context is available, update team XP totals.

## Invocation patterns

| Command | Behavior |
|---|---|
| `award-xp <name> --amount N` | Award N XP points to the agent |
| `award-xp <name> --amount N --reason "<text>"` | Award XP with a reason (audit log only) |
| `award-xp <name> --amount N --achievement <name>` | Award XP and grant an achievement |
| `award-xp <name> --amount N --team <team>` | Award XP in a specific team context |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--amount` | yes | Positive integer (1 or greater) |
| `--reason` | no | Free-form text; stored in audit log only, not in frontmatter |
| `--achievement` | no | Must match `^[a-z][a-z0-9-]{1,63}$`; no duplicates |
| `--team` | no | Must match an existing entry in `$WIKI_TEAMS` |

## XP thresholds for leveling

| Level | XP required |
|---|---|
| 1 | 0 |
| 2 | 100 |
| 3 | 300 |
| 4 | 600 |
| 5 | 1000 |

Suggested XP award values (configurable via `$MODELS_CONFIG` if extended):

| Activity | XP |
|---|---|
| Task completion | 10 |
| Code review | 15 |
| Bug fix | 20 |
| Feature delivery | 50 |
| OKR key result completed | 30 |
| Mentorship | 25 |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist at `$TEAM_AGENTS/<name>.md` (project scope) or `$AGENTS_GLOBAL/<name>.md` (freelance pool). If not, refuse: `Error: agent <name> not found. Run /software-house list people to see available agents.`
3. The agent must have `status: active` or `status: freelance`. If `status: onboarding`, `transfer`, or `alumni`, refuse: `Error: agent <name> has status '<status>'. Only active or freelance agents can receive XP.`

## Step-by-step protocol

### 1. Validate inputs

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

Validate `--amount` is a positive integer. Abort if zero, negative, or non-numeric: `Error: --amount must be a positive integer. Got: <value>.`

If `--achievement` is given, validate against `^[a-z][a-z0-9-]{1,63}$`. Abort on mismatch: `Error: achievement name '<value>' is invalid. Must match ^[a-z][a-z0-9-]{1,63}$.`

If `--team` is given, verify `$WIKI_TEAMS/<team>.md` exists. If not, abort: `Error: team <team> not found.`

### 2. Resolve agent file and scope

Locate the canonical agent file:
- If `--team <name>` is given, find the project root from `$PROJECTS_INDEX` by team name -> `$TEAM_AGENTS/<name>.md`.
- If no `--team` flag, auto-detect from `pwd` per `_shared.md §4`.
- If no project detected, check `$AGENTS_GLOBAL/<name>.md` (freelance pool).

Read the canonical agent file. Parse frontmatter. Extract: `xp`, `level`, `achievements`, `team`, `status`.

If `status` is not `active` and not `freelance`, refuse per Precondition 3.

### 3. Compute new XP and level

Calculate new XP total:

```
new_xp = current_xp + amount
```

Determine if a level-up occurred. Check thresholds from highest to lowest:

| Check | New level |
|---|---|
| `new_xp >= 1000` | 5 |
| `new_xp >= 600` | 4 |
| `new_xp >= 300` | 3 |
| `new_xp >= 100` | 2 |
| otherwise | 1 |

If the computed new level is higher than `current_level`, a level-up occurs. Record:
- `levels_gained = new_level - current_level`
- Add achievement `level-<new_level>-reached` to the `achievements` array (if not already present)

If the agent is already at level 5 and XP increases, no level-up occurs (level 5 is the maximum).

### 4. Check achievement for duplicates

If `--achievement` is given, check whether the achievement string already exists in the agent's `achievements` array.

- If it already exists, warn but continue: `Note: achievement '<name>' already exists for <agent>. It will not be duplicated.`
- If it does not exist, it will be added in Step 7.

### 5. Tier-3 confirmation

Build the list of changes:

```
I will update the following for agent '<name>':
  XP:       <current_xp> -> <new_xp>
  Level:    <current_level> -> <new_level>  (if level-up, otherwise "<current_level> (no change)")
  Achievement: <name>  (if --achievement given, otherwise "(none)")
  New achievements from level-up: level-<N>-reached  (if applicable, otherwise "(none)")
  Agent file: <canonical agent file path>
  Wiki page:  $WIKI_PEOPLE/<name>.md
  Team page:  $WIKI_TEAMS/<team>.md  (if team context, otherwise "(none)")
  Audit log:  $AUDIT_LOG
```

Print the Tier-2 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Update canonical agent file

Using the atomic write pattern from `_shared.md §6`, update the following frontmatter fields in the canonical agent file:

```yaml
xp: <new_xp>
level: <new_level>
achievements: [<existing achievements>, <new achievement if given>, <level-<N>-reached if level-up>]
```

Remove duplicate achievements (preserve order, keep first occurrence).

Also update `updated_at` (if present in frontmatter) or add it.

### 7. Update wiki people page

Read `$WIKI_PEOPLE/<name>.md`. Using the atomic write pattern from `_shared.md §6`, update the same frontmatter fields as Step 6:

```yaml
xp: <new_xp>
level: <new_level>
achievements: [<same as canonical>]
```

If `$WIKI_PEOPLE/<name>.md` does not exist, skip this step (the agent may be in the freelance pool without a wiki page).

### 8. Update team wiki page (if team context)

If the agent has a `team` field (or `--team` was given), read `$WIKI_TEAMS/<team>.md`.

Recompute `team_xp`: sum the `xp` field of all members listed in the `members` array. Read each member's canonical agent file or wiki page to get current XP.

Check `team_level` thresholds (same as individual: 100, 300, 600, 1000 for levels 2-5):

```
if team_xp >= 1000 -> team_level = 5
elif team_xp >= 600 -> team_level = 4
elif team_xp >= 300 -> team_level = 3
elif team_xp >= 100 -> team_level = 2
else -> team_level = 1
```

Using the atomic write pattern from `_shared.md §6`, update:

```yaml
team_xp: <recomputed total>
team_level: <recomputed level>
```

If no team context, skip this step.

### 9. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"award-xp","scope":"agent:<name>","args":{"name":"<name>","amount":<amount>,"reason":"<reason|null>","achievement":"<achievement|null>","team":"<team|null>"},"diff":{"updated":["<canonical agent file>","$WIKI_PEOPLE/<name>.md","$WIKI_TEAMS/<team>.md"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

Omit `$WIKI_PEOPLE/<name>.md` from `diff.updated` if it was skipped. Omit `$WIKI_TEAMS/<team>.md` if no team context.

Include a `level_up` field in `args` if a level-up occurred:

```json
"level_up": {"from":<old_level>,"to":<new_level>,"achievement":"level-<new_level>-reached"}
```

### 10. Report to user

```
Awarded <amount> XP to <name>
  Previous XP:  <current_xp>
  New XP:       <new_xp>
  Level:        <current_level> -> <new_level>  (or "<current_level> (no change)")
  Achievement:  <name>  (or "(none)")
  Team XP:      <new_team_xp>  (or "(no team context)")

<If level-up occurred>
  LEVEL UP! <name> is now level <new_level>.
  Achievement added: level-<new_level>-reached
<End if>

Next steps:
  /software-house show <name>              inspect the updated agent record
  /software-house dashboard                see company-wide gamification stats
  /software-house okr-review --tier <t>    check OKR progress for this agent's team
```

## Failure modes

- Agent not found -> refuse before any confirmation gate; no log.
- Agent status not `active` or `freelance` -> refuse; no log.
- `--amount` is zero or negative -> refuse; no log.
- Achievement name invalid -> refuse; no log.
- Achievement already exists -> warn but continue (no duplicate added).
- Team not found (`--team` given but no match) -> abort; no log.
- Atomic write failure on agent file -> roll back `.tmp`, log `result: failed`.
- Wiki people page missing (freelance pool) -> skip wiki update, continue.
- Team wiki page missing -> skip team XP update, continue.

## Examples

```
# Award 50 XP to alice for delivering a feature
/software-house award-xp alice --amount 50 --reason "Feature delivery: user auth module"

# Award 15 XP and a code-reviewer achievement to bob
/software-house award-xp bob --amount 15 --achievement code-reviewer-5

# Award 30 XP to carol for completing an OKR key result, with team context
/software-house award-xp carol --amount 30 --reason "Completed KR 1.2: API latency under 200ms" --team api-gateway

# Award 10 XP for a simple task completion
/software-house award-xp dave --amount 10 --reason "Task: fix login typo"
```