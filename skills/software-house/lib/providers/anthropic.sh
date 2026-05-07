#!/usr/bin/env bash
# providers/anthropic.sh -- Anthropic (Claude) provider adapter
# Routes through the Claude Code Agent tool when running inside Claude Code,
# or prints manual dispatch instructions for other harnesses.
# Provides: provider_execute_anthropic

# Anthropic execution: when running inside Claude Code, outputs an Agent tool
# invocation instruction for the orchestrating LLM to pick up. When not in
# Claude Code, prints instructions for the user to dispatch manually.
# provider_execute_anthropic <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
provider_execute_anthropic() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  local sys_content user_content
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"

  local max_tokens thinking_flag temperature
  read -r max_tokens thinking_flag temperature <<< "$(get_effort_params "$effort")"

  # Check if we're running inside Claude Code (has the Agent tool available)
  # In CLI context, we cannot invoke the Agent tool directly from bash.
  # Instead, we write an instruction file that the orchestrating LLM picks up.
  local instruction_file="${output_file%.md}.spawn.md"

  cat > "$instruction_file" <<SPAWNEOF
---
type: agent-spawn-instruction
provider: anthropic
model: $model
effort: $effort
max_tokens: $max_tokens
thinking: $thinking_flag
temperature: $temperature
output: $output_file
---

# Agent Spawn Instruction

An Anthropic agent needs to be spawned. The orchestrating LLM should invoke the
Agent tool with the following parameters:

## System Prompt

$sys_content

## User Prompt

$user_content

## Output

Write results to: $output_file

## Parameters

- Model: $model
- Max tokens: $max_tokens
- Thinking: $thinking_flag
- Temperature: $temperature
SPAWNEOF

  log_info "Anthropic spawn instruction written to $instruction_file"
  log_info "The orchestrating LLM should pick up this instruction and invoke the Agent tool."

  # For direct CLI execution (outside Claude Code), attempt the Anthropic API
  # if the user has an API key configured.
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    log_info "ANTHROPIC_API_KEY found, attempting direct API call"

    local messages_body
    messages_body="$(jq -n \
      --arg sys "$sys_content" \
      --arg user "$user_content" \
      --argjson max_tokens "$max_tokens" \
      --argjson temp "$temperature" \
      '{
        model: $model_name,
        max_tokens: $max_tokens,
        temperature: $temp,
        system: $sys,
        messages: [{role: "user", content: $user}]
      }' \
      --arg model_name "$model" \
    )"

    local http_code
    http_code="$(curl -s -w "%{http_code}" -o "$output_file" \
      -X POST "https://api.anthropic.com/v1/messages" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -d "$messages_body" 2>/dev/null)" || {
      log_error "Failed to connect to Anthropic API"
      return 1
    }

    if [[ "$http_code" != "200" ]]; then
      log_error "Anthropic API returned HTTP $http_code"
      return 1
    fi

    # Extract content from Anthropic-format response
    if command -v jq &>/dev/null; then
      local content
      content="$(jq -r '.content[0].text // empty' "$output_file" 2>/dev/null)"
      if [[ -n "$content" ]]; then
        echo "$content" > "$output_file"
      fi
    fi

    return 0
  fi

  # No API key -- print instructions for manual dispatch
  printf '\n=== Anthropic Agent Spawn Required ===\n'
  printf 'Provider: anthropic\n'
  printf 'Model: %s\n' "$model"
  printf 'Effort: %s\n' "$effort"
  printf 'Output: %s\n' "$output_file"
  printf '\nSpawn instruction written to: %s\n' "$instruction_file"
  printf '\nThe orchestrating LLM should invoke the Agent tool with the prompt above.\n'
  printf 'If running outside Claude Code, copy the prompt manually to a Claude session.\n\n'

  # Return success since the instruction file is written
  # The actual execution happens asynchronously
  return 0
}