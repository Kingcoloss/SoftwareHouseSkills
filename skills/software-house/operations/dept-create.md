# Operation: dept-create -- create a new department

**Risk tier:** 2 (additive -- creates new directories and files only; escalates to Tier 3 with --force if dept already exists)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Create a department directory under `$DEPARTMENTS_HOME/<dept-name>/` with a charter file (`CLAUDE.md`), an empty `agents/` directory, and an empty `okrs.md`. Register the department in `$WIKI_DEPTS` and rebuild `$COMPANY_INDEX`. Optionally set a parent department for hierarchy. If the department already exists, refuse and suggest `--force` to overwrite (which upgrades to Tier 3).

## Invocation patterns

| Command | Behavior |
|---|---|
| `dept-create <name>` | Create department with an empty charter |
| `dept-create <name> --parent <dept>` | Create with a parent department for hierarchy |
| `dept-create <name> --charter "<text>"` | Create with inline charter text |
| `dept-create <name> --charter-from <path>` | Create with charter text read from a local file |
| `dept-create <name> --force` | Overwrite if exists (Tier 3, requires diff confirmation) |

The command may also be invoked as `dept create` (space-separated) per the Phase 2 routing table in `SKILL.md`.

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--parent` | no | Must match an existing key in `$WIKI_DEPTS` |
| `--charter` | no | Inline string; max 2000 characters |
| `--charter-from` | no | Local file path; must be readable; max 64 KB |
| `--force` | no | Flag; escalates to Tier 3 if dept exists |

`--charter` and `--charter-from` are mutually exclusive. If both are given, abort: `Error: use --charter or --charter-from, not both.`

## Preconditions

1. `$COMPANY_HOME` exists. If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. `$DEPARTMENTS_HOME` directory exists (created by `init`).
3. If `--parent` given, `$DEPARTMENTS_HOME/<parent>/` must exist.
4. Conflict check (see Step 2).

## Step-by-step protocol

### 1. Validate inputs

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

If `--parent` is given, verify `$DEPARTMENTS_HOME/<parent>/` exists. If not, abort: `Error: parent department <parent> does not exist. Create it first or omit --parent.`

If `--charter-from` is given, read the specified local file using `Read`. Verify it is readable and under 64 KB. Abort if unreadable: `Error: cannot read charter file at <path>.`

If `--charter` is given, use the inline text verbatim.

If neither `--charter` nor `--charter-from` is given, the charter body is:
```
(No charter text provided. Edit $DEPARTMENTS_HOME/<name>/CLAUDE.md to add department charter.)
```

### 2. Conflict check

Check whether `$DEPARTMENTS_HOME/<name>/` already exists.

- If it exists AND `--force` is NOT given:
  Refuse:
  ```
  Error: department <name> already exists at $DEPARTMENTS_HOME/<name>/.
  Recovery: run /software-house dept-create <name> --force to overwrite the charter and metadata.
             This will be a Tier 3 (modifying) operation with a diff displayed before any changes.
  ```
  No log entry.

- If it exists AND `--force` IS given:
  Switch to Tier-3 mode. The charter file and wiki entry will be overwritten. Proceed to Step 3 (but confirmation in Step 5 uses the Tier-3 prompt and a diff).

### 3. Compute the plan

Files and directories to create (Tier 2 fresh create):

```
$DEPARTMENTS_HOME/<name>/
$DEPARTMENTS_HOME/<name>/CLAUDE.md       (department charter)
$DEPARTMENTS_HOME/<name>/agents/         (empty directory)
$DEPARTMENTS_HOME/<name>/okrs.md         (empty OKR file)
$WIKI_DEPTS/<name>.md                    (department wiki entry)
$COMPANY_INDEX                           (rebuild)
$AUDIT_LOG                               (append)
```

For `--force` (Tier 3 overwrite), the plan modifies:
```
$DEPARTMENTS_HOME/<name>/CLAUDE.md       (overwrite charter)
$WIKI_DEPTS/<name>.md                    (update frontmatter fields)
$COMPANY_INDEX                           (rebuild)
$AUDIT_LOG                               (append)
```

### 4. Build file contents

#### 4.1 `$DEPARTMENTS_HOME/<name>/CLAUDE.md`

```markdown
---
type: department-charter
name: <name>
parent: <parent | null>
classification: internal
created_at: <utc-date YYYY-MM-DD>
head: null
---

# Department: <name>

## Charter

<charter text from --charter, --charter-from, or the default placeholder>

## Standards

(Add department-wide coding/process standards here.)

## Teams

(Teams in this department are listed in $WIKI_DEPTS/<name>.md)
```

#### 4.2 `$DEPARTMENTS_HOME/<name>/okrs.md`

```markdown
# OKRs -- <name>

(No OKRs set yet. Run /software-house okr set --dept <name> to set objectives.)
```

#### 4.3 `$WIKI_DEPTS/<name>.md`

Frontmatter per `_shared.md §7`:

```yaml
---
name: <name>
description: <first non-empty sentence of charter, or "(no charter)">
head: null
parent: <parent | null>
teams: []
status: active
classification: internal
created_at: <utc-date YYYY-MM-DD>
---
```

Body:

```markdown
# Department: <name>

See charter: $DEPARTMENTS_HOME/<name>/CLAUDE.md

## Teams

(none yet)
```

### 5. Confirmation

#### Tier-2 (fresh create)

Print the plan, then print the Tier-2 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

#### Tier-3 (--force overwrite)

Compute and print a diff of existing vs. new charter and wiki frontmatter per `safety.md §5`:

```
File: $DEPARTMENTS_HOME/<name>/CLAUDE.md
  - <old charter lines>
  + <new charter lines>
File: $WIKI_DEPTS/<name>.md (frontmatter)
  field description: "<old>" -> "<new>"
```

Print all modified file paths. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Create directories (Tier 2 only)

```
mkdir -p $DEPARTMENTS_HOME/<name>/agents
```

The `okrs/` subdirectory is not created here; quarterly OKR files are created by the `okr set` operation (Phase 4). `okrs.md` (the top-level placeholder) is created as a flat file in Step 7.

### 7. Write files

Use atomic write per `_shared.md §6` for any existing file (Tier-3 force path). For new files, write directly.

Write in order:
1. `$DEPARTMENTS_HOME/<name>/CLAUDE.md`
2. `$DEPARTMENTS_HOME/<name>/okrs.md`
3. `$WIKI_DEPTS/<name>.md`

If `--parent` is given, also update `$WIKI_DEPTS/<parent>.md`: add `<name>` to the `teams` list (note: the field is named `teams` in the wiki entry for parents; child departments share the same list because the schema supports departments-under-departments as well as teams-under-departments). Use atomic write.

### 8. Rebuild company index

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 9. Append audit log entry

Tier 2 (fresh create):

```json
{"ts":"<utc>","actor":"user","op":"dept-create","scope":"company","args":{"name":"<name>","parent":"<parent|null>","charter_source":"<inline|file:<path>|none>","force":false},"diff":{"created":["$DEPARTMENTS_HOME/<name>/","$DEPARTMENTS_HOME/<name>/CLAUDE.md","$DEPARTMENTS_HOME/<name>/agents/","$DEPARTMENTS_HOME/<name>/okrs.md","$WIKI_DEPTS/<name>.md"],"updated":["$COMPANY_INDEX"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

Tier 3 (--force):

```json
{"ts":"<utc>","actor":"user","op":"dept-create","scope":"company","args":{"name":"<name>","parent":"<parent|null>","charter_source":"<source>","force":true},"diff":{"updated":["$DEPARTMENTS_HOME/<name>/CLAUDE.md","$WIKI_DEPTS/<name>.md","$COMPANY_INDEX"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 10. Report to user

```
Department created: <name>
  Charter:  $DEPARTMENTS_HOME/<name>/CLAUDE.md
  OKRs:     $DEPARTMENTS_HOME/<name>/okrs.md
  Agents:   $DEPARTMENTS_HOME/<name>/agents/  (empty)
  Wiki:     $WIKI_DEPTS/<name>.md
  Parent:   <parent | "(none, top-level)">

Next steps:
  /software-house dept-assign <agent> <name>   add an agent to this department
  /software-house show dept <name>             inspect the department record
```

## Failure modes

- Name validation fails -> abort, no log.
- `--parent` not found -> abort, no log.
- `--charter-from` file not readable -> abort, no log.
- Department exists, `--force` not given -> refuse with recovery hint, no log.
- Confirmation non-affirmative -> abort, no log, no changes.
- `mkdir` failure -> abort, report path, no log.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.

## Examples

```
# Create an engineering department with no charter
/software-house dept-create engineering

# Create a frontend sub-department under engineering
/software-house dept-create frontend --parent engineering --charter "Owns all user-facing web interfaces."

# Create from an existing charter file
/software-house dept-create platform --charter-from ./docs/platform-charter.md

# Overwrite an existing department's charter (Tier 3)
/software-house dept-create engineering --charter "Revised charter text." --force
```
