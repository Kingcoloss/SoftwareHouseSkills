# Backlog

Tracking work items not yet shipped. Updated as part of each commit.

## Phase 2 -- Recruitment (spec scaffolded; implementation pending)

Operation specs exist under `skills/software-house/operations/`. Implementation = wiring SKILL.md routing + reference impl + tests.

- hire -- Create a new agent with provider/model/effort + egress consent gate (`hire.md`)
- onboard -- Run onboarding checklist for new agent (`onboard.md`)
- fire -- Remove an agent (Tier 4 destructive gate, two-step typed CONFIRM) (`fire.md`)
- dept-create -- Bootstrap a new department (`dept-create.md`)
- dept-assign -- Assign an agent to a department (`dept-assign.md`)
- SKILL.md routing -- Add Phase 2 ops to operation routing table (not yet wired)
- Schemas -- Define agent frontmatter JSON schema in `schemas/` (referenced by hire/fire/dept-assign)

## Phase 3 -- Mobility & Outsource (not started)

- transfer -- Move an agent to another team
- second -- Matrix-assign an agent to a second team
- promote -- Increase an agent's level/role
- demote -- Decrease an agent's level/role
- set-model -- Change provider/model/effort (egress re-consent on local to external)
- outsource hire -- Add an agent to the freelance pool
- contract -- Attach a freelance agent to a project
- off-board -- Off-boarding checklist before removal
- disband -- Remove an entire team (Tier 4 destructive gate)

## Phase 4 -- OKR & Gamification (not started)

- okr set -- Set OKRs at company, department, team, or role tier
- okr review -- Review OKR progress and adjust
- award-xp -- Grant XP and trigger level/achievement checks
- dashboard -- Show gamification stats and skill-tree state across all agents

## Cross-cutting / future

- Cross-machine sync (deferred -- design uses files so git-trackable later)
- Templates dir is empty -- populate with starter agent and dept charter templates
- Freelance pool agents do not get adapters at hire; trigger adapter generation on future `transfer` (flagged by Track B during Phase 2 design)
- `lint` does not yet check for missing department agent indexes (flagged by Track B)
- `fire.md` uses `rm` for adapter shims (justified as auto-generated, no unique content); revisit if a `mv`-to-temp recovery path becomes desirable

## Done

- Polish round 1 (Phase 1.1):
  - install.sh confirm() widened to accept `y|yes|proceed|ok` case-insensitive (matches safety.md section 9)
  - install.sh detect_codex() honors `CODEX_HOME` env var
  - install.sh check_source() verifies all 6 required source files
  - safety.md section 9 tightened to whole-word reject (avoids false abort on "yes, no problem")
  - AGENTS.md / GEMINI.md adapter dir listing updated (no longer "(planned)")
  - adapters/codex.md openai.yaml description updated to reflect shipped file
