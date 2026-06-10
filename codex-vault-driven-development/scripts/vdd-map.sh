#!/usr/bin/env bash
#
# vdd-map.sh — render the vault's broadcast/intent graph as a Mermaid diagram
#
# The map is DERIVED from frontmatter (broadcasts / reacts_to / emits_to), never
# authored. Same data vdd-blast.sh traverses for one key — this renders the whole
# graph. Because it derives from the lint-enforced frontmatter, the map can never
# be staler than the vault (no separate sync, unlike code-scanned graphs).
#
# Usage:
#   vdd map [mode] [--layer <name>] [--no-fence]
#
# Modes:
#   (default)    collapsed — layer-level nodes; one edge per cross-layer signal key
#                (namespace prefix stripped from the label). The teaching view:
#                spine + fan-in + isolated layers at a glance.
#   --raw        key-level — every broadcast key as a node, grouped by emitter layer;
#                edges to consumer layers. Unconsumed keys (reactor 0) dimmed.
#   --orphans    audit (text, not graph) — lists broadcast keys with zero reactor,
#                grouped by layer. Cross-vault V-05 (orphan broadcast) visualization.
#   --layer <n>  restrict raw view to one layer's emitted keys + their consumers.
#   --no-fence   omit the ```mermaid code fence (raw mermaid for piping).
#
# Examples:
#   vdd map                  # collapsed layer map
#   vdd map --raw            # full key-level map
#   vdd map --orphans        # orphan-key audit
#   vdd map --raw --layer auth
#
# Identity model: a broadcast key is identified by (emitter LAYER, key), so the
# layer page and its _state-contract mirror collapse to one node, and same-named
# keys in different layers (loaded, initial, …) stay distinct. reacts_to / emits_to
# anchors (layer/_state-contract#key) carry the emitter layer; bare keys are
# resolved against declared broadcasts.

set -uo pipefail

# ── args (parsed before any vault/lib access so --help works anywhere) ──────
MODE="collapsed"
FILTER_LAYER=""
FENCE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --raw)      MODE="raw" ;;
    --orphans)  MODE="orphans" ;;
    --layer)    shift; FILTER_LAYER="${1:-}" ;;
    --no-fence) FENCE=0 ;;
    -h|--help)
      sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "ERROR: unknown arg '$1' (see --help)" >&2; exit 1 ;;
  esac
  shift
done

# Plugin-only SoT — invoked via the `vdd` dispatcher (plugin bin/ on PATH).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
VAULT="$PROJECT_ROOT/docs/vault"
if [ ! -d "$VAULT" ]; then
  echo "ERROR: no docs/vault/ at $PROJECT_ROOT — run from a project root or set CODEX_PROJECT_DIR or CLAUDE_PROJECT_DIR" >&2
  exit 1
fi

# Canonical YAML extractors — sourced from plugin path.
_VDD_LIB="$LIB_DIR/vdd-yaml-lib.sh"
if ! . "$_VDD_LIB" 2>/dev/null; then
  echo "ERROR: $_VDD_LIB not found — plugin install may be corrupt (re-run claude plugin install vault-driven-development@pdev-jay)" >&2
  exit 1
fi

cd "$VAULT" || exit 1

# Page set: every layer page (path has a layer folder), minus rollups/examples/archive.
# Top-level files (index.md, CONSTRAINTS.md, _decisions.md, …) have no layer folder
# and carry no graph relations — skipped by the */* requirement in the loop.
list_pages() {
  find . -type f -name "*.md" ! -path "./examples/*" ! -path "./_archive/*" ! -path "*.removed.*" ! -path "*.bak.*" | sort
}

# ── data collection ─────────────────────────────────────────────────────────
# BCASTS: one line per declared broadcast key   →  <layer>\t<key>
# EDGES:  one line per consumer edge            →  <emLayer>\t<key>\t<conLayer>\t<kind>
BCASTS="$(mktemp)"; EDGES="$(mktemp)"; BC_RESOLVE="$(mktemp)"
trap 'rm -f "$BCASTS" "$EDGES" "$BC_RESOLVE"' EXIT

norm_key() { case "$1" in *\#*) echo "${1#*#}" ;; *) echo "$1" ;; esac; }
layer_of() { local r="${1#./}"; echo "${r%%/*}"; }

while IFS= read -r f; do
  rel="${f#./}"
  case "$rel" in */*) : ;; *) continue ;; esac   # require a layer folder
  lyr="${rel%%/*}"

  while IFS= read -r b; do
    [ -z "$b" ] && continue
    printf '%s\t%s\n' "$lyr" "$(norm_key "$b")" >> "$BCASTS"
  done < <(extract_list "$f" "broadcasts")

  for kind in reacts_to emits_to; do
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      key="$(norm_key "$r")"
      case "$r" in
        */*\#*) emL="$(layer_of "${r%%\#*}")" ;;   # anchored: emitter layer from path
        *\#*)   emL="$(layer_of "${r%%\#*}")" ;;
        *)      emL="?" ;;                          # bare key — resolve later
      esac
      printf '%s\t%s\t%s\t%s\n' "$emL" "$key" "$lyr" "${kind%_to}" >> "$EDGES"
    done < <(extract_list "$f" "$kind")
  done
done < <(list_pages)

# Resolve bare-key edges (emitter layer "?") against declared broadcasts.
# Unique owning layer → bind; ambiguous/none → leave "?" (drawn as external).
sort -u "$BCASTS" > "$BC_RESOLVE"
if grep -q $'^?\t' "$EDGES" 2>/dev/null; then
  RESOLVED="$(mktemp)"
  while IFS=$'\t' read -r emL key conL kind; do
    if [ "$emL" = "?" ]; then
      owners="$(awk -F'\t' -v k="$key" '$2==k{print $1}' "$BC_RESOLVE" | sort -u)"
      if [ "$(printf '%s\n' "$owners" | grep -c .)" = "1" ]; then emL="$owners"; fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$emL" "$key" "$conL" "$kind"
  done < "$EDGES" > "$RESOLVED"
  mv "$RESOLVED" "$EDGES"
fi

# ── helpers ──────────────────────────────────────────────────────────────────
sanitize() { echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'; }
fence_open()  { [ "$FENCE" = 1 ] && echo '```mermaid'; }
fence_close() { [ "$FENCE" = 1 ] && echo '```'; }

# layers seen in the signal graph (emit or react)
graph_layers() { cut -f1 "$BCASTS" 2>/dev/null; cut -f1 "$EDGES" 2>/dev/null; cut -f3 "$EDGES" 2>/dev/null; }
# every layer folder on disk (a dir under vault root holding a layer page),
# minus system dirs — so signal-silent layers still surface (gap candidates).
fs_layers() {
  find . -mindepth 2 -maxdepth 2 -name "*.md" ! -path "./examples/*" ! -path "./_archive/*" ! -path "./scripts/*" ! -path "*.removed.*" ! -path "*.bak.*" \
    | sed 's#^\./##; s#/.*##' | sort -u
}
all_layers() { { graph_layers; fs_layers; } | sort -u | grep -v '^$' | grep -v '^?$'; }

# A (layer,key) is consumed iff some edge targets it.
key_consumed() {
  awk -F'\t' -v l="$1" -v k="$2" '$1==l && $2==k{found=1} END{exit !found}' "$EDGES"
}

# ── orphans mode (text audit) ────────────────────────────────────────────────
if [ "$MODE" = "orphans" ]; then
  echo "═══════════════════════════════════════════════"
  echo "vdd-map orphans — broadcast keys with zero reactor"
  echo "  (cross-vault V-05 audit; some are expected — UI states read"
  echo "   directly via the framework, not via reacts_to)"
  echo "═══════════════════════════════════════════════"
  echo
  total=0; dark=0; cur=""
  while IFS=$'\t' read -r lyr key; do
    [ -n "$FILTER_LAYER" ] && [ "$lyr" != "$FILTER_LAYER" ] && continue
    total=$((total+1))
    if ! key_consumed "$lyr" "$key"; then
      if [ "$lyr" != "$cur" ]; then echo "▼ $lyr"; cur="$lyr"; fi
      echo "    ✗ $key"
      dark=$((dark+1))
    fi
  done < <(sort -u "$BCASTS")
  echo
  echo "─ keys: $total declared / $dark with zero reactor"
  exit 0
fi

# ── raw mode (key-level Mermaid) ─────────────────────────────────────────────
if [ "$MODE" = "raw" ]; then
  fence_open
  echo "graph LR"
  # emitter subgraphs: one per layer, listing its broadcast keys as nodes
  for lyr in $(cut -f1 "$BC_RESOLVE" | sort -u); do
    [ -n "$FILTER_LAYER" ] && [ "$lyr" != "$FILTER_LAYER" ] && continue
    echo "  subgraph SG_$(sanitize "$lyr")[\"$lyr\"]"
    while IFS=$'\t' read -r l key; do
      [ "$l" = "$lyr" ] || continue
      nid="K_$(sanitize "$lyr")__$(sanitize "$key")"
      if key_consumed "$lyr" "$key"; then
        echo "    ${nid}[\"$key\"]"
      else
        echo "    ${nid}[\"$key\"]:::dark"
      fi
    done < <(awk -F'\t' -v l="$lyr" '$1==l' "$BC_RESOLVE" | sort -u)
    echo "  end"
  done
  # edges: keyNode → consumer layer node
  sort -u "$EDGES" | while IFS=$'\t' read -r emL key conL kind; do
    [ "$emL" = "?" ] && continue
    if [ -n "$FILTER_LAYER" ] && [ "$emL" != "$FILTER_LAYER" ] && [ "$conL" != "$FILTER_LAYER" ]; then continue; fi
    nid="K_$(sanitize "$emL")__$(sanitize "$key")"
    cid="L_$(sanitize "$conL")"
    if [ "$kind" = "reacts" ]; then echo "  ${nid} --> ${cid}[\"$conL\"]"
    else                            echo "  ${nid} -.-> ${cid}[\"$conL\"]"; fi
  done
  echo "  classDef dark fill:#f0f0f0,stroke:#ccc,color:#aaa,stroke-dasharray:2;"
  fence_close
  exit 0
fi

# ── collapsed mode (layer-level Mermaid, default) ────────────────────────────
fence_open
echo "graph LR"
# declare every layer node (so isolated layers still appear)
for lyr in $(all_layers | sort -u | grep -v '^$' | grep -v '^?$'); do
  echo "  L_$(sanitize "$lyr")[\"$lyr\"]"
done
# one edge per cross-layer (emitter,consumer,key) — short lines, paste-safe.
# (aggregating all keys into one <br/>-joined label produced 160+ char lines that
#  soft-wrap in terminals; copying the wrap injects a real newline mid-statement
#  and Mermaid rejects it — got 'NEWLINE'. one key per line never wraps.)
# self-edges (intra-layer emits) omitted — internal, not cross-layer signal.
# label = key with its "<prefix>:" namespace stripped (the emitter node already names it).
awk -F'\t' '$1!="?" && $1!=$3 {print $1"\t"$3"\t"$2"\t"$4}' "$EDGES" | sort -u \
  | awk -F'\t' '
      function san(s){ gsub(/[^a-zA-Z0-9]/,"_",s); return s }
      function lbl(k,  i){ i=index(k,":"); return i ? substr(k,i+1) : k }
      { arrow = ($4=="reacts" ? " -->" : " -.->")
        print "  L_" san($1) arrow "|\"" lbl($3) "\"| L_" san($2)
      }
    '
# mark isolated layers (no in/out cross-layer edge) as dark
for lyr in $(all_layers | sort -u | grep -v '^$' | grep -v '^?$'); do
  if ! awk -F'\t' -v l="$lyr" '$1!="?" && $1!=$3 && ($1==l||$3==l){f=1} END{exit !f}' "$EDGES"; then
    echo "  class L_$(sanitize "$lyr") iso;"
  fi
done
echo "  classDef iso fill:#f5f5f5,stroke:#bbb,color:#999,stroke-dasharray:3;"
fence_close
