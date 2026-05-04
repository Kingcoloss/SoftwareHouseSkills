#!/usr/bin/env bash
# award-xp.sh -- grant XP and trigger level/achievement checks
# Spec: operations/award-xp.md | Tier 3 (modifying)

op_award_xp() {
  local name=""
  local amount=0
  local reason=""
  local achievement=""
  local team=""

  while (( $# > 0 )); do
    case "$1" in
      --amount)      amount="$2"; shift 2 ;;
      --reason)      reason="$2"; shift 2 ;;
      --achievement) achievement="$2"; shift 2 ;;
      --team)        team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: award-xp <name> --amount N [--reason "<text>"] [--achievement <name>] [--team <t>]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi
  if (( amount <= 0 )); then
    printf 'Error: --amount must be a positive integer. Got: %s\n' "$amount"; return 1
  fi

  # Validate achievement name if given
  if [[ -n "$achievement" ]] && [[ ! "$achievement" =~ ^[a-z][a-z0-9-]{1,63}$ ]]; then
    printf 'Error: achievement name "%s" is invalid. Must match ^[a-z][a-z0-9-]{1,63}\$.\n' "$achievement"
    return 1
  fi

  require_company_init || return 1

  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$name"; return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" != "active" ]] && [[ "$AGENT_STATUS" != "freelance" ]]; then
    printf 'Error: agent %s has status "%s". Only active or freelance agents can receive XP.\n' "$name" "$AGENT_STATUS"
    return 1
  fi

  # Compute new XP and level
  local new_xp=$(( AGENT_XP + amount ))
  local new_level="$AGENT_LEVEL"

  if (( new_xp >= 1000 )); then new_level=5
  elif (( new_xp >= 600 )); then new_level=4
  elif (( new_xp >= 300 )); then new_level=3
  elif (( new_xp >= 100 )); then new_level=2
  fi

  local level_up=false
  if (( new_level > AGENT_LEVEL )); then
    level_up=true
  fi

  # Tier-3 confirmation
  printf '\nI will update the following for agent '"'"'%s'"'"':\n' "$name"
  printf '  XP:       %s -> %s\n' "$AGENT_XP" "$new_xp"
  printf '  Level:    %s -> %s\n' "$AGENT_LEVEL" "$new_level"
  if [[ -n "$achievement" ]]; then
    printf '  Achievement: %s\n' "$achievement"
  fi
  if $level_up; then
    printf '  LEVEL UP! Level %s -> %s\n' "$AGENT_LEVEL" "$new_level"
  fi

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would award $amount XP to $name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # Update canonical agent file
  write_agent_field "$canonical_file" "xp" "$new_xp"
  write_agent_field "$canonical_file" "level" "$new_level"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  # TODO: Add achievement to achievements array

  # Update wiki people page
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${name}.md" "xp" "$new_xp"
    write_agent_field "$WIKI_PEOPLE/${name}.md" "level" "$new_level"
  fi

  # Audit log
  local level_up_json="null"
  if $level_up; then
    level_up_json="{\"from\":$AGENT_LEVEL,\"to\":$new_level}"
  fi

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"award-xp\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"amount\":$amount,\"reason\":\"${reason:-null}\",\"achievement\":\"${achievement:-null}\",\"level_up\":$level_up_json},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nAwarded %s XP to %s\n' "$amount" "$name"
  printf '  Previous XP: %s\n' "$AGENT_XP"
  printf '  New XP:      %s\n' "$new_xp"
  printf '  Level:       %s -> %s\n' "$AGENT_LEVEL" "$new_level"
  if $level_up; then
    printf '  LEVEL UP! %s is now level %s.\n' "$name" "$new_level"
  fi
}