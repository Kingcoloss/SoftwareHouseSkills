#!/usr/bin/env bash
# providers/ollama.sh -- Ollama provider adapter
# Sources _shared.sh for common helpers.
# Provides: provider_execute_ollama
#
# IMPORTANT: `ollama run` has NO `--system` flag in current releases. The system
# prompt is embedded into the user prompt as a prefix block. To set system
# prompts at the model level, users must build a custom Modelfile.

# provider_execute_ollama <model> <effort> <sys-prompt-file> <user-prompt-file> <output-file>
provider_execute_ollama() {
  local model="$1"
  local effort="$2"
  local sys_prompt_file="$3"
  local user_prompt_file="$4"
  local output_file="$5"

  if ! command -v ollama &>/dev/null; then
    log_error "ollama command not found. Install Ollama first."
    return 1
  fi

  # Embed system prompt as a prefix block in the user prompt.
  # ollama run does not support a --system CLI flag; modelfile is the alternative.
  local combined_prompt_file
  combined_prompt_file="$(mktemp /tmp/sh-agent-ollama-prompt-XXXXXX.txt)"

  {
    printf '<<SYSTEM>>\n'
    cat "$sys_prompt_file"
    printf '\n<<END_SYSTEM>>\n\n'
    printf '<<USER>>\n'
    cat "$user_prompt_file"
    printf '\n<<END_USER>>\n'
  } > "$combined_prompt_file"

  # Map effort to think mode (only for high/xhigh; some models reject --think).
  local think_arg=""
  case "$effort" in
    xhigh|high) think_arg="--think=high" ;;
    medium)     think_arg="--think=medium" ;;
    *)          think_arg="" ;;
  esac

  # Try with --think first if requested; on failure retry without (model may not support it).
  if [[ -n "$think_arg" ]]; then
    if ollama run "$model" "$think_arg" --hidethinking --nowordwrap < "$combined_prompt_file" > "$output_file" 2>/dev/null; then
      rm -f "$combined_prompt_file"
      return 0
    fi
    log_warn "ollama run with $think_arg failed; retrying without --think"
  fi

  if ollama run "$model" --nowordwrap < "$combined_prompt_file" > "$output_file" 2>/dev/null; then
    rm -f "$combined_prompt_file"
    return 0
  fi

  local rc=$?
  rm -f "$combined_prompt_file"
  log_error "Ollama execution failed (exit code: $rc)"
  return 1
}
