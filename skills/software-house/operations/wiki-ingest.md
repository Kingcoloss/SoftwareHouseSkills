# Operation: wiki-ingest -- ingest a source document into the wiki

**Risk tier:** 2 (additive -- creates new wiki pages and copies source)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Ingest a source document (markdown, text, code file) into the company or team wiki. The original is archived immutably in `$RAW_DIR`, then an LLM-compiled wiki page is created in the appropriate wiki subdirectory (`concepts/`, `decisions/`, or `synthesis/`). The compiled page includes confidence, lifecycle, and source_refs frontmatter per `_shared.md section 19`.

This operation is the entry point for the "compile, don't re-derive" pattern: raw sources are preserved, and derived wiki pages reference their sources.

## Invocation patterns

| Command | Scope |
|---|---|
| `wiki-ingest <source-path>` | Company tier (default) |
| `wiki-ingest <source-path> --team <name>` | Team tier |
| `wiki-ingest <source-path> --dept <name>` | Department tier |

Options:

| Flag | Purpose |
|---|---|
| `--type concept\|decision\|synthesis` | Force page type (auto-detected if omitted) |
| `--title "<text>"` | Override page title (default: derived from source filename) |
| `--tags <tag1,tag2,...>` | Comma-separated tags for frontmatter |
| `--confidence <0.0-1.0>` | Initial confidence (default: 0.7 for compiled pages) |
| `--no-compile` | Archive source only, skip LLM compilation step |

## Step-by-step

### 1. Validate input

- `<source-path>` must exist on the local filesystem. Reject remote URLs or paths outside the user's machine per C1.
- If `--team` is specified, the team must exist in `$WIKI_TEAMS` or be detected from `$PROJECTS_INDEX`.
- If `--dept` is specified, the department must exist in `$WIKI_DEPTS`.
- If `--type` is specified, it must be one of: `concept`, `decision`, `synthesis`.

### 2. Archive the source

Copy the source file to `$RAW_DIR` (or `$TEAM_RAW_DIR` for team scope):

```
<raw-dir>/<utc-timestamp>-<original-filename>
```

Example: `raw/2026-05-06T10-30-00Z-api-design-notes.md`

The timestamp prefix ensures immutability and avoids name collisions. The original file is never modified or moved.

If `$RAW_DIR` does not exist, create it via `mkdir -p`.

### 3. Auto-detect page type (if --type not specified)

Read the source file content and infer the wiki page type:

| Heuristic | Type |
|---|---|
| Contains "ADR", "decision", "chosen", "alternatives" | `decision` |
| Contains "concept", "pattern", "principle", "definition" | `concept` |
| Contains "status", "summary", "overview", "dashboard" | `synthesis` |
| Default | `concept` |

The heuristic is simple keyword matching. When ambiguous, prefer `concept`.

### 4. Compile the wiki page

Generate a structured markdown page from the source. The compiled page includes:

#### Frontmatter

```yaml
---
type: <concept|decision|synthesis>
title: <page-title>
confidence: 0.7
lifecycle: draft
last_compiled: <utc-date>
source_refs:
  - raw/<timestamp>-<filename>
tags: []
created_at: <utc-date>
classification: internal
---
```

- `confidence`: Set to `0.7` (draft, compiled from single source). Override with `--confidence`.
- `lifecycle`: Always `draft` for newly ingested pages. Must be promoted to `reviewed` or `verified` manually.
- `source_refs`: Array pointing to the archived source in `raw/`.
- `tags`: From `--tags` flag, or empty.

#### Body structure by type

**Concept page:**

```markdown
# <Title>

## Summary
<one-paragraph summary extracted from source>

## Key Points
- <point 1>
- <point 2>

## Related
- [[<concept-name>]]
- [[<decision-name>]]
```

**Decision page (ADR format):**

```markdown
# <Title>

## Status
Draft

## Context
<what motivated this decision>

## Decision
<what was decided>

## Consequences
<positive and negative outcomes>

## Related
- [[<concept-name>]]
```

**Synthesis page:**

```markdown
# <Title>

## Overview
<compiled summary>

## Current State
<as of <date>>

## Key Insights
- <insight 1>

## Related
- [[<concept-or-decision>]]
```

### 5. Write the wiki page

Determine the target directory based on type and scope:

| Scope | Concept | Decision | Synthesis |
|---|---|---|---|
| Company | `$WIKI_CONCEPTS/<slug>.md` | `$WIKI_DECISIONS/<slug>.md` | `$WIKI_SYNTHESIS/<slug>.md` |
| Team | `$TEAM_WIKI_DECISIONS/<slug>.md` | `$TEAM_WIKI_DECISIONS/<slug>.md` | `$TEAM_WIKI_SYNTHESIS/<slug>.md` |

The `<slug>` is derived from `--title` or the source filename: lowercase, spaces to hyphens, alphanumeric + hyphens only.

If the page already exists, append the new source to `source_refs` and update `last_compiled`. Do not overwrite the entire page -- merge new information.

### 6. Update index.md

Append the new page to the appropriate section in `$COMPANY_INDEX` or `$TEAM_INDEX`:

```markdown
- [<title>](<relative-path>) -- <one-line summary>
```

### 7. Append to wiki log

Add an entry to `$WIKI_LOG` (or `$TEAM_WIKI_LOG`):

```markdown
- <utc-timestamp> | wiki-ingest | raw/<archived-file> -> <type>/<slug>.md
```

### 8. Audit log

```json
{"ts":"<utc>","actor":"user","op":"wiki-ingest","scope":"<company|team:<name>>","args":{"source":"<source-path>","type":"<concept|decision|synthesis>","title":"<title>"},"diff":{"created":["raw/<file>","wiki/<type>/<slug>.md"],"updated":["wiki/log.md","index.md"]},"confirmation":{"tier":2},"egress_consent":{"required":false},"result":"ok"}
```

### 9. Report to the user

```
Ingested: <source-path>
  Archived: raw/<timestamp>-<filename>
  Compiled: wiki/<type>/<slug>.md (confidence: 0.7, lifecycle: draft)
  Index updated: <type> section

  Next: /software-house wiki-lint          check wiki health
        /software-house show <slug>        view the compiled page
```

## Failure modes

- Source file not found -> error, no archive, no wiki page.
- `$RAW_DIR` creation fails -> error, suggest permissions check.
- Target wiki directory missing -> create it via `mkdir -p`.
- Page already exists and merge fails -> warn, leave existing page intact, still archive source.
- `--no-compile` specified -> skip steps 3-5, only archive the source and log it.