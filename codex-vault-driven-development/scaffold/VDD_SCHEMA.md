# vault — per-project schema (this file is loaded into Claude's context for vault work)

You are the maintainer of this project's **vault** — the descriptive Source of Truth for architecture, intent, progress, decisions, and cross-layer state contracts.

This file is the operating manual. Read it at the start of every vault-related session.

---

## What vault is for

Three concrete jobs:

1. **Architectural intent capture** — page bodies describe WHY a layer exists, what it owns, what conventions apply, what NOT to do. Code can't tell you these.
2. **Cross-layer impact map** — `broadcasts` / `reacts_to` / `emits_to` frontmatter + `_reverse-index.md` answer "if I change X, who's affected?" in one grep.
3. **Narrative state** — page frontmatter `status` / `tasks` / `decisions` replace separate PROGRESS.md / task_ledger.json / per-feature MEMORY.md files.

If a piece of information doesn't fit one of those three jobs, it doesn't belong here.

---

## Rule 0 — phase skill first; the skill reads the vault

**Before any code or vault change, INVOKE the matching phase skill — do NOT read the vault yourself and then edit inline.** The full Rule 0 router (intent → skill table, Red-flags, exceptions, decision-conflict handler) lives in the **`vdd-workflow` skill's `<EXTREMELY_IMPORTANT>` block** — that is the enforcement surface, reinforced by `CONSTRAINTS.md` (V-01) and the `project instruction` hook. This file is the vault *schema* manual, not the router; it does not restate the gate.

---

## Hard rules

1. **One layer = one folder under `docs/vault/`.** Each layer has a `<layer>.md` index page (zoom 0).
2. **Filename = slug.** Lowercase, hyphenated, ASCII. Match the H1 title.
3. **Folder name = layer index file name.** `auth/auth.md`, not `auth/_index.md` (Obsidian wikilinks resolve by basename — keep them unique).
4. **System pages prefix with `_`.** `_state-contract.md`, `_lint.sh`, `_reverse-index.md` — distinguishes from feature pages.
5. **Never delete a page silently.** Move to `_archive/` and update frontmatter `status: deprecated` with rationale.
6. **Every page has frontmatter.** Even trivial pages. Frontmatter is the lint contract.
7. **Lint must pass before commit.** `vdd lint` exits 0.
8. **`code_refs` are anchors, not narrative.** Symbol-level (`#SymbolName`) preferred over line numbers (`#L42-L80`) — symbols rot less.
9. **Trivial pages stay trivial.** Don't pad WHY for the sake of structure. 5–15 line body is OK if that's all you can honestly say.
10. **Cross-platform parity is first-class.** When a layer has multiple platform-specific native counterparts (e.g. two mobile OS targets, host + native, multiple OS targets), document them side-by-side with a parity table. Drift is silent failure.

---

## Page format

```yaml
---
title: <human readable title>
zoom: 0|1|2|...                  # parent chain depth from layer (0 = layer index)
parent: [[wikilink]] | null      # null only for layer index pages
children:                         # quick navigation list
  - <slug>
status: active|draft|deprecated|in_progress
broadcasts:                       # signals this page emits (layer-scoped names; sub-stream OK e.g. 'phase:idle')
  - <key>
reacts_to:                        # signals this page subscribes to
  - <layer>/_state-contract#<key>
emits_to:                         # signals this page indirectly triggers
  - <layer>/_state-contract#<key>
depends_on:                       # structural code dependencies (non-anchor)
  - <path>
intent_refs:                      # vault pages whose decisions/conventions constrain this page — a design-time intent dependency. NOT a runtime signal (reacts_to), NOT a vague see-also (related). vdd-impact.sh follows these transitively to compute the full impact closure.
  - [[<layer>/<page>]]
related:                          # non-hierarchical links
  - [[wikilink]]
branch_from: [[wikilink]]         # for side-branch pages (parent: null + branch_from)
shared_by:                        # if this page is a shared sub-flow
  - [[wikilink]]
code_refs:
  - path/file.dart#SymbolName
tasks:                             # this page's TODOs (becomes _open-issues + _progress)
  - {todo: "verify platform-B side", priority: high|med|low}
decisions:                         # constraints on future work — NOT an event log. record test (V-04): "would a future worker, not knowing this, take a wrong turn or reintroduce a bug?". if no → it's history (the result is in the code), don't record.
                                   # note: ≤200 chars, one line; archive past ~25 active entries (V-08)
                                   # prefer WHY + the condition it holds under: "<decision> — <why>; holds while <condition>".
                                   # a conditionless conclusion is easy to consume as a verdict on zoom-in; the condition cues re-evaluation. (soft convention)
  - {date: 2026-04-30, note: "PassageDetector lives in native, host runtime mirrors via enum; holds while passage logic stays native-only"}
updated: YYYY-MM-DD
reviewed_at: YYYY-MM-DD             # optional — last /vdd-review date (written by `_lint.sh --stamp`)
reviewed_code_hash: <sha256>        # optional — code_refs content fingerprint at last review; Check 14 (V-10) warns on mismatch
---
```

**YAML style — block-style arrays canonical.** Use `key:` followed by `  - item` lines (as shown above) rather than inline `key: [item, ...]`. Both styles are accepted by `_lint.sh` and `vdd-blast.sh`, but block-style is the canonical form because:

- Diff-friendly — adding/removing one item is a single-line change.
- Anchors are clearer — `auth/_state-contract#auth:reconnecting` reads better on its own line than inside `[...]`.
- Quotes rarely needed — keys with `:` like `phase:idle` don't need quoting in block-style values.

Empty arrays use the inline literal `key: []`. Inline-array values with multiple items (`key: [a, b]`) are tolerated for parity but are not the recommended form.

Field order: `title` → `zoom` → `parent` → `children` → `status` → broadcast graph fields → `intent_refs` → `code_refs` → `tasks` → `decisions` → `updated` → `reviewed_at` / `reviewed_code_hash` (optional, written by `--stamp`).

After frontmatter: H1 (matching `title`), then body.

---

## Body sections (recommended, in this order)

For layer pages (zoom 0):
1. One-paragraph capability summary
2. **Structure** — ASCII tree of children (+ shared sub-flows / state-contract). Trivial layers (1 page only) can write `(no zoom-in)` instead of a tree.
3. **Flow** — ASCII diagram of the layer's primary mechanism. Pick the fitting kind: *broadcast flow* (state-contract heavy, e.g. auth), *state machine* (phase-driven), *sequence/pipeline* (chains), *decision tree* (pattern dispatch). Skip if the layer is a thin index with no mechanism.
4. **Capability boundary** — what this layer owns / does NOT own
5. **Children (zoom-in)** — wikilinks to feature pages
6. **Architectural conventions** — invariants this layer enforces
7. **Cross-layer dependencies** — what this layer depends on / who depends on it
8. **Open issues / drift watch** — things that need attention
9. **decisions archive** *(only if at least one decision has been reversed)* —
   replaced `decisions:` entries live here, NOT in frontmatter. See the
   "Decision replace + archive" subsection below.

**ASCII diagram rules**: box-drawing connectors `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ▼ ▲ ◄ ►` only — **no Mermaid** (terminal-readable, diff-friendly). Annotate edges with the broadcast/event name (`──► loaded`); mark hot risks `★`, divergences `⚠`.

For feature/sub-flow pages (zoom 1+):
1. **End-to-end flow** — ASCII diagram for non-trivial flows
2. **Logic flow** — step-by-step
3. **Why this is the boundary** — the WHY corpus
4. **What is NOT here** — explicit anti-scope
5. **Code references** — symbol anchors

For state-contract pages (`_state-contract.md`):
1. **State variants** — table of variant + payload + meaning
2. **Phase/transition diagrams** — when applicable
3. **Critical conventions** — non-obvious rules (e.g., failureCode reset before retry)
4. **Reactor matrix** — who reacts and how

---

## Workflow

The step-by-step procedures (adding a feature, refactoring across layers, discovering drift) are owned by the phase skills — `vdd-plan` → `vdd-build` → `vdd-review` → `vdd-done`. This file defines the page *format* those skills write; it does not restate their procedures. The one invariant that lives here: **spec-first** — the feature page (`## End-to-end flow` + `## Why`) is authored before or alongside the code, never after.

---

## Cross-platform parity

For projects with multiple platform-specific native counterparts (mobile OS pair, host + native, or other multi-platform setups):

- Document parity in a single page per layer (not separate per-platform pages, unless they diverge significantly).
- Use a parity table: rows = aspects, columns = platforms.
- Mark divergence explicitly with ⚠ or ❌. Drift here is silent failure.

Example:

```markdown
| Aspect | Platform A | Platform B | Match |
|---|---|---|---|
| State enum | `IDLE/ENTERED/EXITED` | `idle/entered/exited` | ✓ (case only) |
| EMA alpha | `0.3` | `0.3` | ✓ |
| Sideeffect isolation | error-isolated | (none) | ⚠ diff |
```

---

## What lint validates

`vdd lint` (the plugin's `_lint.sh`) checks:

1. **frontmatter** — every page starts with `---`; pages must be LF-only (a CRLF vault page is an error — the parsers normalize it for extraction, but it is silently fragile across tools)
2. **wikilinks** — every `[[name]]` resolves to a `name.md` file (basename match); covers body links and frontmatter wikilinks alike (`parent` / `related` / `intent_refs`). Page basenames must be unique (Hard Rule 3 — a collision silently resolves links / `vdd-impact` closures to the wrong page; duplicate basename is an error). **Exception**: `_`-prefixed system pages (`_state-contract.md`, etc.) living inside a layer folder are convention-by-design — each layer carries its own copy. These collisions are PASSED with an INFO note. **But**: bare references like `[[_state-contract]]` are then **ambiguous** (which layer?) and are an ERROR — always write them as full path `[[<layer>/_state-contract]]` (e.g. `[[auth/_state-contract]]`, `[[connection/_state-contract]]`). The same applies in body prose, frontmatter `parent` / `related` / `intent_refs`, and ASCII diagrams.
3. **code_refs** — paths exist (file or directory); a missing path is an **error** (exit 1, blocks the V-06 lint-PASS gate — a dead reference makes the page's anchors lies). `#SymbolName` anchors are validated by two-tier grep (broad presence + multi-language declaration heuristic) and stay **warnings** (rare-language / rename false-positives)
4. **broadcast keys** — every `reacts_to` / `emits_to` references a key declared in some `broadcasts:` list; an undefined-key reference is an **error** (exit 1, blocks V-06 — a dangling reactor edge waits at runtime for a key no one emits). `_signals:*` are layer-internal and exempt. Additionally, a page that declares a `broadcasts:` key whose token is absent from *every* one of its own `code_refs` files is **warned** (V-09 — contract→code drift; heuristic, never an error; pages with no concrete `code_refs` file are skipped). The binding cross-artifact verdict is the `vdd-review` skill (Mode B — Analyze)
5. **reverse-index generation** — auto-creates `_reverse-index.md` from current frontmatter
6. **rollups** — `_progress.md` (status + tasks), `_decisions.md` (chronological), `_open-issues.md` (drift-watch)
7. **review freshness** — for pages carrying `reviewed_code_hash` (set by `--stamp` on a passing `/vdd-review`), warns when the content fingerprint of the page's `code_refs` no longer matches the reviewed one (V-10). Pure WARN, never blocks, content-based (no git — fresh right after review, survives clone/rebase). Re-stamp after re-reviewing: `vdd lint --stamp <page>`. Also warns when active `decisions:` exceed the count cap (~25 — V-08 archival nudge).

---

## Anti-patterns to avoid

- **Padding trivial pages.** If a feature is genuinely a thin dispatch, write 5 lines and move on. Don't manufacture WHY content.
- **Mirroring code structure.** Vault is *intent*, not a code map. If your layer organization mirrors `lib/features/` 1:1, you're probably under-thinking.
- **Forgetting `What is NOT here`.** Most vault drift comes from layer scope expanding without explicit "this layer doesn't do X" guards.
- **Documenting the wrong thing.** Code-paraphrase ("this function calls that function") is wasteful. Capture WHY (decisions, conventions, sideeffects).
- **Skipping state contracts for stateful BLoCs/services.** Without `_state-contract.md`, cross-layer impact is invisible.

---

## Logging convention (in `decisions:` frontmatter)

**Record only constraint-bearing decisions (V-04).** Before logging, apply the record
test: *"would a future worker editing this area, not knowing this, take a wrong turn or
reintroduce a bug?"* If no, it's history — the result is in the code; don't record it.
`decisions:` is a harness on future work, not a changelog.

```yaml
decisions:
  - date: 2026-04-30
    note: "<one-line decision>. Rationale: <why>. Affected: <which pages>."
```

**`note` is ≤200 chars, single line.** `_lint.sh` Check 12 warns above 200. Longer rationale belongs in commit message body or in the page body's § decisions paragraph — not in frontmatter.

Good:

```yaml
- date: 2026-05-15
  note: "PassageDetector lives in native; host mirrors via enum. Why: avoid drift between platforms."
```

Bad (narrative — moves to body or commit):

```yaml
- date: 2026-05-15
  note: "We initially considered putting PassageDetector in the host runtime, but after analysis we decided to keep it in native because of A, B, C, D… [continues 400+ chars]"
```

`_lint.sh` rolls these up chronologically into `_decisions.md`. Bloated notes turn the rollup into a narrative dump and break the chronological scan it exists for.

### Decision replace + archive — body format

When a decision is overturned, the **procedure** (detect conflict → halt → surface → replace + archive) is owned by the `vdd-workflow` Decision-conflict handler and executed by `vdd-log` (V-04). This file defines only the body *format* the archived entry takes:

```markdown
## decisions archive

### YYYY-MM-DD — <one-line title of the old decision>

**Note (frontmatter as it stood):** "<original note verbatim>"

**Replaced YYYY-MM-DD:** <one-clause why it changed>. See current entry in `decisions:` frontmatter dated <new-date>.
```

Archive bodies are prose — V-08's ≤200 char limit on `decisions[*].note` does NOT apply here; expand the reason fully. **Refinement is NOT reversal**: narrowing / extending the same direction is a normal append, not an archive. If the archive section grows past ~200 body lines, escalate to the **archive child page** pattern below.

### Archive pattern — when a layer accumulates many decisions

If a layer page collects so many decisions that even one-line trims cannot keep `decisions:` under 100 entries (long-running layers, research-heavy modules), use the **archive child page** pattern instead of cramming frontmatter:

1. Create `<layer>/decision-log.md` (zoom: 1, parent: `[[<layer>]]`, `decisions: []`).
2. Move each rationale into the body as `## YYYY-MM-DD — <title>` heading + paragraph.
3. Set the layer page's `decisions: []  # archived → [[decision-log]] (V-08)` and add `decision-log` to its `children:`.
4. `_lint.sh` Section 6 has a body-heading fallback: when frontmatter `decisions:` is empty, it scans body `## YYYY-MM-DD — title` (or `### …`) headings and folds them into the chronological `_decisions.md` rollup. So the archive page stays scannable in the rollup without forcing narrative back into frontmatter.

This is the canonical V-08 escape valve for layers like `positioning/` that accumulate sweep results and design rationale over weeks.

---

## Tone for vault prose

- **Declarative, not chatty.** "X is Y" not "It seems X might be Y".
- **No filler.** Every sentence carries a fact, definition, or citation.
- **Language follows project preference.** Match the project's existing docs.
- **No code paraphrase.** If a sentence can be replaced by `cat path/file.dart`, delete it.

---

## Escalation

- Cross-layer impact unclear → run `_lint.sh`, check `_reverse-index.md`. If still unclear, escalate to user.
- New layer needed → propose to user before creating folder.
- Schema doesn't fit → escalate (don't invent fields silently).
- Cross-platform divergence found → escalate immediately + document in parity table.

---

## Optional Obsidian MCP

The vault is plain markdown with **no Obsidian dependency** — filesystem tools (`Read` / `Grep` / `Edit`) are the always-available primary path. If an Obsidian MCP server is exposed (`mcp__*obsidian*__*`), the read/write tool-routing table is in the global `~/.claude/AGENTS.md`. The vault-critical hard rule:

**Vault writes — byte-level tools only.** Any MCP write tool that routes through a YAML serializer (`update_frontmatter`, `write_note --frontmatter`, `manage_tags`) re-emits frontmatter and silently mutates formatting (broadcast keys gain quotes, flow collapses to block, dates normalize) — `_lint.sh` parses with awk (no YAML lib) and breaks on these → false-positive errors. Allowed: `Edit` / `Write` / `MultiEdit` and `patch_note` (byte-level, but use `Edit` for frontmatter). Forbidden: `write_note --frontmatter`, `update_frontmatter`, `manage_tags`, `delete_note`, `move_note`, `move_file`. Deterministic CLI scripts (`vdd-plan.sh`, `vdd-blast.sh`, `_lint.sh`) remain SoT; MCP is read-side corroboration, never a replacement.
