#!/usr/bin/env bash
# show.sh -- display one entity (employee, team, department) in detail
# Spec: operations/show.md | Tier 1 (read-only)

op_show() {
  local name=""
  local entity_type=""

  while (( $# > 0 )); do
    case "$1" in
      --help|-h)
        printf 'Usage: show <name> [people|team|dept]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"; shift
        elif [[ -z "$entity_type" ]]; then
          entity_type="$1"; shift
        else
          shift
        fi ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Error: entity name is required.\n'; return 1
  fi

  require_company_init || return 1

  # Auto-detect entity type if not specified
  if [[ -z "$entity_type" ]]; then
    if [[ -f "$WIKI_PEOPLE/${name}.md" ]] || [[ -f "$AGENTS_GLOBAL/${name}.md" ]]; then
      entity_type="people"
    elif [[ -f "$WIKI_TEAMS/${name}.md" ]]; then
      entity_type="team"
    elif [[ -f "$WIKI_DEPTS/${name}.md" ]]; then
      entity_type="dept"
    else
      printf 'Error: %s not found as person, team, or department.\n' "$name"
      return 1
    fi
  fi

  case "$entity_type" in
    people|person|agent)
      show_person "$name"
      ;;
    team)
      show_team "$name"
      ;;
    dept|department)
      show_dept "$name"
      ;;
    *)
      printf 'Error: unknown entity type "%s". Use: people, team, dept.\n' "$entity_type"
      return 1
      ;;
  esac
}

show_person() {
  local name="$1"
  local file=""

  # Check multiple locations
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    file="$WIKI_PEOPLE/${name}.md"
  elif [[ -f "$AGENTS_GLOBAL/${name}.md" ]]; then
    file="$AGENTS_GLOBAL/${name}.md"
  elif [[ -f "$ALUMNI/${name}.md" ]]; then
    file="$ALUMNI/${name}.md"
  else
    printf 'Error: agent %s not found.\n' "$name"; return 1
  fi

  read_agent "$file"

  printf '# %s\n\n' "$AGENT_NAME"
  printf '| Field | Value |\n'
  printf '|---|---|\n'
  printf '| Name | %s |\n' "$AGENT_NAME"
  printf '| Role | %s |\n' "$AGENT_ROLE"
  printf '| Position | %s |\n' "$AGENT_POSITION"
  printf '| Provider | %s |\n' "$AGENT_PROVIDER"
  printf '| Model | %s |\n' "$AGENT_MODEL"
  printf '| Effort | %s |\n' "$AGENT_EFFORT_PRESET"
  printf '| Egress | %s |\n' "$AGENT_EGRESS_CONSENT"
  printf '| Employee ID | %s |\n' "$AGENT_EMPLOYEE_ID"
  printf '| Team | %s |\n' "$AGENT_TEAM"
  printf '| Department | %s |\n' "$AGENT_DEPARTMENT"
  printf '| Status | %s |\n' "$AGENT_STATUS"
  printf '| Level | %s |\n' "$AGENT_LEVEL"
  printf '| XP | %s |\n' "$AGENT_XP"
  printf '| Hired | %s |\n' "$AGENT_HIRED_AT"
  printf '| Employment | %s |\n' "$AGENT_EMPLOYMENT"
  printf '| Classification | %s |\n' "$AGENT_CLASSIFICATION"
  printf '| Reports To | %s |\n' "$AGENT_REPORTS_TO"
  printf '| Buddy | %s |\n' "$AGENT_BUDDY"
  [[ "$AGENT_ONBOARD_STATUS" != "null" ]] && printf '| Onboarded | %s |\n' "$AGENT_ONBOARD_AT"
  [[ "$AGENT_OFFBOARD_STATUS" != "null" ]] && printf '| Off-boarded | %s |\n' "$AGENT_OFFBOARD_AT"
  printf '| File | %s |\n' "$file"
}

show_team() {
  local name="$1"
  local file="$WIKI_TEAMS/${name}.md"

  if [[ ! -f "$file" ]]; then
    printf 'Error: team %s not found.\n' "$name"; return 1
  fi

  printf '# Team: %s\n\n' "$name"
  cat "$file"
}

show_dept() {
  local name="$1"
  local file="$WIKI_DEPTS/${name}.md"

  if [[ ! -f "$file" ]]; then
    printf 'Error: department %s not found.\n' "$name"; return 1
  fi

  printf '# Department: %s\n\n' "$name"
  cat "$file"
}