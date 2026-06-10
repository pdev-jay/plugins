# Migration: `install.sh` → Claude Code Plugin

Status: **complete** (Phases 1–3 done; Phase 4 = marketplace publish pending).

## Final state

```
~/vault-driven-development-plugin/
├── .claude-plugin/
│   └── plugin.json          ← native plugin manifest
├── hooks/
│   ├── hooks.json           ← declarative hook registration (SessionStart only)
│   └── session-start-vault-inject.sh
├── skills/                  ← 12 skills (all vdd-*) — auto-discovered at root
├── agents/                  ← 8 agents (5 vault-* + 1 vdd-implementer + 2 wiki-*) — auto-discovered at root
├── bin/                     ← `vdd` dispatcher — on PATH (Claude Code adds <plugin>/bin)
├── scripts/                 ← deterministic tools: _lint, bootstrap, vdd-blast, vdd-plan, vdd-impact, vdd-schedule, vdd-map, grasp-gate, vdd-yaml-lib (sourced). Invoked via `vdd <name>`.
├── scaffold/                ← plugin-owned SoT (read in place; only index.md is copied)
│   ├── CLAUDE.md            ← vault schema (hook injects its path; not copied)
│   ├── CONSTRAINTS.md       ← V-XX workflow invariants (hook injects its path; not copied)
│   ├── index.md             ← vault index template (the ONE file install.sh copies + substitutes)
│   └── examples/            ← reference pages (read from plugin; not copied)
└── install.sh               ← copies only index.md per-project (everything else plugin-owned)
```

## Phase summary

### Phase 1 — Plugin scaffolding (✓)
- `.claude-plugin/plugin.json` declares skills (path), agents (array of paths), hooks (path).
- `claude plugin validate` passes.

### Phase 2 — Hooks declarative migration (✓)
- Bash hooks moved from `template/hooks/` to `hooks/` (plugin convention).
- `hooks/hooks.json` declares SessionStart entry only (Pre/Post/Stop removed in a later refactor — see CHANGELOG 2026-05).
- Hook invoked via `${CLAUDE_PLUGIN_ROOT}/hooks/session-start-vault-inject.sh`.
- No more per-project `.claude/hooks/` copies; no more `settings.json` jq patching.

### Phase 3 — `install.sh` simplification (✓)
- Removed: global skills/agents copy, per-project hook copy, settings.json patch, jq dependency, `--force-*` flags.
- Kept: `docs/vault/` scaffold (CLAUDE.md, index.md, _lint.sh, scripts/, examples/), `{{PROJECT_NAME}}` substitution, `.bak.<ts>` preservation.
- Result: 213 lines → ~120 lines, single responsibility.

### Phase 4 — Marketplace publish (pending)
- Self-host `marketplace.json` or submit to Anthropic's marketplace via [platform.claude.com/plugins/submit](https://platform.claude.com/plugins/submit).
- Tag a release: `claude plugin tag .` will produce `vault-driven-development--v0.1.0-alpha.1`.

## Skill rename history

The Obra-superpowers-origin 7 skills were renamed with a `vdd-` prefix to avoid collision when both VDD and Obra superpowers are installed in the same `~/.claude/skills/` directory:

| Old | New |
|---|---|
| brainstorming | vdd-spec |
| writing-plans | vdd-plan |
| done | vdd-done |
| log | vdd-log |
| search-first | vdd-search |
| verification-before-completion | vdd-verify |
| strategic-compact | vdd-compact |

> Note: `vdd-compact` — plus the later-added `vdd-lean` and `vdd-promote` — were
> removed in a subsequent cleanup. A later **skill consolidation** (2026-05) merged
> `vdd-spec` + `vdd-contract` into `vdd-plan` (Mode A / B / C), `vdd-verify` +
> `vdd-analyze` into `vdd-review` (Verify / Analyze), and folded `vdd-search` into
> `vdd-explain`'s external-scan flavor; `vdd-build` was added as the top-level
> implementation-dispatch skill. The plugin now ships **12 skills, 10 user-invocable**
> (see README).

VDD-native skills kept their names: `vdd-investigate`, `vdd-onboarding`, `vdd-workflow`. `vdd-init` was added 2026-05 (orchestrator); `vdd-build` and `vdd-review` are the consolidated phase skills.

Inside Claude Code, plugin skills are addressed as `vault-driven-development:<skill-name>` (e.g., `/vault-driven-development:vdd-plan`).
