# Operation: dashboard -- show gamification stats and skill-tree

**Risk tier:** 1 (read-only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Display a comprehensive dashboard of gamification state across all agents. Reads all agent files from `$WIKI_PEOPLE/`, `$TEAM_AGENTS/`, and `$AGENTS_GLOBAL/`. Computes and displays company-wide XP total and average, top agents by XP (leaderboard), level distribution, recent achievements, team XP comparison, and at-risk OKRs summary. Never modifies any file.

## Invocation patterns

| Command | Behavior |
|---|---|
| `dashboard` | Full company dashboard |
| `dashboard --team <team>` | Dashboard scoped to one team |
| `dashboard --dept <dept>` | Dashboard scoped to one department |
| `dashboard --top N` | Leaderboard size (default 10) |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `--team` | no | Must match an existing entry in `$WIKI_TEAMS` |
| `--dept` | no | Must match an existing directory under `$DEPARTMENTS_HOME` |
| `--top` | no | Positive integer, default 10, max 50 |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`

## Step-by-step protocol

### 1. Validate inputs

If `--team` is given, verify `$WIKI_TEAMS/<team>.md` exists. If not, abort: `Error: team <team> not found. Run /software-house list teams to see available teams.`

If `--dept` is given, verify `$DEPARTMENTS_HOME/<dept>/` exists. If not, abort: `Error: department <dept> not found. Run /software-house list departments to see available departments.`

If `--top` is given, validate it is a positive integer between 1 and 50. Clamp to 50 if larger.

### 2. Collect agent data

Determine scope:
- `--team <team>`: only agents in that team (from `$WIKI_PEOPLE/` filtered by `team` frontmatter field matching `<team>`, plus `$TEAM_AGENTS/` for the team's project).
- `--dept <dept>`: only agents whose `department` frontmatter field matches `<dept>`.
- No scope flag: all agents company-wide.

Read agent data from:
1. `$WIKI_PEOPLE/*.md` -- all active employees.
2. `$AGENTS_GLOBAL/*.md` -- freelance pool agents.
3. `$TEAM_AGENTS/*.md` -- project-scoped canonical agent files (for additional context).

For each agent, parse frontmatter and extract:
- `name`
- `xp`
- `level`
- `achievements`
- `team`
- `department`
- `status`
- `role`
- `provider`

Skip agents with `status: alumni`.

### 3. Compute company-wide stats

Aggregate across all collected agents:

```
total_xp = sum of all agents' xp
average_xp = total_xp / agent_count (rounded to nearest integer)
agent_count = total active agents
```

### 4. Compute leaderboard

Sort agents by XP descending. Take the top `--top` entries (default 10).

```
Leaderboard (top <N>)
+------+----------------+--------+-------+-------+
| Rank | Agent          | XP     | Level | Team  |
+------+----------------+--------+-------+-------+
| 1    | <name>         | <xp>   | <lvl> | <team>|
| 2    | <name>         | <xp>   | <lvl> | <team>|
| ...  |                |        |       |       |
+------+----------------+--------+-------+-------+
```

If two agents have the same XP, sort by level descending, then name ascending.

### 5. Compute level distribution

Count agents at each level:

```
Level Distribution
+-------+--------+
| Level | Count  |
+-------+--------+
| 5     | <n>    |
| 4     | <n>    |
| 3     | <n>    |
| 2     | <n>    |
| 1     | <n>    |
+-------+--------+
```

### 6. Collect recent achievements

Grep `$AUDIT_LOG` for recent achievement-related entries. Filter for lines containing `"op":"award-xp"` and `"achievement"` where the achievement value is not null.

Parse the last 10 such entries. Extract: agent name, achievement name, timestamp.

```
Recent Achievements (last 10)
+---------------------+----------------+----------------------------+
| Timestamp           | Agent          | Achievement                |
+---------------------+----------------+----------------------------+
| <ts>                | <name>         | <achievement>             |
| ...                 |                |                            |
+---------------------+----------------+----------------------------+
```

If no achievement entries exist, display: `(no achievements recorded yet)`.

### 7. Compute team XP comparison

If the scope includes multiple teams (company-wide or department-scoped):

Read all team pages from `$WIKI_TEAMS/*.md`. For each team, extract `team_xp` and `team_level` from frontmatter.

```
Team XP Comparison
+------------------+---------+---------+-----------+
| Team             | Members | Team XP | Team Lvl  |
+------------------+---------+---------+-----------+
| <team-name>      | <count> | <xp>    | <level>   |
| ...              |         |         |           |
+------------------+---------+---------+-----------+
```

Sort by `team_xp` descending.

If scoped to a single team (`--team`), skip this section and instead show the team's own stats in the header.

### 8. Collect at-risk OKRs

Glob for OKR files:
- `$COMPANY_HOME/okrs/*.md`
- `$DEPARTMENTS_HOME/*/okrs/*.md`
- For each project in `$PROJECTS_INDEX`: `<project>/.software-house/team/okrs/*.md`

Read each OKR file. Parse objectives and key results. Identify objectives with status `at-risk` or `off-track`.

```
At-Risk OKRs
+------------------+--------------------------+----------+-----------+
| Scope            | Objective                | Progress | Status    |
+------------------+--------------------------+----------+-----------+
| <scope>          | <objective title>         | <pct>%   | at-risk   |
| <scope>          | <objective title>         | <pct>%   | off-track |
+------------------+--------------------------+----------+-----------+
```

If no at-risk or off-track OKRs, display: `(all OKRs on-track or no OKRs set)`.

### 9. Render full dashboard

Assemble all sections into a single formatted output:

```
+==============================================================+
|  SOFTWARE HOUSE -- GAMIFICATION DASHBOARD                     |
|  Generated: <utc-timestamp>                                  |
|  Scope: <company | team: <name> | dept: <name>>              |
+==============================================================+

COMPANY STATS
  Total agents:   <count>
  Total XP:       <total_xp>
  Average XP:     <average_xp>

<Leaderboard table>

<Level Distribution table>

<Recent Achievements table>

<Team XP Comparison table -- omit if scoped to one team>

<At-Risk OKRs table>

+==============================================================+
|  Use /software-house show <name> for agent details            |
|  Use /software-house okr-review for full OKR analysis         |
+==============================================================+
```

### 10. Report to user

```
Dashboard displayed for <scope>.
  Agents:   <count>
  Total XP: <total_xp>
  Top agent: <name> (<xp> XP, level <level>)
  At-risk OKRs: <count>

No files were modified. This is a read-only operation.
```

## Failure modes

- Company not initialized -> refuse, no log (Tier 1, no state change).
- Team or department not found -> abort with suggestion to list.
- No agents exist -> display empty dashboard with `(no agents hired yet -- run /software-house hire to add your first agent)`.
- Audit log does not exist or is empty -> recent achievements section shows `(none)`.
- No OKR files exist -> at-risk section shows `(no OKRs set -- run /software-house okr-set)`.
- `$PROJECTS_INDEX` missing or malformed -> skip project-scoped OKR scan, continue with company and department OKRs only.

## Examples

```
# Full company dashboard
/software-house dashboard

# Dashboard for a specific team
/software-house dashboard --team api-gateway

# Dashboard for a department, top 5 leaderboard
/software-house dashboard --dept engineering --top 5

# Top 20 leaderboard only (still full dashboard, just larger leaderboard)
/software-house dashboard --top 20
```