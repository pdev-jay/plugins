# CONSTRAINTS.md — VDD workflow integrity rules

> **Read once per session** — at the first code/docs task. The vdd-workflow skill
> Reads it at session entry; it is stable within a session, so do NOT re-read on
> later tasks in the same context window (re-read only if `/fix` edited it mid-session).
> It is not an always-on control surface but a *reference checked at the entry of
> workflow skills* (vdd-plan / vdd-build / vdd-review / vdd-done /
> vdd-investigate). Procedure enforcement by skill bodies is the **primary**
> mechanism; hook enforcement is opt-in backstop.

## Rules

`V-XX` — **VDD system integrity**. These protect the contract that the vault is
the SoT. They are universal and plugin-owned: this file ships in the plugin and
is read straight from there (the project AGENTS.md instruction injects its absolute path).
There is **no per-project copy** to edit, drift, or sync — and no project-specific
rule prefix. A real incident that should harden behavior becomes either a new V-XX
here (proposed upstream) or a page `decisions:` entry, not a local constraint file.

`_lint.sh` Section 4c is a plugin-internal self-consistency check: the `### V-XX`
count in this file must match the `# V-XX` check lines (or `# V-XX: MANUAL`
markers) in the lint body. Any rule expressed as a grep-able marker must be
registered in lint too.

## 4-part format

```
### V-XX: <title>
- **Forbidden**: <specific action>
- **Why**: <reason — incident / causality / what breaks>
- **Correct path**: <which procedure to follow>
- **Detection**: <_lint.sh auto / `/vdd-review` skill body / manual review>
```

---

### V-01: Missing owner-vault-page Read before code edit

- **Forbidden**: Editing / writing a code file whose path is listed in some vault
  page's `code_refs:` without first Reading that owner page.
- **Why**: The vault is the SoT for architectural intent / conventions /
  decisions. Editing without Read lets changes violate that page's stated
  invariants *without any signal*. Multi-owner files are especially risky —
  one layer sees the change but other owner pages do not, so cross-layer drift
  accumulates silently.
- **Correct path**:
  1. Run `vdd impact <code-path>` to enumerate owner pages.
  2. Read every owner page in the output (MCP `read_note` preferred, `Read` fallback).
  3. Inspect § Capability boundary / § Architectural conventions / decisions.
  4. **Decision-conflict check** — for each `decisions[*].note` on the owner page,
     test whether the user's current request explicitly contradicts it as a
     `(topic, direction)` pair (same subject, opposite direction). If so, STOP —
     do NOT silently override the user (insisting on the old decision) and do NOT
     silently override the decision (proceeding without recording). Quote the
     conflicting entry (`date` + `note`) to the user and ask: "이 작업은 `<date>`
     결정 `<note>` 을(를) 뒤집습니다. 의도가 맞습니까?". On confirm → invoke the
     **replace + archive** procedure via `/vdd-log` (see V-04). On rescind → keep
     the old decision and stop the conflicting change.
  5. Decide if the change matches intent, then Edit.

  **Conflict trigger — explicit only.** False positives erode the signal. Apply
  ALL three filters:
  - **Same topic** — same subject (component / pattern / artifact named in the
    decision). Adjacent / related work on the same layer is NOT a conflict.
  - **Opposite direction** — the user's intent reverses the decision's
    predicate (location, owner, presence/absence, mechanism choice).
  - **Intent match, not keyword match** — sharing a noun token while the
    decision's *object* differs is NOT a conflict. Match against (subject,
    predicate) pairs, not against `grep`.

  **Refinement is NOT reversal.** Narrowing scope, adding a caveat, or extending
  the same direction with more nuance is a *new entry alongside* the original,
  not a replacement. Only flip the `(topic, direction)` pair triggers the
  replace path. Refinements are appended normally via `/vdd-log`.
- **Detection**: MANUAL — lint cannot see Read-before-edit ordering nor
  intent-level conflict. Enforced by the workflow skill bodies' `vdd-impact` step
  and the Decision-conflict handler in `vdd-workflow` (no hook backstop —
  discipline is the model's responsibility). Marked `# V-01: MANUAL` in
  `_lint.sh` so the 4c coverage check reports it as acknowledged-uncovered, not
  falsely covered.

---

### V-02: Missing reactor page sync when a broadcast key changes

- **Forbidden**: Adding / changing / removing a `broadcasts:` key on vault page A
  without *also* updating reactor pages that have that key in `reacts_to:` or
  `emits_to:`. Changing code without updating the contract page is forbidden too.
- **Why**: The broadcast graph is the SoT of the cross-layer contract.
  One-sided changes leave dangling edges. With luck `_lint.sh` catches it
  (undefined key); without luck lint passes but at runtime reactors wait for a
  key that no one emits.
- **Correct path**:
  1. Run `vdd blast <broadcast-key>` to enumerate reactors.
  2. Read every reactor / emitter page.
  3. Edit reactors together. If the key is *removed or renamed*, commit type is
     **`vault!`** (BREAKING contract).
  4. If the change is large, enter `vdd-plan` Mode C (contract) for page-first workflow.
- **Detection**: `_lint.sh` broadcast-graph consistency check — a `reacts_to` /
  `emits_to` reference to an undefined key is an **error** (exit 1), so it
  blocks the V-06 lint-PASS gate (no longer a silently-ignorable warning).
  Automatic.

---

### V-03: code_refs pointing at non-existent files / symbols

- **Forbidden**: Listing in `code_refs:` a path that does not exist, or a symbol
  anchor (`path/file.ext#SymbolName`) that no longer resolves; or moving a file /
  renaming a symbol without updating the vault page's `code_refs:` before ending
  the work session.
- **Why**: `code_refs` is the vault → code link. Dead references accumulate and
  the page's anchors become lies — the next session starts from false claims.
  Vault trust starts with reference integrity.
- **Correct path**:
  - File moved → update the `code_refs:` path.
  - Symbol renamed → update the anchor.
  - Symbol *gone* → archive the relevant section of the page, or move the page
    itself to `_archive/` with `status: deprecated` + a decision entry.
- **Detection**: `_lint.sh` code_refs check. A missing file / directory path is
  an **error** (exit 1, blocks the V-06 gate). The 2-tier symbol-anchor grep
  stays a **warning** (rare-language / rename false-positives make a hard fail
  unsafe). Automatic.

---

### V-04: Architectural decision not recorded in vault during work

- **Forbidden**: Reaching a **constraint-bearing** architectural decision during
  a work session — one that future work must respect to avoid a wrong turn or a
  regression (an invariant, a forbidden path, a required approach, a threshold) —
  without recording it in the relevant vault page's `decisions:` frontmatter or
  via `/vdd-log` before moving on.
- **The record test — a decision is constraint-bearing iff**: *"would a future
  worker (LLM or human) editing this area, not knowing this, take a wrong turn
  or reintroduce a bug?"* If yes → record. If the choice merely happened and
  leaves no constraint — its result lives in the code, and re-deciding it
  differently later is safe — it is **history, not a decision**. Do not record
  history; code, imports, and git already preserve it. Recording every rationale
  inflates `decisions:` into a narrative dump and buries the entries that
  actually act as a harness on future work.
- **Why**: A `decisions:` entry is a guardrail fed back to later sessions
  (project instruction inject + Rule 0 zoom-in). Code preserves the *result* of a choice
  but not the *constraint* behind it — capture the binding reason, not the event
  log. A choice with no constraint is already recoverable from code.
- **Correct path**:
  - On decision: `/vdd-log "<decision> — <reason>"` or add to that page's
    frontmatter as `decisions: - {date: YYYY-MM-DD, note: "..."}`.
  - **On decision *reversal* (overturning a prior `decisions:` entry on the same
    page)**: use the **replace + archive** procedure — `frontmatter` holds only
    currently-active decisions, `body` holds history. Silent reversal (appending
    a contradictory decision without archiving the old) is the same violation as
    not recording at all; the page's `decisions:` would then contain two active,
    contradictory entries with no signal of which is current.
    1. **Remove the reversed entry** from `decisions:` frontmatter (via `Edit`,
       not MCP frontmatter tools).
    2. **Archive it into the page body** under a `## decisions archive`
       heading. Form:
       ```markdown
       ## decisions archive

       ### YYYY-MM-DD — <one-line title of the old decision>

       **Note (frontmatter as it stood):** "<original note verbatim>"

       **Replaced YYYY-MM-DD:** <one-clause why it changed>. See current entry
       in `decisions:` frontmatter dated <new-date>.
       ```
       (Archive entries are body prose — V-08's ≤200 char limit on
       `decisions[*].note` does not apply to them; expand reasons freely here.)
    3. **Append the new decision** as a fresh `decisions:` entry with today's
       date.
    4. **Sweep the page body for sibling claims** — if `## Architectural
       conventions` / `## Capability boundary` / parity tables / ASCII flow
       diagrams in the same page state the *reversed* direction explicitly,
       update them in the same edit. Body sections are not auto-derived from
       `decisions:`; leaving them stale recreates the contradiction at a
       different surface.
    5. If the archive section accumulates so many entries that the page body
       grows past ~200 lines, **escalate to V-08's archive child page pattern**:
       move the archive section into `<layer>/decision-log.md` and leave a
       pointer in the body.
  - V-01's Decision-conflict handler invokes this path when a user-driven
    reversal is detected and confirmed.
  - At session end, `/vdd-done` scans the conversation and surfaces missed
    decisions (Auto Decision Log).
- **Detection**: `_lint.sh` warns if an *active* page has empty `decisions:` +
  body >50 lines (filler risk); `/vdd-done` Auto Decision Log fills the gap.
  Reversal-without-archive is MANUAL (intent-level) — enforced by the V-01
  handler + `vdd-log` body. The `_decisions.md` rollup sources only frontmatter,
  so it stays a clean "what is true now" scan; archived reversals stay visible on
  the page itself ("what changed and why").

---

### V-05: New broadcast key introduced without a reactor decided

- **Forbidden**: Adding a new `broadcasts:` entry to a vault page and moving to
  code implementation without deciding which page will be the reactor
  (`reacts_to:` / `emits_to:`).
- **Why**: An emitter without a receiver leaves the contract partially defined.
  Code built on that state ships before "who is responsible" is agreed; later,
  when assigning a reactor, the emitter's payload often turns out unsuitable,
  forcing emitter changes too — cascade rework.
- **Correct path**: At spec time, name at least one reactor candidate. If it is
  temporarily deferred to another ticket, mark it `"TBD — see <issue/PR>"`. A
  broadcast with zero reactors is forbidden.
- **Detection**: `_lint.sh` broadcast orphan check (key in `broadcasts:` with no
  `reacts_to:` anywhere) warns. `vdd-plan` Mode A skill body checks explicitly
  during spec authoring.

---

### V-06: `_lint.sh` PASS not confirmed before closing

- **Forbidden**: Running `/vdd-done` or proposing a commit message while
  `vdd lint` exits with errors > 0.
- **Why**: Lint failure = schema violation or dangling reference. Committing
  in that state means the next session starts on a broken SoT. Trusting a wrong
  vault page is *worse* than having no vault at all (false confidence).
- **Correct path**:
  - Run `/vdd-review` or `vdd lint` directly.
  - If errors > 0, fix every ERR line and re-run.
  - Only after 0 errors, proceed to `/vdd-done`. Warnings are triage-able
    (do not need to be zero).
- **Detection**: `/vdd-review` and `/vdd-done` skill bodies explicitly invoke
  lint and check the exit code (procedure enforcement — no hook backstop).

---

### V-07: Missing verdict on impact-set members in impact analysis

- **Forbidden**: Proceeding to implementation or session close while at least
  one member of the impact set enumerated by `vdd-impact.sh` / `vdd-blast.sh`
  (owning pages + `intent_refs` closure + reactors / emitters) is left without
  an explicit verdict (`affected` / `unaffected` / `deferred`).
- **Why**: Impact-set *computation* is deterministic, but whether each member
  was actually *considered* is not verified. A member without a verdict ends as
  "silently missed" rather than "reviewed and unrelated" — the affected page
  drifts and no signal fires. A one-line verdict per member makes the silent
  gap visible.
- **Correct path**:
  1. Run `vdd-impact.sh <code-file>` (or `vdd-blast.sh <key>`).
  2. Attach the enumerated set verbatim to Impact Analysis.
  3. Give each member a one-line verdict — `affected` (what changes) /
     `unaffected` (why it doesn't reach here) / `deferred` (separate issue / PR — link it).
  4. If any member lacks a verdict, do not proceed to implementation / `/vdd-done`.
- **Detection**: MANUAL — verdict *correctness* is not automatable. Enforced by
  workflow skill bodies (vdd-plan all modes / vdd-investigate) at the Impact
  Analysis step; user review + post-hoc `_lint.sh` (broadcast graph / code_refs
  integrity, now error-level) compensate. Marked `# V-07: MANUAL` in `_lint.sh`
  so the 4c coverage check reports it honestly.

---

### V-08: Vault page bloat — narrative padding / code paraphrase / oversized decisions notes

- **Forbidden**: Inserting into a vault page's body or frontmatter (a) narrative
  filler that is not intent, (b) a paragraph that paraphrases code, or (c) a
  `decisions[*].note` longer than 200 chars — turning a *decision one-liner*
  into *narrative*.
- **Why**: Vault's value comes from *intent preservation* + *cheaper Rule 0*.
  Bloat causes: (1) drift becomes certain (code paraphrase falsifies the moment
  code changes); (2) Rule 0's "Read the layer page" becomes physically
  impossible at 40KB (Read token limit); (3) the `_decisions.md` rollup becomes
  a narrative dump, defeating chronological scanning; (4) "SoT contradicts
  itself" — body of page A and `note` on page B saying the same fact in
  different words leaves the authoritative version ambiguous.
- **Correct path**:
  - In the body, keep only *WHY* / *invariant* / *NOT here*. Anything code can
    answer is delegated to `code_refs` anchors.
  - `decisions[*].note` is one line (≤200 chars) — "decision: <one line>.
    rationale: <one clause>". Longer justification goes in the commit message
    body or the page body's § decisions paragraph.
  - If a long narrative is genuinely needed, fork it into a child page (zoom +1).
- **Detection**: `_lint.sh` Check 12 WARNs `decisions[*].note > 200 chars`;
  Check 12b WARNs when active `decisions:` entries exceed the count cap (default
  25) — nudging the archive-child-page pattern before the page turns into
  archaeology. Body bloat / code paraphrase auto-detection is hard (same as
  V-04) — trim review in `vdd-log` / `vdd-done` skill bodies + post-hoc
  `vault-critic` agent compensate.

---

### V-09: broadcast key declared without a code producer (contract ↔ code drift)

- **Forbidden**: Leaving a vault page with a non-empty `broadcasts:` key whose
  emitting code is absent from *every* one of that page's own `code_refs:`
  files — i.e. the contract claims the page emits a signal the code it points
  at does not produce.
- **Why**: `_lint.sh` (V-02 / V-05) only proves the broadcast graph is
  internally well-formed, never that *code* backs the contract. A page can
  declare `broadcasts: [auth:reconnecting]` while no `code_refs` file emits it
  — lint passes, the SoT lies, the next session builds on a phantom emitter.
  This is the contract → code direction no other check covers.
- **Correct path**:
  1. When declaring a `broadcasts:` key, ensure at least one `code_refs:`
     entry on the same page points at the file that emits it.
  2. If the emitter is not yet implemented (spec-first), keep the page
     `status: draft` / `in_progress` and leave `code_refs:` without the
     producer file *or* empty — the check skips pages with no concrete
     code_refs file, so an honest spec-first page produces no false alarm.
  3. Run `vdd-review` Mode B (Analyze) for the binding cross-artifact verdict
     — it pairs this deterministic floor with the `vault-verifier` batch pass.
- **Detection**: `_lint.sh` Check 13 — heuristic (key→token presence in the
  page's own `code_refs` files), **WARN only** (a token-match false positive
  must never block the V-06 gate). The binding gate is `vdd-review` Mode B's
  batch consistency verdict (NOT READY surfaced via the same skill's Verify
  mode handoff). Marked `# V-09` automated in `_lint.sh`.

---

### V-10: Vault page intent left unverified against drifted code (stale review)

- **Forbidden**: Closing a work session with a vault page whose `code_refs`
  content has changed since the page's `reviewed_code_hash` stamp, without
  re-reviewing the page's intent against the new code and re-stamping.
- **Why**: `_lint.sh` proves *reference integrity* but never that the page's
  *prose intent* still matches its code. A page stays lint-green while the code
  drifts semantically — the next session trusts a page that became a lie.
  V-01..V-09 catch structural drift; nothing catches "code moved, intent
  unchecked". The review stamp makes it lint-visible: a passing review
  fingerprints the confirmed code, and any later change re-raises the flag.
- **Correct path**:
  1. Run `/vdd-review` (Mode B Analyze) on the pages whose code changed.
  2. Confirm the page's § Architectural conventions / § Capability boundary /
     `decisions:` still hold against the new code; fix the page if they don't.
  3. Re-stamp: `vdd lint --stamp <page>` (or bare `--stamp` for
     every page) records the current code fingerprint as the reviewed state.
     `/vdd-review` does this automatically for every page it verdicts CONSISTENT.
- **Detection**: `_lint.sh` Check 14 — WARN-only. For each page that carries
  `reviewed_code_hash`, it recomputes the fingerprint of the page's own
  `code_refs` and WARNs "intent may be stale" on mismatch. Pages with code_refs
  but no stamp are summarized once (INFO), never an error. The binding intent
  verdict is `/vdd-review` Mode B — this check is its deterministic prompt. WARN
  never blocks the V-06 gate (a content change is a re-review prompt, not a
  schema break; renames / whitespace trip it by design, cleared cheaply by
  re-stamping). Fingerprint is content-based (not git): fresh immediately after
  review, survives clone / rebase. Marked `# V-10` automated in `_lint.sh`.

---

### V-11: Layer left silent in the broadcast/intent graph without triage

- **Forbidden**: Closing a work stage with a layer whose pages collectively
  declare **none** of `broadcasts:` / `reacts_to:` / `emits_to:` / `intent_refs:`
  — a "silent" layer — without having decided whether that silence is
  intentional (a genuinely standalone, cross-cutting layer) or a gap (a layer
  that *should* participate but declares nothing).
- **Why**: V-02 / V-05 only validate *declared* edges — they prove the edges you
  wrote are consistent. They are structurally blind to the **absence** of an
  edge that ought to exist. A native-bridge layer that produces events but
  declares no `broadcasts:`, or a layer whose `intent_refs:` were never recorded,
  stays lint-green and invisible: the broadcast graph looks complete while a real
  producer/consumer sits off the map. Drawing the map is the only way this
  surfaces today — V-11 makes the same fact deterministic so it does not depend
  on someone happening to render the graph.
- **Correct path**:
  1. Per silent layer, decide: standalone or gap.
  2. **Gap** → add the missing edge (`broadcasts:` on the emitting page,
     `reacts_to:` / `emits_to:` on consumers, or `intent_refs:` for a design
     dependency) so the layer joins the graph.
  3. **Standalone** → record it once in the layer index page's `decisions:`
     (e.g. "standalone: cross-cutting error surface, emits no cross-layer signal
     by design") so the next worker reads intent, not silence.
  4. Run `vdd-review` Mode B (Analyze) — its triage step classifies each silent
     layer (standalone vs gap) as a *hypothesis*, then `vault-verifier` confirms
     against code. The FIX-vs-leave verdict stays with the human (intent).
- **Detection**: `_lint.sh` Check 15 (4e) — aggregates the four graph fields
  **per layer** (not per page: `auth/auth.md` alone is empty but the auth layer
  is connected via `_state-contract.md` + feature pages) and emits an **INFO**
  list of silent layers. INFO-only — never WARN, never blocks the V-06 gate
  (silence is frequently legitimate; a per-layer nag would be noise). The list is
  the deterministic triage input for `vdd-review` Mode B, which decides
  standalone-vs-gap. Marked `# V-11` automated in `_lint.sh`.

<!-- end of V-XX rules -->
