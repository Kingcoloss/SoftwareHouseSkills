#!/usr/bin/env bash
# test-hire.sh -- tests for the hire operation
# TODO: Full coverage -- currently covers golden path only.

test_hire_creates_agent_file() {
  init_test_company
  load_config

  # Create a test agent file directly (bypassing interactive confirm)
  local test_name="alice"
  local canonical_file="$AGENTS_GLOBAL/${test_name}.md"

  local fm
  fm=$(cat <<FMEOF
name: $test_name
description: backend-dev agent
provider: ollama
model: qwen3-coder:32b
egress_consent: none
employee_id: emp-001
team: null
department: null
role: backend-dev
position: backend-dev
reports_to: null
status: onboarding
hired_at: $(utc_date)
level: 1
xp: 0
effort_preset: medium
classification: internal
buddy: null
employment: permanent
hired_by_teams: []
achievements: []
FMEOF
)

  local body="# $test_name\n\nAgent provisioned by software-house skill."
  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  assert_file_exists "$canonical_file" "agent file should be created"
  assert_contains "$canonical_file" "name: $test_name" "agent file should contain name"
  assert_contains "$canonical_file" "provider: ollama" "agent file should contain provider"
}

test_hire_validates_name() {
  init_test_company
  validate_name "alice"
  assert_eq "0" "$?" "alice should be a valid name"

  validate_name "INVALID"
  # Should fail
  assert_not_eq "0" "$?" "INVALID should be rejected"
}

test_hire_validates_role() {
  init_test_company
  load_config

  # Test that the default role exists
  local roles
  roles="$(list_roles)"
  assert_contains "$MODELS_CONFIG" "backend-dev" "models config should contain backend-dev role"
}

# Run tests
setup_test_env
test_hire_creates_agent_file
teardown_test_env

setup_test_env
test_hire_validates_name
teardown_test_env

setup_test_env
test_hire_validates_role
teardown_test_env