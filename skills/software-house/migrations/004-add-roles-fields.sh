#!/bin/sh
# 004-add-roles-fields.sh
# Backfill role template fields (responsibilities, deliverables, collaborates_with,
# handoff_triggers) and wiki-LLM fields (confidence, lifecycle, last_compiled,
# source_refs) into existing agent canonical files. Also updates wiki pages with
# structured role content if they exist.
# Idempotent: skips agents that already have the responsibilities field.

OLD_VER="${1:-none}"
NEW_VER="${2:-unknown}"

printf '  [004-add-roles-fields] Backfilling role template + wiki-LLM fields. old=%s new=%s\n' "${OLD_VER}" "${NEW_VER}"

SH_HOME="${SH_HOME:-$HOME/.software-house}"

# Locate role-templates.json
ROLE_TEMPLATES=""
if [ -f "$SH_HOME/config/role-templates.json" ]; then
  ROLE_TEMPLATES="$SH_HOME/config/role-templates.json"
else
  MIG_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "$MIG_DIR/../config/role-templates.json" ]; then
    ROLE_TEMPLATES="$MIG_DIR/../config/role-templates.json"
  fi
fi

if [ -z "$ROLE_TEMPLATES" ] || [ ! -f "$ROLE_TEMPLATES" ]; then
  printf '    WARNING: role-templates.json not found. Adding empty fields only.\n'
fi

TODAY=$(date -u +"%Y-%m-%d" 2>/dev/null || echo "unknown")
COUNT=0
SKIP=0

# ---------------------------------------------------------------------------
# backfill_agent <agent-file>
# ---------------------------------------------------------------------------
backfill_agent() {
  local agent_file="$1"

  # Idempotent: skip if already backfilled
  if grep -q '^responsibilities:' "$agent_file" 2>/dev/null; then
    SKIP=$((SKIP + 1))
    return 0
  fi

  # Read role from frontmatter
  local role
  role=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^role:' | head -1 | sed 's/role:[[:space:]]*//')

  if [ -z "$role" ]; then
    printf '    Skipping %s: no role field\n' "$(basename "$agent_file" .md)"
    SKIP=$((SKIP + 1))
    return 0
  fi

  # Find line number of second ---
  local second_dash
  second_dash=$(awk '/^---$/{n++; if(n==2) {print NR; exit}}' "$agent_file")

  if [ -z "$second_dash" ]; then
    printf '    Skipping %s: malformed frontmatter\n' "$(basename "$agent_file" .md)"
    SKIP=$((SKIP + 1))
    return 0
  fi

  # Build fields temp file
  local fields_tmp
  fields_tmp=$(mktemp)

  if [ -n "$ROLE_TEMPLATES" ] && command -v jq >/dev/null 2>&1; then
    local has_template
    has_template=$(jq -r ".role_templates[\"$role\"] | if . then \"yes\" else \"no\" end" "$ROLE_TEMPLATES" 2>/dev/null)

    if [ "$has_template" = "yes" ]; then
      # Responsibilities
      printf 'responsibilities:\n' > "$fields_tmp"
      jq -r ".role_templates[\"$role\"].responsibilities // [] | if length > 0 then map(\"  - \" + .) | join(\"\n\") else \"[]\" end" "$ROLE_TEMPLATES" >> "$fields_tmp"
      printf '\n' >> "$fields_tmp"

      # Deliverables
      printf 'deliverables:\n' >> "$fields_tmp"
      jq -r ".role_templates[\"$role\"].deliverables // [] | if length > 0 then map(\"  - \" + .) | join(\"\n\") else \"[]\" end" "$ROLE_TEMPLATES" >> "$fields_tmp"
      printf '\n' >> "$fields_tmp"

      # Collaborates_with
      printf 'collaborates_with:\n' >> "$fields_tmp"
      jq -r ".role_templates[\"$role\"].collaborates_with // [] | if length > 0 then map(\"  - \" + .) | join(\"\n\") else \"[]\" end" "$ROLE_TEMPLATES" >> "$fields_tmp"
      printf '\n' >> "$fields_tmp"

      # Handoff triggers
      printf 'handoff_triggers:\n' >> "$fields_tmp"
      jq -r ".role_templates[\"$role\"].handoff_triggers // {} | if length > 0 then to_entries | map(\"  \" + .key + \": [\" + (.value | join(\", \")) + \"]\") | join(\"\n\") else \"{}\" end" "$ROLE_TEMPLATES" >> "$fields_tmp"
      printf '\n' >> "$fields_tmp"
    else
      printf 'responsibilities: []\ndeliverables: []\ncollaborates_with: []\nhandoff_triggers: {}\n' > "$fields_tmp"
    fi
  else
    printf 'responsibilities: []\ndeliverables: []\ncollaborates_with: []\nhandoff_triggers: {}\n' > "$fields_tmp"
  fi

  # Wiki-LLM fields (always added)
  printf 'confidence: 1.0\nlifecycle: draft\nlast_compiled: %s\nsource_refs: []\n' "$TODAY" >> "$fields_tmp"

  # Splice into frontmatter before closing ---
  local tmp_file="${agent_file}.migtmp"
  head -n $((second_dash - 1)) "$agent_file" > "$tmp_file"
  cat "$fields_tmp" >> "$tmp_file"
  printf -- '---\n' >> "$tmp_file"
  tail -n +$((second_dash + 1)) "$agent_file" >> "$tmp_file"
  mv "$tmp_file" "$agent_file"

  rm -f "$fields_tmp"

  COUNT=$((COUNT + 1))
  printf '    Backfilled %s (role=%s)\n' "$(basename "$agent_file" .md)" "$role"

  # Update wiki page if it exists
  update_wiki_page "$agent_file" "$role"
}

# ---------------------------------------------------------------------------
# update_wiki_page <agent-file> <role>
# ---------------------------------------------------------------------------
update_wiki_page() {
  local agent_file="$1"
  local role="$2"
  local name
  name=$(basename "$agent_file" .md)

  # Try to find the wiki page
  local wiki_page=""
  local wiki_dir=""

  # Check company wiki
  if [ -f "$SH_HOME/company/wiki/people/${name}.md" ]; then
    wiki_page="$SH_HOME/company/wiki/people/${name}.md"
    wiki_dir="$SH_HOME/company/wiki"
  fi

  # Check team wiki via projects-index
  if [ -z "$wiki_page" ] && [ -f "$SH_HOME/projects-index.json" ] && command -v jq >/dev/null 2>&1; then
    local project_path
    project_path=$(jq -r --arg n "$name" '
      if .projects then
        .projects | to_entries[] |
        select(.value.agents // [] | map(select(. == $n)) | length > 0) |
        .key
      else empty end' "$SH_HOME/projects-index.json" 2>/dev/null | head -1)

    if [ -n "$project_path" ] && [ -f "$project_path/.software-house/team/wiki/people/${name}.md" ]; then
      wiki_page="$project_path/.software-house/team/wiki/people/${name}.md"
      wiki_dir="$project_path/.software-house/team/wiki"
    fi
  fi

  if [ -z "$wiki_page" ]; then
    return 0
  fi

  # Skip if already has Responsibilities section
  if grep -q '^## Responsibilities' "$wiki_page" 2>/dev/null; then
    return 0
  fi

  # Build wiki sections from role template
  local sections_tmp
  sections_tmp=$(mktemp)

  if [ -n "$ROLE_TEMPLATES" ] && command -v jq >/dev/null 2>&1; then
    local has_template
    has_template=$(jq -r ".role_templates[\"$role\"] | if . then \"yes\" else \"no\" end" "$ROLE_TEMPLATES" 2>/dev/null)

    if [ "$has_template" = "yes" ]; then
      # Responsibilities
      printf '\n## Responsibilities\n' > "$sections_tmp"
      jq -r ".role_templates[\"$role\"].responsibilities // [] | if length > 0 then map(\"- \" + .) | join(\"\n\") else \"(none)\" end" "$ROLE_TEMPLATES" >> "$sections_tmp"

      # Deliverables
      printf '\n## Deliverables\n' >> "$sections_tmp"
      jq -r ".role_templates[\"$role\"].deliverables // [] | if length > 0 then map(\"- \" + .) | join(\"\n\") else \"(none)\" end" "$ROLE_TEMPLATES" >> "$sections_tmp"

      # Collaboration Map
      printf '\n## Collaboration Map\n' >> "$sections_tmp"
      local collab escalates
      collab=$(jq -r ".role_templates[\"$role\"].collaborates_with // [] | join(\", \")" "$ROLE_TEMPLATES" 2>/dev/null)
      escalates=$(jq -r ".role_templates[\"$role\"].escalates_to // [] | join(\", \")" "$ROLE_TEMPLATES" 2>/dev/null)
      printf -- '- Works with: %s\n' "$collab" >> "$sections_tmp"
      printf -- '- Escalates to: %s\n' "$escalates" >> "$sections_tmp"

      # Handoff Protocol
      printf '\n## Handoff Protocol\n' >> "$sections_tmp"
      jq -r ".role_templates[\"$role\"].handoff_triggers // {} | if length > 0 then to_entries | map(\"- \" + .key + \" -> \" + (.value | join(\", \"))) | join(\"\n\") else \"(none)\" end" "$ROLE_TEMPLATES" >> "$sections_tmp"
    fi
  fi

  # Append sections to wiki page
  if [ -s "$sections_tmp" ]; then
    cat "$sections_tmp" >> "$wiki_page"
    printf '    Updated wiki page: %s\n' "$wiki_page"
  fi

  rm -f "$sections_tmp"
}

# ---------------------------------------------------------------------------
# Main: process all agent files
# ---------------------------------------------------------------------------

# Freelance pool agents
if [ -d "$SH_HOME/agents" ]; then
  find "$SH_HOME/agents" -name '*.md' -type f 2>/dev/null | while read -r agent_file; do
    backfill_agent "$agent_file"
  done
fi

# Team agents via projects-index.json
if [ -f "$SH_HOME/projects-index.json" ] && command -v jq >/dev/null 2>&1; then
  jq -r 'if .projects then .projects | to_entries[] | .key else empty end' "$SH_HOME/projects-index.json" 2>/dev/null | while read -r project_path; do
    TEAM_AGENTS="$project_path/.software-house/team/agents"
    if [ -d "$TEAM_AGENTS" ]; then
      find "$TEAM_AGENTS" -name '*.md' -type f 2>/dev/null | while read -r agent_file; do
        backfill_agent "$agent_file"
      done
    fi
  done
fi

# Copy role-templates.json to state config if not already there
if [ -n "$ROLE_TEMPLATES" ] && [ ! -f "$SH_HOME/config/role-templates.json" ]; then
  mkdir -p "$SH_HOME/config" 2>/dev/null
  cp "$ROLE_TEMPLATES" "$SH_HOME/config/role-templates.json" 2>/dev/null && \
    printf '    Copied role-templates.json to %s/config/\n' "$SH_HOME"
fi

printf '  [004-add-roles-fields] Done. Backfilled: %d, Skipped: %d\n' "$COUNT" "$SKIP"

exit 0