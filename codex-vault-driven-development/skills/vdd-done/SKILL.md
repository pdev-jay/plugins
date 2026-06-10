---
name: vdd-done
description: |
  All intent to close a work stage / wrap up / commit. Covers either language: "다 됐어/끝났어/마무리/정리해/정리하고 가자/이제 됐다/커밋하자/커밋 메시지/PR 올리자/통과 확인하고 커밋" / "done/finished/wrap up/ship it/are we done?/let's commit/commit message/let's PR/verify and commit/call it a day". Delegates verification to vdd-review, harvests decisions, runs vault lint, suggests a commit message (does NOT auto-commit). Single decision recording → vdd-log; verification only → vdd-review.
---

# vdd-done — Wrap-up workflow

**Announce on entry:** `▸ vdd-done entry — CONSTRAINTS gate → change summary → decision harvest → commit message (<targets completed this session>)`

## CONSTRAINTS gate (run FIRST, before everything else)

Read the plugin-owned **CONSTRAINTS V-XX** (its absolute path is injected at
project instruction — there is no `docs/vault/CONSTRAINTS.md`) and validate each
applicable V-XX before any "done / committed / wrap up" output. This is the procedural enforcement that
replaces blocking hooks — if a V-XX is unsatisfied, vdd-done refuses to produce
a commit message and surfaces the rule number.

- **V-01** — for every code file edited this session, was the owning vault
  page Read at least once? If not, Read it now (or document why bypass was
  legitimate via `VAULT_GATE_BYPASS=1` / user opt-out).
- **V-02** — if `broadcasts:` keys changed, did every reactor get updated?
  Check `_reverse-index.md`. If a key was removed/renamed, commit type
  **must be `vault!`**.
- **V-03** — `_lint.sh` code_refs validation must be clean (or warns triaged).
- **V-04** — Auto Decision Log step below addresses this; do not skip it.
- **V-05** — any new broadcast key added this session must have at least one
  reactor declared (or marked `TBD — see <issue>`).
- **V-06** — `vdd lint` exit 0 BEFORE the commit message. This
  is the hard gate; the commit message is the *output* of vdd-done, and it
  must not appear unless lint passed in this message.
- **V-07** — every member of the impact set produced by `vdd-impact.sh` /
  `vdd-blast.sh` this session must carry a verdict (`affected` /
  `unaffected` / `deferred`). No silent omissions.
- **V-08** — every decision recorded this session has `note:` ≤200 chars,
  single line. Trim before writing; move long rationale to commit body or
  page body's § decisions paragraph. `_lint.sh` Check 12 surfaces violators.
  Check 12b also nudges when a page's active `decisions:` exceed the count cap
  (~25) — archive older entries to `<layer>/decision-log.md` if flagged.
- **V-10** — vault pages verified this session should carry a current
  `reviewed_code_hash`. `vdd-review` (Analyze, Step 5) stamps every CONSISTENT
  page; confirm `_lint.sh` shows no V-10 stale WARN for this session's pages
  before emitting the commit message. A lingering V-10 WARN means a page
  describes code that moved without re-review — resolve it (re-review →
  re-stamp, or fix the page) rather than committing on a stale page. The stamp
  edits ride along in this commit. Pages verdicted DRIFT / UNVERIFIABLE are
  intentionally NOT stamped — leave their flag raised.

If any V-XX fails, output the rule number + concrete miss + "fix and re-invoke
vdd-done". Do not paper over with "minor issue".

## Instructions

1. Review every target completed in this session.
2. Final check that no forbidden rules / out-of-scope changes leaked in.
3. Organize all changed files (git status / diff summary).
4. **Delegate verification to `vdd-review`** — if a fresh `vdd-review` report does not exist for this session's changes, invoke it now. Consume its Overall verdict: `READY` → continue; `NOT READY` → surface its drift list and stop.
5. **Verify vault page updates** (see "Vault narrative update" below).
6. **Auto-collect decisions** from the conversation (see "Auto Decision Log") — this is V-04 enforcement.
7. **Run `vdd lint`** to refresh rollups (`_progress.md`, `_decisions.md`, `_open-issues.md`, `_reverse-index.md`). Exit code 0 required per V-06.
8. **Wiki promotion check (optional)** — if `~/wiki/wiki/` exists and this session added new vault decisions, ask the user whether to scan for wiki-promotable decisions before commit. On "yes", invoke the **`wiki-promoter`** agent (Codex worker delegation, `role prompt: wiki-promoter`) with the list of new decisions from this session; the agent returns candidate wiki entries with draft prose; user reviews and manually applies to `~/wiki/wiki/`. On "skip" / "later" — non-blocking.
9. **Suggest a Conventional Commit message** (do NOT run `git commit` / `git push` automatically — only when the user explicitly instructs).
10. Output the result using the template below.

## Vault narrative update

If `docs/vault/` exists, update frontmatter on pages affected by the change:

| Field | When to update |
|---|---|
| `decisions:` | On non-trivial decision — append `{date: YYYY-MM-DD, note: "<one-line>"}` |
| `tasks:` | On task identified/completed — add/remove `{todo: "...", priority: high\|med\|low}` |
| `code_refs:` | On new file/symbol added — `path/file.ext#SymbolName` |
| `status:` | On `active` ↔ `in_progress` transition |
| `updated:` | On any body change — set to today |

**When the broadcast graph changed** (state contract delta):
1. Verify `<layer>/_state-contract.md` `broadcasts:` / `reacts_to:` / `emits_to:` reflect the new wire.
2. Confirm every reactor page that consumes the changed key is updated.
3. Commit type **must be `vault!`** (breaking) if a key was removed/renamed.

**Validation gate** — must pass before suggesting a commit message:
```bash
vdd lint   # exit 0 (0 errors) required — V-06.
                           # warnings are triaged, not necessarily 0.
```

If lint fails, surface the errors and stop. The user fixes the vault, then re-invokes vdd-done.

**Prose quality audit** — after lint passes:

- **Mandatory when this session edited any `docs/vault/<layer>/*.md`** —
  invoke the **`vault-critic` agent** on the changed pages. The critic
  flags filler / code paraphrase / empty WHY / stale `updated:` / missing
  "What is NOT here" — it does not modify pages, it reports. LLM-authored
  vault content can drift toward plausible-but-empty prose; this audit
  is the deterministic check.
- **Also recommended when significant decisions were captured** —
  `vault-verifier` agent for page claims ↔ code consistency.

**Batch parallel when ≥3 layers were touched this session.** Dispatch
`vault-critic` (and `vault-verifier` if applicable) — one subagent per
touched layer — in a single message with multiple Task calls (per
`vdd-review` § Mode B Step 2 batch dispatch). Both agents are read-only;
no race / evidence concerns. Merge N reports into a single consolidated
audit before composing the commit message. Skip parallel when <3 layers
were touched (single-pass is faster).

Fix flagged issues before the commit message. If the critic / verifier
finds nothing actionable, note that in the commit body ("vault audit:
no issues").

## Auto Decision Log

When vdd-done runs, scan the conversation and surface notable decisions for recording.

**The record test (V-04) — apply to every candidate before surfacing it:** *"would a
future worker editing this area, not knowing this, take a wrong turn or reintroduce a
bug?"* Record only constraint-bearing decisions — an invariant, a forbidden path, a
required approach, a threshold. A choice that merely happened and leaves no constraint
(its result is in the code, re-deciding it differently later is safe) is **history, not
a decision** — do not surface it. The collection targets below are where to *look* for
candidates; the record test is what *passes* them.

### Collection targets

| Source | What to collect |
|---|---|
| Planning conversation | Scope decisions, library/pattern adoption, deferred items |
| Implementation conversation | Out-of-scope changes the user approved, resolutions after verification failure |
| Review feedback | Issues found and the user's judgment on each |
| Architecture / design choices | Layer boundary changes, contract additions/breaks, new vault pages |

### Procedure

1. Compile a candidate decision list from the session.
2. **Trim each candidate to ≤200 chars / one line (V-08)** before showing
   the confirmation prompt. Form: `"decision: <one line>. rationale: <one clause>."`.
   If the rationale doesn't fit, keep the decision tight and reserve the long
   form for the commit message body. Do NOT paraphrase the full conversation into a note.
3. **Confirm with the user before recording**:
   ```
   Record the following in the decision log?

     1. [Decision] <content> — <reason>
     2. [Decision] <content> — <reason>
     3. [Deferred] <content> — <reason>

   Tell me if anything needs editing or removing. Confirm to record.
   ```
4. **Reversal check (V-04 reversal path).** For each approved candidate,
   before writing, scan the target page's existing `decisions[*].note` for an
   entry that this new decision reverses — same `(topic, direction)` pair,
   opposite predicate. If found:
   - The session necessarily already had the user confirm the reversal in
     conversation (otherwise this candidate would not be on the list).
   - Use the **replace + archive** procedure (V-04):
     a. Remove the reversed entry from frontmatter `decisions:` (Edit).
     b. Append it to the page body's `## decisions archive` section as
        `### YYYY-MM-DD — <title>` with `**Note (frontmatter as it stood):** "<original>"`
        and `**Replaced YYYY-MM-DD:** <one-clause why>. See current entry in decisions: frontmatter dated <new-date>.`
     c. Append the new candidate as a fresh `decisions:` entry.
     d. Sweep sibling body claims on the same page (`## Architectural
        conventions`, `## Capability boundary`, parity tables, ASCII
        diagrams) — if any state the reversed direction, update them in the
        same edit.
   - If no reversal target is found (or the candidate is a refinement / new
     topic), use append mode (step 5 below).
5. On approval (append mode), write to the appropriate destination — every
   decision lands in *some* vault page's frontmatter so `_lint.sh` rolls it
   into `_decisions.md`. There is no separate `ARCHITECTURE.md`:
   - **If a vault layer is identified** (the decision belongs to a specific
     `<layer>`): append to `<layer>/<layer>.md` frontmatter `decisions:`
     array (`{date: YYYY-MM-DD, note: "..."}`).
   - **If it is a broadcast-graph / contract decision**: append to that
     layer's `<layer>/_state-contract.md` `decisions:` instead.
   - **Else** (cross-layer — spans several layers): append to the most
     central layer's page `decisions:` and state the cross-layer scope in
     the note text.
   - **[Deferred] items** → append to the same page's `tasks:` array
     (`{todo: "...", priority: high|med|low}`).
6. Re-run `vdd lint` to update `_decisions.md` rollup.
7. If there's nothing notable, ask whether to record anything; skip if the user declines.
8. If the user replies "don't record", skip silently.

### What not to collect

- **History — choices that impose no constraint on future work.** "Chose library X",
  "used pattern Y here", "did the work in this order" — the result is in the code; a
  future worker re-deciding differently breaks nothing. Fails the record test. (If the
  choice *is* a lock-in — "must stay on X, switching breaks Z" — that's the constraint;
  record *that*, not the bare choice.)
- Trivial implementation details (renames, import cleanup).
- Duplicates of decisions already in the log.
- Items the user explicitly excluded.

## Output Template (always use this format)

```
Done Checklist:
  - All targets completed: Yes/No
  - No forbidden / out-of-scope changes: Yes/No
  - Vault frontmatter updated: Yes/No/N/A
  - _lint.sh: exit 0 (0 errors), warnings triaged: Yes/No

Targets Completed:
  - [target 1] — <one-line summary>
  - [target 2] — <one-line summary>

Files Changed:
  - [new/modified/deleted] <file path> — <one-line description>

Vault Pages Touched:
  - <layer>/<page>.md — <field updated: decisions/tasks/code_refs/status/updated>

Decisions Logged:
  - <N> decisions recorded / nothing to record / user skipped

Suggested Commit Message (Conventional Commits):
  <type>(<scope>): <description>

  <optional body>
```

## Commit message rules

- **Conventional Commits.** type/scope in English; description body follows your team's language convention.
  - e.g. `feat(auth): add JWT-based authentication`
  - e.g. `vault!(auth): native:expired → native:reconnecting (BREAKING contract)`
- **Do not include Claude / Anthropic / AI-assistant Co-authored-by lines.**
- **Do not leave traces of Codex / AI / LLM tool use in the message body.**
- Check `.gitignore` before `git add` — never add ignored files.
- Run `git commit` / `git push` **only when the user explicitly asks for it.**

| type | Use |
|---|---|
| feat | New feature |
| fix | Bug fix |
| refactor | Behavior-preserving code change |
| docs | Documentation only |
| test | Add/update tests |
| chore | Build, config, misc |
| vault | Vault page/frontmatter update only (no code change) |
| vault! | Vault contract **breaking** — broadcast key removed/renamed |

## Context boundary — close the episode

Once the commit message is emitted, this target's cycle is **CLOSED**. Before the next target:

- **Recommend `/clear`.** A fresh context per target is the single strongest guard against the most common gate failure: carrying momentum from a finished target (a just-completed `vdd-investigate` / `vdd-build`) into a new request and editing it inline instead of re-entering `vdd-plan`. `/clear` loses nothing — the vault is the SoT: the project AGENTS.md instruction re-injects the vault index and Rule 0 re-reads the relevant pages on the next task. Restoration is cheaper than the drift a warm-context inline edit causes.
- **A new code-change instruction after a done is a NEW cycle, not an addendum.** It re-enters Rule 0 → `vdd-plan` (change) or `vdd-investigate` (bug). Per vdd-workflow Rule 0 (phase skill first) the model never self-grants an inline edit anyway, but post-done is where the "small follow-up to what we just shipped" framing is strongest — so it is explicitly called out: only the user authorizes a direct edit, never the model.
- Keep one context only *within* a single target (plan → build → review → done continuity). Do **not** `/clear` mid-target.

State this at the end of the output: `▸ target closed — /clear recommended before the next target; a new change re-enters vdd-plan.`

## Fallback: no formal workflow preceded

If vdd-done runs without a prior planning/implementation phase visible in the session:
- Best-effort summary from `git diff` / `git status` and in-conversation changes.
- Note in the output that "no formal workflow was followed".
- Still run the vault frontmatter check + `_lint.sh` if `docs/vault/` exists.
