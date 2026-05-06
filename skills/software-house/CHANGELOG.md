# Changelog

All notable changes to the software-house skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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