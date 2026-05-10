---
name: 001-code-review-graph-coding-scope
type: decision
classification: internal
created_at: 2026-05-10
status: approved
---

# Decision: Use Code Review Graph to Specify Coding Scope

**Date:** 2026-05-10
**Status:** Approved

## Context
As the project grows in complexity, it is increasingly important to precisely define the scope of any code modification to prevent regressions and unintended side effects. We have access to a rich `.code-review-graph/graph.db` database that tracks architectural relationships, communities, flows, and risks.

## Decision
All team members MUST use the `code-review-graph` database to explicitly specify and verify the **coding scope** before planning and implementation. 

## Scope Identification Guidelines

1. **Identify Impacted Nodes and Edges**
   Query the `nodes` and `edges` tables to trace dependencies. When a function or class is changed, verify what upstream components call or reference it, and what downstream dependencies it relies on (`CALLS`, `IMPORTS_FROM`, `INHERITS`, `REFERENCES`).

2. **Review Critical Flows**
   Check the `flows` and `flow_snapshots` tables to determine if the modified node participates in a critical execution path. High criticality flows require elevated testing and architectural review.

3. **Domain & Community Boundaries**
   Use the `communities` and `community_summaries` tables to understand the bounding context of the code. If a change bridges multiple independent communities, it should be flagged as a cross-cutting concern.

4. **Risk Assessment**
   Reference the `risk_index` table to evaluate the risk score of the impacted nodes. Nodes with high risk scores or insufficient test coverage must have their tests fortified as part of the scope.

## Action Items
- **Planning:** All technical plans and handoff briefs must include a "Coding Scope" section backed by queries from the `code-review-graph` database.
- **Review:** Code reviewers (`yuki`) should leverage the graph to verify that all edge effects and callers of the modified code have been appropriately handled and tested.
