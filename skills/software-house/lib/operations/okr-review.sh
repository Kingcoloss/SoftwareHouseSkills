#!/usr/bin/env bash
# okr-review.sh -- review OKR progress
# Spec: operations/okr-review.md | Tier 1 (read-only)

op_okr_review() {
  local tier=""
  local quarter=""
  local dept=""
  local team=""

  while (( $# > 0 )); do
    case "$1" in
      --tier)     tier="$2"; shift 2 ;;
      --quarter)  quarter="$2"; shift 2 ;;
      --dept)     dept="$2"; shift 2 ;;
      --team)     team="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: okr-review [--tier <tier>] [--quarter <YYYY-QN>] [--dept <name>] [--team <name>]\n'
        return 0
        ;;
      *) shift ;;
    esac
  done

  require_company_init || return 1

  # Determine which OKR files to review
  local okr_files=()

  if [[ -n "$quarter" ]]; then
    # Look for specific quarter
    for f in "$COMPANY_HOME/okrs/${quarter}.md" \
             "$DEPARTMENTS_HOME"/*/okrs/"${quarter}.md"; do
      [[ -f "$f" ]] && okr_files+=("$f")
    done
  else
    # Review all OKR files
    for f in "$COMPANY_HOME/okrs"/*.md; do
      [[ -f "$f" ]] && okr_files+=("$f")
    done
  fi

  if (( ${#okr_files[@]} == 0 )); then
    printf 'No OKR files found.\n'
    printf 'Run /software-house okr-set to create OKRs.\n'
    return 0
  fi

  # Display OKR status
  printf '# OKR Review\n\n'
  for okr_file in "${okr_files[@]}"; do
    printf '## %s\n\n' "$(basename "$okr_file" .md)"
    if [[ -f "$okr_file" ]]; then
      cat "$okr_file"
    else
      printf '(file not found)\n'
    fi
    printf '\n'
  done
}