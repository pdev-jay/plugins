# Codex Vault-Driven Development

This is a Codex adapter for Vault-Driven Development (VDD).

VDD makes `docs/vault/` the architectural Source of Truth for a project: layer intent, decisions, `code_refs`, broadcast/reactor contracts, and review freshness. Codex reads the vault before changing code, updates the vault when decisions change, and uses deterministic shell tools to verify drift.

## What This Adapter Includes

- `.codex-plugin/plugin.json` — Codex plugin manifest.
- `skills/vdd-*` — Codex-facing VDD workflow skills.
- `bin/vdd` — dispatcher for deterministic tools.
- `scripts/` — lint, map, impact, blast, schedule, plan, bootstrap, and YAML helpers.
- `scaffold/` — plugin-owned schema, constraints, and project vault templates.
- `role-prompts/` — original VDD agent prompts preserved as Codex worker prompt material.

## Key Difference From The Claude Plugin

The original VDD plugin uses Claude Code custom agents and a SessionStart hook. Codex does not use those surfaces the same way.

In this adapter:

- Skill routing and workflow discipline are preserved.
- Deterministic `vdd` scripts are preserved.
- The installer writes a VDD section into project-root `AGENTS.md`.
- Claude agents become reusable role prompts under `role-prompts/`.
- Parallel Codex workers are opt-in through user request or the installed `AGENTS.md` policy.

## Install Into A Project

From this adapter folder:

```bash
./install.sh /path/to/project
```

Then make sure `bin/` is available on `PATH`, or call the dispatcher by absolute path:

```bash
/path/to/codex-vault-driven-development-plugin/bin/vdd lint
```

The installer creates or preserves:

- `/path/to/project/docs/vault/index.md`
- `/path/to/project/docs/vault/_archive/`
- `/path/to/project/AGENTS.md` with a VDD section

It does not copy plugin-owned scripts, schema, constraints, or examples into the project.

## Day-To-Day Flow

```text
request
  -> matching VDD skill
  -> read docs/vault/index.md + owner page
  -> run vdd impact / blast / schedule as needed
  -> implement
  -> vdd lint
  -> vdd-review
  -> vdd-done
```

Useful prompts:

- "set up VDD here" -> `vdd-init`
- "plan this change with the vault first" -> `vdd-plan`
- "implement the approved plan" -> `vdd-build`
- "why is this broken?" -> `vdd-investigate`
- "does the vault match the code?" -> `vdd-review`
- "wrap up and suggest a commit message" -> `vdd-done`

## Parallel Worker Opt-In

Codex workers may be used when the user explicitly asks for parallel/delegated work, or when the target project's `AGENTS.md` contains the installed `VDD Parallel Worker Opt-In` section.

Worker mode requires:

- owner-page partitioning
- disjoint write scopes
- `vdd schedule <owner_page>...` for multi-page work
- main-agent review and integration
- `vdd lint` after integration

Without opt-in, Codex should execute the workflow sequentially in the main session.

## Validate

The deterministic script tests from the original VDD plugin should still pass:

```bash
bash dev/test/run.sh
```
