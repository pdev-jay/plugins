#!/usr/bin/env bash
#
# vault scaffold installer — drops descriptive SoT scaffold into <project>/docs/vault/
#
# Usage:
#   ~/codex-vault-driven-development-plugin/install.sh [project_root]
#
# Default project_root = $PWD.
#
# What it does (per-project only):
#   1. Creates docs/vault/ skeleton (index.md only — the sole per-project file)
#   2. {{PROJECT_NAME}} substitution in index.md
#   3. Prunes plugin-owned files (AGENTS.md / CONSTRAINTS.md / examples /
#      the old _lint.sh wrapper) from older installs — all now read from the plugin
#   4. Adds a VDD section to project-root AGENTS.md when absent
#
# What it does NOT do:
#   - Install the Codex plugin globally
#   - Register Claude hooks
#   - Copy ANYTHING plugin-owned per-project — schema / V-XX / examples / tools
#     all live in the plugin (`vdd` dispatcher runs every tool incl. `vdd lint`)
#
# Re-run safety:
#   - index.md and layer pages (per-project content) are never overwritten

set -euo pipefail

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── ARG PARSING ──────────────────────────────────────
PROJECT_ROOT=""
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0 ;;
    -*) echo "ERROR: unknown flag '$arg'" >&2; exit 1 ;;
    *)  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$arg" ;;
  esac
done
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
TARGET="$PROJECT_ROOT/docs/vault"

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "ERROR: project root '$PROJECT_ROOT' does not exist" >&2
  exit 1
fi

# ─── HELPERS ──────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
echo "==> vault scaffold installing into: $TARGET"

# ─── CREATE STRUCTURE ────────────────────────────────
mkdir -p "$TARGET" "$TARGET/_archive"

# Tooling layout: NOTHING plugin-owned is copied per-project. Every deterministic
# tool — including lint — runs through the `vdd` dispatcher on PATH (Codex
# adds <plugin>/bin to PATH): `vdd lint`, `vdd map`, `vdd blast <key>`,
# `vdd impact <file>`, … The dispatcher self-locates the plugin root via `$0`, so
# there is no per-project copy, no wrapper, and no <codex-vdd-plugin-root>
# dependency (Codex does NOT export it to Bash nor substitute it in SKILL
# bodies — verified empirically). Plugin updates take effect immediately.
#
# Legacy per-script wrappers AND the old `_lint.sh` wrapper from older installs
# are pruned below (the wrapper is relocated with the other plugin-owned files
# in the migration step further down).
for old in bootstrap.sh vdd-blast.sh vdd-plan.sh vdd-impact.sh vdd-schedule.sh vdd-map.sh grasp-gate.sh; do
  if [ -f "$TARGET/scripts/$old" ]; then
    mv "$TARGET/scripts/$old" "$TARGET/scripts/$old.removed.$TS" 2>/dev/null \
      && echo "    - $TARGET/scripts/$old (now on PATH via \`vdd $old\` — moved to .removed.$TS)"
  fi
done

# Prune deprecated scripts that should no longer exist in projects.
# vdd-yaml-lib.sh was a per-project sourced helper before plugin-only SoT;
# now plugin-only (sourced from ${PLUGIN_ROOT}scripts/).
# vdd-profile.sh was per-user-synced before plugin-only; ditto.
for old in vdd-yaml-lib.sh vdd-profile.sh migrate-from-harness.sh migrate-from-auto-wiki.sh; do
  if [ -f "$TARGET/scripts/$old" ]; then
    mv "$TARGET/scripts/$old" "$TARGET/scripts/$old.removed.$TS"
    echo "    - $TARGET/scripts/$old (deprecated — moved to .removed.$TS)"
  fi
done

# ─── PLUGIN-OWNED FILES ARE NOT COPIED PER-PROJECT ────
# The vault schema (scaffold/AGENTS.md), the V-XX invariants
# (scaffold/CONSTRAINTS.md), and the onboarding examples (scaffold/examples/)
# are universal and plugin-owned. They are NOT copied here:
#   - schema + V-XX  → the project AGENTS.md instruction injects their absolute plugin
#     paths into context every session; the model Reads them on demand.
#   - examples       → vdd-onboarding cats them from the plugin cache via the
#     same locator the `vdd` dispatcher uses.
# This means plugin updates to any of these take effect immediately, with no
# install.sh re-run, and nothing in docs/vault/ can drift from the plugin.
#
# Migration: older installs copied these per-project. Relocate any leftover
# copies into _archive/_migrated-<ts>/ — which every vault tool (lint, map,
# blast, impact, schedule) already excludes (`! -path "./_archive/*"`), so the
# pruned files never pollute the graph or trip lint, yet stay recoverable (a
# project that grew C-XX rules keeps them in the archive).
MIGRATED="$TARGET/_archive/_migrated-$TS"
_migrate() {
  local src="$1" label="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$MIGRATED"
  mv "$src" "$MIGRATED/"
  echo "    - $src ($label — moved to _archive/_migrated-$TS/)"
}
_migrate "$TARGET/AGENTS.md"      "now plugin-owned"
_migrate "$TARGET/CONSTRAINTS.md" "now plugin-owned"
_migrate "$TARGET/examples"       "now read from plugin cache"
_migrate "$TARGET/_lint.sh"       "lint now runs via 'vdd lint'"

# ─── PER-PROJECT INDEX ────────────────────────────────
if [ ! -f "$TARGET/index.md" ]; then
  cp "$VAULT_ROOT/scaffold/index.md" "$TARGET/index.md"
  sed -i.bak "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TARGET/index.md" && rm "$TARGET/index.md.bak"
  echo "    + $TARGET/index.md (skeleton for $PROJECT_NAME)"
else
  echo "    = $TARGET/index.md (preserved)"
fi

# ─── ROOT AGENTS.md SECTION ──────────────────────────
# Codex reads project guidance from AGENTS.md. Add a VDD section when the
# project does not have one yet; preserve existing user-authored guidance.
ROOT_AGENTS_MD="$PROJECT_ROOT/AGENTS.md"
ROOT_HINT_BLOCK="$(cat "$VAULT_ROOT/scaffold/AGENTS.md")"
if [ ! -f "$ROOT_AGENTS_MD" ]; then
  printf '# %s\n\n%s\n' "$PROJECT_NAME" "$ROOT_HINT_BLOCK" > "$ROOT_AGENTS_MD"
  echo "    + $ROOT_AGENTS_MD (new — VDD section)"
elif ! grep -qF "## Vault-Driven Development" "$ROOT_AGENTS_MD" 2>/dev/null; then
  {
    printf '\n'
    printf '%s\n' "$ROOT_HINT_BLOCK"
  } >> "$ROOT_AGENTS_MD"
  echo "    + $ROOT_AGENTS_MD (appended VDD section)"
else
  echo "    = $ROOT_AGENTS_MD (VDD section preserved)"
fi

# ─── LEGACY CLEANUP ───────────────────────────────────
# Per-project .profile from older VDD layouts is no longer used.
if [ -f "$TARGET/.profile" ]; then
  mv "$TARGET/.profile" "$TARGET/.profile.removed.$TS"
  echo "    - $TARGET/.profile (legacy profile system — moved to .removed.$TS)"
fi

# ─── DONE ─────────────────────────────────────────────
echo
echo "==> vault scaffold installed."
echo "    $TARGET"
echo
echo "    Codex adapter files live at:"
echo "      $VAULT_ROOT"
echo "    Ensure this plugin is installed/enabled in Codex, or keep"
echo "    $VAULT_ROOT/bin on PATH for the vdd dispatcher."
echo
echo "    Next steps:"
echo "      1. vdd lint                          # verify (0/0 expected)"
echo "      2. vdd bootstrap                     # survey codebase"
echo "      3. vdd bootstrap --write <layer>     # scaffold first layer page"
echo "      4. Open $TARGET/index.md and start filling layer list"
echo "      (Inside Codex: ask for vdd-init to handle 1-3 interactively.)"
echo "      Note: every tool — incl. \`vdd lint\` — is on PATH via the \`vdd\`"
echo "      dispatcher and delegates to the plugin, so plugin updates take effect"
echo "      immediately (no install.sh re-run, nothing plugin-owned copied per-project)."
echo
echo "    Optional — Obsidian MCP remains a read-side accelerator when available."
echo "      Skip entirely and VDD still works — skills fall back to filesystem grep."
