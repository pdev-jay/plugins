# Contributing

Issues and PRs welcome. The skill catalog and frontmatter schema are not yet stable — open an issue before sending non-trivial changes.

## Local check

```bash
# Regression locks (also run in CI smoke.yml) — run before sending a PR:
bash dev/test/run.sh        # deterministic-script golden + _lint exit-code tests
bash dev/check-counts.sh    # skill/agent/hook/lint-check count drift guard

# After an INTENTIONAL change to a deterministic script's output, regenerate
# the goldens and review the diff before committing (never blind-update):
UPDATE_GOLDEN=1 bash dev/test/run.sh

# End-to-end scaffold check (from the plugin repo root):
./install.sh /tmp/vdd-test-project
PATH="$PWD/bin:$PATH" CLAUDE_PROJECT_DIR=/tmp/vdd-test-project vdd lint
# (`vdd` is the dispatcher in bin/ — in a Claude Code session it is already on
#  PATH; in a plain terminal prepend bin/ as shown. Nothing is copied
#  per-project: lint runs straight from the plugin's scripts/_lint.sh.)
```

## Conventions

- **Commit messages** — Conventional Commits. type/scope English, description Korean or English (consistent within a commit).
- **No AI-tool attribution in commits** — no `Co-Authored-By: Claude`, no "Generated with..." footers.
- **Skill frontmatter** — every skill declares `Use when` / `Skip when` / `Skill type` / `Boundary`. See existing skills for examples.
- **Body language** — skill/agent bodies English (the multilingual surface is the `description:` frontmatter trigger catalog only). Exception: verbatim Korean output templates the agent must speak to a Korean user. Author-enforced — the old `no Korean in BODY` smoke check was removed because it false-flagged that exception with no clean carve-out.
- **CHANGELOG** — add a line under `[Unreleased]` for any user-visible change.

## License

By contributing you agree your contributions are MIT-licensed (see `LICENSE`).
