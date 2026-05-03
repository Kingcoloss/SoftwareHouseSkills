# Operation: okr-set -- set OKRs at any tier

**Risk tier:** 2 (additive -- creates new OKR files; modifying if OKR file already exists for the quarter)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Set objectives and key results at company, department, or team tier. Creates or updates the OKR file for the specified quarter. If an OKR file already exists for the quarter, appends new objectives (does not replace existing ones unless `--replace` flag is given, which upgrades to Tier 3). Validates that each objective has at least one key result and that key results are measurable (must contain a target value in parentheses).

## Invocation patterns

| Command | Behavior |
|---|---|
| `okr-set --tier company --quarter <Q> --objective "<text>" --kr "<text>"` | Set company OKRs |
| `okr-set --tier dept --dept <name> --quarter <Q> --objective "<text>" --kr "<text>"` | Set department OKRs |
| `okr-set --tier team --team <name> --quarter <Q> --objective "<text>" --kr "<text>"` | Set team OKRs |
| `okr-set ... --owner <name>` | Assign an owner to the objective |
| `okr-set ... --replace` | Replace existing OKRs for the quarter (Tier 3) |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--tier` | yes | One of `company`, `dept`, `team` |
| `--quarter` | yes | Must match `YYYY-QN` where N is 1-4 (e.g., `2026-Q2`) |
| `--objective` | yes | Non-empty string; can be repeated for multiple objectives |
| `--kr` | yes | Must contain `(target: <value>)` pattern; can be repeated; at least one per objective |
| `--owner` | no | Agent name, team name, or department name; must match `^[a-z][a-z0-9-]{0,63}$` if agent name |
| `--dept` | conditional | Required if `--tier dept`; must match an existing directory under `$DEPARTMENTS_HOME` |
| `--team` | conditional | Required if `--tier team`; must match an existing entry in `$WIKI_TEAMS` |
| `--replace` | no | Flag; upgrades operation to Tier 3 (modifying) |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. If `--tier dept`, `$DEPARTMENTS_HOME/<dept>/` must exist. If not, refuse: `Error: department <dept> not found. Run /software-house dept-create <dept> first.`
3. If `--tier team`, `$WIKI_TEAMS/<team>.md` must exist. If not, refuse: `Error: team <team> not found. Run /software-house list teams to see available teams.`
4. At least one `--objective` must be provided.
5. At least one `--kr` must be provided per objective. If KRs are fewer than objectives, the last objective(s) receive no KRs and the operation is refused.

## Step-by-step protocol

### 1. Validate inputs

Validate `--quarter` against `^(\d{4})-Q([1-4])$`. Abort on mismatch with: `Error: invalid quarter format '<value>'. Expected YYYY-QN where N is 1-4 (e.g., 2026-Q2).`

Validate `--tier` is one of `company`, `dept`, `team`. Abort on invalid value.

If `--tier dept` and `--dept` is missing, abort: `Error: --dept is required when --tier is dept.`

If `--tier team` and `--team` is missing, abort: `Error: --team is required when --tier is team.`

Validate each `--kr` contains the pattern `(target: <value>)`. The `<value>` must be a non-empty string (numeric or descriptive). Abort if any KR lacks this pattern: `Error: key result '<text>' is not measurable. Include a target value in the format (target: <value>).`

Associate KRs to objectives: objectives and KRs are processed in order. The first objective gets KRs until the next objective appears, then the next objective gets the following KRs, and so on. If the last objective has no KRs, abort: `Error: objective '<text>' has no key results. Each objective requires at least one --kr.`

If `--owner` is given, validate the name against `^[a-z][a-z0-9-]{0,63}$` (agent name convention). If it does not match, treat it as a team or department name and accept it.

### 2. Resolve target path

Determine the OKR file path based on tier:

| Tier | OKR directory | OKR file |
|---|---|---|
| `company` | `$COMPANY_HOME/okrs/` | `$COMPANY_HOME/okrs/<quarter>.md` |
| `dept` | `$DEPARTMENTS_HOME/<dept>/okrs/` | `$DEPARTMENTS_HOME/<dept>/okrs/<quarter>.md` |
| `team` | `$TEAM_DIR/okrs/` (resolved from `$PROJECTS_INDEX` or `--team`) | `$TEAM_DIR/okrs/<quarter>.md` |

For the `team` tier, resolve `$TEAM_DIR`:
- If `--team <name>` is given, find the project root from `$PROJECTS_INDEX` by team name.
- If no `--team` flag, auto-detect from `pwd` per `_shared.md §4`.

### 3. Check existing state

Check if the OKR file already exists at the target path.

- If it does NOT exist: this is a fresh create (Tier 2). Continue to Step 5.
- If it DOES exist AND `--replace` is NOT given: this is an append (still Tier 2 -- appending new objectives is additive). Read the existing file, parse frontmatter and body. Continue to Step 4.
- If it DOES exist AND `--replace` IS given: this is a replace (Tier 3 -- modifies existing content). Read the existing file. Continue to Step 4 with the Tier-3 flag set.

### 4. Build OKR content

Get current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Construct the OKR content to write or append.

#### For fresh create (no existing file)

Write the full OKR file with frontmatter per the OKR schema:

```markdown
---
type: okr
tier: <company | department | team>
scope: <company | dept-name | team-name>
quarter: <YYYY-QN>
status: draft
created_at: <utc-date YYYY-MM-DD>
updated_at: <utc-date YYYY-MM-DD>
---

# OKRs -- <scope> <quarter>

## Objective 1: <objective text>

**Status:** on-track
**Owner:** <owner | unassigned>

### Key Results

- [ ] KR 1.1: <key result text> (target: <value>, current: 0)
```

Number objectives sequentially. Number KRs as `<objective-number>.<kr-sequential>`.

If multiple objectives, repeat the `## Objective N` section for each.

#### For append (existing file, no --replace)

Read the existing file. Count existing objectives (match `## Objective N:` headings). New objectives are numbered starting from the next number.

Append new `## Objective N:` sections after the last line of the existing file body. Do not modify existing objectives or KRs.

Update frontmatter: set `updated_at` to current UTC date, set `status` to `draft` if it was `closed`.

#### For replace (existing file, --replace flag)

This upgrades the operation to Tier 3. Compute a diff of the old vs. new content. The new file replaces all objectives and KRs. The diff is shown at Step 5 using the Tier-3 confirmation prompt.

### 5. Confirmation

#### Tier 2 (fresh create or append)

Print the file path that will be created or updated:

```
I will create/update the following:
  OKR file:  <okr-file-path>
  Audit log: $AUDIT_LOG
```

For append, also print: `(Appending N new objective(s) to existing OKR file.)`

Print the Tier-2 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

#### Tier 3 (--replace)

Compute and print a diff per `safety.md §5`:

```
File: <okr-file-path>
  - <old objective/KR lines>
  + <new objective/KR lines>
```

Print all modified file paths. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Write OKR file

Create the OKR directory if it does not exist:

```
mkdir -p <okr-directory>
```

For fresh create: write the file directly.

For append: use the atomic write pattern from `_shared.md §6`. Append new objective sections to the end of the file body. Update frontmatter `updated_at` and `status`.

For replace: use the atomic write pattern from `_shared.md §6`. Write the full new content, replacing all existing objectives.

### 7. Append audit log entry

Tier 2 (fresh create or append):

```json
{"ts":"<utc>","actor":"user","op":"okr-set","scope":"<company | department:<dept> | team:<team>>","args":{"tier":"<tier>","quarter":"<quarter>","objectives":<count>,"key_results":<count>,"owner":"<owner|null>","replace":false},"diff":{"created":["<okr-file-path>"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

For append, use `"diff":{"updated":["<okr-file-path>"]}` instead.

Tier 3 (--replace):

```json
{"ts":"<utc>","actor":"user","op":"okr-set","scope":"<company | department:<dept> | team:<team>>","args":{"tier":"<tier>","quarter":"<quarter>","objectives":<count>,"key_results":<count>,"owner":"<owner|null>","replace":true},"diff":{"updated":["<okr-file-path>"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

### 8. Report to user

```
OKRs set for <scope> -- <quarter>
  Objectives:  <count>
  Key results: <count>
  Owner:       <owner | unassigned>
  File:        <okr-file-path>
  Status:      draft

Next steps:
  /software-house okr-review --tier <tier>   review progress
  /software-house award-xp <name>            award XP for completed KRs
```

## Failure modes

- Invalid quarter format -> abort, no log.
- Missing `--dept` or `--team` for the respective tier -> abort, no log.
- Department or team not found -> abort, no log.
- KR without `(target: <value>)` pattern -> abort, no log.
- Objective with no KRs -> abort, no log.
- Existing OKR file + `--replace` not given + user cancels -> abort, no log, no changes.
- Atomic write failure -> roll back `.tmp`, log `result: failed`.
- `mkdir` failure (permissions) -> report path, abort, no log.

## Examples

```
# Set company OKRs for Q2 2026
/software-house okr-set --tier company --quarter 2026-Q2 \
  --objective "Ship v2.0 of the platform" \
  --kr "Complete 90% of v2.0 feature scope (target: 90%, current: 0)" \
  --kr "Reduce P1 bug count to under 5 (target: 5, current: 12)"

# Set department OKRs for engineering with an owner
/software-house okr-set --tier dept --dept engineering --quarter 2026-Q2 \
  --objective "Improve code quality" \
  --kr "Increase test coverage to 85% (target: 85%, current: 62%)" \
  --owner tech-lead

# Set team OKRs
/software-house okr-set --tier team --team api-gateway --quarter 2026-Q2 \
  --objective "Reduce API latency" \
  --kr "P99 latency under 200ms (target: 200ms, current: 450ms)"

# Replace existing team OKRs (Tier 3)
/software-house okr-set --tier team --team api-gateway --quarter 2026-Q2 \
  --objective "Migrate to new infra" \
  --kr "Complete migration of 100% services (target: 100%, current: 0)" \
  --replace

# Set multiple objectives in one command
/software-house okr-set --tier company --quarter 2026-Q3 \
  --objective "Grow user base" \
  --kr "Reach 10k active users (target: 10000, current: 3200)" \
  --objective "Improve retention" \
  --kr "30-day retention at 60% (target: 60%, current: 45%)"
```