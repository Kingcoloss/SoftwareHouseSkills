# Operation: wiki-lint -- wiki-specific health checks

**Risk tier:** 1 (read-only)

**Required reading first:** `policies/privacy.md`, `policies/safety.md`, `operations/_shared.md`

## Purpose

Run wiki-specific health checks on the company or team wiki. Unlike the general `lint` operation (which checks structural integrity of agents, teams, departments), `wiki-lint` focuses on the knowledge quality of wiki pages: confidence drift, stale pages, broken wikilinks, orphan pages, empty sections, missing concepts, and source trail integrity.

Never modifies state. Never auto-fixes.

## Invocation patterns

| Command | Scope |
|---|---|
| `wiki-lint` | Full company + all teams (if detected) |
| `wiki-lint company` | Company tier only |
| `wiki-lint team <name>` | One team |
| `wiki-lint --check <category>` | Run only specific check category |

Options:

| Flag | Purpose |
|---|---|
| `--check <category>` | Run only the named check category (comma-separated for multiple) |
| `--fix-suggestions` | Include suggested `/software-house` commands to fix findings |
| `--json` | Output findings as JSONL (one line per finding) |

## Check categories

### 1. Confidence drift

Pages with `confidence < 0.5` that have not been reviewed recently.

| Condition | Severity |
|---|---|
| `confidence < 0.3` and `lifecycle: draft` | **error** (very low confidence, never reviewed) |
| `confidence < 0.5` and `lifecycle: draft` | **warning** |
| `confidence < 0.5` and `lifecycle: reviewed` or higher | **info** (was reviewed but confidence dropped) |

Fix: re-compile the page from updated sources, or manually review and update confidence.

### 2. Stale pages

Pages that have not been compiled recently.

| Condition | Severity |
|---|---|
| `lifecycle: stale` explicitly set | **warning** (page marked stale) |
| `last_compiled` > 30 days ago and `lifecycle != archived` | **warning** (may be stale) |
| `lifecycle: archived` | **info** (intentionally archived, no action needed) |

Fix: run `wiki-ingest` with updated source, or manually update `last_compiled` and promote `lifecycle`.

### 3. Broken wikilinks

`[[page-name]]` references that do not resolve to an existing wiki page.

Scan all wiki page bodies for `[[...]]` patterns. For each, check if the referenced page exists in any wiki subdirectory (people/, teams/, departments/, concepts/, decisions/, synthesis/, handoffs/).

| Condition | Severity |
|---|---|
| `[[name]]` references a page that does not exist anywhere | **error** (broken link) |
| `[[name]]` references a page in a different scope (company vs team) | **info** (cross-scope link) |

Fix: create the missing page, or correct the wikilink.

### 4. Orphan pages

Wiki pages not referenced from `index.md` or any other wiki page.

| Condition | Severity |
|---|---|
| Page exists but is not listed in `index.md` and no other page links to it | **warning** (orphan) |
| Page is in `index.md` but has zero inbound wikilinks | **info** (indexed but not linked) |

Fix: add the page to `index.md` or add a wikilink from a related page.

### 5. Empty sections

Wiki pages with placeholder content.

| Condition | Severity |
|---|---|
| Person page with "(empty)" or "(not yet written)" Notes section | **warning** |
| Concept/decision page with "(Extract key points...)" placeholder | **warning** |
| Synthesis page with "(As of...)" but no actual content | **warning** |

Fix: run `wiki-ingest` with relevant source documents, or manually fill in the content.

### 6. Missing concepts

Decision or synthesis pages that reference a concept but no concept page exists.

| Condition | Severity |
|---|---|
| Decision page body mentions a concept name that has no concept page | **info** (consider creating the concept) |
| Synthesis page references a concept not in wiki/concepts/ | **info** |

Fix: run `wiki-ingest` to create the concept page from a source document.

### 7. Source trail

Pages with `source_refs` pointing to missing `raw/` documents.

| Condition | Severity |
|---|---|
| `source_refs` contains a path that does not exist in `raw/` | **error** (broken source trail) |
| `source_refs` is empty and `lifecycle != archived` | **info** (no source provenance) |

Fix: re-archive the source document, or remove the broken reference.

### 8. Wikilink consistency

Cross-reference integrity between entity pages.

| Condition | Severity |
|---|---|
| Person page does not link to their team via `[[team-name]]` | **warning** |
| Team page does not list all members via wikilinks | **warning** |
| Decision page does not link to the person who proposed it | **info** |

Fix: manually add wikilinks to maintain graph connectivity.

## Step-by-step

### 1. Collect targets

Determine scope (company, team, or all). Build the list of wiki page files to check.

### 2. Run check categories

Run all categories by default, or only those specified by `--check`. Accumulate findings with severity levels.

### 3. Render

Default output: grouped by severity, then by category.

```
Wiki Lint Report -- <scope>  (<n> errors, <m> warnings, <k> info)

ERRORS
  [broken-wikilink] decisions/adr-003.md
    [[api-pattern]] -- page not found in any wiki directory
    -> run /software-house wiki-ingest <source> --type concept --title "api-pattern"

  [source-trail] concepts/auth-pattern.md
    source_refs: raw/2026-05-01T10-00-00Z-notes.md -- file not found
    -> source was deleted or moved; re-archive or remove the reference

WARNINGS
  [confidence-drift] concepts/caching-strategy.md (confidence: 0.3, lifecycle: draft)
    Very low confidence, never reviewed.
    -> review and update confidence, or re-compile with wiki-ingest

  [stale] synthesis/project-status.md (last_compiled: 2026-04-01, 35 days ago)
    Page may be stale.
    -> run wiki-ingest with updated source, or manually update

  [orphan] concepts/deprecated-pattern.md
    Not in index.md and no inbound wikilinks found.
    -> add to index or link from a related page

INFO
  [missing-concept] decisions/adr-005.md references "rate-limiting" but no concept page exists
  [wikilink-consistency] people/alice.md does not link to [[engineering]]
```

If `--fix-suggestions`, append a fix line to each finding.

If `--json`, output one JSONL line per finding:

```json
{"severity":"error","category":"broken-wikilink","page":"decisions/adr-003.md","detail":"[[api-pattern]] -- page not found","fix":"wiki-ingest <source> --type concept --title api-pattern"}
```

### 4. Exit posture

- Zero errors and zero warnings -> print `Wiki is clean. No findings.` and exit 0.
- Any errors -> exit 1.
- Warnings only -> exit 0.

Always end with: `Run /software-house wiki-lint --fix-suggestions for suggested commands. Wiki-lint never modifies state automatically.`

## Performance

- Read frontmatter via streaming (parse YAML head only for confidence/lifecycle/source_refs checks).
- Use `Grep` for wikilink extraction (`\[\[.+?\]\]` pattern).
- For orphan detection, build a page set and a reference set, then diff.
- For large wikis (100+ pages), consider parallelizing checks across categories.