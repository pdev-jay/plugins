---
name: vdd-build
description: |
  Dispatches the approved vdd-plan task set to implementer agents per owner_page. GO signals in either language: "구현해줘/만들자/짜줘/진행해/실행해/이제 가자/돌리자/시작해/작업 시작/병렬 실행/동시 진행" / "build it/implement it/write the code/let's go/start working/kick it off/run it/parallel run/parallel implement". If no approved task set exists, routes to vdd-plan. This is the sole chokepoint for code edits from a change request — the main LLM does not Edit code directly from a bare request. Phase 2 of plan → build → review → done. HARD-GATE in body.
---

# vdd-build — dispatch vdd-implementer agents

**Announce on entry:** `▸ vdd-build entry — dispatch implementer agents for <N> owner_page group(s) (<parallel | sequential>)`.

## Codex adapter policy

In Codex, `vdd-implementer` is not an automatically registered custom agent type. Treat `role-prompts/vdd-implementer.md` as the worker role prompt.

Default execution is main-agent, owner-page-by-owner-page implementation. Use Codex workers only when:

1. The user explicitly asks for parallel/delegated work, or project `AGENTS.md` contains `VDD Parallel Worker Opt-In`.
2. The task set is partitioned by `owner_page`.
3. Each worker gets exactly one owner page and a disjoint file/write scope.
4. `vdd schedule <owner_page>...` has been run for multi-page work.
5. The main Codex agent reviews and integrates the worker result before claiming completion.

When worker mode is not allowed or the partition is unsafe, run the same procedure sequentially in the main Codex session.

## What this skill is

The execution phase of the workflow. `vdd-plan` produced an `owner_page`-partitioned task set; this skill runs it.

The dispatcher (main LLM) **does not implement inline**. It hands every plan-approved single-owner_page group to `vdd-implementer`, which is scope-locked to that page's `code_refs:` files + the page's frontmatter.

**This skill is the sole door from a change request to a code `Edit`.** A bare "fix this / change that / 수정해줘" with no approved `vdd-plan` does NOT get edited inline — it fails the precondition below and routes to `vdd-plan` first. (The other door is `vdd-investigate` for debugging existing behavior. Bug → investigate; change → plan → build.) There is no path where the main LLM edits code straight from a bare request **on its own judgment** — the only bypass is the user's explicit authorization ("그냥 고쳐" / `ignore vault` / `VAULT_GATE_BYPASS=1`); the model never self-grants a "trivial → inline" exception. The "inline groups" mentioned later mean *main-LLM instead of a subagent* for a cross-page/contract group **within** an approved build — not "skip the workflow".

**Why a separate skill?** Implementation is a distinct trigger ("implement it" / "build it") from planning ("how should we build X"). Splitting the dispatch logic out of `vdd-plan` keeps both shorter and makes the trigger surface for the build phase unambiguous.

## Preconditions (verified at entry)

```
1. TaskList — at least one Codex task list task exists
2. Every task carries owner_page (from vdd-plan decompose mode)
3. Every task's Files: are subsumed by its owner_page's code_refs (or will be)
4. The most recent vdd-plan run was approved by the user
```

If any precondition fails → refuse to dispatch. Output:

```
vdd-build cannot dispatch:
  - <which precondition failed>
  - <how to fix: run vdd-plan first / add owner_page to tasks / get user approval>
```

## Two decisions, decoupled

### Decision 1 — Dispatch to vdd-implementer? (the ①–④ gate)

YES when the group is:
1. **Fully specified** — concrete plan steps, not exploratory probing.
2. **Single owner_page** — every `Files:` entry belongs to one owner page's `code_refs:`.
3. **Plan-approved** — from an approved `vdd-plan` task set.
4. **Non-interactive** — no mid-implementation user back-and-forth expected.

NO → main-LLM inline. Only two cases land here:

- **Cross-page task** (violates 2) — files span two owner_pages. Either split at plan time, or run that one task inline.
- **`_state-contract.md` / broadcast-graph change** — `vdd-plan` Mode C's domain; `vdd-implementer` refuses by design.

Exploratory / interactive work never reaches this skill (that is `vdd-investigate` or interactive coding, outside `vdd-plan`'s scope). Within `vdd-build` the gate reduces at runtime to "single owner_page AND not a contract change".

### Decision 2 — Parallel or sequential? (computed, not eyeballed)

Do **not** judge "independent groups" by eye. Run the deterministic scheduler over the `implementer` group's owner_pages:

```bash
vdd schedule <owner_page> <owner_page> ...
```

It reads the broadcast graph (`broadcasts` / `reacts_to` / `emits_to` / `intent_refs`) restricted to that page set, derives precedence edges (**broadcaster before reactor/emitter; intent source before dependent**), and topologically layers the set into **parallel-safe batches** (Kahn's algorithm). It emits a machine block:

```
SCHEDULE_BATCH 1 <page> <page> ...
SCHEDULE_BATCH 2 <page> ...
```

Dispatch rule, derived from the schedule:

- **Per batch** — pages in the same `SCHEDULE_BATCH` share no in-set contract edge → dispatch them **concurrently**. A **barrier** sits between batches: batch *k+1* starts only after every instance in batch *k* returns (batch *k* may produce the contract a batch *k+1* page reacts to).
- **Parallel form (Phase 3)** applies when a batch has **width ≥3** → single-message N-Task dispatch for that batch.
- **Sequential form** when a batch has width 1 or 2 → dispatch `vdd-implementer` one at a time. Below 3 the *parallelism* stops paying off (dispatch overhead > wall-clock savings), but the implementer dispatch itself still applies: scope-lock, model isolation (`vdd-implementer` = sonnet), main-transcript hygiene. **NOT main-LLM inline.**
- **`SCHEDULE_CYCLE` line present** (exit 3) — a contract loop among the owner_pages; the set cannot be ordered. Do **not** dispatch. Route the loop to `vdd-plan` Mode C (break or co-edit the contract) first, then re-schedule.

The scheduler also lists **external dependencies** — keys an in-set page reacts to that no in-set page broadcasts. Those are assumed already settled (prior contract / earlier branch); they are not a batch barrier.

## Dispatch procedure

### Step 1 — Partition

Group tasks by `owner_page` → `{owner_page → tasks[]}`. Apply the ①–④ gate per group:

- Cross-page / contract → `inline` (main-LLM, NOT vdd-implementer).
- Otherwise → `implementer`.

Then run `vdd-schedule.sh` over the `implementer` owner_pages (Decision 2) → ordered `SCHEDULE_BATCH` list. Each batch is the unit of dispatch; width ≥3 → parallel, else sequential. A `SCHEDULE_CYCLE` line means stop and route the loop to `vdd-plan` Mode C.

### Step 2 — Evidence pre-deposit (uses R2 transcript inheritance)

For *every* `implementer` group (parallel-eligible or sequential):

```bash
# For each code file in the owner page's code_refs that the tasks will modify:
vdd impact <code-file>
```

```
# And Read the owner page itself
mcp__obsidian-vault__read_note "<layer>/<page>"   # or Read fallback
```

These calls land in the **parent transcript**. In Codex, do not assume worker transcript inheritance is identical to Claude Task inheritance; include the relevant evidence explicitly in each worker prompt when delegating.

### Step 3 — Dispatch (batch by batch, in `SCHEDULE_BATCH` order)

Walk the batches in order. Within a batch dispatch by width; wait for the whole batch to return before starting the next (barrier).

**Parallel form** — a batch of width ≥3 → N Codex worker calls in one delegation round when worker mode is allowed:

```text
Worker 1: role prompt = role-prompts/vdd-implementer.md
        prompt = { owner_page: <p1>, task_list: <g1>, scope_lock: { allowed_files: ... } }
Worker 2: role prompt = role-prompts/vdd-implementer.md
        prompt = { owner_page: <p2>, task_list: <g2>, scope_lock: { allowed_files: ... } }
...
Worker N: role prompt = role-prompts/vdd-implementer.md
        prompt = { owner_page: <pN>, task_list: <gN>, scope_lock: { allowed_files: ... } }
```

**Sequential form** — a batch of width 1 or 2 → run one owner page at a time in the main Codex session, or use one worker at a time when worker mode is explicitly allowed. Same prompt shape. Wait for each instance to return before launching the next. (Batch order already encodes the dependency chain — earlier batches produce the contracts later batches react to.)

**Inline groups** — run in the main-LLM context (Edit/Write/Bash directly). Do not route through `vdd-implementer`.

### Step 4 — Collect reports

Each `vdd-implementer` instance returns:

```text
owner_page: <path>
tasks_completed: <list>
tasks_failed: <list with reason>
files_edited: <list>
vault_frontmatter_changes: <decisions added, code_refs delta, tasks delta>
scope_violations: <empty if clean — if non-empty, partition error>
```

Aggregate all N reports.

### Step 5 — Unified verification

Single `vdd lint` run after ALL groups (parallel + sequential + inline) complete. The dispatcher does this once; `vdd-implementer` never runs lint.

If lint fails → surface errors → user decides.

### Step 6 — Handoff

> "All implementer groups returned. Lint exit <code>. Invoke `vdd-review` for verification (tests/build/lint + drift audit) before `vdd-done` — including fixes from your own manual testing: a post-build edit re-enters this gate, it does not skip to `vdd-done`."

## Risks and gates

| Risk | Mitigation |
|---|---|
| R1: Two instances edit the same vault page | Partition by `owner_page` — guaranteed by Step 1 |
| R2: Subagent hook evidence missing | Pre-deposit in Step 2 — inherits parent transcript |
| R3: Vault frontmatter drift after code edit | `vdd-implementer` Edits the owner page's frontmatter in the same step as code Edit |
| R4: Cross-page edit mixed in | Excluded at gate ②, runs inline |
| R5: Partial failure | Step 7 below — user-gated decision, no auto-rollback |

## Partial failure handling

If some `vdd-implementer` instances failed:

1. Surface `git diff` to user (the source of truth).
2. Lint may break due to partial state — report exit code, do not paper over.
3. Ask user: retry failed groups / roll back / accept partial + manual fix.
4. Do NOT proceed to `vdd-review` until the user decides.

## When the *parallel* form does not apply (still vdd-implementer, just sequential)

These are the cases `vdd-schedule.sh` reduces to width-<3 batches — the reason is named so the schedule output is legible:

- **Single-layer feature** (1 owner_page) — one batch, width 1, sequential.
- **Contract-chained pages** — a `broadcaster → reactor` edge forces them into separate batches; the barrier serializes them in dependency order. The schedule encodes this; do not second-guess it by eye.
- **Cycle** — a `SCHEDULE_CYCLE` line means the pages mutually depend and cannot be ordered. Stop and resolve via `vdd-plan` Mode C before dispatching.

## When vdd-implementer does not apply at all (→ main-LLM inline)

- **Cross-page task** — files span two owner_pages; split at plan time or run that one task inline.
- **Contract delta in scope** — `vdd-plan` Mode C owns the page-first workflow; `vdd-implementer` refuses `_state-contract.md`. Do Mode C first (page + reactor pages), then re-enter `vdd-build` for the code work.

## Anti-patterns

- ❌ Implementing inline when a single-owner_page group exists (skip implementer "to save dispatch overhead") — defeats scope-lock + model isolation.
- ❌ Running `_lint.sh` per group instead of once at the end.
- ❌ Dispatching without evidence pre-deposit (R2 inheritance breaks — subagent hooks block).
- ❌ Auto-rollback on partial failure (silently undoes user-visible work).
- ❌ Proceeding to `vdd-review` while some groups failed and the user has not decided.

## Companion / dispatched agents

| Agent | Role |
|---|---|
| `vdd-implementer` | Per-owner_page executor — scope-locked to one vault page + its `code_refs:` files. Edits code + frontmatter. Dispatched parallel or sequential by this skill. |

`vault-verifier` / `vault-critic` are NOT dispatched here — they belong to `vdd-review` (verify) and `vdd-done` (audit). This skill is execution-only.

## Handoff diagram

```
vdd-plan (decompose mode)
      ↓ owner_page-partitioned task set
vdd-build  ◄── this skill
      ├── partition + gate
      ├── vdd-schedule.sh → parallel batch layering
      ├── evidence pre-deposit
      ├── dispatch batch-by-batch (parallel ≥3 | sequential | inline)
      ├── collect N reports
      └── single _lint.sh
            ↓
vdd-review (verify + analyze)
            ↓
vdd-done (harvest + commit)
```
