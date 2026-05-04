# Operation: show — display one entity in detail

**Risk tier:** 1 (read-only)

**Required reading first:** `operations/_shared.md`

## Purpose

Print full details of one employee, team, or department, including frontmatter fields, recent activity, and cross-references. No state changes.

## Invocation patterns

| Command | Behavior |
|---|---|
| `show <employee-name>` | Default: show employee |
| `show team <team-name>` | Show team with full member list |
| `show dept <dept-name>` | Show department with full team list |

If the argument is ambiguous (matches both an employee and a team), ask the user which they meant.

## Step-by-step

### 1. Resolve the entity

Search in this order:

1. `$WIKI_PEOPLE/<name>.md` — active employee
2. `$ALUMNI/<name>.md` — former employee (mark output as `[ALUMNI]`)
3. `$AGENTS_GLOBAL/<name>.md` — freelance (mark as `[FREELANCE]`)
4. `$WIKI_TEAMS/<name>.md` — team
5. `$WIKI_DEPTS/<name>.md` — department

If `show team <name>` or `show dept <name>` is used, restrict to that namespace.

If nothing matches, print `Not found. Try /software-house list to see available entities.` and stop.

### 2. Read

- Read the entity page in full (frontmatter + body).
- Read its referenced agent file(s) if applicable. For an employee: also read `$TEAM_AGENTS/<name>.md` (the actual subagent definition) if the project context is detectable.
- Read the last 10 lines of `$AUDIT_LOG` filtered to events involving this entity.

### 3. Render

#### Employee

```
+- <position> . <name> --------------------------------------------+
| Role: <role>          Status: <status>      Level: <level>       |
| Team: <team>          Dept: <dept>          XP: <xp>             |
| Reports to: <reports_to>     Buddy: <buddy>                      |
| Provider: <provider> [<class>]   Model: <model>   Effort: <eff>  |
| Egress consent: <egress_consent>                                 |
| Classification: <classification>    Hired: <hired_at>            |
+------------------------------------------------------------------+

Description
  <description from frontmatter>

Body
  <full body of wiki/people/<name>.md>

Achievements
  <list, or "(none yet)">

Recent activity (last 10 audit entries)
  <ts>  <op>  <summary>
  ...
```

The Provider line shows the configured provider key plus its class from `$PROVIDERS_CONFIG` in brackets (e.g., `Provider: ollama [local]` or `Provider: anthropic [external]`). The Egress consent line shows `none` for local providers or `external:<utc-date>` for external providers. The skill MAY substitute the ASCII `+--`/`|` markers with the Unicode box-drawing equivalents (`├── │ └──`) when the rendering context supports them — never substitute emoji.

#### Team

```
+- Team: <name> ---------------------------------------------------+
| Department: <dept>     Lead: <lead>                              |
| Members: <count>        Team Level: <level>     Team XP: <xp>    |
| Project path: <path>   Status: <status>                          |
+------------------------------------------------------------------+

Description
  <description>

Members
  <name> [<role>] Lv.<level>  — <position>
  ...

Recent activity
  ...
```

#### Department

```
+- Department: <name> ---------------------------------------------+
| Head: <head>     Teams: <count>     Total members: <count>       |
+------------------------------------------------------------------+

Description
  <description>

Teams
  <team> — <member-count> members, lead: <lead>
  ...
```

### 4. Cross-references

If the entity page or agent file mentions other entity names (anywhere in the body), list them at the end as:

```
See also: <name1>, <name2>, ...
```

Run `Grep` to find references. Do not invent links.

## Empty / error states

- Entity not found → `Not found. Try /software-house list.`
- Entity exists but file is malformed (invalid frontmatter) → print what you can read, then `Warning: frontmatter could not be parsed in <path>`. Do not auto-fix; tell the user to inspect.

## Output style

- Match the user's language.
- The box-drawing header is decorative — if rendering in a context that doesn't support it, fall back to plain `# <heading>` markdown.
- Truncate the body if longer than 50 lines and offer: `(... truncated. Read <path> for full content.)`
