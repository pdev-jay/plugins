---
name: vdd-plan
description: |
  Enters whenever there's any signal of code change or design intent — starts a spec dialogue to clarify even when intent is vague. Covers new feature / state / broadcast additions; refactor ("손보자/개선하자/통일하자/리팩토링/뜯어고치자" / "let's clean up/refactor/unify/rework/overhaul"); change impact analysis ("어디까지 영향/파급력/cross-layer 변경/여러 layer 영향" / "blast radius/impact scope/cross-layer change/multi-layer impact"); vague expressions ("신경 쓰여/그렇지 않아/맞나/어떻게 처리하지" / "feels off/doesn't feel right/is this right/how should we handle"). Explicit bug signals ("안 돼/이상해" / "doesn't work/is broken/looks wrong") → vdd-investigate; lookup on existing behavior ("어디 있어/뭐 함/어떻게 돌아가더라" / "where is/what does X do/how does X work") → vdd-explain; wrap-up intent ("정리하고 가자/마무리" / "let's wrap up/call it a day") → vdd-done. Impact analysis belongs to vdd-plan because Contract mode runs vdd-blast.sh + the vault-planner agent to compute the actual blast graph (vdd-explain only cites). Phase 1 of plan → build → review → done.
---

# vdd-plan — design + decompose + contract delta

**Announce on entry:** `▸ vdd-plan entry — <mode-name> mode (<why-now>)` — e.g. `spec mode (no design yet for chat feature)`, `decompose mode (4 layer areas)`, `contract mode (adding auth:reconnecting key)`.

## Mode detection (decide at entry)

```
user request
   │
   ▼
broadcast graph touched? (broadcasts/reacts_to/emits_to change,
new state-contract entry, cross-layer state ripple)
   │
   ├── YES ──► Mode C: Contract  (page-first, vdd-blast.sh required)
   │
   └── NO ──► design already approved this session?
                  │
                  ├── YES ──► Mode B: Decompose  (build owner_page-partitioned tasks)
                  │
                  └── NO  ──► Mode A: Spec       (collaborative design dialogue)
```

A single user turn can traverse multiple modes (Spec → Decompose, Contract → Decompose). Detect at entry, re-detect when the artifact transitions.

## Common HARD-GATE — vault read first

Before producing any output in any mode:

1. **CONSTRAINTS V-XX** — plugin-owned; path injected at project instruction (no `docs/vault/CONSTRAINTS.md`). The V-XX rules applicable to this task.
2. `docs/vault/index.md` — layer map.
3. Target layer `<layer>/<layer>.md` — § Capability boundary, § Architectural conventions, § decisions.
4. **Cross-layer / contract work**: `<layer>/_state-contract.md` — broadcasts / reacts_to / emits_to.

Read tool: `mcp__obsidian-vault__read_note` when present, else `Read`. Skipping the layer page Read is a skill violation — the skill REFUSES to emit a design / task set / contract delta until the page has been Read in this session.

Re-checking one keyword on an already-read large page (the multi-step modes do this often)? Use `mcp__obsidian-vault__search_notes` or `Read` + `offset` — not a broad `grep -n "A\|B\|C"` on the file (dumps full prose, ~5K tok/call).

**Bypass** — only with explicit user opt-out: "ignore vault" / "fresh approach" / `VAULT_GATE_BYPASS=1`.

## Common: Impact Analysis (V-07)

For every code file the work will *modify* (not create), run **`vdd impact <code-file>`** once. State the output inline. Give *every* enumerated member (owning pages + `intent_refs` closure) a one-line verdict:

- `affected` — change touches it; state what changes.
- `unaffected` — in the set but the change doesn't reach it; state why.
- `deferred` — handled separately; link issue / PR.

A member with no verdict is a silent coverage gap, not implicit pass (CONSTRAINTS V-07).

For broadcast graph changes, additionally run `vdd blast <key>` (forward: key → reactors) and `vdd plan --staged` (contract delta) — apply the same per-member verdict.

---

## Mode A — Spec (design undefined)

Evolve a new-feature idea into a complete, vault-grounded, user-approved design.

### Anti-pattern: "too simple to need a design"

Every change goes through this — todo lists, single-function utilities, config tweaks. The design may be a few sentences for trivial work, but it must be presented and approved.

### Checklist (in order)

0. **Self-disambiguation gate** (vague entry only) — when the prompt that triggered Spec mode lacks explicit new-feature / state-addition / broadcast-change content and entered via aggressive catch (refactor cues, impact cues, "신경 쓰여/feels off/맞나/is this right" type vague expressions), surface the interpretation FIRST and offer reroute before the heavy lifting:

   > "Reading this as Spec-mode design dialogue on **\<one-line interpretation>**. If you actually meant:
   > - **debug existing behavior** → say so, I'll switch to vdd-investigate
   > - **lookup existing code/structure** → vdd-explain
   > - **wrap up & commit current work** → vdd-done
   > - **record a single decision only** → vdd-log
   >
   > Otherwise I'll proceed with the design conversation."

   Use `AskUserQuestion` with the four reroute options when the prompt is genuinely ambiguous (three or more skills plausible). For two-way ambiguity, a single inline confirmation question is enough.

   **Skip this step** when: user prompt contains explicit feature/state/broadcast trigger words ("X 추가/add X/new state Y"); user already confirmed design intent earlier in this session; the prompt names a concrete artifact to design.

1. **Intent capture FIRST** — explicitly capture user requirements / constraints / preferences *before* reading vault.
   - Intent unclear → ask the user (multiple-choice when possible, one question per message).
   - Vault does not override intent. On vault ↔ intent conflict, surface it; user decides.
   - Override keywords skip vault read entirely.

2. **Vault zoom traversal** (Common HARD-GATE above) + project `AGENTS.md` — not a flat top-down read. Locate the node the task touches, zoom-out (`parent`/layer/`broadcasts`/`reacts_to`/`intent_refs`) and zoom-in (`children`/decisions/`code_refs`), reading each decision WITH its condition and *evaluating* whether it still holds (do not consume conclusions as verdicts). See `vdd-workflow` § Vault zoom traversal. **Record the evaluation as the Grasp note (§ Grasp note below) and run `grasp-gate.sh`** — this turns "did I look?" from an unverifiable claim into a checked artifact.

3. **Wiki context (optional)** — if `~/wiki/wiki/` exists, invoke `wiki-querier` agent for domain-general patterns. Fold returned trade-offs into the design.

4. **Scope check** — multi-subsystem request → propose split into sub-projects, each with its own plan cycle.

5. **Existing solution scan** — before locking tool / library choices, search:
   - vault → project grep → MCP → npm/pub/maven → GitHub → web.
   - Reuse beats invention. Surface candidates with one-line trade-offs. (Absorbed from former vdd-search.)
   - Decision matrix: Adopt (exact match, well-maintained) / Extend (partial, thin wrapper) / Compose (combine small packages) / Build (nothing fits).

6. **Present 2–3 approaches** with trade-offs. Lead with the recommendation.

7. **Impact Analysis** (Common above) — state all 5 items (Callers / Related layers / Cross-platform symmetry / Lifecycle / State transitions) with per-member verdicts.

8. **V-05 gate** — any new `broadcasts:` key MUST have at least one declared reactor (or `TBD — see <issue>`). Surface and wait if unresolved.

9. **Present the design** — sections sized to complexity. After each section, confirm before moving on. The design lives in the conversation, NOT in a separate `docs/specs/` file — the vault page IS the spec.

10. **Self-review** — placeholder scan / internal consistency / scope / ambiguity.

11. **User approves the design** (HARD-GATE) — confirm *against the Grasp note's verdicts* (step 2), not a bare y/n. Surface the falsifiable bases so a lazy approval is impossible — the human is reading verdicts to *spot a wrong one*, not clicking yes:
    > "Grasp verdicts this direction rests on: D[2026-05-21] BROKEN (task tracks 3 tags → revising to multi-connection); D[2026-05-18] HOLDS (quality untouched). Confirm these verdicts, or correct any that are wrong, and I'll write it into the vault and decompose. A BROKEN verdict = a decision to revise."

12. **Write the design into the vault page**:
    - Target page exists → update body (§ Capability boundary, § Architectural conventions, § Why this is the boundary, § What is NOT here) + frontmatter.
    - No page yet → `vdd bootstrap --write <layer>` to scaffold, then fill.
    - Frontmatter: `decisions:` (rationale + rejected alternatives, ≤200 chars, V-08), `tasks:` (deferred follow-ups), `code_refs:` (anchors), bump `updated:`.
    - Run `vdd lint` → exit 0.

13. **Transition to Mode B (Decompose)** — continue in the same skill turn.

### Grasp note (step 2 artifact — forces the zoom into a checkable form)

The zoom traversal's output is a **Grasp note**: in-conversation (not a persisted file — its durable residue is the `decisions:` updates it triggers). It converts the un-verifiable "did the model grasp the intent?" into a structurally-gated artifact.

**Ordering is the whole point — evaluation first, direction last.** Do NOT write "I proceed direction X because <reasons>" (post-hoc justification → confabulation, no teeth). Write each touched decision's verdict *independently*, then let the direction *follow* from the verdicts:

```
## Grasp — <task one-liner>

Touched: <layer/page>[, <page>…]            ← zoom entry + out

Decisions evaluated (EVERY decision on touched pages):
- [2026-05-21] single global BLE connection — holds while: one tag at a time
    verdict: BROKEN — task tracks 3 tags → this decision must be revised, not applied
- [2026-05-18] quality feeds σ — holds while: quality = (uint8_t)(-rssi)
    verdict: HOLDS — task doesn't touch quality semantics

Direction: <follows from the verdicts>; depends on / changes: revise D[2026-05-21]
```

Rules:
- **Every** decision on the touched pages gets a line: condition restated + `verdict: {HOLDS | BROKEN | N-A}` + one-line basis. An omitted decision = one you didn't evaluate.
- Each basis must be **falsifiable against the task** ("BROKEN — task tracks 3 tags") — a one-line basis a human can spot-check, not a holistic rationalization.
- Run `vdd grasp-gate <note> <touched-page>…` → it deterministically flags any decision date with no verdict line (catches "didn't look"). Exit 0 before presenting the design.

**What it does / doesn't do**: the gate proves you *addressed* every decision (structural floor, deterministic) — same shape as `coverage-gate`. It does NOT prove your verdict is *correct* (confabulation is possible; a wrong "HOLDS" passes the gate). Correctness is caught at step 11's condition-based confirm, where the human reads the falsifiable bases. Under-declared touched pages evade the gate (declare honestly; review cross-checks the diff's actual `code_refs`).

### Spec-mode flow

```
intent → vault ZOOM (relevant node, out+in) → Grasp note: verdict EACH decision → grasp-gate
   → wiki (optional) → scope check → existing-solution scan → 2–3 approaches
   → Impact Analysis (V-07) → V-05 gate → present design (direction FOLLOWS the verdicts)
   → self-review → user APPROVAL (confirm verdicts, not y/n) ──► write into vault page ──► Mode B
```

---

## Mode B — Decompose (design approved)

Break the approved design into bite-sized, owner_page-partitioned tasks for `vdd-build` to dispatch.

### The plan is ephemeral

The plan lives as:
- **`Codex task list` tasks** — one per bite-sized unit; description carries file list, steps, `done-when`. Live execution state.
- **Vault page `tasks:` frontmatter** — durable follow-ups (deferred work, known gaps). `_lint.sh` rolls these into `_open-issues.md`.
- **The conversation** — Impact Analysis, ASCII diagram, architecture summary.

**No `docs/plans/*.md` file.** A committed plan competes with vault as SoT and rots. Vault page = durable record; `Codex task list` = live state.

### File structure mapping

Before tasks, map each file → which vault page's `code_refs:` it belongs to. Decomposition decisions lock in here.

- One responsibility per file. Well-defined interfaces.
- Follow existing patterns in established codebases.
- Small focused files reason better in context.

### Bite-sized task units

Each step is one action (2–5 minutes): write failing test → run → minimal code → run → commit. **Task count ≤ 10 recommended** — combine when logically inseparable, split only when work needs different attention.

### Plan summary (inline, not committed)

```
Plan: [Feature Name]

Goal:        [one sentence — what this builds]
Architecture: [2–3 sentences — the approach]
Tech stack:  [key technologies / libraries]
Vault pages: [docs/vault/<layer>/<file>.md — authored | updated | read-only]
Task count:  [N tasks, ≤10 recommended]
```

This is the conversational artifact the user approves before tasks are created.

### Iterative refinement (M/L tier, ≤2 iterations)

```
Draft 1 → self-diagnose → confident?
                  │
            ┌─────┴─────┐
            no          yes
            │            │
        refine ≤2     proceed
            │
   ┌────────┼────────┐
   │        │        │
 user Q  re-search  extra grep
```

**Confidence break conditions:**
- [ ] every task has stated `done-when:`
- [ ] risks ≥1 with mitigation
- [ ] alternatives ≥2 (chosen + rejection reason)
- [ ] scenarios ≥3 (golden + edge + failure)
- [ ] Impact Analysis 5 items filled, every V-07 member has verdict
- [ ] ASCII diagram ≥1 (M/L tier)
- [ ] every task names its vault page

**user Q vs re-search**: domain ambiguous → user Q; code unclear → re-search; both → re-search first. Cap > 2 → escalate to user.

### ASCII diagram (M/L tier mandatory)

Flow / Layer / State pattern. Box-drawing chars only. No Mermaid / dot / svg.

### Task structure

````
[Component Name]

owner_page: docs/vault/<layer>/<page>.md
Vault page: <same as owner_page> (author | update | read-only)

Files (must all be in owner_page's code_refs after this task completes):
- Create: exact/path/to/file.ext
- Modify: exact/path/to/existing.ext:123-145
- Test:   tests/exact/path/to/test.ext

Done when: [observable, verifiable condition]

Step 1: Write the failing test
  <actual test code>
Step 2: Run test to verify it fails (exit 1, message X)
Step 3: Write minimal implementation
  <actual code>
Step 4: Run test to verify pass
Step 5: Update vault page (code_refs / decisions / updated)
Step 6: Commit  (Conventional Commit)
````

Use `TaskUpdate addBlockedBy` between tasks that must run sequentially; independent tasks stay unblocked.

**Durable follow-ups** (deferred, not part of this set) → vault page's `tasks:` frontmatter, not `Codex task list`.

### No placeholders

Task failures: "TBD" / "TODO" / "implement later" / "add appropriate error handling" / "similar to Task N" / "write tests for the above" without actual code / references to undefined types.

### Owner_page partition (vdd-build readiness)

Every task names an `owner_page`. Group tasks by `owner_page`. For each group, verify all `Files:` belong to that owner's `code_refs:`. Cross-page tasks (Files spanning two owner_pages) → split at plan time, or mark inline (main-LLM, not vdd-build). Every other group is dispatched to `vdd-build`.

This partition discipline is non-optional — `vdd-build` requires it.

### Self-review (no agent)

After full task set:

1. **Design coverage** — every part of the approved design maps to a task.
2. **Placeholder scan** — fix inline.
3. **Type consistency** — names/signatures match across tasks.
4. **Impact Analysis** — all 5 items + V-07 verdicts.
5. **Vault mapping** — every task names a page; every page needing update has a task.
6. **Owner_page partition** — every task has `owner_page`; cross-page splits made.

Fix inline. No second review.

### Handoff

> "Task set created (`TaskList` to view). Invoke `vdd-build` to dispatch implementer agents."

`vdd-build` owns the dispatch logic (parallel vs sequential, scope-lock, evidence pre-deposit). This skill stops at the partitioned task set.

---

## Mode C — Contract (broadcast graph change)

Page-first workflow for changes that touch `broadcasts:` / `reacts_to:` / `emits_to:` or ripple across multiple vault layers.

### Workflow

```
1. SCOPE
   identify target layer; check vault page exists
2. PAGE BOOTSTRAP (no code yet)
   vdd bootstrap
   frontmatter: zoom / parent / children / status
3. INTENT FIRST  (before vault read)
   capture user requirements
   THEN read § Capability boundary, § Why, § What is NOT here,
   § End-to-end flow, broadcasts/reacts_to/emits_to frontmatter
   intent ↔ vault conflict → user decides
4. WIKI CONTEXT (optional)
   wiki-querier agent for domain-general patterns
5. FORWARD BLAST (before editing _state-contract.md)
   vdd blast <key>
   → existing reactors for affected keys (Rigid; required by V-02)
6. CONTRACT DELTA
   update broadcasts/reacts_to/emits_to in _state-contract.md
   vdd plan --staged
   → contract delta + per-page TODO template
7. VAULT-PLANNER AGENT
   dispatch with vdd-plan.sh output + change intent
   → per-page prose update plan
8. APPLY page updates → vdd lint  (exit 0)
9. TRANSITION to Mode B (Decompose) — implement the code
```

### Wikilink discipline (Hard Rule 3)

Every `_state-contract.md` lives inside a specific layer folder; basename collision is intentional. References MUST be full path: `[[<layer>/_state-contract]]` (e.g. `[[auth/_state-contract]]`). Bare `[[_state-contract]]` is ambiguous → ERR.

### Impact coverage (per-member verdict)

Three deterministic sources:
- `vdd-impact.sh <code-file>` — owning pages + `intent_refs` closure.
- `vdd-blast.sh <key>` — direct reactors + indirect emitters.
- `vdd-plan.sh --staged` — contract-delta affected pages.

Paste the enumerated output; give *every* member a one-line verdict (`affected` / `unaffected` / `deferred`). Coverage = every member verdicted. V-07.

### Commit type

For breaking contract changes (key removed/renamed): `vault!(<layer>): <summary> (BREAKING contract)`.

---

## Cross-mode handoff

```
Mode A (Spec)
   ↓ user approves design
Mode B (Decompose)
   ↓ task set created
vdd-build  (separate skill — dispatches vdd-implementer agents)
   ↓ all groups complete
vdd-review (verify + analyze)
   ↓ READY
vdd-done   (harvest + commit)

Mode C (Contract)
   ↓ contract delta applied + lint 0/0
Mode B (Decompose) — implement the code
   ↓
vdd-build → vdd-review → vdd-done
```

Mode A and Mode C both transition into Mode B in the same skill turn — re-detect mode at the transition.

## Anti-patterns

- ❌ Writing code without an approved design (Mode A bypass).
- ❌ Editing `_state-contract.md` without `vdd-blast.sh` (Mode C V-02 violation).
- ❌ Letting subagents edit pages (`vault-planner` reports, human applies).
- ❌ Force-filling WHY in trivial pages (padding trap).
- ❌ Tasks without `owner_page` (vdd-build dispatch fails).
- ❌ Impact-set member without verdict (V-07).
- ❌ `docs/specs/*.md` or `docs/plans/*.md` files (vault IS the spec; `Codex task list` IS the plan).

## Core principles

1. **Intent first** — user intent before vault. Vault is an option catalog; user is the decider.
2. **Page first** — fix the vault page's intent/boundary/contract before code (Mode A, C).
3. **No code without approved plan** — terminal artifact (design / task set / contract delta) needs user approval first.
4. **One owner_page per task** — required by `vdd-build` partition.
5. **Vault narrative + code in same PR** — drift blocker.
6. **Subagents do not modify pages** — read-only; human applies.
7. **Reject padding** — trivial pages stay 5–15 lines.

## Companion agents

| Agent | When |
|---|---|
| `wiki-querier` | Mode A step 3, Mode C step 4 — `~/wiki/wiki/concepts/` patterns |
| `vault-suggester` | Mode A step 12 (new page) — empty-section fill hints |
| `vault-planner` | Mode C step 7 — per-page prose update plan from contract delta |
| `vault-critic` | After Mode A page write — quality check (filler / WHY / NOT-here) |
| `vault-verifier` | Mode A or C — claim ↔ code consistency on existing pages |

`vdd-implementer` dispatch is owned by **`vdd-build`**, not this skill.
