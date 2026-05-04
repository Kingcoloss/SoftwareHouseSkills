#!/bin/sh
# 001-initial-schema.sh
# No-op placeholder documenting the migration contract.
# This is the baseline migration for version 0.4.0.
# No schema changes are needed -- the initial schema is already current.

# Arguments (provided by install.sh):
#   $1 = old version (may be empty on fresh install)
#   $2 = new version

OLD_VER="${1:-none}"
NEW_VER="${2:-unknown}"

printf '  [001-initial-schema] Migration placeholder (no-op). old=%s new=%s\n' "${OLD_VER}" "${NEW_VER}"

# Contract documentation:
# - Exit 0 on success
# - Exit non-zero on failure (install.sh will warn but continue)
# - Must be idempotent (safe to run multiple times)
# - Must not make network calls
# - May modify ~/.software-house/ state files
# - Must not modify skill install path files

exit 0