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
    # $1 = prompt text; returns 0 if user says y/Y, 1 otherwise
    printf '%s [y/N] ' "$1"
    read -r _answer
    case "${_answer}" in
        y|Y) return 0 ;;
        *)   return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

FLAG_FORCE=0
FLAG_SYMLINK=0
FLAG_UNINSTALL=0
FLAG_LIST=0
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

# Replace "present:agents" / "present:codex" with "present" for display
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
# Source check (only needed for install/symlink)
# ---------------------------------------------------------------------------

check_source() {
    if ! test -f "${SOURCE}/SKILL.md"; then
        die "Source skill not found: ${SOURCE}/SKILL.md is missing. Is this the correct repository?"
    fi
}

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
        if test "${FLAG_FORCE}" -eq 0; then
            if ! confirm "Overwrite ${_htarget}?"; then
                printf '  %s: skipped (user chose not to overwrite)\n' "${_hid}"
                return 0
            fi
        fi
        # Remove existing
        if test -L "${_htarget}"; then
            rm "${_htarget}"
        else
            rm -rf "${_htarget}"
        fi
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
        cp -R "${SOURCE}" "${_htarget}"
        if ! test -f "${_htarget}/SKILL.md"; then
            die "Copy succeeded but ${_htarget}/SKILL.md is missing for ${_hid}."
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
