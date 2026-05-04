#!/usr/bin/env bash
# dept-assign.sh -- assign an agent to a department
# Spec: operations/dept-assign.md | Tier 3 (modifying)

op_dept_assign() {
  local agent_name=""
  local dept_name=""
  local team=""
  local pool=0

  while (( $# > 0 )); do
    case "$1" in
      --team)  team="$2"; shift 2 ;;
      --pool)  pool=1; shift ;;
      --help|-h)
        printf 'Usage: dept-assign <agent-name> <dept-name> [--team <t>] [--pool]\n'
        return 0
        ;;
      *)
        if [[ -z "$agent_name" ]]; then
          agent_name="$1"; shift
        elif [[ -z "$dept_name" ]]; then
          dept_name="$1"; shift
        else
          shift
        fi ;;
    esac
  done

  if [[ -z "$agent_name" ]]; then
    printf 'Error: agent name is required.\n'; return 1
  fi
  if [[ -z "$dept_name" ]]; then
    printf 'Error: department name is required.\n'; return 1
  fi
  if ! validate_name "$agent_name"; then return 1; fi
  if ! validate_name "$dept_name"; then return 1; fi

  require_company_init || return 1

  # Validate department exists
  if [[ ! -d "$DEPARTMENTS_HOME/$dept_name" ]]; then
    printf 'Error: department %s not found. Run /software-house dept-create %s first.\n' "$dept_name" "$dept_name"
    return 1
  fi

  # Resolve agent file
  local canonical_file
  if (( pool )); then
    canonical_file="$AGENTS_GLOBAL/${agent_name}.md"
  else
    # TODO: Resolve from team/project context
    canonical_file="$AGENTS_GLOBAL/${agent_name}.md"
  fi

  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$agent_name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" == "alumni" ]]; then
    printf 'Error: %s is archived. Cannot assign.\n' "$agent_name"; return 1
  fi

  # Check if already assigned to same dept
  if [[ "$AGENT_DEPARTMENT" == "$dept_name" ]]; then
    printf 'Error: %s is already assigned to department %s. No changes needed.\n' "$agent_name" "$dept_name"
    return 1
  fi

  local from_dept="$AGENT_DEPARTMENT"

  # Tier-3 confirmation
  printf '\nI will update the following for agent '"'"'%s'"'"':\n' "$agent_name"
  printf '  Department: %s -> %s\n' "${from_dept:-null}" "$dept_name"
  printf '  Agent file: %s\n' "$canonical_file"
  if [[ -n "$from_dept" ]] && [[ "$from_dept" != "null" ]]; then
    printf '  Note: %s is currently in department %s. This will reassign them to %s.\n' "$agent_name" "$from_dept" "$dept_name"
  fi

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would assign $agent_name to department $dept_name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # Update canonical agent file
  write_agent_field "$canonical_file" "department" "$dept_name"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # Update wiki people page
  if [[ -f "$WIKI_PEOPLE/${agent_name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${agent_name}.md" "department" "$dept_name"
  fi

  # Update department agents index
  mkdir -p "$DEPARTMENTS_HOME/$dept_name/agents"
  local dept_index="$DEPARTMENTS_HOME/$dept_name/agents/index.md"
  if [[ ! -f "$dept_index" ]]; then
    printf '# Agents -- %s\n\n| Name | Role | Provider | Status | Assigned At |\n|---|---|---|---|---|\n' "$dept_name" > "$dept_index"
  fi
  printf '| %s | %s | %s | active | %s |\n' "$agent_name" "$AGENT_ROLE" "$AGENT_PROVIDER" "$utc_d" >> "$dept_index"

  # Remove from old department index if applicable
  if [[ -n "$from_dept" ]] && [[ "$from_dept" != "null" ]] && [[ -f "$DEPARTMENTS_HOME/$from_dept/agents/index.md" ]]; then
    # TODO: Remove agent row from old department index
    : # Requires row-level editing of markdown table
  fi

  # Audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"dept-assign\",\"scope\":\"agent:$agent_name\",\"args\":{\"agent\":\"$agent_name\",\"dept\":\"$dept_name\",\"from_dept\":\"${from_dept:-null}\"},\"diff\":{\"updated\":[\"$canonical_file\",\"$dept_index\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nAssigned %s to department %s\n' "$agent_name" "$dept_name"
  printf '  From dept:  %s\n' "${from_dept:-(none)}"
}