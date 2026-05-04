#!/usr/bin/env bash
# outsource-hire.sh -- add an agent to the freelance pool
# Spec: operations/outsource-hire.md | Tier 2 (additive)

op_outsource_hire() {
  local name=""
  local role=""
  local provider=""
  local model=""
  local contract_type=""
  local contract_end=""

  while (( $# > 0 )); do
    case "$1" in
      --role)          role="$2"; shift 2 ;;
      --provider)      provider="$2"; shift 2 ;;
      --model)         model="$2"; shift 2 ;;
      --contract-type) contract_type="$2"; shift 2 ;;
      --contract-end)  contract_end="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: outsource-hire <name> --role <role> [--provider <p>] [--model <m>] [--contract-type <type>] [--contract-end <date>]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then printf 'Error: agent name is required.\n'; return 1; fi
  if ! validate_name "$name"; then return 1; fi
  if [[ -z "$role" ]]; then printf 'Error: --role is required.\n'; return 1; fi

  require_company_init || return 1

  load_config

  local canonical_file="$AGENTS_GLOBAL/${name}.md"
  if [[ -f "$canonical_file" ]]; then
    printf 'Error: agent %s already exists.\n' "$name"; return 1
  fi

  # Resolve defaults
  if [[ -z "$provider" ]]; then
    local defaults
    defaults="$(get_role_defaults "$role")"
    read -r provider model _ <<< "$defaults"
  fi

  # Egress consent if external
  local provider_class
  provider_class="$(get_provider_class "$provider")"
  local egress_consent_value="none"
  if [[ "$provider_class" == "external" ]]; then
    local endpoint
    endpoint="$(get_provider_endpoint "$provider")"
    if ! egress_consent "$provider" "$endpoint"; then
      printf '\nOutsource hire cancelled -- egress consent not given.\n'; return 1
    fi
    egress_consent_value="external:$(utc_date)"
  fi

  # Tier-2 confirmation
  printf '\nI will create freelance agent %s:\n' "$name"
  printf '  Canonical: %s\n' "$canonical_file"

  if ! confirm 2; then return 1; fi

  if dry_run_msg "Would hire freelance agent $name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"
  local emp_id
  emp_id="$(next_employee_id)"

  local fm
  fm=$(cat <<FMEOF
name: $name
description: $role agent (freelance)
provider: $provider
model: $model
egress_consent: $egress_consent_value
employee_id: $emp_id
team: null
department: null
role: $role
position: $role
reports_to: null
status: freelance
hired_at: $utc_d
level: 1
xp: 0
effort_preset: medium
classification: internal
buddy: null
employment: freelance
hired_by_teams: []
achievements: []
contract_type: ${contract_type:-null}
contract_start: $utc_d
contract_end: ${contract_end:-null}
FMEOF
)

  local body="# $name\n\nFreelance agent provisioned by software-house skill.\nRole: $role\nProvider: $provider [$provider_class]"

  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  # Update outsource manifest
  # TODO: Add agent to $OUTSOURCE_MANIFEST

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"outsource-hire\",\"scope\":\"freelance\",\"args\":{\"name\":\"$name\",\"role\":\"$role\",\"provider\":\"$provider\",\"model\":\"$model\",\"contract_type\":\"${contract_type:-null}\"},\"diff\":{\"created\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":2},\"egress_consent\":{\"required\":$([[ "$egress_consent_value" != "none" ]] && echo true || echo false)},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nHired freelance agent %s (%s)\n' "$name" "$role"
  printf '  Provider: %s [%s]\n' "$provider" "$provider_class"
  printf '  Contract: %s\n' "${contract_type:-(not set)}"
}