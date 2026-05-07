# Operation: delegate -- delegate a task to an agent

**Risk tier:** 2 (creates handoff files, spawns sub-agent execution)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Delegate a task to an active agent. This operation:
1. Validates the agent exists and is active
2. Reads the agent's canonical file and wiki page for context
3. Constructs a system prompt from wiki context + role template
4. Writes the task to the handoffs inbox
5. Outputs execution instructions (sh-agent command or Agent tool invocation)

For Claude Code: outputs a `SPAWN` instruction that the LLM picks up to use the Agent tool.
For CLI execution: outputs the `sh-agent` command for the user to run.

## Invocation patterns

| Command | Behavior |
|---|---|
| `delegate <agent-name> <task-description>` | Print the spawn plan and `sh-agent` command (no execution) |
| `delegate <agent-name> --from-file <path>` | Delegate a task from a file |
| `delegate <agent-name> <task> --context <wiki-page>...` | Include additional wiki context pages |
| `delegate <agent-name> <task> --wiki-update` | Append result to agent's wiki page |
| `delegate <agent-name> <task> --output <path>` | Specify output file path |
| `delegate <agent-name> <task> --execute` | After tier-2 confirmation, actually run the sub-agent CLI inline and write output to the `.md` file |
| `delegate <agent-name> <task> --execute --watch` | Same as `--execute`, plus print the result to stdout after the sub-agent finishes |

## Harness routing

The skill resolves a harness (CLI transport) for each delegation in this order:

1. Agent canonical-file `harness` frontmatter (per-agent override)
2. `models-config.json` `harness_defaults[provider]` (per-provider default)
3. `null` (direct provider execution)

Valid harness ids:

- `claude-code` -- spawn via `claude -p --system-prompt ... --model ...`
- `codex` -- spawn via `codex exec ... -o <output>` (system prompt embedded in user prompt)
- `gemini` -- spawn via `gemini -p ... -y -o text` (system prompt embedded)
- `ollama:<integration>` -- spawn via `ollama launch <integration> --model <m> -- <args>`. Supported integrations: `claude`, `claude-desktop`, `codex`, `cline`, `copilot`, `droid`, `hermes`, `kimi`, `opencode`, `openclaw`, `pi`, `pool`, `vscode`. Note: `ollama:gemini` is **not** supported (gemini is not in the `ollama launch` integration list) and is rejected at validation time.

When `--execute` is set, the resolved harness routes through `execute_with_fallback`'s three-tier path:

1. Tier 1: `execute_via_harness <id>` -- the configured CLI transport.
2. Tier 2: direct provider execution (e.g. `ollama run`, Anthropic API).
3. Tier 3: Anthropic fallback per role (after EGRESS-CONSENT).

## Inputs

| Input | Required | Validation |
|---|---|---|
| `agent-name` | yes | Must match `^[a-z][a-z0-9-]{0,63}$` and reference an existing agent |
| `task-description` | yes (or `--from-file`) | Non-empty string describing the task |
| `--from-file` | no | Path to a file containing the task description |
| `--context` | no | One or more wiki page paths to include in system prompt (repeatable) |
| `--wiki-update` | no | Flag to append result summary to agent's wiki page |
| `--output` | no | Path for output file (default: auto-generated in handoffs/) |
| `--execute` | no | Actually run the sub-agent CLI inline after tier-2 confirmation (default is to print the spawn plan only) |
| `--watch` | no | Print the result to stdout after `--execute` completes |

## Preconditions

1. `$SH_HOME` exists (company initialized). If not, refuse: `Error: company not initialized. Run /software-house init first.`
2. Agent canonical file exists at `$TEAM_AGENTS/<name>.md` or `$AGENTS_GLOBAL/<name>.md`. If not, refuse: `Error: agent '<name>' not found.`
3. Agent status is `active`. If `onboarding`, refuse: `Error: agent '<name>' is still onboarding. Run /software-house onboard <name> first.` If `alumni`/`freelance`/`transfer`, refuse with appropriate message.

## Step-by-step protocol

### 1. Validate inputs

Validate `agent-name` matches `^[a-z][a-z0-9-]{0,63}$`. Abort on mismatch.

If `--from-file` is specified, validate the file exists and is readable.

If `--context` is specified, validate each page path exists.

### 2. Load agent data

Read the agent's canonical file using `read_agent()`. Extract:
- `AGENT_NAME`, `AGENT_ROLE`, `AGENT_PROVIDER`, `AGENT_MODEL`
- `AGENT_EFFORT_PRESET`, `AGENT_TEAM`, `AGENT_STATUS`
- `AGENT_EGRESS_CONSENT`, `AGENT_RESPONSIBILITIES`, `AGENT_COLLABORATES_WITH`
- `AGENT_HANDOFF_TRIGGERS`, `AGENT_TOOLS`

Validate `AGENT_STATUS` is `active`. Abort if not.

### 3. Load role template

Read `$ROLE_TEMPLATES` and extract the role template for `AGENT_ROLE`. This provides:
- `responsibilities` -- what the agent is expected to do
- `deliverables` -- expected output types
- `collaborates_with` -- which roles this agent works with
- `handoff_triggers` -- events that trigger handoffs to other roles

### 4. Build task prompt

If `--from-file` is specified, read the task description from the file. Otherwise, use the inline `task-description`.

Compose the full task prompt:

```
# Task: <task-description>

Assigned to: <AGENT_NAME> (<AGENT_ROLE>)
Priority: medium
Created: <utc-timestamp>

## Instructions

1. Read the relevant wiki pages and project context provided in your system prompt.
2. Complete the task described above.
3. Write your results to the output file specified by the orchestrator.
4. If you encounter blockers, document them clearly in the results.
5. If this task triggers a handoff to another role, generate a handoff brief per your Handoff Protocol.

## Expected Deliverables

<from role template deliverables for this role>
```

### 5. Build system prompt

Use `build_system_prompt()` from `lib/providers/_shared.sh` to construct the system prompt from:
- Agent wiki page (`$WIKI_PEOPLE/<name>.md`)
- Project status (`$COMPANY_HOME/wiki/synthesis/project-status.md`)
- Relevant decision pages (filtering `$WIKI_DECISIONS/*.md` for mentions of the agent's role)
- Handoff protocol from role template
- Additional context pages from `--context` flags

### 6. Write task file and handoff inbox entry

Write the task prompt to a temporary file.

Create a handoff inbox entry at `$WIKI_HANDOFF_INBOX/<agent>-<timestamp>.md` (or per-project equivalent):

```yaml
---
from: ceo
to: <agent-name>
task: <first line of task description>
priority: medium
context_pages: [<list of wiki pages included>]
created_at: <utc-timestamp>
status: pending
---
```

Body: full task description.

### 7. Determine execution mode

Detect the current harness:

- Claude Code: execution mode is `agent-spawn` (the LLM picks up a `SPAWN` instruction)
- Codex/Gemini/other: execution mode is `cli-exec` (user runs `sh-agent` manually)

### 8. Tier-2 confirmation

Print the delegation plan:

```
+----------------------------------------------------------+
| I will delegate the following task to <agent-name>.       |
| Agent:    <name> (<role>)                                  |
| Provider: <provider> / <model>                             |
| Effort:   <effort>                                         |
| Output:   <output-path>                                     |
| Wiki update: <yes/no>                                       |
|                                                             |
| Reply 'yes' to proceed, or anything else to cancel.        |
+----------------------------------------------------------+
```

Wait for affirmative response per `safety.md section 9`.

### 9. Execute or print instructions

#### For `agent-spawn` mode (Claude Code):

Print the Agent tool invocation instruction:

```
SPAWN: agent=<agent-name> role=<role> tools=[<resolved tool list>]
OUTPUT: <output-path>
PROMPT: <task description>

System prompt context has been prepared. The agent's wiki page and project
context will be included automatically when the sub-agent is spawned.
```

The orchestrating LLM should then invoke the Agent tool with these parameters.

#### For `cli-exec` mode (Codex, Gemini, CLI):

Print the `sh-agent` command:

```bash
sh-agent <agent-name> /tmp/sh-agent-task-<timestamp>.md \
  --output <output-path> \
  [--wiki-update] \
  [--context <page1> --context <page2>]
```

### 10. Append audit log entry

```json
{"ts":"<utc>","actor":"user","op":"delegate","scope":"agent:<name>","args":{"agent":"<name>","role":"<role>","provider":"<provider>","model":"<model>","effort":"<effort>","execution_mode":"<agent-spawn|cli-exec>","output":"<output-path>","wiki_update":<bool>},"diff":{"created":["<inbox-entry-path>","<task-file-path>"]},"confirmation":{"tier":2,"prompt":"<exact box text>","response":"<user verbatim>","ts":"<utc>"},"egress_consent":{"required":<bool>,"granted":null},"result":"ok"}
```

If the agent's provider is external and egress consent is `none`, set `egress_consent.required` to `true` and prompt for consent.

### 11. Report to user

```
Task delegated to <agent-name> (<role>).
  Provider:   <provider> / <model>
  Effort:     <effort>
  Output:     <output-path>
  Execution:  <agent-spawn | cli-exec>

Inbox entry: <inbox-path>

<If agent-spawn mode:>
The Agent tool should now be invoked with the above parameters.

<If cli-exec mode:>
Run the following command to execute:
  <sh-agent command>
```

## Failure modes

- Agent not found -> abort, no log.
- Agent not active -> abort with status-specific message, no log.
- Task description empty and no `--from-file` -> abort: `Error: task description is required.`
- `--from-file` path does not exist -> abort: `Error: task file not found: <path>`
- `--context` path does not exist -> abort: `Error: context page not found: <path>`
- Confirmation non-affirmative -> abort, no log, no changes.
- External provider without egress consent -> abort: `Error: external provider requires egress consent. Run /software-house set-model <name> --egress-consent first.`
- Role template not found -> warn but continue (use defaults from models-config.json).
- Resolved harness fails `is_valid_harness` (e.g. `ollama:gemini`, or `ollama:claude` when provider is not `ollama`) -> abort with explanatory error.
- `--execute` set, harness CLI not on PATH -> log warning and fall through to direct provider (tier 2).
- `--execute` set, sub-agent execution returns non-zero -> print failure message, preserve inbox entry, return the same exit code.

## Examples

```
# Delegate a task to tony (tech-lead)
/software-house delegate tony "Review the authentication module architecture"

# Delegate with context from a decision page
/software-house delegate alice "Implement the new API endpoints" --context wiki/decisions/adr-003.md

# Delegate from a file with wiki update
/software-house delegate bob --from-file task-prompts/fix-tests.md --wiki-update

# Delegate with explicit output path
/software-house delegate carol "Write API documentation" --output results/api-docs.md
```