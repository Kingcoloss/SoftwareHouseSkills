# Installation — software-house skill

The skill is portable across Claude Code, OpenAI Codex CLI, and Gemini CLI. `install.sh` auto-detects which CLIs are present and installs the same source tree into each.

## Prerequisites

- At least one supported agent CLI installed:
  - **Claude Code** (looks for `~/.claude/`)
  - **OpenAI Codex CLI** (looks for `~/.agents/` or `~/.codex/`)
  - **Gemini CLI** (looks for `~/.gemini/`)
- A POSIX shell (macOS / Linux). Windows users use WSL.

## Method 1: Using install.sh (recommended)

Clone or download this repo, then run from the repo root:

```sh
./install.sh
```

The script detects which agent CLIs are installed and copies `skills/software-house/` to each:

| Detected harness | Install destination                  |
|------------------|--------------------------------------|
| Claude Code      | `~/.claude/skills/software-house/`   |
| OpenAI Codex CLI | `~/.agents/skills/software-house/`   |
| Gemini CLI       | `~/.gemini/extensions/software-house/` |

| Flag                       | Effect                                                                       |
|----------------------------|------------------------------------------------------------------------------|
| _(none)_                   | Copy-install to all detected harnesses; prompt before overwriting an existing install |
| `--force`                  | Skip overwrite prompts                                                       |
| `--symlink`                | Create symlinks (target -> source) instead of copying — useful for active development |
| `--uninstall`              | Remove the installed skill from each detected harness                        |
| `--harness <id>[,<id>...]` | Restrict to a subset; valid ids: `claude-code`, `codex`, `gemini`            |
| `--list-harnesses`         | Print the harness detection table and exit (no changes)                      |
| `--help`, `-h`             | Print usage and exit                                                         |

Examples:

```sh
./install.sh --list-harnesses             # see what would be installed
./install.sh --harness claude-code        # only install for Claude Code
./install.sh --harness codex,gemini       # install for Codex and Gemini
./install.sh --symlink --force            # dev mode: symlink everywhere, no prompts
```

Re-running `./install.sh` updates an existing install (idempotent).

### Codex post-install registration (manual, one-time)

Codex requires a `[[skills]]` entry in `~/.codex/config.toml` to load installed skills, plus a Codex restart. The installer prints the exact snippet after a successful Codex install:

```toml
[[skills]]
path = "~/.agents/skills/software-house"
enabled = true
```

The installer never edits your config — that step is yours.

### Gemini post-install note

Gemini CLI may need a restart to pick up newly installed extensions. The installer prints a reminder when it installs the Gemini extension.

## Method 2: Manual install

Pick the section for the harness(es) you use.

### Claude Code

```sh
mkdir -p ~/.claude/skills
cp -R skills/software-house ~/.claude/skills/
```

### OpenAI Codex CLI

```sh
mkdir -p ~/.agents/skills
cp -R skills/software-house ~/.agents/skills/
```

Then add to `~/.codex/config.toml`:

```toml
[[skills]]
path = "~/.agents/skills/software-house"
enabled = true
```

Restart Codex.

### Gemini CLI

```sh
mkdir -p ~/.gemini/extensions
cp -R skills/software-house ~/.gemini/extensions/software-house
```

Restart Gemini CLI if needed.

### Symlink (development mode for any harness)

```sh
ln -s "$(pwd)/skills/software-house" ~/.claude/skills/software-house
ln -s "$(pwd)/skills/software-house" ~/.agents/skills/software-house
ln -s "$(pwd)/skills/software-house" ~/.gemini/extensions/software-house
```

## Verify the install

Open your agent CLI and run:

```
/software-house
```

No arguments should print the help summary. Then run:

```
/software-house init
```

This bootstraps `~/.software-house/` and prompts for confirmation before writing anything. The same canonical state directory is read by all three harnesses.

## What gets installed where

| Source path                  | Destination path                              | Notes                                            |
|------------------------------|-----------------------------------------------|--------------------------------------------------|
| `skills/software-house/`     | `~/.claude/skills/software-house/`            | Installed by `install.sh` if Claude Code present |
| `skills/software-house/`     | `~/.agents/skills/software-house/`            | Installed by `install.sh` if Codex present       |
| `skills/software-house/`     | `~/.gemini/extensions/software-house/`        | Installed by `install.sh` if Gemini present      |
| (created by `init`)          | `~/.software-house/`                          | Canonical company state — created by `/software-house init`, never by install |
| (created per project as you work) | `<project>/.software-house/team/` and `<project>/.software-house/agents/` | Canonical team state and agent definitions    |

## Privacy note

`install.sh` performs only local file operations: `mkdir`, `cp`, `ln`, `rm`, `test`, `printf`, `read`. It does not touch the network, does not run `git push`, and does not contact any remote service. It does not edit `~/.codex/config.toml` or any other user config — it only prints what you need to add. You can read the script before running it.

## Updating

```sh
git pull
./install.sh
```

Updates ALL detected harnesses. Use `--harness <id>` to limit. To overwrite without prompts:

```sh
./install.sh --force
```

The skill files at the per-harness install paths are refreshed. Your canonical state at `~/.software-house/` is never touched by install or update.

## Uninstalling

```sh
./install.sh --uninstall
```

Prompts per harness and removes the skill from each. Your canonical state at `~/.software-house/` is preserved.

To also remove company data (destructive — back up first if you want to keep history):

```sh
rm -rf ~/.software-house/
```

To remove only one harness:

```sh
./install.sh --uninstall --harness gemini
```

## Troubleshooting

| Symptom                                              | Fix                                                                                       |
|------------------------------------------------------|-------------------------------------------------------------------------------------------|
| "Skill not found" (Claude Code)                      | Run `ls ~/.claude/skills/software-house/SKILL.md` and confirm the file exists.            |
| "Skill not found" (Codex)                            | Verify `~/.codex/config.toml` has the `[[skills]]` entry; restart Codex.                  |
| "Extension not loaded" (Gemini)                      | Verify `~/.gemini/extensions/software-house/gemini-extension.json` exists; restart Gemini CLI. |
| "Permission denied" running install.sh               | Run `chmod +x install.sh` first.                                                          |
| `/software-house` command not recognized             | Restart your agent CLI session.                                                           |
| Installer says "no agent CLI detected"               | Install at least one of Claude Code / Codex CLI / Gemini CLI; re-run `./install.sh`.      |
| `init` says state already exists                     | The skill is already initialized at `~/.software-house/`. Run `/software-house list` instead. |
