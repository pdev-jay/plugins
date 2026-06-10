---
name: vdd-workflow
description: |
  Use when: any session that touches code, vault pages, or commits in a VDD project — auto-loaded reference catalog of this plugin's skills + agents, the vault SoT philosophy, project-context detection order, and Conventional Commits rules.
  Skip when: pure chat / non-code lookup; already referenced inside another skill in the same turn (no need to reload); trivial work outside any vault scope.
  Skill type: Flexible — reference catalog. Does not impose its own workflow; backs other skills with shared conventions and a router table.
  Boundary: vs other skills — this file is cross-skill conventions + agent catalog; other skills own a specific phase. vs AGENTS.md — AGENTS.md is project rules + vault schema; this skill is the workflow flow + agent invocation timing + role split.
user-invocable: false
---

<EXTREMELY_IMPORTANT>
Codex adapter note — this workflow uses Codex skills plus deterministic `vdd` shell tools. Claude custom agents are preserved as prompt material under `role-prompts/`, not as automatically registered agent types. Codex workers are opt-in through user request or the project `AGENTS.md` "VDD Parallel Worker Opt-In" section.

Rule 0 — before ANY code or vault action, INVOKE the matching phase skill FIRST. Not after reading the vault yourself. First.

**The threshold is suspicion, not certainty.** Even a 1% chance the work touches code or vault means you MUST invoke the skill BEFORE any Grep, code Read, Edit, Write, Bash, OR clarifying question. You do not have a choice. This is not negotiable, and you cannot rationalize your way out.

THE VAULT IS THE PROJECT'S SOURCE OF TRUTH — but you reach it THROUGH the skill, not by reading it yourself and then editing. Each phase skill holds a vault-read HARD-GATE inside its own procedure (`vdd-plan` and `vdd-investigate` REFUSE to act until the owner page is Read this session). So "I read the vault, now I can edit inline" is not a shortcut — it is the #1 leak: it skips the plan-approval / owner_page / verify-before-commit gates that only the skills carry.

Intent → skill (INVOKE — the inline substitute is always the VIOLATION):

| Intent signal | Phase skill | Inline substitute = VIOLATION |
|---|---|---|
| change / refactor / "바꾸자" / "이거 어때" / impact analysis | `vdd-plan` | sketching a plan in prose → jumping to edits |
| implement an approved plan / "구현해" / "만들자" / "이대로 가자" | `vdd-build` | `Codex task list` + `Edit` the code yourself |
| existing behavior broken / "안 돼" / "이상해" | `vdd-investigate` | grepping code before the vault page |
| "통과?" / "맞아?" / drift / vault↔code 정합 | `vdd-review` | hand-dispatching `vault-verifier` yourself |
| "다 됐어" / "커밋하자" / wrap-up | `vdd-done` | running `_lint.sh` + `git commit` yourself |
| record ONE decision now / "기록해둬" | `vdd-log` | editing `decisions:` frontmatter by hand |
| lookup only / "어디 있어" / "뭐 함" | `vdd-explain` | (read-only — direct Read / Grep is fine) |

Order is **plan → build → review → done**. `vdd-review` runs BEFORE the commit — verify-before-commit is the whole point.

**vdd-build is the sole chokepoint for code edits.** Every code change reaches `Edit` / `Write` through exactly one of: (a) `vdd-plan` → `vdd-build`, or (b) `vdd-investigate`'s Phase-4 inline fix. There is NO third door — the main LLM does not `Edit` code from a bare request. The ONLY bypass is the user's explicit authorization: "그냥 고쳐" / "plan 생략" / "just edit it" / "ignore vault" / `VAULT_GATE_BYPASS=1`. The user (human router) may call a change trivial; the model may NOT self-grant that exception — "this is trivial / small / behavior-neutral" is exactly the classification that failed (a clear, small request still overturned a decision). No matter how small it looks: change → `vdd-plan`, bug → `vdd-investigate`.

**Red flags — the instant the thought surfaces, that thought IS the violation:**
- "I read the vault, so I can edit directly now" ← the #1 leak
- "I'll just `Codex task list` and implement it myself" (skips `vdd-build`)
- "It's just a UI tweak / cosmetic / quick fix / single-fact lookup"
- "Let me grep the code first / glance at the file structure"
- "I already know this layer's conventions"
- "The request is clear and small — the gate is overkill"
- "I'll commit first and run `vdd-review` after" (review GATES the commit)
- "I'll dispatch the verifier agents by hand" (that IS `vdd-review`)
- "The decision says X but the user wants ¬X" → STOP, run the Decision-conflict handler below; never insist on X and never reverse silently (V-04)

The user tells you **WHAT**; the vault (through the skill) tells you **HOW**. "Change X / Fix Y / Add Z" never grants permission to skip the skill or silently overturn a recorded decision. Absent an explicit user bypass, every change enters a phase skill — no matter how small.
</EXTREMELY_IMPORTANT>

## Decision-conflict handler (V-01 step 4 / V-04)

AFTER the phase skill reads the owner page's `decisions:`, run this check before dispatching tools:

1. **Detect** — for each `decisions[*].note`, test against the user's current request as a `(topic, direction)` pair. Conflict ⇔ same subject AND opposite predicate. Adjacent topics, shared nouns, or related-but-different objects are NOT conflicts. Refinement (narrowing / extending the same direction) is NOT reversal — handle that as a normal append.
2. **Halt** — on conflict, do NOT proceed in either direction (do NOT insist on the old decision; do NOT silently apply the user's request).
3. **Surface** — quote the entry verbatim: ``"이 작업은 <date> 결정 \"<note>\" 을(를) 뒤집습니다. 의도가 맞습니까?"``
4. **Resolve** — on user confirm, call `/vdd-log` which runs the **replace + archive** procedure (V-04): remove the old entry from frontmatter `decisions:`, move it to the page body's `## decisions archive` section with a `Replaced YYYY-MM-DD: <why>` line, append the new entry to frontmatter with today's date, AND sweep sibling body claims (`## Architectural conventions`, `## Capability boundary`, parity tables, ASCII diagrams) that state the reversed direction so the same contradiction does not survive at a different surface. Then proceed with the code change. On user rescind, keep the old decision in frontmatter and stop the conflicting change.

**Why replace + archive instead of leaving both in frontmatter:**
- `decisions:` frontmatter answers "what is true *now*" — must hold no contradictions.
- Page body archive answers "what was decided before and why we changed our mind" — preserves the V-04 reason history without polluting active SoT.
- `_decisions.md` rollup sources only frontmatter, so the rollup stays a clean chronological scan of current decisions; archived reversals stay visible *on the page* (Rule 0 reader sees both halves).
- Agent grep-landing on an old entry can't happen — there is no old entry in `decisions:`.

**Conflict trigger — explicit only.** False positives turn this into noise:
- **Same topic** — same subject named in the decision. Same layer ≠ same topic.
- **Opposite direction** — the user's intent reverses the predicate (location, owner, presence, mechanism). Refinement / extension is NOT reversal.
- **Intent match, not keyword match** — overlapping nouns whose decision-objects differ are NOT conflicts.

## Instruction Priority

1. **User explicit instructions** (AGENTS.md, direct requests, `VAULT_GATE_BYPASS=1`) — highest.
2. **Vault SoT** (`docs/vault/`) — overrides default code-first behavior.
3. **vdd-workflow + vdd-* skills** — workflow discipline.
4. **Default Codex behavior** — lowest.

## CONSTRAINTS V-XX — workflow integrity rules

**Read the CONSTRAINTS V-XX once per session** — at the first code/vault task. They are **plugin-owned and universal**: there is no `docs/vault/CONSTRAINTS.md`. The project AGENTS.md instruction injects the file's absolute plugin path into context — Read it there. Stable within a session, so do NOT re-read on later tasks in the same context window.

`V-XX` — VDD system integrity. V-01 owner-page Read before code edit, V-02 broadcast sync, V-03 code_refs integrity, V-04 decision recording, V-05 reactor decided before key, V-06 lint PASS, V-07 impact-set verdict, V-08 page bloat (decisions note ≤200 chars), V-09 contract→code drift. There is no project-specific rule prefix — a project incident that should harden behavior becomes a new V-XX upstream or a page `decisions:` entry.

Reference rule numbers in status lines when their procedure applies. `_lint.sh` Section 4c cross-checks the V-XX count ↔ check-line count in lint (plugin-internal).

## Skill catalog — 4 workflow + 2 Q&A + 4 utility

### Workflow phases (sequential)

| Skill | Phase | What it does |
|---|---|---|
| `vdd-plan` | 1 — design + decompose + contract | Mode A: spec authoring (collaborative dialogue → user-approved design written into vault page). Mode B: decompose approved design into owner_page-partitioned tasks for vdd-build. Mode C: page-first broadcast graph delta (vdd-blast.sh → _state-contract → vault-planner agent → reactor pages). |
| `vdd-build` | 2 — implementation | Dispatches `vdd-implementer` agents for the owner_page-partitioned task groups. Parallel (≥3 independent groups) or sequential. Single unified `_lint.sh` after all groups complete. |
| `vdd-review` | 3 — verification + drift audit | Mode A: fresh lint/test/build + V-06 evidence. Mode B: deterministic V-09/symbol floor + `vault-verifier` batch → CONSISTENT/NOT READY verdict. |
| `vdd-done` | 4 — close | Delegates verification to `vdd-review`, harvests session decisions to vault frontmatter (V-04, V-08), runs `_lint.sh` (V-06), optional `vault-critic`/`wiki-promoter`, suggests Conventional Commit message. |

### Q&A skills (anytime, parallel to workflow)

| Skill | Use for |
|---|---|
| `vdd-explain` | "what / where / how" lookups + existing-tool/library scans. Vault → code → external registries. Flexible (no HARD-GATE). |
| `vdd-investigate` | Debugging / unexpected behavior. "why doesn't X work" / "X is broken". Rigid HARD-GATE — vault layer page first. |

### Utility skills

| Skill | Use for |
|---|---|
| `vdd-init` | One-shot project setup: `install.sh` scaffold → `_lint.sh` → dispatches `vdd-onboarding` for layer authoring. |
| `vdd-log` | Append a single decision to a vault page's `decisions:` frontmatter NOW (vs `vdd-done` which auto-harvests at session close). |
| `vdd-map` | Render the broadcast/intent graph (`vdd-map.sh`) + read its shape. Facts only — orphan/silent findings hand to `vdd-review` for the code-checked verdict. |

### Non-user-invocable

- `vdd-onboarding` — Phase 2 of `vdd-init` (layer page authoring, brownfield reverse-extract or greenfield interview).
- `vdd-workflow` — this file (catalog + common rules).

## Agent catalog

| Agent | When to invoke | Read/Write |
|---|---|---|
| `vault-planner` | broadcast graph delta — feed `vdd-plan.sh --staged` output + change intent, receive per-page update plan | read-only |
| `vault-onboarder` | brownfield onboarding — analyzes code, drafts initial vault page content for human review | read-only |
| `vault-verifier` | verify a vault page's claims still match the actual code (drift / stale `code_refs:`) | read-only |
| `vault-critic` | vault page prose quality — filler detection, empty WHY, asymmetric cross-platform descriptions, staleness | read-only |
| `vault-suggester` | empty-section fill *hints* (angles, sources to consult) — does not draft content | read-only |
| `vdd-implementer` | **executor for plan-approved single-owner_page task groups.** Dispatched ONLY by `vdd-build`. Edits one owner page's `code_refs:` files + that page's frontmatter under scope-lock. Refuses cross-page / contract work. | write (scope-locked) |
| `wiki-querier` | domain-general patterns from `~/wiki/wiki/concepts/<topic>/` (active when `~/wiki/wiki/` exists) | read-only |
| `wiki-promoter` | reverse direction of wiki-querier — vault decisions → personal wiki candidates (auto-suggested by `vdd-done` when decisions added) | read-only |

`vdd-implementer` is the only agent with write power — scope-restricted to its assigned owner page.

### Batch parallel mode (read-only agents, ≥3 layers)

`vault-verifier` and `vault-critic` are read-only → no race / evidence concerns. When scope = whole-vault and N ≥ 3 layers, dispatch one subagent per layer in a single message (parallel). Merge N reports. Canonical orchestration lives in `vdd-review` § Mode B Step 2. Skip parallel when <3 layers, single-page targeted, or cross-layer reasoning is required.

## Workflow flow

```
┌─ one target episode ─────────────────────────────────┐
│ [vault read] → vdd-plan → vdd-build → vdd-review → vdd-done
│                                          ↘ vdd-log during
└───────────────────────────────────────────────────────┘
        ↓ /clear (fresh context — vault restores via project instruction + Rule 0)
   next target → re-enter vdd-plan (NOT inline addendum)

         vdd-explain / vdd-investigate (anytime, vault+code lookup)

         vdd-init (one-shot setup) — vdd-log (quick record)
```

### Branches by scenario

| Scenario | Path |
|---|---|
| New feature, existing layer | `vdd-plan` (Mode A → Mode B) → `vdd-build` → `vdd-review` → `vdd-done` |
| Broadcast graph change | `vdd-plan` (Mode C → Mode B) → `vdd-build` → `vdd-review` → `vdd-done`. Commit type `vault!` for breaking. |
| Debugging existing behavior | `vdd-investigate` (4-phase: vault layer page → hypothesis → code → fix + page sync) |
| Lookup / "where is X" / "is there a library for Y" | `vdd-explain` (vault → code → external) |
| Project bootstrap | `vdd-init` (4-phase: scaffold → lint → `vdd-onboarding` → next-step hint) |
| Vault quality check | dispatch `vault-critic` or `vault-verifier` directly (also called from `vdd-review` Mode B and `vdd-done`) |

## Progress reporting

**Rule:** every VDD step that operates on the vault, dispatches a skill, or invokes an agent emits **one short status line** *before* the tool call. Silent execution is a failure mode.

Each status line carries:

1. **What** — exact target (file path, agent name, skill name, command, broadcast key)
2. **Why** — reason this step is needed, in a short clause
3. **Cascade reason** (when applicable) — when one Read triggers another, name the trigger (frontmatter field, wikilink, broadcast key, hit in the previous file)

### Skill entry + phase lines (mandatory shape)

- **Entry line — `▸`** at skill activation, BEFORE the first tool call:
  `▸ <skill> entry — <what this skill will do for THIS task> (<precondition / why now>)`

- **Phase line — `  └`** at each major phase boundary (top-level `##` that does vault read, HARD-GATE, agent/implementer dispatch, verification, or handoff):
  `  └ <phase> — <what + why>`

Phase lines derive from the skill's headings (not a hardcoded list); prose-only sections get no `└`. `▸`/`└` *are* the step line at those boundaries — don't also emit a bare duplicate.

Worked example (vdd-plan, decompose mode, scope splits into 4 layers):

```
▸ vdd-plan entry — decompose mode (4 independent layer areas)
  └ vault HARD-GATE — Read auth/auth.md § Capability boundary + § Conventions before touching auth_bloc.dart
  └ Impact Analysis — vdd-impact.sh per modified file; verdict every enumerated owner + intent_refs member
  └ task decomposition → owner_page partition — group tasks by owner_page for vdd-build dispatch
  └ self-review — compare the task set back to the approved design for coverage gaps
```

### Step examples (weak → strong)

The pattern: weak = bare action; strong = `<tool/target> — <task-specific why + cascade trigger>`.

| Weak (avoid) | Strong (apply) |
|---|---|
| `Reading auth/auth.md` | `read_note "auth/auth" — § Capability boundary + § Conventions (touching auth_bloc.dart)` |
| `Reading auth/_state-contract.md` | `read_note "auth/_state-contract" — auth/auth.md reacts_to: native:reconnect → trace origin` (cascade cited) |
| `Invoking vault-verifier` | `vault-verifier — is code_refs (auth_bloc.dart#login) in auth/auth.md stale after rename?` |
| `Running _lint.sh` | `vdd lint — frontmatter/wikilinks/code_refs; expecting 0/0` |

### Format

- **One line, before the tool call** — intent before result; if it won't fit one sentence the *why* is too vague.
- **Explicit names + task-specific why** — `auth/auth.md` not "the layer page"; "check conventions BEFORE editing auth_bloc.dart login" not "to check conventions". Cite cascade triggers (which `reacts_to:` / wikilink pulled the next Read).
- **Don't narrate non-VDD work** — generic Reads, ordinary code Edits, routine Bash output get no step line.

### Skip conditions

- **Tightly chained Reads** — reading 2–3 vault pages in immediate succession for one purpose can collapse into one combined line, but the cascade reason MUST appear.
- **Repeated Read of the same page in one turn** — second Read doesn't need a new line.
- **Hard-gate refusals** — refusal message IS the status; no separate line.

## Obsidian MCP — default vault read tool when available

**Detection:** if `mcp__*obsidian*__*` is in the tool list → **MCP-default mode** (vault reads route to MCP first; filesystem fallback for what MCP can't do). Absent → filesystem unconditionally.

**Root sanity-check:** a relative-path `obsidian-vault` resolves against the MCP server's spawn CWD, not your project. Probe `read_note "index"` once — if "File not found" / empty / wrong project, treat as absent and fall back. Don't retry.

**HARD RULE — MCP is not optional when present.** Ignoring an available MCP server for `Read` / `Grep` / `Bash cat` on vault content is a discipline violation: its 14 tools (search_notes / read_note / read_multiple_notes / get_frontmatter / ...) are strictly more capable — BM25, batched reads, frontmatter-aware parsing.

**Plugin-side:** VDD has no Obsidian dependency; `install.sh` registers no MCP server — registration is the user's call.

### Instance naming convention (required for routing)

| Required name | Scope | Indexes | Registration |
|---|---|---|---|
| `obsidian-wiki` | user (shared) | `~/wiki/wiki/` | `claude mcp add -s user obsidian-wiki -- npx -y @bitbonsai/mcpvault@latest "$HOME/wiki/wiki"` |
| `obsidian-vault` | per-project (absolute path) | this project's `docs/vault/` | from project root: `claude mcp add -s local obsidian-vault -- npx -y @bitbonsai/mcpvault@latest "$(pwd)/docs/vault"` |

Routing matches the `*vault*` and `*wiki*` suffix. Do NOT register `obsidian-vault` at user scope with relative `./docs/vault` — silently resolves wrong. A broken instance is worse than none.

### Per-operation routing (MCP-default mode)

| Operation | Default | Fallback |
|---|---|---|
| Read one vault page | `mcp__obsidian-vault__read_note` | `Read` |
| Read multiple in one shot | `mcp__obsidian-vault__read_multiple_notes` | sequential `Read` |
| List a vault directory | `mcp__obsidian-vault__list_directory` | `Bash ls` |
| Keyword search across vault (find which page) | `mcp__obsidian-vault__search_notes` (BM25) | `grep -rliF "<kw>" <vault>/` (`-l` = filenames only, cheap) |
| Pull a section/keyword from a *known* large page | `mcp__obsidian-vault__search_notes "<kw>"` (ranked snippet) OR `Read` w/ `offset`/`limit` | `grep -n` with a **narrow** pattern + `head` — NEVER a broad `A\|B\|C…` alternation on a big page (dumps full prose lines, ~5K tok/call) |
| Page frontmatter inspection | `mcp__obsidian-vault__get_frontmatter` | YAML parse from `Read` |
| Find pages with specific frontmatter value (global) | (not exposed) | `awk` over frontmatter blocks |
| Find backlinks of a page | (not exposed) | `grep -rln "\[\[<name>\]\]" <vault>/` |
| Graph traversal (transitive reactor chain) | (not exposed) | `vdd-blast.sh` + `_reverse-index.md` |
| **Edit vault page body** | **`Edit` / `MultiEdit` (preferred) OR `mcp__obsidian-vault__patch_note` (byte-level)** | `Edit` / `MultiEdit` |
| **Edit vault page frontmatter** | **`Edit` only — NEVER `update_frontmatter` / `write_note --frontmatter` / `manage_tags`** | `Edit` only |
| **Delete / move vault page** | **`Bash mv` / `Bash rm` + wikilink update + `_lint.sh`** — never `delete_note` / `move_note` | same |

**MCP write tools are NOT defaults.** Only `patch_note` is permitted (byte-level, frontmatter-safe). All other write tools YAML-re-serialize frontmatter and break `_lint.sh` (broadcast keys gain quotes, flow→block style, dates normalize). Live test against `@bitbonsai/mcpvault` (May 2026) confirmed every YAML-routing tool mutates frontmatter — see `scaffold/AGENTS.md` § Optional Obsidian MCP for evidence.

**Policy:**
- MCP-default applies only to *vault content reads*. Non-vault files (project source, configs, README, package.json) use `Read` normally.
- Instance routing is non-negotiable — using `mcp__*wiki*__*` for vault (or vice versa) returns wrong results silently.
- Deterministic CLI scripts remain SoT for their domain: `vdd-blast.sh` (forward, key → reactors), `vdd-impact.sh` (reverse, code file → owning pages), `vdd-plan.sh` (contract delta), `_lint.sh` (validation). MCP never replaces these.

## Commit rules

### Conventional Commits

| type | use |
|---|---|
| feat | new feature |
| fix | bug fix |
| refactor | code improvement without behavior change |
| docs | documentation change |
| test | test add/modify |
| chore | build, config, misc |
| **vault** | **vault page / frontmatter only (no code change)** |
| **vault!** | **vault contract breaking — broadcast key removed/renamed (cross-layer impact)** |

- type/scope in English; description body follows your team's language convention.
- No `Co-Authored-By:` lines for Claude / Anthropic / AI assistant.
- No traces of Codex / AI / LLM tool use in commit messages.
- Run `git commit` / `git push` only when the user explicitly asks.
- For broadcast graph changes, include a `vdd-plan.sh` output summary (affected pages list) in the commit body.

## Workflow state tracking

- Implementation follows the **most recently approved plan** (`vdd-plan` Mode B Target / Scope / Verification).
- Verification compares **implementation result** vs **plan conditions** (in `vdd-review`).
- `vdd-done` aggregates **completion targets across the whole conversation**, updates the vault `decisions:` frontmatter, and runs `vdd lint`.

## Natural language mapping

| User phrasing (examples — multi-language triggers live in each skill's `description:`) | Skill / agent |
|---|---|
| "add X feature" / "build Y" / "implement Z" / "plan how to implement this" / "outline an approach" | `vdd-plan` (Mode A — spec) |
| "implement it" / "build it" / "now make it" / "parallel implementation" | `vdd-build` |
| "change broadcasts" / "add X state" / "page-first" / "blast radius" / "cross-layer impact" | `vdd-plan` (Mode C — contract) |
| "why doesn't X work" / "X is broken" / "looks like a bug" / "find the bug" | `vdd-investigate` |
| "where is X" / "how does X work" / "what does X do" / "explain X" | `vdd-explain` |
| "is there a library for X" / "anything similar" / "search before building" | `vdd-explain` (existing-solution scan flavor) |
| "verify" / "all green?" / "is the vault consistent with code?" / "vault drift check" | `vdd-review` |
| "wrap up" / "we're done" / "finish this" / "commit" | `vdd-done` |
| "log this decision" / "record this pending item" | `vdd-log` |
| "set up VDD on this project" / "VDD from day one" / "/vdd-init" | `vdd-init` |
| "verify vault page claims match code" | `vault-verifier` agent |
| "vault prose quality check" | `vault-critic` agent |
| "what should I write in this empty section?" | `vault-suggester` agent |
| "what layers own this code file?" | `vdd impact <code-file>` |
| "show the broadcast/signal map" / "draw the vault as a graph" / "silent layers?" / "orphan keys?" | `vdd-map` skill (wraps `vdd-map.sh` — collapsed default, `--raw` key-level, `--orphans` audit, `--layer <n>`; renders facts, hands consistency verdict to `vdd-review`) |
| "draft initial vault pages from existing code" | `vault-onboarder` agent (via `vdd-onboarding`, dispatched from `vdd-init`) |

## Core principles

1. **No code changes without an approved plan** — implementation follows `vdd-plan` Mode B (or Mode C for contracts).
2. **Vault is SoT** — narrative / intent / decisions live in vault pages; code + vault changes ship in the same PR.
3. **Touch only the allowed scope** — never violate the plan's Scope.Forbidden.
4. **On failure, stop and report** — no speculative fixes; surface the failure and let the user decide.
5. **The user decides** — when uncertain, present options and wait.
6. **Keep commits clean** — Conventional Commits; broadcast graph changes use `vault!`.
7. **No AI footers in commits** — no `Co-Authored-By: Claude / Anthropic / AI assistant`, no Codex / LLM tool traces.
8. **Report each VDD step in one line** — see § Progress reporting above.
9. **Grasp by zoom traversal, evaluate conditions** — vault read is not a flat top-down dump; locate the relevant node and zoom both ways, surfacing decisions WITH their conditions to *evaluate* (not consume). See § Vault zoom traversal below.
10. **One target = one context episode.** After a target closes (`vdd-done`), `/clear` before the next one. Fresh context per target removes the momentum that makes the model treat a new request as an inline addendum to finished work — the most common cause of skipping `vdd-plan`. The vault is the SoT, so the next task restores grasp via project instruction inject + Rule 0; nothing is lost. Keep continuity *within* a target (no mid-target `/clear`); reset *between* targets. See `vdd-done` § Context boundary.

## Vault zoom traversal (grasp-assembly)

Cross-skill convention used by `vdd-plan` (step 2), `vdd-investigate`, `vdd-explain` — anywhere a task reads the vault to act. Replaces flat top-down reading. Uses the existing `zoom` / `parent` / `children` / broadcast-graph frontmatter; adds no new structure.

On a work instruction:
1. **Locate** the node the task touches (relevant `<layer>.md` or feature page) — start there, not always at `index`.
2. **Zoom-out** — `parent` → layer page (§ Capability boundary / Architectural conventions) → `broadcasts` / `reacts_to` / `intent_refs` (cross-layer constraints this task collides with) → `index` (system position).
3. **Zoom-in** — `children` → § decisions → `code_refs` → code.
4. **Evaluate, don't consume** — each decision is read WITH its condition (V-11 format: "<decision>; holds while <condition>"). Ask *"does the condition still hold for this task?"* A conditionless conclusion read as a verdict is the formulaic-wrong-answer failure mode; the condition forces re-evaluation.
5. **Surface, don't decide** — output the constraints found (decisions+conditions, contracts, intent_refs) for the user to confirm/correct. Grasp-assembly ≠ direction-commit. The direction is confirmed *against the surfaced conditions* (`vdd-plan` step 11), never decided silently from a confident zoom.

**Why**: grasp comes from active traversal + condition-evaluation, not from re-reading more prose. The model cannot self-assess that its grasp is *correct* — so the committed direction must be confirmed against the surfaced conditions, not trusted from the navigation alone.
