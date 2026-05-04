# software-house

A multi-harness, multi-provider skill that turns your local machine into a managed software house. Subagents become employees, projects become teams, and you become the CEO. The skill itself never sends a byte off your machine; agents that you explicitly configure with an external provider may egress only after you type a one-time `EGRESS-CONSENT-<provider>` token recorded in the audit log. HR-style workforce operations, OKR cascades, and a gamified skill system, accessible the same way from Claude Code, OpenAI Codex CLI, or Gemini CLI.

---

## Skill Description

software-house models a software company as a directory tree under `~/.software-house/`. Every agent you hire gets a canonical markdown definition with frontmatter (provider, model, role, level, XP) and auto-generated adapter shims for each harness you have installed (Claude Code, Codex, Gemini). The skill enforces a four-tier confirmation gate system, an append-only audit log, and a local-default provider policy that keeps external API calls opt-in.

Core capabilities:

- **HR operations**: hire, fire, transfer, promote, demote, second (matrix assignment), onboard, off-board, disband
- **Read-only inspection**: list, show, org-chart, lint
- **Outsource management**: outsource-hire, contract (freelance pool with project attachment)
- **OKR cascade**: set and review objectives at company, department, or team tier
- **Gamification**: XP, levels (1--5), achievements, skill tree, dashboard
- **Multi-provider**: 7 local providers and 18 external providers per role, local-default policy with egress consent gate
- **LLM Wiki**: compiled entity pages regenerated on every state change for fast, structured context
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
~/.software-house/config/models-config.json   <- Defaults by role (local-default)
~/.software-house/config/models-config.local.json <- User overlay (never overwritten on update)

<project>/.software-house/team/          <- Canonical team state (LLM Wiki)
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

- **Skill-managed** (`providers.json`, `models-config.json`) -- overwritten on each `install.sh` run with baseline defaults.
- **User overlay** (`*.local.json`) -- never overwritten by `install.sh`. Add custom providers, role defaults, or model aliases here.

When reading config, the overlay merges with and overrides the base file.

### Version and Migrations

The skill ships a `VERSION` file (semver). On update:

- **Same version**: prompts to confirm re-install (or skips with `--force`).
- **Upgrade**: shows CHANGELOG entries between versions, runs pending migrations, then installs.
- **Downgrade**: warns and requires confirmation.

Migrations are shell scripts in `migrations/NNN-<name>.sh`, run in sort order on version change. See `migrations/README.md` for the migration contract.

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
```

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

A bash CLI is available at `skills/software-house/bin/software-house`:

```sh
bin/software-house --help
bin/software-house --version          # 0.4.0
bin/software-house hire --help        # Per-command help
bin/software-house list people --dry-run  # Preview without changes
```

This is a reference scaffold -- all operations are implemented as step-by-step markdown instruction sets that Claude Code reads and follows. The bash CLI provides `--dry-run` previews and `--version` checks but some operations contain TODO placeholders for complex logic (YAML array manipulation, project root resolution, full JSON Schema validation).

### Privacy and Safety

The skill enforces a two-layer privacy model:

| Layer          | Who acts                          | What is allowed                                                                                        |
|----------------|-----------------------------------|--------------------------------------------------------------------------------------------------------|
| Skill          | The skill itself, while running   | Local file ops only. No `WebFetch`, `WebSearch`, `curl`, `git push`, MCP. Allowlist + denylist enforced before every shell command. |
| Agent runtime  | The harness (when an agent runs)  | Egress allowed IF the agent's `provider` is `external` AND the user typed `EGRESS-CONSENT-<provider>` at hire/set-model time, recorded in the audit log. Local-provider agents never egress. |

Confirmation gates apply even when the harness bypass flag is active:

| Tier                    | Examples                      | Gate                                                |
|-------------------------|-------------------------------|-----------------------------------------------------|
| 1 -- Read-only          | list, show, org-chart, lint   | none                                                |
| 2 -- Additive           | init, hire (draft), onboard   | "Reply 'yes' to proceed" boxed prompt              |
| 3 -- Modifying          | transfer, promote, demote     | Diff + "Reply 'yes' to proceed"                     |
| 4 -- Destructive        | fire, disband, off-board      | Two-step: intent prompt then `CONFIRM <subject-name>` |
| Egress consent (orthogonal) | hire/set-model with external provider | Literal `EGRESS-CONSENT-<provider>` token      |

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
| `set-model`      | Change provider/model/effort (egress re-consent if external)        | 3         |
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

### Additional Flags

| Flag                | Description                                                       |
|---------------------|-------------------------------------------------------------------|
| `--dry-run`         | Preview what would be done without making changes                 |
| `--fix-adapters`    | Regenerate per-project adapter shims from canonical agent files   |
| `--help`            | Show help                                                         |
| `--version`         | Show version (currently 0.4.0)                                    |

---

## Architecture Overview

The skill is organized in four tiers, each with the same internal layout:

```
<tier-root>/
  raw/       <- Immutable source documents (job specs, policies, etc.)
  wiki/      <- Compiled entity, concept, and synthesis pages (LLM Wiki)
  index.md   <- Auto-generated catalog of all entities in this tier
  audit.log  <- Append-only JSONL event stream
  CLAUDE.md  <- Schema and instructions for this tier
```

The **LLM Wiki** pattern compiles raw sources into dense, structured pages that the assistant can load in a fraction of the tokens required to re-read raw files. Pages are regenerated automatically whenever the underlying sources change.

Tiers:

1. **Company** -- `~/.software-house/company/` -- global policies, headcount, OKR top level
2. **Department** -- `~/.software-house/departments/<dept>/` -- grouped teams, dept OKRs
3. **Team** -- `<project>/.software-house/team/` -- project context, sprint board, team OKRs
4. **Role** -- `<project>/.software-house/agents/<role>.md` (canonical) plus auto-generated harness adapters under `<project>/.claude/agents/`, `<project>/.codex/agents/`, `<project>/.gemini/extensions/<role>/`. Freelance pool at `~/.software-house/agents/`.

---

## Project Structure

```
SoftwareHouseSkills/
  install.sh                                    <- Multi-harness installer
  skills/software-house/
    SKILL.md                                    <- Claude Code entry point
    AGENTS.md                                   <- Codex entry point
    GEMINI.md                                   <- Gemini entry point
    VERSION                                     <- Semver (0.4.0)
    CHANGELOG.md                                <- Keep a Changelog format
    bin/software-house                           <- Bash CLI (reference implementation)
    lib/_shared.sh                               <- Shared bash library
    lib/operations/                              <- 23 operation modules
    tests/                                       <- Test suite (9 files)
    commands/software-house.toml                 <- Gemini CLI command definition
    config/
      providers.json                             <- 25-provider catalog
      providers.local.json                       <- User overlay (never overwritten)
      models-config.json                         <- Role defaults (local-default)
      models-config.local.json                   <- User overlay (never overwritten)
    operations/                                  <- 24 operation spec markdown files
    schemas/agent.json                           <- JSON Schema (draft-07)
    templates/                                   <- Starter templates
    policies/                                   <- Privacy and safety policies
    migrations/                                  <- Schema migration scripts
```

---

## License

MIT -- copyright 2026 kanganapong sriduang. See [LICENSE.md](./LICENSE.md).