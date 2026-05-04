# Operation: onboard -- write personalized briefing for a new agent

**Risk tier:** 2 (additive -- creates or updates sidecar briefing file; idempotent re-run updates briefing in place)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

After `hire`, populate the agent's onboarding briefing: read the team's charter files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) and the project's existing wiki context, then write a personalized briefing into a sidecar file `<name>.onboard.md` alongside the canonical agent file. Append a summary into the agent's frontmatter (`onboard_at` timestamp and `onboard_status: done`). Register the agent in the team's org-chart entry. Idempotent -- re-running `onboard` for an already-onboarded agent overwrites the briefing with a fresh one (still Tier 2 because no data is deleted).

No egress. All reads and writes are local.

## Invocation patterns

| Command | Behavior |
|---|---|
| `onboard <name>` | Onboard agent in the current project team |
| `onboard <name> --team <team>` | Onboard agent in a specific team |
| `onboard <name> --pool` | Onboard a freelance pool agent (uses company-tier charter only) |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` |
| `--team` | no | Override team; must exist in `$WIKI_TEAMS` |
| `--pool` | no | Target freelance pool agent at `$AGENTS_GLOBAL/<name>.md` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized).
2. The canonical agent file for `<name>` must exist at `$TEAM_AGENTS/<name>.md` (or `$AGENTS_GLOBAL/<name>.md` for `--pool`). If not, refuse: `Error: agent <name> not found. Run /software-house hire <name> first.`
3. For project scope, the project must be detected or `--team` must be provided.

## Step-by-step protocol

### 1. Resolve scope and agent file

Determine canonical path:
- `--pool` flag -> `$AGENTS_GLOBAL/<name>.md`
- `--team <t>` override -> locate project root from `$PROJECTS_INDEX` by team name -> `<project>/.software-house/agents/<name>.md`
- Auto-detect from `pwd` via `$PROJECTS_INDEX` -> `$TEAM_AGENTS/<name>.md`

Read the canonical agent file. Parse frontmatter. Extract: `role`, `provider`, `model`, `effort_preset`, `team`, `department`, `status`, `classification`.

### 2. Check idempotency state

Check whether `<name>.onboard.md` already exists at the same directory as the canonical agent file.

- If it exists and `onboard_status: done` is in the agent frontmatter, this is a re-onboard. Print:
  ```
  Note: <name> has been onboarded before (onboard_at: <date>). Re-running will overwrite the briefing.
  ```
  Continue (still Tier 2 -- briefing file is additive on first run, updated on re-run; audit log records both).

- If not present, this is a fresh onboard. Continue.

### 3. Read charter context

Read the following files (skip any that do not exist -- non-fatal):

For project-scoped agents:
- `$PROJECT/CLAUDE.md` -- team charter for Claude Code
- `$PROJECT/AGENTS.md` -- team charter for Codex CLI
- `$PROJECT/GEMINI.md` -- team charter for Gemini CLI
- `$TEAM_INDEX` -- team wiki index (people, teams, OKRs listed)
- `$TEAM_ROSTER` -- current team roster

For pool-scoped agents:
- `$COMPANY_HOME/CLAUDE.md` -- company schema
- `$COMPANY_INDEX` -- company-tier index

Collect the role-specific defaults for the agent's `role` from `$MODELS_CONFIG`. This provides context on what the role is meant to do.

### 4. Build briefing content

Synthesize a briefing document using the information read in Step 3. The briefing is a markdown file (no frontmatter). It must contain all of the following sections:

```
# Onboarding Briefing: <name>

Generated: <utc-timestamp>
Role: <role>
Team: <team | "Freelance Pool">
Department: <dept | none>

## Your Role

<One paragraph describing what the role (<role>) is responsible for,
drawn from models-config.json role key and any description in the wiki.>

## Team Context

<Summary of the team's purpose, drawn from CLAUDE.md / AGENTS.md / GEMINI.md.
If no charter exists, write: "No team charter found at <project path>. Ask the team lead to run /software-house init or add a CLAUDE.md.">

## Current Roster

<List of team members from $TEAM_ROSTER, or "(roster not yet populated)".>

## Your Provider and Model

Provider: <provider> [<class>]
Model:    <model>
Effort:   <effort_preset>

<If provider is external, add: "Your conversations will egress to <endpoint> when you run. This was consented to at <egress_consent date>.">
<If provider is local, add: "Your conversations remain on this machine.">

## Working Conventions

<Extract any conventions from CLAUDE.md / AGENTS.md relevant to the agent's role.
If no relevant conventions found, write: "(No role-specific conventions found in charter -- consult team lead.)">

## First Steps

1. Review the team charter at: <charter path(s) that exist>
2. Check your canonical definition: <canonical agent file path>
3. Introduce yourself to the team lead.
4. Pick up your first task from the project backlog.
```

Do not hallucinate content. If a source file is missing, say so plainly in the relevant section.

### 5. Tier-2 confirmation

Print the briefing path and the index path that will be updated:

```
I will create/update the following:
  Briefing:   <canonical-dir>/<name>.onboard.md
  Agent file: <canonical agent file> (frontmatter fields: onboard_at, onboard_status)
  Index:      $TEAM_INDEX (or $COMPANY_INDEX for pool)
  Audit log:  $AUDIT_LOG
```

Print the Tier-2 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Write briefing sidecar file

Write `<canonical-dir>/<name>.onboard.md` with the content built in Step 4. Use Write (new file) or atomic write (existing file) per `_shared.md §6`.

### 7. Update agent frontmatter

Using the atomic write pattern from `_shared.md §6`, add or update these two fields in the canonical agent file's frontmatter:

```yaml
onboard_at: <utc-date YYYY-MM-DD>
onboard_status: done
```

Also update `status` from `onboarding` to `active` if it is currently `onboarding`.

### 8. Update org-chart entry

Read `$TEAM_ROSTER`. If it does not exist, create it with a skeleton. Append or update the agent's entry:

```
| <name> | <role> | <provider> [<class>] | Lv.1 | onboarded: <date> |
```

If the agent already appears in the roster (re-onboard), update the `onboarded:` date in-place using atomic write.

### 9. Rebuild index

Rebuild `$TEAM_INDEX` (or `$COMPANY_INDEX` for pool) per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"onboard","scope":"<team:<name> | agent:<name>>","args":{"name":"<name>","team":"<team|null>","pool":<bool>,"reonboard":<bool>},"diff":{"created":["<briefing path>"],"updated":["<agent file>","<roster>","<index>"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":false},"result":"ok"}
```

`reonboard: true` if the agent was already onboarded (Step 2 detected existing briefing).

### 11. Report to user

```
Onboarded <name>
  Briefing:  <canonical-dir>/<name>.onboard.md
  Status:    active
  Roster:    updated

Next steps:
  /software-house show <name>       verify the full agent record
  /software-house dept-assign <name> <dept>   assign to a department
```

## Integration with show.md

The `show` operation already reads the canonical agent file frontmatter. After onboarding, `show <name>` will display `onboard_status: done` and `onboard_at: <date>` in the frontmatter fields. No changes to `show.md` are required; the new fields appear automatically.

## Failure modes

- Agent not found -> refuse before any confirmation gate; no log.
- Charter files missing (CLAUDE.md etc.) -> continue with reduced context; note in briefing.
- Atomic write failure on agent frontmatter -> roll back `.tmp`, log `result: failed`.
- Re-onboard: if the user cancels the Tier-2 prompt, the existing briefing is preserved unchanged.

## Examples

```
# Onboard alice on the current project team
/software-house onboard alice

# Onboard bob specifying the team explicitly
/software-house onboard bob --team api-gateway

# Re-onboard alice after team charter was updated
/software-house onboard alice
```
