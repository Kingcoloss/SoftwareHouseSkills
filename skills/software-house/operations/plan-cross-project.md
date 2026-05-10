# Plan Cross-Project Operation

**Pattern:** `plan cross-project "<goal>" [--team <team>]`
**Tier:** 2 (Additive)
**Harness:** Portable (Bash/Gemini/Codex)

## Overview
Gathers context across multiple microservice repositories linked via `PROJECTS_INDEX` to allow architects or tech-leads to synthesize a unified architecture plan.

## Workflow
1. Parse the goal and determine the target team/project.
2. Find the lead agent (`system-architect` or `tech-lead`) for the team.
3. Read `PROJECTS_INDEX` and aggregate architecture decisions (`wiki/decisions/`) from all linked projects.
4. Formulate the brief payload.
5. Optimize the token length using the `optimize_tokens` hook.
6. Drop the brief in the lead agent's inbox.
7. Log to `audit.log`.