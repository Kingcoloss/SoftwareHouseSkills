#!/usr/bin/env bash
# test-shared.sh -- tests for _shared.sh library functions
# TODO: Full coverage -- currently covers golden path only.

test_validate_name_accepts_valid() {
  validate_name "alice" && assert_eq "0" "0" "alice should be valid"
  validate_name "bob-123" && assert_eq "0" "0" "bob-123 should be valid"
  validate_name "a" && assert_eq "0" "0" "single char should be valid"
}

test_validate_name_rejects_invalid() {
  if validate_name "Alice" 2>/dev/null; then
    assert_eq "1" "0" "capitalized name should be rejected"
  else
    assert_eq "1" "1" "capitalized name should be rejected"
  fi

  if validate_name "123abc" 2>/dev/null; then
    assert_eq "1" "0" "name starting with digit should be rejected"
  else
    assert_eq "1" "1" "name starting with digit should be rejected"
  fi

  if validate_name "has space" 2>/dev/null; then
    assert_eq "1" "0" "name with space should be rejected"
  else
    assert_eq "1" "1" "name with space should be rejected"
  fi
}

test_utc_now_format() {
  local ts
  ts="$(utc_now)"
  # Should match YYYY-MM-DDTHH:MM:SSZ
  if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    assert_eq "1" "1" "UTC timestamp format is correct"
  else
    assert_eq "expected-ISO-format" "$ts" "UTC timestamp format"
  fi
}

test_next_employee_id() {
  init_test_company
  local emp_id
  emp_id="$(next_employee_id)"
  assert_eq "emp-001" "$emp_id" "first employee ID should be emp-001"
}

test_json_str_escapes_quotes() {
  local result
  result="$(json_str 'hello "world"')"
  assert_eq '"hello \"world\""' "$result" "json_str should escape double quotes"
}

# Run tests
test_validate_name_accepts_valid
test_validate_name_rejects_invalid
test_utc_now_format

setup_test_env
test_next_employee_id
teardown_test_env

test_json_str_escapes_quotes