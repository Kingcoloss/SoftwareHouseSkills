#!/usr/bin/env bash
# lint.sh -- check the company state for structural problems
# Spec: operations/lint.md | Tier 1 (read-only)

op_lint() {
  local scope=""
  local fix_suggestions=0

  while (( $# > 0 )); do
    case "$1" in
      --fix-suggestions) fix_suggestions=1; shift ;;
      --help|-h)
        printf 'Usage: lint [company|dept <name>|team <name>] [--fix-suggestions]\n'
        return 0
        ;;
      company|dept|team)
        scope="$1"; shift
        ;;
      *)
        shift ;;
    esac
  done

  require_company_init || return 1

  local error_count=0
  local warning_count=0
  local info_count=0

  printf '# Lint Report\n\n'

  # Check 1: Orphaned agents
  printf '## Orphan Checks\n\n'
  if [[ -d "$WIKI_PEOPLE" ]]; then
    for f in "$WIKI_PEOPLE"/*.md; do
      [[ -f "$f" ]] || continue
      local p_name
      p_name="$(basename "$f" .md)"
      if [[ ! -f "$AGENTS_GLOBAL/${p_name}.md" ]]; then
        # Check team agents too (TODO: project context resolution)
        printf '  [WARNING] Wiki page for %s has no matching canonical agent file.\n' "$p_name"
        warning_count=$(( warning_count + 1 ))
      fi
    done
  fi

  # Check 2: Reference integrity
  printf '\n## Reference Integrity\n\n'
  if [[ -d "$WIKI_PEOPLE" ]]; then
    for f in "$WIKI_PEOPLE"/*.md; do
      [[ -f "$f" ]] || continue
      read_agent "$f"

      # Check reports_to
      if [[ -n "$AGENT_REPORTS_TO" ]] && [[ "$AGENT_REPORTS_TO" != "null" ]]; then
        if [[ ! -f "$WIKI_PEOPLE/${AGENT_REPORTS_TO}.md" ]] && [[ ! -f "$ALUMNI/${AGENT_REPORTS_TO}.md" ]]; then
          printf '  [ERROR] %s reports_to %s -- person not found.\n' "$AGENT_NAME" "$AGENT_REPORTS_TO"
          error_count=$(( error_count + 1 ))
        elif [[ -f "$ALUMNI/${AGENT_REPORTS_TO}.md" ]]; then
          printf '  [WARNING] %s reports_to %s -- person is alumni.\n' "$AGENT_NAME" "$AGENT_REPORTS_TO"
          warning_count=$(( warning_count + 1 ))
        fi
      fi

      # Check team reference
      if [[ -n "$AGENT_TEAM" ]] && [[ "$AGENT_TEAM" != "null" ]]; then
        if [[ ! -f "$WIKI_TEAMS/${AGENT_TEAM}.md" ]]; then
          printf '  [ERROR] %s team=%s -- team not found.\n' "$AGENT_NAME" "$AGENT_TEAM"
          error_count=$(( error_count + 1 ))
        fi
      fi

      # Check department reference
      if [[ -n "$AGENT_DEPARTMENT" ]] && [[ "$AGENT_DEPARTMENT" != "null" ]]; then
        if [[ ! -d "$DEPARTMENTS_HOME/$AGENT_DEPARTMENT" ]]; then
          printf '  [ERROR] %s department=%s -- department not found.\n' "$AGENT_NAME" "$AGENT_DEPARTMENT"
          error_count=$(( error_count + 1 ))
        fi
      fi

      # Check egress consent for external providers
      local provider_class
      provider_class="$(get_provider_class "$AGENT_PROVIDER" 2>/dev/null || echo "unknown")"
      if [[ "$provider_class" == "external" ]] && [[ "$AGENT_EGRESS_CONSENT" == "none" ]]; then
        printf '  [ERROR] %s uses external provider %s without egress consent.\n' "$AGENT_NAME" "$AGENT_PROVIDER"
        error_count=$(( error_count + 1 ))
      fi
    done
  fi

  # Check 3: Required fields
  printf '\n## Required Field Checks\n\n'
  if [[ -d "$AGENTS_GLOBAL" ]]; then
    for f in "$AGENTS_GLOBAL"/*.md; do
      [[ -f "$f" ]] || continue
      local missing_fields=()
      for field in name provider model role status hired_at level xp employment; do
        if ! grep -q "^${field}:" "$f"; then
          missing_fields+=("$field")
        fi
      done
      if (( ${#missing_fields[@]} > 0 )); then
        printf '  [ERROR] %s missing required fields: %s\n' "$(basename "$f" .md)" "${missing_fields[*]}"
        error_count=$(( error_count + 1 ))
      fi
    done
  fi

  # Summary
  printf '\n## Summary\n\n'
  printf '  Errors:   %s\n' "$error_count"
  printf '  Warnings: %s\n' "$warning_count"
  printf '  Info:     %s\n' "$info_count"

  if (( fix_suggestions )) && (( error_count + warning_count > 0 )); then
    printf '\n## Fix Suggestions\n\n'
    printf '  Run /software-house set-model <name> to fix egress consent issues.\n'
    printf '  Run /software-house dept-assign <name> <dept> to fix department references.\n'
  fi

  # Exit with error code if errors found
  if (( error_count > 0 )); then
    return 1
  fi
  return 0
}