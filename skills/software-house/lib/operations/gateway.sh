#!/usr/bin/env bash

# op_gateway <agent_name> --message "..."
op_gateway() {
  require_company_init
  source "$LIB_DIR/providers/_shared.sh"

  if (( $# < 1 )); then
    log_error "Usage: software-house gateway <agent_name> --message <text>"
    return 1
  fi

  local target_agent="$1"
  shift

  local message=""
  local context_pages=()

  while (( $# > 0 )); do
    case "$1" in
      --message|-m)
        message="$2"
        shift 2
        ;;
      --context|-c)
        context_pages+=("$2")
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ -z "$message" ]]; then
    log_error "Message cannot be empty. Use --message \"<text>\""
    return 1
  fi

  local agent_file
  if ! agent_file="$(find_agent_file "$target_agent")"; then
    log_error "Agent '$target_agent' not found."
    return 1
  fi

  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  local now
  now=$(date -u +"%Y-%m-%d")

  local agent_team
  agent_team="$(fm_field "$agent_file" "team")"

  # Resolve project directory to find the target inbox
  local target_inbox="$WIKI_HANDOFF_INBOX"
  if [[ -f "$PROJECTS_INDEX" ]] && command -v jq &>/dev/null; then
    local project_path
    project_path=$(jq -r --arg t "$agent_team" 'if .projects then .projects | to_entries[] | select(.value.team == $t or (.key | test(".*" + $t + ".*"))) | .key else empty end' "$PROJECTS_INDEX" 2>/dev/null | head -1)
    if [[ -n "$project_path" ]] && [[ -d "$project_path/.software-house/team/wiki/handoffs/inbox" ]]; then
      target_inbox="$project_path/.software-house/team/wiki/handoffs/inbox"
    fi
  fi

  mkdir -p "$target_inbox"

  local bid="ceo-${target_agent}-${ts}"
  local brief_file="$target_inbox/${bid}.md"

  log_info "Optimizing CEO message for $target_agent..."
  local optimized_message
  optimized_message="$(optimize_text "$message")"

  cat > "$brief_file" << BRIEF_EOF
---
from: ceo
to: ${target_agent}
task: "${optimized_message}"
priority: high
context_pages: [$(printf '%s' "${context_pages[*]:-}" | sed 's/ /, /g')]
created_at: ${now}
status: pending
completed_at: null
deliverables: []
dependencies: []
brief_id: ${bid}
---

## Direct Message from CEO

${optimized_message}

## Context

Trigger: gateway

This brief was generated directly by the CEO. Address the request accordingly.
BRIEF_EOF

  log_info "Message successfully delivered to ${target_agent}'s inbox: $brief_file"

  audit_log '{"timestamp": "'"${ts}"'", "action": "gateway", "from": "ceo", "to": "'"${target_agent}"'", "brief_id": "'"${bid}"'"}'

  return 0
}