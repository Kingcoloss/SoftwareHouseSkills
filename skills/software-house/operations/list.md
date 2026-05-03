# Operation: list — show employees, teams, or departments

**Risk tier:** 1 (read-only)

**Required reading first:** `operations/_shared.md`

## Purpose

Print a tabular summary of the company's people, teams, or departments. No state changes, no confirmation, no audit log entry.

## Invocation patterns

| Command | Behavior |
|---|---|
| `list` | Default: list all employees grouped by team |
| `list people` | List all employees as a flat table |
| `list teams` | List all teams with member counts |
| `list departments` (or `list dept`) | List all departments with team counts |
| `list outsource` | List freelance pool |
| `list <team-name>` | List employees in that specific team |
| `list alumni` | List archived (former) employees |

## Step-by-step

### 1. Resolve the variant

Inspect arguments and route to one of the variants above. If the argument is unrecognized, treat it as a team name and try `list <team-name>`.

### 2. Read sources

Glob the relevant directory:

| Variant | Source |
|---|---|
| `list people` (default) | `$WIKI_PEOPLE/*.md` |
| `list teams` | `$WIKI_TEAMS/*.md` |
| `list departments` | `$WIKI_DEPTS/*.md` |
| `list outsource` | `$OUTSOURCE_MANIFEST` plus `$AGENTS_GLOBAL/*.md` |
| `list <team-name>` | `$WIKI_PEOPLE/*.md` filtered by `team` frontmatter field |
| `list alumni` | `$ALUMNI/*.md` |

Read frontmatter only — no need to read full bodies.

### 3. Render

Use a table. Columns vary by variant:

#### People

| Name | Role | Team | Dept | Status | Lvl | Provider | Model | Effort |

The `Provider` column shows the configured provider key; if its class in `$PROVIDERS_CONFIG` is `external`, append a `*` to the cell (e.g., `anthropic*`) so the user can spot egress agents at a glance.

#### Teams

| Team | Department | Members | Lead | Status | Team Lvl |

#### Departments

| Department | Head | Teams | Members |

#### Outsource

| Name | Role | Hired by teams | Provider | Model |

Same `*` suffix rule as the People table — external providers are flagged.

#### Alumni

| Name | Role | Last team | Off-boarded at |

### 4. Summary line

End with a one-line summary: total counts and any notable status (e.g., `3 people, 1 onboarding, 1 transfer in progress, 2 external-provider`). The external-provider count is the number of agents whose provider class is `external` per `$PROVIDERS_CONFIG`.

## Empty states

- If `$COMPANY_HOME` does not exist → tell the user to run `/software-house init` first.
- If a variant has zero entries → print the empty table headers and a row that says `(none)`.
- If `list <team-name>` matches no team → suggest `/software-house list teams` to see available teams.

## Performance

If there are many people (>100), prefer reading frontmatter only via `Grep` for `^---` blocks and YAML head, rather than `Read`-ing entire files. The frontmatter contains all fields needed for the table.

## Output style

- Match the user's language (Thai or English).
- Use markdown tables.
- Truncate long descriptions to fit the row width — the user can run `show <name>` for full detail.
