#!/usr/bin/env bash
# wiki-ingest.sh -- ingest a source document into the wiki
# Spec: operations/wiki-ingest.md | Tier 2 (additive)

op_wiki_ingest() {
  local source_path=""
  local scope="company"
  local team_name=""
  local dept_name=""
  local page_type=""
  local page_title=""
  local page_tags=""
  local page_confidence="0.7"
  local no_compile=0

  # Parse arguments
  while (( $# > 0 )); do
    case "$1" in
      --team)
        shift; team_name="${1:-}"; shift ;;
      --dept)
        shift; dept_name="${1:-}"; shift ;;
      --type)
        shift; page_type="${1:-}"; shift ;;
      --title)
        shift; page_title="${1:-}"; shift ;;
      --tags)
        shift; page_tags="${1:-}"; shift ;;
      --confidence)
        shift; page_confidence="${1:-0.7}"; shift ;;
      --no-compile)
        no_compile=1; shift ;;
      --help|-h)
        printf 'Usage: wiki-ingest <source-path> [--team <name>] [--dept <name>]\n'
        printf '       [--type concept|decision|synthesis] [--title "<text>"]\n'
        printf '       [--tags <tag1,tag2>] [--confidence <0.0-1.0>] [--no-compile]\n'
        return 0
        ;;
      -*)
        printf 'Error: unknown flag %s\n' "$1" >&2
        return 1
        ;;
      *)
        if [[ -z "$source_path" ]]; then
          source_path="$1"; shift
        else
          shift
        fi
        ;;
    esac
  done

  if [[ -z "$source_path" ]]; then
    printf 'Error: source path required. Usage: wiki-ingest <source-path>\n' >&2
    return 1
  fi

  # Step 1: Validate input
  if [[ ! -f "$source_path" ]]; then
    printf 'Error: source file not found: %s\n' "$source_path" >&2
    return 1
  fi

  # Validate --type if specified
  if [[ -n "$page_type" ]] && [[ "$page_type" != "concept" ]] && [[ "$page_type" != "decision" ]] && [[ "$page_type" != "synthesis" ]]; then
    printf 'Error: --type must be concept, decision, or synthesis. Got: %s\n' "$page_type" >&2
    return 1
  fi

  # Determine scope and paths
  local raw_dir="" wiki_concepts="" wiki_decisions="" wiki_synthesis="" wiki_log="" index_file=""

  if [[ -n "$team_name" ]]; then
    scope="team:$team_name"
    # Resolve team dir
    local team_dir=""
    team_dir="$(resolve_team_dir "$team_name")"
    if [[ -z "$team_dir" ]]; then
      printf 'Error: team "%s" not found.\n' "$team_name" >&2
      return 1
    fi
    raw_dir="$team_dir/raw"
    wiki_concepts=""  # team has no concepts dir
    wiki_decisions="$team_dir/wiki/decisions"
    wiki_synthesis="$team_dir/wiki/synthesis"
    wiki_log="$team_dir/wiki/log.md"
    index_file="$team_dir/index.md"
  else
    scope="company"
    raw_dir="$RAW_DIR"
    wiki_concepts="$WIKI_CONCEPTS"
    wiki_decisions="$WIKI_DECISIONS"
    wiki_synthesis="$WIKI_SYNTHESIS"
    wiki_log="$WIKI_LOG"
    index_file="$COMPANY_INDEX"
  fi

  require_company_init || return 1

  # Step 2: Archive the source
  local utc_ts utc_d
  utc_ts="$(utc_now)"
  utc_d="$(utc_date)"
  local source_filename
  source_filename="$(basename "$source_path")"
  # Replace colons from timestamp with hyphens for filename safety
  local safe_ts
  safe_ts="$(echo "$utc_ts" | sed 's/://g' | sed 's/Z$//')"
  local archived_name="${safe_ts}-${source_filename}"
  local archived_path="${raw_dir}/${archived_name}"

  mkdir -p "$raw_dir" || { log_error "Failed to create raw dir: $raw_dir"; return 1; }

  cp "$source_path" "$archived_path" || { log_error "Failed to archive source to $archived_path"; return 1; }

  printf 'Archived: %s\n' "$archived_path"

  if (( no_compile )); then
    # --no-compile: just archive and log
    append_wiki_log "$wiki_log" "$utc_ts" "wiki-ingest" "$archived_name -> (archived only, no compile)"
    local audit_entry
    audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"wiki-ingest\",\"scope\":\"$scope\",\"args\":{\"source\":\"$source_path\",\"no_compile\":true},\"diff\":{\"created\":[\"$archived_path\"]},\"confirmation\":{\"tier\":2},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
    audit_log "$audit_entry"
    printf 'Source archived (no-compile mode).\n'
    return 0
  fi

  # Step 3: Auto-detect page type
  if [[ -z "$page_type" ]]; then
    page_type="$(detect_page_type "$source_path")"
  fi

  # Determine target directory
  local target_dir=""
  case "$page_type" in
    concept)
      target_dir="$wiki_concepts"
      ;;
    decision)
      target_dir="$wiki_decisions"
      ;;
    synthesis)
      target_dir="$wiki_synthesis"
      ;;
  esac

  if [[ -z "$target_dir" ]]; then
    # concepts not available at team level, fall back to decisions
    if [[ -n "$team_name" ]] && [[ "$page_type" == "concept" ]]; then
      target_dir="$wiki_decisions"
      page_type="decision"
      printf 'Note: team scope has no concepts/ dir. Falling back to decisions/.\n'
    else
      log_error "Cannot determine target directory for type: $page_type"
      return 1
    fi
  fi

  mkdir -p "$target_dir" || { log_error "Failed to create target dir: $target_dir"; return 1; }

  # Step 4: Compile the wiki page
  local slug
  if [[ -n "$page_title" ]]; then
    slug="$(echo "$page_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')"
  else
    # Derive from source filename (strip extension)
    local base_name
    base_name="$(echo "$source_filename" | sed 's/\.[^.]*$//')"
    slug="$(echo "$base_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')"
  fi

  # Default title from slug
  if [[ -z "$page_title" ]]; then
    page_title="$(echo "$slug" | sed 's/-/ /g' | sed 's/\b\(.\)/\u/g')"
  fi

  local page_file="${target_dir}/${slug}.md"

  # Build tags yaml
  local tags_yaml="[]"
  if [[ -n "$page_tags" ]]; then
    local tags_json
    tags_json="$(echo "$page_tags" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -s . 2>/dev/null || echo '[]')"
    tags_yaml="$tags_json"
  fi

  # Extract a one-line summary from source
  local summary
  summary="$(head -5 "$source_path" | grep -v '^#' | grep -v '^$' | head -1)"
  if [[ -z "$summary" ]]; then
    summary="(compiled from $source_filename)"
  fi

  local source_ref="raw/${archived_name}"

  if [[ -f "$page_file" ]]; then
    # Page exists: append source_ref, update last_compiled
    printf 'Page exists: %s -- updating source_refs and last_compiled.\n' "$page_file"

    # Add source_ref if not already present
    if ! grep -q "$source_ref" "$page_file"; then
      # Find source_refs line and append
      if grep -q '^source_refs:' "$page_file"; then
        # Simple append to existing source_refs array
        sed -i.bak "/^source_refs:/a\\  - $source_ref" "$page_file" && rm -f "${page_file}.bak"
      fi
    fi

    # Update last_compiled
    if grep -q '^last_compiled:' "$page_file"; then
      sed -i.bak "s/^last_compiled:.*$/last_compiled: $utc_d/" "$page_file" && rm -f "${page_file}.bak"
    fi

    printf 'Updated: %s\n' "$page_file"
  else
    # Create new page
    case "$page_type" in
      concept)
        cat > "$page_file" << CONCEPTEOF
---
type: concept
title: "$page_title"
confidence: $page_confidence
lifecycle: draft
last_compiled: $utc_d
source_refs:
  - $source_ref
tags: $tags_yaml
created_at: $utc_d
classification: internal
---

# $page_title

## Summary

$summary

## Key Points

(Extract key points from the source document.)

## Related

CONCEPTEOF
        ;;
      decision)
        cat > "$page_file" << DECISIONEOF
---
type: decision
title: "$page_title"
confidence: $page_confidence
lifecycle: draft
last_compiled: $utc_d
source_refs:
  - $source_ref
tags: $tags_yaml
created_at: $utc_d
classification: internal
---

# $page_title

## Status

Draft

## Context

(What motivated this decision.)

## Decision

(What was decided.)

## Consequences

(Positive and negative outcomes.)

## Related

DECISIONEOF
        ;;
      synthesis)
        cat > "$page_file" << SYNTHESISEOF
---
type: synthesis
title: "$page_title"
confidence: $page_confidence
lifecycle: draft
last_compiled: $utc_d
source_refs:
  - $source_ref
tags: $tags_yaml
created_at: $utc_d
classification: internal
---

# $page_title

## Overview

$summary

## Current State

(As of $utc_d.)

## Key Insights

(Extract key insights from the source document.)

## Related

SYNTHESISEOF
        ;;
    esac

    printf 'Compiled: %s (confidence: %s, lifecycle: draft)\n' "$page_file" "$page_confidence"
  fi

  # Step 6: Update index.md
  if [[ -f "$index_file" ]]; then
    local section_header=""
    case "$page_type" in
      concept)  section_header="## Concepts" ;;
      decision)  section_header="## Decisions" ;;
      synthesis) section_header="## Synthesis" ;;
    esac

    # Check if section exists in index
    local rel_path
    case "$page_type" in
      concept)  rel_path="wiki/concepts/${slug}.md" ;;
      decision)  rel_path="wiki/decisions/${slug}.md" ;;
      synthesis) rel_path="wiki/synthesis/${slug}.md" ;;
    esac

    if grep -q "^${section_header}" "$index_file"; then
      # Check if entry already exists
      if ! grep -q "$slug" "$index_file"; then
        # Append entry after section header (find next section or EOF)
        local next_section
        next_section="$(grep -n "^## " "$index_file" | tail -n +2 | head -1 | cut -d: -f1)"
        if [[ -n "$next_section" ]]; then
          sed -i.bak "$(( next_section - 1 ))a\\- [${page_title}](${rel_path}) -- ${summary}" "$index_file" && rm -f "${index_file}.bak"
        else
          echo "- [${page_title}](${rel_path}) -- ${summary}" >> "$index_file"
        fi
      fi
    else
      # Add section to end of index
      printf '\n%s\n\n- [%s](%s) -- %s\n' "$section_header" "$page_title" "$rel_path" "$summary" >> "$index_file"
    fi
    printf 'Index updated: %s section\n' "$page_type"
  fi

  # Step 7: Append to wiki log
  append_wiki_log "$wiki_log" "$utc_ts" "wiki-ingest" "$archived_name -> ${page_type}/${slug}.md"

  # Step 8: Audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"wiki-ingest\",\"scope\":\"$scope\",\"args\":{\"source\":\"$source_path\",\"type\":\"$page_type\",\"title\":\"$page_title\"},\"diff\":{\"created\":[\"$archived_path\",\"$page_file\"],\"updated\":[\"$wiki_log\",\"$index_file\"]},\"confirmation\":{\"tier\":2},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  # Step 9: Report
  printf '\nIngested: %s\n' "$source_path"
  printf '  Archived: raw/%s\n' "$archived_name"
  printf '  Compiled: wiki/%s/%s.md (confidence: %s, lifecycle: draft)\n' "$page_type" "$slug" "$page_confidence"
  printf '  Index updated: %s section\n' "$page_type"
  printf '\n  Next: /software-house wiki-lint          check wiki health\n'
  printf '        /software-house show %s        view the compiled page\n' "$slug"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Detect page type from source content keywords
detect_page_type() {
  local src="$1"
  local content
  content="$(head -50 "$src" 2>/dev/null || echo "")"

  local score_decision=0
  local score_concept=0
  local score_synthesis=0

  # Decision keywords
  for kw in ADR decision chosen alternatives rejected accepted; do
    echo "$content" | grep -qi "$kw" && score_decision=$(( score_decision + 1 ))
  done

  # Concept keywords
  for kw in concept pattern principle definition architecture design; do
    echo "$content" | grep -qi "$kw" && score_concept=$(( score_concept + 1 ))
  done

  # Synthesis keywords
  for kw in status summary overview dashboard report metrics; do
    echo "$content" | grep -qi "$kw" && score_synthesis=$(( score_synthesis + 1 ))
  done

  # Pick highest score, default to concept
  if (( score_decision > score_concept )) && (( score_decision > score_synthesis )); then
    echo "decision"
  elif (( score_synthesis > score_concept )); then
    echo "synthesis"
  else
    echo "concept"
  fi
}

# Append entry to wiki log
append_wiki_log() {
  local log_file="$1"
  local ts="$2"
  local op="$3"
  local msg="$4"

  # Create log file if missing
  if [[ ! -f "$log_file" ]]; then
    local log_dir
    log_dir="$(dirname "$log_file")"
    mkdir -p "$log_dir" 2>/dev/null || true
    printf '# Wiki Log\n\n' > "$log_file"
  fi

  printf -- '- %s | %s | %s\n' "$ts" "$op" "$msg" >> "$log_file"
}

# Resolve team directory from team name
resolve_team_dir() {
  local name="$1"
  # Check projects-index.json for path
  if [[ -f "$PROJECTS_INDEX" ]] && command -v jq &>/dev/null; then
    local project_path
    project_path="$(jq -r ".projects | to_entries[] | select(.value.team == \"$name\") | .key" "$PROJECTS_INDEX" 2>/dev/null | head -1)"
    if [[ -n "$project_path" ]] && [[ -d "${project_path}/.software-house/team" ]]; then
      echo "${project_path}/.software-house/team"
      return 0
    fi
  fi
  # Fallback: check WIKI_TEAMS for team info
  if [[ -f "$WIKI_TEAMS/${name}.md" ]]; then
    local proj_path
    proj_path="$(grep '^project_path:' "$WIKI_TEAMS/${name}.md" 2>/dev/null | sed 's/project_path: *//' | tr -d '"')"
    if [[ -n "$proj_path" ]] && [[ -d "${proj_path}/.software-house/team" ]]; then
      echo "${proj_path}/.software-house/team"
      return 0
    fi
  fi
  echo ""
}