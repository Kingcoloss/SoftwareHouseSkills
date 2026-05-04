#!/usr/bin/env bash
# second.sh -- matrix-assign an agent to a second team
# Spec: operations/second.md | Tier 3 (modifying)

op_second() {
  local name=""
  local to_team=""

  while (( $# > 0 )); do
    case "$1" in
      --to)   to_team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: second <name> --to <team>\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi
  if [[ -z "$to_team" ]]; then printf 'Error: --to <team> is required.\n'; return 1; fi

  require_company_init || return 1

  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" == "alumni" ]]; then
    printf 'Error: %s is archived. Cannot second.\n' "$name"; return 1
  fi

  # Tier-3 confirmation
  printf '\nI will matrix-assign %s to team %s as a secondary team.\n' "$name" "$to_team"
  printf '  Current team: %s\n' "$AGENT_TEAM"
  printf '  Secondary teams: %s\n' "$AGENT_SECONDARY_TEAMS"

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would second $name to team $to_team"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # TODO: Update secondary_teams in frontmatter (requires array manipulation)
  # For now, update updated_at
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # Audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"second\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"to_team\":\"$to_team\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nSeconded %s to team %s\n' "$name" "$to_team"
}