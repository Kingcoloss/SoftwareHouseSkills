#!/usr/bin/env bash
# obsidian-setup.sh -- create an Obsidian vault linked to the software-house wiki
# Creates symlinks from the vault to wiki directories for graph view and backlinks.
# Spec: Phase D6 of the software-house plan.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SH_HOME="${SH_HOME:-$HOME/.software-house}"
VAULT_NAME="software-house-obsidian"
VAULT_DIR="${1:-$HOME/$VAULT_NAME}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { printf '[obsidian-setup] %s\n' "$*"; }
warn()  { printf '[obsidian-setup] WARNING: %s\n' "$*" >&2; }
error() { printf '[obsidian-setup] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# Check company state exists
if [[ ! -d "$SH_HOME/company" ]]; then
  error "Company state not found at $SH_HOME. Run /software-house init first."
fi

# Check if Obsidian is installed
detect_obsidian() {
  # macOS
  if [[ -d "/Applications/Obsidian.app" ]]; then
    echo "macOS"
    return 0
  fi
  # Linux AppImage, snap, flatpak
  if command -v obsidian &>/dev/null; then
    echo "linux"
    return 0
  fi
  if [[ -f "$HOME/.local/bin/Obsidian" ]]; then
    echo "linux"
    return 0
  fi
  # Windows (WSL)
  if [[ -d "/mnt/c/Users" ]]; then
    local win_obsidian
    win_obsidian="$(find /mnt/c/Users/*/AppData/Local/Obsidian -maxdepth 0 2>/dev/null | head -1)"
    if [[ -n "$win_obsidian" ]]; then
      echo "windows-wsl"
      return 0
    fi
  fi
  echo "not-found"
  return 0
}

obsidian_platform="$(detect_obsidian)"

if [[ "$obsidian_platform" == "not-found" ]]; then
  warn "Obsidian not detected on this system."
  warn "The vault will be created anyway -- install Obsidian later and open the vault."
  warn "Download from: https://obsidian.md"
else
  log "Obsidian detected ($obsidian_platform)."
fi

# ---------------------------------------------------------------------------
# Create vault
# ---------------------------------------------------------------------------

if [[ -d "$VAULT_DIR" ]]; then
  log "Vault directory already exists: $VAULT_DIR"
else
  mkdir -p "$VAULT_DIR"
  log "Created vault directory: $VAULT_DIR"
fi

# Create .obsidian config
mkdir -p "$VAULT_DIR/.obsidian"

# Basic Obsidian config
cat > "$VAULT_DIR/.obsidian/app.json" << 'APPEOF'
{
  "legacyEditor": false,
  "livePreview": true,
  "readableLineLength": true,
  "showLineNumber": false,
  "spellcheck": false,
  "strictLineBreaks": true,
  "defaultViewMode": "preview"
}
APPEOF

# Enable wikilinks (not markdown links)
cat > "$VAULT_DIR/.obsidian/core-plugins.json" << 'COREEOF'
{
  "file-explorer": true,
  "global-search": true,
  "graph-view": true,
  "backlink": true,
  "outgoing-link": true,
  "tag-pane": true,
  "page-preview": true,
  "templates": true,
  "markdown-importer": false,
  "word-count": true,
  "editor-status": true,
  "outline": true
}
COREEOF

log "Created Obsidian config."

# ---------------------------------------------------------------------------
# Create symlinks to wiki directories
# ---------------------------------------------------------------------------

COMPANY_HOME="$SH_HOME/company"

# Define wiki directories to link
declare -A link_map
link_map=(
  ["people"]="$COMPANY_HOME/wiki/people"
  ["teams"]="$COMPANY_HOME/wiki/teams"
  ["departments"]="$COMPANY_HOME/wiki/departments"
  ["concepts"]="$COMPANY_HOME/wiki/concepts"
  ["decisions"]="$COMPANY_HOME/wiki/decisions"
  ["synthesis"]="$COMPANY_HOME/wiki/synthesis"
  ["handoffs"]="$COMPANY_HOME/wiki/handoffs"
  ["raw"]="$COMPANY_HOME/raw"
)

# Link individual files
link_file_map=(
  ["index.md"]="$COMPANY_HOME/index.md"
  ["log.md"]="$COMPANY_HOME/wiki/log.md"
)

created_count=0
skipped_count=0

# Ensure wiki subdirectories exist
for target in "${link_map[@]}"; do
  if [[ ! -d "$target" ]]; then
    mkdir -p "$target"
    log "Created wiki directory: $target"
  fi
done

# Create symlinks for directories
for name in "${!link_map[@]}"; do
  local_target="${link_map[$name]}"
  local_link="$VAULT_DIR/$name"

  if [[ -L "$local_link" ]]; then
    # Symlink already exists -- check if it points to the right target
    local current_target
    current_target="$(readlink "$local_link" 2>/dev/null || echo "")"
    if [[ "$current_target" == "$local_target" ]]; then
      skipped_count=$(( skipped_count + 1 ))
      continue
    else
      warn "Symlink $local_link points to $current_target, expected $local_target. Skipping."
      skipped_count=$(( skipped_count + 1 ))
      continue
    fi
  elif [[ -d "$local_link" ]]; then
    warn "Directory $local_link already exists (not a symlink). Skipping."
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  ln -s "$local_target" "$local_link"
  created_count=$(( created_count + 1 ))
  log "Linked: $name -> $local_target"
done

# Create symlinks for files
for name in "${!link_file_map[@]}"; do
  local_target="${link_file_map[$name]}"
  local_link="$VAULT_DIR/$name"

  if [[ ! -f "$local_target" ]]; then
    warn "Source file $local_target does not exist. Skipping $name."
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  if [[ -L "$local_link" ]]; then
    skipped_count=$(( skipped_count + 1 ))
    continue
  elif [[ -f "$local_link" ]]; then
    warn "File $local_link already exists. Skipping."
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  ln -s "$local_target" "$local_link"
  created_count=$(( created_count + 1 ))
  log "Linked: $name -> $local_target"
done

# ---------------------------------------------------------------------------
# Link per-project team wikis
# ---------------------------------------------------------------------------

PROJECTS_INDEX="$SH_HOME/projects-index.json"

if [[ -f "$PROJECTS_INDEX" ]] && command -v jq &>/dev/null; then
  # Read project paths
  local project_paths
  project_paths="$(jq -r '.projects | keys[]' "$PROJECTS_INDEX" 2>/dev/null || true)"

  for proj_path in $project_paths; do
    local team_wiki_dir="$proj_path/.software-house/team/wiki"
    if [[ -d "$team_wiki_dir" ]]; then
      # Extract team name
      local team_name
      team_name="$(jq -r ".projects[\"$proj_path\"].team" "$PROJECTS_INDEX" 2>/dev/null || echo "")"
      if [[ -z "$team_name" ]]; then
        team_name="$(basename "$proj_path")"
      fi
      local team_link_name="team-${team_name}"
      local team_link="$VAULT_DIR/$team_link_name"

      if [[ ! -L "$team_link" ]] && [[ ! -d "$team_link" ]]; then
        ln -s "$team_wiki_dir" "$team_link"
        log "Linked team: $team_link_name -> $team_wiki_dir"
        created_count=$(( created_count + 1 ))
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# Community plugin recommendations
# ---------------------------------------------------------------------------

PLUGINS_DIR="$VAULT_DIR/.obsidian/plugins"
mkdir -p "$PLUGINS_DIR"

# Create a recommendations file (not auto-installed -- user must install manually)
cat > "$VAULT_DIR/.obsidian/RECOMMENDED-PLUGINS.md" << 'PLUGEOF'
# Recommended Obsidian Plugins for Software House Wiki

Install these community plugins for enhanced wiki functionality:

## 1. Graph Explorer Base View
- Visual graph navigation of wiki connections
- Shows frontier nodes, confidence coloring
- Install: Settings -> Community Plugins -> Browse -> "Graph Explorer Base View"

## 2. Dataview
- Dashboard queries for agent status, handoff tracking
- SQL-like queries over markdown frontmatter
- Install: Settings -> Community Plugins -> Browse -> "Dataview"

## 3. LLM Wiki (local-first)
- Local-first wiki operations (ingest, query, lint) without egress
- Privacy-first, works with Ollama
- Install: Settings -> Community Plugins -> Browse -> "LLM Wiki"
- Configure: Set Ollama as default provider (policy C1: local-first)

## 4. Templater (optional)
- Advanced templates for consistent page structure
- Useful for creating new concept/decision pages
- Install: Settings -> Community Plugins -> Browse -> "Templater"
PLUGEOF

log "Created plugin recommendations at .obsidian/RECOMMENDED-PLUGINS.md"

# ---------------------------------------------------------------------------
# Create vault homepage
# ---------------------------------------------------------------------------

if [[ ! -f "$VAULT_DIR/Welcome.md" ]]; then
  cat > "$VAULT_DIR/Welcome.md" << 'WELCOMEOF'
# Software House Wiki

This Obsidian vault is linked to your Software House company wiki at `~/.software-house/`.

## Directory Guide

| Directory | Content |
|---|---|
| `people/` | Agent wiki pages |
| `teams/` | Team wiki pages |
| `departments/` | Department wiki pages |
| `concepts/` | Architectural concepts and patterns |
| `decisions/` | Architecture Decision Records (ADRs) |
| `synthesis/` | Cross-cutting synthesis pages |
| `handoffs/` | Inter-agent handoff briefs |
| `raw/` | Immutable source documents |

## Quick Start

1. Use the **Graph View** to explore connections between pages
2. Use **Backlinks** to see what references each page
3. Use **Dataview** queries for dashboards (e.g., agents by status)
4. Run `/software-house wiki-ingest <source>` to add new wiki pages
5. Run `/software-house wiki-lint` to check wiki health

## Wiki Conventions

- Pages use `[[wikilinks]]` for cross-references
- Every page has `confidence` and `lifecycle` frontmatter
- Sources are archived in `raw/` before compilation
- Confidence < 0.5 means the page needs review

See `.obsidian/RECOMMENDED-PLUGINS.md` for plugin suggestions.
WELCOMEOF
  log "Created vault homepage: Welcome.md"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

printf '\n'
printf 'Obsidian vault created at: %s\n' "$VAULT_DIR"
printf '  Symlinks created: %s\n' "$created_count"
printf '  Symlinks skipped: %s\n' "$skipped_count"
printf '  Plugin recommendations: .obsidian/RECOMMENDED-PLUGINS.md\n'
printf '\n'
printf 'To open:\n'

case "$obsidian_platform" in
  macOS)
    printf '  1. Open Obsidian\n'
    printf '  2. Open folder as vault: %s\n' "$VAULT_DIR"
    ;;
  linux)
    printf '  1. Open Obsidian\n'
    printf '  2. Open folder as vault: %s\n' "$VAULT_DIR"
    ;;
  windows-wsl)
    printf '  1. Open Obsidian on Windows\n'
    printf '  2. Open folder as vault (use Windows path)\n'
    ;;
  not-found)
    printf '  1. Install Obsidian from https://obsidian.md\n'
    printf '  2. Open folder as vault: %s\n' "$VAULT_DIR"
    ;;
esac

printf '\n  Recommended: install community plugins per .obsidian/RECOMMENDED-PLUGINS.md\n'
printf '  Graph view:  click "Open Graph View" to see wiki connections\n'