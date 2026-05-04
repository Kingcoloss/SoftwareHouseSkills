#!/usr/bin/env bash
# fire.sh -- remove an agent (archive, never delete)
# Spec: operations/fire.md | Tier 4 (destructive)

op_fire() {
  local name=""
  local team=""
  local pool=0

  while (( $# > 0 )); do
    case "$1" in
      --team)  team="$2"; shift 2 ;;
      --pool)  pool=1; shift ;;
      --help|-h)
        printf 'Usage: fire <name> [--team <t>] [--pool]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Error: agent name is required.\n'
    return 1
  fi
  if ! validate_name "$name"; then return 1; fi

  require_company_init || return 1

  # Resolve canonical file
  local canonical_file=""
  if (( pool )); then
    canonical_file="$AGENTS_GLOBAL/${name}.md"
  else
    # TODO: Resolve from team/project context
    canonical_file="$AGENTS_GLOBAL/${name}.md"
  fi

  if [[ ! -f "$canonical_file" ]]; then
    printf 'Error: agent %s not found.\n' "$name"
    return 1
  fi

  read_agent "$canonical_file"

  if [[ "$AGENT_STATUS" == "alumni" ]]; then
    printf 'Error: %s is already archived (status: alumni). Use /software-house list --alumni to inspect.\n' "$name"
    return 1
  fi

  # Compute archive paths
  local utc_ts_compact
  utc_ts_compact="$(utc_timestamp_compact)"
  local utc_d
  utc_d="$(utc_date)"

  local archive_dir
  local archive_file
  if (( pool )); then
    mkdir -p "$AGENTS_GLOBAL/_archived"
    archive_dir="$AGENTS_GLOBAL/_archived"
    archive_file="$AGENTS_GLOBAL/_archived/${name}-${utc_ts_compact}.md"
  else
    # TODO: Resolve project root for team-scoped archive
    archive_dir="$AGENTS_GLOBAL/_archived"
    archive_file="$AGENTS_GLOBAL/_archived/${name}-${utc_ts_compact}.md"
    mkdir -p "$archive_dir"
  fi

  local wiki_archive="$ALUMNI/${name}.md"

  # Step 3: Tier-4 step 1 -- impact disclosure
  printf '\nImpact of firing %s:\n\n' "$name"
  printf '  FILES TO ARCHIVE (recoverable):\n'
  printf '    %s\n' "$canonical_file"
  printf '      -> %s\n' "$archive_file"
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    printf '    %s/%s.md\n' "$WIKI_PEOPLE" "$name"
    printf '      -> %s\n' "$wiki_archive"
  fi
  printf '\n  ADAPTERS TO REMOVE (auto-generated, recreated by re-hire):\n'
  # TODO: List adapter paths when project root is resolved
  printf '    (adapter detection TODO)\n'
  printf '\n  RESTORE COMMAND:\n'
  printf "    mv '%s' '%s'\n" "$archive_file" "$canonical_file"
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    printf "    mv '%s' '%s/%s.md'\n" "$wiki_archive" "$WIKI_PEOPLE" "$name"
  fi
  printf '    # Then re-run: /software-house onboard %s\n' "$name"

  if ! confirm 4 "$name"; then
    return 1
  fi

  # Execute
  if dry_run_msg "Would archive agent $name"; then
    return 0
  fi

  # Step 6: Archive canonical agent file
  # Update frontmatter first
  write_agent_field "$canonical_file" "status" "alumni"
  write_agent_field "$canonical_file" "fired_at" "$utc_d"
  mv "$canonical_file" "$archive_file"

  # Step 7: Archive wiki people page
  if [[ -f "$WIKI_PEOPLE/${name}.md" ]]; then
    write_agent_field "$WIKI_PEOPLE/${name}.md" "status" "alumni"
    write_agent_field "$WIKI_PEOPLE/${name}.md" "fired_at" "$utc_d"
    mv "$WIKI_PEOPLE/${name}.md" "$wiki_archive"
  fi

  # Step 8-9: Archive sidecar and remove adapters
  # TODO: Implement when project root resolution is available.

  # Step 12: Append audit log
  local utc_ts
  utc_ts="$(utc_now)"
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"fire\",\"scope\":\"agent:$name\",\"args\":{\"name\":\"$name\",\"team\":\"$AGENT_TEAM\",\"pool\":$pool},\"diff\":{\"archived\":[\"$archive_file\",\"$wiki_archive\"],\"removed\":[]},\"confirmation\":{\"tier\":4},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  # Step 13: Report
  printf '\nFired %s\n' "$name"
  printf '  Archived canonical:  %s\n' "$archive_file"
  printf '  Archived wiki page:  %s\n' "$wiki_archive"
  printf '\nTo restore:\n'
  printf "  mv '%s' '%s'\n" "$archive_file" "$canonical_file"
  printf "  mv '%s' '%s/%s.md'\n" "$wiki_archive" "$WIKI_PEOPLE" "$name"
  printf '  /software-house onboard %s\n' "$name"
}