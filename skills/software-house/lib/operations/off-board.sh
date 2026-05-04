#!/usr/bin/env bash
# off-board.sh -- run off-boarding checklist before removal
# Spec: operations/off-board.md | Tier 3 (modifying)

op_off_board() {
  local name=""
  local team=""
  local pool=0

  while (( $# > 0 )); do
    case "$1" in
      --team)  team="$2"; shift 2 ;;
      --pool)  pool=1; shift ;;
      --help|-h)
        printf 'Usage: off-board <name> [--team <t>] [--pool]\n'
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

  if [[ "$AGENT_OFFBOARD_STATUS" == "done" ]]; then
    printf 'Note: %s is already off-boarded (offboard_at: %s).\n' "$name" "$AGENT_OFFBOARD_AT"
  fi

  # Tier-3 confirmation
  printf '\nI will off-board %s:\n' "$name"
  printf '  Agent file: %s\n' "$canonical_file"
  printf '  Current status: %s\n' "$AGENT_STATUS"

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would off-board $name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  write_agent_field "$canonical_file" "offboard_at" "$utc_d"
  write_agent_field "$canonical_file" "offboard_status" "pending"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # TODO: Full off-boarding checklist per off-board.md spec
  # - Check for open OKR ownership
  # - Check for reports_to references
  # - Check for active task assignments

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"off-board\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nOff-boarded %s (pending final review)\n' "$name"
  printf '  Next: /software-house fire %s to complete removal\n' "$name"
}