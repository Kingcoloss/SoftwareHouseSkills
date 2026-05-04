#!/usr/bin/env bash
# contract.sh -- attach a freelance agent to a project team
# Spec: operations/contract.md | Tier 3 (modifying)

op_contract() {
  local name=""
  local team=""

  while (( $# > 0 )); do
    case "$1" in
      --team)  team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: contract <name> --team <team>\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi
  if [[ -z "$team" ]]; then printf 'Error: --team is required.\n'; return 1; fi

  require_company_init || return 1

  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found in freelance pool.\n' "$name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_EMPLOYMENT" != "freelance" ]]; then
    printf 'Error: %s is not a freelance agent. Use /software-house dept-assign instead.\n' "$name"; return 1
  fi

  # Tier-3 confirmation
  printf '\nI will contract %s to team %s:\n' "$name" "$team"
  printf '  Agent file: %s\n' "$canonical_file"

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would contract $name to team $team"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # TODO: Update hired_by_teams array in frontmatter
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # TODO: Write harness adapters for the project
  # TODO: Add to team roster

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"contract\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"team\":\"$team\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nContracted %s to team %s\n' "$name" "$team"
}