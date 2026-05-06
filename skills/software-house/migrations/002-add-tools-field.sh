#!/bin/sh
# 002-add-tools-field.sh
# Add 'tools' frontmatter field to all existing agent files.
# For each agent, resolves tools from tools-config.json: shared_tools + role_tools[role].
# Idempotent: skips agents that already have a 'tools' field.

OLD_VER="${1:-none}"
NEW_VER="${2:-unknown}"

printf '  [002-add-tools-field] Adding tools field to existing agents. old=%s new=%s\n' "${OLD_VER}" "${NEW_VER}"

SH_HOME="${SH_HOME:-$HOME/.software-house}"
TOOLS_CONFIG="${SH_HOME}/config/tools-config.json"

# Check tools-config.json exists
if [ ! -f "$TOOLS_CONFIG" ]; then
  printf '  [002-add-tools-field] tools-config.json not found -- skipping.\n'
  exit 0
fi

# Parse shared_tools from config (jq if available, otherwise skip)
if ! command -v jq >/dev/null 2>&1; then
  printf '  [002-add-tools-field] jq not available -- skipping auto-resolve.\n'
  exit 0
fi

SHARED_TOOLS=$(jq -r '.shared_tools | join(",")' "$TOOLS_CONFIG" 2>/dev/null)

# Find all agent files (global + per-project)
find "$SH_HOME/agents" -name '*.md' -type f 2>/dev/null | while read -r agent_file; do
  # Skip if tools field already exists
  if grep -q '^tools:' "$agent_file" 2>/dev/null; then
    continue
  fi
  # Read role from frontmatter
  ROLE=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^role:' | head -1 | sed 's/role:[[:space:]]*//')
  if [ -z "$ROLE" ]; then
    ROLE="default"
  fi
  # Resolve role_tools
  ROLE_TOOLS=$(jq -r ".role_tools.${ROLE} | if . then join(\",\") else \"\" end" "$TOOLS_CONFIG" 2>/dev/null)
  # Combine shared + role tools
  if [ -n "$ROLE_TOOLS" ]; then
    ALL_TOOLS="${SHARED_TOOLS},${ROLE_TOOLS}"
  else
    ALL_TOOLS="$SHARED_TOOLS"
  fi
  # Deduplicate (simple approach: convert to yaml list format)
  YAML_TOOLS=$(echo "$ALL_TOOLS" | tr ',' '\n' | awk '!seen[$0]++' | sed 's/^/    - /' | tr '\n' ' ' | sed 's/ *$//')
  YAML_LINE="tools: [$(echo "$ALL_TOOLS" | tr ',' '\n' | awk '!seen[$0]++' | tr '\n' ',' | sed 's/,$//')]"
  # Insert tools field after the last frontmatter field before closing ---
  sed -i.bak "/^---$/i\\${YAML_LINE}" "$agent_file" 2>/dev/null && rm -f "${agent_file}.bak"
  printf '    Added tools to %s (role=%s)\n' "$agent_file" "$ROLE"
done

# Also check per-project agent files
find . -path '*/.software-house/agents/*.md' -type f 2>/dev/null | while read -r agent_file; do
  if grep -q '^tools:' "$agent_file" 2>/dev/null; then
    continue
  fi
  ROLE=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^role:' | head -1 | sed 's/role:[[:space:]]*//')
  if [ -z "$ROLE" ]; then
    ROLE="default"
  fi
  ROLE_TOOLS=$(jq -r ".role_tools.${ROLE} | if . then join(\",\") else \"\" end" "$TOOLS_CONFIG" 2>/dev/null)
  if [ -n "$ROLE_TOOLS" ]; then
    ALL_TOOLS="${SHARED_TOOLS},${ROLE_TOOLS}"
  else
    ALL_TOOLS="$SHARED_TOOLS"
  fi
  YAML_LINE="tools: [$(echo "$ALL_TOOLS" | tr ',' '\n' | awk '!seen[$0]++' | tr '\n' ',' | sed 's/,$//')]"
  sed -i.bak "/^---$/i\\${YAML_LINE}" "$agent_file" 2>/dev/null && rm -f "${agent_file}.bak"
  printf '    Added tools to %s (role=%s)\n' "$agent_file" "$ROLE"
done

exit 0