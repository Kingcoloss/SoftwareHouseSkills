#!/usr/bin/env bash
# _shared.sh -- shared library for software-house operations
# Sourced by bin/software-house and lib/operations/*.sh
# Read operations/_shared.md for the canonical spec this code implements.

set -euo pipefail

# ---------------------------------------------------------------------------
# Path constants (mirrors _shared.md section 2)
# ---------------------------------------------------------------------------
: "${SH_HOME:=$HOME/.software-house}"
: "${COMPANY_HOME:=$SH_HOME/company}"
: "${DEPARTMENTS_HOME:=$SH_HOME/departments}"
: "${AGENTS_GLOBAL:=$SH_HOME/agents}"
: "${AUDIT_LOG:=$COMPANY_HOME/audit.log}"
: "${COMPANY_INDEX:=$COMPANY_HOME/index.md}"
: "${WIKI_PEOPLE:=$COMPANY_HOME/wiki/people}"
: "${WIKI_TEAMS:=$COMPANY_HOME/wiki/teams}"
: "${WIKI_DEPTS:=$COMPANY_HOME/wiki/departments}"
: "${ALUMNI:=$COMPANY_HOME/alumni}"
: "${OUTSOURCE_MANIFEST:=$COMPANY_HOME/outsource/manifest.json}"
: "${PROJECTS_INDEX:=$SH_HOME/projects-index.json}"
: "${CONFIG_HOME:=$SH_HOME/config}"
: "${PROVIDERS_CONFIG:=$CONFIG_HOME/providers.json}"
: "${MODELS_CONFIG:=$CONFIG_HOME/models-config.json}"
: "${TOOLS_CONFIG:=$CONFIG_HOME/tools-config.json}"
: "${TOOLS_LOCAL:=$CONFIG_HOME/tools-config.local.json}"

# Per-team paths (resolved at runtime based on PROJECT)
: "${TEAM_DIR:=$PROJECT/.software-house/team}"
: "${TEAM_SPRINTS:=$TEAM_DIR/sprints}"
: "${TEAM_BACKLOG:=$TEAM_DIR/backlog.md}"
: "${TEAM_PLANS:=$TEAM_DIR/plans}"

# Skill source directory (where this file lives)
SKILL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="$SKILL_SRC/schemas"
OPERATIONS_DIR="$SKILL_SRC/operations"
TEMPLATES_DIR="$SKILL_SRC/templates"
CONFIG_SRC_DIR="$SKILL_SRC/config"

# ---------------------------------------------------------------------------
# Logging (mirrors _shared.md section 11)
# ---------------------------------------------------------------------------
log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf "[%-5s] [%s] %s\n" "$level" "$ts" "$msg" >&2
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Name validation (mirrors _shared.md section 10)
# ---------------------------------------------------------------------------
# Valid name: ^[a-z][a-z0-9-]{0,63}$
validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]{0,63}$ ]]; then
    log_error "Invalid name '$name'. Must match ^[a-z][a-z0-9-]{0,63}\$"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Confirm / safety gate (mirrors safety.md sections 1-3, 9)
# ---------------------------------------------------------------------------
# confirm <tier> <subject-name>
# tier: 1 = no prompt, 2 = y/n, 3 = y/n with warning, 4 = two-step typed CONFIRM
# Returns 0 if confirmed, 1 if aborted.
# For tier 1: always returns 0 (no prompt).
# For tier 2-3: reads one line from stdin, checks for affirmative tokens.
# For tier 4: two-step - first affirmative, then typed CONFIRM <subject>.
confirm() {
  local tier="$1"
  local subject="${2:-}"

  case "$tier" in
    1)
      # Read-only, no confirmation needed
      return 0
      ;;
    2)
      printf '+----------------------------------------------------------+\n'
      printf '| I will create the new files listed above.                |\n'
      printf '| Reply '"'"'yes'"'"' to proceed, or anything else to cancel.      |\n'
      printf '+----------------------------------------------------------+\n'
      read -r response
      if is_affirmative "$response"; then
        return 0
      fi
      printf 'Cancelled. No changes made.\n'
      return 1
      ;;
    3)
      printf '+----------------------------------------------------------+\n'
      printf '| I will apply the diff above to existing files.           |\n'
      printf '| Reply '"'"'yes'"'"' to proceed, or anything else to cancel.      |\n'
      printf '+----------------------------------------------------------+\n'
      read -r response
      if is_affirmative "$response"; then
        return 0
      fi
      printf 'Cancelled. No changes made.\n'
      return 1
      ;;
    4)
      # Step 1: impact disclosure + intent check
      printf '+----------------------------------------------------------+\n'
      printf '| Destructive operation on %s.                      |\n' "$subject"
      printf '| Files will be MOVED to archive (recovery path printed).  |\n'
      printf '| Reply '"'"'yes'"'"' to advance to the typed-token step.          |\n'
      printf '+----------------------------------------------------------+\n'
      read -r response
      if ! is_affirmative "$response"; then
        printf 'Cancelled. No changes made.\n'
        return 1
      fi

      # Step 2: typed token CONFIRM <subject>
      printf '+----------------------------------------------------------+\n'
      printf '| To proceed, type the literal token on the next line:     |\n'
      printf '|   CONFIRM %s                                         |\n' "$subject"
      printf '| Anything else, or no response, will cancel.              |\n'
      printf '+----------------------------------------------------------+\n'
      read -r token_response
      if [[ "$token_response" == *"CONFIRM $subject"* ]]; then
        return 0
      fi
      printf 'Cancelled. Token did not match. No changes made.\n'
      return 1
      ;;
    *)
      log_error "Unknown tier: $tier"
      return 1
      ;;
  esac
}

# Check if a response is affirmative per safety.md section 9
# Accepts (case-insensitive): yes, y, proceed, ok, Yes/OK/Y
# Rejects if contains whole-word: no, cancel, stop, abort, wait, n, nope
is_affirmative() {
  local response="$1"
  local lower
  lower="$(echo "$response" | tr '[:upper:]' '[:lower:]')"

  # Check for rejection words first (whole-word matching)
  local reject_words="no cancel stop abort wait n nope"
  for word in $reject_words; do
    if [[ "$lower" =~ (^|[[:space:]])"$word"($|[[:space:]]|[[:punct:]]) ]]; then
      return 1
    fi
  done

  # Check for affirmative first word
  local first_word
  first_word="${lower%%[[:space:]]*}"
  case "$first_word" in
    yes|y|proceed|ok) return 0 ;;
    "yes,") return 0 ;; # "Yes, proceed" case handled below
  esac

  # Check for exact "yes, proceed" (case-insensitive)
  if [[ "$lower" == "yes, proceed" ]]; then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Egress consent gate (mirrors safety.md section 3, special tier)
# ---------------------------------------------------------------------------
# egress_consent <provider> <endpoint>
# Returns 0 if consent granted, 1 if not.
egress_consent() {
  local provider="$1"
  local endpoint="$2"

  printf '+----------------------------------------------------------+\n'
  printf '| WARNING -- External provider selected: %s        |\n' "$provider"
  printf '| When this agent runs, its conversations will be sent to: |\n'
  printf '|   %s                         |\n' "$endpoint"
  printf '| This egress is performed by the agent runtime, not by    |\n'
  printf '| this skill. The skill itself never makes network calls.  |\n'
  printf '|                                                          |\n'
  printf '| To approve this egress, type the literal token:          |\n'
  printf '|   EGRESS-CONSENT-%s                              |\n' "$provider"
  printf '| Anything else, or no response, will cancel the hire.     |\n'
  printf '+----------------------------------------------------------+\n'

  read -r consent_response
  if [[ "$consent_response" == *"EGRESS-CONSENT-$provider"* ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Require tier (mirrors safety.md section 1)
# ---------------------------------------------------------------------------
# require_tier <required-tier> <actual-tier>
# Ensures the actual tier is at least the required tier.
require_tier() {
  local required="$1"
  local actual="$2"
  if (( actual < required )); then
    log_error "Operation requires tier $required but is only tier $actual."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Agent file I/O (mirrors _shared.md section 6, 7)
# ---------------------------------------------------------------------------

# Read YAML frontmatter from a markdown file into associative array.
# Usage: read_agent <file-path>
# Sets global variables: AGENT_NAME, AGENT_PROVIDER, AGENT_MODEL, etc.
# Simple implementation: extract fields using grep/sed.
read_agent() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Agent file not found: $file"
    return 1
  fi

  # Extract frontmatter between --- delimiters
  local in_fm=false
  local fm_content=""
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if $in_fm; then
        break
      fi
      in_fm=true
      continue
    fi
    if $in_fm; then
      fm_content+="$line"$'\n'
    fi
  done < "$file"

  # Parse key fields into global variables
  AGENT_NAME="$(echo "$fm_content" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//' || echo "")"
  AGENT_DESCRIPTION="$(echo "$fm_content" | grep '^description:' | head -1 | sed 's/^description:[[:space:]]*//' || echo "")"
  AGENT_PROVIDER="$(echo "$fm_content" | grep '^provider:' | head -1 | sed 's/^provider:[[:space:]]*//' || echo "")"
  AGENT_MODEL="$(echo "$fm_content" | grep '^model:' | head -1 | sed 's/^model:[[:space:]]*//' || echo "")"
  AGENT_EGRESS_CONSENT="$(echo "$fm_content" | grep '^egress_consent:' | head -1 | sed 's/^egress_consent:[[:space:]]*//' || echo "none")"
  AGENT_EMPLOYEE_ID="$(echo "$fm_content" | grep '^employee_id:' | head -1 | sed 's/^employee_id:[[:space:]]*//' || echo "")"
  AGENT_TEAM="$(echo "$fm_content" | grep '^team:' | head -1 | sed 's/^team:[[:space:]]*//' || echo "null")"
  AGENT_DEPARTMENT="$(echo "$fm_content" | grep '^department:' | head -1 | sed 's/^department:[[:space:]]*//' || echo "null")"
  AGENT_ROLE="$(echo "$fm_content" | grep '^role:' | head -1 | sed 's/^role:[[:space:]]*//' || echo "")"
  AGENT_POSITION="$(echo "$fm_content" | grep '^position:' | head -1 | sed 's/^position:[[:space:]]*//' || echo "")"
  AGENT_REPORTS_TO="$(echo "$fm_content" | grep '^reports_to:' | head -1 | sed 's/^reports_to:[[:space:]]*//' || echo "null")"
  AGENT_STATUS="$(echo "$fm_content" | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' || echo "")"
  AGENT_HIRED_AT="$(echo "$fm_content" | grep '^hired_at:' | head -1 | sed 's/^hired_at:[[:space:]]*//' || echo "")"
  AGENT_LEVEL="$(echo "$fm_content" | grep '^level:' | head -1 | sed 's/^level:[[:space:]]*//' || echo "1")"
  AGENT_XP="$(echo "$fm_content" | grep '^xp:' | head -1 | sed 's/^xp:[[:space:]]*//' || echo "0")"
  AGENT_EFFORT_PRESET="$(echo "$fm_content" | grep '^effort_preset:' | head -1 | sed 's/^effort_preset:[[:space:]]*//' || echo "medium")"
  AGENT_CLASSIFICATION="$(echo "$fm_content" | grep '^classification:' | head -1 | sed 's/^classification:[[:space:]]*//' || echo "internal")"
  AGENT_BUDDY="$(echo "$fm_content" | grep '^buddy:' | head -1 | sed 's/^buddy:[[:space:]]*//' || echo "null")"
  AGENT_EMPLOYMENT="$(echo "$fm_content" | grep '^employment:' | head -1 | sed 's/^employment:[[:space:]]*//' || echo "permanent")"
  AGENT_ACHIEVEMENTS="$(echo "$fm_content" | grep '^achievements:' | head -1 | sed 's/^achievements:[[:space:]]*//' || echo "[]")"
  AGENT_ONBOARD_AT="$(echo "$fm_content" | grep '^onboard_at:' | head -1 | sed 's/^onboard_at:[[:space:]]*//' || echo "null")"
  AGENT_ONBOARD_STATUS="$(echo "$fm_content" | grep '^onboard_status:' | head -1 | sed 's/^onboard_status:[[:space:]]*//' || echo "null")"
  AGENT_SECONDARY_TEAMS="$(echo "$fm_content" | grep '^secondary_teams:' | head -1 | sed 's/^secondary_teams:[[:space:]]*//' || echo "[]")"
  AGENT_UPDATED_AT="$(echo "$fm_content" | grep '^updated_at:' | head -1 | sed 's/^updated_at:[[:space:]]*//' || echo "null")"
}

# Write a YAML frontmatter field update using sed.
# This is a simplified version -- production code would use a proper YAML library.
# write_agent_field <file> <field> <new-value>
write_agent_field() {
  local file="$1"
  local field="$2"
  local new_value="$3"

  if [[ ! -f "$file" ]]; then
    log_error "Cannot update field in non-existent file: $file"
    return 1
  fi

  # Atomic write pattern: write to .tmp, verify, mv
  local tmp="${file}.tmp"
  cp "$file" "$tmp"

  if grep -q "^${field}:" "$tmp"; then
    # Replace existing field
    sed -i "s|^${field}:.*|${field}: ${new_value}|" "$tmp"
  else
    # Add field after the first --- line
    sed -i "/^---$/a\\
${field}: ${new_value}" "$tmp"
  fi

  # Verify the temp file still has valid frontmatter (basic check)
  if ! head -1 "$tmp" | grep -q "^---"; then
    rm -f "$tmp"
    log_error "Atomic write verification failed for $file"
    return 1
  fi

  mv "$tmp" "$file"
}

# Write a complete agent file with frontmatter and body.
# write_agent <file> <frontmatter-content> <body-content>
write_agent() {
  local file="$1"
  local fm="$2"
  local body="$3"

  local tmp="${file}.tmp"
  {
    printf '---\n'
    printf '%s\n' "$fm"
    printf '---\n'
    printf '%s\n' "$body"
  } > "$tmp"

  # Verify
  if ! head -1 "$tmp" | grep -q "^---"; then
    rm -f "$tmp"
    log_error "Agent file verification failed for $file"
    return 1
  fi

  mv "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# Agent validation against JSON Schema (mirrors schemas/agent.json)
# ---------------------------------------------------------------------------
# validate_agent <agent-file>
# Uses jq to extract frontmatter as JSON and validate against agent.json.
validate_agent() {
  local file="$1"

  if ! command -v jq &>/dev/null; then
    log_warn "jq not found -- skipping schema validation for $file"
    return 0
  fi

  if [[ ! -f "$SCHEMA_DIR/agent.json" ]]; then
    log_warn "Schema file not found: $SCHEMA_DIR/agent.json -- skipping validation"
    return 0
  fi

  # Extract YAML frontmatter and convert to JSON (simplified)
  # A proper implementation would use yq or a YAML-to-JSON converter.
  # For now, basic key:value extraction.
  local in_fm=false
  local json_parts=()
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if $in_fm; then break; fi
      in_fm=true
      continue
    fi
    if $in_fm && [[ "$line" =~ ^[a-z_]+: ]]; then
      local key="${line%%:*}"
      local val="${line#*: }"
      # Trim whitespace
      val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      json_parts+=("\"$key\": $(yaml_val_to_json "$val")")
    fi
  done < "$file"

  local json="{"
  json+="$(IFS=,; echo "${json_parts[*]}")"
  json+="}"

  # Validate against schema using jq
  # TODO: Full JSON Schema validation requires ajv or similar; jq cannot do full draft-07 validation.
  # For now, check required fields exist.
  local required_fields="name description provider model egress_consent employee_id role position status hired_at level xp effort_preset classification employment"
  local missing=()
  for field in $required_fields; do
    if ! echo "$json" | jq -e --arg f "$field" 'has($f)' &>/dev/null; then
      missing+=("$field")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log_error "Agent validation failed for $file. Missing required fields: ${missing[*]}"
    return 1
  fi

  return 0
}

# Convert a YAML scalar value to JSON representation
yaml_val_to_json() {
  local val="$1"
  if [[ "$val" == "null" ]]; then
    echo "null"
  elif [[ "$val" =~ ^[0-9]+$ ]]; then
    echo "$val"
  elif [[ "$val" == "true" || "$val" == "false" ]]; then
    echo "$val"
  elif [[ "$val" == "[]" ]]; then
    echo "[]"
  elif [[ "$val" == "{}" ]]; then
    echo "{}"
  elif [[ "$val" =~ ^\" ]]; then
    echo "$val"
  else
    # String value -- wrap in quotes, escape internal quotes
    local escaped
    escaped="$(echo "$val" | sed 's/"/\\"/g')"
    echo "\"$escaped\""
  fi
}

# ---------------------------------------------------------------------------
# Config loading (mirrors _shared.md, providers.json, models-config.json)
# ---------------------------------------------------------------------------

# Load providers config, merging with *.local.json if present.
# Sets PROVIDERS_JSON global.
load_providers() {
  if [[ ! -f "$PROVIDERS_CONFIG" ]]; then
    log_error "providers.json not found at $PROVIDERS_CONFIG"
    return 1
  fi
  PROVIDERS_JSON="$(cat "$PROVIDERS_CONFIG")"

  # Overlay with local config if present
  if [[ -f "${PROVIDERS_CONFIG%.json}.local.json" ]]; then
    if command -v jq &>/dev/null; then
      local local_config
      local_config="$(cat "${PROVIDERS_CONFIG%.json}.local.json")"
      PROVIDERS_JSON="$(echo "$PROVIDERS_JSON" | jq -s '.[0] * .[1]' - <(echo "$local_config") 2>/dev/null || echo "$PROVIDERS_JSON")"
    fi
  fi
}

# Get provider class (local or external) from loaded config.
# get_provider_class <provider-key>
get_provider_class() {
  local provider="$1"
  if command -v jq &>/dev/null; then
    echo "$PROVIDERS_JSON" | jq -r ".providers.${provider}.class // empty" 2>/dev/null
  else
    # Fallback without jq: grep for the class
    grep -A3 "\"${provider}\"" "$PROVIDERS_CONFIG" 2>/dev/null | grep '"class"' | head -1 | sed 's/.*"class"[[:space:]]*:[[:space:]]*"//' | sed 's/".*//'
  fi
}

# Get provider default endpoint from loaded config.
# get_provider_endpoint <provider-key>
get_provider_endpoint() {
  local provider="$1"
  if command -v jq &>/dev/null; then
    echo "$PROVIDERS_JSON" | jq -r ".providers.${provider}.default_endpoint // empty" 2>/dev/null
  else
    grep -A5 "\"${provider}\"" "$PROVIDERS_CONFIG" 2>/dev/null | grep '"default_endpoint"' | head -1 | sed 's/.*"default_endpoint"[[:space:]]*:[[:space:]]*"//' | sed 's/".*//'
  fi
}

# Load models config, merging with *.local.json if present.
# Sets MODELS_JSON global.
load_models() {
  if [[ ! -f "$MODELS_CONFIG" ]]; then
    log_error "models-config.json not found at $MODELS_CONFIG"
    return 1
  fi
  MODELS_JSON="$(cat "$MODELS_CONFIG")"

  # Overlay with local config if present
  if [[ -f "${MODELS_CONFIG%.json}.local.json" ]]; then
    if command -v jq &>/dev/null; then
      local local_config
      local_config="$(cat "${MODELS_CONFIG%.json}.local.json")"
      MODELS_JSON="$(echo "$MODELS_JSON" | jq -s '.[0] * .[1]' - <(echo "$local_config") 2>/dev/null || echo "$MODELS_JSON")"
    fi
  fi
}

# Get role defaults from loaded models config.
# get_role_defaults <role-key>
# Prints: provider model effort
get_role_defaults() {
  local role="$1"
  if command -v jq &>/dev/null; then
    echo "$MODELS_JSON" | jq -r ".defaults_by_role.${role} | \"\(.provider) \(.model) \(.effort)\"" 2>/dev/null
  else
    # Fallback: grep from the file
    grep -A3 "\"${role}\"" "$MODELS_CONFIG" 2>/dev/null | grep -E '"(provider|model|effort)"' | sed 's/.*: "//;s/".*//' | tr '\n' ' '
  fi
}

# List valid role keys from models config.
list_roles() {
  if command -v jq &>/dev/null; then
    echo "$MODELS_JSON" | jq -r '.defaults_by_role | keys[]' 2>/dev/null
  else
    grep -E '^\s+"[a-z]' "$MODELS_CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/'
  fi
}

# List valid provider keys from providers config.
list_providers() {
  if command -v jq &>/dev/null; then
    echo "$PROVIDERS_JSON" | jq -r '.providers | keys[]' 2>/dev/null
  else
    grep -E '^\s+"[a-z]' "$PROVIDERS_CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/'
  fi
}

# Load config files (convenience for operations that need both).
load_config() {
  load_providers
  load_models
}

# ---------------------------------------------------------------------------
# Tools configuration (mirrors _shared.md section 16)
# ---------------------------------------------------------------------------

# Load tools config (base + local overlay).
TOOLS_JSON=""
load_tools() {
  if [[ ! -f "$TOOLS_CONFIG" ]]; then
    log_error "tools-config.json not found at $TOOLS_CONFIG"
    return 1
  fi
  if command -v jq &>/dev/null; then
    TOOLS_JSON="$(cat "$TOOLS_CONFIG")"
    if [[ -f "$TOOLS_LOCAL" ]]; then
      # Merge overlay on top of base
      local overlay
      overlay="$(cat "$TOOLS_LOCAL")"
      # Merge shared_tools and role_tools from overlay
      local shared_base shared_overlay shared_merged
      shared_base="$(echo "$TOOLS_JSON" | jq -c '.shared_tools // []')"
      shared_overlay="$(echo "$overlay" | jq -c '.shared_tools // []')"
      shared_merged="$(echo "$shared_base $shared_overlay" | jq -s '.[0] + .[1] | unique')"
      local role_base role_overlay role_merged
      role_base="$(echo "$TOOLS_JSON" | jq -c '.role_tools // {}')"
      role_overlay="$(echo "$overlay" | jq -c '.role_tools // {}')"
      role_merged="$(echo "$role_base" | jq -c --argjson overlay "$role_overlay" '. * $overlay')"
      TOOLS_JSON="$(echo "$TOOLS_JSON" | jq -c --argjson shared "$shared_merged" --argjson roles "$role_merged" '.shared_tools = $shared | .role_tools = $roles')"
    fi
  else
    TOOLS_JSON="$(cat "$TOOLS_CONFIG")"
  fi
}

# Get shared tools array (prints one tool per line).
get_shared_tools() {
  if [[ -z "$TOOLS_JSON" ]]; then
    load_tools
  fi
  if command -v jq &>/dev/null; then
    echo "$TOOLS_JSON" | jq -r '.shared_tools[]' 2>/dev/null
  else
    grep -A100 '"shared_tools"' "$TOOLS_CONFIG" 2>/dev/null | grep '"[a-z-]*"' | sed 's/.*"\([a-z-]*\)".*/\1/'
  fi
}

# Get role-specific tools array (prints one tool per line).
# get_role_tools <role-key>
get_role_tools() {
  local role="$1"
  if [[ -z "$TOOLS_JSON" ]]; then
    load_tools
  fi
  if command -v jq &>/dev/null; then
    echo "$TOOLS_JSON" | jq -r ".role_tools.${role}[] // empty" 2>/dev/null
  else
    grep -A5 "\"${role}\"" "$TOOLS_CONFIG" 2>/dev/null | grep '"[a-z-]*"' | sed 's/.*"\([a-z-]*\)".*/\1/'
  fi
}

# Resolve full tool list for a role (shared + role-specific, deduplicated).
# resolve_agent_tools <role-key>
# Prints: comma-separated canonical tool names
resolve_agent_tools() {
  local role="$1"
  local tools=""
  # Start with shared tools
  tools="$(get_shared_tools | tr '\n' ',' | sed 's/,$//')"
  # Add role-specific tools
  local role_tools
  role_tools="$(get_role_tools "$role" | tr '\n' ',' | sed 's/,$//')"
  if [[ -n "$role_tools" ]]; then
    if [[ -n "$tools" ]]; then
      tools="${tools},${role_tools}"
    else
      tools="$role_tools"
    fi
  fi
  # Deduplicate while preserving order
  local seen="" result=""
  IFS=',' read -ra arr <<< "$tools"
  for t in "${arr[@]}"; do
    if [[ -n "$t" ]] && ! echo "$seen" | grep -qw "$t"; then
      if [[ -n "$result" ]]; then
        result="${result},$t"
      else
        result="$t"
      fi
      seen="$seen $t"
    fi
  done
  echo "$result"
}

# ---------------------------------------------------------------------------
# Audit log (mirrors _shared.md section 5)
# ---------------------------------------------------------------------------

# Append a JSONL entry to the audit log.
# audit_log <json-string>
audit_log() {
  local entry="$1"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  printf '%s\n' "$entry" >> "$AUDIT_LOG"
}

# Build a JSON object from key-value pairs.
# json_build key1 val1 key2 val2 ...
# Arrays and objects should be pre-formatted as JSON strings.
json_build() {
  local result="{"
  local first=true
  while (( $# >= 2 )); do
    local key="$1"; shift
    local val="$1"; shift
    if ! $first; then result+=","; fi
    first=false
    result+="\"$key\":$val"
  done
  result+="}"
  echo "$result"
}

# Quote a string value for JSON.
json_str() {
  local val="$1"
  # Escape backslashes and double-quotes
  val="$(echo "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  echo "\"$val\""
}

# ---------------------------------------------------------------------------
# Time helpers (mirrors _shared.md section 9)
# ---------------------------------------------------------------------------
utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

utc_date() {
  date -u +"%Y-%m-%d"
}

utc_timestamp_compact() {
  date -u +"%Y%m%dT%H%M%SZ"
}

# ---------------------------------------------------------------------------
# Project detection (mirrors _shared.md section 4)
# ---------------------------------------------------------------------------

# Find team for the current working directory.
# Returns team name or empty string if not found.
detect_team() {
  if [[ ! -f "$PROJECTS_INDEX" ]]; then
    return 0
  fi
  local pwd_path
  pwd_path="$(pwd)"
  if command -v jq &>/dev/null; then
    jq -r --arg p "$pwd_path" '.projects | to_entries[] | select(.key == $p) | .value.team' "$PROJECTS_INDEX" 2>/dev/null | head -1
  else
    # Fallback: grep
    grep "$pwd_path" "$PROJECTS_INDEX" 2>/dev/null | head -1 | sed 's/.*"team"[[:space:]]*:[[:space:]]*"//; s/".*//'
  fi
}

# ---------------------------------------------------------------------------
# Harness detection (mirrors _shared.md section 3, init.md step 2)
# ---------------------------------------------------------------------------
HAS_CLAUDE_CODE=0
HAS_CODEX=0
HAS_GEMINI=0

detect_harnesses() {
  [[ -d "$HOME/.claude" ]] && HAS_CLAUDE_CODE=1 || HAS_CLAUDE_CODE=0
  { [[ -d "$HOME/.codex" ]] || [[ -d "$HOME/.agents" ]]; } && HAS_CODEX=1 || HAS_CODEX=0
  [[ -d "$HOME/.gemini" ]] && HAS_GEMINI=1 || HAS_GEMINI=0
}

# ---------------------------------------------------------------------------
# Next employee ID (mirrors hire.md step 6)
# ---------------------------------------------------------------------------
next_employee_id() {
  local count=0
  if [[ -d "$WIKI_PEOPLE" ]]; then
    count=$(( count + $(find "$WIKI_PEOPLE" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ') ))
  fi
  if [[ -d "$AGENTS_GLOBAL" ]]; then
    count=$(( count + $(find "$AGENTS_GLOBAL" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ') ))
  fi
  count=$(( count + 1 ))
  printf 'emp-%03d' "$count"
}

# ---------------------------------------------------------------------------
# Index rebuild (mirrors _shared.md section 8)
# ---------------------------------------------------------------------------
# rebuild_index <index-file> <wiki-dir>
# Generates a simple markdown index from the wiki directory.
rebuild_index() {
  local index_file="$1"
  local wiki_dir="$2"
  local header="${3:-Wiki Index}"

  local tmp="${index_file}.tmp"
  {
    printf '# %s\n\n' "$header"
    printf 'This index is auto-generated by the software-house skill. Do not edit\n'
    printf 'directly -- your changes will be overwritten on the next rebuild.\n\n'

    # Group entries
    local sections=("People" "Teams" "Departments" "Synthesis")
    for section in "${sections[@]}"; do
      local subdir="$wiki_dir/$(echo "$section" | tr '[:upper:]' '[:lower:]')"
      printf '## %s\n\n' "$section"
      if [[ -d "$subdir" ]]; then
        local found=0
        for f in "$subdir"/*.md; do
          [[ -f "$f" ]] || continue
          found=1
          local name
          name="$(basename "$f" .md)"
          local desc=""
          if command -v jq &>/dev/null; then
            desc="$(head -20 "$f" | grep '^description:' | head -1 | sed 's/^description:[[:space:]]*//')"
          else
            desc="$(head -20 "$f" | grep '^description:' | head -1 | sed 's/^description:[[:space:]]*//')"
          fi
          printf '- [%s](%s/%s.md) -- %s\n' "$name" "$(echo "$section" | tr '[:upper:]' '[:lower:]')" "$name" "$desc"
        done
        if (( ! found )); then
          printf '(none yet)\n'
        fi
      else
        printf '(none yet)\n'
      fi
      printf '\n'
    done
  } > "$tmp"

  mv "$tmp" "$index_file"
}

# ---------------------------------------------------------------------------
# Dry-run support
# ---------------------------------------------------------------------------
DRY_RUN=0

dry_run_msg() {
  if (( DRY_RUN )); then
    printf '[DRY-RUN] %s\n' "$*"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Company initialization check
# ---------------------------------------------------------------------------
require_company_init() {
  if [[ ! -d "$COMPANY_HOME" ]]; then
    printf 'Error: company not initialized. Run /software-house init first.\n'
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Sprint and Backlog helpers (mirrors _shared.md section 17)
# ---------------------------------------------------------------------------

# Get the next sprint ID by scanning the sprints directory.
next_sprint_id() {
  local max_id=0
  if [[ -d "$TEAM_SPRINTS" ]]; then
    for d in "$TEAM_SPRINTS"/sprint-*/; do
      local id
      id="$(basename "$d" | sed 's/sprint-//')"
      id="${id%%[!0-9]*}"
      if [[ -n "$id" ]] && (( id > max_id )); then
        max_id=$id
      fi
    done
  fi
  printf 'sprint-%03d' $((max_id + 1))
}

# Get the next backlog item ID from the backlog frontmatter.
next_backlog_item_id() {
  local next_id=1
  if [[ -f "$TEAM_BACKLOG" ]]; then
    next_id=$(grep '^next_id:' "$TEAM_BACKLOG" 2>/dev/null | sed 's/next_id:[[:space:]]*//')
    next_id="${next_id:-1}"
  fi
  printf 'item-%03d' "$next_id"
}

# Read sprint frontmatter into variables.
# read_sprint <sprint-id>
# Sets: SPRINT_ID, SPRINT_NAME, SPRINT_GOAL, SPRINT_START, SPRINT_END, SPRINT_STATUS, SPRINT_PLAN_ID
read_sprint() {
  local sprint_id="$1"
  local sprint_file="$TEAM_SPRINTS/$sprint_id/sprint.md"
  if [[ ! -f "$sprint_file" ]]; then
    log_error "Sprint $sprint_id not found at $sprint_file"
    return 1
  fi
  SPRINT_ID=$(grep '^id:' "$sprint_file" | sed 's/id:[[:space:]]*//')
  SPRINT_NAME=$(grep '^name:' "$sprint_file" | sed 's/name:[[:space:]]*//')
  SPRINT_GOAL=$(grep '^goal:' "$sprint_file" | sed 's/goal:[[:space:]]*//')
  SPRINT_START=$(grep '^start_date:' "$sprint_file" | sed 's/start_date:[[:space:]]*//')
  SPRINT_END=$(grep '^end_date:' "$sprint_file" | sed 's/end_date:[[:space:]]*//')
  SPRINT_STATUS=$(grep '^status:' "$sprint_file" | sed 's/status:[[:space:]]*//')
  SPRINT_PLAN_ID=$(grep '^plan_id:' "$sprint_file" | sed 's/plan_id:[[:space:]]*//')
}

# ---------------------------------------------------------------------------
# Plan helpers (mirrors _shared.md section 18)
# ---------------------------------------------------------------------------

# Get the next plan ID by scanning the plans directory.
next_plan_id() {
  local max_id=0
  if [[ -d "$TEAM_PLANS" ]]; then
    for d in "$TEAM_PLANS"/plan-*/; do
      local id
      id="$(basename "$d" | sed 's/plan-//')"
      id="${id%%[!0-9]*}"
      if [[ -n "$id" ]] && (( id > max_id )); then
        max_id=$id
      fi
    done
  fi
  printf 'plan-%03d' $((max_id + 1))
}

# Read plan frontmatter into variables.
# read_plan <plan-id>
# Sets: PLAN_ID, PLAN_NAME, PLAN_STATUS, PLAN_CREATED_BY, PLAN_SPRINT_ID
read_plan() {
  local plan_id="$1"
  local plan_file="$TEAM_PLANS/$plan_id/plan.md"
  if [[ ! -f "$plan_file" ]]; then
    log_error "Plan $plan_id not found at $plan_file"
    return 1
  fi
  PLAN_ID=$(grep '^id:' "$plan_file" | sed 's/id:[[:space:]]*//')
  PLAN_NAME=$(grep '^name:' "$plan_file" | sed 's/name:[[:space:]]*//')
  PLAN_STATUS=$(grep '^status:' "$plan_file" | head -1 | sed 's/status:[[:space:]]*//')
  PLAN_CREATED_BY=$(grep '^created_by:' "$plan_file" | sed 's/created_by:[[:space:]]*//')
  PLAN_SPRINT_ID=$(grep '^sprint_id:' "$plan_file" | sed 's/sprint_id:[[:space:]]*//')
}

# Topological sort of tasks by dependencies.
# Reads plan frontmatter tasks and outputs task IDs in execution order.
# topological_sort <plan-id>
topological_sort() {
  local plan_id="$1"
  local plan_file="$TEAM_PLANS/$plan_id/plan.md"
  if [[ ! -f "$plan_file" ]]; then
    log_error "Plan $plan_id not found"
    return 1
  fi
  # Extract task IDs and their dependencies from the plan frontmatter
  # This is a simplified implementation for the bash scaffold
  # Full implementation uses jq when available
  if command -v jq &>/dev/null; then
    local tasks_json
    tasks_json=$(sed -n '/^---$/,/^---$/p' "$plan_file" | head -n -1 | tail -n +2 | yq -r '.tasks' 2>/dev/null || echo '[]')
    echo "$tasks_json" | jq -r '.[].id' 2>/dev/null
  else
    # Fallback: grep task-IDs from the plan file
    grep -oE 'task-[0-9]+' "$plan_file" | sort -u
  fi
}

# Spawn a sub-agent for a plan task (Claude Code only).
# spawn_subagent <task-id> <assignee> <role> <prompt-text> <output-path>
# This constructs the Agent tool invocation parameters.
spawn_subagent() {
  local task_id="$1"
  local assignee="$2"
  local role="$3"
  local prompt_text="$4"
  local output_path="$5"
  # Resolve tools for this agent's role
  local tools
  tools=$(resolve_agent_tools "$role")
  # The actual Agent tool invocation is done by the LLM reading this output,
  # not by bash directly (bash cannot call the Agent tool).
  printf 'SPAWN: task=%s assignee=%s role=%s tools=[%s]\n' "$task_id" "$assignee" "$role" "$tools"
  printf 'OUTPUT: %s\n' "$output_path"
  printf 'PROMPT: %s\n' "$prompt_text"
}