#!/usr/bin/env bash
# providers/_shared.sh -- common provider execution helpers and fallback logic
# Sourced by bin/sh-agent and individual provider adapters.

set -euo pipefail

# ---------------------------------------------------------------------------
# Harness adapters (CLI-based sub-agent spawning)
# ---------------------------------------------------------------------------
# Each adapter accepts a system prompt + user prompt and writes the model's
# response to a .md output file. Used when the agent's resolved harness routes
# execution through another CLI (claude, codex, gemini) instead of a direct
# provider HTTP call.
#
# Function signature for all adapters:
#   <fn> <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
# Returns 0 on success, non-zero on failure.

# execute_via_claude_code -- spawn via `claude -p` CLI.
# Uses --system-prompt + --print + --model for non-interactive output.
execute_via_claude_code() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  if ! command -v claude &>/dev/null; then
    log_error "claude CLI not found. Install Claude Code first."
    return 1
  fi

  local sys_content user_content
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"

  local effort_flag=""
  case "$effort" in
    low|medium|high|xhigh|max) effort_flag="--effort $effort" ;;
  esac

  local model_flag=""
  if [[ -n "$model" && "$model" != "default" ]]; then
    model_flag="--model $model"
  fi

  log_info "Spawning via claude -p (model=${model:-default} effort=${effort})"

  # Use --print for non-interactive, --output-format text for clean output.
  # Pass user prompt via stdin; system prompt via flag.
  if printf '%s' "$user_content" | claude -p \
      --system-prompt "$sys_content" \
      --output-format text \
      ${model_flag} \
      ${effort_flag} \
      --dangerously-skip-permissions \
      > "$output_file" 2>/dev/null; then
    return 0
  fi
  log_error "claude -p execution failed"
  return 1
}

# execute_via_codex -- spawn via `codex exec` CLI.
# codex has no --system flag; we embed the system prompt in the user prompt.
# Uses -o/--output-last-message to write the model's final message to file.
execute_via_codex() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  if ! command -v codex &>/dev/null; then
    log_error "codex CLI not found. Install OpenAI Codex CLI first."
    return 1
  fi

  local combined_prompt_file
  combined_prompt_file="$(mktemp /tmp/sh-agent-codex-prompt-XXXXXX.txt)"
  {
    printf '<system>\n'
    cat "$sys_prompt_file"
    printf '\n</system>\n\n<user>\n'
    cat "$user_prompt_file"
    printf '\n</user>\n'
  } > "$combined_prompt_file"

  local model_flag=""
  if [[ -n "$model" && "$model" != "default" ]]; then
    model_flag="-m $model"
  fi

  log_info "Spawning via codex exec (model=${model:-default} sandbox=workspace-write)"

  # Read combined prompt from stdin to keep argv clean.
  if codex exec \
      ${model_flag} \
      --skip-git-repo-check \
      -s workspace-write \
      -o "$output_file" \
      < "$combined_prompt_file" >/dev/null 2>&1; then
    rm -f "$combined_prompt_file"
    return 0
  fi
  rm -f "$combined_prompt_file"
  log_error "codex exec execution failed"
  return 1
}

# execute_via_gemini -- spawn via `gemini -p` CLI.
# gemini has no --system flag; embed system prompt in user prompt.
execute_via_gemini() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  if ! command -v gemini &>/dev/null; then
    log_error "gemini CLI not found. Install Gemini CLI first."
    return 1
  fi

  local sys_content user_content combined
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"
  combined="<system>\n${sys_content}\n</system>\n\n<user>\n${user_content}\n</user>"

  local model_flag=""
  if [[ -n "$model" && "$model" != "default" ]]; then
    model_flag="-m $model"
  fi

  log_info "Spawning via gemini -p (model=${model:-default} yolo=true)"

  if printf '%b' "$combined" | gemini -p "Continue from the system+user prompt provided on stdin." \
      ${model_flag} \
      -y \
      -o text \
      > "$output_file" 2>/dev/null; then
    return 0
  fi
  log_error "gemini -p execution failed"
  return 1
}

# execute_via_ollama_launch -- route ollama through another CLI via `ollama launch`.
# Wraps the chosen integration's CLI args after `--`.
# integration: claude | claude-desktop | codex | cline | copilot | droid | hermes |
#              kimi | opencode | openclaw | pi | pool | vscode (NOT gemini).
execute_via_ollama_launch() {
  local integration="$1"
  local model="$2"
  local effort="$3"
  local sys_prompt_file="$4"
  local user_prompt_file="$5"
  local output_file="$6"

  if ! command -v ollama &>/dev/null; then
    log_error "ollama CLI not found."
    return 1
  fi

  if [[ "$integration" == "gemini" ]]; then
    log_error "ollama launch does not support gemini -- pick a supported integration."
    return 1
  fi

  local sys_content user_content
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"

  log_info "Spawning via ollama launch ${integration} (model=${model})"

  case "$integration" in
    claude)
      # ollama launch claude -- -p "user" --system-prompt "sys" --output-format text
      if printf '%s' "$user_content" | ollama launch claude --model "$model" -y -- \
          -p \
          --system-prompt "$sys_content" \
          --output-format text \
          --dangerously-skip-permissions \
          > "$output_file" 2>/dev/null; then
        return 0
      fi
      ;;
    codex)
      # ollama launch codex -- exec "combined" -s workspace-write -o output
      local combined_prompt_file
      combined_prompt_file="$(mktemp /tmp/sh-agent-launch-codex-XXXXXX.txt)"
      {
        printf '<system>\n%s\n</system>\n\n<user>\n%s\n</user>\n' "$sys_content" "$user_content"
      } > "$combined_prompt_file"

      if ollama launch codex --model "$model" -y -- \
          exec \
          --skip-git-repo-check \
          -s workspace-write \
          -o "$output_file" \
          < "$combined_prompt_file" >/dev/null 2>&1; then
        rm -f "$combined_prompt_file"
        return 0
      fi
      rm -f "$combined_prompt_file"
      ;;
    *)
      # Generic fallback: pass system+user as a single combined prompt to the
      # integration's CLI via stdin. Output goes to stdout -> output_file.
      local combined
      combined="<system>\n${sys_content}\n</system>\n\n<user>\n${user_content}\n</user>"
      if printf '%b' "$combined" | ollama launch "$integration" --model "$model" -y \
          > "$output_file" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  log_error "ollama launch ${integration} execution failed"
  return 1
}

# execute_via_harness <harness-id> <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
# Dispatches to the correct adapter. Returns 0 on success.
execute_via_harness() {
  local harness="$1"
  local model="$2"
  local effort="$3"
  local sys_prompt_file="$4"
  local user_prompt_file="$5"
  local output_file="$6"

  case "$harness" in
    claude-code)
      execute_via_claude_code "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
      return $?
      ;;
    codex)
      execute_via_codex "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
      return $?
      ;;
    gemini)
      execute_via_gemini "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
      return $?
      ;;
    ollama:*)
      local integration="${harness#ollama:}"
      execute_via_ollama_launch "$integration" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
      return $?
      ;;
    *)
      log_error "Unknown harness: $harness"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Provider capability detection
# ---------------------------------------------------------------------------

# Check if a local provider daemon is reachable.
# provider_reachable <provider> [<endpoint>]
# Returns 0 if reachable, 1 if not.
provider_reachable() {
  local provider="$1"
  local endpoint="${2:-}"

  case "$provider" in
    ollama)
      # Check if ollama command exists and daemon is running
      if ! command -v ollama &>/dev/null; then
        return 1
      fi
      # Quick health check -- ollama ps exits 0 when daemon is running
      ollama ps &>/dev/null || return 1
      return 0
      ;;
    lmstudio)
      local ep="${endpoint:-http://localhost:1234}"
      curl -s -f -m 2 "${ep}/v1/models" &>/dev/null || return 1
      return 0
      ;;
    vllm)
      local ep="${endpoint:-http://localhost:8000}"
      curl -s -f -m 2 "${ep}/v1/models" &>/dev/null || return 1
      return 0
      ;;
    llamacpp|localai|jan|text-generation-webui)
      # Generic localhost check -- endpoint required
      if [[ -z "$endpoint" ]]; then
        return 1
      fi
      curl -s -f -m 2 "${endpoint}/v1/models" &>/dev/null || return 1
      return 0
      ;;
    *)
      # External providers are always "reachable" (network assumed)
      # but require egress consent
      return 0
      ;;
  esac
}

# Check if a specific model is available on a provider.
# model_available <provider> <model> [<endpoint>]
# Returns 0 if model exists, 1 if not.
model_available() {
  local provider="$1"
  local model="$2"
  local endpoint="${3:-}"

  case "$provider" in
    ollama)
      # ollama list shows pulled models
      ollama list 2>/dev/null | grep -q "$model" || return 1
      return 0
      ;;
    lmstudio)
      local ep="${endpoint:-http://localhost:1234}"
      local models_json
      models_json="$(curl -s -f -m 2 "${ep}/v1/models" 2>/dev/null)" || return 1
      echo "$models_json" | grep -q "$model" || return 1
      return 0
      ;;
    vllm)
      local ep="${endpoint:-http://localhost:8000}"
      local models_json
      models_json="$(curl -s -f -m 2 "${ep}/v1/models" 2>/dev/null)" || return 1
      echo "$models_json" | grep -q "$model" || return 1
      return 0
      ;;
    *)
      # Cannot check remote models -- assume available
      return 0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Fallback logic
# ---------------------------------------------------------------------------

# Load fallback config for a role from models-config.json.
# get_fallback_config <role>
# Prints: <provider> <model> <effort>
# Returns 1 if no fallback configured for role.
get_fallback_config() {
  local role="$1"
  if [[ -z "$MODELS_JSON" ]]; then
    load_models
  fi

  if command -v jq &>/dev/null; then
    local fb
    fb="$(echo "$MODELS_JSON" | jq -r ".fallback_external.${role} | \"\(.provider) \(.model) \(.effort)\"" 2>/dev/null)"
    if [[ -n "$fb" && "$fb" != "null null null" ]]; then
      echo "$fb"
      return 0
    fi
    # Try default fallback
    fb="$(echo "$MODELS_JSON" | jq -r '.fallback_external.default | "\(.provider) \(.model) \(.effort)"' 2>/dev/null)"
    if [[ -n "$fb" && "$fb" != "null null null" ]]; then
      echo "$fb"
      return 0
    fi
  fi

  return 1
}

# Get effort preset parameters from models-config.json.
# get_effort_params <effort-key>
# Prints: <max_tokens> <thinking> <temperature>
get_effort_params() {
  local effort="$1"
  if [[ -z "$MODELS_JSON" ]]; then
    load_models
  fi

  if command -v jq &>/dev/null; then
    echo "$MODELS_JSON" | jq -r ".effort_presets.${effort} | \"\(.max_tokens) \(.thinking) \(.temperature)\"" 2>/dev/null
  else
    # Fallback defaults
    case "$effort" in
      low)    echo "4096 false 0.2" ;;
      medium) echo "16384 false 0.3" ;;
      high)   echo "65536 true 0.5" ;;
      xhigh)  echo "131072 true 0.6" ;;
      *)      echo "16384 false 0.3" ;;
    esac
  fi
}

# Attempt primary provider (optionally via harness transport), then fall back
# to Anthropic if unavailable. Three-tier fallback: harness -> direct provider
# -> Anthropic fallback (per role).
# execute_with_fallback <agent-name> <role> <provider> <model> <effort> <system-prompt-file> <user-prompt-file> <output-file> [<harness>]
# Returns 0 on success, 1 on all failures.
execute_with_fallback() {
  local agent_name="$1"
  local role="$2"
  local provider="$3"
  local model="$4"
  local effort="$5"
  local sys_prompt_file="$6"
  local user_prompt_file="$7"
  local output_file="$8"
  local harness="${9:-}"

  local provider_class
  provider_class="$(get_provider_class "$provider")"

  # Tier 1: harness transport (if configured)
  if [[ -n "$harness" && "$harness" != "null" && "$harness" != "none" ]]; then
    if detect_harness_cli "$harness"; then
      log_info "Using harness transport: $harness ($provider / $model)"
      if execute_via_harness "$harness" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"; then
        return 0
      fi
      log_warn "Harness transport $harness failed; trying direct provider"
    else
      log_warn "Harness $harness CLI not found on PATH; trying direct provider"
    fi
  fi

  # Tier 2: direct primary provider
  if [[ "$provider_class" == "local" ]]; then
    if provider_reachable "$provider" && model_available "$provider" "$model"; then
      log_info "Using primary provider: $provider / $model"
      execute_provider "$provider" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
      return $?
    fi

    # Primary failed -- attempt fallback
    log_warn "Primary provider $provider / $model unavailable"
  else
    # External provider -- check egress consent
    local agent_file
    agent_file="$(find_agent_file "$agent_name")"
    if [[ -f "$agent_file" ]]; then
      read_agent "$agent_file"
      if [[ "$AGENT_EGRESS_CONSENT" == "none" ]]; then
        log_error "External provider $provider requires egress consent. Grant via: /software-house set-model $agent_name --egress-consent"
        return 1
      fi
    fi
    log_info "Using external provider: $provider / $model"
    execute_provider "$provider" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
    return $?
  fi

  # Fallback to Claude
  local fb_config
  fb_config="$(get_fallback_config "$role")" || {
    log_error "No fallback configured for role '$role' and primary provider unavailable"
    return 1
  }

  local fb_provider fb_model fb_effort
  fb_provider="$(echo "$fb_config" | awk '{print $1}')"
  fb_model="$(echo "$fb_config" | awk '{print $2}')"
  fb_effort="$(echo "$fb_config" | awk '{print $3}')"

  # Check egress consent for fallback
  local agent_file
  agent_file="$(find_agent_file "$agent_name")"
  if [[ -f "$agent_file" ]]; then
    read_agent "$agent_file"
    if [[ "$AGENT_EGRESS_CONSENT" == "none" ]]; then
      log_error "Fallback provider $fb_provider requires egress consent. Grant via: /software-house set-model $agent_name --egress-consent"
      return 1
    fi
  fi

  log_info "Falling back to: $fb_provider / $fb_model (effort: $fb_effort)"

  # Log the fallback event
  local ts
  ts="$(utc_now)"
  local fallback_entry
  fallback_entry="$(json_build \
    "ts" "$(json_str "$ts")" \
    "actor" "$(json_str "system")" \
    "op" "$(json_str "provider-fallback")" \
    "scope" "$(json_str "agent:$agent_name")" \
    "args" "{\"primary_provider\":\"$provider\",\"primary_model\":\"$model\",\"fallback_provider\":\"$fb_provider\",\"fallback_model\":\"$fb_model\",\"fallback_effort\":\"$fb_effort\"}" \
    "result" "$(json_str "ok")" \
  )"
  audit_log "$fallback_entry"

  execute_provider "$fb_provider" "$fb_model" "$fb_effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
  return $?
}

# ---------------------------------------------------------------------------
# Provider dispatch
# ---------------------------------------------------------------------------

# execute_provider <provider> <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
# Routes to the correct provider adapter.
execute_provider() {
  local provider="$1"
  local model="$2"
  local effort="$3"
  local sys_prompt_file="$4"
  local user_prompt_file="$5"
  local output_file="$6"

  # Source the provider adapter if it exists
  local adapter="$SKILL_SRC/lib/providers/${provider}.sh"
  if [[ -f "$adapter" ]]; then
    source "$adapter"
  fi

  # Each adapter must define: provider_execute_<name>
  local exec_func="provider_execute_${provider}"
  if declare -f "$exec_func" &>/dev/null; then
    "$exec_func" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
    return $?
  fi

  # No adapter found -- try generic OpenAI-compatible endpoint
  log_warn "No adapter for provider '$provider', trying generic OpenAI-compatible endpoint"
  provider_execute_generic "$provider" "$model" "$effort" "$sys_prompt_file" "$user_prompt_file" "$output_file"
  return $?
}

# Generic OpenAI-compatible provider execution (fallback for unknown providers).
# provider_execute_generic <provider> <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
provider_execute_generic() {
  local provider="$1"
  local model="$2"
  local effort="$3"
  local sys_prompt_file="$4"
  local user_prompt_file="$5"
  local output_file="$6"

  local endpoint
  endpoint="$(get_provider_endpoint "$provider")"
  if [[ -z "$endpoint" ]]; then
    log_error "No endpoint configured for provider '$provider'"
    return 1
  fi

  local sys_content user_content
  sys_content="$(cat "$sys_prompt_file")"
  user_content="$(cat "$user_prompt_file")"

  local max_tokens thinking_flag temperature
  read -r max_tokens thinking_flag temperature <<< "$(get_effort_params "$effort")"

  local body
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

  local http_code
  http_code="$(curl -s -w "%{http_code}" -o "$output_file" \
    -X POST "${endpoint}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$body" 2>/dev/null)" || {
    log_error "Failed to connect to $provider at $endpoint"
    return 1
  }

  if [[ "$http_code" != "200" ]]; then
    log_error "Provider $provider returned HTTP $http_code"
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

# ---------------------------------------------------------------------------
# Agent file resolution
# ---------------------------------------------------------------------------

# find_agent_file <agent-name>
# Prints the path to the agent's canonical file.
# Checks per-project first, then global freelance pool.
find_agent_file() {
  local name="$1"

  # Per-project agents
  if [[ -n "${TEAM_AGENTS:-}" && -f "$TEAM_AGENTS/${name}.md" ]]; then
    echo "$TEAM_AGENTS/${name}.md"
    return 0
  fi

  # Also check $TEAM_DIR/agents (alternative layout)
  if [[ -n "${TEAM_DIR:-}" && -f "$TEAM_DIR/../agents/${name}.md" ]]; then
    echo "$TEAM_DIR/../agents/${name}.md"
    return 0
  fi

  # Global freelance pool
  if [[ -f "$AGENTS_GLOBAL/${name}.md" ]]; then
    echo "$AGENTS_GLOBAL/${name}.md"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# System prompt construction
# ---------------------------------------------------------------------------

# build_system_prompt <agent-name> <agent-file> [context-pages...]
# Builds a system prompt from the agent's wiki page, project status,
# relevant decisions, and handoff protocol.
# Writes to stdout.
build_system_prompt() {
  local agent_name="$1"
  local agent_file="$2"
  shift 2
  local context_pages=("$@")

  # Read agent frontmatter
  read_agent "$agent_file" || return 1

  # Start building system prompt
  local prompt=""
  prompt+="You are ${agent_name}, a ${AGENT_ROLE} agent"
  [[ -n "$AGENT_TEAM" && "$AGENT_TEAM" != "null" ]] && prompt+=" on the ${AGENT_TEAM} team"
  prompt+=".\n"
  prompt+="Read your wiki page for your responsibilities, experience, and working notes.\n\n"

  # Add wiki page content if it exists
  local wiki_file="$WIKI_PEOPLE/${agent_name}.md"
  if [[ -f "$wiki_file" ]]; then
    prompt+="## Your Wiki Page\n\n"
    prompt+="$(cat "$wiki_file")\n\n"
  fi

  # Add project status / synthesis
  local synthesis_file="$COMPANY_HOME/wiki/synthesis/project-status.md"
  if [[ -f "$synthesis_file" ]]; then
    prompt+="## Project Context\n\n"
    prompt+="$(cat "$synthesis_file")\n\n"
  fi

  # Per-project synthesis
  if [[ -n "${TEAM_DIR:-}" && -f "$TEAM_DIR/wiki/synthesis/project-status.md" ]]; then
    prompt+="## Team Context\n\n"
    prompt+="$(cat "$TEAM_DIR/wiki/synthesis/project-status.md")\n\n"
  fi

  # Add relevant decision pages
  if [[ -d "$WIKI_DECISIONS" ]]; then
    local has_decisions=false
    for dec_file in "$WIKI_DECISIONS"/*.md; do
      [[ -f "$dec_file" ]] || continue
      # Only include decisions that mention this role
      if grep -qi "$AGENT_ROLE" "$dec_file" 2>/dev/null; then
        $has_decisions || { prompt+="## Relevant Decisions\n\n"; has_decisions=true; }
        prompt+="### $(basename "$dec_file" .md)\n\n"
        prompt+="$(cat "$dec_file")\n\n"
      fi
    done
  fi

  # Add handoff protocol and core principles from role template
  if [[ -f "$ROLE_TEMPLATES" ]] && command -v jq &>/dev/null; then
    local principles_json
    principles_json="$(jq -r ".role_templates[\"${AGENT_ROLE}\"].core_principles // []" "$ROLE_TEMPLATES" 2>/dev/null)"
    if [[ "$principles_json" != "[]" && "$principles_json" != "null" ]]; then
      prompt+="## Core Principles (Buddhist Epistemic Methods)\n\n"
      prompt+="You must adhere to the following principles to prevent hallucination, eliminate root causes, and maintain steadiness:\n"
      prompt+="$(echo "$principles_json" | jq -r '.[] | "- \(.)"' 2>/dev/null)\n\n"
    fi

    local handoff_json
    handoff_json="$(jq -r ".role_templates[\"${AGENT_ROLE}\"].handoff_triggers // {}" "$ROLE_TEMPLATES" 2>/dev/null)"
    if [[ "$handoff_json" != "{}" && "$handoff_json" != "null" ]]; then
      prompt+="## Handoff Protocol\n\n"
      prompt+="When your work triggers a handoff event, generate a brief for the relevant roles:\n"
      prompt+="$(echo "$handoff_json" | jq -r 'to_entries | map("  - \(.key): \(.value | join(", "))") | .[]' 2>/dev/null)\n\n"
      prompt+="Write briefs to wiki/handoffs/briefs/<from>-<to>-<timestamp>.md\n\n"
    fi
  fi

  # Add additional context pages if specified
  if (( ${#context_pages[@]} > 0 )); then
    prompt+="## Additional Context\n\n"
    for ctx_page in "${context_pages[@]}"; do
      if [[ -f "$ctx_page" ]]; then
        prompt+="### $(basename "$ctx_page" .md)\n\n"
        prompt+="$(cat "$ctx_page")\n\n"
      fi
    done
  fi

  printf '%b' "$prompt"
}