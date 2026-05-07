#!/usr/bin/env bash
# providers/vllm.sh -- vLLM provider adapter
# Uses OpenAI-compatible API at localhost:8000.
# Provides: provider_execute_vllm

# vLLM execution: POST to OpenAI-compatible /v1/chat/completions endpoint.
# provider_execute_vllm <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
provider_execute_vllm() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  local endpoint="${VLLM_ENDPOINT:-http://localhost:8000}"

  local sys_content user_content
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"

  local max_tokens thinking_flag temperature
  read -r max_tokens thinking_flag temperature <<< "$(get_effort_params "$effort")"

  # vLLM supports thinking/reasoning via extra_body for supported models
  local body
  if [[ "$thinking_flag" == "true" ]]; then
    body="$(cat <<JSONEOF
{
  "model": "$model",
  "max_tokens": $max_tokens,
  "temperature": $temperature,
  "messages": [
    {"role": "system", "content": $(echo "$sys_content" | jq -Rs .)},
    {"role": "user", "content": $(echo "$user_content" | jq -Rs .)}
  ],
  "extra_body": {
    "include_reasoning": true
  }
}
JSONEOF
)"
  else
    body="$(cat <<JSONEOF
{
  "model": "$model",
  "max_tokens": $max_tokens,
  "temperature": $temperature,
  "messages": [
    {"role": "system", "content": $(echo "$sys_content" | jq -Rs .)},
    {"role": "user", "content": $(echo "$user_content" | jq -Rs .)}
  ]
}
JSONEOF
)"
  fi

  local http_code
  http_code="$(curl -s -w "%{http_code}" -o "$output_file" \
    -X POST "${endpoint}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$body" 2>/dev/null)" || {
    log_error "Failed to connect to vLLM at $endpoint"
    return 1
  }

  if [[ "$http_code" != "200" ]]; then
    log_error "vLLM returned HTTP $http_code"
    return 1
  fi

  # Extract content from OpenAI-format response
  if command -v jq &>/dev/null; then
    local content
    content="$(jq -r '.choices[0].message.content // empty' "$output_file" 2>/dev/null)"
    if [[ -n "$content" ]]; then
      echo "$content" > "$output_file"
    fi
  fi

  return 0
}