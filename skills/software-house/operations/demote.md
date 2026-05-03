# Operation: demote -- demote agent (decrease level/role)

**Risk tier:** 3 (modifying -- updates agent frontmatter, wiki page)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Decrease an agent's `level` by 1 (default) or by a specified amount with `--by N`. Optionally change the agent's `role` with `--to-role`. The minimum level is 1 -- if the demotion would bring level below 1, the operation is refused. A demotion audit trail is added to the agent frontmatter. The wiki people page is also updated. If the new role has different provider/model defaults, the user is warned but the provider/model are NOT auto-changed.

## Invocation patterns

| Command | Behavior |
|---|---|
| `demote <name>` | Decrease level by 1 (default) |
| `demote <name> --by N` | Decrease level by N |
| `demote <name> --to-role <role>` | Change role alongside demotion |
| `demote <name> --by N --to-role <role>` | Decrease level by N and change role |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--by N` | no | Positive integer; default is 1 |
| `--to-role <role>` | no | Must exactly match a key in `defaults_by_role` in `$MODELS_CONFIG` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active`. Refuse for other statuses: `Error: <name> has status <status>. Only active agents can be demoted.`
4. The resulting level must not go below 1. If `current_level - by_value < 1`, refuse: `Error: level cannot go below 1.`

## Step-by-step protocol

### 1. Validate inputs

Read the canonical agent file. Parse frontmatter. Extract: `level`, `role`, `position`, `provider`, `model`, `status`, `team`, `employment`.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

If `--by N` is given, validate it is a positive integer. If not, abort: `Error: --by must be a positive integer. Got: <value>.`

If `--to-role <role>` is given, read `$MODELS_CONFIG` and validate that `<role>` matches a key in `defaults_by_role`. If not, list valid role keys and abort.

Compute new level: `current_level - by_value`.

If `new_level < 1`, refuse: `Error: level cannot go below 1. Current level is <current_level>, demotion by <by_value> would result in level <new_level>.`

### 2. Check provider/model mismatch warning

If `--to-role` is given, read the new role's defaults from `$MODELS_CONFIG` (`defaults_by_role[<new-role>]`).

Compare the new role's default `provider` and `model` with the agent's current `provider` and `model`.

If they differ, prepare a warning message (shown in the diff and in the final report). Do NOT auto-change provider or model -- that requires a separate `set-model` operation.

```
Warning: role <new-role> defaults to provider=<default-provider> model=<default-model>,
but <name> currently uses provider=<current-provider> model=<current-model>.
Consider running /software-house set-model <name> after demotion to align with role defaults.
```

### 3. Compute diff

Build the modification plan:

```
File: <canonical agent file> (frontmatter)
  field level: <old-level> -> <new-level>
  <If --to-role given:>
  field role: <old-role> -> <new-role>
  field position: <old-position> -> <new-role-label>
  field demotion_at: <absent> -> <utc-date YYYY-MM-DD>
  field demotion_from_level: <absent> -> <old-level>
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  field level: <old-level> -> <new-level>
  <If --to-role given:>
  field role: <old-role> -> <new-role>
  field position: <old-position> -> <new-role-label>
  field demotion_at: <absent> -> <utc-date YYYY-MM-DD>
  field demotion_from_level: <absent> -> <old-level>

<If provider/model mismatch:>
  Warning: role defaults differ from current provider/model (see above)
```

Also update `$AUDIT_LOG` (append).

### 4. Tier-3 confirmation

Print the full diff from Step 3. Print the paths that will be modified. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 5. Update canonical agent file

Using atomic write per `_shared.md §6`, update the following frontmatter fields:

```yaml
level: <new-level>
updated_at: <utc-date YYYY-MM-DD>
```

If `--to-role` is given, also update:

```yaml
role: <new-role>
position: <new-role human-readable label from $MODELS_CONFIG>
```

Add demotion audit trail fields:

```yaml
demotion_at: <utc-date YYYY-MM-DD>
demotion_from_level: <old-level>
```

### 6. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the same frontmatter fields as Step 5 (mirroring canonical agent file). Use atomic write per `_shared.md §6`.

### 7. Rebuild indexes

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 8. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"demote","scope":"agent:<name>","args":{"name":"<name>","from_level":<old-level>,"to_level":<new-level>,"by":<by-value>,"old_role":"<old-role>","new_role":"<new-role|null>"},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","$COMPANY_INDEX"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 9. Report to user

```
Demoted <name>
  Level:   <old-level> -> <new-level>  (-<by-value>)
  Role:    <old-role> -> <new-role | "(unchanged)">
  Position: <new-position | "(unchanged)">
  Canonical: <canonical agent path>
  Wiki:      $WIKI_PEOPLE/<name>.md

<If provider/model mismatch:>
  WARNING: role defaults differ from current provider/model.
  Consider: /software-house set-model <name>

Next steps:
  /software-house show <name>           verify the updated agent record
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent status not active -> refuse; no log.
- Level would go below 1 -> refuse; no log.
- `--by` not a positive integer -> abort; no log.
- `--to-role` not in `$MODELS_CONFIG` -> list valid roles, abort; no log.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Demote alice by one level
/software-house demote alice

# Demote bob by two levels
/software-house demote bob --by 2

# Demote carol and change role to junior-dev
/software-house demote carol --to-role junior-dev

# Demote dave by 1 level and change role to intern
/software-house demote dave --by 1 --to-role intern
```