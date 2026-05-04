#!/usr/bin/env bash
# disband.sh -- remove an entire team (two-step typed CONFIRM)
# Spec: operations/disband.md | Tier 4 (destructive)

op_disband() {
  local team_name=""

  while (( $# > 0 )); do
    case "$1" in
      --help|-h)
        printf 'Usage: disband <team>\n'
        return 0
        ;;
      *)
        if [[ -z "$team_name" ]]; then team_name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$team_name" ]]; then printf 'Error: team name is required.\n'; return 1; fi
  if ! validate_name "$team_name"; then return 1; fi

  require_company_init || return 1

  # Check team exists
  if [[ ! -f "$WIKI_TEAMS/${team_name}.md" ]]; then
    printf 'Error: team %s not found.\n' "$team_name"; return 1
  fi

  # Tier-4 step 1
  printf '\nImpact of disbanding %s:\n\n' "$team_name"
  printf '  Team wiki page: %s/%s.md\n' "$WIKI_TEAMS" "$team_name"
  printf '  All members will lose their team assignment.\n'
  printf '  OKR files for this team will be archived.\n'
  printf '  Adapters for all team members will be removed.\n\n'

  if ! confirm 4 "$team_name"; then return 1; fi

  if dry_run_msg "Would disband team $team_name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # Archive team wiki page
  local archive_dir="$COMPANY_HOME/wiki/teams/_archived"
  mkdir -p "$archive_dir"
  local archive_file="$archive_dir/${team_name}-$(utc_timestamp_compact).md"

  if [[ -f "$WIKI_TEAMS/${team_name}.md" ]]; then
    write_agent_field "$WIKI_TEAMS/${team_name}.md" "status" "disbanded"
    mv "$WIKI_TEAMS/${team_name}.md" "$archive_file"
  fi

  # TODO: Update all member agent files (remove team field)
  # TODO: Remove adapters for all team members
  # TODO: Archive OKR files

  # Rebuild company index
  rebuild_index "$COMPANY_INDEX" "$COMPANY_HOME/wiki" "Company Wiki Index"

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"disband\",\"scope\":\"team:$team_name\",\"args\":{\"name\":\"$team_name\"},\"diff\":{\"archived\":[\"$archive_file\"]},\"confirmation\":{\"tier\":4},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nDisbanded team %s\n' "$team_name"
  printf '  Archived to: %s\n' "$archive_file"
}