---
name: vdd-init
description: |
  Enters when installing VDD/vault into a fresh Codex project or when docs/vault/ is empty. Covers either language: "vdd 깔자/vault 만들자/세팅/처음 시작/초기화/VDD 적용/프로젝트 시작인데 vault 어떻게" / "set up VDD/initialize the vault/install VDD/create the vault/initial setup/VDD from day one/fresh repo vault setup/where do I start with vault". Runs install.sh → vdd lint → onboarding handoff. If docs/vault/ already has populated layer pages, routes to vdd-plan.
user-invocable: true
---

# vdd-init — Codex VDD project bootstrap

**Announce on entry:** `▸ vdd-init entry — bootstrap VDD for this project (<scaffold + lint + onboarding handoff>)`

This is the Codex entry point for "set up VDD here". It uses the Codex adapter's `install.sh`; no Claude hooks, Claude custom agents, or `.claude/settings.json` are installed.

## Procedure

### Phase 0 — Locate plugin root

Prefer the installed plugin path if known. Otherwise infer it from the current skill path or ask the user for the adapter folder.

If the repository itself is the adapter checkout, the plugin root is the folder containing:

- `.codex-plugin/plugin.json`
- `install.sh`
- `bin/vdd`
- `skills/`
- `scripts/`

### Phase 1 — Scaffold

Run:

```bash
bash <codex-vdd-plugin-root>/install.sh "$PWD"
```

The installer creates/preserves:

- `docs/vault/index.md`
- `docs/vault/_archive/`
- project-root `AGENTS.md` with a VDD section when absent

It does not copy plugin-owned schema, constraints, examples, or scripts into the project. Tools run through the plugin's `bin/vdd` dispatcher.

### Phase 2 — Verify Scaffold

Run from the project root:

```bash
vdd lint
```

If `vdd` is not on `PATH`, use:

```bash
<codex-vdd-plugin-root>/bin/vdd lint
```

Expected result for an empty scaffold is exit 0 with no schema errors.

### Phase 3 — Onboarding Handoff

If the project already has code but no layer pages, continue with `vdd-onboarding` in brownfield mode:

- Survey code structure.
- Propose initial layer candidates.
- Draft layer pages with `[UNVERIFIED]` tags where code inference is uncertain.
- Ask the user to confirm capability boundaries.

If the repo is greenfield, ask for the initial layer list, then create skeleton layer pages with:

```bash
vdd bootstrap --write <layer>
```

### Phase 4 — Report

Return:

- files created or preserved
- whether `AGENTS.md` now contains the VDD section
- `vdd lint` exit code
- recommended next command, usually `vdd-plan` for the first real change

## Codex Notes

- Do not use Claude `Task`, `subagent_type`, `CLAUDE_PLUGIN_ROOT`, or SessionStart assumptions.
- Parallel workers are opt-in through project `AGENTS.md` or explicit user request.
- The role prompts under `role-prompts/` are prompt material, not automatically registered Codex agent types.
