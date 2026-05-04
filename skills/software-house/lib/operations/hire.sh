#!/usr/bin/env bash
# hire.sh -- create a new agent with provider/model/effort
# Spec: operations/hire.md | Tier 2 (additive)

op_hire() {
  local name=""
  local role=""
  local provider=""
  local model=""
  local effort=""
  local dept=""
  local pool=0

  # Parse arguments
  while (( $# > 0 )); do
    case "$1" in
      --role)      role="$2"; shift 2 ;;
      --provider)  provider="$2"; shift 2 ;;
      --model)     model="$2"; shift 2 ;;
      --effort)    effort="$2"; shift 2 ;;
      --dept)      dept="$2"; shift 2 ;;
      --pool)      pool=1; shift ;;
      --help|-h)
        printf 'Usage: hire <name> --role <role> [--provider <p>] [--model <m>] [--effort <e>] [--dept <d>] [--pool]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  # Step 1: Validate inputs
  if [[ -z "$name" ]]; then
    printf 'Error: agent name is required.\n'
    return 1
  fi
  if ! validate_name "$name"; then return 1; fi

  if [[ -z "$role" ]]; then
    printf 'Error: --role is required.\n'
    return 1
  fi

  require_company_init || return 1

  # Load config
  load_config

  # Validate role
  local valid_roles
  valid_roles="$(list_roles)"
  if ! echo "$valid_roles" | grep -qx "$role"; then
    printf 'Error: role "%s" not found in models-config.json.\n' "$role"
    printf 'Valid roles:\n'
    echo "$valid_roles" | sed 's/^/  /'
    return 1
  fi

  # Resolve provider and model
  if [[ -z "$provider" ]]; then
    local defaults
    defaults="$(get_role_defaults "$role")"
    read -r provider model effort <<< "$defaults"
  else
    if [[ -z "$model" ]]; then
      printf 'Error: --model is required when --provider is specified.\n'
      return 1
    fi
    # Validate provider
    local valid_providers
    valid_providers="$(list_providers)"
    if ! echo "$valid_providers" | grep -qx "$provider"; then
      printf 'Error: provider "%s" not found in providers.json.\n' "$provider"
      printf 'Valid providers:\n'
      echo "$valid_providers" | sed 's/^/  /'
      return 1
    fi
  fi

  # Resolve effort
  if [[ -z "$effort" ]]; then
    local defaults
    defaults="$(get_role_defaults "$role")"
    effort="$(echo "$defaults" | awk '{print $3}')"
  fi
  # med -> medium
  [[ "$effort" == "med" ]] && effort="medium"

  # Validate dept if given
  if [[ -n "$dept" ]] && [[ ! -d "$DEPARTMENTS_HOME/$dept" ]]; then
    printf 'Error: department %s not found. Run /software-house dept-create %s first.\n' "$dept" "$dept"
    return 1
  fi

  # Step 2: Determine scope and target paths
  local scope="team"
  local canonical_dir=""
  local canonical_file=""

  if (( pool )); then
    scope="freelance"
    canonical_dir="$AGENTS_GLOBAL"
    canonical_file="$AGENTS_GLOBAL/${name}.md"
  else
    local detected_team
    detected_team="$(detect_team)"
    if [[ -n "$detected_team" ]]; then
      # TODO: Resolve project root from $PROJECTS_INDEX
      # For now, use $SH_HOME as fallback
      canonical_dir="$SH_HOME"
      canonical_file="$SH_HOME/${name}.md"
    else
      # No project detected -- use freelance pool
      scope="freelance"
      canonical_dir="$AGENTS_GLOBAL"
      canonical_file="$AGENTS_GLOBAL/${name}.md"
    fi
  fi

  # Step 3: Check for conflicts
  if [[ -f "$canonical_file" ]]; then
    printf 'Error: agent %s already exists. Use /software-house set-model to change config, or /software-house fire then re-hire.\n' "$name"
    return 1
  fi

  # Step 4: Egress consent gate
  local provider_class
  provider_class="$(get_provider_class "$provider")"
  local egress_required=false
  local egress_consent_value="none"

  if [[ "$provider_class" == "external" ]]; then
    egress_required=true
    local endpoint
    endpoint="$(get_provider_endpoint "$provider")"
    printf '\n'
    if ! egress_consent "$provider" "$endpoint"; then
      # Print local fallback
      # TODO: Read fallback_external from models config for the role
      printf '\nHire cancelled -- egress consent not given.\n'
      printf '\nLocal fallback for role %s:\n' "$role"
      printf '  provider: ollama\n'
      printf '  model:    (check models-config.json)\n'
      printf '  effort:   %s\n' "$effort"
      printf '\nRun the same hire command without --provider to use the local fallback.\n'
      return 1
    fi
    egress_consent_value="external:$(utc_date)"
  fi

  # Step 5: Tier-2 confirmation
  printf '\nI will create the following for agent '"'"'%s'"'"':\n' "$name"
  printf '  Canonical:  %s\n' "$canonical_file"
  if [[ "$scope" != "freelance" ]]; then
    printf '  Wiki:       %s/%s.md\n' "$WIKI_PEOPLE" "$name"
  fi
  # TODO: List adapter paths based on detected harnesses and project root
  printf '  Audit log:  %s\n' "$AUDIT_LOG"

  if ! confirm 2; then
    return 1
  fi

  # Step 6: Write canonical agent file
  if dry_run_msg "Would create agent file at $canonical_file"; then
    return 0
  fi

  local utc_ts
  utc_ts="$(utc_now)"
  local utc_d
  utc_d="$(utc_date)"
  local emp_id
  emp_id="$(next_employee_id)"

  local team_value="null"
  local dept_value="null"
  local employment_value="permanent"

  if (( pool )); then
    employment_value="freelance"
  else
    team_value="$(detect_team)"
    [[ -z "$team_value" ]] && team_value="null"
  fi
  [[ -n "$dept" ]] && dept_value="$dept"

  local fm
  fm=$(cat <<FMEOF
name: $name
description: $role agent
provider: $provider
model: $model
egress_consent: $egress_consent_value
employee_id: $emp_id
team: $team_value
department: $dept_value
role: $role
position: $role
reports_to: null
status: onboarding
hired_at: $utc_d
level: 1
xp: 0
effort_preset: $effort
classification: internal
buddy: null
employment: $employment_value
hired_by_teams: []
achievements: []
FMEOF
)

  local body="# $name\n\nAgent provisioned by software-house skill.\nRole: $role\nProvider: $provider [$provider_class]"

  write_agent "$canonical_file" "$fm" "$(printf '%b' "$body")"

  # Step 7: Write wiki people page (project scope only)
  if [[ "$scope" != "freelance" ]]; then
    local wiki_file="$WIKI_PEOPLE/${name}.md"
    if [[ ! -f "$wiki_file" ]]; then
      local wiki_body="# $name\n\n## Onboarding\n\nBriefing not yet written. Run /software-house onboard $name to generate.\n\n## Notes\n\n(empty)"
      write_agent "$wiki_file" "$fm" "$(printf '%b' "$wiki_body")"
    fi
  fi

  # Step 8: Write harness adapters
  # TODO: Implement full adapter writing per _shared.md section 3
  # This requires resolving the project root directory.
  # For now, detect harnesses but skip adapter writing with a TODO.
  detect_harnesses
  # Adapter writing is a TODO -- requires project root resolution.

  # Step 9: Update team roster and index
  # TODO: Implement roster and index updates when team context is resolved.

  # Step 10: Append audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"hire\",\"scope\":\"$scope\",\"args\":{\"name\":\"$name\",\"role\":\"$role\",\"provider\":\"$provider\",\"model\":\"$model\",\"effort\":\"$effort\",\"dept\":\"$dept_value\",\"pool\":$pool},\"diff\":{\"created\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":2},\"egress_consent\":{\"required\":$egress_required,\"granted\":$( [[ "$egress_consent_value" != "none" ]] && printf '"EGRESS-CONSENT-%s"' "$provider" || echo 'null' ),\"provider\":\"$provider\"},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  # Step 11: Report
  printf '\nHired %s (%s)\n' "$name" "$role"
  printf '  Canonical:    %s\n' "$canonical_file"
  if [[ "$scope" != "freelance" ]]; then
    printf '  Wiki:         %s/%s.md\n' "$WIKI_PEOPLE" "$name"
  fi
  printf '  Provider:     %s [%s]\n' "$provider" "$provider_class"
  printf '  Model:        %s\n' "$model"
  printf '  Effort:       %s\n' "$effort"
  printf '  Egress:       %s\n' "$egress_consent_value"
  printf '  Status:       onboarding\n'
  printf '\n  Next steps:\n'
  printf '    /software-house onboard %s    write personalized briefing\n' "$name"
  printf '    /software-house show %s       inspect the agent record\n' "$name"
}