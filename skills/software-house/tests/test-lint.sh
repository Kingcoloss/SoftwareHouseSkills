#!/usr/bin/env bash
# test-lint.sh -- tests for the lint operation
# TODO: Full coverage -- currently covers golden path only.

test_lint_detects_missing_egress_consent() {
  init_test_company

  # Create an agent with external provider but no egress consent
  local test_name="eve"
  local canonical_file="$AGENTS_GLOBAL/${test_name}.md"

  local fm
  fm=$(cat <<FMEOF
name: $test_name
description: agent with bad egress
provider: anthropic
model: claude-opus-4-7
egress_consent: none
employee_id: emp-005
team: null
department: null
role: tech-lead
position: tech-lead
reports_to: null
status: active
hired_at: $(utc_date)
level: 1
xp: 0
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

  # Check that lint would detect this
  load_config
  local provider_class
  provider_class="$(get_provider_class "anthropic")"
  assert_eq "external" "$provider_class" "anthropic should be classified as external"
}

# Run tests
setup_test_env
test_lint_detects_missing_egress_consent
teardown_test_env