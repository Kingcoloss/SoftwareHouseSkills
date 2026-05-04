#!/usr/bin/env bash
# onboard.sh -- write personalized briefing for a new agent
# Spec: operations/onboard.md | Tier 2 (additive)

op_onboard() {
  local name=""
  local team=""
  local pool=0

  while (( $# > 0 )); do
    case "$1" in
      --team)  team="$2"; shift 2 ;;
      --pool)  pool=1; shift ;;
      --help|-h)
        printf 'Usage: onboard <name> [--team <t>] [--pool]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Error: agent name is required.\n'
    return 1
  fi
  if ! validate_name "$name"; then return 1; fi

  require_company_init || return 1

  # Resolve agent file
  local canonical_file=""
  if (( pool )); then
    canonical_file="$AGENTS_GLOBAL/${name}.md"
  elif [[ -n "$team" ]]; then
    # TODO: Resolve project root from team name via $PROJECTS_INDEX
    canonical_file="$AGENTS_GLOBAL/${name}.md"
  else
    canonical_file="$AGENTS_GLOBAL/${name}.md"
    # Also check team agents
    if [[ ! -f "$canonical_file" ]]; then
      # TODO: Check project-scoped agents
      canonical_file=""
    fi
  fi

  if [[ -z "$canonical_file" ]] || [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found. Run /software-house hire %s first.\n' "$name" "$name"
    return 1
  fi

  # Read agent frontmatter
  read_agent "$canonical_file"

  # Check idempotency
  local reonboard=false
  if [[ "$AGENT_ONBOARD_STATUS" == "done" ]]; then
    printf 'Note: %s has been onboarded before (onboard_at: %s). Re-running will overwrite the briefing.\n' "$name" "$AGENT_ONBOARD_AT"
    reonboard=true
  fi

  # Step 5: Tier-2 confirmation
  local briefing_path
  briefing_path="$(dirname "$canonical_file")/${name}.onboard.md"
  printf '\nI will create/update the following:\n'
  printf '  Briefing:   %s\n' "$briefing_path"
  printf '  Agent file: %s (frontmatter fields: onboard_at, onboard_status)\n' "$canonical_file"
  printf '  Audit log:  %s\n' "$AUDIT_LOG"

  if ! confirm 2; then
    return 1
  fi

  if dry_run_msg "Would write briefing to $briefing_path"; then
    return 0
  fi

  # Step 6: Write briefing sidecar
  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  cat > "$briefing_path" << BRIEFEOF
# Onboarding Briefing: $name

Generated: $utc_ts
Role: $AGENT_ROLE
Team: ${AGENT_TEAM}
Department: ${AGENT_DEPARTMENT}

## Your Role

$(printf 'Agent in the %s role. Provider: %s, Model: %s, Effort: %s.' "$AGENT_ROLE" "$AGENT_PROVIDER" "$AGENT_MODEL" "$AGENT_EFFORT_PRESET")

## Team Context

$(if [[ "$AGENT_TEAM" != "null" ]]; then printf 'Team: %s' "$AGENT_TEAM"; else printf 'Freelance Pool -- no team context.'; fi)

## Current Roster

$(printf '(roster lookup TODO -- requires team context resolution)')

## Your Provider and Model

Provider: $AGENT_PROVIDER [$(get_provider_class "$AGENT_PROVIDER")]
Model:    $AGENT_MODEL
Effort:   $AGENT_EFFORT_PRESET

$(if [[ "$AGENT_PROVIDER_CLASS" == "external" ]]; then printf 'Your conversations will egress to an external provider when you run.'; else printf 'Your conversations remain on this machine.'; fi)

## First Steps

1. Review the team charter.
2. Check your canonical definition: $canonical_file
3. Introduce yourself to the team lead.
4. Pick up your first task from the project backlog.
BRIEFEOF

  # Step 7: Update agent frontmatter
  write_agent_field "$canonical_file" "onboard_at" "$utc_d"
  write_agent_field "$canonical_file" "onboard_status" "done"
  if [[ "$AGENT_STATUS" == "onboarding" ]]; then
    write_agent_field "$canonical_file" "status" "active"
  fi

  # Step 10: Append audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"onboard\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"team\":\"$AGENT_TEAM\",\"pool\":$pool,\"reonboard\":$reonboard},\"diff\":{\"created\":[\"$briefing_path\"],\"updated\":[\"$canonical_file\"]},\"confirmation\":{\"tier\":2},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  # Step 11: Report
  printf '\nOnboarded %s\n' "$name"
  printf '  Briefing:  %s\n' "$briefing_path"
  printf '  Status:    active\n'
  printf '\n  Next steps:\n'
  printf '    /software-house show %s       verify the full agent record\n' "$name"
}