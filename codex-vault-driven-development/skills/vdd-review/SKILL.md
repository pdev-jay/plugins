---
name: vdd-review
description: |
  All intent to verify completion / passage / consistency. Verification expressions in either language: "통과?/됐어?/맞아?/돌아가?/OK?/lint 깨끗해?/테스트 어떻게 됐어?/vault ↔ code 맞나/drift 있나/감사/점검/페이지가 코드랑 안 맞는 거" / "passing?/all green?/fixed?/working?/right?/lint clean?/tests pass?/did it pass?/vault matches code?/any drift?/audit the vault/check the pages". Two modes: Verify (fresh lint/test evidence for a single claim) / Analyze (vault↔code consistency gate). Phase 3 of plan → build → review → done.
---

# vdd-review — verify before claim + analyze cross-artifact consistency

**Announce on entry:** `▸ vdd-review entry — <verify | analyze> mode (<what's being checked>)`.

## Mode detection

```
prompt mentions...
   ├── "drift", "audit", "consistent with code",
   │   "vault ↔ code", "contract matches code"  ──► Analyze mode
   │
   ├── "passing", "green", "fixed", "tests OK",
   │   "lint clean", "build OK"                  ──► Verify mode
   │
   └── both signals present                        ──► Verify, then Analyze
                                                       (verify gates first;
                                                        analyze runs only if
                                                        verify is PASS)
```

A `vdd-done` invocation reaches this skill transitively (verify is `vdd-done`'s first step) — Verify mode by default; Analyze runs only if vault pages were edited this session.

## Common HARD-GATE

```
NO COMPLETION CLAIM WITHOUT FRESH VERIFICATION EVIDENCE
NO "VAULT IS CONSISTENT WITH CODE" CLAIM WITHOUT A FRESH BATCH PASS
```

If you have not run the relevant command(s) **in this message**, you cannot claim. Confidence ≠ evidence. Words like "should", "probably", "seems to", or a premature "Done!" are themselves the violation signal — STOP and run the command.

## CONSTRAINTS pre-check (both modes)

Read the plugin-owned **CONSTRAINTS V-XX** (path injected at project instruction — no `docs/vault/CONSTRAINTS.md`) once and apply the rules load-bearing for this stage:

- **V-06** — `vdd lint` must exit 0 before any "passing / green / verified" claim. Quote the exit code in the report.
- **V-03** — if vault pages were edited this session, the lint's `code_refs` check covers existence / symbol drift automatically.
- **V-04** — if architectural decisions were made and the prompt asks "is it done?", flag decisions not yet written to vault frontmatter.
- **V-02** — if `broadcasts:` keys changed in any `_state-contract.md`, verify reactor pages in `_reverse-index.md` were also updated.

If any V-XX is unsatisfied, state the rule number and the concrete miss. Do not generalize ("vault stale") when the rule has a concrete trigger.

---

## Mode A — Verify (pre-claim verification)

### Gate procedure

```
1. IDENTIFY  — which command proves this claim?
2. RUN       — execute it fresh, complete
3. READ      — read entire output, check exit code, count failures
4. VERIFY    — does the output corroborate the claim?
5. CLAIM     — only then make the claim (quote exit code as evidence)

Skipping any step = lying, not verifying.
```

### What needs which command

| Claim | What proves it |
|---|---|
| Tests pass | test command output: 0 failures |
| Linter clean | linter exit 0 |
| Build succeeds | build command: exit 0 |
| Bug fixed | original symptom test: passes (red-green for new tests) |
| Vault consistent (schema) | `vdd lint` exit 0 (V-06) |
| Vault ↔ code match | → delegate to Analyze mode (this skill, below) |
| Broadcast change applied | all reactor pages updated (V-02) |
| Agent finished | VCS diff shows changes (do not trust agent self-report) |

### Verification stages (in order)

1. **Project lint / test / build** — run as defined in the project's AGENTS.md or vault root. Confirm exit 0 and read the output tail.
2. **Vault lint** — `vdd lint`. Required whenever any vault page changed, any `code_refs:` path was edited, or any `broadcasts:` / `reacts_to:` / `emits_to:` field was modified.
3. **Vault ↔ code drift** — single page touched: `grep -rl "<changed_path>" docs/vault/`, confirm prose still describes behavior, `code_refs:` still resolve. Whole-vault or cross-layer scope, or drift suspected: switch to **Analyze mode** (below). Consume its verdict — `CONSISTENT` → continue; `NOT READY` → this report's Vault↔code line is `drift`, Overall is NOT READY with the drift list.
4. **Re-grep affected scope** — every modified function / class / flag re-grepped to confirm callers updated consistently.
5. **Cross-platform builds** — when native code on any platform-specific path changed, all platforms must build. Asymmetric pass = report immediately.
6. **Real-device QA enumeration** — for runtime / lifecycle / hardware paths (BLE, GPS, camera, background, push, permission, role switch), state the manual scenarios the user must run. Static analysis cannot cover these.

### Verify report

```
Verification Report
==================
Project lint:      [PASS/FAIL]
Project tests:     [PASS/FAIL]
Project build:     [PASS/FAIL/N-A]
Vault lint:        [PASS/FAIL]    (vdd lint — V-06)
Vault ↔ code:      [clean / drift in <pages>]   (from Analyze mode if invoked)
Scope re-grep:     [done / skip-reason]
Native builds:     [PASS/FAIL/N-A]
Real-device QA:    [item list / N-A]

Overall: [READY / NOT READY] for vdd-done

Fixes needed:
1. ...
```

A PASS without an exit code or command quote is not a verification — it is a guess.

### Differentiated depth

- **Mechanical** (renames, file moves, alias cleanup): stages 1–3 + diff review suffice.
- **Logic / native / contract change**: full 1–6, plus Analyze mode for cross-artifact consistency.

---

## Mode B — Analyze (cross-artifact consistency)

`_lint.sh` proves the vault is internally well-formed (V-02 / V-05). It does **not** prove the code backs the contract. A page can declare `broadcasts: [auth:reconnecting]` with no emitting `code_refs` file, or describe a Flow the code no longer matches — lint stays green while the SoT lies. This mode is the proof that **code ↔ contract ↔ decision** agree.

### Procedure

#### Step 1 — Deterministic floor

```bash
vdd lint
```

- **exit ≠ 0** → STOP. V-06 precedes everything: fix every `ERR` and re-run before any consistency analysis. A consistency pass over a schema-broken vault is meaningless.
- **exit 0** → harvest the deterministic cross-artifact signals from the output:
  - **Check 13 (V-09)** `WARN ... broadcasts key '...' not found in any of this page's code_refs files` → contract→code drift candidates.
  - **Check 3** `WARN ... code_refs symbol '#...' ... (renamed?)` → code→contract symbol drift candidates.
  - **Check 4d (V-05)** `WARN ... orphan broadcast '...'` → declared keys with zero reactor — anomaly candidates (some legitimate, e.g. UI states read directly by the framework).
  - **Check 4e (V-11)** `INFO: silent layers ...` → layers participating in neither the broadcast nor the intent graph — absence candidates.

These signals are the floor — deterministic, reproducible, CI-portable. They are **facts** (an edge is missing / a layer is silent), never verdicts. They feed the triage (Step 1.5), they do not decide alone.

#### Step 1.5 — Triage (LLM hypothesis, non-authoritative)

The floor (Step 1) hands you **facts**: orphan keys, silent layers, V-09 / symbol WARNs. Classify each into a *hypothesis* — this is the layer where naming convention + domain knowledge add value, and the one place an LLM judgment belongs. It is **look-here, not this-is-broken**: triage prioritizes what the verifier chases, it never decides.

For each fact, label it:

```
NORMAL      explainable by convention — likely not a defect, low verifier priority.
            e.g. orphan `initial/loading/loaded/failure` on a feature BLoC = standard
            UI state read directly by the view, never via reacts_to → expected dark.
SUSPICIOUS  convention says this SHOULD have a counterpart but doesn't — high priority.
            e.g. orphan on a state-machine transition key (`phase:verifying`); a
            paired-lifecycle key present on one side only (`passage:entered` consumed,
            `passage:exited` orphan); a silent layer whose code_refs point at
            event-producing code (a native bridge).
QUESTION    asymmetry or absence that is ambiguous without intent — medium priority,
            flag for human if code is also silent.
```

Triage is **fallible by design** — `phase:*` "SUSPICIOUS" may turn out intentional. That is why it only *orders* the verifier pass; the code-read (Step 2) confirms or refutes, and the FIX-vs-leave call stays with the human. Do **not** record a triage label as a verdict, and do **not** put this classification into `_lint.sh` — convention heuristics are project-specific and brittle as deterministic checks (the bash floor surfaces the fact; the LLM triages it).

#### Step 2 — Batch verifier pass (semantic layer)

Enumerate layers: `ls -d docs/vault/*/` minus `_*` / `_archive`.

- N ≥ 3 AND scope = whole-vault → single-message parallel dispatch, one `vault-verifier` per layer.
- N < 3 OR single-page targeted → sequential single-pass.

**Frame each verifier task around the triage hypotheses (Step 1.5), not just "verify the layer"** — hand it the specific question to settle against code. A focused prompt resolves the anomaly; a broad one re-derives it.

```text
# Focused form — settle the SUSPICIOUS/QUESTION hypotheses against code
"Verify docs/vault/beacon_scan/* vs code. SPECIFICALLY: passage:exited is
 declared but has zero reactor — does the code emit/handle an exit transition?
 If yes → vault is missing the reacts_to/emits_to edge (DRIFT). If the code has
 no exit path → the contract over-declares (note it). Report which."
```

`vault-verifier` is read-only (`Read/Grep/Glob/Bash`) — no race / evidence concerns. Collect N reports.

```text
# Parallel form (≥3 layers, when Codex worker mode is allowed)
Worker 1: role prompt = role-prompts/vault-verifier.md
          prompt: "Verify docs/vault/<L1>/* claims vs code"
Worker 2: role prompt = role-prompts/vault-verifier.md
          prompt: "Verify docs/vault/<L2>/* claims vs code"
...
Worker N: ...
```

`vault-critic` may dispatch in the same message or as a second batch for prose-quality audit (called out in `vdd-done`, not here).

#### Step 3 — Merge → per-page verdict

For every page, fold the deterministic floor (Step 1) + `vault-verifier` claims (Step 2):

```
CONSISTENT     code, contract, decisions agree; no floor WARN, no contradicted claim
DRIFT          ≥1 contradicted claim OR a V-09 / symbol WARN corroborated by the verifier
               (contract claims an emitter the code lacks; Flow ≠ code;
                decision cites dead code)
UNVERIFIABLE   architectural-intent claim the code cannot confirm/deny
               (deferred to human)
```

A bare V-09 / symbol WARN with no corroborating verifier finding is reported as **DRIFT (heuristic — confirm)**, not silently dropped and not auto-escalated.

#### Step 4 — Verdict

```
any page = DRIFT   → overall NOT READY  (list each drifting page + the specific mismatch)
else               → overall CONSISTENT
```

`UNVERIFIABLE` alone does not fail the gate — surfaced for human judgment.

#### Step 5 — Stamp the CONSISTENT pages (V-10 review freshness)

Each page verdicted CONSISTENT was just confirmed against the current code. Record that so V-10 detects *future* drift:

```bash
vdd lint --stamp <page>   # one per CONSISTENT page (bare --stamp = all)
```

This writes `reviewed_code_hash` (a content fingerprint of the page's `code_refs`) + `reviewed_at` into the page frontmatter. Content-based, so the stamp is fresh immediately — no commit needed — and the edit rides along in this session's commit.

**Stamp ONLY CONSISTENT pages.** Do NOT stamp pages verdicted DRIFT or UNVERIFIABLE — their freshness flag must stay raised until the drift is resolved / the human confirms. Stamping them would mask the very drift this gate exists to surface. (The main LLM runs this after the consolidated report — `vault-verifier` is read-only and never stamps.)

### Analyze report

```
Cross-artifact analysis
=======================
Lint floor:        [exit 0 / exit 1 → blocked]   vdd lint
V-09 (contract→code) floor:  N candidate(s)
Symbol (code→contract) floor: N candidate(s)
Verifier batch:    [parallel ×N / sequential]    M reports merged
Stamped (V-10):    [N CONSISTENT page(s) re-stamped fresh / none]

Per page:
  docs/vault/auth/auth.md            CONSISTENT
  docs/vault/sync/sync.md            DRIFT — broadcasts: sync:flushed has no emitter in
                                      code_refs (V-09) + verifier: body claims debounce
                                      at sync_bloc.dart:88, code shows none
  docs/vault/ui/ui.md                UNVERIFIABLE — "header is the only reconnect surface"
                                      (architectural intent — human confirm)

Overall: [CONSISTENT / NOT READY]

Drift to resolve:
1. sync/sync.md — add the emitter to code_refs OR remove the broadcasts key (decide which is true)
```

A CONSISTENT verdict without a quoted fresh lint exit code and a merged verifier batch is a guess, not an analysis.

---

## Skip parallel when

- vault has <3 layers (orchestration overhead > benefit).
- a single layer / page is targeted (no fan-out needed).
- verification needs cross-layer context (single agent reasons better with full scope).
- session is interactive Q&A (latency, not throughput, dominates).

## Why parallel dispatch is safe

Both agents (`vault-verifier`, `vault-critic`) are **read-only** (`tools: Read, Grep, Glob, Bash` — no Edit / Write). No race on vault page state, no evidence-hook entanglement. Page modifications, if any, are user / main-LLM driven *after* the consolidated report.

## What this skill does NOT do

- Suggest a commit message → that is `vdd-done`.
- Harvest decisions from conversation → that is `vdd-done` / `vdd-log`.
- Wiki promotion check → handled inside `vdd-done`.
- Modify page bodies or code — Analyze mode emits a verdict; the human / main-LLM resolves drift afterward (update page to match code, or fix code to match intent). The one write it does make is the `reviewed_code_hash` freshness stamp on CONSISTENT pages (Step 5) — a frontmatter marker recording "verified against this code", not a content/drift edit.
- Block tool calls — no hook. The gate is procedural (the verdict that `vdd-done` consumes).

This skill is intentionally narrow: **verify before claim** + **prove the vault is true**. Everything else belongs in the closing workflow.

## Handoff diagram

```
vdd-build (returns aggregated reports)
      ↓
vdd-review ◄── this skill
      ├── Verify mode — lint/test/build + V-06 + scope re-grep
      ├── Analyze mode — deterministic floor + vault-verifier batch + verdict
      └── Overall: READY → vdd-done
                   NOT READY → user fixes → re-invoke
            ↓
vdd-done (harvest + commit)
```
