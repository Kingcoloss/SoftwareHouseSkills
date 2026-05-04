#!/usr/bin/env bash
# list.sh -- list people, teams, departments, or the freelance pool
# Spec: operations/list.md | Tier 1 (read-only)

op_list() {
  local entity=""
  local alumni=0

  while (( $# > 0 )); do
    case "$1" in
      --alumni) alumni=1; shift ;;
      --help|-h)
        printf 'Usage: list [people|teams|departments|pool] [--alumni]\n'
        return 0
        ;;
      *)
        if [[ -z "$entity" ]]; then entity="$1"; shift; else shift; fi ;;
    esac
  done

  require_company_init || return 1

  # Default to showing everything
  if [[ -z "$entity" ]]; then
    list_people
    list_teams
    list_departments
    list_pool
    return 0
  fi

  case "$entity" in
    people)       list_people ;;
    teams)        list_teams ;;
    departments)  list_departments ;;
    pool)         list_pool ;;
    alumni)       list_alumni ;;
    *)
      printf 'Error: unknown entity "%s". Use: people, teams, departments, pool, alumni.\n' "$entity"
      return 1
      ;;
  esac
}

list_people() {
  printf '## People\n\n'
  if [[ ! -d "$WIKI_PEOPLE" ]] || [[ -z "$(ls -A "$WIKI_PEOPLE" 2>/dev/null)" ]]; then
    printf '(none yet -- run /software-house hire to add employees)\n\n'
    return 0
  fi

  printf '| Name | Role | Provider | Level | Status |\n'
  printf '|---|---|---|---|---|\n'
  for f in "$WIKI_PEOPLE"/*.md; do
    [[ -f "$f" ]] || continue
    read_agent "$f"
    [[ "$AGENT_STATUS" == "alumni" ]] && continue
    printf '| %s | %s | %s | %s | %s |\n' "$AGENT_NAME" "$AGENT_ROLE" "$AGENT_PROVIDER" "$AGENT_LEVEL" "$AGENT_STATUS"
  done
  printf '\n'
}

list_teams() {
  printf '## Teams\n\n'
  if [[ ! -d "$WIKI_TEAMS" ]] || [[ -z "$(ls -A "$WIKI_TEAMS" 2>/dev/null)" ]]; then
    printf '(none yet)\n\n'
    return 0
  fi

  printf '| Name | Department | Lead | Members | Status |\n'
  printf '|---|---|---|---|---|\n'
  for f in "$WIKI_TEAMS"/*.md; do
    [[ -f "$f" ]] || continue
    read_agent "$f"
    # TODO: Proper team frontmatter parsing (different from agent)
    local t_name t_dept t_lead t_status
    t_name="$(grep '^name:' "$f" | head -1 | sed 's/^name:[[:space:]]*//')"
    t_dept="$(grep '^department:' "$f" | head -1 | sed 's/^department:[[:space:]]*//')"
    t_lead="$(grep '^lead:' "$f" | head -1 | sed 's/^lead:[[:space:]]*//')"
    t_status="$(grep '^status:' "$f" | head -1 | sed 's/^status:[[:space:]]*//')"
    [[ -z "$t_status" ]] && t_status="active"
    printf '| %s | %s | %s | - | %s |\n' "${t_name:-(unknown)}" "${t_dept:--}" "${t_lead:--}" "$t_status"
  done
  printf '\n'
}

list_departments() {
  printf '## Departments\n\n'
  if [[ ! -d "$WIKI_DEPTS" ]] || [[ -z "$(ls -A "$WIKI_DEPTS" 2>/dev/null)" ]]; then
    printf '(none yet -- run /software-house dept-create to add departments)\n\n'
    return 0
  fi

  printf '| Name | Parent | Status |\n'
  printf '|---|---|---|\n'
  for f in "$WIKI_DEPTS"/*.md; do
    [[ -f "$f" ]] || continue
    local d_name d_parent d_status
    d_name="$(grep '^name:' "$f" | head -1 | sed 's/^name:[[:space:]]*//')"
    d_parent="$(grep '^parent:' "$f" | head -1 | sed 's/^parent:[[:space:]]*//')"
    d_status="$(grep '^status:' "$f" | head -1 | sed 's/^status:[[:space:]]*//')"
    [[ -z "$d_status" ]] && d_status="active"
    printf '| %s | %s | %s |\n' "${d_name:-(unknown)}" "${d_parent:--}" "$d_status"
  done
  printf '\n'
}

list_pool() {
  printf '## Freelance Pool\n\n'
  if [[ ! -d "$AGENTS_GLOBAL" ]] || [[ -z "$(ls -A "$AGENTS_GLOBAL"/*.md 2>/dev/null)" ]]; then
    printf '(none yet -- run /software-house outsource-hire to add freelance agents)\n\n'
    return 0
  fi

  printf '| Name | Role | Provider | Level | Contract |\n'
  printf '|---|---|---|---|---|\n'
  for f in "$AGENTS_GLOBAL"/*.md; do
    [[ -f "$f" ]] || continue
    read_agent "$f"
    [[ "$AGENT_STATUS" == "alumni" ]] && continue
    printf '| %s | %s | %s | %s | %s |\n' "$AGENT_NAME" "$AGENT_ROLE" "$AGENT_PROVIDER" "$AGENT_LEVEL" "${AGENT_CONTRACT_TYPE:--}"
  done
  printf '\n'
}

list_alumni() {
  printf '## Alumni\n\n'
  if [[ ! -d "$ALUMNI" ]] || [[ -z "$(ls -A "$ALUMNI"/*.md 2>/dev/null)" ]]; then
    printf '(none)\n\n'
    return 0
  fi

  printf '| Name | Role | Fired At |\n'
  printf '|---|---|---|\n'
  for f in "$ALUMNI"/*.md; do
    [[ -f "$f" ]] || continue
    local a_name a_role a_fired
    a_name="$(grep '^name:' "$f" | head -1 | sed 's/^name:[[:space:]]*//')"
    a_role="$(grep '^role:' "$f" | head -1 | sed 's/^role:[[:space:]]*//')"
    a_fired="$(grep '^fired_at:' "$f" | head -1 | sed 's/^fired_at:[[:space:]]*//')"
    printf '| %s | %s | %s |\n' "${a_name:-(unknown)}" "${a_role:--}" "${a_fired:--}"
  done
  printf '\n'
}