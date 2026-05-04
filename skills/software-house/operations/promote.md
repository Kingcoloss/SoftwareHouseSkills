# Operation: promote -- promote agent (increase level/role)

**Risk tier:** 3 (modifying -- updates agent frontmatter, wiki page, and roster)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Increase an agent's `level` and optionally change their `role`. The level increases by 1 by default (or by `--by N`). If `--to-role` is given, the role and position fields are updated. The wiki people page frontmatter is also updated. If the new role has different provider/model defaults in `$MODELS_CONFIG`, the user is warned about the mismatch but the provider and model are NOT auto-changed (suggest `set-model` instead). A promotion audit trail is added to the agent frontmatter.

## Invocation patterns

| Command | Behavior |
|---|---|
| `promote <name>` | Increase level by 1 (default) |
| `promote <name> --by N` | Increase level by N |
| `promote <name> --to-role <role>` | Change role (and position) alongside promotion |
| `promote <name> --by N --to-role <role>` | Increase level by N and change role |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--by N` | no | Positive integer; default is 1 |
| `--to-role <role>` | no | Must exactly match a key in `defaults_by_role` in `$MODELS_CONFIG` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active`. Refuse for other statuses: `Error: <name> has status <status>. Only active agents can be promoted.`

## Step-by-step protocol

### 1. Validate inputs

Read the canonical agent file. Parse frontmatter. Extract: `level`, `role`, `provider`, `model`, `team`, `position`, `status`, `employment`.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

If `--by N` is given, validate it is a positive integer. If not, abort: `Error: --by must be a positive integer. Got: <value>.`

If `--to-role <role>` is given, read `$MODELS_CONFIG` and validate that `<role>` matches a key in `defaults_by_role`. If not, list valid role keys and abort.

Compute new level: `current_level + by_value`.

### 2. Check provider/model mismatch warning

If `--to-role` is given, read the new role's defaults from `$MODELS_CONFIG` (`defaults_by_role[<new-role>]`).

Compare the new role's default `provider` and `model` with the agent's current `provider` and `model`.

If they differ, prepare a warning message (shown in the diff and in the final report). Do NOT auto-change provider or model -- that requires a separate `set-model` operation.

```
Warning: role <new-role> defaults to provider=<default-provider> model=<default-model>,
but <name> currently uses provider=<current-provider> model=<current-model>.
Consider running /software-house set-model <name> after promotion to align with role defaults.
```

### 3. Compute diff

Build the modification plan:

```
File: <canonical agent file> (frontmatter)
  field level: <old-level> -> <new-level>
  field promotion_at: <absent | old-value> -> <utc-date YYYY-MM-DD>
  field promotion_from_level: <absent | old-value> -> <old-level>
  <If --to-role given:>
  field role: <old-role> -> <new-role>
  field position: <old-position> -> <new-role-label>
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  field level: <old-level> -> <new-level>
  field promotion_at: <absent | old-value> -> <utc-date YYYY-MM-DD>
  field promotion_from_level: <absent | old-value> -> <old-level>
  <If --to-role given:>
  field role: <old-role> -> <new-role>
  field position: <old-position> -> <new-role-label>

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

Add promotion audit trail fields:

```yaml
promotion_at: <utc-date YYYY-MM-DD>
promotion_from_level: <old-level>
```

### 6. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the same frontmatter fields as Step 5 (mirroring canonical agent file). Use atomic write per `_shared.md §6`.

### 7. Rebuild indexes

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 8. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"promote","scope":"agent:<name>","args":{"name":"<name>","from_level":<old-level>,"to_level":<new-level>,"by":<by-value>,"old_role":"<old-role>","new_role":"<new-role|null>"},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","$COMPANY_INDEX"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 9. Report to user

```
Promoted <name>
  Level:   <old-level> -> <new-level>  (+<by-value>)
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
- `--by` not a positive integer -> abort; no log.
- `--to-role` not in `$MODELS_CONFIG` -> list valid roles, abort; no log.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Promote alice by one level
/software-house promote alice

# Promote bob by two levels
/software-house promote bob --by 2

# Promote carol and change role to tech-lead
/software-house promote carol --to-role tech-lead

# Promote dave by 3 levels and change role to principal-dev
/software-house promote dave --by 3 --to-role principal-dev
```