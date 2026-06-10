---
name: vdd-log
description: |
  Records a single decision / memo / issue into the vault page's `decisions:` frontmatter NOW. Covers either language: "기록해둬/결정 남겨/메모해둬/적어둬/이건 잊지 말자/일단 남겨두자/이건 챙겨놔" / "log this/record this/record this decision/note this down/jot this down/don't forget this/keep this". Batch harvest at session end is vdd-done's job; use this skill when the record needs to be written immediately. Does not enter without a concrete decision on the table.
---

# /vdd-log

**Announce on entry:** `▸ vdd-log entry — record the decision into its owning vault page's decisions: frontmatter (<the decision>)`

**Content to log**: $ARGUMENTS

> 💡 When `/vdd-done` runs, decisions made during the workflow are auto-collected.
> Use `/vdd-log` for immediate manual logging.

## Instructions

The vault is the SoT — a decision belongs in a vault page's frontmatter, not a
separate document. `_lint.sh` rolls every page's `decisions:` into `_decisions.md`.

When the user explicitly invokes `/vdd-log`, honor the request — they have judged it
worth keeping. But if the content reads as **history rather than a constraint** (a
choice whose result is already in the code and that future work could safely re-make
differently), say so in one line and offer to skip — the record test (V-04) is *"would
a future worker, not knowing this, take a wrong turn or reintroduce a bug?"*. Recording
history inflates `decisions:` and buries the entries that act as a harness.

1. **Identify the target vault page.** The decision belongs to whichever
   layer/feature it concerns:
   - Tied to a specific layer/feature → that layer's
     `docs/vault/<layer>/<layer>.md` (or the relevant feature page).
   - A broadcast-graph / contract decision → the layer's
     `docs/vault/<layer>/_state-contract.md`.
   - Cross-layer (spans several layers) → the most central layer's page;
     state the cross-layer scope in the entry text.
   - To find the page: `grep -rliF "<keyword>" docs/vault/` for the
     decision's keywords, or invoke the `vault-suggester` agent.
2. **Reversal check (V-01 / V-04).** Before appending, scan the target page's
   existing `decisions[*].note` for an entry that this new decision *reverses*
   — same `(topic, direction)` pair, opposite predicate — NOT keyword overlap,
   NOT refinement / extension of the same direction. If one is found, switch
   from append-mode to **replace + archive**:
   - **Required user confirmation.** If the reversal was already confirmed in
     this session via V-01's Decision-conflict handler (i.e. the user was
     shown the old entry and answered "yes, reverse"), proceed. Otherwise
     STOP, surface the conflict
     (``"이 작업은 <date> 결정 \"<note>\" 을(를) 뒤집습니다. 의도가 맞습니까?"``),
     and only continue after the user confirms.
   - **Step A — remove old entry from frontmatter `decisions:`.** Single
     `Edit` deleting the `{date, note}` line(s) for the reversed entry.
   - **Step B — archive into page body.** Ensure a `## decisions archive`
     section exists (create at the bottom of the body if not, above
     `## Cross-layer dependencies` / `## Open issues` if those exist). Append
     a sub-heading:
     ```markdown
     ### YYYY-MM-DD — <one-line title>

     **Note (frontmatter as it stood):** "<original note verbatim>"

     **Replaced YYYY-MM-DD:** <one-clause why it changed>. See current entry
     in `decisions:` frontmatter dated <new-date>.
     ```
     Archive bodies are prose — V-08's ≤200 char limit does NOT apply here;
     expand the reason fully.
   - **Step C — append the new entry to frontmatter `decisions:`** with
     today's date and the V-08-trimmed note (≤200 chars).
   - **Step D — sweep sibling body claims.** Inspect `## Architectural
     conventions`, `## Capability boundary`, parity tables, and ASCII flow
     diagrams on the same page; if any of them state the *reversed*
     direction explicitly, update them in the same edit. Body sections are
     not auto-derived from `decisions:` — stale ones recreate the
     contradiction at a different surface (V-04 sibling sweep).
   - If the archive section ever exceeds ~200 body lines, escalate to V-08's
     `<layer>/decision-log.md` archive child page pattern.

   If no reversal target is found (or the change is a *refinement* — same
   direction, narrower scope / added caveat), skip this step and append
   normally.
3. **Append to that page's frontmatter** — use `Edit` only (never
   `update_frontmatter` / MCP frontmatter tools — they re-emit YAML and
   break `_lint.sh`):
   - **decision (append mode)** → append `{date: YYYY-MM-DD, note: "<decision>. Rationale: <reason>"}`
     to the `decisions:` array.
   - **decision (replace + archive mode — step 2 triggered)** → follow Steps
     A → B → C above; the new entry's note has no special token — the
     archive section itself IS the historical record.
   - **pending** (`$ARGUMENTS` contains `[pending]`) → append
     `{todo: "<question>", priority: med}` to the `tasks:` array.
4. Use today's date. If `$ARGUMENTS` contains "—", the part before is the
   decision and the part after is the rationale.

   **Trim discipline (V-08).** The `note:` is ≤200 chars, single line —
   form: `"decision: <one line>. rationale: <one clause>."`. Don't paraphrase
   the conversation. Don't list alternatives that were considered. Don't quote
   rationale verbatim from the user's message if it's narrative.

   If the rationale doesn't fit in one line:
   1. Compress to ≤200 chars and put the long form in the **commit message body**
      (where rationale archives belong) or as a paragraph in the page body's
      § decisions section.
   2. Reference: `note: "<decision>. See commit body / § decisions."`

   `_lint.sh` Check 12 warns above 200; the rollup `_decisions.md` exists for
   chronological scan, not for narrative dumps.
5. **Modify only the target page** — frontmatter in all modes, plus the body's
   `## decisions archive` section *only* in replace + archive mode. Never touch
   other pages or other sections of the same page.
6. Run `vdd lint` so the `_decisions.md` / `_open-issues.md`
   rollups refresh and the frontmatter edit is validated.
7. After logging, show: the new frontmatter entry that was added, AND — if
   step 2 triggered — the archived block (removed entry + the body archive
   sub-heading added). The user must see both sides of the reversal in one
   report.

## When `docs/vault/` does not exist

vdd-log is a VDD skill — it expects a vault. If the project has no
`docs/vault/`:

1. Tell the user the project isn't vaultified yet and recommend
   `vdd-onboarding`.
2. Log the decision **in-conversation only**, in this format:
   ```
   📝 Decision Log (in-conversation — no vault yet):
   - Date: <today>
   - Status: decided / pending
   - Content: <decision>
   - Rationale: <reason>
   ```
   Do not create `ARCHITECTURE.md` or any other standalone file — the
   decision belongs in a vault page once the vault exists.
