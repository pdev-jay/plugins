---
name: vdd-explain
description: |
  All lookup intent about existing code/features/libraries/structure/conventions. Covers vague paraphrases in either language: "뭐 함/어디 있어/어떻게 돌아가/이미 있나/이거 뭐임/비슷한 거/예전에 어떻게 했더라/원래 누가 처리하더라/직접 짜기 전에/이 프로젝트 어떻게" / "what does X do/where is X/how does X work/is there already one/what is this/anything similar/how did we do this before/who handles this/before I write from scratch/how does this project work". Reads vault SoT first → code → external, answers with citations. Explicit bug signals → vdd-investigate; new feature/design intent → vdd-plan.
---

# vdd-explain — vault → code → external lookup

**Announce on entry:** `▸ vdd-explain entry — answer from vault SoT first, code/external on a vault miss (<the question's subject>)`.

A workflow for projects with a vault: when the user asks an informational question — *without* signaling something is broken — answer from the vault SoT first, fall back to code or external search only when vault has no hit.

## Why this skill

The vault holds **intent, conventions, and decisions** that code cannot tell you. For "what is X" / "how does X work" / "is there already a tool for Y" questions, the vault answer is usually:

- Faster (one page Read vs N code Reads).
- Higher-fidelity (states the WHY, not just the mechanism).
- Citable (the answer points at a SoT page the user can verify).

But unlike `vdd-investigate`, the cost-benefit of a HARD-GATE is weaker here — many lookup questions are genuinely outside vault scope (build tooling, dependency versions, env config). So this skill is **flexible**: vault-first by default, code / external fallback on miss, no refusal.

## Three flavors (same procedure, different fallback)

| Flavor | User phrasing | Fallback when vault is silent |
|---|---|---|
| **Structure / behavior** | "what does X do", "where is X", "how does X work" | Code grep (`Grep`, `Read`) |
| **Existing solution scan** | "is there a library for X", "any existing tool", "anything similar?" | Project grep → MCP → npm / pub / maven → GitHub → web |
| **Boundary / convention** | "why is X like this", "what's the X layer about" | `decisions:` + § Conventions on the layer page; if absent → flag drift |

The procedure is identical; only the fallback path differs.

## Boundary vs neighbors

| If the prompt says… | Use |
|---|---|
| "why doesn't X work", "broken", "weird", "X keeps vanishing" | `vdd-investigate` (HARD-GATE — failure signal) |
| **"what does X do", "where is X", "how does X work", "explain X", "is there a library for X"** | **this skill** |
| "add X feature", "build Y", "implement Z" | `vdd-plan` (Mode A) |
| "what's the blast radius of this change" | `vdd-plan` (Mode C) |
| "verify", "all green?", "vault drift?" | `vdd-review` |
| "why is build / test / lint failing" | general build/type troubleshooting |

The discriminator vs `vdd-investigate` is **failure signal**. If the user is reporting unexpected behavior, that is `vdd-investigate`. If they are asking *what / where / how / is-there*, that is this skill.

## Procedure

Flexible — no HARD-GATE. Steps are preferred order, not a gate.

### Step 1 — Vault index

Read `docs/vault/index.md`. Enumerate layers. Identify candidate layer(s) for the question.

- MCP available → `mcp__obsidian-vault__read_note "index"`.
- Fallback → `Read docs/vault/index.md`.

If `docs/vault/` doesn't exist → skip to Step 4 directly (no vault to consult).

### Step 2 — Vault keyword scan (co-equal SoT)

For each user-supplied noun / verb, search across ALL vault SoT files — layer pages, state contracts, `_reverse-index.md`, `_decisions.md` are co-equal targets.

- MCP available → `mcp__obsidian-vault__search_notes "<keyword>"` (BM25).
- Fallback → `grep -rliF "<keyword>" docs/vault/ --include='*.md'`.

The hit set narrows which pages own the answer. **Trust the hit set over your initial layer guess** — index keyword-matching is fragile.

### Step 3 — Candidate page Read

Read the hit pages from Step 2 (or the layer page from Step 1 if no keyword hit). Scan in this order:

1. **§ Capability boundary** — what this layer owns / does not own.
2. **§ Architectural conventions** — invariants the layer enforces.
3. **decisions:** (frontmatter) — recorded rationale.
4. **§ Flow** / **§ End-to-end flow** — the mechanism diagram.
5. **`code_refs:`** — anchor symbols for follow-up code Read if needed.

For "how does X work", the Flow section + `code_refs:` anchor is usually the answer. For "what is X", boundary + conventions usually suffice. For "why is X like this", `decisions:` is the SoT.

### Step 4 — Fallback by flavor

If vault Steps 1–3 do not answer the question, choose fallback by flavor:

#### 4a. Structure / behavior flavor — code

- `Grep` / `Read` the symbol or path.
- Cite the file + line range in the answer.

#### 4b. Existing solution scan flavor — external registries

Order (stop at first concrete hit):

1. **Project grep** — `rg` related modules / tests. Verify symbol / utility doesn't already exist.
2. **Package registry** — npm / PyPI / pub.dev / Maven Central. Search by capability keyword.
3. **MCP server** — check configured MCP servers that match the capability.
4. **Skills catalog** — `~/.claude/skills/` for installed Claude skills.
5. **GitHub** — OSS implementation search.
6. **Web** — general search if registry / GitHub returns nothing.

**Decision matrix:**

| Signal | Action |
|---|---|
| Exact match, well-maintained, MIT/Apache | **Adopt** — install and use as-is |
| Partial match, solid foundation | **Extend** — install + thin wrapper |
| Multiple weak matches | **Compose** — combine 2–3 small packages |
| Nothing fits | **Build** — write it yourself, informed by the research |

**No-guessing policy** — when reporting candidates, label each:

- `verified` — confirmed via grep / file read / registry hit.
- `needs verification` — explicit flag that you didn't verify.
- `vault reference: <layer>.md` — pulled from vault SoT.
- ❌ "should be fine" / "probably works" / "as I recall" — forbidden.

#### 4c. Boundary / convention flavor — drift flag

If the topic is architectural and the layer page is silent on it:

> "Vault has no page / section on this — likely drift. The code shows <X>, but architectural intent is not documented. Consider adding to `<layer>/<layer>.md` § Architectural conventions or running `vault-suggester` to identify the gap."

Silent code-only answers let the vault rot — always flag.

### Step 5 — Answer with citation

Compose the response. Two rules:

- **Cite the page.** Name the file path (`docs/vault/auth/auth.md`, § Capability boundary). The user must be able to verify the source. This is what separates a vault-grounded answer from a guess.
- **Don't paraphrase code.** If the answer requires showing code mechanism, *quote* the symbol from `code_refs:` rather than narrating it. Vault explains WHY; code is WHAT.

If multiple pages contributed, cite each.

## Quick reference

| Step | Tool (MCP-default) | Tool (filesystem fallback) |
|---|---|---|
| 1. Index | `mcp__obsidian-vault__read_note "index"` | `Read docs/vault/index.md` |
| 2. Keyword scan | `mcp__obsidian-vault__search_notes "<kw>"` | `grep -rliF "<kw>" docs/vault/` |
| 3. Page Read | `mcp__obsidian-vault__read_note "<layer>/<page>"` | `Read docs/vault/<layer>/<page>.md` |
| 3b. Drill into a *large* page | `mcp__obsidian-vault__search_notes "<kw>"` / `Read` + `offset` | `grep -n` narrow pattern + `head` — never broad `A\|B\|C…` (dumps prose, ~5K tok) |
| 4a. Code fallback | — | `Grep` / `Read` |
| 4b. External | — | `rg`, registry search, MCP, web |
| 4c. Drift flag | — | (compose response) |
| 5. Cite | — | — |

## Examples

### Example 1 — Structure / behavior

> User: "where is auth?"

```
1. read_note "index" → enumerate layers, find auth layer
2. search_notes "auth" → docs/vault/auth/auth.md hit
3. read_note "auth/auth" → § Capability boundary + § Flow
5. Answer: "auth layer is at docs/vault/auth/. Capability boundary in
   auth/auth.md § Capability boundary: 'owns login + token refresh + role
   switching'. Code anchors in code_refs: auth_bloc.dart#AuthBloc."
```

### Example 2 — Existing solution scan

> User: "is there a library for dead-link checking?"

```
1. read_note "index" → docs/quality layer exists
2. search_notes "dead link" → no hit in vault
3. (vault silent on link checking — proceed to fallback)
4b. rg "dead.?link" → no project utility
    npm search "markdown dead link checker" → textlint-rule-no-dead-link (verified, maintained)
5. Answer: "Vault has no page for link checking (potential drift if quality
   layer should own this). External: textlint-rule-no-dead-link (verified,
   MIT, maintained 2025) — Adopt with `npm install textlint-rule-no-dead-link`."
```

### Example 3 — Boundary / convention (drift flag)

> User: "why does the passage detector live in native?"

```
1. read_note "index" → positioning layer is candidate
2. search_notes "passage" → docs/vault/positioning/positioning.md hit
3. read_note "positioning/positioning" → decisions: frontmatter has the rationale
5. Answer: "Per positioning/positioning.md decisions: '2026-05-15 — PassageDetector
   lives in native; host mirrors via enum. Why: avoid drift between platforms.'
   The host runtime keeps an enum copy for parity."
```

## Anti-patterns

- ❌ Skipping Step 1–2 and jumping to code / web because "it's just a quick question". If `docs/vault/` exists, the vault read is one page Read — cheaper than an exploratory grep round.
- ❌ Citing layer pages by name but not quoting the actual section. The user can't audit "I read auth.md" — they need "auth.md § Architectural conventions states …".
- ❌ Treating a vault-hit page as decoration ("the vault says X, and now let me grep code anyway"). If vault answered, stop. Grep only if vault was incomplete.
- ❌ Silently answering from code or external sources when vault is silent on an *architectural* topic. Always flag the drift.
- ❌ Using this skill for failure reports. "Why doesn't X work" / "X is broken" → `vdd-investigate`.
- ❌ External-solution scan without project grep first — reinventing what the project already has.
- ❌ Adopting a library based on registry stars alone — `verified` requires a doc read or repo scan, not a count.

## Relationship to Rule 0

This skill is the **read-only variant** of Rule 0. Rule 0 routes every code/vault action through a phase skill; this skill is the one whose action *is* the answer itself, not an edit — the same vault-grounded flow without the edit step at the end.

The discipline is the model's responsibility — there is no hook backstop. The only enforcement is the user noticing missing citations: every claim cites a vault page path, and a vault-grounded answer without that citation is itself the violation signal.
