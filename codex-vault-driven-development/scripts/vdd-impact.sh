#!/usr/bin/env bash
#
# vdd-impact.sh — reverse query: given a code file, list vault pages that
# own it via `code_refs` + the broadcasts those layers emit.
#
# Counterpart to vdd-blast.sh (broadcast key → reactor pages).
# Use BEFORE editing a code file to understand multi-layer impact.
#
# Usage:
#   vdd impact <code-file>
#
# Examples:
#   vdd impact src/auth/session.ts
#   vdd impact lib/shared/event_bus.dart
#
# Output:
#   - owning vault pages (matched via code_refs grep)
#   - per-layer broadcasts (cross-layer signal sources)
#   - layer impact summary
#   - paranoid-profile read targets (layer page + _state-contract.md when
#     broadcasts non-empty)

set -uo pipefail

# Plugin-only SoT — this script is invoked via the `vdd` dispatcher
# and operates on the caller's project vault, not on a copy of itself.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
VAULT="$PROJECT_ROOT/docs/vault"
if [ ! -d "$VAULT" ]; then
  echo "ERROR: no docs/vault/ at $PROJECT_ROOT — run from a project root or set CODEX_PROJECT_DIR or CLAUDE_PROJECT_DIR" >&2
  exit 1
fi

# Canonical YAML extractors (single source of truth — sourced from plugin path).
_VDD_LIB="$LIB_DIR/vdd-yaml-lib.sh"
if ! . "$_VDD_LIB" 2>/dev/null; then
  echo "ERROR: $_VDD_LIB not found — plugin install may be corrupt (re-run claude plugin install vault-driven-development@pdev-jay)" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  cat <<EOF >&2
Usage: vdd-impact <code-file>

  <code-file>: path to a code file (relative to project root, or absolute)

Examples:
  vdd impact src/auth/session.ts
  vdd impact lib/shared/event_bus.dart
EOF
  exit 1
fi

INPUT="$1"

# Normalize to project-relative path
if [[ "$INPUT" = /* ]]; then
  REL_PATH="${INPUT#$PROJECT_ROOT/}"
else
  REL_PATH="$INPUT"
fi

# Find vault pages referencing this path via code_refs — EXACT path match
# (entry path == REL_PATH, or a directory code_ref that REL_PATH is under).
# The former `grep -rlwF "$REL_PATH"` mis-owned files: grep -w treats '/' and
# '.' as non-word, so basename / suffix / prefix collisions (login.dart vs
# login.dart.bak, lib/a.dart vs old/lib/a.dart) produced false owners and a
# project-root prefix mismatch produced silent misses.
OWNING_PAGES="$(
  while IFS= read -r _pg; do
    while IFS= read -r _ref; do
      [ -z "$_ref" ] && continue
      _rp="${_ref%%#*}"
      if [ "$_rp" = "$REL_PATH" ]; then
        echo "$_pg"; break
      elif [ "${_rp%/}" != "$_rp" ] && [ "${REL_PATH#"$_rp"}" != "$REL_PATH" ]; then
        echo "$_pg"; break
      fi
    done < <(extract_list "$_pg" code_refs)
  done < <(find "$VAULT" -type f -name "*.md" 2>/dev/null \
    | grep -vE '/(_reverse-index|_progress|_decisions|_open-issues|index|CLAUDE)\.md$' \
    | LC_ALL=C sort)
)"

echo "═══════════════════════════════════════════════"
echo "vdd impact: $REL_PATH"
echo "═══════════════════════════════════════════════"
echo

if [ -z "$OWNING_PAGES" ]; then
  echo "▼ No vault page references this file."
  echo
  echo "Hints:"
  echo "  - File may be untracked (no vault page owns it yet)."
  echo "  - If it should be vault-tracked, add to a layer page's code_refs."
  echo "  - Spec-first nudge fires on Write of new code files in populated vaults."
  exit 0
fi

# List broadcasts under a layer (layer page + _state-contract, merged).
# Uses the canonical extractor (inline + block + quotes + CRLF/BOM).
list_broadcasts() {
  local layer="$1" f
  for f in "$VAULT/${layer}/${layer}.md" "$VAULT/${layer}/_state-contract.md"; do
    [ -f "$f" ] || continue
    extract_list "$f" broadcasts
  done | LC_ALL=C sort -u
}

# Per-layer broadcasts presence check.
has_broadcasts() {
  [ -n "$(list_broadcasts "$1")" ]
}

# Resolve a page's intent_refs to VAULT-relative page paths.
# intent_refs are block-style `[[<layer>/<page>]]` wikilinks; resolution is
# by basename (Obsidian-style), matching _lint.sh's wikilink check.
resolve_intent_refs() {
  local f="$1"
  [ -f "$f" ] || return 0
  extract_list "$f" intent_refs | while IFS= read -r link; do
    [ -z "$link" ] && continue
    # Canonical extractor keeps wikilink brackets; strip them + any anchor.
    link="${link#\[\[}"; link="${link%\]\]}"
    link="${link%%#*}"
    [ -z "$link" ] && continue
    # Prefer the path-hinted form [[<layer>/<page>]] → docs/vault/<layer>/<page>.md
    if [ -f "$VAULT/$link.md" ]; then
      echo "$link.md"
      continue
    fi
    # Fall back to basename resolution (Obsidian-style), matching _lint.sh
    base="${link##*/}"
    [ -z "$base" ] && continue
    found="$(find "$VAULT" -type f -name "${base}.md" 2>/dev/null | LC_ALL=C sort | head -1)"
    [ -n "$found" ] && echo "${found#$VAULT/}"
  done
}

# Extract unique owning layers
OWNING_LAYERS=$(
  while IFS= read -r page; do
    [ -z "$page" ] && continue
    layer="${page#$VAULT/}"
    layer="${layer%%/*}"
    [ "$layer" = "${page#$VAULT/}" ] && continue
    echo "$layer"
  done <<< "$OWNING_PAGES" | sort -u
)

LAYER_COUNT=$(echo "$OWNING_LAYERS" | grep -c . || true)

# ─── Intent-dependency closure (transitive intent_refs) ──────────────
# Owning pages may declare intent_refs — vault pages whose decisions /
# conventions constrain them. Follow transitively (cycle-guarded via a SEEN
# set) so the impact set is the full intent closure, not just code_refs owners.
CLOSURE_FILE="$(mktemp)"
_SEEN_FILE="$(mktemp)"
_FRONTIER_FILE="$(mktemp)"
printf '%s\n' "$OWNING_PAGES" | while IFS= read -r p; do
  [ -z "$p" ] && continue
  echo "${p#$VAULT/}"
done | sort -u > "$_FRONTIER_FILE"
cp "$_FRONTIER_FILE" "$_SEEN_FILE"
while [ -s "$_FRONTIER_FILE" ]; do
  _NEXT_FILE="$(mktemp)"
  while IFS= read -r relpage; do
    [ -z "$relpage" ] && continue
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      if ! grep -qFx "$ref" "$_SEEN_FILE"; then
        echo "$ref" >> "$_SEEN_FILE"
        echo "$ref" >> "$_NEXT_FILE"
        echo "$ref" >> "$CLOSURE_FILE"
      fi
    done < <(resolve_intent_refs "$VAULT/$relpage")
  done < "$_FRONTIER_FILE"
  mv "$_NEXT_FILE" "$_FRONTIER_FILE"
done
rm -f "$_SEEN_FILE" "$_FRONTIER_FILE"

echo "▼ Owning vault pages ($LAYER_COUNT layer(s))"
while IFS= read -r page; do
  [ -z "$page" ] && continue
  echo "  - ${page#$PROJECT_ROOT/}"
done <<< "$OWNING_PAGES"
echo

echo "▼ Intent-dependency closure (transitive intent_refs)"
if [ -s "$CLOSURE_FILE" ]; then
  sort -u "$CLOSURE_FILE" | while IFS= read -r p; do
    echo "  - docs/vault/$p"
  done
else
  echo "  (none — owning pages declare no intent_refs)"
fi
echo

echo "▼ Per-layer broadcasts"
while IFS= read -r layer; do
  [ -z "$layer" ] && continue
  if has_broadcasts "$layer"; then
    echo "  - $layer:"
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      echo "      • $b"
    done < <(list_broadcasts "$layer")
  else
    echo "  - $layer: (none)"
  fi
done <<< "$OWNING_LAYERS"
echo

echo "▼ Layer impact summary"
echo "  affected layers: $LAYER_COUNT"
echo "$OWNING_LAYERS" | sed 's/^/    - /'
echo

# Read targets — vault pages that constrain the change
echo "▼ Read targets"
echo "  Layer pages to Read before editing:"
while IFS= read -r layer; do
  [ -z "$layer" ] && continue
  echo "    - docs/vault/${layer}/${layer}.md"
done <<< "$OWNING_LAYERS"
if [ -s "$CLOSURE_FILE" ]; then
  echo "  + intent_refs closure (conventions here constrain the change — read too):"
  sort -u "$CLOSURE_FILE" | while IFS= read -r p; do
    echo "    - docs/vault/$p"
  done
fi
echo
echo "  Also Read _state-contract.md for layers with non-empty broadcasts:"
while IFS= read -r layer; do
  [ -z "$layer" ] && continue
  if has_broadcasts "$layer"; then
    echo "    - docs/vault/${layer}/_state-contract.md"
  fi
done <<< "$OWNING_LAYERS"
echo
echo "  For broadcast graph changes, also run vdd-blast.sh for each affected key."
echo

rm -f "$CLOSURE_FILE"

echo "═══════════════════════════════════════════════"
echo "Next action candidates:"
echo "  - Read the un-read layer pages before editing $REL_PATH"
echo "  - For broadcast-emitting layers: also Read _state-contract.md"
echo "  - For broadcast key impact (reactor pages):"
echo "      vdd blast <key>"
echo "═══════════════════════════════════════════════"
