# Operation: okr-review -- review OKR progress

**Risk tier:** 1 (read-only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Display and assess the status of OKRs for a given tier and quarter. Reads the OKR file, parses all objectives and key results, computes progress percentage for each key result, computes overall progress per objective, highlights at-risk and off-track items, and suggests adjustments. Never modifies any file.

## Invocation patterns

| Command | Behavior |
|---|---|
| `okr-review` | Review current quarter company OKRs |
| `okr-review --tier company` | Review company OKRs |
| `okr-review --tier dept --dept <name>` | Review department OKRs |
| `okr-review --tier team --team <name>` | Review team OKRs |
| `okr-review --quarter <YYYY-QN>` | Review a specific quarter |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--tier` | no | One of `company`, `dept`, `team`; default `company` |
| `--quarter` | no | Must match `YYYY-QN` where N is 1-4; defaults to current quarter |
| `--dept` | conditional | Required if `--tier dept`; must match an existing directory under `$DEPARTMENTS_HOME` |
| `--team` | conditional | Required if `--tier team`; must match an existing entry in `$WIKI_TEAMS` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The OKR file for the specified tier and quarter must exist. If not, print: `No OKRs found for <scope> <quarter>. Run /software-house okr-set to create them.` and stop.

## Step-by-step protocol

### 1. Resolve quarter

If `--quarter` is not given, compute the current quarter:

```
date -u +"%Y-Q"
```

Append the quarter number based on the month:
- January-March: Q1
- April-June: Q2
- July-September: Q3
- October-December: Q4

Alternatively, parse the month from `date -u +"%m"`:
- 01-03 -> Q1, 04-06 -> Q2, 07-09 -> Q3, 10-12 -> Q4

Validate `--quarter` against `^(\d{4})-Q([1-4])$` if provided. Abort on mismatch.

### 2. Resolve OKR file path

Determine the OKR file path based on tier:

| Tier | OKR file |
|---|---|
| `company` | `$COMPANY_HOME/okrs/<quarter>.md` |
| `dept` | `$DEPARTMENTS_HOME/<dept>/okrs/<quarter>.md` |
| `team` | `$TEAM_DIR/okrs/<quarter>.md` |

For the `team` tier, resolve `$TEAM_DIR`:
- If `--team <name>` is given, find the project root from `$PROJECTS_INDEX` by team name.
- If no `--team` flag, auto-detect from `pwd` per `_shared.md §4`.

### 3. Read and parse OKR file

Read the OKR file in full. Parse frontmatter to extract: `tier`, `scope`, `quarter`, `status`, `created_at`, `updated_at`.

Parse the body to extract all objectives and key results:

For each `## Objective N: <title>` section:
- Extract the objective number and title.
- Extract the `**Status:**` line value (`on-track`, `at-risk`, `off-track`, `completed`).
- Extract the `**Owner:**` line value.
- Extract each `- [ ] KR N.M:` or `- [x] KR N.M:` line:
  - Checkbox state: `[ ]` = incomplete, `[x]` = complete.
  - KR text.
  - Parse `(target: <value>, current: <value>)` from the KR text.

### 4. Compute progress

For each key result that contains a numeric `current` and `target`:

- Progress = `(current / target) * 100` (if target is numeric and > 0).
- Round to the nearest integer.
- Cap at 100% (do not show > 100% even if current exceeds target).
- If target or current is non-numeric or target is zero, display `N/A`.

For each objective:
- Overall progress = average of all KR progress percentages (excluding N/A entries).
- Round to the nearest integer.

Classify objective status:
- `completed`: all KRs checked off or at 100%.
- `on-track`: overall progress >= 70%.
- `at-risk`: overall progress >= 40% and < 70%, OR any single KR is off-track while others are on-track.
- `off-track`: overall progress < 40%, OR 2+ KRs are off-track.

### 5. Render review

Print the OKR review in formatted tables using ASCII box-drawing characters.

```
+-- OKR Review: <scope> -- <quarter> ---------------------------+
| Tier: <tier>     Status: <status>     Updated: <updated_at>  |
+---------------------------------------------------------------+

Objectives Summary
+----------------+----------------+----------+----------+
| Objective      | Owner          | Progress | Status   |
+----------------+----------------+----------+----------+
| <title>        | <owner>        | <pct>%   | <status> |
| ...            |                |          |          |
+----------------+----------------+----------+----------+

Key Results Detail
+--------+---------------------------+--------+---------+----------+
| Obj    | Key Result                | Target | Current | Progress |
+--------+---------------------------+--------+---------+----------+
| 1      | KR 1.1: <text>            | <val>  | <val>   | <pct>%   |
| 1      | KR 1.2: <text>            | <val>  | <val>   | <pct>%   |
| 2      | KR 2.1: <text>            | <val>  | <val>   | <pct>%   |
+--------+---------------------------+--------+---------+----------+
```

### 6. Highlight at-risk and off-track

After the tables, print an assessment section:

```
Assessment

  ON-TRACK:
    <list objectives that are on-track, or "(none)">

  AT-RISK:
    <list objectives that are at-risk with the specific KRs that are lagging>
    Example: "Obj 1: KR 1.2 at 30% -- needs acceleration"

  OFF-TRACK:
    <list objectives that are off-track with recommendations>
    Example: "Obj 2: Only 15% progress -- consider reducing scope or extending deadline"

  COMPLETED:
    <list objectives that are completed, or "(none)">
```

### 7. Suggest adjustments

Print actionable suggestions for at-risk and off-track objectives:

```
Suggestions

  <if any at-risk objectives exist>
  - Escalate at-risk KRs to the objective owner for review.
  - Consider adjusting target values if scope has changed.
  - Reassign ownership if the current owner is overloaded.

  <if any off-track objectives exist>
  - Break down off-track KRs into smaller milestones.
  - Request additional resources or reduce scope.
  - Set a checkpoint review date within 2 weeks.

  <if all on-track or completed>
  - No adjustments needed. Progress is healthy.
```

### 8. Report to user

```
OKR review complete for <scope> -- <quarter>
  Objectives:  <total> (on-track: <n>, at-risk: <n>, off-track: <n>, completed: <n>)
  KRs checked: <completed>/<total>
  Overall:     <average progress across all objectives>%

No files were modified. This is a read-only operation.
```

## Failure modes

- Company not initialized -> refuse, no log (Tier 1, no state change).
- OKR file not found -> inform user, suggest `okr-set`, no log.
- OKR file malformed (invalid frontmatter) -> print what can be parsed, then `Warning: OKR file may be malformed at <path>. Some data may be incomplete.`
- No KRs with numeric target/current -> print tables with `N/A` progress, note that progress cannot be computed.

## Examples

```
# Review current quarter company OKRs
/software-house okr-review

# Review department OKRs for a specific quarter
/software-house okr-review --tier dept --dept engineering --quarter 2026-Q2

# Review team OKRs
/software-house okr-review --tier team --team api-gateway

# Review company OKRs for Q3
/software-house okr-review --tier company --quarter 2026-Q3
```