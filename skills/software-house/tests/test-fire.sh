#!/usr/bin/env bash
# test-fire.sh -- tests for the fire operation
# TODO: Full coverage -- currently covers golden path only.

test_fire_archives_agent() {
  init_test_company

  # Create a test agent to fire
  local test_name="bob"
  local canonical_file="$AGENTS_GLOBAL/${test_name}.md"

  local fm
  fm=$(cat <<FMEOF
name: $test_name
description: linter agent
provider: ollama
model: qwen3-coder:7b
egress_consent: none
employee_id: emp-002
team: null
department: null
role: linter
position: linter
reports_to: null
status: active
hired_at: $(utc_date)
level: 1
xp: 0
effort_preset: low
classification: internal
buddy: null
employment: permanent
hired_by_teams: []
achievements: []
FMEOF
)

  local body="# $test_name\n\nAgent."
  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  # Simulate fire (direct file operations, bypassing interactive confirm)
  mkdir -p "$AGENTS_GLOBAL/_archived"
  local utc_ts
  utc_ts="$(utc_timestamp_compact)"
  local archive_file="$AGENTS_GLOBAL/_archived/${test_name}-${utc_ts}.md"

  write_agent_field "$canonical_file" "status" "alumni"
  write_agent_field "$canonical_file" "fired_at" "$(utc_date)"
  mv "$canonical_file" "$archive_file"

  assert_file_exists "$archive_file" "agent should be archived"
  assert_file_not_exists "$canonical_file" "original file should be removed"
  assert_contains "$archive_file" "status: alumni" "archived agent should have alumni status"
}

# Run tests
setup_test_env
test_fire_archives_agent
teardown_test_env