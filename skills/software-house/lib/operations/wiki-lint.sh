#!/usr/bin/env bash
# wiki-lint.sh -- wiki-specific health checks
# Spec: operations/wiki-lint.md | Tier 1 (read-only)

op_wiki_lint() {
  local scope="company"
  local team_name=""
  local check_categories=""
  local fix_suggestions=0
  local json_output=0

  # Parse arguments
  while (( $# > 0 )); do
    case "$1" in
      company)  scope="company"; shift ;;
      team)    shift; team_name="${1:-}"; scope="team"; shift ;;
      --check) shift; check_categories="${1:-}"; shift ;;
      --fix-suggestions) fix_suggestions=1; shift ;;
      --json)  json_output=1; shift ;;
      --help|-h)
        printf 'Usage: wiki-lint [company|team <name>] [--check <categories>]\n'
        printf '       [--fix-suggestions] [--json]\n'
        printf '\nCheck categories: confidence-drift, stale, broken-wikilinks,\n'
        printf '  orphan, empty-sections, missing-concepts, source-trail, wikilink-consistency\n'
        return 0
        ;;
      *) shift ;;
    esac
  done

  require_company_init || return 1

  local error_count=0
  local warning_count=0
  local info_count=0

  # Parse check categories (comma-separated)
  local -a enabled_checks=()
  if [[ -n "$check_categories" ]]; then
    IFS=',' read -ra enabled_checks <<< "$check_categories"
  else
    # All checks enabled by default
    enabled_checks=(confidence-drift stale broken-wikilinks orphan empty-sections missing-concepts source-trail wikilink-consistency)
  fi

  # Helper: check if a category is enabled
  check_enabled() {
    local cat="$1"
    for c in "${enabled_checks[@]}"; do
      [[ "$c" == "$cat" ]] && return 0
    done
    return 1
  }

  # Determine wiki directories based on scope
  local -a wiki_dirs=()
  local index_file=""
  local raw_dir=""

  if [[ "$scope" == "team" ]] && [[ -n "$team_name" ]]; then
    local team_dir
    team_dir="$(resolve_team_dir "$team_name")"
    if [[ -z "$team_dir" ]]; then
      printf 'Error: team "%s" not found.\n' "$team_name" >&2
      return 1
    fi
    wiki_dirs=("$team_dir/wiki/people" "$team_dir/wiki/decisions" "$team_dir/wiki/synthesis" "$team_dir/wiki/handoffs/briefs")
    index_file="$team_dir/index.md"
    raw_dir="$team_dir/raw"
  else
    wiki_dirs=("$WIKI_PEOPLE" "$WIKI_TEAMS" "$WIKI_DEPTS" "$WIKI_CONCEPTS" "$WIKI_DECISIONS" "$WIKI_SYNTHESIS" "$WIKI_HANDOFF_BRIEFS")
    index_file="$COMPANY_INDEX"
    raw_dir="$RAW_DIR"
  fi

  if ! (( json_output )); then
    printf '# Wiki Lint Report -- %s\n\n' "$scope"
  fi

  # Collect all wiki pages
  local -a all_pages=()
  local -a all_page_names=()
  for d in "${wiki_dirs[@]}"; do
    if [[ -d "$d" ]]; then
      for f in "$d"/*.md; do
        [[ -f "$f" ]] || continue
        all_pages+=("$f")
        local pname
        pname="$(basename "$f" .md)"
        all_page_names+=("$pname")
      done
    fi
  done

  # Build a set of page names for wikilink resolution
  declare -A page_name_set
  for name in "${all_page_names[@]}"; do
    page_name_set["$name"]=1
  done

  # Read index.md for orphan checks
  local index_content=""
  if [[ -f "$index_file" ]]; then
    index_content="$(cat "$index_file")"
  fi

  # Helper: emit a finding
  emit_finding() {
    local severity="$1" category="$2" page="$3" detail="$4" fix="$5"
    local sev_key=""
    case "$severity" in
      error)   sev_key="ERRORS"; error_count=$(( error_count + 1 )) ;;
      warning) sev_key="WARNINGS"; warning_count=$(( warning_count + 1 )) ;;
      info)    sev_key="INFO"; info_count=$(( info_count + 1 )) ;;
    esac

    if (( json_output )); then
      printf '{"severity":"%s","category":"%s","page":"%s","detail":"%s","fix":"%s"}\n' \
        "$severity" "$category" "$page" "$detail" "$fix"
    else
      local page_display
      page_display="$(echo "$page" | sed "s|$SH_HOME/||")"
      printf '  [%s] %s\n    %s\n' "$category" "$page_display" "$detail"
      if (( fix_suggestions )) && [[ -n "$fix" ]]; then
        printf '    -> %s\n' "$fix"
      fi
    fi
  }

  # ---- Check 1: Confidence drift ----
  if check_enabled "confidence-drift"; then
    if ! (( json_output )); then
      printf '## Confidence Drift\n\n'
    fi
    for f in "${all_pages[@]}"; do
      local confidence="" lifecycle=""
      confidence="$(grep '^confidence:' "$f" 2>/dev/null | head -1 | sed 's/confidence: *//' | tr -d '"')"
      lifecycle="$(grep '^lifecycle:' "$f" 2>/dev/null | head -1 | sed 's/lifecycle: *//' | tr -d '"')"

      [[ -z "$confidence" ]] && continue

      local conf_val
      conf_val="$(echo "$confidence" | awk '{print $1}')"

      if (( $(echo "$conf_val < 0.3" | bc -l 2>/dev/null || echo 0) )) && [[ "$lifecycle" == "draft" ]]; then
        emit_finding "error" "confidence-drift" "$f" "confidence: $confidence, lifecycle: draft" "review and update confidence, or re-compile with wiki-ingest"
      elif (( $(echo "$conf_val < 0.5" | bc -l 2>/dev/null || echo 0) )) && [[ "$lifecycle" == "draft" ]]; then
        emit_finding "warning" "confidence-drift" "$f" "confidence: $confidence, lifecycle: draft" "review and update confidence"
      elif (( $(echo "$conf_val < 0.5" | bc -l 2>/dev/null || echo 0) )) && [[ "$lifecycle" != "archived" ]]; then
        emit_finding "info" "confidence-drift" "$f" "confidence: $confidence, lifecycle: $lifecycle" "was reviewed but confidence low"
      fi
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 2: Stale pages ----
  if check_enabled "stale"; then
    if ! (( json_output )); then
      printf '## Stale Pages\n\n'
    fi
    local thirty_days_ago
    thirty_days_ago="$(date -u -v-30d +"%Y-%m-%d" 2>/dev/null || date -u -d '30 days ago' +"%Y-%m-%d" 2>/dev/null || echo "2000-01-01")"

    for f in "${all_pages[@]}"; do
      local lifecycle="" last_compiled=""
      lifecycle="$(grep '^lifecycle:' "$f" 2>/dev/null | head -1 | sed 's/lifecycle: *//' | tr -d '"')"
      last_compiled="$(grep '^last_compiled:' "$f" 2>/dev/null | head -1 | sed 's/last_compiled: *//' | tr -d '"')"

      if [[ "$lifecycle" == "stale" ]]; then
        emit_finding "warning" "stale" "$f" "lifecycle: stale" "run wiki-ingest with updated source"
      elif [[ "$lifecycle" == "archived" ]]; then
        emit_finding "info" "stale" "$f" "lifecycle: archived (intentional)" "no action needed"
      elif [[ -n "$last_compiled" ]] && [[ "$last_compiled" != "null" ]] && [[ "$last_compiled" < "$thirty_days_ago" ]] && [[ "$lifecycle" != "archived" ]]; then
        emit_finding "warning" "stale" "$f" "last_compiled: $last_compiled (>30 days ago)" "run wiki-ingest or manually update"
      fi
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 3: Broken wikilinks ----
  if check_enabled "broken-wikilinks"; then
    if ! (( json_output )); then
      printf '## Broken Wikilinks\n\n'
    fi
    for f in "${all_pages[@]}"; do
      # Extract [[...]] references from body (skip frontmatter)
      local body_start=0
      local line_num=0
      while IFS= read -r line; do
        line_num=$(( line_num + 1 ))
        if [[ "$line" == "---" ]]; then
          if [[ $body_start -eq 0 ]]; then
            body_start=1
          else
            body_start=2
          fi
          continue
        fi
        [[ $body_start -lt 2 ]] && continue

        # Find [[...]] patterns in this line
        local refs
        refs="$(echo "$line" | grep -oE '\[\[[^]]+\]\]' 2>/dev/null || true)"
        for ref in $refs; do
          # Strip brackets
          local ref_name
          ref_name="$(echo "$ref" | sed 's/\[\[//;s/\]\]//')"
          # Check if page exists
          if [[ -z "${page_name_set[$ref_name]}" ]]; then
            emit_finding "error" "broken-wikilink" "$f" "[[$ref_name]] -- page not found" "wiki-ingest <source> --title $ref_name"
          fi
        done
      done < "$f"
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 4: Orphan pages ----
  if check_enabled "orphan"; then
    if ! (( json_output )); then
      printf '## Orphan Pages\n\n'
    fi
    # Build a set of referenced page names from all page bodies and index
    declare -A referenced_pages
    for name in "${all_page_names[@]}"; do
      # Check if name appears in index
      if echo "$index_content" | grep -q "$name"; then
        referenced_pages["$name"]=1
      fi
    done
    # Check wikilinks from all pages
    for f in "${all_pages[@]}"; do
      local body_refs
      body_refs="$(grep -oE '\[\[[^]]+\]\]' "$f" 2>/dev/null | sed 's/\[\[//;s/\]\]//' || true)"
      for ref in $body_refs; do
        referenced_pages["$ref"]=1
      done
    done

    for name in "${all_page_names[@]}"; do
      if [[ -z "${referenced_pages[$name]}" ]]; then
        # Find the actual file for this name
        for f in "${all_pages[@]}"; do
          if [[ "$(basename "$f" .md)" == "$name" ]]; then
            emit_finding "warning" "orphan" "$f" "not in index.md and no inbound wikilinks" "add to index or link from a related page"
            break
          fi
        done
      fi
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 5: Empty sections ----
  if check_enabled "empty-sections"; then
    if ! (( json_output )); then
      printf '## Empty Sections\n\n'
    fi
    for f in "${all_pages[@]}"; do
      local fcontent
      fcontent="$(cat "$f")"

      # Check for common placeholder patterns
      if echo "$fcontent" | grep -qi "(empty)\|(not yet written)\|(none yet)"; then
        emit_finding "warning" "empty-section" "$f" "contains placeholder content" "fill in content or run wiki-ingest"
      fi

      if echo "$fcontent" | grep -q "(Extract key points"; then
        emit_finding "warning" "empty-section" "$f" "concept page has placeholder key points" "run wiki-ingest with relevant source"
      fi

      if echo "$fcontent" | grep -q "(What motivated\|(What was decided\|(Positive and negative"; then
        emit_finding "warning" "empty-section" "$f" "decision page has placeholder sections" "run wiki-ingest with relevant source"
      fi
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 6: Missing concepts ----
  if check_enabled "missing-concepts"; then
    if ! (( json_output )); then
      printf '## Missing Concepts\n\n'
    fi
    # Only applies to company scope (teams have no concepts dir)
    if [[ "$scope" == "company" ]] && [[ -d "$WIKI_CONCEPTS" ]]; then
      # Build set of existing concept names
      declare -A concept_set
      for cf in "$WIKI_CONCEPTS"/*.md; do
        [[ -f "$cf" ]] || continue
        concept_set["$(basename "$cf" .md)"]=1
      done

      # Check decision and synthesis pages for concept references
      for check_dir in "$WIKI_DECISIONS" "$WIKI_SYNTHESIS"; do
        [[ -d "$check_dir" ]] || continue
        for f in "$check_dir"/*.md; do
          [[ -f "$f" ]] || continue
          # Look for [[...]] references to non-existent concepts
          local refs
          refs="$(grep -oE '\[\[[^]]+\]\]' "$f" 2>/dev/null | sed 's/\[\[//;s/\]\]//' || true)"
          for ref in $refs; do
            if [[ -z "${concept_set[$ref]}" ]] && [[ -z "${page_name_set[$ref]}" ]]; then
              emit_finding "info" "missing-concept" "$f" "references [[$ref]] but no concept page exists" "wiki-ingest <source> --type concept --title $ref"
            fi
          done
        done
      done
    fi
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 7: Source trail ----
  if check_enabled "source-trail"; then
    if ! (( json_output )); then
      printf '## Source Trail\n\n'
    fi
    for f in "${all_pages[@]}"; do
      # Extract source_refs from frontmatter
      local in_fm=0
      local in_refs=0
      while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
          if [[ $in_fm -eq 0 ]]; then
            in_fm=1
          else
            break
          fi
          continue
        fi
        if [[ $in_fm -eq 1 ]] && [[ "$line" =~ ^source_refs: ]]; then
          in_refs=1
          # Check if empty
          if [[ "$line" == "source_refs: []" ]] || [[ "$line" == "source_refs:" && -z "$(echo "$line" | sed 's/source_refs: *//')" ]]; then
            local fm_lifecycle
            fm_lifecycle="$(grep '^lifecycle:' "$f" 2>/dev/null | head -1 | sed 's/lifecycle: *//' | tr -d '"')"
            [[ "$fm_lifecycle" != "archived" ]] && \
              emit_finding "info" "source-trail" "$f" "source_refs is empty (no source provenance)" "run wiki-ingest with original source"
          fi
          continue
        fi
        if [[ $in_refs -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
          local ref_path
          ref_path="$(echo "$line" | sed 's/^[[:space:]]*- *//' | tr -d '"')"
          if [[ -n "$ref_path" ]] && [[ ! -f "${raw_dir}/$(basename "$ref_path")" ]]; then
            emit_finding "error" "source-trail" "$f" "source_refs: $ref_path -- file not found in raw/" "re-archive source or remove the reference"
          fi
          # Check subsequent list items
          if [[ "$line" =~ ^[^[:space:]] && ! "$line" =~ ^source_refs ]]; then
            in_refs=0
          fi
        fi
      done < "$f"
    done
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Check 8: Wikilink consistency ----
  if check_enabled "wikilink-consistency"; then
    if ! (( json_output )); then
      printf '## Wikilink Consistency\n\n'
    fi
    # Check person pages link to their team
    if [[ -d "$WIKI_PEOPLE" ]]; then
      for f in "$WIKI_PEOPLE"/*.md; do
        [[ -f "$f" ]] || continue
        local person_team
        person_team="$(grep '^team:' "$f" 2>/dev/null | head -1 | sed 's/team: *//' | tr -d '"')"
        if [[ -n "$person_team" ]] && [[ "$person_team" != "null" ]]; then
          if ! grep -q "\[\[${person_team}\]\]" "$f" 2>/dev/null; then
            emit_finding "warning" "wikilink-consistency" "$f" "does not link to team [[$person_team]]" "add [[$person_team]] to page body"
          fi
        fi
      done
    fi

    # Check team pages list all members via wikilinks
    if [[ -d "$WIKI_TEAMS" ]]; then
      for f in "$WIKI_TEAMS"/*.md; do
        [[ -f "$f" ]] || continue
        local team_members
        team_members="$(grep '^members:' "$f" 2>/dev/null | head -1 | sed 's/members: *//' | tr -d '[]')"
        if [[ -n "$team_members" ]]; then
          IFS=',' read -ra members <<< "$team_members"
          for m in "${members[@]}"; do
            m="$(echo "$m" | tr -d ' ')"
            [[ -z "$m" ]] && continue
            if ! grep -q "\[\[${m}\]\]" "$f" 2>/dev/null; then
              emit_finding "warning" "wikilink-consistency" "$f" "member $m not linked via [[$m]]" "add [[$m]] to members section"
            fi
          done
        fi
      done
    fi
    if ! (( json_output )); then printf '\n'; fi
  fi

  # ---- Summary ----
  if ! (( json_output )); then
    printf '## Summary\n\n'
    printf '  Errors:   %s\n' "$error_count"
    printf '  Warnings: %s\n' "$warning_count"
    printf '  Info:     %s\n' "$info_count"

    if (( error_count == 0 )) && (( warning_count == 0 )); then
      printf '\nWiki is clean. No findings.\n'
    else
      printf '\nRun /software-house wiki-lint --fix-suggestions for suggested commands.\n'
      printf 'Wiki-lint never modifies state automatically.\n'
    fi
  fi

  if (( error_count > 0 )); then
    return 1
  fi
  return 0
}