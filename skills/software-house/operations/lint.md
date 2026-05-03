# Operation: lint — health checks on the company wiki

**Risk tier:** 1 (read-only)

**Required reading first:** `operations/_shared.md`

## Purpose

Scan the company, department, and team wikis for structural problems: orphaned entities, broken cross-references, stale pages, missing required fields, and policy violations. Reports findings, suggests fixes. Never modifies state. Never auto-fixes.

## Invocation patterns

| Command | Scope |
|---|---|
| `lint` | Full company + all departments + current team (if detected) |
| `lint company` | Company tier only |
| `lint dept <name>` | One department |
| `lint team <name>` | One team |
| `lint --fix-suggestions` | Same scan, but include explicit `/software-house ...` commands the user can run to fix each finding |

## Step-by-step

### 1. Collect targets

Build the file list from the requested scope. Read frontmatter only for index-level checks; read full body when checking link integrity (§3).

### 2. Run check categories

Run all checks and accumulate findings. Each finding is one of severity: `error` (must fix), `warning` (should fix), `info` (FYI).

#### 2.1 Orphan checks

- An agent file (`$TEAM_AGENTS/<name>.md` or `$AGENTS_GLOBAL/<name>.md`) with no matching `$WIKI_PEOPLE/<name>.md` → **warning**.
- A wiki/people page with no matching agent file → **warning**.
- A team in `$WIKI_TEAMS` with `project_path` that does not exist on disk → **error**.
- A department in `$WIKI_DEPTS` with zero teams listed → **info**.

#### 2.2 Reference integrity

- `reports_to` points to a person not in `$WIKI_PEOPLE` and not in alumni → **error**.
- `reports_to` points to alumni → **warning** (orphaned reporting line).
- `reports_to` points to someone in a different team → **warning**.
- `team` field on a person points to a team not in `$WIKI_TEAMS` → **error**.
- `department` field on a person points to a dept not in `$WIKI_DEPTS` → **error**.
- `buddy` field points to a person not in `$WIKI_PEOPLE` → **warning**.
- A team's `members` list contains names not in `$WIKI_PEOPLE` → **error**.
- A team's `lead` field is empty or points to a non-member → **warning**.
- A department's `head` field points to a non-employee → **error**.
- A department's `teams` list contains teams not in `$WIKI_TEAMS` → **error**.

#### 2.3 Required fields

- Any person page missing `role`, `team` (unless `employment: freelance`), `provider`, `model`, `egress_consent`, `status`, `classification` → **error**.
- Any team page missing `lead`, `department` (unless company-direct), `status`, `classification` → **error**.
- Any department page missing `head`, `status`, `classification` → **error**.

#### 2.4 Status sanity

- A person with `status: onboarding` and no `buddy` → **warning**.
- A person with `status: transfer` for more than 30 days (compare to `updated_at` if present, else flag for manual review) → **warning**.
- A person with `status: alumni` still in a team's `members` list → **error**.
- A person with `status: alumni` not in `$ALUMNI/` → **error**.
- A team with `status: disbanded` still listed under a department → **error**.

#### 2.5 Classification ceilings

- A wiki page references (by name, in body) another entity whose classification is higher than its own → **warning** (potential leak by reference).
- The audit log file's permissions are world-readable while it contains entries with `confidential` or `restricted` scope → **warning**.

#### 2.6 Privacy posture and provider egress

- The skill itself was modified to add `WebFetch`, `WebSearch`, or any denylisted Bash pattern in any operation file → **error** (skill tampering).

Provider/egress checks per `policies/privacy.md §7.6`:

- An agent file's `provider` value is not present as a key in `$PROVIDERS_CONFIG` → **error** (unknown provider).
- An agent file's `provider` is classified `external` and `egress_consent` is `none` (or missing the `external:<utc-date>` prefix) → **error** (egress without consent).
- An agent file's `provider` is classified `external` and the audit log contains no matching `EGRESS-CONSENT-<provider>` token at or after the `hired_at` (or last `set-model`) timestamp → **error** (consent not recorded).
- An agent file's `provider` is classified `local` and `egress_consent` is anything other than `none` → **warning** (stale consent on a local-provider agent — should be cleared).
- `$PROVIDERS_CONFIG` itself is missing or unreadable → **error** (skill state corrupted; suggest re-run `/software-house init`).

#### 2.7 Index drift

- `$COMPANY_INDEX` lists pages that no longer exist → **warning** (run `lint --fix-suggestions` to get rebuild command).
- A wiki page exists but is not in `$COMPANY_INDEX` → **warning**.

### 3. Render

Group findings by severity, then by category:

```
Lint report — <scope>  (<n> errors, <m> warnings, <k> info)

ERRORS
  [reference] alice (~/.software-house/company/wiki/people/alice.md)
    reports_to: nobody
    → "nobody" is not in wiki/people/ or alumni/

  [egress] dan (~/.software-house/company/wiki/people/dan.md)
    provider: anthropic (external) but egress_consent: none
    → run /software-house set-model dan --provider anthropic ... and supply EGRESS-CONSENT-anthropic

WARNINGS
  [orphan] charlie has agent file but no wiki entry
    File: SoftwareHouseSkills/.software-house/agents/charlie.md
    → run /software-house hire charlie ... to create the wiki entry

INFO
  [department] engineering has 0 teams
```

If `--fix-suggestions` is set, append a fix line to each finding.

### 4. Exit posture

- If there are zero errors and zero warnings → print `Wiki is clean. No findings.` and stop.
- If there are findings → end with: `Run /software-house lint --fix-suggestions for suggested commands. Lint never modifies state automatically.`

## Performance

For a wiki with hundreds of pages, the link-integrity pass can be expensive. Read frontmatter via streaming (parse the YAML head only). Use `Grep` for body-text reference checks; do not read entire bodies into context.

## Limits

Lint is structural, not semantic. It will not detect:

- Stale knowledge (a wiki page that contradicts new facts) — that needs human review.
- Misclassified entities (a "confidential" page that should be "internal") — needs policy review.
- Duplicated content across pages — Phase 2+ work.

These limits are by design: lint does not invoke an LLM judgment on content quality; it only checks structural rules.
