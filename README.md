# software-house

A multi-harness, multi-provider skill that turns your local machine into a managed software house. Subagents become employees, projects become teams, and you become the CEO. The skill itself never sends a byte off your machine; agents that you explicitly configure with an external provider may egress only after you type a one-time `EGRESS-CONSENT-<provider>` token recorded in the audit log. HR-style workforce operations, OKR cascades, Scrum, plan execution, sub-agent spawning, inter-agent handoff, an LLM Wiki, and a gamified skill system, accessible the same way from Claude Code, OpenAI Codex CLI, or Gemini CLI.

---

## Skill Description

software-house models a software company as a directory tree under `~/.software-house/`. Every agent you hire gets a canonical markdown definition with frontmatter (provider, model, role, level, XP, harness, tools, role template) and auto-generated adapter shims for each harness you have installed (Claude Code, Codex, Gemini). The skill enforces a four-tier confirmation gate system, an append-only audit log, and a local-default provider policy that keeps external API calls opt-in.

Core capabilities:

- **HR operations**: hire, fire, transfer, promote, demote, second (matrix assignment), onboard, off-board, disband
- **Read-only inspection**: list, show, org-chart, lint
- **Outsource management**: outsource-hire, contract (freelance pool with project attachment)
- **OKR cascade**: set and review objectives at company, department, or team tier
- **Gamification**: XP, levels (1--5), achievements, skill tree, dashboard
- **Scrum**: backlog management (add/list/prioritize) and sprint lifecycle (create/plan/board/standup/review/retro)
- **Plan execution**: plan-create, plan-confirm, plan-execute (auto-spawn parallel sub-agents), plan-status, plan-synthesize
- **Cross-project analysis**: aggregate architectural context across multiple linked repositories via `plan cross-project`
- **Sub-agent spawning**: `bin/sh-agent` CLI executor with provider adapters (Ollama, LMStudio, vLLM, Anthropic) and three-tier fallback (harness -> direct provider -> Claude)
- **Harness routing**: route a sub-agent through another CLI (claude-code, codex, gemini, ollama:<integration>) via the `harness` frontmatter field
- **Harness tool validation**: automated checks ensure an agent's harness supports the specific tools required for its role
- **Token optimization**: multi-layered 'Senior Technical Editor' hook producing high-density technical summaries for all communications
- **CEO-to-agent gateway**: bypass triggers and send direct directive messages to any agent via `gateway`
- **Dhamma integration**: Buddhist epistemic methods (Kalāma, Yoniso Manasikāra, etc.) injected into agent system prompts to reduce hallucination
- **Inter-agent handoff**: structured briefs in `wiki/handoffs/inbox/` and `completed/`, with list/show/complete/generate subcommands
- **LLM Wiki**: compiled entity, concept, decision, and synthesis pages regenerated on every state change for fast, structured context
- **Wiki ingestion and lint**: archive raw sources, compile into wiki pages, and run 8 health checks (confidence drift, stale pages, broken wikilinks, orphan pages, etc.)
- **Multi-provider**: 7 local providers and 18 external providers per role, local-default policy with egress consent gate
- **Update mechanism**: version detection, changelog preview, config overlays, schema migrations, adapter re-sync

### Mental Model

| Real World     | This Skill (canonical)                                         | Per-harness adapter (auto-generated)                       |
|----------------|----------------------------------------------------------------|------------------------------------------------------------|
| Company        | Your computer (`~/.software-house/`)                           | n/a                                                        |
| Department     | Named group of teams (`~/.software-house/departments/<d>/`)    | n/a                                                        |
| Team           | A project folder with `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md` | n/a                                                        |
| Employee       | Canonical agent at `<project>/.software-house/agents/<n>.md`   | `<project>/.claude/agents/`, `.codex/agents/`, `.gemini/extensions/<n>/` (thin shims) |
| Freelance pool | `~/.software-house/agents/`                                    | `~/.claude/agents/`, `~/.codex/agents/`, `~/.gemini/extensions/<n>/`                  |
| CEO            | You                                                            | n/a                                                        |

### Data Layout

```
~/.software-house/                       <- Canonical state (harness-neutral)
~/.software-house/company/               <- Company tier (audit log lives here)
~/.software-house/departments/<d>/       <- Department tier
~/.software-house/agents/                <- Freelance / outsource pool
~/.software-house/config/providers.json  <- 25-provider catalog with egress flags
~/.software-house/config/providers.local.json  <- User overlay (never overwritten on update)
~/.software-house/config/models-config.json   <- Defaults by role + harness_defaults
~/.software-house/config/models-config.local.json <- User overlay (never overwritten on update)
~/.software-house/config/role-templates.json  <- 10 role templates (responsibilities, deliverables, ...)
~/.software-house/config/tools-config.json    <- Shared and per-role tool vocabulary

<project>/.software-house/team/          <- Canonical team state (LLM Wiki)
<project>/.software-house/team/backlog.md
<project>/.software-house/team/sprints/<id>/
<project>/.software-house/team/plans/<id>/
<project>/.software-house/team/wiki/concepts/
<project>/.software-house/team/wiki/decisions/
<project>/.software-house/team/wiki/synthesis/
<project>/.software-house/team/wiki/handoffs/inbox/
<project>/.software-house/team/wiki/handoffs/completed/
<project>/.software-house/team/wiki/handoffs/briefs/
<project>/.software-house/agents/<n>.md  <- Canonical agent definition
<project>/.claude/agents/<n>.md          <- Adapter (auto-generated)
<project>/.codex/agents/<n>.md           <- Adapter (auto-generated)
<project>/.gemini/extensions/<n>/        <- Adapter (auto-generated)
```

### Harness Compatibility

| Harness          | Install path (default)                  | Entry-point file               | Bypass flag (still gated by skill) |
|------------------|-----------------------------------------|--------------------------------|------------------------------------|
| Claude Code      | `~/.claude/skills/software-house/`      | `SKILL.md`                     | `--dangerously-skip-permissions`   |
| OpenAI Codex CLI | `~/.agents/skills/software-house/`      | `SKILL.md` (+ `agents/openai.yaml`) | `--dangerously-bypass-approvals-and-sandbox` / `--full-auto` |
| Gemini CLI       | `~/.gemini/extensions/software-house/`  | `gemini-extension.json` + `GEMINI.md` + `commands/*.toml` | `--yolo` / `--approval-mode yolo`  |

The same canonical state is read by all three CLIs. Per-harness adapter directories are thin shims that point at the canonical agent file, so you can hire an employee once and use them from any harness.

---

## Installation

See [INSTALL.md](./INSTALL.md) for full details. Quick start:

```sh
# Clone and enter the repo
git clone <repo-url> && cd SoftwareHouseSkills

# See which harnesses will be detected
./install.sh --list-harnesses

# Install into all detected harnesses (prompts before overwriting)
./install.sh

# Install into a single harness
./install.sh --harness claude-code

# Dev mode: symlink instead of copy (edits to source are live)
./install.sh --symlink

# Update an existing installation (version check, changelog preview, migration)
./install.sh --update

# Re-sync adapter shims after canonical agent changes
./install.sh --fix-adapters
```

The installer detects installed harnesses by checking for `~/.claude`, `~/.codex`/`~/.agents`, and `~/.gemini`. Codex requires one manual step after install (a `[[skills]]` entry in `~/.codex/config.toml`); the installer prints the exact snippet.

### Config Overlays

Config files follow a two-layer pattern:

- **Skill-managed** (`providers.json`, `models-config.json`, `role-templates.json`, `tools-config.json`) -- overwritten on each `install.sh` run with baseline defaults.
- **User overlay** (`*.local.json`) -- never overwritten by `install.sh`. Add custom providers, role defaults, or model aliases here.

When reading config, the overlay merges with and overrides the base file.

### Version and Migrations

The skill ships a `VERSION` file (semver, currently `0.10.0`). On update:

- **Same version**: prompts to confirm re-install (or skips with `--force`).
- **Upgrade**: shows CHANGELOG entries between versions, runs pending migrations, then installs.
- **Downgrade**: warns and requires confirmation.

Migrations are shell scripts in `migrations/NNN-<name>.sh`, run in sort order on version change. Five migrations ship today: 001 baseline, 002 tools field, 003 sprint/plan dirs, 004 role-template + wiki-LLM backfill, 005 harness field. See `migrations/README.md` for the migration contract.

---

## How to Use

### Initialize the Company

Open any project and run:

```
/software-house init
```

Bootstraps `~/.software-house/`. Confirmation prompted before any file is created.

### Hire an Employee

Local provider (default: Ollama, no egress):

```
/software-house hire alice --role backend-dev
```

External provider (requires egress consent):

```
/software-house hire bob --role tech-lead --provider anthropic --model claude-opus-4-7
```

The skill prints a warning naming the destination service and waits for you to type `EGRESS-CONSENT-anthropic` before writing the agent file.

### Hire a Freelance Agent

```
/software-house outsource-hire carol --role designer --provider google --model gemini-2.5-pro
```

Freelance pool agents live at `~/.software-house/agents/` and do not receive per-project adapter shims until contracted to a team.

### Attach a Freelancer to a Project

```
/software-house contract carol --team my-project
```

Generates adapter shims in the target project's harness directories.

### Move, Promote, Manage

```
/software-house transfer alice --to backend-team
/software-house promote alice --to-role senior-dev
/software-house demote alice --by 1
/software-house second alice --to frontend-team
/software-house set-model alice --provider openai --model gpt-4.1
/software-house set-model alice --harness claude-code
/software-house set-model alice --clear-harness
```

### Sub-Agent Spawning and Delegation

Run an agent's task via the configured provider (with three-tier fallback):

```
bin/sh-agent alice "Refactor the auth middleware"
bin/sh-agent alice "Refactor the auth middleware" --harness claude-code
```

Or via the skill:

```
/software-house delegate alice --task "Refactor the auth middleware"
/software-house delegate alice --task "Refactor the auth middleware" --execute
```

`--execute` runs the sub-agent inline after the tier-2 confirmation, writing the response to a `.md` output file. Without `--execute`, the operation prints the `sh-agent` command for manual review.

#### Ollama Provider Routing

All default roles use `provider: ollama`. The actual command line depends on the `harness` field resolution order:

1. Agent frontmatter `harness` (per-agent override)
2. `models-config.json` `harness_defaults[provider]`
3. `null` (direct provider execution)

**Current default** (`harness_defaults.ollama: null`): every ollama agent falls through to **Tier 2 -- direct provider execution**, which runs:

```bash
ollama run <model> --nowordwrap < /tmp/sh-agent-ollama-prompt-XXXXXX.txt
```

The prompt file embeds the system prompt as a `<<SYSTEM>>...<<END_SYSTEM>>` prefix block because `ollama run` has no `--system` flag. If effort is `high` or `xhigh`, `--think=high` is tried first and retried without it on failure.

**Limitation:** `ollama run` is a bare model invocation with no tool ecosystem (no Read/Write/Edit/Glob/Grep). Code-modifying agents need tools. To route an ollama agent through a harness that provides tools, set `harness` to one of:

| Harness id | Command | Tool access |
|---|---|---|
| `ollama:claude` | `ollama launch claude --model <m> -y -- -p --system-prompt ... --output-format text --dangerously-skip-permissions` | Full (Read/Write/Edit/Bash/Glob/Grep) |
| `ollama:codex` | `ollama launch codex --model <m> -y -- exec ... -s workspace-write -o <output>` | Full (workspace-scoped) |
| `ollama:cline` / `ollama:copilot` / etc. | `ollama launch <integration> --model <m> -y` (generic stdin passthrough) | Varies by integration |

To change the default for all ollama agents, edit `models-config.local.json`:

```json
{ "harness_defaults": { "ollama": "ollama:claude" } }
```

Or per-agent:

```bash
/software-house set-model <agent-name> --harness ollama:claude
```

**Restrictions:**
- `ollama:gemini` is **rejected at validation time** -- `gemini` is not in the `ollama launch` integration list.
- `harness: claude-code` combined with `provider: ollama` is contradictory (Claude Code Agent tool requires an Anthropic model id) and is refused at hire time.
- When orchestrating from Claude Code with `harness: ollama:claude`, the adapter shim sets `model: inherit` and dispatches via Bash (`nohup` + `Bash(run_in_background)`) rather than the Agent tool, which cannot spawn ollama models.

### Inter-Agent Handoff

```
/software-house handoff generate --from alice --to bob --task "..." --priority high
/software-house handoff list --team my-project --status inbox
/software-house handoff show <brief-id>
/software-house handoff complete <brief-id> --summary "..."
```

Briefs are JSONL-frontmatter markdown files routed through `wiki/handoffs/inbox/` and `completed/`. Both sender and receiver wiki pages update on completion.

### Scrum (Backlog and Sprint)

```
/software-house backlog add --title "Fix auth bug" --priority high
/software-house backlog list --status open
/software-house backlog prioritize <item-id> --priority urgent

/software-house sprint create --goal "Ship auth refactor"
/software-house sprint plan <sprint-id> --items <i1>,<i2>,<i3>
/software-house sprint board <sprint-id>
/software-house sprint standup <sprint-id>
/software-house sprint review <sprint-id>
/software-house sprint retro <sprint-id>
```

### Plan Execution (auto-spawn parallel sub-agents)

```
/software-house plan create --goal "Add OAuth flow"
/software-house plan confirm <plan-id>
/software-house plan execute <plan-id>
/software-house plan status <plan-id>
/software-house plan synthesize <plan-id>
```

`plan execute` topologically sorts the plan's task graph and dispatches independent tasks in parallel via the Claude Code Agent tool (or manual dispatch in Codex/Gemini).

### Wiki Ingestion and Lint

```
/software-house wiki-ingest <source-file> --kind concept
/software-house wiki-lint
/software-house wiki-lint --fix-suggestions
/software-house wiki-lint --json
```

Eight check categories: confidence drift, stale pages, broken wikilinks, orphan pages, empty sections, missing concepts, source trail integrity, wikilink consistency.

### OKRs and Gamification

```
/software-house okr-set --tier company --objective "Ship v2 by Q3"
/software-house award-xp alice --amount 100 --reason "shipped auth refactor"
/software-house dashboard
```

### Inspect and Lint

```
/software-house list people
/software-house show alice
/software-house org-chart
/software-house lint
/software-house lint --fix-adapters
```

### Remove an Agent

```
/software-house off-board alice          # Run off-boarding checklist first
/software-house fire alice               # Tier 4 gate: two-step typed CONFIRM
```

Adapter shims are moved to `~/.software-house/.trash/` (not deleted) for recovery.

### CLI (Reference Implementation)

Two bash CLIs ship in `bin/`:

```sh
bin/software-house --help
bin/software-house --version          # 0.10.0
bin/software-house hire --help        # Per-command help
bin/software-house list people --dry-run  # Preview without changes

bin/sh-agent --help
bin/sh-agent alice "task description" --harness claude-code
```

`bin/software-house` is the operation dispatcher (41 operation modules in `lib/operations/`). `bin/sh-agent` is the sub-agent executor that reads the agent's wiki for personalization, builds the system prompt, and runs the task through the provider adapter chain (`lib/providers/`) with three-tier fallback.

### Privacy and Safety

The skill enforces a two-layer privacy model:

| Layer          | Who acts                          | What is allowed                                                                                        |
|----------------|-----------------------------------|--------------------------------------------------------------------------------------------------------|
| Skill          | The skill itself, while running   | Local file ops only. No `WebFetch`, `WebSearch`, `curl`, `git push`, MCP. Allowlist + denylist enforced before every shell command. |
| Agent runtime  | The harness (when an agent runs)  | Egress allowed IF the agent's `provider` is `external` AND the user typed `EGRESS-CONSENT-<provider>` at hire/set-model time, recorded in the audit log. Local-provider agents never egress. |

Confirmation gates apply even when the harness bypass flag is active:

| Tier                    | Examples                      | Gate                                                |
|-------------------------|-------------------------------|-----------------------------------------------------|
| 1 -- Read-only          | list, show, org-chart, lint, dashboard, sprint-board, plan-status, handoff-list, handoff-show | none |
| 2 -- Additive           | init, hire (draft), onboard, dept-create, backlog-add, sprint-create, plan-create, handoff-generate, wiki-ingest | "Reply 'yes' to proceed" boxed prompt |
| 3 -- Modifying          | transfer, promote, demote, set-model, contract, off-board, sprint-plan, plan-confirm, plan-execute, handoff-complete, delegate | Diff + "Reply 'yes' to proceed" |
| 4 -- Destructive        | fire, disband                 | Two-step: intent prompt then `CONFIRM <subject-name>` |
| Egress consent (orthogonal) | hire/set-model/delegate with external provider | Literal `EGRESS-CONSENT-<provider>` token |

Every state-modifying operation appends one JSONL line to `~/.software-house/company/audit.log`. Records are never edited or deleted.

---

## Command Reference

### Phase 1 -- Foundation (Read-only)

| Command     | Description                                    | Risk Tier |
|-------------|------------------------------------------------|-----------|
| `init`      | Bootstrap `~/.software-house/`                  | 2         |
| `list`      | List people, teams, departments, freelance pool | 1         |
| `show`      | Display one entity in detail                    | 1         |
| `org-chart` | Render ASCII org tree                           | 1         |
| `lint`      | Health-check the company state                  | 1         |

### Phase 2 -- Recruitment

| Command       | Description                                                        | Risk Tier |
|---------------|--------------------------------------------------------------------|-----------|
| `hire`        | Create a new agent with provider/model/effort + egress consent gate | 2         |
| `onboard`     | Run onboarding checklist for a new agent                          | 2         |
| `fire`        | Remove an agent (two-step typed CONFIRM)                           | 4         |
| `dept create` | Create a new department                                            | 2         |
| `dept assign` | Assign an agent to a department                                    | 2         |

### Phase 3 -- Mobility and Outsource

| Command          | Description                                                        | Risk Tier |
|------------------|--------------------------------------------------------------------|-----------|
| `transfer`       | Transfer an agent to another team (cross-project egress re-consent)| 3         |
| `second`         | Matrix-assign an agent to a second team                            | 3         |
| `promote`        | Increase an agent's level/role                                     | 3         |
| `demote`         | Decrease an agent's level/role                                     | 3         |
| `set-model`      | Change provider/model/effort/harness (egress re-consent if external) | 3         |
| `outsource-hire` | Add an agent to the freelance pool                                 | 2         |
| `contract`       | Attach a freelance agent to a project team                         | 3         |
| `off-board`      | Off-boarding checklist before removal                               | 3         |
| `disband`        | Remove an entire team (two-step typed CONFIRM)                     | 4         |

### Phase 4 -- OKR and Gamification

| Command       | Description                                         | Risk Tier |
|---------------|-----------------------------------------------------|-----------|
| `okr set`     | Set OKRs at company, department, or team tier        | 2         |
| `okr review`  | Review OKR progress                                  | 1         |
| `award-xp`    | Grant XP and trigger level/achievement checks        | 3         |
| `dashboard`   | Show gamification stats and skill-tree state         | 1         |

### Phase 5 -- Scrum (Backlog and Sprint)

| Command               | Description                                  | Risk Tier |
|-----------------------|----------------------------------------------|-----------|
| `backlog add`         | Add a backlog item                            | 2         |
| `backlog list`        | List backlog items (filter by status, etc.)   | 1         |
| `backlog prioritize`  | Re-prioritize a backlog item                  | 3         |
| `sprint create`       | Create a sprint with a goal                   | 2         |
| `sprint plan`         | Assign backlog items to a sprint              | 3         |
| `sprint board`        | Show sprint board                             | 1         |
| `sprint standup`      | Daily standup view                            | 1         |
| `sprint review`       | Sprint review summary                          | 1         |
| `sprint retro`        | Retrospective notes                            | 2         |

### Phase 6 -- Plan Execution

| Command            | Description                                                | Risk Tier |
|--------------------|------------------------------------------------------------|-----------|
| `plan create`      | Author a multi-task plan with dependencies                  | 2         |
| `plan confirm`     | Confirm and lock the plan before execution                  | 3         |
| `plan execute`     | Auto-spawn parallel sub-agents per topological wave         | 3         |
| `plan status`      | Show progress of a plan                                     | 1         |
| `plan synthesize`  | Combine sub-agent outputs into a single deliverable          | 3         |
| `plan cross-project` | Aggregate architectural context across microservice repos  | 2         |

### Phase 7 -- Sub-Agent Delegation

| Command     | Description                                                            | Risk Tier |
|-------------|------------------------------------------------------------------------|-----------|
| `delegate`  | Hand a task to a configured agent. `--execute` runs it inline          | 3         |
| `gateway`   | Send a direct message/directive to an agent from the CEO               | 2         |

### Phase 8 -- Inter-Agent Handoff

| Command                | Description                                              | Risk Tier |
|------------------------|----------------------------------------------------------|-----------|
| `handoff generate`     | Generate a structured handoff brief                       | 2         |
| `handoff list`         | List handoff briefs (filter by team, status, from, to)    | 1         |
| `handoff show`         | Show a single brief                                       | 1         |
| `handoff complete`     | Close a brief with a summary                              | 3         |

### Phase 9 -- Wiki-LLM

| Command           | Description                                              | Risk Tier |
|-------------------|----------------------------------------------------------|-----------|
| `wiki-ingest`     | Archive a source file and compile into a wiki page        | 2         |
| `wiki-lint`       | Run 8 wiki health checks; supports `--fix-suggestions` and `--json` | 1 |

### Additional Flags

| Flag                | Description                                                       |
|---------------------|-------------------------------------------------------------------|
| `--dry-run`         | Preview what would be done without making changes                 |
| `--fix-adapters`    | Regenerate per-project adapter shims from canonical agent files   |
| `--harness <value>` | Route sub-agent execution through another CLI (sh-agent, set-model) |
| `--clear-harness`   | Remove the harness field (set-model only)                         |
| `--execute`         | Run the sub-agent inline after confirmation (delegate only)       |
| `--watch`           | Tail the sub-agent output (delegate only)                         |
| `--help`            | Show help                                                         |
| `--version`         | Show version (currently 0.9.0)                                    |

---

## Architecture Overview

The skill is organized in four tiers, each with the same internal layout:

```
<tier-root>/
  raw/       <- Immutable source documents (job specs, policies, etc.)
  wiki/      <- Compiled entity, concept, decision, synthesis, and handoff pages
  index.md   <- Auto-generated catalog of all entities in this tier
  audit.log  <- Append-only JSONL event stream
  CLAUDE.md  <- Schema and instructions for this tier
```

The **LLM Wiki** pattern compiles raw sources into dense, structured pages that the assistant can load in a fraction of the tokens required to re-read raw files. Pages carry `confidence`, `lifecycle`, `last_compiled`, and `source_refs` frontmatter and are regenerated automatically whenever the underlying sources change. `wiki-lint` enforces eight health checks across the corpus.

Tiers:

1. **Company** -- `~/.software-house/company/` -- global policies, headcount, OKR top level
2. **Department** -- `~/.software-house/departments/<dept>/` -- grouped teams, dept OKRs
3. **Team** -- `<project>/.software-house/team/` -- project context, sprint board, plan board, handoff inbox, team OKRs
4. **Role** -- `<project>/.software-house/agents/<role>.md` (canonical) plus auto-generated harness adapters under `<project>/.claude/agents/`, `<project>/.codex/agents/`, `<project>/.gemini/extensions/<role>/`. Freelance pool at `~/.software-house/agents/`.

### Sub-Agent Execution Path

When `bin/sh-agent <agent> <task>` (or `delegate --execute`) runs, the executor:

1. Reads the canonical agent definition and resolves `provider`, `model`, `effort`, `harness`, and tools.
2. Loads the agent's wiki page for personalization context (responsibilities, deliverables, collaborators).
3. Loads the role template (responsibilities, handoff triggers) from `config/role-templates.json`.
4. Constructs a system prompt and dispatches via `execute_with_fallback`:
   - **Tier 1** -- if `harness` is set (claude-code, codex, gemini, ollama:<integration>), route through that CLI.
   - **Tier 2** -- otherwise call the provider adapter directly (`lib/providers/{ollama,lmstudio,vllm,anthropic}.sh`).
   - **Tier 3** -- on failure, fall back to Anthropic if `fallback_claude` is configured for the role and egress consent is on file.
5. Writes the model's response to a `.md` output file and appends a JSONL audit record.

#### Ollama Execution Detail

When an ollama agent has no `harness` set (the default), the executor calls `provider_execute_ollama()` which runs `ollama run <model>` directly. System prompts are embedded as `<<SYSTEM>>...<<END_SYSTEM>>` blocks because `ollama run` lacks a `--system` flag. High-effort tasks first try `--think=high` and fall back to no-think on failure.

When `harness` is set to `ollama:<integration>`, the executor calls `execute_via_ollama_launch()` which runs `ollama launch <integration> --model <m> -y -- <args>`. The `<args>` vary by integration: `claude` gets `-p --system-prompt ... --output-format text`, `codex` gets `exec ... -s workspace-write -o <output>`, and all others get a combined `<system>...<user>...` prompt via stdin.

The `ollama:claude` harness is the recommended default for code-modifying agents because it provides the full tool ecosystem (Read/Write/Edit/Bash/Glob/Grep) through the Claude Code runtime.

---

## Project Structure

```
SoftwareHouseSkills/
  install.sh                                    <- Multi-harness installer
  skills/software-house/
    SKILL.md                                    <- Claude Code entry point
    AGENTS.md                                   <- Codex entry point
    GEMINI.md                                   <- Gemini entry point
    VERSION                                     <- Semver (0.10.0)
    CHANGELOG.md                                <- Keep a Changelog format
    manifest.yaml                               <- Operation manifest
    bin/
      software-house                            <- Operation dispatcher
      sh-agent                                  <- Sub-agent executor
    lib/
      _shared.sh                                <- Shared bash library + harness/role-template helpers
      operations/                               <- 41 operation modules
      providers/                                <- 5 provider adapters (ollama, lmstudio, vllm, anthropic, _shared)
    adapters/                                   <- Harness adapter docs (claude-code, codex, gemini)
    scripts/
      obsidian-setup.sh                         <- Obsidian vault symlink setup
    tests/                                      <- Test suite (9 files)
    commands/software-house.toml                <- Gemini CLI command definition
    config/
      providers.json                            <- 25-provider catalog
      providers.local.json                      <- User overlay (never overwritten)
      models-config.json                        <- Role defaults + harness_defaults
      models-config.local.json                  <- User overlay (never overwritten)
      role-templates.json                       <- 10 role templates
      tools-config.json                         <- Shared and per-role tool vocabulary
    operations/                                 <- 41 operation spec markdown files
    schemas/                                    <- agent, sprint, backlog-item, plan, handoff-brief
    templates/                                  <- agent-starter, dept-charter, backlog, sprint, plan
    policies/                                   <- Privacy and safety policies
    migrations/                                 <- 5 migration scripts (001-005)
```

---

## License

MIT -- copyright 2026 kanganapong sriduang. See [LICENSE.md](./LICENSE.md).
