## Vault-Driven Development

`docs/vault/` is the architectural Source of Truth for this project: intent, decisions, cross-layer state contracts, and ownership. Code shows mechanism; the vault records why the mechanism is shaped that way.

### At The Start Of Code Or Vault Work

Before editing code or vault pages, follow the matching VDD skill:

- `vdd-plan` for changes, refactors, new features, and impact analysis.
- `vdd-build` for implementing an approved VDD plan.
- `vdd-investigate` for existing behavior that is broken or surprising.
- `vdd-review` for passing/green/drift/consistency checks.
- `vdd-done` for wrap-up, decision harvest, and commit message preparation.
- `vdd-log` for recording one decision immediately.
- `vdd-explain` for read-only lookup.

Read `docs/vault/index.md` and the owning vault page before modifying code. For cross-layer state changes, also read the relevant `<layer>/_state-contract.md`.

The plugin-owned schema and constraints live in the Codex VDD plugin folder:

- schema: `scaffold/VDD_SCHEMA.md`
- constraints: `scaffold/CONSTRAINTS.md`

If the absolute plugin path is known in the current session, read those files from the plugin path. Otherwise, use the copies in the installed plugin folder that provided this instruction.

### Lint Gate

Run `vdd lint` from the project root after vault edits and before claiming completion. A completion or passing claim requires fresh verification evidence in the current turn.

### VDD Parallel Worker Opt-In

This project permits Codex to use sub-agents for VDD workflows when all of the following are true:

- The task has been partitioned by `owner_page`.
- `vdd schedule <owner_page>...` has been run when more than one owner page is involved.
- Each worker has exactly one owner page and a disjoint file/write scope.
- Cross-page contract or `_state-contract.md` changes stay in the main Codex agent unless explicitly assigned.
- The main Codex agent remains responsible for reviewing and integrating worker results.
- `vdd lint` runs after worker results are integrated.

For VDD build/review work, phrases like "implement it", "build it", "review drift", or "wrap up" may be treated as permission to use Codex workers only when the partition is safe under the rules above.

### Bypass

Rare. Prefix the prompt with `ignore vault` or set `VAULT_GATE_BYPASS=1` for a session when the VDD workflow should be skipped.
