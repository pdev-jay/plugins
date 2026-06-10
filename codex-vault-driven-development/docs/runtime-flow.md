# Codex Runtime Flow

## Session Setup

The target project carries `AGENTS.md` with VDD instructions installed by `install.sh`. Codex uses that standing instruction instead of a Claude SessionStart hook.

## Prompt Loop

```text
Prompt
  -> match a VDD skill
  -> read docs/vault/index.md
  -> read owner page and relevant state contract
  -> run deterministic vdd scripts
  -> edit code/vault when approved by the workflow
  -> run vdd lint
  -> report evidence
```

## Worker Loop

Workers are not automatic custom VDD agents in Codex. When worker mode is allowed, the main Codex agent:

1. partitions the plan by `owner_page`
2. runs `vdd schedule`
3. gives each worker one owner page and disjoint file scope
4. uses `role-prompts/<role>.md` as prompt material
5. reviews and integrates worker output
6. runs `vdd lint`

When worker mode is not allowed, the main Codex agent executes sequentially.
