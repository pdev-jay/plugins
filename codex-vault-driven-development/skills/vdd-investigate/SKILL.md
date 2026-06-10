---
name: vdd-investigate
description: |
  Any signal that existing behavior diverges from intent. Covers soft symptom expressions in either language: "안 돼/이상해/안 떠/사라져/안 보여/깜빡여/끊겨/어색해/그렇지 않아?/이거 왜 이래" / "doesn't work/is broken/looks wrong/doesn't show up/keeps disappearing/flickers/keeps cutting out/feels off/something's off/why is this happening". Reads the vault page before any code grep (HARD-GATE — body). New feature/design intent → vdd-plan; simple lookup → vdd-explain.
---

# vdd-investigate

**Announce on entry:** `▸ vdd-investigate entry — query vault SoT before tracing code (<the reported behavior>)`

A workflow for projects with a vault: when the user raises **a question or debugging request about existing behavior**, query the vault SoT first before tracing code directly.

## Why this skill

The vault is the SoT for architectural intent + decisions + invariants. When a user says "X is weird," 90% of the time:

| Pattern | Diagnosis |
|---|---|
| Code matches the vault invariant + the user doesn't know the invariant | → Reading the vault first lets you immediately answer "this is intended behavior" |
| Code violates the vault invariant | → Vault read narrows the location of the violation. Faster than code grep. |
| Vault doesn't state the invariant (drift) | → The vault itself is stale → invoke vault-verifier, page must be updated |
| Truly vault-unrelated (low-level bug, dependency, env) | → Quickly skip vault, then proceed with general debugging |

**In 3 / 4 cases vault read is faster than code grep.** Only 1 / 4 is wasted. The expected ROI of vault-first ≫ code-first.

**The spirit of this skill**: when the user asks "why doesn't X work", unconditionally read the vault layer page once → then form hypotheses / trace code.

## HARD-GATE

```
NO CODE TRACE BEFORE VAULT LAYER PAGE READ
```

This skill enforces the following **before any code grep / file read / agent dispatch**.

## Trigger

Use this skill if any of the following apply:

- The user expresses a question about *existing behavior* — "why X", "X doesn't work", "X is weird", "bug", "wrong"
- The user reports an *inconsistency* — "shrinks", "disappears", "not visible", "missing", "doesn't match"
- The user reports an *unexpected result* — "is this right?", "this seems off", "looks wrong"
- A reviewer / verifier agent reports "intent and code mismatch"

**Not triggered by**:
- New feature / fresh implementation (→ use `vdd-plan` Mode A / Mode C)
- Simple lookup / usage question (→ use `vdd-explain`)
- Build error / type error (→ general build/type troubleshooting)

## Preconditions

- `docs/vault/` directory exists. If not → fall back to general debugging directly
- `docs/vault/index.md` (or layer index) exists and lists the layers

## 4-Phase workflow

Only enter the next phase after completing the current one.

---

### Phase 1 — Layer identification

Map the user's wording → which layer's behavior it refers to.

**Tools** (in preference order):

If an Obsidian MCP server is available in this session (look for tools matching `mcp__*obsidian*__*` in the available tool list), prefer its query primitives — they are faster for backlinks / graph / properties lookups than filesystem grep:

- Obsidian MCP `search` — across vault, returns hit pages with context
- Obsidian MCP `backlinks` (if exposed) — pages that link to a candidate
- Obsidian MCP `properties` / `dataview` (if exposed) — frontmatter query (e.g. pages where `broadcasts:` contains a key)

Filesystem fallback (always works, no Obsidian dependency):
1. `cat docs/vault/index.md` (or layer index) — layer list + one-line descriptions
2. `grep -rliF "<keyword>" docs/vault/ --include="*.md"` — page candidates containing the keyword (search ALL vault SoT, not a single layer — `_reverse-index.md` and `_decisions.md` are co-equal targets)
3. If a code path is mentioned, **`vdd impact <code-file>`** — single-shot reverse blast: prints owning vault pages + per-layer broadcasts. Use this in preference to plain `grep -rln "<file>"` — it deduplicates by layer and surfaces broadcast emitters. Running it here folds Phase 1 layer identification into one step.

**Example mapping**:
| User wording | Candidate layer |
|---|---|
| "grid / canvas / screen / UI" | ui / view |
| "connection / scan / disconnect" | connection / network |
| "no data / stream / event" | data / repository / channel |
| "location / positioning / tracking" | positioning / tracking |
| "state / state machine" | state-contract pages |

**Exit criterion**: 1-3 candidate layers selected.

---

### Phase 2 — Page read (forced)

Read the candidate layer pages from Phase 1 **in order**. **Skipping this phase and starting code trace is a skill violation.**

Big page (>~25K tok, e.g. a mature layer index)? Pull the sections with `mcp__obsidian-vault__search_notes` or `Read` + `offset`/`limit` — not a broad `grep -n "A\|B\|C"` over the file, which dumps full prose lines (~5K tok/call). (Phase 1's `grep -rliF -l` for *finding* the page stays fine.)

In each page, scan these 4 sections first:

1. **Architectural conventions** / **Capability boundary** — what this layer owns / does not own
2. **decisions** (frontmatter) — reasons for past decisions. Especially recent (last 7 days) decisions.
3. **`## Invariants`** (when present) — explicit SoT statements
4. **What is NOT here** — anti-scope, explicit non-responsibility

**Exit criterion**:
- Can state in one line which conv/decision/invariant on the page conflicts with the user's observation
- Or diagnose "no relevant invariant on the page, suspect page is stale"

**Optional — wiki context**: if `~/wiki/wiki/` exists and the suspected issue is a domain-general pattern (timing race, retry semantics, lifecycle ordering, etc.), invoke the `wiki-querier` agent to surface known patterns from `~/wiki/wiki/concepts/<topic>/`. Skip if no wiki or issue is clearly project-specific.

---

### Phase 3 — Hypothesis + code verification

Formalize the diagnosis from Phase 2 into a hypothesis.

**Hypothesis form**:
> "Per decision/invariant Y on Page X, Z must hold. The user's observation is ¬Z. Therefore the [specific path] in code must be violating Y."

Code trace happens **only along the path narrowed by this hypothesis**:
- Grep starting from the anchor in code_refs
- Read starting from the file/symbol the hypothesis points to
- No indiscriminate grep / file walk

**Diagnosis branches**:
- (a) Hypothesis confirmed → Phase 4
- (b) Hypothesis missed → return to Phase 1, consider another layer candidate
- (c) 3 hypothesis misses → vault is stale or it's a cross-layer issue. **Invoke the vault-verifier subagent** or escalate to general debugging

---

### Phase 4 — Fix + page sync

The fix and the vault page update **must go in the same commit**.

1. Code fix (one root cause, single fix)
2. **Impact coverage (V-07)** — take the `vdd-impact.sh` output from Phase 1 (owning pages + `intent_refs` closure). The fix touches code those pages own; give *every* enumerated member a one-line verdict — `affected` (the fix changes it; sync it in this commit), `unaffected` (in the set but the fix doesn't reach it; say why), `deferred` (separate issue / PR; link it). A member with no verdict is a silent coverage gap. If Phase 1 skipped `vdd-impact.sh` (no code path was named), run it now on the file the fix touches.
3. **Page update** type:
   - **Case A**: invariant was stated on the page + code violated it → fix code, page unchanged
   - **Case B**: invariant was *not* on the page (page stale) → fix code + add invariant to page `decisions:`, blocking future drift
   - **Case C**: user observation matches the invariant (i.e. it really was intended behavior) → no code change + explain to the user "this works as per the X decision in vault"
4. `vdd lint` → 0 errors
5. Add a reproduction test where possible

**Exit criterion**: lint pass + (when code changed) test pass + invariant stated on page.

---

## Anti-patterns (forbidden)

- ❌ Skipping Phase 2 and going straight to code grep
- ❌ "This looks like a simple bug, vault unrelated" — many simple bugs are vault invariant violations
- ❌ Vault read found no invariant → "not in vault, so just look at code" → wrong. **The page is stale**, and after the fix the page must be updated.
- ❌ Committing a code fix without updating the page — the next debugging session will repeat the same maze
- ❌ User wording is ambiguous, so just guess → starting from vault index narrows down layer candidates

## Red Flags — interrupt and return to Phase 1

If any of these thoughts surface, the thought ITSELF is the violation signal:
- "Just one quick code look, then vault"
- "This is too low-level for vault"
- "Vault page is probably inaccurate, code first"
- "User gave me the code path, go straight there"
- "Already 5 minutes in vault and not finding it, time for code"

**All of these are reflex regression to code-first habits.** STOP — the
thought is the trigger to halt and redo Phase 1 layer identification.
NO exceptions without explicit user bypass.

## Common rationalizations

| Rationalization | Why it's wrong |
|---|---|
| "Vault page is short, no answer there" | Short pages state invariants more clearly. Doesn't take 5 minutes. |
| "Code is truth more than vault" | Both must agree. Mismatch = *one of them is wrong* — vault is intent, code is reality. |
| "No time this round, just code quickly" | Code-grep 5 rounds (frustrated user) > vault read 1 round. This case proves it. |
| "grep -r is faster than vault" | grep -r is keyword match, vault read is intent comprehension. Both are different information. |

## Human partner's "you're doing it wrong" signals

- "Why aren't you looking at vault?"
- "Where is the SoT for this?"
- "Why can't you find the obvious?" (← the signal that prompted this skill)
- "Look at the page first, the answer is there"

On any of these signals, return to Phase 1 immediately.

## Quick reference

| Phase | Activity | Success criterion |
|---|---|---|
| **1. Layer identification** | check the index, list 1-3 candidate layers | layer candidate list |
| **2. Page read** | scan conv/decision/invariant for candidate layers | one-line conflict statement |
| **3. Hypothesis** | hypothesis → code trace along the narrowed path | root cause identified or escalate |
| **4. Fix + sync** | code fix + page update | lint pass + invariant stated |

## Relationship to general debugging

vdd-investigate **first**, general debugging **second**:

```
user debugging question
    │
    ▼
vault present?
   YES → vdd-investigate
            │
            ├─ Phase 4 reached → done
            └─ Phase 3 (c) escalate → general debugging
   NO  → general debugging directly
```

When the vault is present, the "pattern analysis / behavior comparison" step of general debugging is largely absorbed by the vault read. The vault is the fast path.

## Real-world impact (case before this skill was introduced)

[2026-05-04 case — locator project]

User: "the dim is shrinking"
- Without vdd-investigate: 5 rounds of code grep, only diagnosed after seeing two user images, user complained "why can't you find the obvious"
- With vdd-investigate: read ui.md (layer page) once → immediately confirm that the painter receives spaceSize → hypothesize "where does spaceSize come from" → trace one code site → fix
- Difference: 5 rounds of guessing vs 1 round of reading. User frustration vs accurate diagnosis.

The ROI of this skill is cumulative — saves 0.5-2 hours per debugging session in projects with a vault, and preserves user trust.
