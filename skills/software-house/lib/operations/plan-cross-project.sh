#!/usr/bin/env bash

# op_plan_cross_project "<goal>" [--team <team>]
op_plan_cross_project() {
  require_company_init
  source "$LIB_DIR/providers/_shared.sh"

  if (( $# < 1 )); then
    log_error "Usage: software-house plan cross-project \"<goal>\" [--team <team>]"
    return 1
  fi

  local goal="$1"
  shift

  local target_team=""
  
  while (( $# > 0 )); do
    case "$1" in
      --team|-t)
        target_team="$2"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  # Default to current project's team if not specified
  if [[ -z "$target_team" ]]; then
    if [[ -n "${PROJECT:-}" && -f "$TEAM_DIR/index.md" ]]; then
      target_team="$(fm_field "$TEAM_DIR/index.md" "name")"
    else
      log_error "No team specified and not inside a valid project. Use --team <name>"
      return 1
    fi
  fi

  # Identify tech-lead or system-architect for the team
  local lead_agent=""
  # First search global wiki
  for role in "system-architect" "tech-lead"; do
    local candidate
    candidate=$(grep -l "^role: $role" "$WIKI_PEOPLE"/*.md 2>/dev/null | xargs grep -l "^team: $target_team" 2>/dev/null | head -1)
    if [[ -n "$candidate" ]]; then
      lead_agent="$(basename "$candidate" .md)"
      break
    fi
  done

  # If not found, search via PROJECTS_INDEX in team-local wikis
  if [[ -z "$lead_agent" ]] && [[ -f "$PROJECTS_INDEX" ]]; then
    jq -r 'if .projects then .projects | to_entries[] | .key else empty end' "$PROJECTS_INDEX" 2>/dev/null | while read -r project_path; do
      for role in "system-architect" "tech-lead"; do
        local candidate
        candidate=$(grep -l "^role: $role" "$project_path/.software-house/team/wiki/people"/*.md 2>/dev/null | xargs grep -l "^team: $target_team" 2>/dev/null | head -1)
        if [[ -n "$candidate" ]]; then
          echo "$(basename "$candidate" .md)"
          return 0
        fi
      done
    done | read -r lead_agent
  fi

  if [[ -z "$lead_agent" ]]; then
    log_error "Could not find a system-architect or tech-lead for team '$target_team'."
    return 1
  fi

  log_info "Gathering cross-project context for agent $lead_agent..."

  local temp_ctx
  temp_ctx="$(mktemp)"
  
  printf "## Cross-Project Context\n\n" > "$temp_ctx"
  printf "Goal: %s\n\n" "$goal" >> "$temp_ctx"

  if [[ -f "$PROJECTS_INDEX" ]] && command -v jq &>/dev/null; then
    jq -r 'if .projects then .projects | to_entries[] | .key else empty end' "$PROJECTS_INDEX" 2>/dev/null | while read -r project_path; do
      [[ -d "$project_path/.software-house/team" ]] || continue

      local pteam=""
      if [[ -f "$project_path/.software-house/team/index.md" ]]; then
        pteam="$(fm_field "$project_path/.software-house/team/index.md" "name" 2>/dev/null)"
      fi
      [[ -z "$pteam" ]] && pteam="$(basename "$project_path")"
      
      printf "### Project/Team: %s\n\n" "$pteam" >> "$temp_ctx"

      # Read architecture decisions
      if [[ -d "$project_path/.software-house/team/wiki/decisions" ]]; then
        printf "#### Architecture Decisions\n\n" >> "$temp_ctx"
        for doc in "$project_path/.software-house/team/wiki/decisions"/*.md; do
          if [[ -f "$doc" ]]; then
            printf "##### %s\n\n" "$(basename "$doc")" >> "$temp_ctx"
            cat "$doc" >> "$temp_ctx"
            printf "\n\n" >> "$temp_ctx"
          fi
        done
      fi

      # Read synthesis (status)
      if [[ -d "$project_path/.software-house/team/wiki/synthesis" ]]; then
        printf "#### Project Status & Synthesis\n\n" >> "$temp_ctx"
        for doc in "$project_path/.software-house/team/wiki/synthesis"/*.md; do
          if [[ -f "$doc" ]]; then
            printf "##### %s\n\n" "$(basename "$doc")" >> "$temp_ctx"
            cat "$doc" >> "$temp_ctx"
            printf "\n\n" >> "$temp_ctx"
          fi
        done
      fi
    done
  fi

  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  local brief_id="cross-project-${ts}"
  
  # Ensure target inbox exists (default to current project or company)
  local target_inbox="$WIKI_HANDOFF_INBOX"
  if [[ -n "${PROJECT:-}" && -d "$TEAM_WIKI_HANDOFF_INBOX" ]]; then
    target_inbox="$TEAM_WIKI_HANDOFF_INBOX"
  fi
  mkdir -p "$target_inbox"
  
  local brief_file="$target_inbox/${brief_id}.md"

  log_info "Optimizing aggregated cross-project context (Summary Mode)..."
  local optimized_ctx
  optimized_ctx="$(optimize_text "$(cat "$temp_ctx")")"
  
  local optimized_goal
  optimized_goal="$(optimize_text "$goal")"

  cat > "$brief_file" << BRIEF_EOF
---
from: ceo
to: ${lead_agent}
task: "${optimized_goal}"
priority: high
context_pages: []
created_at: $(date -u +"%Y-%m-%d")
status: pending
completed_at: null
deliverables: [cross-project-plan]
dependencies: []
brief_id: ${brief_id}
---

## Cross-Project Analysis Request

${optimized_goal}

## Aggregated Context

${optimized_ctx}
BRIEF_EOF

  rm -f "$temp_ctx"

  log_info "Cross-project analysis brief delivered to ${lead_agent}'s inbox: $brief_file"
  
  audit_log '{"timestamp": "'"${ts}"'", "action": "plan-cross-project", "goal": "'"${goal}"'", "lead_agent": "'"${lead_agent}"'"}'

  return 0
}