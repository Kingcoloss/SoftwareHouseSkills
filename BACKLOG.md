# Backlog

Tracking work items not yet shipped. Updated as part of each commit.

## Phase 2 -- Recruitment (DONE)

Operation specs wired into SKILL.md routing table. Schemas and templates populated.

- hire -- Create a new agent with provider/model/effort + egress consent gate (`hire.md`)
- onboard -- Run onboarding checklist for new agent (`onboard.md`)
- fire -- Remove an agent (Tier 4 destructive gate, two-step typed CONFIRM) (`fire.md`)
- dept-create -- Bootstrap a new department (`dept-create.md`)
- dept-assign -- Assign an agent to a department (`dept-assign.md`)
- SKILL.md routing -- Phase 2 ops wired into routing table
- Schemas -- `schemas/agent.json` validates all frontmatter fields from `_shared.md §7`
- Templates -- `templates/agent-starter.md` and `templates/dept-charter.md` populated

## Phase 3 -- Mobility & Outsource (DONE)

Operation specs written and wired into SKILL.md routing table.

- transfer -- Move an agent to another team (Tier 3, cross-project egress re-consent) (`transfer.md`)
- second -- Matrix-assign an agent to a second team (Tier 3) (`second.md`)
- promote -- Increase an agent's level/role (Tier 3) (`promote.md`)
- demote -- Decrease an agent's level/role (Tier 3) (`demote.md`)
- set-model -- Change provider/model/effort (Tier 3, egress re-consent on local-to-external) (`set-model.md`)
- outsource hire -- Add an agent to the freelance pool (Tier 2) (`outsource-hire.md`)
- contract -- Attach a freelance agent to a project (Tier 3) (`contract.md`)
- off-board -- Off-boarding checklist before removal (Tier 3) (`off-board.md`)
- disband -- Remove an entire team (Tier 4, two-step CONFIRM) (`disband.md`)

## Phase 4 -- OKR & Gamification (DONE)

Operation specs written and wired into SKILL.md routing table.

- okr set -- Set OKRs at company, department, team tier (Tier 2, Tier 3 with --replace) (`okr-set.md`)
- okr review -- Review OKR progress (Tier 1, read-only) (`okr-review.md`)
- award-xp -- Grant XP and trigger level/achievement checks (Tier 2) (`award-xp.md`)
- dashboard -- Show gamification stats and skill-tree state (Tier 1, read-only) (`dashboard.md`)

## Cross-cutting / future

- Cross-machine sync (deferred -- design uses files so git-trackable later)
- Reference implementation + integration tests (each operation spec is a markdown instruction set; no executable code yet)

## Update mechanism (cross-cutting; raised 2026-05-03)

Current update story: `--symlink` mode = `git pull` only; copy mode = `git pull && ./install.sh --force`. Canonical state at `~/.software-house/` is preserved. Five gaps that will hurt as the skill evolves:

1. **No version detection** -- install.sh does not read installed VERSION vs source VERSION. Re-running with older source silently overwrites. Fix: ship `skills/software-house/VERSION` (semver) and have install.sh compare and warn on downgrade.
2. **No diff/changelog preview** -- "Overwrite ?" prompt does not show what changes. Fix: show `diff -r` summary or `CHANGELOG.md` entries between installed and source versions before confirming.
3. **User edits to installed config are lost** -- `cp -R` blows away any local edits to `config/providers.json`, `config/models-config.json`, etc. Fix: split into skill-managed files (overwrite OK) plus `*.local.json` overlay files that install.sh never touches.
4. **No schema migration** -- if Phase 2+ changes agent frontmatter (e.g. adds required field), existing agents under `~/.software-house/` and per-project `<project>/.software-house/agents/` go stale. Fix: `skills/software-house/migrations/NNN-<name>.sh` runner invoked by install.sh on version change.
5. **Adapter shims do not re-sync** -- per-project `<project>/.claude/agents/<name>.md` shims are written once at hire time. If canonical agent schema changes, shims stay stale. Fix: `software-house lint --fix-adapters` to regenerate shims from canonical, or invoke regeneration from migration scripts.

Recommended skill layout addition:

```
skills/software-house/
+-- VERSION                         <- semver, read by install.sh
+-- CHANGELOG.md                    <- shown during update prompt
+-- migrations/
|   +-- 001-<name>.sh               <- auto-run on version change
+-- config/
|   +-- providers.json              <- skill-managed (overwrite on update)
|   +-- providers.local.json        <- user overlay (NEVER overwritten)
|   +-- models-config.json          <- skill-managed
|   +-- models-config.local.json    <- user overlay
```

Recommended new install.sh subcommand: `./install.sh --update` = source-version check + changelog display + migration runner + selective overwrite (preserving `*.local.*`). Suggested phase: 3.5 (between Phase 3 mobility and Phase 4 OKR), or earlier if external users start adopting before Phase 4.

## Done

- Polish round 1 (Phase 1.1):
  - install.sh confirm() widened to accept `y|yes|proceed|ok` case-insensitive (matches safety.md section 9)
  - install.sh detect_codex() honors `CODEX_HOME` env var
  - install.sh check_source() verifies all 6 required source files
  - safety.md section 9 tightened to whole-word reject (avoids false abort on "yes, no problem")
  - AGENTS.md / GEMINI.md adapter dir listing updated (no longer "(planned)")
  - adapters/codex.md openai.yaml description updated to reflect shipped file
- Phase 2 (Recruitment):
  - Operation specs: hire.md, onboard.md, fire.md, dept-create.md, dept-assign.md
  - SKILL.md routing table wired for Phase 2 commands
  - schemas/agent.json: JSON Schema (draft-07) validating agent frontmatter fields (completed to all _shared.md §7 fields in this commit)
  - templates/agent-starter.md: starter template for new agents (completed to all _shared.md §7 fields in this commit)
  - templates/dept-charter.md: starter template for department charters
  - _shared.md §7: added Phase 2+ frontmatter fields (onboard_at, onboard_status, contract_type, etc.)
- Phase 3 (Mobility & Outsource):
  - Operation specs: transfer.md, second.md, promote.md, demote.md, set-model.md, outsource-hire.md, contract.md, off-board.md, disband.md
  - SKILL.md routing table wired for Phase 3 commands
  - _shared.md §7: added secondary_teams, promotion/demotion fields
- Phase 4 (OKR & Gamification):
  - Operation specs: okr-set.md, okr-review.md, award-xp.md, dashboard.md
  - SKILL.md routing table wired for Phase 4 commands
  - XP thresholds: 100/300/600/1000 for levels 2-5
  - Achievement system: first-commit, code-reviewer-5, bug-hunter, team-lead, okr-champion