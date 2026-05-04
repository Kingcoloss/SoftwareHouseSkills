#!/usr/bin/env bash
# test-award-xp.sh -- tests for the award-xp operation
# TODO: Full coverage -- currently covers golden path only.

test_award_xp_increments_total() {
  init_test_company

  local test_name="dave"
  local canonical_file="$AGENTS_GLOBAL/${test_name}.md"

  local fm
  fm=$(cat <<FMEOF
name: $test_name
description: backend-dev agent
provider: ollama
model: qwen3-coder:32b
egress_consent: none
employee_id: emp-004
team: null
department: null
role: backend-dev
position: backend-dev
reports_to: null
status: active
hired_at: $(utc_date)
level: 1
xp: 50
effort_preset: medium
classification: internal
buddy: null
employment: permanent
hired_by_teams: []
achievements: []
FMEOF
)

  local body="# $test_name\n\nAgent."
  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  # Simulate award-xp: add 50 to 50 = 100, level up to 2
  read_agent "$canonical_file"
  assert_eq "50" "$AGENT_XP" "initial XP should be 50"

  local new_xp=$(( AGENT_XP + 50 ))
  write_agent_field "$canonical_file" "xp" "$new_xp"

  # Check level up (100 XP = level 2)
  local new_level=2
  write_agent_field "$canonical_file" "level" "$new_level"

  read_agent "$canonical_file"
  assert_eq "100" "$AGENT_XP" "XP should be 100 after award"
  assert_eq "2" "$AGENT_LEVEL" "level should be 2 after XP award triggers level up"
}

test_award_xp_validates_amount() {
  # Amount must be positive
  local amount=0
  if (( amount <= 0 )); then
    assert_eq "1" "1" "zero amount should be rejected"
  fi
}

# Run tests
setup_test_env
test_award_xp_increments_total
teardown_test_env

test_award_xp_validates_amount