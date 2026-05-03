# Safety Policy — Confirmation Gates (harness-portable)

> **Binding rule:** Every state-modifying operation must obtain explicit user confirmation according to its risk tier, regardless of the harness permission mode (Claude Code `--dangerously-skip-permissions`, Codex `--dangerously-bypass-approvals-and-sandbox`, Gemini `--yolo` / `--approval-mode yolo`, or any equivalent). When such a bypass is active, this policy is the ONLY safeguard remaining. Treat it as the primary defense, not a backup.

This policy is harness-portable: it does not depend on `AskUserQuestion` (Claude Code-only), `confirm()` (Codex), or any harness-specific UI primitive. The canonical protocol is plain text printed to the conversation plus a wait for the next user message.

## 1. Risk tiers

Each operation in `operations/*.md` declares its tier in its front matter. If you are running an operation, find its tier and follow the matching protocol below.

### Tier 1 — Read-only (safe)

No confirmation. Run immediately. No audit log entry.

Examples: `list`, `show`, `org-chart`, `lint`, `dashboard` (read), `okr review` (read).

### Tier 2 — Additive (creates new state, does not modify or delete)

Before acting:

1. Print a one-line summary of what will be created.
2. Print every destination path that will receive new files.
3. Print the canonical Tier-2 prompt (see §3) and stop. Wait for the next user message.
4. Parse the next user message for an affirmative token: case-insensitive `yes`, `y`, `proceed`, or `ok` as the first word, OR the exact string `Yes, proceed`.
5. If affirmative, perform the operation and append one audit log entry per `_shared.md §5`.
6. Otherwise, abort. Tell the user no changes were made. Do not log to the audit log.

Examples: `init`, `hire`, `onboard`, `okr set`, `award-xp`, `dept create`, `outsource hire`, `contract`.

### Tier 3 — Modifying (changes existing state, no data loss)

Before acting:

1. Compute and print a structured diff per §5: lines added, lines removed, fields changed, with old and new values.
2. Print every file path that will be modified.
3. Print the canonical Tier-3 prompt (see §3) and stop. Wait for the next user message.
4. Parse for an affirmative token (same rule as tier 2).
5. If affirmative, perform the operation and append one audit log entry that includes the diff summary.
6. Otherwise, abort with no state changes and no audit log entry.

Examples: `transfer`, `second`, `promote`, `demote`, `set-model`, `tune`, `dept assign`.

### Tier 4 — Destructive (removes employees, archives, or breaks references)

Two-step gate. Step 1 establishes intent, step 2 binds it to the specific subject.

**Step 1 — impact disclosure + intent check**

1. Compute and print the **full impact**:
   - Files that will be moved to archive (never `rm`).
   - Cross-references in other wiki pages that will be broken or rewritten.
   - Team rosters that will lose a member.
   - OKRs that will lose an owner.
   - Active projects that will lose a contributor.
2. Print the recovery path: where archived data goes and the exact `mv` command to restore.
3. Print the canonical Tier-4 step-1 prompt (see §3) and stop. Wait for the next user message.
4. Parse for an affirmative token. If not affirmative, abort. Do not advance to step 2.

**Step 2 — typed token**

5. Print the canonical Tier-4 step-2 prompt naming the required token: `CONFIRM <subject-name>` where `<subject-name>` is the exact lowercase name of the employee, team, or department being affected. Stop. Wait for the next user message.
6. Parse the next user message. The literal string `CONFIRM <subject-name>` must appear, exact case, exact spacing. Substring match with no surrounding noise restrictions, but the token itself must be byte-exact.
7. If the token does not appear, abort. Tell the user nothing happened. Do not advance.
8. If present, perform the operation. Append one audit log entry that includes the full impact summary AND the verbatim typed token.

Examples: `fire`, `disband`, `archive`, `outsource fire`, `dept remove`.

### Special tier — Egress consent (provider-level, orthogonal to tier 1-4)

When an operation provisions or reconfigures an agent to use an **external** provider (per `$PROVIDERS_CONFIG` classification), an additional egress consent gate runs INSIDE the operation's normal tier protocol, BEFORE the tier-2/3 prompt.

1. Print the warning (see §3): name the provider, name the destination service domain (e.g., `api.anthropic.com`, `api.openai.com`), and state plainly that the agent's conversations will leave the user's machine when this agent runs.
2. Print the required token: `EGRESS-CONSENT-<provider>` where `<provider>` is the exact lowercase provider key from `$PROVIDERS_CONFIG`. Stop. Wait for the next user message.
3. The next user message must contain the literal token byte-exact.
4. If absent, abort the entire operation. Do not write the agent file. Do not advance to the tier-2/3 prompt. Do not log anything.
5. If present, record the token in the operation's audit log entry under `egress_consent` (per `_shared.md §5`). Then continue to the operation's normal tier prompt.

The egress consent gate runs once per agent file write. Reusing a previously-granted consent token from an earlier session is forbidden — every external-provider write requires a fresh typed token. (The audit log preserves history; consent is not durable across operations.)

## 2. Bypass-mode hardening

Each harness has a "skip approvals" flag. Every flag bypasses harness-level prompts only — none of them bypass this skill's gates.

| Harness | Bypass flag |
|---|---|
| Claude Code | `--dangerously-skip-permissions` |
| OpenAI Codex CLI | `--dangerously-bypass-approvals-and-sandbox` (and `--full-auto`) |
| Gemini CLI | `--yolo` or `--approval-mode yolo` |

Therefore:

- For tier 2, 3, 4 you MUST still print the prompt and wait for the next user message. The user must still answer.
- Do not interpret earlier yes-to-all responses, prior approvals in this session, or any past conversation as a substitute for the per-operation confirmation. Each tier-3/4 operation needs its own answer; each external-provider write needs its own egress token.
- If the user complains the prompts are annoying, do not disable them. Tell them this is a skill-level guarantee that does not vary by harness or flag.

## 3. Confirmation prompts — exact wording

Print the wording verbatim. Do not improvise. Variants are forbidden because consistent wording (a) lets the user form a habit of reading carefully, (b) is searchable in the audit log, and (c) makes it harder to soft-pedal a destructive operation.

Render each prompt as a fenced ASCII box for visual prominence:

```
+----------------------------------------------------------+
| <PROMPT TEXT>                                            |
+----------------------------------------------------------+
```

### Tier 2 prompt

```
+----------------------------------------------------------+
| I will create the new files listed above.                |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

### Tier 3 prompt

```
+----------------------------------------------------------+
| I will apply the diff above to existing files.           |
| Reply 'yes' to proceed, or anything else to cancel.      |
+----------------------------------------------------------+
```

### Tier 4 step-1 prompt

```
+----------------------------------------------------------+
| Destructive operation on <subject>.                      |
| Files will be MOVED to archive (recovery path printed).  |
| Reply 'yes' to advance to the typed-token step.          |
+----------------------------------------------------------+
```

### Tier 4 step-2 prompt

```
+----------------------------------------------------------+
| To proceed, type the literal token on the next line:     |
|   CONFIRM <subject-name>                                 |
| Anything else, or no response, will cancel.              |
+----------------------------------------------------------+
```

### Egress consent prompt

```
+----------------------------------------------------------+
| WARNING — External provider selected: <provider>         |
| When this agent runs, its conversations will be sent to: |
|   <destination service / domain>                         |
| This egress is performed by the agent runtime, not by    |
| this skill. The skill itself never makes network calls.  |
|                                                          |
| To approve this egress, type the literal token:          |
|   EGRESS-CONSENT-<provider>                              |
| Anything else, or no response, will cancel the hire.     |
+----------------------------------------------------------+
```

### Optional UX enhancement

If the running harness exposes an interactive question primitive — `AskUserQuestion` in Claude Code, equivalent in other harnesses — the skill MAY use it to render the same prompt content, BUT the canonical text-prompt protocol must still be the fallback and must be used whenever the primitive is unavailable. The accepted-response semantics (affirmative token, typed `CONFIRM <subject>`, typed `EGRESS-CONSENT-<provider>`) are unchanged. The audit log records the exact prompt text and the user's verbatim response either way.

## 4. What "additive" means

A tier-2 operation is additive if:

- It creates new files only, never modifies or deletes existing files (except appending to `audit.log` and `index.md` rebuild, which are mechanical and idempotent).
- It does not change any existing field in any existing wiki page.
- Reverting it requires only deleting the new files.

If you are unsure whether your operation is additive or modifying, treat it as modifying (tier 3) and show a diff.

## 5. Diff format for tier 3

Render diffs as:

```
File: <path>
  - <old line>
  + <new line>
File: <path> (frontmatter)
  field <name>: <old> -> <new>
```

For binary files or large blobs, render only field-level changes. Never paste secrets into the diff display, even if the underlying file contains them.

## 6. Recovery promise (tier 4)

For every tier-4 operation, the operation file MUST document where archived data goes. Tier-4 operations never `rm` files; they `mv` to an archive path.

Standard archive paths (under `~/.software-house/`):

- Fired employee: `~/.software-house/company/alumni/<name>.md`
- Disbanded team: `~/.software-house/company/wiki/teams/_archived/<team>-<utc-timestamp>.md`
- Removed department: `~/.software-house/departments/_archived/<dept>-<utc-timestamp>/`
- Off-boarded freelance: `~/.software-house/agents/_archived/<name>-<utc-timestamp>.md`

Restoration must be one shell command (a single `mv` back to the original path). Operation files must print this exact restore command in the impact disclosure.

## 7. Failure handling

If at any step a confirmation cannot be obtained (the user does not respond, the typed token is wrong, the user replies non-affirmatively), the operation aborts cleanly:

- No partial writes. Use the temp-file + atomic rename pattern from `_shared.md §6`.
- Roll back any temp files: `rm -f` only on `.tmp` files this operation created.
- Log nothing to the audit log. The audit log records completed operations only (see §8).
- Tell the user the operation was cancelled and no changes were made.

## 8. Confirmation log discipline

When confirmation is obtained, the audit log entry MUST include the `confirmation` field per `_shared.md §5`:

```
"confirmation": {
  "tier": 2 | 3 | 4,
  "prompt": "<exact prompt text shown, including the box characters>",
  "response": "<user's verbatim next-message body, trimmed>",
  "ts": "<UTC ISO-8601>"
}
```

For tier 4, additionally store the typed token under `confirmation.token` (e.g., `"CONFIRM alice"`).

For external-provider writes, the `egress_consent` field is also required per `_shared.md §5`:

```
"egress_consent": {
  "required": true,
  "granted": "EGRESS-CONSENT-<provider>",
  "provider": "<provider>",
  "ts": "<UTC ISO-8601>"
}
```

This makes both tier confirmation and egress consent auditable retrospectively.

## 9. Parsing the user's response — strictness

Affirmative parsing for tier 2 and tier 3 (and Tier-4 step 1) is intentionally narrow:

- Accept (case-insensitive): `yes`, `y`, `proceed`, `ok`, `Yes, proceed`, `Yes`, `OK`, `Y`.
- Reject silently if the message contains any of: `no`, `cancel`, `stop`, `abort`, `wait`, `n`, `nope` — even if `yes` also appears later. Mixed signals = abort.
- A response that does not start with an accepted affirmative token, treat as non-affirmative. Abort.

Typed-token parsing for Tier-4 step 2 and egress consent:

- Look for the literal token as a substring, byte-exact (case-sensitive, exact spacing).
- The user may include explanation around the token. Token presence is sufficient.
- If the token is malformed by even one character (`CONFIRM Alice` instead of `CONFIRM alice`, `EGRESS-CONSENT-Anthropic` instead of `EGRESS-CONSENT-anthropic`), reject. Do not auto-correct.

## 10. When in doubt

Stop and ask. A confirmation that is not strictly required is harmless. A destructive action without confirmation, or an external-provider write without egress consent, is a defect.
