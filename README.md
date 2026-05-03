# software-house

A multi-harness, multi-provider skill that turns your local machine into a managed software house. Subagents become employees, projects become teams, and you become the CEO. The skill itself never sends a byte off your machine; agents that you explicitly configure with an external provider may egress only after you type a one-time `EGRESS-CONSENT-<provider>` token recorded in the audit log. HR-style workforce operations, OKR cascades, and a gamified skill system, accessible the same way from Claude Code, OpenAI Codex CLI, or Gemini CLI.

---

## Mental Model

| Real World     | This Skill (canonical)                                         | Per-harness adapter (auto-generated)                       |
|----------------|----------------------------------------------------------------|------------------------------------------------------------|
| Company        | Your computer (`~/.software-house/`)                           | n/a                                                        |
| Department     | Named group of teams (`~/.software-house/departments/<d>/`)    | n/a                                                        |
| Team           | A project folder with `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md` | n/a                                                        |
| Employee       | Canonical agent at `<project>/.software-house/agents/<n>.md`   | `<project>/.claude/agents/`, `.codex/agents/`, `.gemini/extensions/<n>/` (thin shims) |
| Freelance pool | `~/.software-house/agents/`                                    | `~/.claude/agents/`, `~/.codex/agents/`, `~/.gemini/extensions/<n>/`                  |
| CEO            | You                                                            | n/a                                                        |

```
~/.software-house/                       <- Canonical state (harness-neutral)
~/.software-house/company/               <- Company tier (audit log lives here)
~/.software-house/departments/<d>/       <- Department tier
~/.software-house/agents/                <- Freelance / outsource pool
~/.software-house/config/providers.json  <- 25-provider catalog with egress flags
~/.software-house/config/models-config.json  <- Defaults_by_role (local-default)

<project>/.software-house/team/          <- Canonical team state (LLM Wiki)
<project>/.software-house/agents/<n>.md  <- Canonical agent definition
<project>/.claude/agents/<n>.md          <- Adapter (auto-generated)
<project>/.codex/agents/<n>.md           <- Adapter (auto-generated)
<project>/.gemini/extensions/<n>/        <- Adapter (auto-generated)
```

The same canonical state is read by all three CLIs. Per-harness adapter directories are thin shims that point at the canonical agent file, so you can hire an employee once and use them from any harness.

---

## Harness Compatibility

| Harness          | Install path (default)                  | Entry-point file               | Bypass flag (still gated by skill) |
|------------------|-----------------------------------------|--------------------------------|------------------------------------|
| Claude Code      | `~/.claude/skills/software-house/`      | `SKILL.md`                     | `--dangerously-skip-permissions`   |
| OpenAI Codex CLI | `~/.agents/skills/software-house/`      | `SKILL.md` (+ `agents/openai.yaml`) | `--dangerously-bypass-approvals-and-sandbox` / `--full-auto` |
| Gemini CLI       | `~/.gemini/extensions/software-house/`  | `gemini-extension.json` + `GEMINI.md` + `commands/*.toml` | `--yolo` / `--approval-mode yolo`  |

`./install.sh` auto-detects which harnesses are present (by checking for `~/.claude`, `~/.codex` or `~/.agents`, `~/.gemini`) and installs the same source tree into each. Codex requires one manual step after install (a `[[skills]]` entry in `~/.codex/config.toml`); the installer prints the exact snippet.

---

## Key Features

- HR operations: hire, fire, transfer, promote, demote, second (matrix assignment), disband, onboard, off-board.
- Read-only inspection: list, show, org-chart, lint.
- Multi-provider per role: 7 local providers (Ollama, LM Studio, vLLM, llama.cpp, LocalAI, Jan, text-generation-webui) and 18 external (Anthropic, OpenAI, Google, Vertex, Azure, Bedrock, Groq, Together, Fireworks, DeepSeek, Mistral, Cohere, xAI, Perplexity, OpenRouter, Replicate, HuggingFace, Novita).
- Local-default policy: `models-config.json` defaults every role to a local provider; external providers require typed consent.
- OKR cascade from company down to individual roles.
- Gamification: XP, levels, achievements, and a skill tree per agent.
- LLM Wiki compiled at every tier — fast, structured context without re-deriving it each session (inspired by Andrej Karpathy's "compile, don't re-derive" pattern: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).
- Append-only audit log at `~/.software-house/company/audit.log` (JSONL).

---

## Privacy & Safety Guarantees

These are first-class, non-negotiable constraints — not optional settings. Detailed in `skills/software-house/policies/privacy.md` and `safety.md`.

### Two-layer privacy model

| Layer        | Who acts                       | What's allowed                                                            |
|--------------|--------------------------------|---------------------------------------------------------------------------|
| Skill        | The skill itself, while running | Local file ops only. No `WebFetch`, `WebSearch`, `curl`, `git push`, MCP. Allowlist + denylist enforced before every shell command. |
| Agent runtime| The harness (when an agent runs)| Egress allowed IF the agent's `provider` is `external` AND the user typed `EGRESS-CONSENT-<provider>` at hire/set-model time, recorded in the audit log. Local-provider agents never egress. |

### Confirmation gates (portable text protocol — works on every harness)

| Tier | Examples                          | Gate                                                          |
|------|-----------------------------------|---------------------------------------------------------------|
| 1 — Read-only | list, show, org-chart, lint  | none                                                          |
| 2 — Additive  | init, hire (draft), onboard  | "Reply 'yes' to proceed" boxed prompt                         |
| 3 — Modifying | transfer, promote, demote    | Diff + "Reply 'yes' to proceed"                               |
| 4 — Destructive | fire, disband, off-board   | Two-step: intent prompt then literal `CONFIRM <subject-name>` |
| Egress consent (orthogonal) | hire/set-model with external provider | Literal `EGRESS-CONSENT-<provider>` token                     |

These gates apply even when the harness's bypass flag (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo`, etc.) is active.

### Audit log

Every state-modifying operation appends one JSONL line to `~/.software-house/company/audit.log`. The line records the operation, args (secrets stripped), the verbatim confirmation prompt and user response, and the egress consent token if applicable. Records are never edited or deleted.

### Allowlist / denylist for shell commands

Every shell command (Bash on Claude Code, shell on Codex, shell on Gemini) is classified before execution per `policies/privacy.md` §2. Network-capable commands (`curl`, `wget`, `git push`, `gh pr create`, `nc`, etc.) are denylisted. Local file operations are allowlisted. Anything else is refused.

---

## Quick Start

Install the skill — see [INSTALL.md](./INSTALL.md) for full details. The short version:

```sh
./install.sh                       # auto-detects all installed harnesses
./install.sh --list-harnesses      # see what would be installed
./install.sh --harness claude-code # restrict to one harness
```

Then open any project and run:

```
/software-house init
```

Bootstraps `~/.software-house/`. Confirmation prompted before any file is created.

To hire your first local-provider employee:

```
/software-house hire alice --role backend-dev
```

Defaults to a local provider (Ollama). The skill prints the plan and asks for confirmation; no egress consent needed because the provider is local.

To hire an external-provider employee (Phase 2 — planned):

```
/software-house hire bob --role tech-lead --provider anthropic --model claude-opus-4-7
```

The skill prints a warning naming the destination service (`api.anthropic.com`) and waits for you to type `EGRESS-CONSENT-anthropic` before writing the agent file.

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

1. **Company** — `~/.software-house/company/` — global policies, headcount, OKR top level
2. **Department** — `~/.software-house/departments/<dept>/` — grouped teams, dept OKRs
3. **Team** — `<project>/.software-house/team/` — project context, sprint board, team OKRs
4. **Role** — `<project>/.software-house/agents/<role>.md` (canonical) plus auto-generated harness adapters under `<project>/.claude/agents/`, `<project>/.codex/agents/`, `<project>/.gemini/extensions/<role>/`. Freelance pool at `~/.software-house/agents/`.

---

## Available Commands

| Command           | Description                                              | Status              |
|-------------------|----------------------------------------------------------|---------------------|
| `init`            | Bootstrap `~/.software-house/`                           | Phase 1 — ready     |
| `list`            | List people, teams, departments, freelance pool          | Phase 1 — ready     |
| `show`            | Display one entity in detail                             | Phase 1 — ready     |
| `org-chart`       | Render ASCII org tree                                    | Phase 1 — ready     |
| `lint`            | Health-check the company state                           | Phase 1 — ready     |
| `hire`            | Create and onboard a new agent (egress consent if external) | Phase 2 — planned   |
| `onboard`         | Run onboarding checklist for a new agent                 | Phase 2 — planned   |
| `fire`            | Remove an agent (Tier 4 gate)                            | Phase 2 — planned   |
| `off-board`       | Off-boarding checklist before removal                    | Phase 2 — planned   |
| `dept create`     | Create a new department                                  | Phase 2 — planned   |
| `dept assign`     | Assign a team to a department                            | Phase 2 — planned   |
| `transfer`        | Move an agent to another team                            | Phase 3 — planned   |
| `second`          | Matrix-assign an agent to a second team                  | Phase 3 — planned   |
| `promote`         | Increase an agent's level/role                           | Phase 3 — planned   |
| `demote`          | Decrease an agent's level/role                           | Phase 3 — planned   |
| `set-model`       | Change provider/model/effort for a role (egress consent if external) | Phase 3 — planned   |
| `outsource hire`  | Add an agent to the freelance pool                       | Phase 3 — planned   |
| `contract`        | Attach a freelance agent to a project                    | Phase 3 — planned   |
| `disband`         | Remove an entire team (Tier 4 gate)                      | Phase 3 — planned   |
| `okr set`         | Set OKRs at any tier                                     | Phase 4 — planned   |
| `okr review`      | Review OKR progress                                      | Phase 4 — planned   |
| `award-xp`        | Grant XP and trigger level/achievement checks            | Phase 4 — planned   |
| `dashboard`       | Show gamification stats across all agents                | Phase 4 — planned   |

---

## Development Status

**Phase 1 — Foundation + Read-only** is currently in progress.

The scaffolding for all four tiers, the LLM Wiki convention, the audit log writer, multi-harness adapters, and the read-only commands (`init`, `list`, `show`, `org-chart`, `lint`) are being built in this phase. Subsequent phases add write operations (`hire`, `fire`, `dept create`), mobility mechanics (`transfer`, `promote`, `set-model`), outsourcing, and the OKR/gamification system.

---

## License

MIT — copyright 2026 kanganapong sriduang. See [LICENSE.md](./LICENSE.md).
