# Operation: org-chart — render the org tree

**Risk tier:** 1 (read-only)

**Required reading first:** `operations/_shared.md`

## Purpose

Print an ASCII tree of the company hierarchy: Company → Departments → Teams → Employees, following `reports_to` links to show the manager-report graph within each team.

## Invocation patterns

| Command | Scope |
|---|---|
| `org-chart` | Whole company |
| `org-chart <team>` | One team only |
| `org-chart dept <dept>` | One department, all its teams |

## Step-by-step

### 1. Read all entity frontmatter

Glob `$WIKI_PEOPLE/*.md`, `$WIKI_TEAMS/*.md`, `$WIKI_DEPTS/*.md`. Read frontmatter only.

Build three in-memory maps:

- `people_by_team[team] = [person, ...]`
- `teams_by_dept[dept] = [team, ...]`
- `parent_map[person] = reports_to`

### 2. Detect and report cycles

Within each team, check that `reports_to` does not form a cycle. If it does, print a warning at the top of the chart and break the cycle visually by marking the offending node with `(!)`.

### 3. Render

Use plain ASCII markers — never emoji. The markers are:

- `[C]` — Company
- `[D]` — Department
- `[T]` — Team
- `*` — Person (employee, local-provider agent)
- `*x` — Person whose agent uses an external provider (egress on run)
- `(!)` — Warning marker for cycle, cross-team report, or other issue

The `*x` vs `*` distinction is derived from the person's `provider` field looked up in `$PROVIDERS_CONFIG`. It lets the user spot, at a glance, which agents will egress when they run. There is no judgment attached — the user has already given consent for any `*x` agent at hire time.

#### Whole company

```
[C] Company  (3 depts, 5 teams, 12 employees)
|
+-- [D] engineering  (head: tech-lead, 3 teams, 8 employees)
|   |
|   +-- [T] SoftwareHouseSkills  (lead: tech-lead, 5 employees)
|   |   +-- * tech-lead [tech-lead] Lv.5
|   |   |   +-- * alice [backend-dev] Lv.2
|   |   |   +-- * bob [frontend-dev] Lv.3
|   |   |   +-- * carol [code-reviewer] Lv.4
|   |   +-- * dan [doc-writer] Lv.1   (no reports_to)
|   |
|   +-- [T] another-project  (...)
|
+-- [D] quant-trading  (...)
|
+-- [D] content-growth  (...)

Freelance pool: 2 contractors  (run `/software-house list outsource`)
```

#### Single team

```
[T] SoftwareHouseSkills  (department: engineering, 5 employees)
|
+-- * tech-lead [tech-lead] Lv.5  -- Tech Lead
|   +-- * alice [backend-dev] Lv.2  -- Backend Developer
|   +-- * bob [frontend-dev] Lv.3  -- Frontend Developer
|   +-- * carol [code-reviewer] Lv.4  -- Code Reviewer
+-- * dan [doc-writer] Lv.1  -- Documentation Writer (no manager)
```

You may use the box-drawing variant (`+--`, `|`, `\--`) instead of ASCII pipes if the user's terminal supports it well; the choice is between two ASCII-safe styles. Never substitute emoji icons for the role markers above.

### 4. Tree-rendering rules

- Use ASCII tree characters: `+--` and `|` (or the box-drawing equivalents `├──`, `│`, `└──`). Both are ASCII-safe.
- Indent one level per `reports_to` depth.
- Sort siblings alphabetically by name.
- Show `[role]` and `Lv.N` inline next to each name.
- If `position` is set, show `-- <position>` after the level.
- Mark special states inline as text: `(onboarding)`, `(transfer)`, `(!)` for issues. No emojis.
- Use `*` vs `*x` to distinguish local-provider vs external-provider agents per §3.
- An employee with no `reports_to` and no reports under them is a sibling of the team lead at the team level (not under anyone).

### 5. Edge cases

- A team with no lead → print the team header followed by `(no lead assigned -- set with /software-house promote <name>)`.
- An employee whose `reports_to` points to someone in a different team → mark `(!) cross-team report: <name>` and render under the local team root.
- An empty team → print the team header and `(no members)`.
- An empty department → print the department header and `(no teams)`.

### 6. Counts in the header

Always include counts in headers: `(N depts, M teams, K employees)`. Counts are truthful — do not estimate.

## Empty / error states

- No company yet → tell the user to run `/software-house init`.
- No teams or people → print `Org chart is empty. Run /software-house hire to add your first employee.`

## Output style

- Match the user's language (label translations, e.g., "department" → "ฝ่าย").
- ASCII only. Never substitute emoji for `[C]`, `[D]`, `[T]`, `*`, or `(!)`.
