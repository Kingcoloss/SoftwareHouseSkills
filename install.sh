#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 kanganapong sriduang

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/skills/software-house"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

print_usage() {
    printf 'Usage: %s [OPTIONS]\n\n' "$0"
    printf 'Install the software-house skill into each detected agent CLI harness.\n\n'
    printf 'Detected harnesses (by existence of config directories):\n'
    printf '  claude-code   ~/.claude               -> ~/.claude/skills/software-house/\n'
    printf '  codex         ~/.agents or ~/.codex    -> ~/.agents/skills/software-house/\n'
    printf '  gemini        ~/.gemini                -> ~/.gemini/extensions/software-house/\n\n'
    printf 'Options:\n'
    printf '  (none)                    Copy-install into all detected harnesses\n'
    printf '                            (prompts before overwriting an existing target)\n'
    printf '  --force                   Skip all confirmation prompts\n'
    printf '  --symlink                 Symlink target -> source instead of copying (dev mode)\n'
    printf '  --uninstall               Remove the skill from each detected harness\n'
    printf '  --harness <id>[,<id>...]  Restrict to a subset of harnesses.\n'
    printf '                            Valid ids: claude-code, codex, gemini\n'
    printf '  --list-harnesses          Print harness detection table and exit 0\n'
    printf '  --fix-adapters            Regenerate per-project adapter shims from canonical\n'
    printf '                            agent files under ~/.software-house/agents/\n'
    printf '  --help, -h                Print this help and exit\n\n'
    printf 'Exit codes: 0=success, 1=aborted/precondition failure, 2=invalid arguments\n'
}

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

die_usage() {
    printf 'Error: %s\n' "$1" >&2
    print_usage >&2
    exit 2
}

confirm() {
    # $1 = prompt text; returns 0 if user says yes/y/proceed/ok (case-insensitive), 1 otherwise
    # Matches safety.md section 9 affirmative protocol
    printf '%s [y/N] ' "$1"
    read -r _answer
    case "${_answer}" in
        y|Y|yes|YES|Yes|proceed|Proceed|PROCEED|ok|OK|Ok) return 0 ;;
        *)   return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Version comparison (semver major.minor.patch)
# Returns: lt=1, eq=0, gt=2 via exit code
# ---------------------------------------------------------------------------

version_compare() {
    # $1 and $2 are "X.Y.Z" version strings
    # Returns 0 if equal, 1 if $1 < $2, 2 if $1 > $2
    _vc1_major="${1%%.*}"; _vc1_rest="${1#*.}"; _vc1_minor="${_vc1_rest%%.*}"; _vc1_patch="${_vc1_rest#*.}"
    _vc2_major="${2%%.*}"; _vc2_rest="${2#*.}"; _vc2_minor="${_vc2_rest%%.*}"; _vc2_patch="${_vc2_rest#*.}"

    if test "${_vc1_major}" -lt "${_vc2_major}"; then return 1; fi
    if test "${_vc1_major}" -gt "${_vc2_major}"; then return 2; fi
    if test "${_vc1_minor}" -lt "${_vc2_minor}"; then return 1; fi
    if test "${_vc1_minor}" -gt "${_vc2_minor}"; then return 2; fi
    if test "${_vc1_patch}" -lt "${_vc2_patch}"; then return 1; fi
    if test "${_vc1_patch}" -gt "${_vc2_patch}"; then return 2; fi
    return 0
}

# ---------------------------------------------------------------------------
# Read version from a file (first line, stripped)
# ---------------------------------------------------------------------------

read_version() {
    # $1 = path to VERSION file
    if test -f "$1"; then
        # Read first line and strip whitespace
        _ver="$(head -n 1 "$1" | tr -d '[:space:]')"
        printf '%s' "${_ver}"
    else
        printf ''
    fi
}

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

FLAG_FORCE=0
FLAG_SYMLINK=0
FLAG_UNINSTALL=0
FLAG_LIST=0
FLAG_FIX_ADAPTERS=0
HARNESS_FILTER=""

_skip_next=0
for _arg in "$@"; do
    if test "${_skip_next}" -eq 1; then
        HARNESS_FILTER="${_arg}"
        _skip_next=0
        continue
    fi
    case "${_arg}" in
        --force)          FLAG_FORCE=1 ;;
        --symlink)        FLAG_SYMLINK=1 ;;
        --uninstall)      FLAG_UNINSTALL=1 ;;
        --list-harnesses) FLAG_LIST=1 ;;
        --fix-adapters)   FLAG_FIX_ADAPTERS=1 ;;
        --harness)        _skip_next=1 ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        --*)
            die_usage "Unknown option: ${_arg}"
            ;;
        *)
            # Could be the value to a previous --harness that was already consumed
            # If _skip_next was set we handled it above; anything else is unknown
            die_usage "Unknown argument: ${_arg}"
            ;;
    esac
done

if test "${_skip_next}" -eq 1; then
    die_usage "--harness requires an argument (e.g. --harness claude-code,gemini)"
fi

if test "${FLAG_SYMLINK}" -eq 1 && test "${FLAG_UNINSTALL}" -eq 1; then
    die_usage "--symlink and --uninstall cannot be used together."
fi

if test "${FLAG_FIX_ADAPTERS}" -eq 1 && test "${FLAG_UNINSTALL}" -eq 1; then
    die_usage "--fix-adapters and --uninstall cannot be used together."
fi

# Validate --harness values if provided
if test -n "${HARNESS_FILTER}"; then
    # Walk comma-separated list and validate each id
    _remaining="${HARNESS_FILTER}"
    while test -n "${_remaining}"; do
        # Extract token up to first comma
        _token="${_remaining%%,*}"
        # Advance past the comma (or clear if no comma)
        case "${_remaining}" in
            *,*) _remaining="${_remaining#*,}" ;;
            *)   _remaining="" ;;
        esac
        case "${_token}" in
            claude-code|codex|gemini) ;;
            *) die_usage "Invalid harness id '${_token}'. Valid ids: claude-code, codex, gemini" ;;
        esac
    done
fi

# ---------------------------------------------------------------------------
# Harness detection
# ---------------------------------------------------------------------------

# For each harness, determine: present (1/0) and install path.
# Codex: prefer ~/.agents; fall back label shows whichever exists.

detect_claude_code() {
    if test -d "${HOME}/.claude"; then
        printf "present"
    else
        printf "absent"
    fi
}

detect_codex() {
    # Check CODEX_HOME env var first; fall back to ~/.agents, then ~/.codex
    _codex_root="${CODEX_HOME:-}"
    if test -n "${_codex_root}" && test -d "${_codex_root}"; then
        printf "present:codex-home"
        return 0
    fi
    if test -d "${HOME}/.agents"; then
        printf "present:agents"
    elif test -d "${HOME}/.codex"; then
        printf "present:codex"
    else
        printf "absent"
    fi
}

detect_gemini() {
    if test -d "${HOME}/.gemini"; then
        printf "present"
    else
        printf "absent"
    fi
}

CC_STATUS="$(detect_claude_code)"
CX_STATUS="$(detect_codex)"
GE_STATUS="$(detect_gemini)"

# Resolve Codex dir label and install path
case "${CX_STATUS}" in
    present:codex-home)
        _codex_root="${CODEX_HOME:-}"
        CX_DIR="${CODEX_HOME}"
        CX_TARGET="${_codex_root}/skills/software-house"
        ;;
    present:agents)
        CX_DIR="~/.agents"
        CX_TARGET="${HOME}/.agents/skills/software-house"
        ;;
    present:codex)
        CX_DIR="~/.codex"
        CX_TARGET="${HOME}/.agents/skills/software-house"
        ;;
    *)
        CX_DIR="~/.agents (or ~/.codex)"
        CX_TARGET="${HOME}/.agents/skills/software-house"
        ;;
esac

CC_TARGET="${HOME}/.claude/skills/software-house"
GE_TARGET="${HOME}/.gemini/extensions/software-house"

# Determine action label for table
_action_label() {
    # $1=status  $2=install_path  $3=flag_uninstall
    _status="$1"
    _path="$2"
    _uninstall="$3"
    if test "${_status}" = "absent"; then
        printf "skip"
    elif test "${_uninstall}" -eq 1; then
        printf "uninstall -> %s" "${_path}"
    else
        printf "install -> %s" "${_path}"
    fi
}

CC_ACTION="$(_action_label "${CC_STATUS}" "${CC_TARGET}" "${FLAG_UNINSTALL}")"
CX_ACTION="$(_action_label "${CX_STATUS}" "${CX_TARGET}" "${FLAG_UNINSTALL}")"
GE_ACTION="$(_action_label "${GE_STATUS}" "${GE_TARGET}" "${FLAG_UNINSTALL}")"

# Replace "present:agents" / "present:codex" / "present:codex-home" with "present" for display
_display_status() {
    case "$1" in
        present:*) printf "present" ;;
        *) printf "%s" "$1" ;;
    esac
}

CC_DISP="$(_display_status "${CC_STATUS}")"
CX_DISP="$(_display_status "${CX_STATUS}")"
GE_DISP="$(_display_status "${GE_STATUS}")"

# ---------------------------------------------------------------------------
# Print detection table (always, unless --help)
# ---------------------------------------------------------------------------

printf 'Detected harnesses:\n'
printf '  %-14s %-22s %-10s %s\n' "claude-code"  "~/.claude"           "${CC_DISP}"  "${CC_ACTION}"
printf '  %-14s %-22s %-10s %s\n' "codex"        "${CX_DIR}"           "${CX_DISP}"  "${CX_ACTION}"
printf '  %-14s %-22s %-10s %s\n' "gemini"       "~/.gemini"           "${GE_DISP}"  "${GE_ACTION}"
printf '\n'

# --list-harnesses: exit after printing table
if test "${FLAG_LIST}" -eq 1; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Check that at least one harness is present
# ---------------------------------------------------------------------------

_any_present=0
if test "${CC_STATUS}" != "absent"; then _any_present=1; fi
if test "${CX_STATUS}" != "absent"; then _any_present=1; fi
if test "${GE_STATUS}" != "absent"; then _any_present=1; fi

if test "${_any_present}" -eq 0; then
    die "no agent CLI detected (looked for ~/.claude, ~/.codex/~/.agents, ~/.gemini). Install at least one and rerun."
fi

# ---------------------------------------------------------------------------
# Build the list of harnesses to operate on (detected INTERSECT filter)
# ---------------------------------------------------------------------------

# Returns 1 if the given harness id is excluded by --harness filter, 0 if included
_harness_selected() {
    _id="$1"
    if test -z "${HARNESS_FILTER}"; then
        return 0   # no filter = all selected
    fi
    _rem="${HARNESS_FILTER}"
    while test -n "${_rem}"; do
        _tok="${_rem%%,*}"
        case "${_rem}" in
            *,*) _rem="${_rem#*,}" ;;
            *)   _rem="" ;;
        esac
        if test "${_tok}" = "${_id}"; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# --fix-adapters: regenerate per-project adapter shims from canonical agents
# ---------------------------------------------------------------------------

run_fix_adapters() {
    _sh_agents="${HOME}/.software-house/agents"
    _fixed=0
    _skipped=0

    if ! test -d "${_sh_agents}"; then
        printf 'No canonical agents directory found at %s\n' "${_sh_agents}"
        printf 'Run /software-house init first, or hire at least one agent.\n'
        return 0
    fi

    printf 'Re-syncing adapter shims from canonical agents...\n\n'

    # Find all projects from projects-index.json
    _projects_index="${HOME}/.software-house/projects-index.json"
    if ! test -f "${_projects_index}"; then
        # No projects index -- scan for global freelance agents only
        printf 'No projects-index.json found. Syncing global adapters only.\n'
    fi

    # Process global (freelance pool) agents
    for _agent_file in "${_sh_agents}"/*.md; do
        test -f "${_agent_file}" || continue
        _agent_name="$(basename "${_agent_file}" .md)"
        # Extract frontmatter fields for shim generation
        _agent_desc=""
        _agent_model=""
        _in_fm=0
        while IFS= read -r _line; do
            case "${_line}" in
                "---")
                    if test "${_in_fm}" -eq 0; then
                        _in_fm=1
                        continue
                    else
                        break
                    fi
                    ;;
                description:*) _agent_desc="${_line#description: }" ;;
                model:*) _agent_model="${_line#model: }" ;;
            esac
        done < "${_agent_file}"

        # Write adapters to each detected harness location
        # Claude Code global adapters
        if test -d "${HOME}/.claude/agents"; then
            _shim_path="${HOME}/.claude/agents/${_agent_name}.md"
            printf '  Updating %s\n' "${_shim_path}"
            cat > "${_shim_path}" <<SHIM_EOF
---
name: ${_agent_name}
description: ${_agent_desc}
model: ${_agent_model}
---

Canonical definition at: ${_sh_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
            _fixed=$(( _fixed + 1 ))
        fi

        # Codex global adapters
        if test -d "${HOME}/.codex/agents" || test -d "${HOME}/.agents/agents"; then
            _codex_agents_dir="${HOME}/.agents/agents"
            test -d "${_codex_agents_dir}" || _codex_agents_dir="${HOME}/.codex/agents"
            if test -d "${_codex_agents_dir}"; then
                _shim_path="${_codex_agents_dir}/${_agent_name}.md"
                printf '  Updating %s\n' "${_shim_path}"
                cat > "${_shim_path}" <<SHIM_EOF
---
name: ${_agent_name}
description: ${_agent_desc}
model: ${_agent_model}
---

Canonical definition at: ${_sh_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
                _fixed=$(( _fixed + 1 ))
            fi
        fi

        # Gemini global adapters
        if test -d "${HOME}/.gemini/extensions"; then
            _ext_dir="${HOME}/.gemini/extensions/${_agent_name}"
            mkdir -p "${_ext_dir}"
            _shim_gemini="${_ext_dir}/GEMINI.md"
            printf '  Updating %s\n' "${_shim_gemini}"
            cat > "${_shim_gemini}" <<SHIM_EOF
# ${_agent_name}

Canonical definition at: ${_sh_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
            _fixed=$(( _fixed + 1 ))
        fi
    done

    # Process per-project team agents
    if test -f "${_projects_index}"; then
        # Parse projects-index.json line by line for project paths
        # Format: {"<path>": {"team": "<name>", "department": "<name>"}}
        # Use simple grep/sed extraction (no jq dependency)
        _paths="$(grep -o '"[^"]*":' "${_projects_index}" | sed 's/^"//; s/":$//' | tail -n +2)"
        for _proj_path in ${_paths}; do
            _team_agents="${_proj_path}/.software-house/agents"
            if ! test -d "${_team_agents}"; then
                continue
            fi
            for _agent_file in "${_team_agents}"/*.md; do
                test -f "${_agent_file}" || continue
                _agent_name="$(basename "${_agent_file}" .md)"
                # Extract frontmatter
                _agent_desc=""
                _agent_model=""
                _in_fm=0
                while IFS= read -r _line; do
                    case "${_line}" in
                        "---")
                            if test "${_in_fm}" -eq 0; then
                                _in_fm=1
                                continue
                            else
                                break
                            fi
                            ;;
                        description:*) _agent_desc="${_line#description: }" ;;
                        model:*) _agent_model="${_line#model: }" ;;
                    esac
                done < "${_agent_file}"

                # Claude Code project adapters
                _claude_agents="${_proj_path}/.claude/agents"
                if test -d "${_claude_agents}"; then
                    _shim_path="${_claude_agents}/${_agent_name}.md"
                    printf '  Updating %s\n' "${_shim_path}"
                    cat > "${_shim_path}" <<SHIM_EOF
---
name: ${_agent_name}
description: ${_agent_desc}
model: ${_agent_model}
---

Canonical definition at: ${_team_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
                    _fixed=$(( _fixed + 1 ))
                fi

                # Codex project adapters
                _codex_agents="${_proj_path}/.codex/agents"
                if test -d "${_codex_agents}"; then
                    _shim_path="${_codex_agents}/${_agent_name}.md"
                    printf '  Updating %s\n' "${_shim_path}"
                    cat > "${_shim_path}" <<SHIM_EOF
---
name: ${_agent_name}
description: ${_agent_desc}
model: ${_agent_model}
---

Canonical definition at: ${_team_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
                    _fixed=$(( _fixed + 1 ))
                fi

                # Gemini project adapters
                _gemini_ext="${_proj_path}/.gemini/extensions/${_agent_name}"
                if test -d "${_gemini_ext}" || test -d "${_proj_path}/.gemini/extensions"; then
                    mkdir -p "${_gemini_ext}"
                    _shim_gemini="${_gemini_ext}/GEMINI.md"
                    printf '  Updating %s\n' "${_shim_gemini}"
                    cat > "${_shim_gemini}" <<SHIM_EOF
# ${_agent_name}

Canonical definition at: ${_team_agents}/${_agent_name}.md

Read that file before responding.
SHIM_EOF
                    _fixed=$(( _fixed + 1 ))
                fi
            done
        done
    fi

    printf '\nAdapter re-sync complete: %d adapter(s) updated.\n' "${_fixed}"
    if test "${_fixed}" -eq 0; then
        printf 'No adapters were updated. Ensure agents exist and harness directories are present.\n'
    fi
}

# Handle --fix-adapters early (does not need full install flow)
if test "${FLAG_FIX_ADAPTERS}" -eq 1; then
    run_fix_adapters
    exit 0
fi

# ---------------------------------------------------------------------------
# Source check (only needed for install/symlink)
# ---------------------------------------------------------------------------

check_source() {
    # Verify all required source files exist
    _required_files="
        SKILL.md
        policies/safety.md
        policies/privacy.md
        manifest.yaml
        config/providers.json
        config/models-config.json
        VERSION
    "

    _missing=0
    for _file in ${_required_files}; do
        if ! test -f "${SOURCE}/${_file}"; then
            printf 'Error: Required source file missing: %s/%s\n' "${SOURCE}" "${_file}" >&2
            _missing=1
        fi
    done

    if test "${_missing}" -eq 1; then
        die "One or more required source files are missing. Is this the correct repository?"
    fi
}

# ---------------------------------------------------------------------------
# Version detection and changelog preview
# ---------------------------------------------------------------------------

# Determine source version
SOURCE_VERSION=""
if test -f "${SOURCE}/VERSION"; then
    SOURCE_VERSION="$(read_version "${SOURCE}/VERSION")"
fi

# Determine installed version by checking the first detected harness target
INSTALLED_VERSION=""
_detect_installed_version() {
    # Check each harness target for an installed VERSION file
    if test -f "${CC_TARGET}/VERSION"; then
        INSTALLED_VERSION="$(read_version "${CC_TARGET}/VERSION")"
        return
    fi
    if test -f "${CX_TARGET}/VERSION"; then
        INSTALLED_VERSION="$(read_version "${CX_TARGET}/VERSION")"
        return
    fi
    if test -f "${GE_TARGET}/VERSION"; then
        INSTALLED_VERSION="$(read_version "${GE_TARGET}/VERSION")"
        return
    fi
}

# Only run version detection for install (not uninstall)
if test "${FLAG_UNINSTALL}" -eq 0 && test "${FLAG_SYMLINK}" -eq 0; then
    _detect_installed_version
fi

# Version comparison and action
VERSION_ACTION="fresh-install"
if test -n "${INSTALLED_VERSION}" && test -n "${SOURCE_VERSION}"; then
    # Capture exit code safely under set -e (|| suppresses exit-on-fail)
    version_compare "${SOURCE_VERSION}" "${INSTALLED_VERSION}" && _cmp=0 || _cmp=$?
    case "${_cmp}" in
        0) VERSION_ACTION="same-version" ;;
        2) VERSION_ACTION="upgrade" ;;
        1) VERSION_ACTION="downgrade" ;;
        *) VERSION_ACTION="same-version" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Changelog preview
# ---------------------------------------------------------------------------

show_changelog_preview() {
    # $1 = installed version, $2 = source version
    # Show entries from CHANGELOG.md between installed and source versions
    _changelog="${SOURCE}/CHANGELOG.md"
    if ! test -f "${_changelog}"; then
        printf '  (No CHANGELOG.md found in source)\n'
        return
    fi

    # Extract version headings and their content
    # Format: "## [X.Y.Z]" or "## [X.Y.Z] - YYYY-MM-DD"
    _printing=0
    _header_found=0
    while IFS= read -r _line; do
        case "${_line}" in
            "## ["*"]"*)
                # Extract version from header
                _hdr_ver="$(printf '%s' "${_line}" | sed 's/^## \[//; s/\].*$//')"
                if test "${_hdr_ver}" = "$1"; then
                    # Reached the old version -- stop printing
                    _printing=0
                    break
                fi
                _printing=1
                _header_found=1
                printf '  %s\n' "${_line}"
                ;;
            *)
                if test "${_printing}" -eq 1; then
                    # Only print non-empty content lines
                    case "${_line}" in
                        "") ;;  # skip blank lines for compactness
                        *)  printf '  %s\n' "${_line}" ;;
                    esac
                fi
                ;;
        esac
    done < "${_changelog}"

    if test "${_header_found}" -eq 0; then
        printf '  (No changelog entries found between %s and %s)\n' "$1" "$2"
    fi
}

# Print version info before proceeding
if test "${FLAG_UNINSTALL}" -eq 0; then
    if test -n "${SOURCE_VERSION}"; then
        printf 'Source version:   %s\n' "${SOURCE_VERSION}"
    fi
    if test -n "${INSTALLED_VERSION}"; then
        printf 'Installed version: %s\n' "${INSTALLED_VERSION}"
    fi

    case "${VERSION_ACTION}" in
        fresh-install)
            printf 'Action: fresh install\n'
            ;;
        same-version)
            printf 'Action: same version already installed\n'
            if test "${FLAG_FORCE}" -eq 0; then
                if ! confirm "Version ${INSTALLED_VERSION} is already installed. Re-install anyway?"; then
                    printf 'Installation skipped (same version).\n'
                    exit 0
                fi
            else
                printf 'Re-installing same version (--force).\n'
            fi
            ;;
        upgrade)
            printf 'Action: upgrade %s -> %s\n' "${INSTALLED_VERSION}" "${SOURCE_VERSION}"
            printf '\nChanges since %s:\n' "${INSTALLED_VERSION}"
            show_changelog_preview "${INSTALLED_VERSION}" "${SOURCE_VERSION}"
            printf '\n'
            if test "${FLAG_FORCE}" -eq 0; then
                if ! confirm "Proceed with upgrade to ${SOURCE_VERSION}?"; then
                    printf 'Upgrade skipped.\n'
                    exit 0
                fi
            fi
            ;;
        downgrade)
            printf 'WARNING: downgrade detected -- source %s is older than installed %s\n' "${SOURCE_VERSION}" "${INSTALLED_VERSION}"
            printf '\nDowngrade changes (from %s to %s):\n' "${INSTALLED_VERSION}" "${SOURCE_VERSION}"
            show_changelog_preview "${SOURCE_VERSION}" "${INSTALLED_VERSION}"
            printf '\n'
            if test "${FLAG_FORCE}" -eq 0; then
                if ! confirm "Downgrade to ${SOURCE_VERSION} anyway?"; then
                    printf 'Downgrade aborted.\n'
                    exit 0
                fi
            else
                printf 'Downgrading (--force).\n'
            fi
            ;;
    esac
    printf '\n'
fi

# ---------------------------------------------------------------------------
# Migration runner
# ---------------------------------------------------------------------------

run_migrations() {
    # $1 = old version, $2 = new version
    # Runs all migrations/NNN-<name>.sh scripts between old and new version
    _migration_dir="${SOURCE}/migrations"
    if ! test -d "${_migration_dir}"; then
        printf '  (No migrations directory found -- skipping)\n'
        return
    fi

    # Find and sort migration scripts
    _migrations="$(find "${_migration_dir}" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)"
    if test -z "${_migrations}"; then
        printf '  (No migration scripts found)\n'
        return
    fi

    _ran=0
    for _migration in ${_migrations}; do
        _mname="$(basename "${_migration}")"
        printf '  Running migration: %s\n' "${_mname}"
        if sh "${_migration}" "${1}" "${2}"; then
            _ran=$(( _ran + 1 ))
        else
            printf '  WARNING: migration %s exited with non-zero status\n' "${_mname}"
        fi
    done

    if test "${_ran}" -gt 0; then
        printf '  %d migration(s) completed.\n' "${_ran}"
    fi
}

# Run migrations on version change (upgrade or downgrade)
if test "${FLAG_UNINSTALL}" -eq 0 && test "${FLAG_SYMLINK}" -eq 0; then
    if test "${VERSION_ACTION}" = "upgrade" || test "${VERSION_ACTION}" = "downgrade"; then
        printf 'Running schema migrations...\n'
        run_migrations "${INSTALLED_VERSION}" "${SOURCE_VERSION}"
        printf '\n'
    fi
fi

# ---------------------------------------------------------------------------
# Per-harness operations
# ---------------------------------------------------------------------------

# install_harness <harness-id> <status> <target>
install_harness() {
    _hid="$1"
    _hstatus="$2"
    _htarget="$3"

    if test "${_hstatus}" = "absent"; then
        return 0
    fi

    _parent_dir="$(dirname "${_htarget}")"

    # Check if target already exists
    if test -e "${_htarget}" || test -L "${_htarget}"; then
        if test "${FLAG_FORCE}" -eq 0 && test "${VERSION_ACTION}" != "upgrade" && test "${VERSION_ACTION}" != "downgrade"; then
            if ! confirm "Overwrite ${_htarget}?"; then
                printf '  %s: skipped (user chose not to overwrite)\n' "${_hid}"
                return 0
            fi
        fi
        # Preserve *.local.* files before removing the target
        _local_tmpdir=""
        if test -d "${_htarget}"; then
            _local_files="$(find "${_htarget}" -name '*.local.*' -type f 2>/dev/null || true)"
            if test -n "${_local_files}"; then
                _local_tmpdir="$(mktemp -d)"
                for _lf in ${_local_files}; do
                    _rel_path="${_lf#${_htarget}/}"
                    _save_dir="$(dirname "${_local_tmpdir}/${_rel_path}")"
                    mkdir -p "${_save_dir}"
                    cp "${_lf}" "${_local_tmpdir}/${_rel_path}"
                done
            fi
        fi
        # Remove existing
        if test -L "${_htarget}"; then
            rm "${_htarget}"
        else
            rm -rf "${_htarget}"
        fi
    else
        _local_tmpdir=""
    fi

    mkdir -p "${_parent_dir}"

    if test "${FLAG_SYMLINK}" -eq 1; then
        ln -s "${SOURCE}" "${_htarget}"
        if ! test -L "${_htarget}"; then
            die "Symlink creation failed for ${_hid}: ${_htarget} does not exist as a symlink."
        fi
        if ! test -f "${_htarget}/SKILL.md"; then
            die "Symlink does not resolve for ${_hid}: ${_htarget}/SKILL.md not reachable."
        fi
        printf '==> Installed: %s -> %s (symlink)\n' "${_hid}" "${_htarget}"
    else
        # Copy source to target, skipping *.local.* files
        # First, copy everything
        cp -R "${SOURCE}" "${_htarget}"
        if ! test -f "${_htarget}/SKILL.md"; then
            die "Copy succeeded but ${_htarget}/SKILL.md is missing for ${_hid}."
        fi

        # Remove any *.local.* files that were copied from source
        # (these should never be overwritten -- user overlays only)
        _copied_locals="$(find "${_htarget}" -name '*.local.*' -type f 2>/dev/null || true)"
        if test -n "${_copied_locals}"; then
            for _cl in ${_copied_locals}; do
                rm -f "${_cl}"
            done
        fi

        # Restore previously preserved local files
        if test -n "${_local_tmpdir}" && test -d "${_local_tmpdir}"; then
            _restored_locals="$(find "${_local_tmpdir}" -name '*.local.*' -type f 2>/dev/null || true)"
            if test -n "${_restored_locals}"; then
                for _rl in ${_restored_locals}; do
                    _rel_path="${_rl#${_local_tmpdir}/}"
                    _restore_path="${_htarget}/${_rel_path}"
                    _restore_dir="$(dirname "${_restore_path}")"
                    mkdir -p "${_restore_dir}"
                    cp "${_rl}" "${_restore_path}"
                    printf '  Preserved local overlay: %s\n' "${_rel_path}"
                done
            fi
            rm -rf "${_local_tmpdir}"
        fi

        printf '==> Installed: %s -> %s\n' "${_hid}" "${_htarget}"
    fi

    # Codex note
    if test "${_hid}" = "codex"; then
        printf '\n'
        printf 'Note: Codex requires manual registration. Add this to ~/.codex/config.toml:\n'
        printf '\n'
        printf '  [[skills]]\n'
        printf '  path = "~/.agents/skills/software-house"\n'
        printf '  enabled = true\n'
        printf '\n'
        printf 'Then restart Codex.\n'
        printf '\n'
    fi
}

# uninstall_harness <harness-id> <status> <target>
uninstall_harness() {
    _hid="$1"
    _hstatus="$2"
    _htarget="$3"

    if test "${_hstatus}" = "absent"; then
        return 0
    fi

    if ! test -e "${_htarget}" && ! test -L "${_htarget}"; then
        printf 'Nothing to uninstall for %s\n' "${_hid}"
        return 0
    fi

    if test "${FLAG_FORCE}" -eq 0; then
        if ! confirm "Remove ${_htarget}?"; then
            printf '  %s: skipped (user chose not to remove)\n' "${_hid}"
            return 0
        fi
    fi

    if test -L "${_htarget}"; then
        rm "${_htarget}"
    else
        rm -rf "${_htarget}"
    fi

    printf '==> Removed: %s -> %s\n' "${_hid}" "${_htarget}"
}

# ---------------------------------------------------------------------------
# Source check (for install modes)
# ---------------------------------------------------------------------------

if test "${FLAG_UNINSTALL}" -eq 0; then
    check_source
fi

# ---------------------------------------------------------------------------
# Execute per-harness (in order: claude-code, codex, gemini)
# ---------------------------------------------------------------------------

CC_RESULT="skipped"
CX_RESULT="skipped"
GE_RESULT="skipped"

# --- claude-code ---
if _harness_selected "claude-code"; then
    if test "${CC_STATUS}" = "absent"; then
        CC_RESULT="skipped (not detected)"
    elif test "${FLAG_UNINSTALL}" -eq 1; then
        uninstall_harness "claude-code" "${CC_STATUS}" "${CC_TARGET}"
        CC_RESULT="uninstalled"
    else
        install_harness "claude-code" "${CC_STATUS}" "${CC_TARGET}"
        CC_RESULT="installed"
    fi
fi

# --- codex ---
if _harness_selected "codex"; then
    if test "${CX_STATUS}" = "absent"; then
        CX_RESULT="skipped (not detected)"
    elif test "${FLAG_UNINSTALL}" -eq 1; then
        uninstall_harness "codex" "${CX_STATUS}" "${CX_TARGET}"
        CX_RESULT="uninstalled"
    else
        install_harness "codex" "${CX_STATUS}" "${CX_TARGET}"
        CX_RESULT="installed"
    fi
fi

# --- gemini ---
if _harness_selected "gemini"; then
    if test "${GE_STATUS}" = "absent"; then
        GE_RESULT="skipped (not detected)"
    elif test "${FLAG_UNINSTALL}" -eq 1; then
        uninstall_harness "gemini" "${GE_STATUS}" "${GE_TARGET}"
        GE_RESULT="uninstalled"
    else
        install_harness "gemini" "${GE_STATUS}" "${GE_TARGET}"
        GE_RESULT="installed"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n'
if test "${FLAG_UNINSTALL}" -eq 1; then
    printf 'Uninstall summary:\n'
else
    printf 'Install summary:\n'
fi
printf '  %-14s %s\n' "claude-code"  "${CC_RESULT}"
printf '  %-14s %s\n' "codex"        "${CX_RESULT}"
printf '  %-14s %s\n' "gemini"       "${GE_RESULT}"
printf '\n'

if test "${FLAG_UNINSTALL}" -eq 1; then
    printf 'Note: ~/.software-house/ (your company state) is preserved. Remove it manually if desired.\n'
else
    printf 'Next step: open your agent CLI and run /software-house init\n'
fi

exit 0