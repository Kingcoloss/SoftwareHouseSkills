#!/usr/bin/env bash
# dashboard.sh -- show gamification stats and skill-tree state
# Spec: operations/dashboard.md | Tier 1 (read-only)

op_dashboard() {
  local team=""
  local dept=""
  local top=10

  while (( $# > 0 )); do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      --dept) dept="$2"; shift 2 ;;
      --top)  top="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: dashboard [--team <t>] [--dept <d>] [--top N]\n'
        return 0
        ;;
      *) shift ;;
    esac
  done

  require_company_init || return 1

  # Clamp top
  (( top > 50 )) && top=50
  (( top < 1 )) && top=1

  # Collect agent data
  local agents=()
  local total_xp=0
  local count=0

  # Read from wiki/people
  if [[ -d "$WIKI_PEOPLE" ]]; then
    for f in "$WIKI_PEOPLE"/*.md; do
      [[ -f "$f" ]] || continue
      read_agent "$f"
      [[ "$AGENT_STATUS" == "alumni" ]] && continue

      # Filter by team/dept if specified
      if [[ -n "$team" ]] && [[ "$AGENT_TEAM" != "$team" ]]; then continue; fi
      if [[ -n "$dept" ]] && [[ "$AGENT_DEPARTMENT" != "$dept" ]]; then continue; fi

      agents+=("$AGENT_NAME|$AGENT_XP|$AGENT_LEVEL|$AGENT_ROLE|$AGENT_STATUS")
      total_xp=$(( total_xp + AGENT_XP ))
      count=$(( count + 1 ))
    done
  fi

  # Read from freelance pool
  if [[ -d "$AGENTS_GLOBAL" ]]; then
    for f in "$AGENTS_GLOBAL"/*.md; do
      [[ -f "$f" ]] || continue
      read_agent "$f"
      [[ "$AGENT_STATUS" == "alumni" ]] && continue

      if [[ -n "$team" ]] || [[ -n "$dept" ]]; then continue; fi

      agents+=("$AGENT_NAME|$AGENT_XP|$AGENT_LEVEL|$AGENT_ROLE|$AGENT_STATUS")
      total_xp=$(( total_xp + AGENT_XP ))
      count=$(( count + 1 ))
    done
  fi

  # Display
  printf '# Software House Dashboard\n\n'

  if (( count == 0 )); then
    printf 'No agents found.\n'
    printf 'Run /software-house hire to add your first agent.\n'
    return 0
  fi

  local avg_xp=0
  if (( count > 0 )); then
    avg_xp=$(( total_xp / count ))
  fi

  printf '## Summary\n\n'
  printf '| Metric | Value |\n'
  printf '|---|---|\n'
  printf '| Total Agents | %s |\n' "$count"
  printf '| Total XP | %s |\n' "$total_xp"
  printf '| Average XP | %s |\n' "$avg_xp"

  # Leaderboard (sort by XP descending)
  printf '\n## Leaderboard (Top %s by XP)\n\n' "$top"
  printf '| Rank | Name | XP | Level | Role | Status |\n'
  printf '|---|---|---|---|---|---|\n'

  local sorted
  sorted="$(printf '%s\n' "${agents[@]}" | sort -t'|' -k2 -rn | head -n "$top")"
  local rank=1
  while IFS='|' read -r a_name a_xp a_level a_role a_status; do
    [[ -z "$a_name" ]] && continue
    printf '| %s | %s | %s | %s | %s | %s |\n' "$rank" "$a_name" "$a_xp" "$a_level" "$a_role" "$a_status"
    rank=$(( rank + 1 ))
  done <<< "$sorted"

  # Level distribution
  printf '\n## Level Distribution\n\n'
  printf '| Level | Count |\n'
  printf '|---|---|\n'
  local level_counts=()
  for lvl in 1 2 3 4 5; do
    local lvl_count=0
    for entry in "${agents[@]}"; do
      local entry_level
      entry_level="$(echo "$entry" | cut -d'|' -f3)"
      [[ "$entry_level" == "$lvl" ]] && lvl_count=$(( lvl_count + 1 ))
    done
    printf '| %s | %s |\n' "$lvl" "$lvl_count"
  done
}