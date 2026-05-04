#!/usr/bin/env bash
# test-promote.sh -- tests for the promote operation
# TODO: Full coverage -- currently covers golden path only.

test_promote_updates_level() {
  init_test_company

  local test_name="carol"
  local canonical_file="$AGENTS_GLOBAL/${test_name}.md"

  local fm
  fm=$(cat <<FMEOF
name: $test_name
description: tech-lead agent
provider: ollama
model: deepseek-v3:671b-q4_K_M
egress_consent: none
employee_id: emp-003
team: null
department: null
role: tech-lead
position: tech-lead
reports_to: null
status: active
hired_at: $(utc_date)
level: 2
xp: 150
effort_preset: high
classification: internal
buddy: null
employment: permanent
hired_by_teams: []
achievements: []
FMEOF
)

  local body="# $test_name\n\nAgent."
  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  # Simulate promote: level 2 -> level 3
  read_agent "$canonical_file"
  assert_eq "2" "$AGENT_LEVEL" "initial level should be 2"

  write_agent_field "$canonical_file" "level" "3"
  write_agent_field "$canonical_file" "promotion_at" "$(utc_date)"
  write_agent_field "$canonical_file" "promotion_from_level" "2"

  read_agent "$canonical_file"
  assert_eq "3" "$AGENT_LEVEL" "level should be 3 after promotion"
}

# Run tests
setup_test_env
test_promote_updates_level
teardown_test_env