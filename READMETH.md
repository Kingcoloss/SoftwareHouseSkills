# software-house

Skill แบบ multi-harness และ multi-provider ที่เปลี่ยนเครื่องของคุณให้กลายเป็นบริษัทซอฟต์แวร์ที่จัดการได้ Subagent กลายเป็นพนักงาน, project กลายเป็นทีม, และคุณคือ CEO. ตัว skill เองไม่ส่งข้อมูลออกนอกเครื่องเลยแม้แต่ไบต์เดียว; agent ที่คุณตั้งค่าให้ใช้ external provider เท่านั้นที่จะ egress ได้ และต้องพิมพ์ token แบบครั้งเดียว `EGRESS-CONSENT-<provider>` ที่บันทึกใน audit log ก่อน. มาพร้อม HR-style workforce operations, OKR cascade, Scrum, plan execution, การ spawn sub-agent, inter-agent handoff, LLM Wiki, และระบบ skill แบบ gamified ใช้งานเหมือนกันทั้ง Claude Code, OpenAI Codex CLI หรือ Gemini CLI.

---

## คำอธิบาย Skill

software-house จำลองบริษัทซอฟต์แวร์เป็น directory tree ภายใต้ `~/.software-house/`. agent ทุกตัวที่คุณ hire จะมี canonical markdown definition พร้อม frontmatter (provider, model, role, level, XP, harness, tools, role template) และ adapter shim ที่ generate ขึ้นมาเองสำหรับแต่ละ harness ที่ติดตั้งอยู่ (Claude Code, Codex, Gemini). Skill บังคับใช้ระบบ confirmation gate 4 tier, audit log แบบ append-only, และ provider policy แบบ local-default เพื่อให้ external API call เป็นแบบ opt-in เสมอ.

ความสามารถหลัก:

- **HR operations**: hire, fire, transfer, promote, demote, second (matrix assignment), onboard, off-board, disband
- **Read-only inspection**: list, show, org-chart, lint
- **Outsource management**: outsource-hire, contract (freelance pool พร้อมการ attach กับ project)
- **OKR cascade**: ตั้งและทบทวน objective ที่ tier company, department หรือ team
- **Gamification**: XP, level (1--5), achievement, skill tree, dashboard
- **Scrum**: จัดการ backlog (add/list/prioritize) และ sprint lifecycle (create/plan/board/standup/review/retro)
- **Plan execution**: plan-create, plan-confirm, plan-execute (auto-spawn sub-agent แบบ parallel), plan-status, plan-synthesize
- **Sub-agent spawning**: `bin/sh-agent` CLI executor พร้อม provider adapter (Ollama, LMStudio, vLLM, Anthropic) และ fallback แบบ 3 tier (harness -> direct provider -> Claude)
- **Harness routing**: route sub-agent ผ่าน CLI ตัวอื่น (claude-code, codex, gemini, ollama:<integration>) ด้วย field `harness` ใน frontmatter
- **Inter-agent handoff**: brief แบบ structured ใน `wiki/handoffs/inbox/` และ `completed/` พร้อม subcommand list/show/complete/generate
- **LLM Wiki**: หน้า entity, concept, decision, synthesis ที่ compile ขึ้นใหม่ทุกครั้งที่ state เปลี่ยน เพื่อให้ assistant โหลด context ได้รวดเร็วและ structured
- **Wiki ingestion และ lint**: archive raw source, compile เป็น wiki page และรัน health check 8 ประเภท (confidence drift, stale page, broken wikilink, orphan page เป็นต้น)
- **Multi-provider**: 7 local provider และ 18 external provider ต่อ role, นโยบาย local-default พร้อม egress consent gate
- **Update mechanism**: ตรวจ version, แสดง changelog, config overlay, schema migration, re-sync adapter

### Mental Model

| โลกจริง        | ใน Skill (canonical)                                            | Adapter ต่อ harness (auto-generate)                       |
|----------------|----------------------------------------------------------------|------------------------------------------------------------|
| บริษัท         | เครื่องคอมของคุณ (`~/.software-house/`)                          | n/a                                                        |
| แผนก           | กลุ่มของทีม (`~/.software-house/departments/<d>/`)               | n/a                                                        |
| ทีม            | Folder project ที่มี `CLAUDE.md`, `AGENTS.md`, หรือ `GEMINI.md`  | n/a                                                        |
| พนักงาน        | Agent canonical ที่ `<project>/.software-house/agents/<n>.md`    | `<project>/.claude/agents/`, `.codex/agents/`, `.gemini/extensions/<n>/` (shim บางๆ) |
| Freelance pool | `~/.software-house/agents/`                                     | `~/.claude/agents/`, `~/.codex/agents/`, `~/.gemini/extensions/<n>/`                  |
| CEO            | คุณ                                                              | n/a                                                        |

### Data Layout

```
~/.software-house/                       <- Canonical state (เป็นกลางต่อ harness)
~/.software-house/company/               <- Tier บริษัท (audit log อยู่ที่นี่)
~/.software-house/departments/<d>/       <- Tier แผนก
~/.software-house/agents/                <- Freelance / outsource pool
~/.software-house/config/providers.json  <- Catalog 25 provider พร้อม flag egress
~/.software-house/config/providers.local.json  <- User overlay (ไม่ถูก overwrite ตอน update)
~/.software-house/config/models-config.json   <- ค่า default ตาม role + harness_defaults
~/.software-house/config/models-config.local.json <- User overlay (ไม่ถูก overwrite)
~/.software-house/config/role-templates.json  <- 10 role template (responsibilities, deliverables, ...)
~/.software-house/config/tools-config.json    <- Tool vocabulary แบบ shared และต่อ role

<project>/.software-house/team/          <- State ของทีม (LLM Wiki)
<project>/.software-house/team/backlog.md
<project>/.software-house/team/sprints/<id>/
<project>/.software-house/team/plans/<id>/
<project>/.software-house/team/wiki/concepts/
<project>/.software-house/team/wiki/decisions/
<project>/.software-house/team/wiki/synthesis/
<project>/.software-house/team/wiki/handoffs/inbox/
<project>/.software-house/team/wiki/handoffs/completed/
<project>/.software-house/team/wiki/handoffs/briefs/
<project>/.software-house/agents/<n>.md  <- Definition agent (canonical)
<project>/.claude/agents/<n>.md          <- Adapter (auto-generate)
<project>/.codex/agents/<n>.md           <- Adapter (auto-generate)
<project>/.gemini/extensions/<n>/        <- Adapter (auto-generate)
```

### ความเข้ากันได้กับ Harness

| Harness          | Path ติดตั้ง (default)                  | Entry-point                    | Bypass flag (ยังถูก gate โดย skill อยู่) |
|------------------|-----------------------------------------|--------------------------------|------------------------------------|
| Claude Code      | `~/.claude/skills/software-house/`      | `SKILL.md`                     | `--dangerously-skip-permissions`   |
| OpenAI Codex CLI | `~/.agents/skills/software-house/`      | `SKILL.md` (+ `agents/openai.yaml`) | `--dangerously-bypass-approvals-and-sandbox` / `--full-auto` |
| Gemini CLI       | `~/.gemini/extensions/software-house/`  | `gemini-extension.json` + `GEMINI.md` + `commands/*.toml` | `--yolo` / `--approval-mode yolo`  |

CLI ทั้งสามตัวอ่าน canonical state เดียวกัน. Adapter directory ของแต่ละ harness เป็นแค่ shim บางๆ ที่ชี้ไปที่ canonical agent file. คุณ hire พนักงานครั้งเดียวแล้วใช้จาก harness ไหนก็ได้.

---

## การติดตั้ง

อ่านรายละเอียดได้ที่ [INSTALL.md](./INSTALL.md). Quick start:

```sh
# Clone repo และเข้า directory
git clone <repo-url> && cd SoftwareHouseSkills

# ดูว่าจะตรวจเจอ harness อะไรบ้าง
./install.sh --list-harnesses

# ติดตั้งใน harness ทั้งหมดที่ตรวจเจอ (ถามก่อน overwrite)
./install.sh

# ติดตั้งแค่ harness เดียว
./install.sh --harness claude-code

# Dev mode: symlink แทน copy (แก้ source แล้ว live)
./install.sh --symlink

# Update installation ที่มีอยู่ (ตรวจ version, ดู changelog, รัน migration)
./install.sh --update

# Re-sync adapter shim หลัง canonical agent เปลี่ยน
./install.sh --fix-adapters
```

Installer ตรวจ harness ที่ติดตั้งอยู่จาก `~/.claude`, `~/.codex`/`~/.agents` และ `~/.gemini`. Codex ต้องมี manual step หลังติดตั้ง (เพิ่ม `[[skills]]` ใน `~/.codex/config.toml`); installer จะ print snippet ให้.

### Config Overlay

Config file ใช้ pattern แบบ 2 layer:

- **Skill-managed** (`providers.json`, `models-config.json`, `role-templates.json`, `tools-config.json`) -- ถูก overwrite ทุกครั้งที่รัน `install.sh` ด้วย default ใหม่.
- **User overlay** (`*.local.json`) -- ไม่ถูก overwrite. ใส่ provider, role default หรือ model alias ที่ custom เองได้.

ตอนอ่าน config, overlay จะ merge ทับ base file.

### Version และ Migration

Skill มี file `VERSION` (semver, ปัจจุบัน `0.9.0`). ตอน update:

- **Version เดียวกัน**: ถามว่าจะ re-install ไหม (หรือข้ามด้วย `--force`).
- **Upgrade**: แสดง CHANGELOG ระหว่าง version, รัน migration ที่ค้าง, แล้วค่อยติดตั้ง.
- **Downgrade**: เตือนและขอ confirm.

Migration เป็น shell script ใน `migrations/NNN-<name>.sh` รันเรียงตามลำดับเมื่อ version เปลี่ยน. ปัจจุบันมี 5 migration: 001 baseline, 002 tools field, 003 sprint/plan dirs, 004 role-template + wiki-LLM backfill, 005 harness field. อ่าน contract ได้ที่ `migrations/README.md`.

---

## วิธีใช้งาน

### Initialize บริษัท

เปิด project ไหนก็ได้แล้วรัน:

```
/software-house init
```

Bootstrap `~/.software-house/`. มีการ confirm ก่อนสร้าง file.

### Hire พนักงาน

Local provider (default: Ollama, ไม่มี egress):

```
/software-house hire alice --role backend-dev
```

External provider (ต้องให้ egress consent):

```
/software-house hire bob --role tech-lead --provider anthropic --model claude-opus-4-7
```

Skill จะ print warning บอกชื่อ service ปลายทาง แล้วรอให้คุณพิมพ์ `EGRESS-CONSENT-anthropic` ก่อนเขียน agent file.

### Hire Freelance

```
/software-house outsource-hire carol --role designer --provider google --model gemini-2.5-pro
```

Agent ใน freelance pool อยู่ที่ `~/.software-house/agents/` และจะยังไม่มี adapter shim ต่อ project จนกว่าจะ contract ให้ทีม.

### Attach Freelancer ให้ Project

```
/software-house contract carol --team my-project
```

Generate adapter shim ใน harness directory ของ project นั้น.

### Move, Promote, Manage

```
/software-house transfer alice --to backend-team
/software-house promote alice --to-role senior-dev
/software-house demote alice --by 1
/software-house second alice --to frontend-team
/software-house set-model alice --provider openai --model gpt-4.1
/software-house set-model alice --harness claude-code
/software-house set-model alice --clear-harness
```

### Sub-Agent Spawning และ Delegation

รัน task ของ agent ผ่าน provider ที่ตั้งไว้ (พร้อม fallback 3 tier):

```
bin/sh-agent alice "Refactor the auth middleware"
bin/sh-agent alice "Refactor the auth middleware" --harness claude-code
```

หรือผ่าน skill:

```
/software-house delegate alice --task "Refactor the auth middleware"
/software-house delegate alice --task "Refactor the auth middleware" --execute
```

`--execute` จะรัน sub-agent inline หลังผ่าน confirmation tier 2 และเขียน response ลง `.md` file. ถ้าไม่ใส่ `--execute`, operation จะ print แค่คำสั่ง `sh-agent` ให้คุณดูก่อน.

### Inter-Agent Handoff

```
/software-house handoff generate --from alice --to bob --task "..." --priority high
/software-house handoff list --team my-project --status inbox
/software-house handoff show <brief-id>
/software-house handoff complete <brief-id> --summary "..."
```

Brief เป็น markdown file พร้อม JSONL frontmatter ที่ route ผ่าน `wiki/handoffs/inbox/` และ `completed/`. เมื่อ complete, wiki page ของทั้งฝ่ายส่งและฝ่ายรับจะ update.

### Scrum (Backlog และ Sprint)

```
/software-house backlog add --title "Fix auth bug" --priority high
/software-house backlog list --status open
/software-house backlog prioritize <item-id> --priority urgent

/software-house sprint create --goal "Ship auth refactor"
/software-house sprint plan <sprint-id> --items <i1>,<i2>,<i3>
/software-house sprint board <sprint-id>
/software-house sprint standup <sprint-id>
/software-house sprint review <sprint-id>
/software-house sprint retro <sprint-id>
```

### Plan Execution (auto-spawn sub-agent แบบ parallel)

```
/software-house plan create --goal "Add OAuth flow"
/software-house plan confirm <plan-id>
/software-house plan execute <plan-id>
/software-house plan status <plan-id>
/software-house plan synthesize <plan-id>
```

`plan execute` ทำ topological sort กับ task graph แล้ว dispatch task ที่ไม่ขึ้นต่อกันแบบ parallel ผ่าน Claude Code Agent tool (หรือ manual dispatch ใน Codex/Gemini).

### Wiki Ingestion และ Lint

```
/software-house wiki-ingest <source-file> --kind concept
/software-house wiki-lint
/software-house wiki-lint --fix-suggestions
/software-house wiki-lint --json
```

Health check 8 ประเภท: confidence drift, stale page, broken wikilink, orphan page, empty section, missing concept, source trail integrity, wikilink consistency.

### OKR และ Gamification

```
/software-house okr-set --tier company --objective "Ship v2 by Q3"
/software-house award-xp alice --amount 100 --reason "shipped auth refactor"
/software-house dashboard
```

### Inspect และ Lint

```
/software-house list people
/software-house show alice
/software-house org-chart
/software-house lint
/software-house lint --fix-adapters
```

### ลบ Agent

```
/software-house off-board alice          # รัน checklist off-boarding ก่อน
/software-house fire alice               # Tier 4 gate: confirm 2 step ด้วยการพิมพ์
```

Adapter shim จะถูกย้ายไป `~/.software-house/.trash/` (ไม่ลบทิ้ง) เพื่อ recover ได้.

### CLI (Reference Implementation)

มี bash CLI 2 ตัวใน `bin/`:

```sh
bin/software-house --help
bin/software-house --version          # 0.9.0
bin/software-house hire --help        # Help ต่อคำสั่ง
bin/software-house list people --dry-run  # Preview โดยไม่แก้ไขอะไร

bin/sh-agent --help
bin/sh-agent alice "task description" --harness claude-code
```

`bin/software-house` คือ operation dispatcher (มี module 41 ตัวใน `lib/operations/`). `bin/sh-agent` คือ sub-agent executor ที่อ่าน wiki ของ agent มาทำ personalization, สร้าง system prompt, แล้วรัน task ผ่าน provider adapter chain (`lib/providers/`) พร้อม fallback 3 tier.

### Privacy และ Safety

Skill บังคับใช้ privacy model แบบ 2 layer:

| Layer          | ใครเป็นคนทำ                       | อะไรอนุญาตได้บ้าง                                                                                       |
|----------------|-----------------------------------|--------------------------------------------------------------------------------------------------------|
| Skill          | ตัว skill เอง ตอนทำงาน             | File operation บน local เท่านั้น. ห้าม `WebFetch`, `WebSearch`, `curl`, `git push`, MCP. มี allowlist + denylist บังคับใช้ก่อนทุกคำสั่ง shell. |
| Agent runtime  | Harness (ตอน agent รัน)            | Egress อนุญาตได้ก็ต่อเมื่อ `provider` ของ agent เป็น `external` และ user พิมพ์ `EGRESS-CONSENT-<provider>` ตอน hire/set-model ที่บันทึกใน audit log. Agent ที่ใช้ local provider จะไม่ egress เลย. |

Confirmation gate ยังบังคับใช้แม้ harness bypass flag จะเปิดอยู่:

| Tier                    | ตัวอย่าง                       | Gate                                                |
|-------------------------|-------------------------------|-----------------------------------------------------|
| 1 -- Read-only          | list, show, org-chart, lint, dashboard, sprint-board, plan-status, handoff-list, handoff-show | ไม่มี |
| 2 -- Additive           | init, hire (draft), onboard, dept-create, backlog-add, sprint-create, plan-create, handoff-generate, wiki-ingest | "Reply 'yes' to proceed" boxed prompt |
| 3 -- Modifying          | transfer, promote, demote, set-model, contract, off-board, sprint-plan, plan-confirm, plan-execute, handoff-complete, delegate | Diff + "Reply 'yes' to proceed" |
| 4 -- Destructive        | fire, disband                 | 2 step: ถาม intent แล้วพิมพ์ `CONFIRM <subject-name>` |
| Egress consent (orthogonal) | hire/set-model/delegate กับ external provider | พิมพ์ token ตรงตัว `EGRESS-CONSENT-<provider>` |

ทุก operation ที่แก้ state จะ append 1 บรรทัด JSONL ลง `~/.software-house/company/audit.log`. Record ไม่ถูกแก้หรือลบเลย.

---

## Command Reference

### Phase 1 -- Foundation (Read-only)

| Command     | คำอธิบาย                                          | Risk Tier |
|-------------|------------------------------------------------|-----------|
| `init`      | Bootstrap `~/.software-house/`                  | 2         |
| `list`      | List พนักงาน, ทีม, แผนก, freelance pool          | 1         |
| `show`      | แสดงรายละเอียดของ entity                          | 1         |
| `org-chart` | Render ASCII org tree                           | 1         |
| `lint`      | ตรวจสุขภาพ state ของบริษัท                        | 1         |

### Phase 2 -- Recruitment

| Command       | คำอธิบาย                                                          | Risk Tier |
|---------------|--------------------------------------------------------------------|-----------|
| `hire`        | สร้าง agent ใหม่พร้อม provider/model/effort + egress consent gate  | 2         |
| `onboard`     | รัน checklist onboarding                                            | 2         |
| `fire`        | ลบ agent (2 step typed CONFIRM)                                     | 4         |
| `dept create` | สร้างแผนกใหม่                                                       | 2         |
| `dept assign` | Assign agent ให้แผนก                                                | 2         |

### Phase 3 -- Mobility และ Outsource

| Command          | คำอธิบาย                                                            | Risk Tier |
|------------------|--------------------------------------------------------------------|-----------|
| `transfer`       | ย้าย agent ไปทีมอื่น (re-consent egress ข้าม project)              | 3         |
| `second`         | Matrix-assign agent ให้ทีมที่ 2                                     | 3         |
| `promote`        | เพิ่ม level/role ของ agent                                          | 3         |
| `demote`         | ลด level/role ของ agent                                             | 3         |
| `set-model`      | เปลี่ยน provider/model/effort/harness (re-consent ถ้าเป็น external) | 3         |
| `outsource-hire` | เพิ่ม agent ลง freelance pool                                       | 2         |
| `contract`       | Attach freelance agent ให้ทีม project                               | 3         |
| `off-board`      | Off-boarding checklist ก่อนลบ                                       | 3         |
| `disband`        | ลบทั้งทีม (2 step typed CONFIRM)                                    | 4         |

### Phase 4 -- OKR และ Gamification

| Command       | คำอธิบาย                                            | Risk Tier |
|---------------|-----------------------------------------------------|-----------|
| `okr set`     | ตั้ง OKR ที่ tier company, department หรือ team     | 2         |
| `okr review`  | ทบทวนความคืบหน้า OKR                                 | 1         |
| `award-xp`    | ให้ XP และ trigger เช็ค level/achievement            | 3         |
| `dashboard`   | แสดงสถิติ gamification และ skill tree                | 1         |

### Phase 5 -- Scrum (Backlog และ Sprint)

| Command               | คำอธิบาย                                       | Risk Tier |
|-----------------------|----------------------------------------------|-----------|
| `backlog add`         | เพิ่ม backlog item                             | 2         |
| `backlog list`        | List backlog item (filter ด้วย status ฯลฯ)    | 1         |
| `backlog prioritize`  | จัดลำดับใหม่ของ backlog item                   | 3         |
| `sprint create`       | สร้าง sprint พร้อม goal                        | 2         |
| `sprint plan`         | Assign backlog item ให้ sprint                | 3         |
| `sprint board`        | แสดง sprint board                             | 1         |
| `sprint standup`      | View standup รายวัน                            | 1         |
| `sprint review`       | สรุป sprint review                             | 1         |
| `sprint retro`        | บันทึก retrospective                            | 2         |

### Phase 6 -- Plan Execution

| Command            | คำอธิบาย                                                  | Risk Tier |
|--------------------|------------------------------------------------------------|-----------|
| `plan create`      | เขียน plan แบบหลาย task พร้อม dependency                     | 2         |
| `plan confirm`     | Confirm และ lock plan ก่อน execute                          | 3         |
| `plan execute`     | Auto-spawn sub-agent แบบ parallel ตาม topological wave      | 3         |
| `plan status`      | แสดงความคืบหน้าของ plan                                      | 1         |
| `plan synthesize`  | รวม output ของ sub-agent เป็น deliverable เดียว              | 3         |

### Phase 7 -- Sub-Agent Delegation

| Command     | คำอธิบาย                                                                | Risk Tier |
|-------------|------------------------------------------------------------------------|-----------|
| `delegate`  | ส่ง task ให้ agent. `--execute` รัน inline; `--watch` ตาม output        | 3         |

### Phase 8 -- Inter-Agent Handoff

| Command                | คำอธิบาย                                                | Risk Tier |
|------------------------|----------------------------------------------------------|-----------|
| `handoff generate`     | สร้าง handoff brief แบบ structured                        | 2         |
| `handoff list`         | List handoff brief (filter ด้วย team, status, from, to)   | 1         |
| `handoff show`         | แสดง brief หนึ่งอัน                                        | 1         |
| `handoff complete`     | ปิด brief พร้อม summary                                    | 3         |

### Phase 9 -- Wiki-LLM

| Command           | คำอธิบาย                                                 | Risk Tier |
|-------------------|----------------------------------------------------------|-----------|
| `wiki-ingest`     | Archive source file แล้ว compile เป็น wiki page           | 2         |
| `wiki-lint`       | รัน health check 8 ประเภท; รองรับ `--fix-suggestions` และ `--json` | 1 |

### Flag เพิ่มเติม

| Flag                | คำอธิบาย                                                          |
|---------------------|-------------------------------------------------------------------|
| `--dry-run`         | Preview โดยไม่แก้ไขอะไร                                            |
| `--fix-adapters`    | Regenerate adapter shim ของ project จาก canonical agent file      |
| `--harness <value>` | Route execution ของ sub-agent ผ่าน CLI ตัวอื่น (sh-agent, set-model) |
| `--clear-harness`   | ลบ field harness ออก (ใช้กับ set-model)                            |
| `--execute`         | รัน sub-agent inline หลัง confirmation (ใช้กับ delegate)           |
| `--watch`           | ตาม output ของ sub-agent (ใช้กับ delegate)                         |
| `--help`            | แสดง help                                                          |
| `--version`         | แสดง version (ปัจจุบัน 0.9.0)                                      |

---

## Architecture Overview

Skill จัดเป็น 4 tier โดยแต่ละ tier มี layout เหมือนกัน:

```
<tier-root>/
  raw/       <- เอกสาร source ที่ไม่เปลี่ยน (job spec, policy ฯลฯ)
  wiki/      <- หน้า entity, concept, decision, synthesis และ handoff ที่ compile แล้ว
  index.md   <- Catalog ของ entity ใน tier นี้ (auto-generate)
  audit.log  <- JSONL event stream แบบ append-only
  CLAUDE.md  <- Schema และคำสั่งของ tier นี้
```

Pattern **LLM Wiki** จะ compile raw source เป็น page ที่ dense และ structured ให้ assistant โหลดได้ด้วย token น้อยกว่าการอ่าน raw file ใหม่. แต่ละ page มี frontmatter `confidence`, `lifecycle`, `last_compiled`, `source_refs` และจะ regenerate อัตโนมัติเมื่อ source เปลี่ยน. `wiki-lint` บังคับใช้ health check 8 ประเภทกับทั้ง corpus.

Tier:

1. **Company** -- `~/.software-house/company/` -- policy ระดับ global, headcount, OKR ระดับบนสุด
2. **Department** -- `~/.software-house/departments/<dept>/` -- กลุ่มของทีม, OKR ของแผนก
3. **Team** -- `<project>/.software-house/team/` -- context ของ project, sprint board, plan board, handoff inbox, OKR ของทีม
4. **Role** -- `<project>/.software-house/agents/<role>.md` (canonical) พร้อม harness adapter ที่ generate เองใน `<project>/.claude/agents/`, `<project>/.codex/agents/`, `<project>/.gemini/extensions/<role>/`. Freelance pool อยู่ที่ `~/.software-house/agents/`.

### เส้นทาง Execute Sub-Agent

เมื่อรัน `bin/sh-agent <agent> <task>` (หรือ `delegate --execute`), executor จะ:

1. อ่าน agent definition แล้ว resolve `provider`, `model`, `effort`, `harness`, tools.
2. โหลด wiki page ของ agent มาเป็น context personalization (responsibilities, deliverables, collaborator).
3. โหลด role template (responsibilities, handoff trigger) จาก `config/role-templates.json`.
4. สร้าง system prompt แล้ว dispatch ผ่าน `execute_with_fallback`:
   - **Tier 1** -- ถ้าตั้ง `harness` (claude-code, codex, gemini, ollama:<integration>), route ผ่าน CLI นั้น.
   - **Tier 2** -- ถ้าไม่ได้ตั้ง, เรียก provider adapter ตรงๆ (`lib/providers/{ollama,lmstudio,vllm,anthropic}.sh`).
   - **Tier 3** -- ถ้า fail, fallback ไป Anthropic ถ้า role มี `fallback_claude` ตั้งไว้และมี egress consent.
5. เขียน response ของ model ลง `.md` file และ append audit record แบบ JSONL.

---

## โครงสร้าง Project

```
SoftwareHouseSkills/
  install.sh                                    <- Installer แบบ multi-harness
  skills/software-house/
    SKILL.md                                    <- Entry point Claude Code
    AGENTS.md                                   <- Entry point Codex
    GEMINI.md                                   <- Entry point Gemini
    VERSION                                     <- Semver (0.9.0)
    CHANGELOG.md                                <- Format Keep a Changelog
    manifest.yaml                               <- Manifest ของ operation
    bin/
      software-house                            <- Operation dispatcher
      sh-agent                                  <- Sub-agent executor
    lib/
      _shared.sh                                <- Bash library + helper สำหรับ harness/role-template
      operations/                               <- Operation module 41 ตัว
      providers/                                <- Provider adapter 5 ตัว (ollama, lmstudio, vllm, anthropic, _shared)
    adapters/                                   <- เอกสาร adapter ของแต่ละ harness (claude-code, codex, gemini)
    scripts/
      obsidian-setup.sh                         <- ตั้ง Obsidian vault ด้วย symlink
    tests/                                      <- Test suite (9 file)
    commands/software-house.toml                <- คำสั่งสำหรับ Gemini CLI
    config/
      providers.json                            <- Catalog 25 provider
      providers.local.json                      <- User overlay (ไม่ถูก overwrite)
      models-config.json                        <- Default ตาม role + harness_defaults
      models-config.local.json                  <- User overlay (ไม่ถูก overwrite)
      role-templates.json                       <- 10 role template
      tools-config.json                         <- Tool vocabulary แบบ shared และต่อ role
    operations/                                 <- Operation spec markdown 41 file
    schemas/                                    <- agent, sprint, backlog-item, plan, handoff-brief
    templates/                                  <- agent-starter, dept-charter, backlog, sprint, plan
    policies/                                   <- Policy ด้าน privacy และ safety
    migrations/                                 <- Migration script 5 file (001-005)
```

---

## License

MIT -- copyright 2026 kanganapong sriduang. ดูที่ [LICENSE.md](./LICENSE.md).
