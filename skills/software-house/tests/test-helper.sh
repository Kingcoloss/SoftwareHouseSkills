#!/usr/bin/env bash
# test-helper.sh -- common test setup/teardown for software-house tests
# Creates a temporary ~/.software-house/ for isolated testing.

# Resolve paths
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$(cd "$TEST_HELPER_DIR/.." && pwd)"
LIB_DIR="$SKILL_SRC/lib"
BIN_DIR="$SKILL_SRC/bin"

source "$LIB_DIR/_shared.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()

# Create temporary SH_HOME for testing
setup_test_env() {
  TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sh-test.XXXXXX")"
  # Override path constants
  SH_HOME="$TEST_TMPDIR/.software-house"
  COMPANY_HOME="$SH_HOME/company"
  DEPARTMENTS_HOME="$SH_HOME/departments"
  AGENTS_GLOBAL="$SH_HOME/agents"
  AUDIT_LOG="$COMPANY_HOME/audit.log"
  COMPANY_INDEX="$COMPANY_HOME/index.md"
  WIKI_PEOPLE="$COMPANY_HOME/wiki/people"
  WIKI_TEAMS="$COMPANY_HOME/wiki/teams"
  WIKI_DEPTS="$COMPANY_HOME/wiki/departments"
  ALUMNI="$COMPANY_HOME/alumni"
  OUTSOURCE_MANIFEST="$COMPANY_HOME/outsource/manifest.json"
  PROJECTS_INDEX="$SH_HOME/projects-index.json"
  CONFIG_HOME="$SH_HOME/config"
  PROVIDERS_CONFIG="$CONFIG_HOME/providers.json"
  MODELS_CONFIG="$CONFIG_HOME/models-config.json"
}

teardown_test_env() {
  if [[ -n "${TEST_TMPDIR:-}" ]] && [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Initialize a minimal company state for testing
init_test_company() {
  setup_test_env
  mkdir -p "$COMPANY_HOME" "$COMPANY_HOME/wiki/people" "$COMPANY_HOME/wiki/teams" \
           "$COMPANY_HOME/wiki/departments" "$COMPANY_HOME/wiki/synthesis" \
           "$COMPANY_HOME/alumni" "$COMPANY_HOME/outsource" \
           "$DEPARTMENTS_HOME" "$AGENTS_GLOBAL" "$CONFIG_HOME"

  # Create minimal config files
  if [[ -f "$SKILL_SRC/config/providers.json" ]]; then
    cp "$SKILL_SRC/config/providers.json" "$PROVIDERS_CONFIG"
  else
    printf '{"version":1,"providers":{"ollama":{"name":"Ollama","class":"local","default_endpoint":"http://localhost:11434"}},"metadata":{"schema_version":1}}\n' > "$PROVIDERS_CONFIG"
  fi

  if [[ -f "$SKILL_SRC/config/models-config.json" ]]; then
    cp "$SKILL_SRC/config/models-config.json" "$MODELS_CONFIG"
  else
    printf '{"version":1,"defaults_by_role":{"default":{"provider":"ollama","model":"qwen3-coder:32b","effort":"medium"}},"effort_presets":{},"model_aliases":{}}\n' > "$MODELS_CONFIG"
  fi

  # Create index
  printf '# Company Wiki Index\n\n## People\n\n(none)\n\n## Teams\n\n(none)\n\n## Departments\n\n(none)\n' > "$COMPANY_INDEX"
  touch "$AUDIT_LOG"
  printf '{"freelancers":[]}\n' > "$OUTSOURCE_MANIFEST"
  printf '{"projects":{}}\n' > "$PROJECTS_INDEX"
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assertion failed}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: expected '$expected', got '$actual'")
  fi
}

assert_not_eq() {
  local not_expected="$1"
  local actual="$2"
  local msg="${3:-assertion failed}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if [[ "$not_expected" != "$actual" ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: should not equal '$not_expected'")
  fi
}

assert_file_exists() {
  local file="$1"
  local msg="${2:-file should exist}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if [[ -f "$file" ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: file '$file' does not exist")
  fi
}

assert_file_not_exists() {
  local file="$1"
  local msg="${2:-file should not exist}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if [[ ! -f "$file" ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: file '$file' should not exist")
  fi
}

assert_dir_exists() {
  local dir="$1"
  local msg="${2:-directory should exist}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if [[ -d "$dir" ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: directory '$dir' does not exist")
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local msg="${3:-file should contain pattern}"
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  if grep -q "$pattern" "$file" 2>/dev/null; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILURES+=("$msg: file '$file' does not contain '$pattern'")
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-exit code mismatch}"
  assert_eq "$expected" "$actual" "$msg"
}

# ---------------------------------------------------------------------------
# Test runner helpers
# ---------------------------------------------------------------------------

run_test_file() {
  local test_file="$1"
  local test_name
  test_name="$(basename "$test_file" .sh)"
  printf '  Running: %s\n' "$test_name"
  source "$test_file"
}

print_test_summary() {
  printf '\n--- Test Summary ---\n'
  printf '  Total:  %s\n' "$TESTS_RUN"
  printf '  Passed: %s\n' "$TESTS_PASSED"
  printf '  Failed: %s\n' "$TESTS_FAILED"

  if (( ${#FAILURES[@]} > 0 )); then
    printf '\nFailures:\n'
    for failure in "${FAILURES[@]}"; do
      printf '  - %s\n' "$failure"
    done
  fi

  if (( TESTS_FAILED > 0 )); then
    return 1
  fi
  return 0
}