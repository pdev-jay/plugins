# Codex VDD Quickstart

## 1. Install The Adapter Into A Project

From the adapter folder:

```bash
./install.sh /path/to/project
```

The installer creates:

- `docs/vault/index.md`
- `docs/vault/_archive/`
- `AGENTS.md` with VDD instructions and worker opt-in policy

## 2. Make `vdd` Available

Either add the adapter `bin/` directory to `PATH`:

```bash
export PATH="/path/to/codex-vault-driven-development-plugin/bin:$PATH"
```

or call it directly:

```bash
/path/to/codex-vault-driven-development-plugin/bin/vdd lint
```

## 3. Verify

From the project root:

```bash
vdd lint
```

An empty scaffold should pass with exit 0.

## 4. Create First Layer Pages

```bash
vdd bootstrap
vdd bootstrap --write auth
```

Then fill the generated page with the layer's capability boundary, decisions, and `code_refs`.

## 5. Work With Codex

Ask naturally:

- "set up VDD here"
- "plan this change with the vault first"
- "implement the approved plan"
- "review vault drift"
- "wrap up and suggest a commit message"

Codex should follow the matching VDD skill, read the vault first, run deterministic `vdd` tools, and verify with `vdd lint` before completion claims.
