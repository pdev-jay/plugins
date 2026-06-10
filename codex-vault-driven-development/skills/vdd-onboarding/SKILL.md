---
name: vdd-onboarding
description: |-
  **Internal sub-skill of `vdd-init` — not user-invocable.** Layer page authoring: analyzes existing code (brownfield reverse-extract) or interviews the user on initial layer intent (greenfield), then produces layer page drafts. Auto-detects mode from repo state. Dispatched as Phase 2 of `vdd-init` after `install.sh` has scaffolded `docs/vault/`.
  Rigid:
    - Brownfield branch: outputs are `[UNVERIFIED]` drafts; user reviews + writes Capability boundary by hand (cannot be inferred from code).
    - Greenfield branch: stops at "initial layer list + scaffolded layer pages"; each layer's actual spec is delegated to `vdd-plan` (Mode A) per layer.
    - **Scaffold prerequisite:** this skill assumes `docs/vault/` skeleton already exists.
  Users should invoke `vdd-init` instead — that orchestrator runs `install.sh` first, then dispatches this skill automatically.
user-invocable: false
---

# vdd-onboarding (layer page authoring — greenfield or brownfield)

**Announce on entry:** `▸ vdd-onboarding entry — author layer pages (<brownfield reverse-extract | greenfield interview>)`

> **Sub-skill positioning.** This skill owns layer page authoring only — the
> `docs/vault/` scaffold (just `index.md` — the schema, CONSTRAINTS V-XX, and
> every tool incl. lint are plugin-owned, not copied here) is created by `install.sh`. The orchestrator `vdd-init` calls install.sh first,
> then dispatches this skill. Calling this skill directly assumes the scaffold
> already exists; if it doesn't, the Step 0 install.sh below covers the gap.

Layer page authoring workflow for projects whose vault skeleton exists but
has **no populated layer pages yet**. Two operating modes, auto-detected from
repo state:

| Mode | Trigger condition | Content source | Method |
|---|---|---|---|
| **Brownfield** | repo has substantive code (`src/` / `lib/` / equivalent has non-trivial files) | existing code + git log | reverse-extract via `vault-onboarder` agent → `[UNVERIFIED]` drafts → user verifies |
| **Greenfield** | repo has no code (or only scaffold-level files) | user's stated intent | interview user on initial layer list → scaffold layer pages → delegate each layer's spec to `vdd-plan` Mode A |

The **destination** (a lint-passing `docs/vault/` with layer pages) is identical.
The **direction** differs (code → vault vs. intent → vault).

## When to use

- **Dispatched from `vdd-init` Phase 2** (the normal entry path) — install.sh just ran, scaffold is in place, now author the layer pages.
- **Direct invocation only when scaffold already exists** — e.g. install.sh was run manually in a prior session, or someone scripted the scaffold, and now only the layer authoring step remains.
- Brownfield: documenting the architecture of an existing project from its code + git log.
- Greenfield: capturing initial layer intent for a brand-new project (vault precedes code).

## Boundary vs neighbors

| If the prompt says… | Use |
|---|---|
| **"set up VDD from zero" / "/vdd-init"** | **`vdd-init`** (orchestrator — scaffold + lint + this skill) |
| "vault already exists, add a new feature" | `vdd-plan` Mode A (vault populated) |
| "change broadcasts / state-contract" | `vdd-plan` Mode C |
| "why doesn't X work" / "buggy" | `vdd-investigate` |
| **"scaffold is in place, now draft pages"** | **this skill (direct)** |

(English-only trigger samples; multi-language trigger catalog lives in `description:` frontmatter.)

The discriminator vs `vdd-init` is **scope**: vdd-init owns scaffold + lint + this skill, this skill owns layer page authoring only. If `docs/vault/` doesn't exist, route to vdd-init first. The discriminator vs `vdd-plan` is **vault populated state**: if `docs/vault/` already has layer pages, you don't need onboarding — you need `vdd-plan` Mode A for the new feature.

## Mode detection

Run once at skill entry:

```bash
# Heuristic: substantive code exists?
test -d src/ -o -d lib/ -o -d app/ -o -d packages/ && \
  find . -name "*.dart" -o -name "*.kt" -o -name "*.swift" \
       -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" \
       -o -name "*.go" -o -name "*.rs" 2>/dev/null \
  | grep -v node_modules | grep -v .git | head -20 | wc -l
```

- Result ≥ 5 source files (non-vendored) → **brownfield**
- Result < 5 → **greenfield**
- Ambiguous (config-only repo, monorepo with vendored deps) → ask the user explicitly: *"Is this a brownfield repo (existing code → vaultify) or greenfield (new project, vault first)?"*

The heuristic isn't load-bearing — when in doubt, just ask. The user knows the answer immediately.

## Common steps (both modes)

### Step 0. Install (only when scaffold is missing)

**Normally skipped.** When this skill is dispatched from `vdd-init`, Phase 0
of the orchestrator already ran `install.sh` — the scaffold is present and
verified by `_lint.sh`. Only run install.sh here if **direct invocation** is
detected with a missing scaffold:

```bash
test -d docs/vault || bash "<codex-vdd-plugin-root>/install.sh" "$PWD"
```

The guard ensures idempotency: install.sh is byte-exact + backs up
customizations to `.bak.<ts>`, so re-running is safe, but skipping when
unnecessary keeps the status line honest.

Wiki integration (`wiki-querier` / `wiki-promoter`) activates automatically
when `~/wiki/wiki/` exists.

### Final step. Lint pass

```bash
vdd lint
# target: 0 errors, 0 warnings
```

Regardless of mode, the gate is the same.

---

## Brownfield branch — reverse-extract from code

```
┌──────────────────────────────────────────────────────┐
│  B1. SURVEY                                          │
│      vault-onboarder agent (survey mode)             │
│      → slice list candidates from file tree +        │
│        state classes + git log                       │
│      user confirms scope (all or priority subset)    │
├──────────────────────────────────────────────────────┤
│  B2. DRAFT                                           │
│      vault-onboarder agent (draft mode, parallel     │
│      if ≥3 slices)                                   │
│      → page drafts with [UNVERIFIED] tags            │
├──────────────────────────────────────────────────────┤
│  B3. REVIEW & WRITE                                  │
│      for each [UNVERIFIED]: verify against code,     │
│      remove tag or fix                               │
│      user hand-writes Capability boundary            │
│      (not inferrable from code)                      │
│      vault-suggester agent on remaining thin         │
│      sections for angle hints                        │
├──────────────────────────────────────────────────────┤
│  B4. VERIFY                                          │
│      vault-verifier agent → claim ↔ code consistency │
│      vault-critic agent → prose quality              │
├──────────────────────────────────────────────────────┤
│  B5. WIRING CHECK                                    │
│      _lint.sh regenerates _reverse-index.md          │
│      vdd-blast.sh <key> per broadcast → verify       │
│      reactor wiring                                  │
└──────────────────────────────────────────────────────┘
```

### B1. Survey

Invoke the `vault-onboarder` agent in survey mode:

> "Survey vault slice candidates for this project."

Output:
- **Slice catalog** — slice list with *confirmed slugs* (kebab-case, lowercase, ASCII). These become folder + page names; once confirmed they are the forward-reference targets for all other drafts.
- `code_refs` candidates per slice
- Children candidates per slice (sub-feature page slugs)
- Native bridge presence per slice
- *(not in survey)* broadcast key catalog — broadcast keys are decided at draft time by the slice that owns them; reverse-extracting from code reliably is harder than reverse-extracting slug boundaries, and a wrong guess pollutes every other draft via `reacts_to`. The B2-merge linker pass handles cross-layer broadcast wiring instead.

**User confirms the slug catalog before B2 dispatches.** Renaming a slug after parallel drafts run is expensive — every other draft's `parent` / `children` / `related` wikilinks may become stale. Lock the slug catalog at the user-confirm step (top of B2).

**User decision**: all slices vs. top N priority first.

Recommended priority order:

| Priority | Target | Reason |
|---|---|---|
| 1st | core domain (main features) | other slices reference it |
| 2nd | shared / infrastructure | dependency analysis required |
| 3rd | native-bridges | cross-platform consistency |
| Last | simple UI slices | low vault value |

### B2. Draft

Once scope is confirmed, dispatch `vault-onboarder` in draft mode. Two paths:

**≥3 slices — parallel dispatch (recommended)**

Single message, N Task calls — one subagent per slice. Each subagent receives **only its slice's portion** of the B1 survey output, not the whole thing (context economy + isolation).

```text
role prompt: vault-onboarder
prompt schema:
  "Draft vault page for slice <slice-name>.

   This slice's survey fragment:
     <code_refs candidates, children candidates, native bridge presence — for THIS slice only>

   Confirmed slug catalog (use these for forward wikilinks):
     <slug1>, <slug2>, ..., <slugN>

   Frontmatter rules:
   - title, status, updated, code_refs: fill from survey + your judgment
   - broadcasts: list the state variants THIS slice emits (decide from code; the
     linker pass downstream will match other slices' reacts_to against these)
   - parent / children / related / intent_refs: USE wikilinks against the confirmed
     slug catalog when a relationship exists (forward reference is OK — pages will
     be created at B3 before lint runs at B5)
   - reacts_to / emits_to: LEAVE AS empty array []. The B2-merge linker pass fills
     these by matching against other slices' broadcasts. Do NOT guess.

   Body: per scaffold/AGENTS.md page format. Use [UNVERIFIED] tags liberally for
   claims inferred from code rather than directly observable (intent, conventions,
   boundary)."
```

Slices are independent for *content* drafting — no shared state, no coordination needed. Each subagent runs stateless against its assigned scope (see `vault-onboarder` Core principle #6). Cross-slice *wiring* (broadcast graph) is deferred to B2-merge so subagents don't have to guess across boundaries.

**<3 slices — sequential**

Run drafts back-to-back; parallel overhead exceeds the savings.

### B2-merge. Result intake + linker pass (after parallel dispatch)

When N drafts return, the main LLM does NOT auto-apply. It:

1. **Collects N draft texts** (each is a candidate page body + frontmatter, with `reacts_to: []` / `emits_to: []` left empty by design).
2. **Verifies `[UNVERIFIED]` tag presence** — if a subagent skipped tagging inferred claims, request a redraft for that slice (a draft with zero `[UNVERIFIED]` on a code-extracted page is itself a quality warning).
3. **Linker pass — fill cross-page broadcast graph** (the part subagents could not do without seeing other slices):

   a. **Build broadcast catalog** — collect every `broadcasts:` key declared across the N drafts, with its owning slice:
      ```
      <slice-A>: [key1, key2, ...]
      <slice-B>: [key3, ...]
      ...
      ```
   b. **Match reactors** — for each draft, scan its body + `code_refs` for evidence that this slice *reacts to* keys owned by other slices (e.g. the slice's code subscribes to a stream / listens to a state class whose owner is another slice). Fill `reacts_to:` with the matched `<owner-layer>/_state-contract#<key>` references.
   c. **Match emitters** — similarly identify *indirect* triggers (this slice's broadcast causes another slice to emit) and fill `emits_to:`.
   d. **Flag unresolved** — broadcast keys that nothing reacts to → V-05 orphan candidates; broadcast keys referenced as reactors but no owner declares them → likely missing slice (raise to user).

   The linker pass is main-LLM work, not a subagent — it requires *all N drafts in one view* to make correct cross-references. This is why subagents leave broadcast cross-page fields empty rather than guessing.

4. **Composes a review queue** for the user, ordered by priority (B1's priority table). Options surfaced:
   - **Sequential apply** — review slice 1, apply, then slice 2, ... (default; safest)
   - **Batch apply after full review** — read all N drafts first, apply together
   - **Cherry-pick** — apply some now, defer others as `status: draft`

5. **Stops** — page writes happen only after user review (B3). The drafts (with linker pass applied) live in conversation memory until then.

### Cherry-pick handling — deferred slices

When the user defers a slice (cherry-pick), every *applied* draft that references the deferred slice via `parent` / `children` / `related` / `intent_refs` / `reacts_to` / `emits_to` would create a broken wikilink or orphan reactor at lint time. Mitigation:

- For each *applied* draft, strip any cross-page field entries pointing at *deferred* slugs. Record the strip in that page's `tasks:` as `{todo: "restore reference to <deferred-slice> after its page is applied", priority: med}`.
- When the deferred slice is later applied, re-run the B2-merge linker pass scoped to *that slice + everything already on disk* to restore the stripped references.
- This keeps `_lint.sh` green at every cherry-pick checkpoint — no broken wikilinks, no orphan reactors — at the cost of two linker passes for deferred slices. Acceptable tradeoff.

No race condition is possible at this stage — drafts are not files; they become files only at B3 when the user has chosen what to apply.

### B3. Review & Write

For every `[UNVERIFIED]` item:
- open the code and verify
- if correct, remove the tag
- if wrong, fix it then remove the tag
- **Capability boundary must be written by the user** (cannot be inferred from code)

Invoke `vault-suggester` agent on each drafted page for remaining empty / thin sections — it gives angle hints (where to pull material from), it does not draft prose.

File authoring order:
1. `_state-contract.md` first (broadcasts definition is the baseline)
2. each slice's `<slice>.md`
3. sub-feature pages

### B4. Verify

```text
vault-verifier agent → claim ↔ code cross-check
vault-critic agent → prose quality (filler, empty WHY, missing ASCII diagrams)
```

**Parallel when ≥3 slices were drafted.** Both agents are read-only — dispatch one subagent per slice in a single message with multiple Task calls (mirror of B2 's parallel draft pattern; see `vdd-review` § Mode B Step 2 batch dispatch for the orchestration template). Merge N reports → single consolidated audit before B5. <3 slices → sequential (single-pass).

### B5. Wiring check

After all slice pages are complete:

- `vdd lint` regenerates `_reverse-index.md` and flags orphan broadcasts (V-05)
- `vdd blast <key>` per broadcast → confirm reactor wiring
- Resolve every orphan-broadcast warning — declare a reactor page or mark `TBD — see <issue>`

---

## Greenfield branch — forward-design from intent

```
┌──────────────────────────────────────────────────────┐
│  G1. INTERVIEW                                       │
│      ask: "which layer / slice to start with?"       │
│      capture: initial layer names + one-line intent  │
│      per layer (NOT full spec — that's vdd-plan Mode A)     │
├──────────────────────────────────────────────────────┤
│  G2. SCAFFOLD                                        │
│      for each layer:                                 │
│        vdd bootstrap <layer>  │
│      → creates docs/vault/<layer>/<layer>.md with    │
│        minimal frontmatter + section headers         │
├──────────────────────────────────────────────────────┤
│  G3. INDEX FILL                                      │
│      Edit docs/vault/index.md → add each layer with  │
│      its one-line intent                             │
├──────────────────────────────────────────────────────┤
│  G4. HANDOFF                                         │
│      For each layer the user wants to flesh out NOW: │
│        invoke vdd-plan Mode A (it owns spec authoring)      │
│      Layers the user wants to defer:                 │
│        leave as scaffolded skeleton (status: draft)  │
│      No [UNVERIFIED] tags — there's nothing to       │
│      verify yet (no code to compare against)         │
└──────────────────────────────────────────────────────┘
```

### G1. Interview

Ask the user (in their language — the example below is the English template):

> *"This project starts from the vault. Which layers do you want to begin with?
> Just a one-line intent per layer. The detailed spec gets filled in by
> `vdd-plan Mode A` in the next step."*

Capture per layer:
- **slug** (kebab-case, lowercase) — becomes folder + page name
- **one-line intent** — what this layer owns

If the user is unsure, suggest 2-3 canonical starting layers based on project type (`auth` / `ui` / `data` for typical app; `infrastructure` / `bridges` for cross-platform), but don't impose — the user decides.

**Do NOT** demand a full design. The Capability boundary and full spec are `vdd-plan Mode A`'s job. This step is "what folders should exist on day 1".

### G2. Scaffold

For each layer:

```bash
vdd bootstrap <layer-slug>
```

Creates `docs/vault/<layer>/<layer>.md` with skeleton frontmatter and section headers. No prose content — the user (via `vdd-plan Mode A`) fills.

### G3. Index fill

Edit `docs/vault/index.md` to list each new layer with its one-line intent. This becomes the project instruction inject content for future sessions.

### G4. Handoff

For each layer:
- **Flesh out now** → invoke `vdd-plan Mode A` for that layer. vdd-plan Mode A owns spec authoring (Capability boundary, Architectural conventions, Flow, decisions). This skill does NOT duplicate that work.
- **Defer** → leave the scaffolded page with `status: draft` and `tasks: [{todo: "fill spec via vdd-plan Mode A", priority: med}]`. Future sessions pick it up.

**No `[UNVERIFIED]` tags in greenfield** — those mark *extracted* claims pending verification. Greenfield content is *declared*, not extracted; the user's intent is the SoT.

---

## Progress checklist

### Brownfield

```
[ ] install.sh complete
[ ] survey → slice list confirmed
[ ] drafts generated
[ ] all [UNVERIFIED] tags removed
[ ] all Capability boundaries written by user
[ ] vault-verifier passed
[ ] vault-critic passed (no 🔴 issues)
[ ] vdd lint 0/0
[ ] no orphan-broadcast warnings (V-05)
[ ] vdd-blast.sh reactor wiring verified per broadcast key
```

### Greenfield

```
[ ] install.sh complete
[ ] initial layer list confirmed with user (slug + one-line intent each)
[ ] bootstrap.sh run per layer → skeleton pages exist
[ ] docs/vault/index.md lists each layer
[ ] for each layer the user wants fleshed out now: vdd-plan Mode A invoked
[ ] deferred layers marked status: draft + tasks
[ ] vdd lint 0/0 (skeleton pages must still pass lint)
```

## Anti-patterns

### Common to both modes

- **Empty Capability boundary on an "active" page** — the most important section. If you can't write it yet, set `status: draft` and defer.
- **Layer-based pages by tech tier** — `domain/` / `infra/` / `presentation/` splits don't belong in the vault. Use feature / vertical slices.
- **All slices at once** — attempting everything without prioritization produces half-finished pages.

### Brownfield-specific

- **Leaving `[UNVERIFIED]` tags** — drafts are drafts. Don't commit before verification.
- **Trusting agent-drafted Capability boundary** — the agent guesses from code. The boundary is user's call.

### Greenfield-specific

- **Authoring full layer spec inside this skill** — that's `vdd-plan Mode A`'s domain. This skill stops at "scaffold exists, intent captured, handoff signaled".
- **Inventing `[UNVERIFIED]` tags** — there's nothing to verify. The user's stated intent IS the truth at this stage.
- **Demanding a complete layer list upfront** — start with what the user knows, defer the rest. Vault is iterative.

## Library-project specifics (brownfield)

A library (consumed by other projects) differs from an app project:

- `_state-contract.md` acts as the **public API contract**
  - documents the interface consumed by downstream projects
  - record breaking-change history under `decisions:`
- `code_refs` should prioritize public interface files
- the consuming project's project AGENTS.md instruction can inject this vault path

## Integration flow

```
vdd-onboarding
   │
   ├── brownfield → vdd-plan (Mode A for new features, Mode C for contract changes)
   │
   └── greenfield → vdd-plan Mode A per layer (handoff at G4)
                       │
                       └── then vdd-plan → vdd-build → vdd-review → vdd-done
```

After onboarding, **vdd-plan** owns new-feature work (Mode A) and broadcast-graph changes (Mode C). This skill's job ends once the vault is bootstrapped.

## Vault page structure (reference)

The standard pattern is a vertical-slice layout (applies to both modes):

```
docs/vault/
├── <feature>/                ← vertical slice unit (not a tech-tier layer)
│   ├── <feature>.md          ← zoom:0, layer index
│   ├── _state-contract.md    ← this layer's broadcasts definition
│   └── <sub-feature>.md      ← zoom:1+, sub-feature
├── infrastructure/           ← shared infra (HTTP, storage, etc.)
├── native-bridges/           ← platform bridges (where applicable)
├── index.md
└── _reverse-index.md         ← auto-generated cross-layer broadcast map
```

### Required frontmatter

```yaml
---
title: <human readable>
zoom: 0                         # 0=layer index, 1=feature, 2=detail
parent: null                    # null or [[<parent-slug>]]
children: [slug1, slug2]        # child page slugs
broadcasts:                     # state variants this layer emits
  - initial
  - loading
  - loaded
  - error
code_refs:                      # implementation file paths (brownfield: filled at draft; greenfield: filled as code lands)
  - <actual feature folder path>
status: active                  # draft | in_progress | active
updated: YYYY-MM-DD
---
```

### Page body structure (zoom: 0)

1. **One-line summary** — what this slice does
2. **Structure** — ASCII tree (children + `_state-contract`)
3. **Flow** — ASCII diagram (event → state transition or data flow)
4. **Capability boundary** — owns / does NOT own
5. **Architectural conventions** — invariants for this slice
6. **Open issues / drift watch**

★ ASCII only (no Mermaid). Box chars: `─ │ ┌ ┐ └ ┘ ├ ┤ ▼ ◄ ►`
