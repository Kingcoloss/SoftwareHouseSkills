# Changelog

All notable changes to the software-house skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-05-07

### Added

- Harness routing for sub-agent spawning. Agents can now route execution through another CLI (claude-code, codex, gemini, ollama:<integration>) via a new `harness` frontmatter field.
- `lib/providers/_shared.sh`: four new harness adapters (`execute_via_claude_code`, `execute_via_codex`, `execute_via_gemini`, `execute_via_ollama_launch`) plus a generic `execute_via_harness` dispatcher. All adapters write the model's response to a `.md` output file.
- Three-tier fallback in `execute_with_fallback`: harness transport -> direct provider -> Anthropic fallback. `execute_with_fallback` now accepts an optional 9th positional arg (`<harness>`).
- `lib/_shared.sh`: `resolve_harness`, `is_valid_harness`, `detect_harness_cli` helpers. `read_agent` now populates `AGENT_HARNESS`.
- `config/models-config.json`: new `harness_defaults` block keyed by provider (default null = direct execution).
- `schemas/agent.json`: optional `harness` field with regex pattern that explicitly forbids `ollama:gemini`.
- `templates/agent-starter.md`: `harness: null` field in starter frontmatter.
- `migrations/005-add-harness-field.sh`: idempotent backfill of `harness: null` for existing agents.
- `delegate` operation: new `--execute` and `--watch` flags. With `--execute`, after tier-2 confirmation the operation actually runs the sub-agent CLI inline via `execute_with_fallback` and writes output to the `.md` file (instead of only printing the `sh-agent` command). Default behavior unchanged.
- `set-model` operation: new `--harness <value>` and `--clear-harness` flags. Validates against the `is_valid_harness` allowlist; rejects `ollama:gemini` (gemini is not a recognized `ollama launch` integration) and rejects `ollama:*` for non-ollama providers.
- `bin/sh-agent`: new `--harness <value>` CLI override (beats agent frontmatter); resolves and validates harness, prints it in the execution plan, passes it to `execute_with_fallback`, includes it in the audit log.

### Fixed

- `lib/providers/ollama.sh`: removed nonexistent `--system` flag from `ollama run`. The system prompt is now embedded as a `<<SYSTEM>>...<<END_SYSTEM>>` prefix block in the user prompt; `--think` is set from the agent's effort preset; `--hidethinking --nowordwrap` are added for clean output. Previously `ollama run --system ...` silently failed against current Ollama releases.

## [0.8.0] - 2026-05-06

### Added

- Wiki-LLM ingestion: `operations/wiki-ingest.md` + `lib/operations/wiki-ingest.sh` -- archive source to raw/, compile into wiki pages (concept/decision/synthesis) with confidence/lifecycle/source_refs frontmatter
- Wiki health checks: `operations/wiki-lint.md` + `lib/operations/wiki-lint.sh` -- 8 check categories (confidence drift, stale pages, broken wikilinks, orphan pages, empty sections, missing concepts, source trail, wikilink consistency) with --fix-suggestions and --json output
- Obsidian vault setup: `scripts/obsidian-setup.sh` -- creates vault with symlinks to wiki directories, plugin recommendations (Graph Explorer, Dataview, LLM Wiki, Templater)
- init.sh: creates wiki/concepts/, wiki/decisions/, wiki/handoffs/ directories during bootstrap
- init.md: updated directory list with concepts, decisions, handoffs paths
- manifest.yaml: Phase 9 wiki-ingest + wiki-lint operations
- SKILL.md: Phase 9 routing table with wiki-ingest and wiki-lint command patterns
- bin/software-house: wiki-ingest and wiki-lint command dispatch

## [0.7.0] - 2026-05-06

### Added

- Inter-agent handoff protocol: `operations/handoff.md` + `lib/operations/handoff.sh`
- Handoff subcommands: list (with --team/--status/--from/--to filters), show, complete (--summary), generate (--priority/--context)
- Handoff brief schema: `schemas/handoff-brief.json` with frontmatter fields (from, to, task, priority, context_pages, created_at, status, completed_at, deliverables, dependencies, brief_id)
- Handoff directory structure: wiki/handoffs/inbox/, completed/, briefs/ (both company and team level)
- _shared.sh: added 12 new path constants for wiki directories (WIKI_CONCEPTS, WIKI_DECISIONS, WIKI_SYNTHESIS, WIKI_HANDOFFS, WIKI_HANDOFF_INBOX, WIKI_HANDOFF_COMPLETED, WIKI_HANDOFF_BRIEFS, WIKI_LOG, RAW_DIR, and team-level equivalents)
- manifest.yaml: Phase 8 handoff operation
- SKILL.md: Phase 8 routing table with 4 handoff command patterns
- bin/software-house: handoff compound command routing

## [0.6.0] - 2026-05-06

### Added

- Role templates: `config/role-templates.json` with 10 roles (tech-lead, system-architect, backend-dev, frontend-dev, code-reviewer, test-runner, linter, doc-writer, researcher, business-analyst) including responsibilities, deliverables, collaborates_with, escalates_to, and handoff_triggers
- Agent schema extended with 8 new fields: responsibilities, deliverables, collaborates_with, handoff_triggers, confidence, lifecycle, last_compiled, source_refs
- Agent starter template updated with structured role template sections
- models-config.json: xhigh effort preset and fallback_claude per role (opus+xhigh, sonnet+high, haiku+high)
- _shared.md section 19: wiki-LLM conventions (confidence scoring, lifecycle states, wikilinks)
- Sub-agent spawning: `bin/sh-agent` CLI executor that reads agent wiki for personalization, constructs system prompt from context, executes via provider adapters with automatic Claude fallback
- Provider adapters: `lib/providers/ollama.sh`, `lmstudio.sh`, `vllm.sh`, `anthropic.sh`, `_shared.sh` (common helpers, fallback logic, egress consent gate)
- Delegate operation: `operations/delegate.md` + `lib/operations/delegate.sh` (agent validation, role template loading, egress consent, handoff inbox entry, harness detection)
- _shared.sh role template helpers: load_role_templates(), get_role_template_field(), list_role_template_keys()
- Gemini adapter TOML fix for commands directory structure
- Migration 003: adds sprint/plan directories to existing teams, tools field to existing agents
- Migration 004: backfills role template fields (responsibilities, deliverables, collaborates_with, handoff_triggers) and wiki-LLM fields (confidence, lifecycle, last_compiled, source_refs) into existing agent canonical files and wiki pages
- manifest.yaml updated with Phase 7 (delegate) operation
- SKILL.md routing table updated with Phase 7 delegate commands
- bin/software-house CLI updated with delegate command routing

## [0.5.0] - 2026-05-04

### Added

- New roles: `researcher` and `business-analyst` in models-config.json (local + external fallback)
- Agent tool declarations: `config/tools-config.json` with canonical tool vocabulary, shared_tools, and per-role tool lists
- Agent frontmatter `tools` field (populated at hire time from shared_tools + role_tools)
- Agile Scrum operations: backlog-add, backlog-list, backlog-prioritize, sprint-create, sprint-plan, sprint-board, sprint-standup, sprint-review, sprint-retro
- Sprint and backlog data structures under `<project>/.software-house/team/sprints/` and `<project>/.software-house/team/backlog.md`
- Plan execution (auto-spawn) operations: plan-create, plan-confirm, plan-execute, plan-status, plan-synthesize
- Plan data structures under `<project>/.software-house/team/plans/` with dependency graph and topological sort
- Sub-agent spawning protocol: plan execute uses Claude Code Agent tool for parallel execution, manual dispatch for Codex/Gemini
- JSON Schema for sprint, backlog-item, and plan frontmatter validation (`schemas/sprint.json`, `schemas/backlog-item.json`, `schemas/plan.json`)
- Templates: `templates/backlog.md`, `templates/sprint.md`, `templates/plan.md`
- Bash operation stubs for all 14 new operations (backlog-*, sprint-*, plan-*)
- Migration 002: adds `tools` field to existing agent frontmatter
- SKILL.md routing table updated with Phase 5 (Scrum) and Phase 6 (Plan Execution)
- manifest.yaml updated with all operations from Phases 1-6 and tools_config reference
- bin/software-house CLI updated with backlog, sprint, plan compound command routing
- _shared.md sections 16-18: tools configuration, sprint/backlog data structures, plan data structures
- _shared.sh helpers: load_tools, get_shared_tools, get_role_tools, resolve_agent_tools, next_sprint_id, next_plan_id, read_sprint, read_plan, topological_sort, spawn_subagent

## [0.4.0] - 2026-05-04

### Added

- OKR cascade at company, department, and team tiers (`okr-set.md`, `okr-review.md`)
- XP and achievement system with configurable thresholds (`award-xp.md`)
- Gamification dashboard showing stats, skill-tree state, and leaderboards (`dashboard.md`)
- SKILL.md routing table wired for Phase 4 commands
- XP thresholds: 100/300/600/1000 for levels 2-5
- Achievement system: first-commit, code-reviewer-5, bug-hunter, team-lead, okr-champion

## [0.3.0] - 2026-05-03

### Added

- Agent transfer between teams with cross-project egress re-consent (`transfer.md`)
- Matrix assignment of agents to secondary teams (`second.md`)
- Agent promotion and demotion with level tracking (`promote.md`, `demote.md`)
- Provider/model/effort changes with egress re-consent on local-to-external (`set-model.md`)
- Freelance pool hiring and project contracting (`outsource-hire.md`, `contract.md`)
- Off-boarding checklist before agent removal (`off-board.md`)
- Team disband with two-step CONFIRM gate (`disband.md`)
- SKILL.md routing table wired for Phase 3 commands
- _shared.md section 7: added secondary_teams, promotion/demotion frontmatter fields

## [0.2.0] - 2026-05-02

### Added

- Agent hiring with provider/model/effort selection and egress consent gate (`hire.md`)
- Onboarding checklist for new agents (`onboard.md`)
- Agent removal with two-step CONFIRM gate (`fire.md`)
- Department creation with optional charter (`dept-create.md`)
- Department agent assignment (`dept-assign.md`)
- SKILL.md routing table wired for Phase 2 commands
- JSON Schema (draft-07) for agent frontmatter validation (`schemas/agent.json`)
- Starter templates for agents and department charters (`templates/`)
- _shared.md section 7: extended frontmatter with Phase 2+ fields

## [0.1.0] - 2026-05-01

### Added

- Multi-harness installer (`install.sh`) supporting Claude Code, Codex CLI, and Gemini CLI
- Harness detection and selective install via `--harness` flag
- Symlink dev mode via `--symlink` flag
- Core skill entry points: `SKILL.md`, `AGENTS.md`, `GEMINI.md`
- Foundation operations: `init`, `list`, `show`, `org-chart`, `lint`
- Privacy policy enforcing local-first, no-network rule (`policies/privacy.md`)
- Safety policy with four-tier confirmation gates (`policies/safety.md`)
- Shared operation primitives and audit log format (`operations/_shared.md`)
- Provider catalog with 25 providers (7 local, 18 external) (`config/providers.json`)
- Role-based model defaults and effort presets (`config/models-config.json`)
- Harness adapter shims for Claude Code, Codex, and Gemini (`adapters/`)
- Gemini extension manifest and command definitions