# Privacy Policy — Local-First Skill, Provider-Aware Agents

> **Binding rule (skill):** This skill itself must never cause data from the user's computer to leave the user's computer. Treat this as a legal compliance requirement.
>
> **Binding rule (agents the skill creates):** Agents may use external providers IF AND ONLY IF the user has typed the matching `EGRESS-CONSENT-<provider>` token at hire/set-model time, recorded in the audit log. The skill is responsible for the consent gate; the harness runtime is responsible for the actual egress when the agent runs.

This policy is read by the assistant before performing any Bash command, MCP tool invocation, or anything that could touch a network. If a contemplated action is not clearly local, refuse it and ask the user. The provider-egress section (§7) clarifies the boundary between skill-local operations and agent-runtime egress.

## 1. Tool classification (skill-local)

### 1.1 Always allowed (purely local)

- `Read`, `Write`, `Edit`, `Glob`, `Grep` — local filesystem only
- Bash commands matching the **local-only allowlist** in §2

### 1.2 Allowed after inspection (Bash)

Before running any `Bash` command (or its harness equivalent — Claude Code Bash, Codex shell tool, Gemini CLI shell), classify it using the protocol in §2. If the command matches the allowlist, run it. If it matches the denylist, refuse. If it matches neither, treat as denied and ask the user.

### 1.3 Default-denied (no exceptions inside this skill)

- `WebFetch`, `WebSearch`
- Any MCP tool that calls an external service (the skill author has not enumerated which MCPs are safe; assume all are external until proven otherwise)
- Any command that uses the network (see §2 denylist)
- Any command that uploads, syncs, or pushes to a remote

If the user explicitly asks for one of these, stop and tell the user it is outside the skill's privacy guarantees, and that they may either (a) inspect the exact command and approve it manually outside this skill, or (b) run the operation in an isolated sandbox. Do not silently bypass.

## 2. Bash inspection protocol (applies to every harness's shell tool)

For every shell command, before running:

1. **Lex the command into program + arguments + redirects + pipes.**
2. **Reject** if the command (or any piped sub-command) matches any denylist pattern in §2.2.
3. **Allow** if the command matches an allowlist pattern in §2.1.
4. **Otherwise**: refuse and ask the user. Do not assume.

The same protocol applies to Claude Code's `Bash` tool, OpenAI Codex CLI's shell tool, and Gemini CLI's shell command. Provider-specific naming differs; the inspection rule is identical.

### 2.1 Allowlist (local-only patterns)

Programs that touch only local filesystem or local processes:

```
ls, cat, head, tail, wc, sort, uniq, cut, awk, sed, grep, find, file, stat
mkdir, rmdir, touch, cp, mv, ln, chmod, chown
diff, cmp, basename, dirname, realpath, readlink
echo, printf, true, false, test, [
date, uname, whoami, id, pwd, env, which, type, command
tr, jq, yq, xxd, base64
```

Local git read/inspect operations (no network):

```
git status, git log, git diff, git show, git blame, git branch -l,
git config --get, git rev-parse, git ls-files, git cat-file,
git show-ref, git for-each-ref
```

Local git write operations on local repo only (no push):

```
git add, git commit, git restore, git checkout, git switch,
git stash, git tag (without -s --push), git reset (with explicit user confirmation per safety policy)
```

Local archive operations on local files:

```
tar (read or extract from local), zip / unzip (local), gzip / gunzip (local)
```

### 2.2 Denylist (outbound or destructive-network patterns)

Refuse if the command (or any piped sub-command) matches any of:

```
curl, wget, http, https, httpie, axel, aria2c
nc, ncat, socat, telnet, ftp, sftp, scp, rsync (with remote destination), ssh
git push, git pull, git fetch, git clone, git remote add, git submodule update --remote
gh pr create, gh pr push, gh release create, gh api (POST/PUT/PATCH/DELETE), gh repo clone, gh repo create
docker push, docker pull (without explicit user confirmation), docker login
npm publish, pip upload, twine upload, cargo publish, gem push
ping, traceroute, nslookup, dig, host
mail, sendmail, smtp, mutt
```

Any command that contains:
- `://` outside a local file URI scheme
- An IP address or hostname argument that is not `localhost` or `127.0.0.1`
- A network port number used as a destination
- Environment variables set inline that look like credentials (`AWS_*`, `GH_TOKEN`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, etc.) before an outbound program

### 2.3 Pipe and chain inspection

A pipeline is denied if any stage is denied. Examples:

- `cat secrets.env | curl ...` -> DENIED (curl is denylisted)
- `git diff | gh pr create ...` -> DENIED (gh pr create is denylisted)
- `find . -name '*.md' | xargs wc -l` -> ALLOWED (all stages local)
- `echo "$DATA" | nc host 80` -> DENIED (nc is denylisted)

Same rule for `&&`, `||`, `;` chains: every command in the chain must independently pass.

### 2.4 Sandboxing option (informational)

If the user genuinely needs an external tool, suggest they run that one operation in an isolated sandbox (a separate VM or container with no access to the company wiki). The skill itself does not provision sandboxes — it only permits the user to step outside the skill for that operation.

## 3. Filesystem scope (skill writes)

The skill writes only inside these paths:

- `~/.software-house/` (canonical company state — wiki, departments, agents pool, config, audit log, projects index)
- The current working project's `.software-house/` directory (canonical team state and canonical agent definitions)
- The current working project's harness-adapter directories — `.claude/agents/`, `.codex/agents/`, `.gemini/extensions/<name>/` — and ONLY for files the skill itself generated (auto-generated thin shims that point at the canonical agent definition). Never edit pre-existing user files in those directories.
- The current working project's `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` (team charter, only when explicitly editing team policy)
- The skill's own install location — under `~/.claude/skills/software-house/`, `~/.agents/skills/software-house/`, or `~/.gemini/extensions/software-house/` — only `config/models-config.json` and `config/providers.json` are mutable at runtime; all other files are read-only at runtime.

Writes outside these paths require explicit user confirmation, even for operations that are otherwise tier-2 additive.

## 4. Reading scope

The skill reads only inside the same paths as §3, plus:

- The current project's source code (read-only, for `lint` operation only)
- `~/.claude/CLAUDE.md`, `~/AGENTS.md`, `~/.gemini/GEMINI.md` (user global instructions per harness, read-only)
- Harness install markers — `~/.claude/`, `~/.codex/`, `~/.agents/`, `~/.gemini/` — for harness detection during `init` and `hire` (existence checks only, no contents read unless required)

Do not read user files outside these paths without explicit user request.

## 5. Logging discipline

The audit log (`~/.software-house/company/audit.log`) is local. It must never be transmitted, synced, or backed up to a remote service by any code path inside this skill. If the user wants offsite backup, that is an explicit step outside the skill.

The audit log may contain employee names, role assignments, team affiliations, provider choices, and verbatim egress consent tokens. Treat it as `internal` classification at minimum. If the user has agents tagged `confidential` or `restricted`, the audit log inherits that ceiling.

## 6. Logging what

For each operation, the audit log records:

- timestamp (UTC ISO-8601)
- actor (always `user` for now, since the user invokes commands)
- operation name
- scope (`company` | `department:<dept>` | `team:<team>` | `agent:<name>`)
- arguments (sanitized — no secrets, no API keys, no tokens other than the confirmation/consent tokens defined in `safety.md`)
- diff summary (what changed, in human terms)
- confirmation block (per `safety.md §8`) for tier 2/3/4
- egress consent block (per §7 below) for any external-provider write
- result (`ok` | `failed` with reason)

The log does not record full file contents. Diffs are summaries, not patches.

## 7. Provider egress policy — the skill/runtime boundary

This section is the single source of truth for how egress is governed. Read it before any `hire`, `set-model`, `transfer` (when it crosses provider), or `outsource hire` operation.

### 7.1 Two distinct kinds of egress

| Kind | Who performs it | When it happens | Skill's responsibility |
|---|---|---|---|
| **Skill egress** | The skill itself, via Bash/MCP/WebFetch | While an operation runs | **Forbidden, always.** §1-§5 enforce this. |
| **Agent-runtime egress** | The harness (Claude Code / Codex / Gemini) when running an agent the skill provisioned | Later, when the user invokes that agent | **Gate at provisioning time** via the consent token in `safety.md §1` "Special tier — Egress consent". The skill does not perform the egress; it permits the user to opt in to it. |

These are independent. The skill being local-only (skill egress = forbidden) does NOT mean agents are local-only. The user may explicitly choose external-provider agents; the skill's job is to make that choice deliberate and auditable.

### 7.2 Provider classification

`$PROVIDERS_CONFIG` (`~/.software-house/config/providers.json`) classifies every provider as `local` or `external`:

- `local` — runs entirely on the user's machine. No egress when the agent runs. Examples: `ollama`, `lmstudio`, `vllm`, `llamacpp`, `localai`, `jan`.
- `external` — sends conversations to a third-party service. Examples: `anthropic`, `openai`, `google`, `vertex`, `azure`, `bedrock`, `groq`, `together`, `fireworks`, `deepseek`, `mistral`, `cohere`, `xai`, `perplexity`, `openrouter`, `replicate`, `huggingface`, `novita`.

The classification is data, not code — `providers.json` is the source of truth and may be extended. Lint (`operations/lint.md`) MUST check that every agent's `provider` field appears in `providers.json` and that `egress_consent` is consistent with the provider's class.

### 7.3 Default preference

`$MODELS_CONFIG` (`~/.software-house/config/models-config.json`) MUST default `defaults_by_role` to `local` providers. Operations that auto-select a model (e.g., `hire` without an explicit `--model` flag) must default to a local provider unless the user explicitly opts in.

This is a default-safe policy: the user gets local-only behavior unless they actively choose otherwise.

### 7.4 The consent gate

When an operation would write an agent file with `provider` classified `external`:

1. The skill MUST run the egress consent gate from `safety.md §1` BEFORE writing the file.
2. The gate prints the warning (provider name, destination service domain) and waits for the user to type `EGRESS-CONSENT-<provider>` byte-exact.
3. If the token does not appear in the next user message, the operation aborts with no state change.
4. If present, the agent file is written with `egress_consent: external:<utc-date>` in its frontmatter, and the audit log entry includes the `egress_consent` block per `_shared.md §5`.

Consent is per-operation, not per-session. Each external-provider write needs a fresh typed token.

### 7.5 Revocation and downgrade

`set-model` from external -> local provider does NOT require an egress consent (downgrades are always allowed). It is still tier-3 (modifying), so the tier-3 confirmation prompt still applies. The new agent file MUST have `egress_consent: none`.

`set-model` from local -> external, or from external-A -> external-B, requires a fresh egress consent token for the new provider. This is true even if the agent already had a consent for a different external provider.

### 7.6 Lint rules

`operations/lint.md` enforces:

- Every agent file's `provider` value exists in `providers.json`.
- If `provider` class is `external`, `egress_consent` MUST start with `external:` and the audit log MUST contain a matching `EGRESS-CONSENT-<provider>` token at or after the `hired_at` (or last `set-model`) timestamp.
- If `provider` class is `local`, `egress_consent` MUST be `none`.

Violations are reported as lint findings, not auto-fixed.

## 8. Failure mode

If you are uncertain whether an action violates this policy, **the correct action is to stop and ask the user**. Do not guess. Do not "try and see." A false positive (refusing a safe action and asking) is fine. A false negative (allowing a leak, or writing an external-provider agent without consent) is a defect.
