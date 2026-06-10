# Codex Integration

This adapter keeps the VDD core and changes the host integration layer.

## Preserved

- `docs/vault/` source-of-truth model
- `skills/vdd-*` workflow phases
- `bin/vdd` dispatcher
- deterministic scripts under `scripts/`
- schema and constraints under `scaffold/`

## Changed From Claude VDD

| Original Claude VDD | Codex Adapter |
|---|---|
| `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| `agents/*.md` auto-registered custom agents | `role-prompts/*.md` reusable worker prompts |
| SessionStart hook injects context | project `AGENTS.md` supplies standing VDD instructions |
| `CLAUDE_PLUGIN_ROOT` | plugin root inferred by user/session or `bin/vdd` self-location |
| automatic `Task subagent_type=...` dispatch | Codex worker opt-in by user request or `AGENTS.md` policy |
| `.claude/settings.json` vdd-live setup | excluded from active skills |

## Runtime Shape

```text
user request
  -> Codex selects matching VDD skill
  -> read docs/vault/index.md and owner page
  -> run vdd impact/blast/schedule where relevant
  -> implement or investigate
  -> run vdd lint
  -> vdd-review
  -> vdd-done
```

Parallel workers are allowed only when the task is owner-page partitioned, write scopes are disjoint, and the project/user has opted in.
