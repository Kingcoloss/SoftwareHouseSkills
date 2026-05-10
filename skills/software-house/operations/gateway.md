# Gateway Operation

**Pattern:** `gateway <agent_name> --message "<text>" [--context <path>]`
**Tier:** 2 (Additive)
**Harness:** Portable (Bash/Gemini/Codex)

## Overview
Directly messages an agent from the CEO, bypassing standard team triggers. Generates an optimized brief and drops it in the agent's inbox.

## Workflow
1. Verify the `agent_name` exists.
2. Formulate the brief payload.
3. Optimize the token length of the brief using the `optimize_tokens` hook.
4. Save to the agent's inbox (`wiki/handoffs/inbox/`).
5. Log to `audit.log`.