#!/usr/bin/env bash
# delegate.sh -- CLI implementation of the delegate operation
# See operations/delegate.md for the full specification.

set -euo pipefail

op_delegate() {
  local agent_name=""
  local task_desc=""
  local from_file=""
  local output_file=""
  local wiki_update=0
  local context_pages=()
  local execute_now=0
  local watch_mode=0

  # Parse arguments
  if (( $# < 1 )); then
    printf 'Usage: software-house delegate <agent-name> <task> [options]\n' >&2
    printf '  --from-file <path>  Read task from file\n' >&2
    printf '  --output <path>     Output file path\n' >&2
    printf '  --wiki-update       Append result to wiki\n' >&2
    printf '  --context <page>    Additional wiki context (repeatable)\n' >&2
    printf '  --execute           Actually run the sub-agent CLI inline\n' >&2
    printf '  --watch             Print output after execution (requires --execute)\n' >&2
    return 1
  fi

  agent_name="$1"; shift

  # Validate agent name
  if ! validate_name "$agent_name"; then
    return 1
  fi

  # Parse remaining arguments
  while (( $# > 0 )); do
    case "$1" in
      --from-file)
        from_file="$2"; shift 2
        ;;
      --output)
        output_file="$2"; shift 2
        ;;
      --wiki-update)
        wiki_update=1; shift
        ;;
      --context)
        context_pages+=("$2"); shift 2
        ;;
      --execute)
        execute_now=1; shift
        ;;
      --watch)
        watch_mode=1; shift
        ;;
      *)
        # Everything else is the task description
        if [[ -z "$task_desc" ]]; then
          task_desc="$1"; shift
          # Append remaining args as part of the description
          while (( $# > 0 )); do
            case "$1" in
              --from-file|--output|--context)
                task_desc="$task_desc $1 $2"; shift 2
                ;;
              --wiki-update)
                wiki_update=1; shift
                ;;
              --execute)
                execute_now=1; shift
                ;;
              --watch)
                watch_mode=1; shift
                ;;
              *)
                task_desc="$task_desc $1"; shift
                ;;
            esac
          done
        fi
        ;;
    esac
  done

  # Require company init
  if ! require_company_init; then
    return 1
  fi

  # Load config
  load_config

  # Get task description
  if [[ -n "$from_file" ]]; then
    if [[ ! -f "$from_file" ]]; then
      log_error "Task file not found: $from_file"
      return 1
    fi
    task_desc="$(cat "$from_file")"
  fi

  if [[ -z "$task_desc" ]]; then
    log_error "Task description is required. Provide inline text or use --from-file."
    return 1
  fi

  # Find agent file
  local agent_file
  if ! agent_file="$(find_agent_file "$agent_name")"; then
    log_error "Agent '$agent_name' not found."
    return 1
  fi

  # Read agent frontmatter
  read_agent "$agent_file"

  # Validate agent is active
  if [[ "$AGENT_STATUS" != "active" ]]; then
    log_error "Agent '$agent_name' is not active (status: $AGENT_STATUS)."
    case "$AGENT_STATUS" in
      onboarding) log_error "Run /software-house onboard $agent_name first." ;;
      alumni) log_error "This agent has been removed from the company." ;;
      *) log_error "Only active agents can receive delegated tasks." ;;
    esac
    return 1
  fi

  # Load role template
  local role_responsibilities="" role_deliverables="" role_collaborates="" role_handoff_triggers=""
  if [[ -f "$ROLE_TEMPLATES" ]] && command -v jq &>/dev/null; then
    role_responsibilities="$(jq -r ".role_templates.${AGENT_ROLE}.responsibilities | join(\", \")" "$ROLE_TEMPLATES" 2>/dev/null || echo "")"
    role_deliverables="$(jq -r ".role_templates.${AGENT_ROLE}.deliverables | join(\", \")" "$ROLE_TEMPLATES" 2>/dev/null || echo "")"
    role_collaborates="$(jq -r ".role_templates.${AGENT_ROLE}.collaborates_with | join(\", \")" "$ROLE_TEMPLATES" 2>/dev/null || echo "")"
    role_handoff_triggers="$(jq -r ".role_templates.${AGENT_ROLE}.handoff_triggers | to_entries | map(\"\(.key): \(.value | join(\", \"))\") | join(\"; \")" "$ROLE_TEMPLATES" 2>/dev/null || echo "")"
  fi

  # Generate default output file
  local ts
  ts="$(utc_timestamp_compact)"
  if [[ -z "$output_file" ]]; then
    if [[ -n "${TEAM_DIR:-}" && -d "$TEAM_DIR" ]]; then
      output_file="$TEAM_DIR/wiki/handoffs/${agent_name}-output-${ts}.md"
    else
      output_file="$WIKI_HANDOFFS/${agent_name}-output-${ts}.md"
    fi
  fi

  # Validate context pages
  for ctx_page in "${context_pages[@]+"${context_pages[@]}"}"; do
    if [[ ! -f "$ctx_page" ]]; then
      log_error "Context page not found: $ctx_page"
      return 1
    fi
  done

  # Check egress consent for external providers
  local provider_class
  provider_class="$(get_provider_class "$AGENT_PROVIDER")"
  local egress_required=false
  if [[ "$provider_class" == "external" ]]; then
    if [[ "$AGENT_EGRESS_CONSENT" == "none" ]]; then
      egress_required=true
    fi
  fi

  # Resolve tools for this agent
  local tools
  tools="$(resolve_agent_tools "$AGENT_ROLE")"

  # Resolve and validate harness
  local resolved_harness
  resolved_harness="$(resolve_harness "${AGENT_HARNESS:-null}" "$AGENT_PROVIDER")"
  if [[ -n "$resolved_harness" ]]; then
    if ! is_valid_harness "$resolved_harness" "$AGENT_PROVIDER"; then
      log_error "Invalid harness/provider combo: harness='$resolved_harness' provider='$AGENT_PROVIDER' (e.g. ollama:gemini is rejected)."
      return 1
    fi
  fi

  # Tier-2 confirmation
  printf '+----------------------------------------------------------+\n'
  printf '| I will delegate the following task to %s.    |\n' "$agent_name"
  printf '| Agent:    %s (%s)                            |\n' "$agent_name" "$AGENT_ROLE"
  printf '| Provider: %s / %s                          |\n' "$AGENT_PROVIDER" "$AGENT_MODEL"
  printf '| Effort:   %s                                   |\n' "$AGENT_EFFORT_PRESET"
  printf '| Harness:  %s                              |\n' "${resolved_harness:-(direct)}"
  printf '| Output:   %s              |\n' "$output_file"
  printf '| Wiki update: %s                               |\n' "$([ $wiki_update -eq 1 ] && echo 'yes' || echo 'no')"
  if $egress_required; then
    printf '| WARNING: External provider requires egress consent.       |\n'
  fi
  printf '|                                                          |\n'
  printf '| Reply '"'"'yes'"'"' to proceed, or anything else to cancel.      |\n'
  printf '+----------------------------------------------------------+\n'

  if ! confirm 2 "$agent_name"; then
    printf 'Cancelled. No changes made.\n'
    return 0
  fi

  # Egress consent for external providers
  if $egress_required; then
    local endpoint
    endpoint="$(get_provider_endpoint "$AGENT_PROVIDER")"
    if ! egress_consent "$AGENT_PROVIDER" "$endpoint"; then
      printf 'Cancelled. Egress consent not granted.\n'
      return 0
    fi
  fi

  # Create handoff inbox entry
  local inbox_dir
  if [[ -n "${TEAM_DIR:-}" && -d "$TEAM_DIR" ]]; then
    inbox_dir="$TEAM_DIR/wiki/handoffs/inbox"
  else
    inbox_dir="$WIKI_HANDOFF_INBOX"
  fi
  mkdir -p "$inbox_dir"

  local inbox_file="$inbox_dir/${agent_name}-task-${ts}.md"
  local first_line
  first_line="$(echo "$task_desc" | head -1)"

  # Build context pages list for frontmatter
  local context_list="[]"
  if (( ${#context_pages[@]} > 0 )); then
    context_list="$(printf '%s\n' "${context_pages[@]}" | jq -R . | jq -s .)"
  fi

  cat > "$inbox_file" <<INBOXEOF
---
from: ceo
to: ${agent_name}
task: ${first_line}
priority: medium
context_pages: ${context_list}
created_at: $(utc_now)
status: pending
output: ${output_file}
---

# Task from CEO

${task_desc}
INBOXEOF

  # Create output directory
  mkdir -p "$(dirname "$output_file")"

  # Detect harness
  detect_harnesses
  local execution_mode="cli-exec"
  if (( HAS_CLAUDE_CODE )); then
    execution_mode="agent-spawn"
  fi

  # Build the task prompt file
  local task_prompt_file
  task_prompt_file="$(mktemp /tmp/sh-agent-task-XXXXXX.md)"
  cat > "$task_prompt_file" <<TASKPROMPTEOF
# Task: ${first_line}

Assigned to: ${agent_name} (${AGENT_ROLE})
Priority: medium
Created: $(utc_now)

## Instructions

1. Read the relevant wiki pages and project context provided in your system prompt.
2. Complete the task described above.
3. Write your results to: ${output_file}
4. If you encounter blockers, document them clearly in the results.
5. If this task triggers a handoff to another role, generate a handoff brief per your Handoff Protocol.

## Task Description

${task_desc}

## Expected Deliverables

${role_deliverables:-See role template for expected deliverables.}
TASKPROMPTEOF

  # Print execution instructions
  printf '\nTask delegated to %s (%s).\n' "$agent_name" "$AGENT_ROLE"
  printf '  Provider:   %s / %s\n' "$AGENT_PROVIDER" "$AGENT_MODEL"
  printf '  Effort:     %s\n' "$AGENT_EFFORT_PRESET"
  printf '  Harness:    %s\n' "${resolved_harness:-(direct)}"
  printf '  Output:     %s\n' "$output_file"
  printf '  Execution:  %s\n' "$execution_mode"
  printf '  Inbox:      %s\n' "$inbox_file"

  if (( execute_now )); then
    # Build system prompt to a tmp file, then run execute_with_fallback
    local sys_prompt_file
    sys_prompt_file="$(mktemp /tmp/sh-agent-sysprompt-XXXXXX.md)"
    build_system_prompt "$agent_name" "$agent_file" "${context_pages[@]+"${context_pages[@]}"}" > "$sys_prompt_file"

    local exec_exit=0
    execute_with_fallback \
      "$agent_name" "$AGENT_ROLE" "$AGENT_PROVIDER" "$AGENT_MODEL" "$AGENT_EFFORT_PRESET" \
      "$sys_prompt_file" "$task_prompt_file" "$output_file" "$resolved_harness" || exec_exit=$?

    rm -f "$sys_prompt_file"

    if (( exec_exit != 0 )); then
      printf 'Execution failed (exit=%d). Inbox entry preserved at: %s\n' "$exec_exit" "$inbox_file" >&2
      return "$exec_exit"
    fi

    if (( watch_mode )) && [[ -f "$output_file" ]]; then
      # execute_with_fallback is synchronous; --watch prints the result after completion
      printf '\n--- output: %s ---\n' "$output_file"
      cat "$output_file"
      printf '--- end ---\n'
    fi

    local out_bytes=0
    [[ -f "$output_file" ]] && out_bytes="$(wc -c < "$output_file" | tr -d ' ')"
    printf 'Output written: %s (%s bytes)\n' "$output_file" "$out_bytes"
  else
    if [[ "$execution_mode" == "agent-spawn" ]]; then
      # Output SPAWN instruction for Claude Code
      printf '\nSPAWN: agent=%s role=%s tools=[%s]\n' "$agent_name" "$AGENT_ROLE" "$tools"
      printf 'OUTPUT: %s\n' "$output_file"
      printf 'PROMPT: %s\n' "$first_line"
      printf '\nSystem prompt context has been prepared. The agent'"'"'s wiki page and project\n'
      printf 'context will be included automatically when the sub-agent is spawned.\n'
      printf '\nTask prompt file: %s\n' "$task_prompt_file"
    else
      # Output sh-agent command for CLI execution
      local sh_agent_cmd="sh-agent ${agent_name} ${task_prompt_file} --output ${output_file}"
      if (( wiki_update )); then
        sh_agent_cmd+=" --wiki-update"
      fi
      for ctx_page in "${context_pages[@]+"${context_pages[@]}"}"; do
        sh_agent_cmd+=" --context ${ctx_page}"
      done

      printf '\nRun the following command to execute:\n'
      printf '  %s\n' "$sh_agent_cmd"
    fi
  fi

  # Audit log
  local audit_entry
  audit_entry="$(json_build \
    "ts" "$(json_str "$(utc_now)")" \
    "actor" "$(json_str "user")" \
    "op" "$(json_str "delegate")" \
    "scope" "$(json_str "agent:${agent_name}")" \
    "args" "{\"agent\":\"${agent_name}\",\"role\":\"${AGENT_ROLE}\",\"provider\":\"${AGENT_PROVIDER}\",\"model\":\"${AGENT_MODEL}\",\"effort\":\"${AGENT_EFFORT_PRESET}\",\"execution_mode\":\"${execution_mode}\",\"output\":\"${output_file}\",\"wiki_update\":${wiki_update},\"harness\":\"${resolved_harness}\",\"execute_now\":${execute_now}}" \
    "diff" "{\"created\":[\"${inbox_file}\",\"${task_prompt_file}\"]}" \
    "confirmation" "{\"tier\":2,\"prompt\":\"I will delegate the following task to ${agent_name}.\",\"response\":\"yes\",\"ts\":\"$(utc_now)\"}" \
    "egress_consent" "{\"required\":${egress_required},\"granted\":$(if $egress_required; then echo "\"EGRESS-CONSENT-${AGENT_PROVIDER}\""; else echo "null"; fi)}" \
    "result" "$(json_str "ok")" \
  )"
  audit_log "$audit_entry"
}