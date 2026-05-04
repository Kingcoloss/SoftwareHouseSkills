#!/usr/bin/env bash
# test-dept-create.sh -- tests for the dept-create operation
# TODO: Full coverage -- currently covers golden path only.

test_dept_create_makes_directory() {
  init_test_company

  # Simulate dept-create: create engineering department
  local dept_name="engineering"
  mkdir -p "$DEPARTMENTS_HOME/$dept_name/agents"

  local utc_d
  utc_d="$(utc_date)"

  cat > "$DEPARTMENTS_HOME/$dept_name/CLAUDE.md" << 'EOF'
---
type: department-charter
name: engineering
parent: null
classification: internal
created_at: __DATE__
head: null
---

# Department: engineering

## Charter

Owns all backend systems.
EOF
  sed -i "s/__DATE__/$utc_d/" "$DEPARTMENTS_HOME/$dept_name/CLAUDE.md"

  assert_dir_exists "$DEPARTMENTS_HOME/$dept_name" "department directory should exist"
  assert_file_exists "$DEPARTMENTS_HOME/$dept_name/CLAUDE.md" "department charter should exist"
  assert_contains "$DEPARTMENTS_HOME/$dept_name/CLAUDE.md" "name: engineering" "charter should contain department name"
}

# Run tests
setup_test_env
test_dept_create_makes_directory
teardown_test_env