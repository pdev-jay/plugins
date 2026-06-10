# Codex Adapter Notes

This folder is a Codex-oriented port of the Claude Code VDD plugin.

## What Is Preserved

- `docs/vault/` remains the architectural Source of Truth.
- `skills/vdd-*` remain the workflow entry points.
- `bin/vdd` and `scripts/` remain the deterministic tooling layer:
  - `vdd lint`
  - `vdd map`
  - `vdd blast`
  - `vdd impact`
  - `vdd plan`
  - `vdd schedule`
  - `vdd bootstrap`
  - `vdd grasp-gate`
- `role-prompts/` preserves the original Claude agent prompts as reusable Codex role prompts.

## What Changes In Codex

Codex does not treat `agents/*.md` as automatically registered custom agent types. The original Claude agents are therefore stored under `role-prompts/` and used as prompt material when Codex workers are explicitly allowed.

Codex also does not use the Claude `SessionStart` hook in this adapter. Instead, `install.sh` writes a VDD section into the target project's `AGENTS.md` when one does not already exist. That project instruction tells Codex to read `docs/vault/index.md`, the owner page, and the plugin-owned schema/constraints before code or vault edits.

## Worker Policy

Default behavior is main-agent execution:

1. Select the matching VDD skill.
2. Read the vault index and owner page.
3. Run deterministic `vdd` tools.
4. Implement in the main Codex session.
5. Run `vdd lint` and review before claiming completion.

Parallel workers are opt-in. Codex may use workers when the user explicitly asks for parallel/delegated work, or when the project `AGENTS.md` contains the "VDD Parallel Worker Opt-In" section installed by this adapter.

When worker mode is allowed:

- Run `vdd schedule <owner_page>...` before dispatch.
- Give each worker exactly one `owner_page`.
- Give each worker a disjoint file/write scope.
- Keep `_state-contract.md` and cross-page contract edits in the main agent unless the user explicitly assigns them.
- The main Codex agent reviews and integrates worker results.
- Run `vdd lint` after integration.

## Installation

From this adapter folder:

```bash
./install.sh /path/to/project
```

Then ensure `bin/` is available on `PATH` for the Codex session, or invoke the dispatcher by absolute path:

```bash
/path/to/codex-vault-driven-development-plugin/bin/vdd lint
```

