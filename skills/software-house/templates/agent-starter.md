---
name: <name>
description: <role-key> agent
provider: ollama
model: qwen3-coder:32b
egress_consent: none
employee_id: emp-<NNN>
team: <team-name>
department: <dept-name>
role: <role-key>
position: <human-readable position title>
reports_to: null
status: onboarding
hired_at: <YYYY-MM-DD>
level: 1
xp: 0
effort_preset: medium
classification: internal
buddy: null
employment: permanent
hired_by_teams: []
secondary_teams: []
contract_type: null
contract_start: null
contract_end: null
rate: null
achievements: []
responsibilities: []
deliverables: []
collaborates_with: []
handoff_triggers: {}
confidence: 1.0
lifecycle: draft
last_compiled: null
source_refs: []
onboard_at: null
onboard_status: null
offboard_at: null
offboard_status: null
promotion_at: null
promotion_from_level: null
demotion_at: null
demotion_from_level: null
fired_at: null
updated_at: null
tools: []
harness: null
---

# <name>

## Responsibilities

(Populated from role-templates.json at hire time.)

## Deliverables

(Populated from role-templates.json at hire time.)

## Collaboration Map

- Works with: (populated from role-templates.json at hire time)
- Escalates to: (populated from role-templates.json at hire time)

## Handoff Protocol

(Populated from role-templates.json handoff_triggers at hire time.)

When receiving a task:
1. Analyze which roles need to be involved
2. Generate a handoff brief for each role
3. Write briefs to wiki/handoffs/briefs/<from>-<to>-<timestamp>.md
4. CEO or orchestrator routes briefs to target agents

## Onboarding

Briefing not yet written. Run `/software-house onboard <name>` to generate.

## Notes

(empty)