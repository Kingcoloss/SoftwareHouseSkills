#!/usr/bin/env bash
# promote.sh -- increase an agent's level and optionally change role
# Spec: operations/promote.md | Tier 3 (modifying)

op_promote() {
  local name=""
  local by=1
  local to_role=""

  while (( $# > 0 )); do
    case "$1" in
      --by)        by="$2"; shift 2 ;;
      --to-role)   to_role="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: promote <name> [--by N] [--to-role <role>]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi

  require_company_init || return 1

  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" == "alumni" ]]; then
    printf 'Error: %s is archived. Cannot promote.\n' "$name"; return 1
  fi

  local new_level=$(( AGENT_LEVEL + by ))
  if (( new_level > 5 )); then
    new_level=5
    printf 'Note: Level capped at 5.\n'
  fi

  # Tier-3 confirmation
  printf '\nI will promote %s:\n' "$name"
  printf '  Level: %s -> %s\n' "$AGENT_LEVEL" "$new_level"
  [[ -n "$to_role" ]] && printf '  New role: %s\n' "$to_role"

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would promote $name to level $new_level"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  write_agent_field "$canonical_file" "level" "$new_level"
  write_agent_field "$canonical_file" "promotion_at" "$utc_d"
  write_agent_field "$canonical_file" "promotion_from_level" "$AGENT_LEVEL"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"
  if [[ -n "$to_role" ]]; then
    write_agent_field "$canonical_file" "role" "$to_role"
    write_agent_field "$canonical_file" "position" "$to_role"
  fi

  # Update wiki people page
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${name}.md" "level" "$new_level"
    write_agent_field "$WIKI_PEOPLE/${name}.md" "promotion_at" "$utc_d"
    [[ -n "$to_role" ]] && write_agent_field "$WIKI_PEOPLE/${name}.md" "role" "$to_role"
  fi

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"promote\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"by\":$by,\"to_role\":\"${to_role:-null}\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nPromoted %s to level %s\n' "$name" "$new_level"
}