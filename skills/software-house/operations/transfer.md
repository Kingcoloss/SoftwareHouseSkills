# Operation: transfer -- transfer agent to another team

**Risk tier:** 3 (modifying -- changes agent's team, updates both team rosters and adapters)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Move an agent from one team to another. The canonical agent file's `team` field is updated. The agent is removed from the old team's roster and added to the new team's roster. Harness adapters are removed from the old team's project directory and written in the new team's project directory. If the transfer crosses projects with different `$MODELS_CONFIG` (different provider classification), an egress re-consent gate is triggered before the Tier-3 confirmation. The transfer is logged to `$TEAM_TRANSFERS` for both teams.

## Invocation patterns

| Command | Behavior |
|---|---|
| `transfer <name> --to <team>` | Transfer agent from current team to target team |
| `transfer <name> --to <team> --team <current>` | Override current team resolution |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--to <team>` | yes | Must match `^[a-z][a-z0-9-]{0,63}$`; must exist in `$WIKI_TEAMS` |
| `--team <current>` | no | Override current team; must exist in `$WIKI_TEAMS` |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active`, `status: onboarding`, or `status: transfer`. Refuse for `status: alumni`: `Error: <name> is archived (status: alumni). Cannot transfer.`
4. The destination team `<team>` (from `--to`) must exist in `$WIKI_TEAMS`. If not, refuse: `Error: team <team> not found. Run /software-house list teams to see available teams.`
5. The agent's current team must not be the same as the destination team. If same, refuse: `Error: <name> is already on team <team>. No transfer needed.`

## Step-by-step protocol

### 1. Resolve agent and teams

Read the canonical agent file. Parse frontmatter. Extract: `team`, `role`, `provider`, `model`, `effort_preset`, `department`, `status`, `classification`, `employment`, `hired_by_teams`.

Resolve the current team:
- If `--team <current>` is given, use it.
- Otherwise, use the `team` field from the agent frontmatter.
- If `team` is `null` and `--team` is not given, refuse: `Error: <name> has no current team. Use --team to specify the source, or use /software-house contract instead.`

Resolve the destination team from `--to <team>`:
- Read `$WIKI_TEAMS/<team>.md`. Parse frontmatter. Extract `project_path`, `department`, `lead`, `members`.
- If the wiki page does not exist, refuse per Precondition 4.

Determine old project root from `$PROJECTS_INDEX` using the old team name. Determine new project root from `$PROJECTS_INDEX` using the new team name or from the `project_path` field in the new team's wiki page.

### 2. Detect egress re-consent requirement

If the transfer crosses project boundaries (different project roots), the new project may use a different `$MODELS_CONFIG`. Read `$PROVIDERS_CONFIG` to classify the agent's current provider.

- If current provider is `local` and the new project's default for the agent's role (from the new project's `$MODELS_CONFIG`) is `external`, print a warning but do NOT require re-consent (the agent's own provider does not change; the warning is informational only).
- If current provider is `external`, check whether the new project's `$MODELS_CONFIG` maps the agent's role to a different external provider. If the provider key would change, egress re-consent IS required: set `egress_reconsent_required = true` and record the new provider.
- If the agent's provider stays the same, no re-consent is needed.

When `egress_reconsent_required` is true, this must happen BEFORE the Tier-3 confirmation.

### 3. Egress re-consent gate (if required)

If `egress_reconsent_required` is true, print the egress consent prompt per `safety.md §3`:

```
+----------------------------------------------------------+
| WARNING -- External provider selected: <provider>        |
| When this agent runs, its conversations will be sent to: |
|   <default_endpoint from providers.json>                 |
| This egress is performed by the agent runtime, not by    |
| this skill. The skill itself never makes network calls.  |
|                                                          |
| To approve this egress, type the literal token:          |
|   EGRESS-CONSENT-<provider>                              |
| Anything else, or no response, will cancel the transfer.  |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- If the token `EGRESS-CONSENT-<provider>` appears, record it and advance to Step 4.
- Otherwise, abort. Print: `Transfer cancelled -- egress consent not given for provider <provider>.` Do not log.

### 4. Compute diff

Build the modification plan showing all changes:

```
File: <canonical agent file> (frontmatter)
  field team: <old-team> -> <new-team>
  field status: <current-status> -> active
  field updated_at: <old-value | "absent"> -> <utc-date>

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  field team: <old-team> -> <new-team>

File: $WIKI_TEAMS/<old-team>.md (frontmatter)
  members list: remove <name>

File: $WIKI_TEAMS/<new-team>.md (frontmatter)
  members list: add <name>

Adapters to REMOVE (old project):
  <list each adapter path, one per line, or "(none detected)">

Adapters to WRITE (new project):
  <list each adapter path, one per line, or "(none detected)">

Transfer logs:
  $TEAM_TRANSFERS (old project): append entry
  $TEAM_TRANSFERS (new project): append entry
```

Also update `$AUDIT_LOG` (append) and `$COMPANY_INDEX` (rebuild).

### 5. Tier-3 confirmation

Print the full diff from Step 4. Print the paths that will be modified. Then print the Tier-3 prompt from `safety.md §3`:

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse per `safety.md §9`. If non-affirmative, abort. Do not log.

### 6. Update canonical agent file

Using atomic write per `_shared.md §6`, update the following frontmatter fields:

```yaml
team: <new-team>
status: active
updated_at: <utc-date YYYY-MM-DD>
```

If `egress_reconsent_required` was true and consent was given, also update:

```yaml
egress_consent: external:<utc-date>
```

### 7. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update `team: <new-team>` in the frontmatter using atomic write per `_shared.md §6`.

### 8. Remove agent from old team roster

Read `$WIKI_TEAMS/<old-team>.md`. Remove `<name>` from the `members` list in the frontmatter. Update `updated_at: <utc-date>` field. Write atomically per `_shared.md §6`.

### 9. Add agent to new team roster

Read `$WIKI_TEAMS/<new-team>.md`. Append `<name>` to the `members` list in the frontmatter. Update `updated_at: <utc-date>` field. Write atomically per `_shared.md §6`.

### 10. Remove adapters from old project

For each harness adapter path in the old project that exists:
- Claude Code adapter: `rm <old-project>/.claude/agents/<name>.md`
- Codex CLI adapter: `rm <old-project>/.codex/agents/<name>.md`
- Gemini CLI extension dir: `rm -rf <old-project>/.gemini/extensions/<name>/`

These are auto-generated shims with no unique content. Removal is safe.

### 11. Write adapters in new project

Detect installed harnesses under the new project root. For each detected harness, write the adapter per `_shared.md §3`:

#### Claude Code adapter

`<new-project>/.claude/agents/<name>.md`:

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

#### Codex CLI adapter

`<new-project>/.codex/agents/<name>.md` (create `.codex/agents/` dir if missing):

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>
```

#### Gemini CLI adapter

Create `<new-project>/.gemini/extensions/<name>/` directory.

Write `<new-project>/.gemini/extensions/<name>/gemini-extension.json`:

```json
{
  "name": "<name>",
  "version": "1.0",
  "description": "<role> agent (software-house managed)",
  "canonicalPath": "<absolute path to canonical agent file>"
}
```

Write `<new-project>/.gemini/extensions/<name>/GEMINI.md`:

```markdown
# <name>

Managed by software-house skill.
Canonical definition: <absolute path to canonical agent file>

Role: <role>
Provider: <provider>
Effort: <effort_preset>
```

### 12. Append to transfer logs

Append a transfer entry to the old team's `$TEAM_TRANSFERS`:

```
<utc-timestamp> | <name> | out | from: <old-team> | to: <new-team>
```

Append a transfer entry to the new team's `$TEAM_TRANSFERS`:

```
<utc-timestamp> | <name> | in | from: <old-team> | to: <new-team>
```

If either `$TEAM_TRANSFERS` file does not exist, create it with a header line:

```
# Transfer Log -- <team>
```

### 13. Rebuild indexes

Rebuild `$TEAM_INDEX` for both old and new projects (if they exist) and `$COMPANY_INDEX` per `_shared.md §8`.

### 14. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"transfer","scope":"agent:<name>","args":{"name":"<name>","from_team":"<old-team>","to_team":"<new-team>"},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","$WIKI_TEAMS/<old-team>.md","$WIKI_TEAMS/<new-team>.md"],"removed":["<old adapter paths>"],"created":["<new adapter paths>","<transfer log entries>"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":<bool>,"granted":"<token|null>","provider":"<provider|null>","ts":"<utc|null>"},"result":"ok"}
```

### 15. Report to user

```
Transferred <name> from <old-team> to <new-team>
  Canonical:    <canonical agent path>
  Wiki:         $WIKI_PEOPLE/<name>.md
  Old adapters: removed (<list or "none">)
  New adapters: written (<list or "none">)
  Egress:       <none | re-consented at <utc-date>>

Next steps:
  /software-house show <name>           verify the updated agent record
  /software-house onboard <name>        regenerate briefing for new team context
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent status is alumni -> refuse before any gate; no log.
- Destination team not found -> refuse before any gate; no log.
- Agent already on destination team -> refuse; no log.
- Egress re-consent not given -> abort; no log; no changes.
- Confirmation non-affirmative -> abort; no log; no changes.
- `mv` or `rm` failure on adapter -> log warning but continue; report the path that could not be removed.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.

## Examples

```
# Transfer alice from current team to the platform team
/software-house transfer alice --to platform

# Transfer bob with explicit source team
/software-house transfer bob --to api-gateway --team backend

# Transfer across projects (may trigger egress re-consent if provider differs)
/software-house transfer carol --to frontend --team backend
```