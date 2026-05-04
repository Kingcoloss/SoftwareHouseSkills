# Operation: set-model -- change agent's provider/model/effort

**Risk tier:** 3 (modifying -- special: egress re-consent when switching from local to external)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Change an agent's provider, model, and/or effort preset. The canonical agent file is the source of truth -- all harness adapters are regenerated atomically from it. When switching from a local provider to an external provider, egress re-consent is REQUIRED before the Tier-3 confirmation. When switching from one external provider to a different external provider, egress re-consent for the NEW provider is REQUIRED. When switching from external to local, no egress consent is needed (downgrade is always allowed). The wiki people page frontmatter is also updated.

## Invocation patterns

| Command | Behavior |
|---|---|
| `set-model <name> --provider <p> --model <m>` | Change provider and model |
| `set-model <name> --model <m>` | Change model only (keep current provider) |
| `set-model <name> --effort <e>` | Change effort preset only |
| `set-model <name> --provider <p> --model <m> --effort <e>` | Change all three |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--provider <p>` | no | Must exactly match a key in `$PROVIDERS_CONFIG`; requires `--model` |
| `--model <m>` | conditional | Required if `--provider` is given; must be a non-empty string |
| `--effort <e>` | no | One of `low`, `medium`, `high` |

At least one of `--provider`, `--model`, or `--effort` must be given. If none are provided, refuse: `Error: at least one of --provider, --model, or --effort is required.`

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. The canonical agent file for `<name>` must exist. If not, refuse: `Error: agent <name> not found.`
3. The agent must have `status: active` or `status: onboarding`. Refuse for `status: alumni`: `Error: <name> is archived (status: alumni). Cannot modify.`
4. `$PROVIDERS_CONFIG` is readable. If not, refuse with lint-style error.
5. If `--provider` is given, it must match a key in `$PROVIDERS_CONFIG`. If not, list valid provider keys and abort.

## Step-by-step protocol

### 1. Validate inputs

Read the canonical agent file. Parse frontmatter. Extract: `provider`, `model`, `effort_preset`, `role`, `team`, `status`, `employment`, `egress_consent`.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

If `--provider` is given:
- Validate against `$PROVIDERS_CONFIG`. Abort if not found.
- If `--model` is not given, abort: `Error: --model is required when --provider is specified.`

If `--model` is given without `--provider`:
- The model string must be non-empty. Abort if empty.
- The provider stays the same; only model changes.

If `--effort` is given:
- Validate it is one of `low`, `medium`, `high`. Abort if not.

Determine the resolved values:
- New provider: `--provider` if given, otherwise current `provider` from frontmatter.
- New model: `--model` if given, otherwise current `model` from frontmatter.
- New effort: `--effort` if given, otherwise current `effort_preset` from frontmatter.

### 2. Determine egress consent requirement

Classify the current provider and new provider using `$PROVIDERS_CONFIG`:

| Current provider | New provider | Egress consent required |
|---|---|---|
| local | local | No |
| local | external | Yes -- must consent to new provider |
| external | local | No (downgrade always allowed) |
| external | same external | No (provider unchanged) |
| external | different external | Yes -- must consent to new provider |

If egress consent is required, set `egress_reconsent_required = true` and record the new provider key.

If switching from external to local, set `clear_egress_consent = true`.

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
| Anything else, or no response, will cancel the change.   |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- If the token `EGRESS-CONSENT-<provider>` appears, record it and advance to Step 4.
- Otherwise, abort. Print: `Model change cancelled -- egress consent not given for provider <provider>.` Do not log.

### 4. Compute diff

Build the modification plan showing all changes:

```
File: <canonical agent file> (frontmatter)
  <If provider changed:>
  field provider: <old-provider> -> <new-provider>
  <If model changed:>
  field model: <old-model> -> <new-model>
  <If effort changed:>
  field effort_preset: <old-effort> -> <new-effort>
  field updated_at: <old-value | "absent"> -> <utc-date YYYY-MM-DD>
  <If egress re-consent given:>
  field egress_consent: <old-value> -> external:<utc-date>
  <If switching external to local:>
  field egress_consent: <old-value> -> none

File: $WIKI_PEOPLE/<name>.md (frontmatter)
  <same fields as canonical>

Adapters to RE-WRITE (all detected harnesses across all project roots):
  Primary project:
    <list each adapter path, one per line, or "(none detected)">
  <For each secondary/hired-by team with adapters:>
  <team-name> project:
    <list each adapter path, one per line, or "(none detected)">
```

Also update `$AUDIT_LOG` (append).

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
provider: <new-provider>  # if changed
model: <new-model>        # if changed
effort_preset: <new-effort>  # if changed
updated_at: <utc-date YYYY-MM-DD>
```

If egress re-consent was given:

```yaml
egress_consent: external:<utc-date>
```

If switching from external to local:

```yaml
egress_consent: none
```

### 7. Update wiki people page

If `$WIKI_PEOPLE/<name>.md` exists, update the same frontmatter fields as Step 6 (mirroring canonical agent file). Use atomic write per `_shared.md §6`.

### 8. Re-write ALL harness adapters

The canonical agent file is the source of truth. All harness adapters are regenerated from it. For each detected harness, overwrite the adapter with fresh content per `_shared.md §3`:

#### Claude Code adapter

`$PROJECT/.claude/agents/<name>.md`:

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <new-model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>

Role: <role>
Provider: <new-provider>
Effort: <new-effort>
```

#### Codex CLI adapter

`$PROJECT/.codex/agents/<name>.md` (create `.codex/agents/` dir if missing):

```yaml
---
name: <name>
description: <role> agent (software-house managed)
model: <new-model>
---

Managed by software-house skill. Canonical definition:
  <absolute path to canonical agent file>
```

#### Gemini CLI adapter

Create `$PROJECT/.gemini/extensions/<name>/` directory if missing.

Write `$PROJECT/.gemini/extensions/<name>/gemini-extension.json`:

```json
{
  "name": "<name>",
  "version": "1.0",
  "description": "<role> agent (software-house managed)",
  "canonicalPath": "<absolute path to canonical agent file>"
}
```

Write `$PROJECT/.gemini/extensions/<name>/GEMINI.md`:

```markdown
# <name>

Managed by software-house skill.
Canonical definition: <absolute path to canonical agent file>

Role: <role>
Provider: <new-provider>
Effort: <new-effort>
```

Detect installed harnesses using existence checks:

```
test -d ~/.claude  -> HAS_CLAUDE_CODE
test -d ~/.codex || test -d ~/.agents  -> HAS_CODEX
test -d ~/.gemini  -> HAS_GEMINI
```

For freelance pool agents (no project context), skip adapter writing -- adapters are written only when the agent is contracted to a project.

After writing adapters for the primary project, also update adapters in additional project roots where this agent has a presence:

1. Read the canonical agent file. Extract `secondary_teams` and `hired_by_teams` arrays.
2. For each team name in `secondary_teams` (permanent employees) or `hired_by_teams` (freelance employees):
   a. Resolve the project root from `$PROJECTS_INDEX` using the team name.
   b. If no project root found, skip this team (warn but continue).
   c. Detect installed harnesses under that project root.
   d. For each detected harness, write the adapter using the same format as above, with the canonical path pointing to `$TEAM_AGENTS/<name>.md` (for project-scoped) or `$AGENTS_GLOBAL/<name>.md` (for freelance).
3. Include all additional adapter paths in the diff and audit log.

### 9. Rebuild indexes

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"set-model","scope":"agent:<name>","args":{"name":"<name>","from_provider":"<old-provider>","from_model":"<old-model>","to_provider":"<new-provider>","to_model":"<new-model>","from_effort":"<old-effort>","to_effort":"<new-effort>"},"diff":{"updated":["<canonical agent path>","$WIKI_PEOPLE/<name>.md","<adapter paths>","$COMPANY_INDEX"]},"confirmation":{"tier":3,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":<bool>,"granted":"<token|null>","provider":"<provider|null>","ts":"<utc|null>"},"result":"ok"}
```

### 11. Report to user

```
Updated model for <name>
  Provider: <old-provider> -> <new-provider>  <or "(unchanged)">
  Model:    <old-model> -> <new-model>  <or "(unchanged)">
  Effort:   <old-effort> -> <new-effort>  <or "(unchanged)">
  Egress:   <none | re-consented at <utc-date> | cleared>
  Canonical: <canonical agent path>
  Wiki:      $WIKI_PEOPLE/<name>.md
  Adapters:  re-written (<list or "none detected">)

Next steps:
  /software-house show <name>           verify the updated agent record
```

## Failure modes

- Agent not found -> refuse before any gate; no log.
- Agent status is alumni -> refuse before any gate; no log.
- `--provider` given without `--model` -> abort; no log.
- Provider not in `$PROVIDERS_CONFIG` -> list valid providers, abort; no log.
- Egress consent not given -> abort; no log; no changes.
- Confirmation non-affirmative -> abort; no log; no changes.
- Atomic write failure -> roll back `.tmp` files; log `result: failed`.
- Adapter write failure -> log warning but continue; report the path that could not be written.

## Examples

```
# Change model only (same provider)
/software-house set-model alice --model qwen3-coder:32b

# Change provider and model (triggers egress consent if external)
/software-house set-model bob --provider anthropic --model claude-opus-4-7

# Change effort preset only
/software-house set-model carol --effort high

# Change provider, model, and effort
/software-house set-model dave --provider openai --model gpt-4o --effort medium

# Downgrade from external to local (no egress consent needed)
/software-house set-model alice --provider ollama --model qwen3-coder:32b
```