#!/usr/bin/env bash
# run-tests.sh -- test runner that sources all test files
# Usage: ./run-tests.sh [test-file-pattern]

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/test-helper.sh"

# Discover test files
local_pattern="${1:-test-*.sh}"

printf '== Software House Test Suite ==\n\n'

for test_file in "$TESTS_DIR"/$local_pattern; do
  [[ -f "$test_file" ]] || continue
  [[ "$(basename "$test_file")" == "test-helper.sh" ]] && continue
  [[ "$(basename "$test_file")" == "run-tests.sh" ]] && continue

  run_test_file "$test_file"
done

print_test_summary
exit $?