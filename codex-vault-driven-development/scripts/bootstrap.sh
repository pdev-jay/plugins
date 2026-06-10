#!/usr/bin/env bash
#
# bootstrap.sh — vault page generation helper
#
# Two modes:
#   - SURVEY (default): scan codebase, suggest layer structure, output to stdout
#   - WRITE (--write):  actually create skeleton pages for confirmed layers
#
# Usage:
#   vdd bootstrap                    # survey
#   vdd bootstrap --write <layer>    # create skeleton for one layer
#
# This is a STARTER. For full LLM-assisted bootstrap (where an agent inspects
# code + writes WHY content), this script just lays the structural skeleton.

set -uo pipefail

# Plugin-only SoT — invoked via the `vdd` dispatcher (plugin bin/ on PATH).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
VAULT="$PROJECT_ROOT/docs/vault"
if [ ! -d "$VAULT" ]; then
  echo "ERROR: no docs/vault/ at $PROJECT_ROOT — run from a project root or set CODEX_PROJECT_DIR or CLAUDE_PROJECT_DIR" >&2
  exit 1
fi

MODE="survey"
LAYER=""
if [ "${1:-}" = "--write" ]; then
  MODE="write"
  LAYER="${2:-}"
  if [ -z "$LAYER" ]; then
    echo "Usage: bootstrap.sh --write <layer-slug>" >&2
    exit 1
  fi
fi

# ─── SURVEY MODE ─────────────────────────────────
if [ "$MODE" = "survey" ]; then
  echo "==> Vault bootstrap survey for: $PROJECT_ROOT"
  echo

  echo "── Detected feature folders (lib/features/, src/features/, app/features/) ──"
  for base in lib/features src/features app/features; do
    if [ -d "$PROJECT_ROOT/$base" ]; then
      ls "$PROJECT_ROOT/$base" 2>/dev/null | sed 's/^/  /'
    fi
  done
  echo

  echo "── Detected state-holder folders (lib/shared/bloc/, src/store/, state/, etc.) ──"
  for base in lib/shared/bloc lib/store src/store src/state; do
    if [ -d "$PROJECT_ROOT/$base" ]; then
      ls "$PROJECT_ROOT/$base" 2>/dev/null | sed 's/^/  /'
    fi
  done
  echo

  echo "── Detected native folders (android/, ios/, native/) ──"
  for d in android ios native; do
    [ -d "$PROJECT_ROOT/$d" ] && echo "  $d/ (consider native-bridges layer)"
  done
  echo

  echo "── Existing vault layers (current docs/vault/) ──"
  for d in "$VAULT"/*/; do
    [ -d "$d" ] || continue
    layer="$(basename "$d")"
    [ "$layer" = "_archive" ] && continue
    [ "$layer" = "scripts" ] && continue
    [ "$layer" = "examples" ] && continue
    pagecount=$(find "$d" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $layer/ ($pagecount pages)"
  done
  echo

  cat <<EOF
Next steps:
  1. Pick a layer slug to bootstrap (e.g. "auth")
  2. Run: vdd bootstrap --write auth
  3. Manually fill ## Capability boundary, ## Architectural conventions sections
  4. (Future) LLM-assisted: an agent inspects code and proposes WHY content

For now, this script only creates the structural skeleton.
EOF
  exit 0
fi

# ─── WRITE MODE ──────────────────────────────────
if [ "$MODE" = "write" ]; then
  TARGET_DIR="$VAULT/$LAYER"
  TARGET_INDEX="$TARGET_DIR/$LAYER.md"

  if [ -e "$TARGET_INDEX" ]; then
    echo "ERROR: $TARGET_INDEX already exists — won't overwrite" >&2
    exit 1
  fi

  mkdir -p "$TARGET_DIR"
  TODAY="$(date +%Y-%m-%d)"

  cat > "$TARGET_INDEX" <<EOF
---
title: $LAYER
zoom: 0
parent: null
children: []
status: draft
broadcasts: []
reacts_to: []
emits_to: []
intent_refs: []
code_refs:
  # TODO: add code paths this layer covers
  # - lib/features/$LAYER/
tasks:
  - {todo: "Fill ## Capability boundary section", priority: high}
  - {todo: "Draw ## Structure ASCII diagram (children tree)", priority: high}
  - {todo: "Draw ## Flow ASCII diagram (broadcast / state machine / sequence)", priority: high}
  - {todo: "List children pages", priority: high}
  - {todo: "Document ## Architectural conventions", priority: med}
decisions: []
updated: $TODAY
---

# $LAYER

(One-paragraph capability summary — TODO)

## Structure

\`\`\`
$LAYER/
├── _state-contract  ─ TODO (define broadcast keys)
└── (children pages — TODO)
\`\`\`

(if no zoom-in, replace with \`(no zoom-in — single state-holder/page)\`)

## Flow

\`\`\`
TODO — primary mechanism diagram for this layer.

  Types (pick the best fit):
   ▸ broadcast flow   — emitter → keys → reactors
   ▸ state machine    — phase transitions
   ▸ sequence/pipeline — bootstrap/contract path
   ▸ decision tree    — pattern dispatch

  ASCII only (no Mermaid). Box chars: ─ │ ┌ ┐ └ ┘ ├ ┤ ▼ ◄ ►
  Mark ★ hot risk, ⚠ divergence.
\`\`\`

## Capability boundary

What this layer owns:
- TODO

What this layer does not own:
- TODO

## Children (zoom-in)

(wikilink list of zoom 1 pages — TODO)

## Architectural conventions

(invariants of this layer — TODO)

## Cross-layer dependencies

- → (what this layer depends on)
- ← (what depends on this layer)

## Open issues / drift watch

- TODO
EOF

  echo "==> created $TARGET_INDEX (status: draft)"
  echo "    Next: edit this file, then vdd lint"
fi
