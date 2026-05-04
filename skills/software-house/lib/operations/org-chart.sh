#!/usr/bin/env bash
# org-chart.sh -- render an ASCII tree of the company hierarchy
# Spec: operations/org-chart.md | Tier 1 (read-only)

op_org_chart() {
  local team=""

  while (( $# > 0 )); do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: org-chart [--team <t>]\n'
        return 0
        ;;
      *) shift ;;
    esac
  done

  require_company_init || return 1

  printf '# Org Chart\n\n'

  # Company level
  printf 'Company\n'
  printf '|\n'

  # Departments
  if [[ -d "$WIKI_DEPTS" ]]; then
    local depts=()
    for f in "$WIKI_DEPTS"/*.md; do
      [[ -f "$f" ]] || continue
      local d_name
      d_name="$(grep '^name:' "$f" | head -1 | sed 's/^name:[[:space:]]*//')"
      [[ -n "$d_name" ]] && depts+=("$d_name")
    done

    local dept_count=${#depts[@]}
    local i=0
    for d in "${depts[@]}"; do
      i=$(( i + 1 ))
      if (( i == dept_count )); then
        printf '+-- Dept: %s\n' "$d"
        printf '|   |\n'
      else
        printf '+-- Dept: %s\n' "$d"
        printf '|   |\n'
      fi

      # Teams under this department
      local teams=()
      if [[ -f "$WIKI_DEPTS/${d}.md" ]]; then
        # TODO: Parse teams list from department frontmatter
        :
      fi

      # People in this department
      if [[ -d "$WIKI_PEOPLE" ]]; then
        for p in "$WIKI_PEOPLE"/*.md; do
          [[ -f "$p" ]] || continue
          read_agent "$p"
          [[ "$AGENT_DEPARTMENT" == "$d" ]] || continue
          [[ "$AGENT_STATUS" == "alumni" ]] && continue
          printf '|   +-- %s (%s, Lv.%s)\n' "$AGENT_NAME" "$AGENT_ROLE" "$AGENT_LEVEL"
        done
      fi
    done
  fi

  # Freelance pool
  printf '+-- Freelance Pool\n'
  if [[ -d "$AGENTS_GLOBAL" ]]; then
    for f in "$AGENTS_GLOBAL"/*.md; do
      [[ -f "$f" ]] || continue
      read_agent "$f"
      [[ "$AGENT_STATUS" == "alumni" ]] && continue
      printf '|   +-- %s (%s, Lv.%s)\n' "$AGENT_NAME" "$AGENT_ROLE" "$AGENT_LEVEL"
    done
    if [[ -z "$(ls -A "$AGENTS_GLOBAL"/*.md 2>/dev/null)" ]]; then
      printf '|   (none)\n'
    fi
  else
    printf '|   (none)\n'
  fi
}