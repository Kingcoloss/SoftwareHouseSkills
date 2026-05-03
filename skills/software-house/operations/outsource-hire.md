# Operation: outsource-hire -- add agent to freelance/outsource pool

**Risk tier:** 2 (additive -- creates new files in the freelance pool)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Hire an agent into the freelance/outsource pool at `$AGENTS_GLOBAL/<name>.md`. Similar to `hire --pool` but with outsource-specific semantics: contract terms, hourly rate placeholder, and contract duration. The agent is added to the `$OUTSOURCE_MANIFEST` freelancers list. No per-project adapters are written at hire time (pool agents get adapters when contracted to a project via the `contract` operation). If the provider is external, an egress consent gate is required before writing any file.

## Invocation patterns

| Command | Behavior |
|---|---|
| `outsource-hire <name> --role <role>` | Hire into freelance pool with role defaults from `$MODELS_CONFIG` |
| `outsource-hire <name> --role <role> --provider <p> --model <m>` | Override provider and model |
| `outsource-hire <name> --role <role> --effort <e>` | Override effort preset |
| `outsource-hire <name> --role <role> --contract-type <type>` | Specify contract type (default: retainer) |
| `outsource-hire <name> --role <role> --contract-end <date>` | Specify contract end date |

## Inputs

| Input | Required | Validation |
|---|---|---|
| `name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` per `_shared.md §10` |
| `--role` | yes | Must exactly match a key in `defaults_by_role` in `$MODELS_CONFIG` |
| `--provider` | no | Must exactly match a key in `$PROVIDERS_CONFIG`; defaults to role default |
| `--model` | no | Required if `--provider` is given; must be a non-empty string |
| `--effort` | no | One of `low`, `medium`, `high`; defaults to role default |
| `--contract-type` | no | One of `retainer`, `hourly`, `project`; defaults to `retainer` |
| `--contract-end` | no | ISO-8601 date (`YYYY-MM-DD`) or `null`; defaults to `null` (open-ended) |

## Preconditions

1. `$COMPANY_HOME` exists (company is initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. `$PROVIDERS_CONFIG` is readable. If not, refuse with lint-style error.
3. `$MODELS_CONFIG` is readable. If not, refuse.
4. No existing agent at `$AGENTS_GLOBAL/<name>.md`. If one exists, refuse: `Error: agent <name> already exists in the freelance pool. Use /software-house set-model to change config, or /software-house fire <name> --pool then re-hire.`
5. `$OUTSOURCE_MANIFEST` path is writable (directory must exist).

## Step-by-step protocol

### 1. Validate inputs

Read `$MODELS_CONFIG`. Check that `--role` matches a key in `defaults_by_role`. If not, list valid role keys and abort.

Validate `name` against `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

Resolve provider and model:
- If `--provider` is not given, read `defaults_by_role[role].provider` and `defaults_by_role[role].model` from `$MODELS_CONFIG`.
- If `--provider` is given, use it. If `--model` is omitted, abort: `Error: --model is required when --provider is specified.`
- Validate `provider` key against `$PROVIDERS_CONFIG`. Abort if not found.

Resolve effort:
- `med` -> `medium` internally.
- If `--effort` is not given, use `defaults_by_role[role].effort`.

Validate `--contract-type` is one of `retainer`, `hourly`, `project`. If not, abort: `Error: --contract-type must be one of: retainer, hourly, project. Got: <value>.`

Validate `--contract-end` is a valid ISO-8601 date (`YYYY-MM-DD`) or `null`. If invalid format, abort: `Error: --contract-end must be a valid date (YYYY-MM-DD) or null. Got: <value>.`

### 2. Determine target paths

- Scope: `freelance`
- Canonical agent file: `$AGENTS_GLOBAL/<name>.md`
- No per-project adapters (written later by `contract` operation)
- Wiki people page: `$WIKI_PEOPLE/<name>.md` (written for company-level visibility)

### 3. Check for conflicts

Check whether `$AGENTS_GLOBAL/<name>.md` already exists. If so, abort per Precondition 4.

Check `$WIKI_PEOPLE/<name>.md` as well. If that exists but the agent file does not, warn: `Warning: wiki entry exists for <name> without a canonical agent file. Proceeding will create both.` and continue.

### 4. Egress consent gate (external providers only)

Classify the resolved `provider` using `$PROVIDERS_CONFIG`. If `class == "external"`:

Print the egress consent prompt from `safety.md §3`:

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
| Anything else, or no response, will cancel the hire.     |
+----------------------------------------------------------+
```

Stop. Wait for the next user message. Parse byte-exact per `safety.md §9`:

- If the token `EGRESS-CONSENT-<provider>` appears, record it and advance to Step 5.
- Otherwise, abort. Print local fallback for the role. Do not log.

If `class == "local"`, skip this step entirely. Set `egress_consent_required = false`.

### 5. Tier-2 confirmation

Build the full file list that will be created. Print it:

```
I will create the following for freelance agent '<name>':
  Canonical: $AGENTS_GLOBAL/<name>.md
  Wiki:      $WIKI_PEOPLE/<name>.md
  Manifest:  $OUTSOURCE_MANIFEST
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

### 6. Write canonical agent file

Get the current UTC timestamp:

```
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Write `$AGENTS_GLOBAL/<name>.md` with YAML frontmatter per `_shared.md §7`:

```yaml
---
name: <name>
description: <role-key> agent (freelance)
provider: <provider>
model: <model>
egress_consent: <none | external:<utc-date>>
employee_id: emp-<padded-next-id>
team: null
department: null
role: <role>
position: <role-key human label>
reports_to: null
status: freelance
hired_at: <utc-date YYYY-MM-DD>
level: 1
xp: 0
effort_preset: <effort>
classification: internal
buddy: null
employment: freelance
hired_by_teams: []
achievements: []
contract_type: <contract-type>
contract_start: <utc-date YYYY-MM-DD>
contract_end: <contract-end | null>
rate: null
---
```

Body:

```markdown
# <name>

Agent provisioned by software-house skill into the freelance/outsource pool.
Role: <role>
Provider: <provider> [<class>]
Contract: <contract-type>
```

For the `employee_id`: glob `$WIKI_PEOPLE/` and `$AGENTS_GLOBAL/` for existing `.md` files, count them, increment by one, zero-pad to 3 digits (e.g., `emp-004`).

`egress_consent` is:
- `none` if provider is local
- `external:<utc-date-of-consent>` if provider is external (date is the timestamp from Step 4)

### 7. Write wiki people page

Write `$WIKI_PEOPLE/<name>.md` with the same frontmatter (identical fields). Add a body section:

```markdown
---
<same frontmatter as canonical agent file>
---

# <name>

## Freelance Agent

Contract type: <contract-type>
Contract start: <contract-date>
Contract end: <contract-end | "open-ended">

## Onboarding

Briefing not yet written. Run `/software-house onboard <name> --pool` to generate.

## Notes

(empty)
```

### 8. Update outsource manifest

Read `$OUTSOURCE_MANIFEST` (create with skeleton if missing). The manifest is a JSON file at `$OUTSOURCE_MANIFEST` (`~/.software-house/company/outsource/manifest.json`).

Skeleton:

```json
{
  "freelancers": [],
  "updated_at": "<utc-date>"
}
```

Append the new agent entry to the `freelancers` array:

```json
{
  "name": "<name>",
  "role": "<role>",
  "provider": "<provider>",
  "model": "<model>",
  "contract_type": "<contract-type>",
  "contract_start": "<utc-date YYYY-MM-DD>",
  "contract_end": "<contract-end | null>",
  "status": "freelance",
  "hired_at": "<utc-date YYYY-MM-DD>"
}
```

Update `updated_at` to current UTC timestamp. Write atomically per `_shared.md §6`.

### 9. Rebuild indexes

Rebuild `$COMPANY_INDEX` per `_shared.md §8`.

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"outsource-hire","scope":"company","args":{"name":"<name>","role":"<role>","provider":"<provider>","model":"<model>","effort":"<effort>","contract_type":"<contract-type>","contract_end":"<contract-end|null>"},"diff":{"created":["$AGENTS_GLOBAL/<name>.md","$WIKI_PEOPLE/<name>.md"],"updated":["$OUTSOURCE_MANIFEST","$COMPANY_INDEX"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":<bool>,"granted":"<token|null>","provider":"<provider|null>","ts":"<utc|null>"},"result":"ok"}
```

### 11. Report to user

```
Hired freelance agent <name> (<role>)
  Canonical:    $AGENTS_GLOBAL/<name>.md
  Wiki:         $WIKI_PEOPLE/<name>.md
  Provider:     <provider> [<class>]
  Model:        <model>
  Effort:       <effort>
  Contract:     <contract-type> (ends: <contract-end | "open-ended">)
  Egress:       <none | consented at <utc-date>>
  Status:       freelance

Next steps:
  /software-house onboard <name> --pool      write personalized briefing
  /software-house contract <name> --team <t> assign to a project team
  /software-house show <name>                inspect the agent record
```

## Failure modes

- Role not in `$MODELS_CONFIG` -> list valid roles, abort, no log.
- Provider not in `$PROVIDERS_CONFIG` -> list valid providers, abort, no log.
- Egress consent not given -> print local fallback, abort, no log.
- Canonical file already exists -> refuse, suggest `set-model` or `fire --pool` + re-hire, no log.
- Invalid `--contract-type` -> abort, no log.
- Invalid `--contract-end` -> abort, no log.
- `mkdir` fails (permissions) -> report path, abort, no log.
- Atomic write failure on manifest -> roll back `.tmp`; log `result: failed`.

## Examples

```
# Hire a freelance backend developer using local defaults
/software-house outsource-hire dev-contractor --role backend-dev

# Hire a freelance tech lead with external provider (triggers egress gate)
/software-house outsource-hire senior-consultant --role tech-lead --provider anthropic --model claude-opus-4-7 --effort high

# Hire a freelance QA tester with hourly contract and end date
/software-house outsource-hire qa-outsourced --role qa --contract-type hourly --contract-end 2026-12-31

# Hire a freelance project-based designer
/software-house outsource-hire designer-x --role frontend-dev --contract-type project --contract-end 2026-09-01
```