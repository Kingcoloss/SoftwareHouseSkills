#!/usr/bin/env bash
# transfer.sh -- transfer agent to another team
# Spec: operations/transfer.md | Tier 3 (modifying)

op_transfer() {
  local name=""
  local to_team=""
  local from_team=""

  while (( $# > 0 )); do
    case "$1" in
      --to)    to_team="$2"; shift 2 ;;
      --team)  from_team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: transfer <name> --to <team> [--team <current>]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi
  if [[ -z "$to_team" ]]; then printf 'Error: --to <team> is required.\n'; return 1; fi
  if ! validate_name "$to_team"; then return 1; fi

  require_company_init || return 1

  # TODO: Resolve agent file from project context or team
  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" == "alumni" ]]; then
    printf 'Error: %s is archived. Cannot transfer.\n' "$name"; return 1
  fi

  if [[ "$AGENT_TEAM" == "$to_team" ]]; then
    printf 'Error: %s is already on team %s. No transfer needed.\n' "$name" "$to_team"; return 1
  fi

  # Tier-3 confirmation
  printf '\nI will transfer %s from %s to %s:\n' "$name" "${from_team:-$AGENT_TEAM}" "$to_team"
  printf '  Agent file: %s (team field update)\n' "$canonical_file"
  printf '  Wiki:       %s/%s.md\n' "$WIKI_PEOPLE" "$name"

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would transfer $name to team $to_team"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # Update canonical agent file
  write_agent_field "$canonical_file" "team" "$to_team"
  write_agent_field "$canonical_file" "status" "active"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # Update wiki people page
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${name}.md" "team" "$to_team"
  fi

  # TODO: Update old team roster (remove member)
  # TODO: Update new team roster (add member)
  # TODO: Move adapters between projects
  # TODO: Write transfer log entries

  # Audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"transfer\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"from_team\":\"${from_team:-$AGENT_TEAM}\",\"to_team\":\"$to_team\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nTransferred %s from %s to %s\n' "$name" "${from_team:-$AGENT_TEAM}" "$to_team"
}