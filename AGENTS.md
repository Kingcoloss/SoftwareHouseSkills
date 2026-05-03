# Software House Skill -- AGENTS.md (OpenAI Codex CLI project context)

This file is read by OpenAI Codex CLI agents working on THIS REPOSITORY (the skill's
own source code). It tells any Codex agent that lands here what the project is, how
to navigate it, and what the non-negotiable rules are.

---

## What this is

The **software-house skill** turns the user's computer into a managed software house:
projects that have an `AGENTS.md` (or `CLAUDE.md`, `GEMINI.md`) are **teams**, the
subagents running inside them are **employees**, and the user is the **CEO**. The
skill provides HR operations (hire, fire, transfer, promote, demote, second, disband,
onboard, off-board), a four-tier org hierarchy (Company > Department > Team > Role),
an LLM-Wiki memory system per tier, OKR cascade, gamification, and per-role
provider+model+effort selection.

The skill is **multi-harness portable**: it installs into Claude Code, OpenAI Codex
CLI, and Gemini CLI without modification to the operation files. All three harnesses
read from the same canonical state directory at `~/.software-house/`.

The skill is **multi-provider**: agents may use any of seven-plus local providers
(Ollama, LM Studio, vLLM, llama.cpp, LocalAI, Jan, text-generation-webui) or eighteen-plus external
providers (Anthropic, OpenAI, Google, Azure, Bedrock, Groq, Together, Fireworks,
DeepSeek, Mistral, Cohere, xAI, Perplexity, OpenRouter, Replicate, HuggingFace,
Novita, Vertex). External providers require explicit typed consent before any agent
is provisioned; the skill itself never egresses.

---

## Repo layout

```
SoftwareHouseSkills/
|
+-- README.md                          Project overview and quick-start
+-- INSTALL.md                         Installation guide for all harnesses
+-- LICENSE.md                         License
+-- install.sh                         Harness-detection installer
+-- AGENTS.md                          This file (Codex project context)
+-- GEMINI.md                          Gemini CLI project context (repo root)
|
+-- skills/
    +-- software-house/
        +-- SKILL.md                   Claude Code entry point (authoritative spec)
        +-- GEMINI.md                  Gemini CLI skill-level context
        +-- manifest.yaml              Skill metadata (name, version, harnesses)
        +-- gemini-extension.json      Gemini extension manifest
        |
        +-- policies/
        |   +-- safety.md              Risk tiers, confirmation gates, exact prompt wording
        |   +-- privacy.md             Local-first rule, Bash inspection protocol, egress policy
        |
        +-- operations/
        |   +-- _shared.md             Shared primitives: audit log format, temp-file protocol
        |   +-- init.md                Bootstrap ~/.software-house/ (Tier 2)
        |   +-- list.md                List people, teams, departments (Tier 1)
        |   +-- show.md                Display one entity in detail (Tier 1)
        |   +-- org-chart.md           Render ASCII org tree (Tier 1)
        |   +-- lint.md                Structural integrity check (Tier 1)
        |
        +-- adapters/                  Harness-specific thin shims
        |   +-- claude-code.md         Claude Code harness adapter
        |   +-- codex.md               OpenAI Codex CLI adapter
        |   +-- gemini.md              Gemini CLI adapter
        +-- config/
        |   +-- providers.json         Provider catalog (local vs. external, egress flags)
        |   +-- models-config.json     Default provider+model+effort per role
        |
        +-- commands/
        |   +-- software-house.toml   Gemini CLI custom command definition
        |
        +-- templates/                 (planned) Agent frontmatter templates
        +-- schemas/                   (planned) JSON schemas for agent and team files
        |
        +-- agents/
            +-- openai.yaml            Codex agent UI metadata and invocation policy
```

---

## How to run the skill from Codex

1. **Install** -- run `./install.sh` from the repo root. The installer detects Codex
   by checking for `~/.codex` or `~/.agents` and copies the skill tree to
   `~/.agents/skills/software-house/`.

2. **Invoke** -- in any Codex session, type:

   ```
   /software-house <command>
   ```

   Available Phase 1 commands: `init`, `list`, `show`, `org-chart`, `lint`.

3. **State** -- canonical company state lives at `~/.software-house/`. All harnesses
   read and write the same directory.

---

## Critical constraints (C1-C4)

These rules are non-negotiable. Any Codex agent working on this repo or running
this skill must honor them. They mirror `skills/software-house/SKILL.md` exactly.

### C1. Skill operations never send data off the machine

The skill itself is local-only. No `curl`, `wget`, `git push`, `gh pr create`,
`gh api` (outbound), `WebFetch`, `WebSearch`, or any network call is permitted
inside any skill operation. Read `skills/software-house/policies/privacy.md` in
full before any shell command. The Bash allowlist and denylist in that file are
binding.

### C2. Agent execution may egress only with typed consent

When provisioning an agent with an external provider (any provider classified
`external` in `config/providers.json`), the skill MUST present a warning naming
the destination service and require the user to type the literal token:

```
EGRESS-CONSENT-<provider>
```

byte-exact, before writing the agent file. Consent is recorded in the audit log.
Reusing a prior session's consent is forbidden -- each external-provider write
needs a fresh typed token. Local providers (Ollama, LM Studio, vLLM, llama.cpp,
LocalAI, Jan) require no consent gate.

### C3. Destructive operations require typed confirmation

Regardless of whether `--dangerously-bypass-approvals-and-sandbox` or `--full-auto`
is active, the skill enforces its own confirmation gate. Risk tiers and exact prompt
wording are in `skills/software-house/policies/safety.md`. The gate is a plain-text
printed prompt followed by a wait for the next user message. Do not improvise the
wording. Required typed tokens:

- Tier 2 (additive): case-insensitive `yes` / `y` / `proceed` / `ok`
- Tier 3 (modifying): same affirmative tokens, after a structured diff
- Tier 4 (destructive): two-step -- affirmative at step 1, then `CONFIRM <subject-name>` byte-exact at step 2

### C4. Audit log is append-only

`~/.software-house/company/audit.log` is JSONL, append-only. One line per
state-modifying operation. Never edit or delete past entries. Format defined in
`skills/software-house/operations/_shared.md`.

---

## Working on this repo

When a Codex agent edits the skill source:

- **No emoji in any file.** Pure ASCII only. Verify with:
  ```
  python3 -c "import re; F='<path>'; print(len(re.findall(r'[\U0001F000-\U0001FFFF\u2600-\u27ff\U0001F300-\U0001F9FF]',open(F).read())))"
  ```
  Must print `0`.

- **Preserve harness-portable posture.** Operation files under `operations/` must
  not import Claude Code-specific tool primitives (e.g., `AskUserQuestion`,
  `computer_use`, Claude-specific MCP calls). They must use only: `Read`, `Write`,
  `Edit`, `Bash`/shell, `Glob`, `Grep` -- tools available in all three harnesses.

- **Validate config files before committing:**
  - JSON: `python3 -m json.tool < <file>` -- must exit 0
  - YAML: `python3 -c "import yaml; yaml.safe_load(open('<file>'))"`
  - TOML: `python3 -c "import tomllib; tomllib.load(open('<file>','rb'))"`

- **No auto-init.** If `~/.software-house/` does not exist, the skill tells the
  user and offers `init`. It does not create the directory automatically.

- **No network calls from operations.** If a proposed operation file would require
  a network call, reject it and redesign without network dependency.

---

## References

- Codex skills docs: https://developers.openai.com/codex/skills
- agents.md spec: https://developers.openai.com/codex/guides/agents-md
- Codex skills on GitHub: https://github.com/openai/codex/blob/main/docs/skills.md
