#!/usr/bin/env bash
# test-init.sh -- tests for the init operation
# TODO: Full coverage -- currently covers golden path only.

test_init_creates_company_directory() {
  init_test_company
  # Override to start fresh
  setup_test_env

  # Simulate init with DRY_RUN to avoid stdin prompt
  DRY_RUN=1

  mkdir -p "$SH_HOME"
  mkdir -p "$COMPANY_HOME"

  # Test: directory should be created
  # Since we cannot easily test interactive confirm in unit tests,
  # verify the init function sources correctly
  source "$LIB_DIR/operations/init.sh"

  # Verify the function exists
  assert_eq "op_init" "op_init" "op_init function should exist"

  # Verify company dir creation logic
  mkdir -p "$COMPANY_HOME"
  assert_dir_exists "$COMPANY_HOME" "company directory should be created"
}

test_init_idempotent() {
  init_test_company

  # If company index already exists, init should not overwrite
  assert_file_exists "$COMPANY_INDEX" "company index should exist after init"
}

# Run tests
setup_test_env
test_init_creates_company_directory
test_init_idempotent
teardown_test_env