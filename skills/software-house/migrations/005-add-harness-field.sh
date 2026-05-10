#!/bin/sh
# 005-add-harness-field.sh
# Backfill 'harness: null' into existing agent canonical YAML frontmatter files.
# Idempotent: skips agents that already have a 'harness:' line.

OLD_VER="${1:-none}"
NEW_VER="${2:-unknown}"

printf '  [005-add-harness-field] Backfilling harness field. old=%s new=%s\n' "${OLD_VER}" "${NEW_VER}"

SH_HOME="${SH_HOME:-$HOME/.software-house}"

COUNT=0
SKIP=0

backfill_agent() {
  AGENT_FILE="$1"

  if grep -q '^harness:' "$AGENT_FILE" 2>/dev/null; then
    SKIP=$((SKIP + 1))
    return 0
  fi

  SECOND_DASH=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$AGENT_FILE")

  if [ -z "$SECOND_DASH" ]; then
    printf '    Skipping %s: malformed frontmatter\n' "$(basename "$AGENT_FILE" .md)"
    SKIP=$((SKIP + 1))
    return 0
  fi

  TMP_FILE=$(mktemp)
  head -n $((SECOND_DASH - 1)) "$AGENT_FILE" > "$TMP_FILE"
  printf 'harness: null\n' >> "$TMP_FILE"
  printf -- '---\n' >> "$TMP_FILE"
  tail -n +$((SECOND_DASH + 1)) "$AGENT_FILE" >> "$TMP_FILE"
  mv "$TMP_FILE" "$AGENT_FILE"

  COUNT=$((COUNT + 1))
  printf '    Backfilled %s (added harness: null)\n' "$(basename "$AGENT_FILE" .md)"
}

if [ -d "$SH_HOME/agents" ]; then
  find "$SH_HOME/agents" -name '*.md' -type f 2>/dev/null | while read -r AGENT_FILE; do
    backfill_agent "$AGENT_FILE"
  done
fi

if [ -f "$SH_HOME/projects-index.json" ] && command -v jq >/dev/null 2>&1; then
  jq -r 'if .projects then .projects | to_entries[] | .key else empty end' "$SH_HOME/projects-index.json" 2>/dev/null | while read -r PROJECT_PATH; do
    TEAM_AGENTS="$PROJECT_PATH/.software-house/team/agents"
    if [ -d "$TEAM_AGENTS" ]; then
      find "$TEAM_AGENTS" -name '*.md' -type f 2>/dev/null | while read -r AGENT_FILE; do
        backfill_agent "$AGENT_FILE"
      done
    fi
  done
fi

printf '  [005-add-harness-field] Done. Backfilled: %d, Skipped: %d\n' "$COUNT" "$SKIP"

exit 0
