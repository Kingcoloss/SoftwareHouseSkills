#!/usr/bin/env bash
# handoff.sh -- CLI implementation of the handoff operation
# See operations/handoff.md for the full specification.

source "$LIB_DIR/_shared.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BRIEF_TS_FORMAT="%Y%m%d%H%M%S"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Ensure handoff directories exist
ensure_handoff_dirs() {
  local base="${1:-$WIKI_HANDOFFS}"
  mkdir -p "$base/inbox" "$base/completed" "$base/briefs" 2>/dev/null
}

# Find brief file by ID across company and team levels
# Prints the file path if found, empty string otherwise.
find_brief() {
  local brief_id="$1"
  local found=""

  # Check company level
  if [ -f "$WIKI_HANDOFF_BRIEFS/${brief_id}.md" ]; then
    found="$WIKI_HANDOFF_BRIEFS/${brief_id}.md"
  fi

  # Check team level
  if [ -z "$found" ] && [ -n "${PROJECT:-}" ] && [ -f "$TEAM_WIKI_HANDOFF_BRIEFS/${brief_id}.md" ]; then
    found="$TEAM_WIKI_HANDOFF_BRIEFS/${brief_id}.md"
  fi

  printf '%s' "$found"
}

# Read a frontmatter field from a file
# Usage: fm_field <file> <field>
fm_field() {
  local file="$1"
  local field="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

# Generate a brief ID
brief_id() {
  local from="$1"
  local to="$2"
  local ts
  ts=$(date -u +"$BRIEF_TS_FORMAT" 2>/dev/null || date +"$BRIEF_TS_FORMAT")
  printf '%s-%s-%s' "$from" "$to" "$ts"
}

# ---------------------------------------------------------------------------
# handoff list
# ---------------------------------------------------------------------------
op_handoff_list() {
  local team_filter=""
  local status_filter=""
  local from_filter=""
  local to_filter=""

  while (( $# > 0 )); do
    case "$1" in
      --team)      team_filter="$2"; shift 2 ;;
      --status)    status_filter="$2"; shift 2 ;;
      --from)      from_filter="$2"; shift 2 ;;
      --to)        to_filter="$2"; shift 2 ;;
      *)           shift ;;
    esac
  done

  # Determine which directories to search
  local search_dirs=()
  if [ -n "$team_filter" ]; then
    local project_path
    project_path=$(jq -r --arg t "$team_filter" 'if .projects then .projects | to_entries[] | select(.value.team == $t or .key | test(".*" + $t + ".*")) | .key else empty end' "$PROJECTS_INDEX" 2>/dev/null | head -1)
    if [ -n "$project_path" ] && [ -d "$project_path/.software-house/team/wiki/handoffs/briefs" ]; then
      search_dirs+=("$project_path/.software-house/team/wiki/handoffs/briefs")
    fi
  else
    # Search both company and all team levels
    if [ -d "$WIKI_HANDOFF_BRIEFS" ]; then
      search_dirs+=("$WIKI_HANDOFF_BRIEFS")
    fi
    if [ -f "$PROJECTS_INDEX" ] && command -v jq >/dev/null 2>&1; then
      jq -r 'if .projects then .projects | to_entries[] | .key else empty end' "$PROJECTS_INDEX" 2>/dev/null | while read -r pp; do
        local tb="$pp/.software-house/team/wiki/handoffs/briefs"
        if [ -d "$tb" ]; then
          search_dirs+=("$tb")
        fi
      done
    fi
  fi

  # Collect briefs
  local found=0
  printf '%-40s %-12s %-12s %-8s %-10s %-20s\n' "BRIEF_ID" "FROM" "TO" "PRIORITY" "STATUS" "CREATED_AT"
  printf '%.0s' {1..102} | tr '\0' '-' ; printf '\n'

  for dir in "${search_dirs[@]}"; do
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      local bid from to pri stat created
      bid=$(fm_field "$f" "brief_id")
      from=$(fm_field "$f" "from")
      to=$(fm_field "$f" "to")
      pri=$(fm_field "$f" "priority")
      stat=$(fm_field "$f" "status")
      created=$(fm_field "$f" "created_at")

      # Apply filters
      [ -n "$status_filter" ] && [ "$stat" != "$status_filter" ] && continue
      [ -n "$from_filter" ] && [ "$from" != "$from_filter" ] && continue
      [ -n "$to_filter" ] && [ "$to" != "$to_filter" ] && continue

      printf '%-40s %-12s %-12s %-8s %-10s %-20s\n' "${bid:-$(basename "$f" .md)}" "$from" "$to" "$pri" "$stat" "$created"
      found=$((found + 1))
    done
  done

  if [ "$found" -eq 0 ]; then
    printf '(no briefs found)\n'
  fi

  # Audit
  audit_log "handoff-list" "{\"filters\":{\"team\":\"${team_filter:-}\",\"status\":\"${status_filter:-}\",\"from\":\"${from_filter:-}\",\"to\":\"${to_filter:-}\"}}"
}

# ---------------------------------------------------------------------------
# handoff show
# ---------------------------------------------------------------------------
op_handoff_show() {
  local brief_id="${1:-}"
  if [ -z "$brief_id" ]; then
    log_error "Usage: handoff show <brief-id>"
    return 1
  fi

  local brief_file
  brief_file=$(find_brief "$brief_id")
  if [ -z "$brief_file" ]; then
    # Try without timestamp suffix
    for dir in "$WIKI_HANDOFF_BRIEFS" "$TEAM_WIKI_HANDOFF_BRIEFS"; do
      for f in "$dir/${brief_id}"*.md; do
        if [ -f "$f" ]; then
          brief_file="$f"
          break 2
        fi
      done
    done
  fi

  if [ -z "$brief_file" ] || [ ! -f "$brief_file" ]; then
    log_error "Brief '$brief_id' not found."
    return 1
  fi

  # Print frontmatter
  printf '=== Handoff Brief: %s ===\n\n' "$(basename "$brief_file" .md)"
  sed -n '/^---$/,/^---$/p' "$brief_file" | grep -v '^---$'
  printf '\n'

  # Print body (everything after second ---)
  awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$brief_file"

  # Audit
  audit_log "handoff-show" "{\"brief_id\":\"$brief_id\"}"
}

# ---------------------------------------------------------------------------
# handoff complete
# ---------------------------------------------------------------------------
op_handoff_complete() {
  local brief_id=""
  local summary=""

  while (( $# > 0 )); do
    case "$1" in
      --summary) summary="$2"; shift 2 ;;
      *)         brief_id="$1"; shift ;;
    esac
  done

  if [ -z "$brief_id" ]; then
    log_error "Usage: handoff complete <brief-id> [--summary \"<text>\"]"
    return 1
  fi

  local brief_file
  brief_file=$(find_brief "$brief_id")
  if [ -z "$brief_file" ]; then
    for dir in "$WIKI_HANDOFF_BRIEFS" "$TEAM_WIKI_HANDOFF_BRIEFS"; do
      for f in "$dir/${brief_id}"*.md; do
        if [ -f "$f" ]; then
          brief_file="$f"
          break 2
        fi
      done
    done
  fi

  if [ -z "$brief_file" ] || [ ! -f "$brief_file" ]; then
    log_error "Brief '$brief_id' not found."
    return 1
  fi

  local cur_status
  cur_status=$(fm_field "$brief_file" "status")
  if [ "$cur_status" = "done" ]; then
    log_error "Brief '$brief_id' is already completed."
    return 1
  fi

  local from to
  from=$(fm_field "$brief_file" "from")
  to=$(fm_field "$brief_file" "to")

  # Update frontmatter
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  local tmp_file="${brief_file}.hctmp"

  awk -v status="done" -v completed_at="$now" '
    BEGIN { in_fm=0; fm_count=0 }
    /^---$/ { fm_count++; in_fm=(fm_count==1); next }
    in_fm {
      if ($1 == "status:") { print "status: " status; next }
      if ($1 == "completed_at:") { print "completed_at: \"" completed_at "\""; next }
    }
    { print }
  ' "$brief_file" > "$tmp_file" && mv "$tmp_file" "$brief_file"

  # Append summary if provided
  if [ -n "$summary" ]; then
    printf '\n## Completion Summary\n\n%s\n' "$summary" >> "$brief_file"
  fi

  # Update receiving agent's wiki page
  local task_desc
  task_desc=$(fm_field "$brief_file" "task")
  local today
  today=$(date -u +"%Y-%m-%d" 2>/dev/null || date +"%Y-%m-%d")

  # Try to find the receiving agent's wiki page
  local wiki_page=""
  if [ -f "$WIKI_PEOPLE/${to}.md" ]; then
    wiki_page="$WIKI_PEOPLE/${to}.md"
  elif [ -f "$TEAM_WIKI_PEOPLE/${to}.md" ]; then
    wiki_page="$TEAM_WIKI_PEOPLE/${to}.md"
  fi

  if [ -n "$wiki_page" ] && [ -f "$wiki_page" ]; then
    # Append handoff history entry
    printf -- '\n- %s: Completed brief from %s about %s -> [%s]\n' "$today" "$from" "${task_desc:0:60}" "$brief_id" >> "$wiki_page"
  fi

  # Also update the sending agent's wiki page
  local from_wiki=""
  if [ -f "$WIKI_PEOPLE/${from}.md" ]; then
    from_wiki="$WIKI_PEOPLE/${from}.md"
  elif [ -f "$TEAM_WIKI_PEOPLE/${from}.md" ]; then
    from_wiki="$TEAM_WIKI_PEOPLE/${from}.md"
  fi

  if [ -n "$from_wiki" ] && [ -f "$from_wiki" ]; then
    printf -- '- %s: Sent brief to %s about %s -> [%s]\n' "$today" "$to" "${task_desc:0:60}" "$brief_id" >> "$from_wiki"
  fi

  printf 'Brief %s marked as done.\n' "$brief_id"
  if [ -n "$wiki_page" ]; then
    printf '  Updated wiki page: %s\n' "$wiki_page"
  fi

  # Audit
  audit_log "handoff-complete" "{\"brief_id\":\"$brief_id\",\"from\":\"$from\",\"to\":\"$to\"}"
}

# ---------------------------------------------------------------------------
# handoff generate
# ---------------------------------------------------------------------------
op_handoff_generate() {
  local from_agent=""
  local task=""
  local priority="medium"
  local context_pages=()

  while (( $# > 0 )); do
    case "$1" in
      --priority) priority="$2"; shift 2 ;;
      --context)  context_pages+=("$2"); shift 2 ;;
      *)
        if [ -z "$from_agent" ]; then
          from_agent="$1"
        else
          task="$task $1"
        fi
        shift ;;
    esac
  done

  # Trim leading space from task
  task="${task# }"

  if [ -z "$from_agent" ] || [ -z "$task" ]; then
    log_error "Usage: handoff generate <from-agent> <task> [--priority high|medium|low] [--context <page>...]"
    return 1
  fi

  # Validate agent exists and is active
  local agent_file
  agent_file=$(find_agent_file "$from_agent")
  if [ -z "$agent_file" ] || [ ! -f "$agent_file" ]; then
    log_error "Agent '$from_agent' not found."
    return 1
  fi

  local agent_status
  agent_status=$(fm_field "$agent_file" "status")
  if [ "$agent_status" != "active" ]; then
    log_error "Agent '$from_agent' is not active (status: ${agent_status:-unknown})."
    return 1
  fi

  local agent_role
  agent_role=$(fm_field "$agent_file" "role")

  # Load role templates
  local templates_file=""
  if [ -f "$CONFIG_HOME/role-templates.json" ]; then
    templates_file="$CONFIG_HOME/role-templates.json"
  elif [ -f "$CONFIG_SRC_DIR/role-templates.json" ]; then
    templates_file="$CONFIG_SRC_DIR/role-templates.json"
  fi

  if [ -z "$templates_file" ] || [ ! -f "$templates_file" ]; then
    log_error "role-templates.json not found. Cannot determine handoff triggers."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for handoff generate."
    return 1
  fi

  # Get handoff triggers for the agent's role
  local has_template
  has_template=$(jq -r ".role_templates[\"$agent_role\"] | if . then \"yes\" else \"no\" end" "$templates_file" 2>/dev/null)

  if [ "$has_template" != "yes" ]; then
    log_error "No role template found for role '$agent_role'. Cannot determine handoff triggers."
    return 1
  fi

  # Extract trigger keys and target roles
  local trigger_keys
  trigger_keys=$(jq -r ".role_templates[\"$agent_role\"].handoff_triggers | keys[]" "$templates_file" 2>/dev/null)

  if [ -z "$trigger_keys" ]; then
    log_error "No handoff triggers defined for role '$agent_role'."
    return 1
  fi

  # Match task keywords against trigger keys
  local task_lower
  task_lower=$(printf '%s' "$task" | tr '[:upper:]' '[:lower:]')

  local briefs_created=0
  local brief_ids=()

  # Ensure handoff directories exist
  ensure_handoff_dirs "$WIKI_HANDOFFS"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  local ts
  ts=$(date -u +"$BRIEF_TS_FORMAT" 2>/dev/null || date +"$BRIEF_TS_FORMAT")

  while IFS= read -r trigger_key; do
    [ -z "$trigger_key" ] && continue

    # Check if any keyword from the trigger appears in the task
    # Convert trigger key to searchable terms (replace hyphens with spaces)
    local search_term
    search_term=$(printf '%s' "$trigger_key" | tr '-' ' ')
    local match=false
    for word in $search_term; do
      if printf '%s' "$task_lower" | grep -qi "$word"; then
        match=true
        break
      fi
    done

    if [ "$match" = false ]; then
      continue
    fi

    # Get target roles for this trigger
    local target_roles
    target_roles=$(jq -r ".role_templates[\"$agent_role\"].handoff_triggers[\"$trigger_key\"] | .[]" "$templates_file" 2>/dev/null)

    while IFS= read -r target_role; do
      [ -z "$target_role" ] && continue

      local bid="${from_agent}-${target_role}-${ts}"
      local brief_file="$WIKI_HANDOFF_BRIEFS/${bid}.md"

      # Skip if brief already exists
      if [ -f "$brief_file" ]; then
        continue
      fi

      # Get deliverables for target role
      local target_deliverables
      target_deliverables=$(jq -r ".role_templates[\"$target_role\"].deliverables | if . then join(\", \") else \"none specified\" end" "$templates_file" 2>/dev/null)

      # Create brief file
      cat > "$brief_file" << BRIEF_EOF
---
from: ${from_agent}
to: ${target_role}
task: "${task}"
priority: ${priority}
context_pages: [$(printf '%s' "${context_pages[*]}" | sed 's/ /, /g')]
created_at: ${now}
status: pending
completed_at: null
deliverables: [${target_deliverables}]
dependencies: []
brief_id: ${bid}
---

## Task

${task}

## Context

Trigger: ${trigger_key}

This brief was auto-generated based on the handoff triggers for the **${agent_role}** role.

## Expected Deliverables

${target_deliverables}
BRIEF_EOF

      brief_ids+=("$bid")
      briefs_created=$((briefs_created + 1))
    done
  done <<< "$trigger_keys"

  # If no triggers matched, show available triggers and ask user
  if [ "$briefs_created" -eq 0 ]; then
    printf 'No handoff triggers matched the task description.\n'
    printf 'Available triggers for role %s:\n' "$agent_role"
    while IFS= read -r trigger_key; do
      [ -z "$trigger_key" ] && continue
      local targets
      targets=$(jq -r ".role_templates[\"$agent_role\"].handoff_triggers[\"$trigger_key\"] | join(\", \")" "$templates_file" 2>/dev/null)
      printf '  %s -> %s\n' "$trigger_key" "$targets"
    done <<< "$trigger_keys"
    printf '\nUse --priority and specify roles manually, or rephrase the task to match a trigger keyword.\n'
    return 0
  fi

  # Display results
  printf 'Generated %d brief(s):\n\n' "$briefs_created"
  printf '%-45s %-12s %-12s %-8s\n' "BRIEF_ID" "FROM" "TO" "PRIORITY"
  printf '%.0s' {1..77} | tr '\0' '-' ; printf '\n'
  for bid in "${brief_ids[@]}"; do
    local bfrom bto bpri
    bfrom=$(fm_field "$WIKI_HANDOFF_BRIEFS/${bid}.md" "from")
    bto=$(fm_field "$WIKI_HANDOFF_BRIEFS/${bid}.md" "to")
    bpri=$(fm_field "$WIKI_HANDOFF_BRIEFS/${bid}.md" "priority")
    printf '%-45s %-12s %-12s %-8s\n' "$bid" "$bfrom" "$bto" "$bpri"
  done

  # Audit
  local ids_json
  ids_json=$(printf '%s\n' "${brief_ids[@]}" | jq -R . | jq -s .)
  audit_log "handoff-generate" "{\"from\":\"$from_agent\",\"briefs_created\":$briefs_created,\"brief_ids\":$ids_json}"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
op_handoff() {
  local subcmd="${1:-list}"
  shift || true

  case "$subcmd" in
    list)      op_handoff_list "$@" ;;
    show)      op_handoff_show "$@" ;;
    complete)  op_handoff_complete "$@" ;;
    generate)  op_handoff_generate "$@" ;;
    *)
      log_error "Unknown handoff subcommand: $subcmd"
      printf 'Usage: software-house handoff <list|show|complete|generate> [args]\n' >&2
      return 1
      ;;
  esac
}