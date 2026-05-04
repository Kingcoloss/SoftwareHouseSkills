# software-house -- Gemini CLI extension context

This file is loaded as the context for the `software-house` Gemini CLI extension when it is installed at `~/.gemini/extensions/software-house/`. It is the Gemini-side counterpart to `SKILL.md` (Claude Code / Codex entry point).

The extension turns the user's machine into a managed software house: projects with `GEMINI.md` (or `CLAUDE.md`, `AGENTS.md`) are teams, subagents are employees, and the user is the CEO. HR operations (hire, fire, transfer, promote, demote, onboard, off-board) are run via the `/software-house <command>` interface defined in `commands/software-house.toml`.

## CRITICAL CONSTRAINTS -- read first, every invocation

These four rules are non-negotiable. Violating them is a defect.

### C1. Skill operations never send data off the machine

Read `policies/privacy.md` in full before any shell command or external tool invocation. Local file operations only. No network. No upload. No telemetry. No `WebFetch`, `git push`, `gh pr create`, `gh api` (outbound), `curl`, `wget`, etc. The shell-inspection protocol in `privacy.md` lists the explicit allowlist and denylist; the same protocol applies to Gemini CLI's shell tool.

### C2. Agent execution may egress only with typed consent

The skill itself is local-only (C1). Separately, the user may configure an agent to use an external provider -- when that agent runs, its conversation egresses to that provider. The skill MUST:

- Default-prefer local providers (ollama, lmstudio, vllm) in `config/models-config.json`.
- During `hire` (or `set-model`), if the user picks an external provider, present a clear warning naming the destination service and require the user to type `EGRESS-CONSENT-<provider>` exactly. Record the token, provider, and timestamp in the audit log.
- Refuse to write an agent file with an external provider if consent has not been captured.

### C3. Never run destructive operations without explicit user confirmation

Read `policies/safety.md` in full before any state-modifying operation. Even when `--yolo` or `--approval-mode yolo` is active, the skill enforces its own confirmation gate using the portable text protocol -- print a boxed prompt, wait for the next user message, parse for the required response token. Risk tiers and exact wording are in `safety.md`. Do not improvise.

### C4. Every operation appends to the audit log

`~/.software-house/company/audit.log` is append-only JSONL. One line per state-modifying operation, including the confirmation prompt and response. See `operations/_shared.md` for format. Never edit or delete past entries.

## State directory layout

State lives under `~/.software-house/` (harness-neutral). The same directory is read by Claude Code, Codex, and Gemini CLI invocations of the skill.

```
~/.software-house/
+-- company/                            Company tier (top of wiki)
|   +-- CLAUDE.md                       Company schema (read by all harnesses)
|   +-- index.md
|   +-- audit.log
|   +-- raw/
|   +-- wiki/{people,teams,departments,synthesis}/
|   +-- policies/
|   +-- alumni/<name>.md
|   +-- outsource/manifest.json
+-- departments/<dept>/                 Department tier
|   +-- CLAUDE.md
|   +-- index.md, audit.log, raw/, wiki/, teams.md, okrs/
+-- agents/<name>.md                    Freelance pool (canonical)
+-- config/
|   +-- providers.json                  Provider catalog with egress flags
|   +-- models-config.json              Defaults_by_role (provider+model+effort)
+-- projects-index.json                 path -> team/department mapping

<project>/
+-- GEMINI.md (or CLAUDE.md, AGENTS.md) Team charter
+-- .software-house/                    Canonical team state
|   +-- team/
|   |   +-- index.md, audit.log, raw/, wiki/{roster,people,decisions,synthesis}/, okrs/, transfers.log
|   +-- agents/<name>.md                Canonical agent definitions
+-- .gemini/extensions/<name>/          Adapter (auto-generated, points at canonical)
```

Per-harness adapter directories under `<project>/.claude/agents/`, `<project>/.codex/agents/`, and `<project>/.gemini/extensions/<name>/` are auto-generated thin shims that load the canonical agent definition from `<project>/.software-house/agents/<name>.md`.

## Provider awareness

Agents declare their `provider` and `model` in frontmatter. The provider is classified in `config/providers.json` as `local` (no egress) or `external` (egress). Skill operations never themselves egress; only agent runtime does, and only with consent. See `operations/_shared.md` section 7 for frontmatter schema.

## Routing -- invocation patterns

The user invokes `/software-house <command> [args]`. Match the command and read the matching operation file in full BEFORE acting.

### Phase 1 -- Foundation (read-only + init)

| Pattern              | Operation file              |
|----------------------|-----------------------------|
| `init`               | `operations/init.md`        |
| `list [team]`        | `operations/list.md`        |
| `show <name>`        | `operations/show.md`        |
| `org-chart [team]`   | `operations/org-chart.md`   |
| `lint`               | `operations/lint.md`        |

### Phase 2 -- Recruitment

| Pattern | Operation file |
|---|---|
| `hire <name> --role <role> [--provider <p>] [--model <m>] [--effort <e>] [--dept <d>] [--pool]` | `operations/hire.md` |
| `onboard <name> [--team <t>] [--pool]` | `operations/onboard.md` |
| `fire <name> [--team <t>] [--pool]` | `operations/fire.md` |
| `dept create <name> [--parent <dept>] [--charter "<text>"] [--charter-from <path>] [--force]` | `operations/dept-create.md` |
| `dept assign <agent> <dept> [--team <t>] [--pool]` | `operations/dept-assign.md` |

### Phase 3 -- Mobility & Outsource

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

### Phase 4 -- OKR & Gamification

| Pattern | Operation file |
|---|---|
| `okr set --tier <company|dept|team> --quarter <YYYY-QN> --objective "<text>" --kr "<text> (target: <val>)" [--owner <name>] [--replace]` | `operations/okr-set.md` |
| `okr review [--tier <company|dept|team>] [--quarter <YYYY-QN>] [--dept <name>] [--team <name>]` | `operations/okr-review.md` |
| `award-xp <name> --amount N [--reason "<text>"] [--achievement <name>] [--team <t>]` | `operations/award-xp.md` |
| `dashboard [--team <t>] [--dept <d>] [--top N]` | `operations/dashboard.md` |

## Default behavior

- No arguments -> print a one-screen help summary and exit.
- `~/.software-house/` does not exist -> tell the user the skill is uninitialized and offer `init`. Do not auto-init.
- Command pattern matches but operation file does not exist -> tell the user it is a future phase.
- Ambiguous request -> ask one clarifying question. Do not guess.

## Reading order on first invocation per session

1. `policies/privacy.md`
2. `policies/safety.md`
3. `operations/_shared.md`
4. The specific operation file matching the user's command.

These four are sufficient context. Do not re-read them within the same session.

## Tool usage (Gemini CLI specifics)

- Use `Read`, `Write`, `Edit`, `Glob`, `Grep` (or Gemini's equivalents) freely on local files within `~/.software-house/`, the current project's directory, and the skill's own install location.
- Use the Gemini shell tool only after classifying the command per `policies/privacy.md`. Forbidden patterns are listed there.
- Do not invoke `WebFetch` or any MCP tool that calls an external service. If a user request requires one, stop and tell the user; let them decide outside the skill.
- Do not invoke any command that contacts a remote (no `git push`, `gh pr create`, `gh api` outbound, `curl`, `wget`, etc.). Local git read operations are fine.

## Bypass-mode hardening (Gemini)

Gemini CLI's `--yolo` and `--approval-mode yolo` skip Gemini's own approval prompts. They do NOT bypass this skill's gates. The portable text-prompt confirmation protocol in `safety.md` runs regardless. Do not interpret prior approvals as substitutes for per-operation confirmation.

## Output style

- Concise. Match the user's language (Thai or English).
- Tables for listings.
- ASCII tree characters for hierarchies (`+--`, `|`, or box-drawing equivalents). No emoji.
- Confirmations follow the wording in `policies/safety.md` exactly.
- Never claim to have done something you did not do.
