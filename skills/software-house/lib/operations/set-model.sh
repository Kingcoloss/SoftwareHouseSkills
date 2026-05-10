#!/usr/bin/env bash
# set-model.sh -- change agent provider/model/effort
# Spec: operations/set-model.md | Tier 3 (modifying)

op_set_model() {
  local name=""
  local provider=""
  local model=""
  local effort=""
  local harness=""
  local harness_changed=0

  while (( $# > 0 )); do
    case "$1" in
      --provider)      provider="$2"; shift 2 ;;
      --model)         model="$2"; shift 2 ;;
      --effort)        effort="$2"; shift 2 ;;
      --harness)       harness="$2"; harness_changed=1; shift 2 ;;
      --clear-harness) harness="null"; harness_changed=1; shift ;;
      --help|-h)
        printf 'Usage: set-model <name> [--provider <p>] [--model <m>] [--effort <e>] [--harness <value>] [--clear-harness]\n'
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
    printf 'Error: %s is archived. Cannot set model.\n' "$name"; return 1
  fi

  # Resolve new values (keep old if not specified)
  local new_provider="${provider:-$AGENT_PROVIDER}"
  local new_model="${model:-$AGENT_MODEL}"
  local new_effort="${effort:-$AGENT_EFFORT_PRESET}"
  [[ "$new_effort" == "med" ]] && new_effort="medium"

  local new_harness="${AGENT_HARNESS:-null}"
  if (( harness_changed )); then
    new_harness="$harness"
  fi
  if [[ "$new_harness" != "null" && -n "$new_harness" ]]; then
    if ! is_valid_harness "$new_harness" "$new_provider"; then
      printf 'Error: invalid harness %s for provider %s.\n' "$new_harness" "$new_provider" >&2
      printf 'Valid: claude-code | codex | gemini | ollama:<integration>\n' >&2
      printf 'Note: ollama:gemini is NOT supported (gemini is not an ollama launch integration).\n' >&2
      printf 'Note: ollama:<integration> requires provider=ollama.\n' >&2
      return 1
    fi
  fi

  # Egress consent gate if switching to external provider
  local provider_class
  provider_class="$(get_provider_class "$new_provider")"
  local egress_required=false

  if [[ "$provider_class" == "external" ]] && [[ "$AGENT_PROVIDER" != "$new_provider" ]]; then
    egress_required=true
    local endpoint
    endpoint="$(get_provider_endpoint "$new_provider")"
    if ! egress_consent "$new_provider" "$endpoint"; then
      printf '\nModel change cancelled -- egress consent not given.\n'
      return 1
    fi
  fi

  # Tier-3 confirmation
  printf '\nI will update the following for %s:\n' "$name"
  printf '  Provider: %s -> %s\n' "$AGENT_PROVIDER" "$new_provider"
  printf '  Model:    %s -> %s\n' "$AGENT_MODEL" "$new_model"
  printf '  Effort:   %s -> %s\n' "$AGENT_EFFORT_PRESET" "$new_effort"
  if (( harness_changed )); then
    printf '  Harness:  %s -> %s\n' "${AGENT_HARNESS:-null}" "$new_harness"
  fi

  if ! confirm 3; then return 1; fi

  if dry_run_msg "Would update model for $name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  write_agent_field "$canonical_file" "provider" "$new_provider"
  write_agent_field "$canonical_file" "model" "$new_model"
  write_agent_field "$canonical_file" "effort_preset" "$new_effort"
  write_agent_field "$canonical_file" "updated_at" "$utc_d"

  if $egress_required; then
    write_agent_field "$canonical_file" "egress_consent" "external:$utc_d"
  fi

  if (( harness_changed )); then
    write_agent_field "$canonical_file" "harness" "$new_harness"
    if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
      write_agent_field "$WIKI_PEOPLE/${name}.md" "harness" "$new_harness"
    fi
  fi

  # Update wiki people page
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${name}.md" "provider" "$new_provider"
    write_agent_field "$WIKI_PEOPLE/${name}.md" "model" "$new_model"
    write_agent_field "$WIKI_PEOPLE/${name}.md" "effort_preset" "$new_effort"
  fi

  # TODO: Rewrite harness adapters with new model

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"set-model\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"provider\":\"$new_provider\",\"model\":\"$new_model\",\"effort\":\"$new_effort\",\"harness\":\"$new_harness\"},\"diff\":{\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":3},\"egress_consent\":{\"required\":$egress_required},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nUpdated model for %s\n' "$name"
  printf '  Provider: %s [%s]\n' "$new_provider" "$provider_class"
  printf '  Model:    %s\n' "$new_model"
  printf '  Effort:   %s\n' "$new_effort"
  printf '  Harness:  %s\n' "${new_harness:-null}"
}