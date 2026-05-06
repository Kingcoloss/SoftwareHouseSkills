---
name: software-house
description: Run the user's computer like a software house company. Manages projects-as-teams and subagents-as-employees with HR operations (hire, fire, transfer, promote, demote, second, disband, onboard, off-board), four-tier org hierarchy (Company → Department → Team → Role), an LLM-Wiki memory system per tier (raw/wiki/index/log), OKR cascade, gamification (XP, achievements, skill tree unlocks), and per-role provider+model+effort selection. Works across Claude Code, OpenAI Codex CLI, and Gemini CLI — same canonical state under ~/.software-house/, harness-specific entry points (SKILL.md, AGENTS.md, GEMINI.md). Agents may use any provider (Ollama, LM Studio, vLLM, llama.cpp, LocalAI, Jan for local; Anthropic, OpenAI, Google, Azure, Bedrock, Groq, Together, Fireworks, DeepSeek, Mistral, Cohere, xAI, Perplexity, OpenRouter, Replicate, HuggingFace, Novita for external). Invoked when the user types `/software-house <command>` or asks about hiring, firing, promoting, transferring, listing, showing the org chart, setting OKRs, or any company-style operation over their projects and agents. Critical guarantee — the skill itself runs entirely on the local machine and never sends data off the user's computer; agents that the user explicitly configures with an external provider may egress only after typed consent recorded in the audit log; destructive operations always require explicit confirmation, even with --dangerously-skip-permissions.
---

# Software House — Company OS Skill

Turn the user's computer into a managed software house: projects with `CLAUDE.md` (or `AGENTS.md`, `GEMINI.md`) are **teams**, subagents are **employees**, and the user is the **CEO**. Perform HR operations, maintain a per-tier LLM-Wiki memory system (Karpathy "compile, don't re-derive" pattern), and provide org visibility.

## CRITICAL CONSTRAINTS — read first, every invocation

These four rules are non-negotiable. Violating them is a defect.

### C1. Skill operations never send data off the machine

**Read `policies/privacy.md` in full before any Bash command or external tool invocation.** Local file operations only. No network. No upload. No telemetry. No `WebFetch`, `WebSearch`, `git push`, `gh pr create`, `gh api` (outbound), `curl`, `wget`, etc. The Bash inspection protocol in `privacy.md` lists the explicit allowlist and denylist.

### C2. Agent execution may egress only with typed consent

The skill itself is local-only (C1). Separately, the user may configure an agent to use an external provider (Anthropic, OpenAI, Google, etc.) — when that agent runs, its conversation egresses to that provider. The skill MUST:

- Default-prefer local providers (Ollama, LM Studio, vLLM) in `models-config.json`.
- During `hire` (or `set-model`), if the user picks an external provider, present a clear warning naming the destination service and require the user to type `EGRESS-CONSENT-<provider>` exactly. Record the consent token, provider, and timestamp in the audit log.
- Refuse to write an agent file with an external provider if consent has not been captured.

### C3. Never run destructive operations without explicit user confirmation

**Read `policies/safety.md` in full before any state-modifying operation.** Even when `--dangerously-skip-permissions` (or the equivalent in Codex/Gemini) is active, the skill enforces its own confirmation gate using a portable text protocol — print a boxed prompt, wait for the next user message, parse for the required response token. Risk tiers and exact wording are in `safety.md`. Do not improvise.

### C4. Every operation appends to the audit log

`~/.software-house/company/audit.log` is append-only JSONL. One line per state-modifying operation, including the confirmation prompt and response. See `operations/_shared.md` for format. Never edit or delete past entries.

## State directory layout

State lives under `~/.software-house/` (harness-neutral). The same directory is read by Claude Code, Codex, and Gemini CLI invocations.

```
~/.software-house/
├── company/                            # Company tier (top of wiki)
│   ├── CLAUDE.md                       # Company schema (read by all harnesses)
│   ├── index.md
│   ├── audit.log
│   ├── raw/
│   ├── wiki/{people,teams,departments,synthesis}/
│   ├── policies/
│   ├── alumni/<name>.md
│   └── outsource/manifest.json
│
├── departments/<dept>/                 # Department tier
│   ├── CLAUDE.md
│   ├── index.md
│   ├── audit.log
│   ├── raw/
│   ├── wiki/{standards,decisions}/
│   ├── teams.md
│   └── okrs/<quarter>.md
│
├── agents/<name>.md                    # Freelance pool (canonical)
│
├── config/
│   ├── providers.json                  # Provider catalog with egress flags
│   ├── models-config.json              # Defaults_by_role (provider+model+effort)
│   └── tools-config.json               # Shared tools + per-role tool declarations
│
└── projects-index.json                 # path → team/department mapping

<project>/
├── CLAUDE.md (or AGENTS.md, GEMINI.md) # Team charter
├── .software-house/                    # Canonical team state
│   ├── team/
│   │   ├── index.md
│   │   ├── audit.log
│   │   ├── raw/
│   │   ├── wiki/{roster.md,people,decisions,synthesis}/
│   │   ├── okrs/<quarter>.md
│   │   └── transfers.log
│   └── agents/<name>.md                # Canonical agent definitions
│
├── .claude/agents/<name>.md            # Adapter (auto-generated, points at canonical)
├── .codex/agents/<name>.md             # Adapter (auto-generated)
└── .gemini/extensions/<name>/          # Adapter (auto-generated)
```

## Harness compatibility

The skill installs into multiple agent CLIs. Each install location holds a thin entry-point pointing at the same operation files in this skill source tree.

| Harness | Skill install path | Entry-point file |
|---|---|---|
| Claude Code | `~/.claude/skills/software-house/` | `SKILL.md` (this file) |
| OpenAI Codex CLI | `~/.agents/skills/software-house/` (or per Codex config) | `SKILL.md` (Codex also reads SKILL.md) plus repo-level `AGENTS.md` |
| Gemini CLI | `~/.gemini/extensions/software-house/` | `gemini-extension.json` + `GEMINI.md` + `commands/*.toml` |

`install.sh` detects which harnesses are present (by checking for `~/.claude`, `~/.codex` or `~/.agents`, `~/.gemini`) and installs into each.

The operation files (`operations/*.md`) are harness-portable — they reference only Read, Write, Edit, Bash, Glob, Grep (which all harnesses provide) and use the portable text-confirmation protocol.

## Provider awareness

Agents declare their `provider` and `model` in frontmatter. The provider is classified in `config/providers.json` as `local` (no egress) or `external` (egress). Skill operations never themselves egress; only agent runtime does, and only with consent. See `_shared.md §7` for frontmatter schema.

## Routing — invocation patterns

User invokes `/software-house <command> [args]`. Match the command and read the matching operation file in full BEFORE acting.

### Phase 1 — Foundation (read-only + init)

| Pattern | Operation file |
|---|---|
| `init` | `operations/init.md` |
| `list [team]` | `operations/list.md` |
| `show <name>` | `operations/show.md` |
| `org-chart [team]` | `operations/org-chart.md` |
| `lint` | `operations/lint.md` |

### Phase 2 — Recruitment

| Pattern | Operation file |
|---|---|
| `hire <name> --role <role> [--provider <p>] [--model <m>] [--effort <e>] [--dept <d>] [--pool]` | `operations/hire.md` |
| `onboard <name> [--team <t>] [--pool]` | `operations/onboard.md` |
| `fire <name> [--team <t>] [--pool]` | `operations/fire.md` |
| `dept create <name> [--parent <dept>] [--charter "<text>"] [--charter-from <path>] [--force]` | `operations/dept-create.md` |
| `dept assign <agent> <dept> [--team <t>] [--pool]` | `operations/dept-assign.md` |

### Phase 3 — Mobility & Outsource

| Pattern | Operation file |
|---|---|
| `transfer <name> --to <team> [--team <current>]` | `operations/transfer.md` |
| `second <name> --to <team>` | `operations/second.md` |
| `promote <name> [--by N] [--to-role <role>]` | `operations/promote.md` |
| `demote <name> [--by N] [--to-role <role>]` | `operations/demote.md` |
| `set-model <name> [--provider <p>] [--model <m>] [--effort <e>]` | `operations/set-model.md` |
| `outsource hire <name> --role <role> [--provider <p>] [--model <m>] [--contract-type <type>] [--contract-end <date>]` | `operations/outsource-hire.md` |
| `contract <name> --team <team>` | `operations/contract.md` |
| `off-board <name> [--team <t>] [--pool]` | `operations/off-board.md` |
| `disband <team>` | `operations/disband.md` |

### Phase 4 — OKR & Gamification

| Pattern | Operation file |
|---|---|
| `okr set --tier <company\|dept\|team> --quarter <YYYY-QN> --objective "<text>" --kr "<text> (target: <val>)" [--owner <name>] [--replace]` | `operations/okr-set.md` |
| `okr review [--tier <company\|dept\|team>] [--quarter <YYYY-QN>] [--dept <name>] [--team <name>]` | `operations/okr-review.md` |
| `award-xp <name> --amount N [--reason "<text>"] [--achievement <name>] [--team <t>]` | `operations/award-xp.md` |
| `dashboard [--team <t>] [--dept <d>] [--top N]` | `operations/dashboard.md` |

### Phase 5 -- Agile Scrum

| Pattern | Operation file |
|---|---|
| `backlog add --title "<text>" [--description "<text>"] [--priority N] [--assignee <name>] [--story-points N] [--type bug\|feature\|task\|spike]` | `operations/backlog-add.md` |
| `backlog list [--status open\|in-sprint\|closed\|all] [--type <type>] [--assignee <name>]` | `operations/backlog-list.md` |
| `backlog prioritize --item <id> --priority N` | `operations/backlog-prioritize.md` |
| `sprint create --name "<text>" --duration <N>w [--goal "<text>"] [--start-date YYYY-MM-DD]` | `operations/sprint-create.md` |
| `sprint plan --sprint <id> --add <backlog-item-id> [--remove <id>] [--from-plan <plan-id>]` | `operations/sprint-plan.md` |
| `sprint board [--sprint <id>]` or `sprint board --move <item-id> --to todo\|in-progress\|review\|done` | `operations/sprint-board.md` |
| `sprint standup --sprint <id> --agent <name> --done "<text>" --doing "<text>" --blockers "<text>"` | `operations/sprint-standup.md` |
| `sprint review --sprint <id> [--demo "<text>"] [--feedback "<text>"]` | `operations/sprint-review.md` |
| `sprint retro --sprint <id> --went-well "<text>" --improve "<text>" --action-items "<text>"` | `operations/sprint-retro.md` |

### Phase 6 -- Plan Execution (Auto-spawn)

| Pattern | Operation file |
|---|---|
| `plan create --name "<text>" [--sprint <sprint-id>]` | `operations/plan-create.md` |
| `plan confirm --plan <plan-id>` | `operations/plan-confirm.md` |
| `plan execute --plan <plan-id> [--max-parallel N]` | `operations/plan-execute.md` |
| `plan status --plan <plan-id>` | `operations/plan-status.md` |
| `plan synthesize --plan <plan-id>` | `operations/plan-synthesize.md` |

## Default behavior

- No arguments → print a 1-screen help summary and exit.
- `~/.software-house/` does not exist → tell the user the skill is uninitialized and offer `init`. Do not auto-init.
- Command pattern matches but operation file does not exist → tell the user it is a future phase.
- Ambiguous request → ask one clarifying question. Do not guess.

## Reading order on first invocation per session

1. `policies/privacy.md`
2. `policies/safety.md`
3. `operations/_shared.md`
4. The specific operation file matching the user's command.

These four are sufficient context. Do not re-read them within the same session.

## Tool usage

- Use `Read`, `Write`, `Edit`, `Glob`, `Grep` freely on local files within `~/.software-house/`, the current project's directory, and the skill's own install location.
- Use `Bash` only after classifying the command per `policies/privacy.md`. Forbidden patterns are listed there.
- Do not invoke `WebFetch`, `WebSearch`, or any MCP tool. If a user request requires one, stop and tell the user; let them decide outside the skill.
- Do not invoke any command that contacts a remote (no `git push`, `gh pr create`, `gh api` outbound, `curl`, `wget`, etc.). Local git read operations are fine.

## Output style

- Concise. Match the user's language (Thai or English).
- Tables for listings.
- ASCII tree characters for hierarchies (`+--`, `|`, or box-drawing `├── │ └──`). No emoji.
- Confirmations follow the wording in `policies/safety.md` exactly.
- Never claim to have done something you did not do.
