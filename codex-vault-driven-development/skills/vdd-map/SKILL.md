---
name: vdd-map
description: |
  Render the vault's broadcast/intent graph by running the deterministic `vdd-map.sh`, then read the result. Triggers — "맵 그려줘 / vault 맵 / 시그널 그래프 / broadcast 맵 / 그래프 보여줘 / silent layer 있어 / 고립된 레이어 / orphan 키 뭐야 / 어디가 허브야" / "show the map / draw the vault graph / signal map / broadcast graph / any silent layers / isolated layer / what orphan keys / where's the hub / fan-in". Picks the mode (collapsed / --raw / --orphans / --layer) from intent, runs the script, presents output + a terminal-readable reading. Renders facts only — the vault↔code consistency VERDICT belongs to `vdd-review` (this skill hands orphan/silent findings there as triage input, never verdicts them). Pure lookup of intent/structure (no graph render) → `vdd-explain`.
---

# vdd-map — render + read the vault's signal/intent graph

**Announce on entry:** `▸ vdd-map entry — render the broadcast/intent graph (<mode>) from frontmatter via vdd-map.sh`.

The map is **derived** from frontmatter (`broadcasts` / `reacts_to` / `emits_to` / `intent_refs`) — never authored, never committed. It is a human-facing visual + the triage input for `vdd-review`. It does not read code and does not verify anything; it shows the graph the vault declares.

## Mode selection (from the invocation)

| User intent / args | Command |
|---|---|
| (none) / "맵 / map / 그래프" | `vdd-map.sh` — collapsed layer map (default) |
| "raw / 키 단위 / broadcast까지 / 자세히" | `vdd-map.sh --raw` |
| "orphan / silent layer / 고립 / 무반응 키" | `vdd-map.sh --orphans` |
| "<layer>만 / just auth / auth 레이어" | `vdd-map.sh --raw --layer <layer>` |

## Procedure

1. **Run the dispatcher** (`vdd` is on PATH — Codex adds the plugin's `bin/`; same entry point as `vdd blast` / `vdd impact`):
   ```bash
   vdd map [mode]
   ```
   - No `docs/vault/` → not a VDD project; say so and stop (offer `/vdd-init`).
   - `vdd: command not found` → the plugin's `bin/` is not on PATH (plugin not installed, or the installed cache predates the `vdd` dispatcher). Fall back to `bash "$(ls -td "$HOME"/.claude/plugins/cache/pdev-jay/vault-driven-development/*/)scripts/vdd-map.sh"`, and tell the user to `claude plugin update`.

2. **Present.**
   - `collapsed` / `--raw` → show the ```mermaid block verbatim (paste into Obsidian / GitHub / mermaid.live to render), then a **terminal-readable reading**: the spine (who emits → who reacts), the convergence/fan-in points, and any anomalies the graph exposes.
   - `--orphans` → already plain text; surface it and group obviously-normal (UI bloc states read directly by the view) vs suspicious (state-machine keys, paired-lifecycle asymmetry, silent layers with event-producing `code_refs`).

3. **Triage, do not verdict.** Orphan keys and silent layers are **facts**. Classifying one as a real defect requires reading code — that is `vdd-review` Mode B's job (Step 1.5 triage → `vault-verifier`). When the user wants "is this actually broken?", hand the findings to `vdd-review`, do not decide here.

## Boundary

- vs `vdd-explain` — explain answers "what/where/how" from vault prose + code; vdd-map renders the *signal graph* and reads its shape. Overlap on "how does this project work" → either is fine; reach for vdd-map when the question is about the **graph** (who emits/reacts, hubs, isolated layers).
- vs `vdd-review` — vdd-map shows facts; vdd-review verifies them against code and emits the binding verdict. vdd-map never reads code.
- Output format — mermaid is the render format for external viewers; the **in-page** vault convention stays ASCII (AGENTS.md — no Mermaid in page bodies). Do not paste vdd-map's mermaid into a vault page.
