#!/bin/sh
# 003-add-roles-tools-scrum.sh
# Create sprint/plan/backlog directories for existing teams.
# Add tools field to existing agent frontmatter if migration 002 was skipped.
# Idempotent: safe to run multiple times.

OLD_VER="${1:-none}"
NEW_VER="${2:-unknown}"

printf '  [003-add-roles-tools-scrum] Setting up Scrum/Plan directories. old=%s new=%s\n' "${OLD_VER}" "${NEW_VER}"

SH_HOME="${SH_HOME:-$HOME/.software-house}"

# Create sprints/ and plans/ directories under each team's .software-house/team/
# Find all projects that have .software-house/team/
if [ -d "$SH_HOME" ]; then
  # Scan projects-index.json for registered project paths
  if [ -f "$SH_HOME/projects-index.json" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.projects | to_entries[] | .key' "$SH_HOME/projects-index.json" 2>/dev/null | while read -r project_path; do
      TEAM_DIR="$project_path/.software-house/team"
      if [ -d "$TEAM_DIR" ]; then
        mkdir -p "$TEAM_DIR/sprints" 2>/dev/null && printf '    Created sprints/ in %s\n' "$TEAM_DIR"
        mkdir -p "$TEAM_DIR/plans" 2>/dev/null && printf '    Created plans/ in %s\n' "$TEAM_DIR"
        # Create backlog.md if missing
        if [ ! -f "$TEAM_DIR/backlog.md" ]; then
          cat > "$TEAM_DIR/backlog.md" << 'BACKLOGEOF'
---
type: product-backlog
created_at: __DATE__
next_id: 1
---

# Product Backlog

| ID | Title | Type | Priority | Points | Assignee | Status | Sprint |
|---|---|---|---|---|---|---|---|
BACKLOGEOF
          # Replace __DATE__ with current date
          UTC_DATE=$(date -u +"%Y-%m-%d" 2>/dev/null || echo "unknown")
          sed -i.bak "s/__DATE__/$UTC_DATE/" "$TEAM_DIR/backlog.md" 2>/dev/null && rm -f "$TEAM_DIR/backlog.md.bak"
          printf '    Created backlog.md in %s\n' "$TEAM_DIR"
        fi
      fi
    done
  fi
fi

# Ensure tools field exists on all agent files (in case migration 002 was skipped)
TOOLS_CONFIG="$SH_HOME/config/tools-config.json"
if [ -f "$TOOLS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
  SHARED_TOOLS=$(jq -r '.shared_tools | join(",")' "$TOOLS_CONFIG" 2>/dev/null)

  find "$SH_HOME/agents" -name '*.md' -type f 2>/dev/null | while read -r agent_file; do
    if grep -q '^tools:' "$agent_file" 2>/dev/null; then
      continue
    fi
    ROLE=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^role:' | head -1 | sed 's/role:[[:space:]]*//')
    if [ -z "$ROLE" ]; then ROLE="default"; fi
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
fi

exit 0