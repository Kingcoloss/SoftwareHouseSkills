#!/usr/bin/env bash
# dept-create.sh -- create a new department
# Spec: operations/dept-create.md | Tier 2 (additive, Tier 3 with --force)

op_dept_create() {
  local name=""
  local parent=""
  local charter=""
  local charter_from=""
  local force=0

  while (( $# > 0 )); do
    case "$1" in
      --parent)        parent="$2"; shift 2 ;;
      --charter)       charter="$2"; shift 2 ;;
      --charter-from)  charter_from="$2"; shift 2 ;;
      --force)         force=1; shift ;;
      --help|-h)
        printf 'Usage: dept-create <name> [--parent <dept>] [--charter "<text>"] [--charter-from <path>] [--force]\n'
        return 0
        ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else shift; fi ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Error: department name is required.\n'
    return 1
  fi
  if ! validate_name "$name"; then return 1; fi

  require_company_init || return 1

  # Validate --charter and --charter-from mutually exclusive
  if [[ -n "$charter" ]] && [[ -n "$charter_from" ]]; then
    printf 'Error: use --charter or --charter-from, not both.\n'
    return 1
  fi

  # Validate parent
  if [[ -n "$parent" ]] && [[ ! -d "$DEPARTMENTS_HOME/$parent" ]]; then
    printf 'Error: parent department %s does not exist. Create it first or omit --parent.\n' "$parent"
    return 1
  fi

  # Validate charter-from
  if [[ -n "$charter_from" ]] && [[ ! -r "$charter_from" ]]; then
    printf 'Error: cannot read charter file at %s.\n' "$charter_from"
    return 1
  fi

  # Resolve charter text
  local charter_text=""
  if [[ -n "$charter" ]]; then
    charter_text="$charter"
  elif [[ -n "$charter_from" ]]; then
    charter_text="$(cat "$charter_from")"
  else
    charter_text="(No charter text provided. Edit $DEPARTMENTS_HOME/$name/CLAUDE.md to add department charter.)"
  fi

  # Conflict check
  local effective_tier=2
  if [[ -d "$DEPARTMENTS_HOME/$name" ]]; then
    if (( ! force )); then
      printf 'Error: department %s already exists at %s/%s/.\n' "$name" "$DEPARTMENTS_HOME" "$name"
      printf 'Recovery: run /software-house dept-create %s --force to overwrite.\n' "$name"
      return 1
    fi
    effective_tier=3
  fi

  # Confirmation
  if (( effective_tier == 2 )); then
    printf '\nI will create the following:\n'
    printf '  %s/%s/\n' "$DEPARTMENTS_HOME" "$name"
    printf '  %s/%s/CLAUDE.md\n' "$DEPARTMENTS_HOME" "$name"
    printf '  %s/%s/agents/\n' "$DEPARTMENTS_HOME" "$name"
    printf '  %s/%s.md\n' "$WIKI_DEPTS" "$name"
    if ! confirm 2; then return 1; fi
  else
    printf '\nI will overwrite the following:\n'
    printf '  %s/%s/CLAUDE.md\n' "$DEPARTMENTS_HOME" "$name"
    printf '  %s/%s.md\n' "$WIKI_DEPTS" "$name"
    if ! confirm 3; then return 1; fi
  fi

  if dry_run_msg "Would create department $name"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  # Create directories
  mkdir -p "$DEPARTMENTS_HOME/$name/agents"

  # Write charter CLAUDE.md
  cat > "$DEPARTMENTS_HOME/$name/CLAUDE.md" << CHARTEREOF
---
type: department-charter
name: $name
parent: ${parent:-null}
classification: internal
created_at: $utc_d
head: null
---

# Department: $name

## Charter

$charter_text

## Standards

(Add department-wide coding/process standards here.)

## Teams

(Teams in this department are listed in $WIKI_DEPTS/$name.md)
CHARTEREOF

  # Write okrs.md
  cat > "$DEPARTMENTS_HOME/$name/okrs.md" << OKRSEOF
# OKRs -- $name

(No OKRs set yet. Run /software-house okr-set --dept $name to set objectives.)
OKRSEOF

  # Write wiki depts entry
  local desc
  desc="$(echo "$charter_text" | head -1 | sed 's/^(//' | cut -c1-80)"
  cat > "$WIKI_DEPTS/${name}.md" << WIKIEOF
---
name: $name
description: "$desc"
head: null
parent: ${parent:-null}
teams: []
status: active
classification: internal
created_at: $utc_d
---

# Department: $name

See charter: $DEPARTMENTS_HOME/$name/CLAUDE.md

## Teams

(none yet)
WIKIEOF

  # Update parent if applicable
  if [[ -n "$parent" ]] && [[ -f "$WIKI_DEPTS/${parent}.md" ]]; then
    # TODO: Add $name to parent's teams list in frontmatter
    : # Placeholder -- requires frontmatter list manipulation
  fi

  # Rebuild company index
  rebuild_index "$COMPANY_INDEX" "$COMPANY_HOME/wiki" "Company Wiki Index"

  # Audit log
  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"dept-create\",\"scope\":\"company\",\"args\":{\"name\":\"$name\",\"parent\":\"${parent:-null}\",\"force\":$force},\"diff\":{\"created\":[\"$DEPARTMENTS_HOME/$name/\",\"$DEPARTMENTS_HOME/$name/CLAUDE.md\",\"$WIKI_DEPTS/$name.md\"]},\"confirmation\":{\"tier\":$effective_tier},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nDepartment created: %s\n' "$name"
  printf '  Charter:  %s/%s/CLAUDE.md\n' "$DEPARTMENTS_HOME" "$name"
  printf '  Wiki:     %s/%s.md\n' "$WIKI_DEPTS" "$name"
  printf '  Parent:   %s\n' "${parent:-(none, top-level)}"
  printf '\n  Next steps:\n'
  printf '    /software-house dept-assign <agent> %s   add an agent to this department\n' "$name"
}