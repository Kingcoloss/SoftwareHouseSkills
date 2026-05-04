# Schema Migrations

Migrations are shell scripts that run automatically when `install.sh` detects a
version change (upgrade or downgrade). They transform existing installed state
to match the new schema.

## How it works

1. `install.sh` compares the installed VERSION with the source VERSION.
2. On version change, it runs all `NNN-<name>.sh` scripts in this directory in
   sort order.
3. Each script receives two arguments: `$1` = old version, `$2` = new version.
4. A migration script exits 0 on success, non-zero on failure (install.sh
   prints a warning but continues).

## Migration contract

- Scripts MUST be executable POSIX sh (`#!/bin/sh`).
- Scripts MUST be idempotent -- running them twice must not break state.
- Scripts MUST NOT modify files under the skill install path (those are
  managed by the copy/symlink logic).
- Scripts MAY modify files under `~/.software-house/` (canonical state) and
   per-project `.software-house/` directories.
- Scripts SHOULD use the `_shared.md` atomic write pattern for existing files:
  write to `<path>.tmp`, verify, then `mv <path>.tmp <path>`.
- Scripts MUST NOT make network calls (same constraint as all skill operations).

## Naming convention

```
NNN-<descriptive-name>.sh
```

- `NNN` is a zero-padded three-digit sequence number (001, 002, ...).
- `<descriptive-name>` uses lowercase with hyphens.
- Scripts run in lexicographic sort order.

## Example

```sh
#!/bin/sh
# 002-add-contract-fields.sh
# Adds contract_type, contract_start, contract_end to freelance agent frontmatter
OLD_VER="$1"
NEW_VER="$2"

# Find all freelance agents and add missing fields
for agent_file in "${HOME}/.software-house/agents/"*.md; do
    test -f "${agent_file}" || continue
    # ... transformation logic ...
done

exit 0
```

## Adding a new migration

1. Determine the next sequence number (increment from the highest existing).
2. Create `NNN-<name>.sh` with `#!/bin/sh` shebang and the migration logic.
3. Test idempotency: run it twice against sample state and verify correctness.
4. Update VERSION and CHANGELOG.md to reflect the new version.