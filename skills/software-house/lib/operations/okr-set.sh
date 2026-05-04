#!/usr/bin/env bash
# okr-set.sh -- set OKRs at company, department, or team tier
# Spec: operations/okr-set.md | Tier 2 (Tier 3 with --replace)

op_okr_set() {
  local tier=""
  local quarter=""
  local objective=""
  local kr=""
  local owner=""
  local replace=0

  while (( $# > 0 )); do
    case "$1" in
      --tier)       tier="$2"; shift 2 ;;
      --quarter)   quarter="$2"; shift 2 ;;
      --objective) objective="$2"; shift 2 ;;
      --kr)         kr="$2"; shift 2 ;;
      --owner)      owner="$2"; shift 2 ;;
      --replace)    replace=1; shift ;;
      --help|-h)
        printf 'Usage: okr-set --tier <company|dept|team> --quarter <YYYY-QN> --objective "<text>" --kr "<text> (target: <val>)" [--owner <name>] [--replace]\n'
        return 0
        ;;
      *) shift ;;
    esac
  done

  if [[ -z "$tier" ]]; then printf 'Error: --tier is required.\n'; return 1; fi
  if [[ -z "$quarter" ]]; then printf 'Error: --quarter is required.\n'; return 1; fi
  if [[ -z "$objective" ]]; then printf 'Error: --objective is required.\n'; return 1; fi
  if [[ -z "$kr" ]]; then printf 'Error: --kr is required.\n'; return 1; fi

  require_company_init || return 1

  local effective_tier=2
  if (( replace )); then effective_tier=3; fi

  # Determine OKR file path based on tier
  local okr_file=""
  case "$tier" in
    company)
      okr_file="$COMPANY_HOME/okrs/${quarter}.md"
      ;;
    dept)
      # TODO: Requires --dept argument
      okr_file="$COMPANY_HOME/okrs/${quarter}.md"
      ;;
    team)
      # TODO: Requires team resolution
      okr_file="$COMPANY_HOME/okrs/${quarter}.md"
      ;;
    *)
      printf 'Error: --tier must be company, dept, or team.\n'; return 1
      ;;
  esac

  # Confirmation
  if (( effective_tier == 2 )); then
    printf '\nI will create OKR for %s (%s):\n' "$quarter" "$tier"
    printf '  Objective: %s\n' "$objective"
    printf '  KR: %s\n' "$kr"
    if ! confirm 2; then return 1; fi
  else
    printf '\nI will replace OKR for %s (%s):\n' "$quarter" "$tier"
    printf '  Objective: %s\n' "$objective"
    printf '  KR: %s\n' "$kr"
    if ! confirm 3; then return 1; fi
  fi

  if dry_run_msg "Would set OKR for $quarter ($tier)"; then
    return 0
  fi

  local utc_d
  utc_d="$(utc_date)"
  local utc_ts
  utc_ts="$(utc_now)"

  mkdir -p "$(dirname "$okr_file")"

  if [[ ! -f "$okr_file" ]]; then
    cat > "$okr_file" << OKRHEOF
# OKRs -- $quarter

## Objective: $objective

### Key Results

- [ ] $kr
OKRHEOF
  else
    # TODO: Append key result to existing OKR file
    printf '\n- [ ] %s\n' "$kr" >> "$okr_file"
  fi

  local audit_entry
  audit_entry="{\"ts\":\"$utc_ts\",\"actor\":\"user\",\"op\":\"okr-set\",\"scope\":\"$tier\",\"args\":{\"tier\":\"$tier\",\"quarter\":\"$quarter\",\"objective\":\"$objective\",\"replace\":$replace},\"diff\":{\"created\":[\"$okr_file\"]},\"confirmation\":{\"tier\":$effective_tier},\"egress_consent\":{\"required\":false},\"result\":\"ok\"}"
  audit_log "$audit_entry"

  printf '\nOKR set for %s (%s)\n' "$quarter" "$tier"
}