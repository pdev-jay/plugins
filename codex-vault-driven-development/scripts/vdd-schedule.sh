#!/usr/bin/env bash
#
# vdd-schedule.sh — deterministic parallel-batch scheduler for a set of owner_pages
#
# Usage:
#   vdd schedule <page> [<page> ...]
#   vdd schedule -            # read page list from stdin
#
#   <page>: a vault path (auth/auth.md), a path w/o extension (auth/auth),
#           or a bare slug (connection) — resolved to one .md under docs/vault/.
#
# What it computes:
#   Given the set of vault pages a plan will modify (the owner_pages), restricts
#   the broadcast graph to that set and derives precedence edges:
#     - B before P  when  P reacts_to a key B broadcasts        (consumer after producer)
#     - B before P  when  P emits_to  a key B broadcasts        (emitter after contract decl)
#     - B before P  when  P intent_refs [[B]] and B is in-set   (intent source settled first)
#   then layers the DAG into parallel-safe batches (Kahn's algorithm). Pages in
#   the same batch share no in-set edge → safe to dispatch concurrently. A barrier
#   sits between batches.
#
# Output:
#   - precedence edges (with reason)
#   - external dependencies (in-set page needs a key no in-set page broadcasts)
#   - the parallel batch schedule
#   - a machine-parseable block (SCHEDULE_BATCH lines) for vdd-build to consume
#   - a dispatch directive (batch count + max parallel width)
#
# Exit codes:
#   0  schedule computed (acyclic)
#   1  usage / no-vault / unresolved-page error
#   3  contract cycle among in-set pages — residual reported, NOT a clean schedule
#
# Pairs with vdd-build: this script replaces the eyeballed "≥3 independent
# groups" heuristic with a computed batch schedule. vdd-build dispatches
# batch-by-batch (parallel within a batch, barrier between).

set -uo pipefail

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

if [ $# -lt 1 ]; then
  cat <<EOF >&2
Usage: vdd-schedule <page> [<page> ...]
       vdd-schedule -            # read page list from stdin (one per line)

  <page>: vault path (auth/auth.md), path w/o ext (auth/auth), or bare slug (connection).

Examples:
  vdd schedule auth/auth connection/connection
  vdd schedule auth/_state-contract auth/auth connection/connection
EOF
  exit 1
fi

cd "$VAULT" || exit 1

norm() { if [[ "$1" == *"#"* ]]; then echo "${1#*#}"; else echo "$1"; fi; }

# ─── STEP 1: collect + resolve input pages → node ids (relative path w/o .md) ──
RAW_ARGS=()
if [ "$1" = "-" ]; then
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"    # rtrim
    [ -z "$line" ] && continue
    RAW_ARGS+=("$line")
  done
else
  RAW_ARGS=("$@")
fi

resolve_page() {
  local a="$1" f=""
  if [ -f "$a" ]; then f="$a"
  elif [ -f "$a.md" ]; then f="$a.md"
  else
    local base; base="$(basename "$a")"; base="${base%.md}"
    local hits n
    hits="$(find . -type f -name "$base.md" ! -path "./examples/*" ! -path "./_archive/*" ! -path "*.removed.*" ! -path "*.bak.*" | sed 's|^\./||')"
    n="$(printf '%s\n' "$hits" | grep -c . || true)"
    if [ "$n" -eq 1 ]; then
      f="$hits"
    elif [ "$n" -gt 1 ]; then
      echo "ERROR: ambiguous page '$a' — matches multiple files:" >&2
      printf '%s\n' "$hits" | sed 's/^/    /' >&2
      return 1
    else
      echo "ERROR: page not found: '$a'" >&2
      return 1
    fi
  fi
  echo "${f#./}" | sed 's/\.md$//'
}

NODES=()
for a in "${RAW_ARGS[@]}"; do
  nid="$(resolve_page "$a")" || exit 1
  NODES+=("$nid")
done

# Sorted-unique node list (determinism: batch member order is sorted).
NODE_LIST="$(printf '%s\n' "${NODES[@]}" | sort -u)"
NODE_COUNT="$(printf '%s\n' "$NODE_LIST" | grep -c . | tr -d ' ')"

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT
NODE_FILE="$TMPDIR_LOCAL/nodes.txt"
printf '%s\n' "$NODE_LIST" > "$NODE_FILE"

# ─── STEP 2: index broadcasters within the node set: key → node ──────────────
# BCAST_FILE lines: "<key>\t<node>"
BCAST_FILE="$TMPDIR_LOCAL/bcast.txt"
> "$BCAST_FILE"
while IFS= read -r node; do
  [ -z "$node" ] && continue
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    printf '%s\t%s\n' "$(norm "$k")" "$node" >> "$BCAST_FILE"
  done < <(extract_list "$node.md" broadcasts)
done < "$NODE_FILE"

# in-set basename → node (for intent_refs without a slash)
basename_node() {
  local b="$1" hit
  hit="$(while IFS= read -r n; do [ "$(basename "$n")" = "$b" ] && echo "$n"; done < "$NODE_FILE" | head -1)"
  echo "$hit"
}

# broadcasters of a key within the set (may be several)
broadcasters_of() {
  local key="$1"
  awk -F'\t' -v k="$key" '$1==k {print $2}' "$BCAST_FILE"
}

# ─── STEP 3: derive precedence edges (FROM before TO) ────────────────────────
# EDGES_DISPLAY lines: "<from>|<to>|<reason>"  ;  EXTERNAL lines: "<node>|<key>|<kind>"
EDGES_DISPLAY="$TMPDIR_LOCAL/edges_display.txt"
EDGES_GRAPH="$TMPDIR_LOCAL/edges_graph.txt"   # "<from>\t<to>"
EXTERNAL="$TMPDIR_LOCAL/external.txt"
> "$EDGES_DISPLAY"; > "$EDGES_GRAPH"; > "$EXTERNAL"

add_signal_edges() {
  local node="$1" kind="$2"   # kind = reacts_to | emits_to
  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    local key; key="$(norm "$raw")"
    local found=0
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      found=1
      [ "$b" = "$node" ] && continue
      printf '%s|%s|%s %s\n' "$b" "$node" "$kind" "$key" >> "$EDGES_DISPLAY"
      printf '%s\t%s\n' "$b" "$node" >> "$EDGES_GRAPH"
    done < <(broadcasters_of "$key")
    [ "$found" -eq 0 ] && printf '%s|%s|%s\n' "$node" "$key" "$kind" >> "$EXTERNAL"
  done < <(extract_list "$node.md" "$kind")
}

while IFS= read -r node; do
  [ -z "$node" ] && continue
  add_signal_edges "$node" reacts_to
  add_signal_edges "$node" emits_to
  # intent_refs → in-set source settled first
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    inner="$ref"
    inner="${inner#"[["}"; inner="${inner%"]]"}"
    inner="${inner%%#*}"
    local_src=""
    if [[ "$inner" == */* ]]; then
      while IFS= read -r n; do [ "$n" = "$inner" ] && local_src="$n"; done < "$NODE_FILE"
    else
      local_src="$(basename_node "$inner")"
    fi
    [ -z "$local_src" ] && continue
    [ "$local_src" = "$node" ] && continue
    printf '%s|%s|%s\n' "$local_src" "$node" "intent_refs" >> "$EDGES_DISPLAY"
    printf '%s\t%s\n' "$local_src" "$node" >> "$EDGES_GRAPH"
  done < <(extract_list "$node.md" intent_refs)
done < "$NODE_FILE"

sort -u "$EDGES_GRAPH" -o "$EDGES_GRAPH"

# ─── STEP 4: Kahn layering (awk; bash-3.2 safe) ──────────────────────────────
# Reads NODE_FILE first (sorted), then EDGES_GRAPH. Emits:
#   BATCH <n> <node> [<node> ...]
#   CYCLE <node> [<node> ...]     (only if a cycle leaves nodes unprocessed)
SCHED_FILE="$TMPDIR_LOCAL/sched.txt"
awk '
  NR==FNR { node[$0]=1; nodes[++nn]=$0; next }
  {
    from=$1; to=$2
    if (node[from] && node[to] && from!=to) {
      ekey=from SUBSEP to
      if (!(ekey in seen)) { seen[ekey]=1; succ[from]=succ[from] " " to; indeg[to]++ }
    }
  }
  END {
    for (i=1;i<=nn;i++){ n=nodes[i]; if (!(n in indeg)) indeg[n]=0 }
    remaining=nn; batch=0
    while (remaining>0) {
      cnt=0
      for (i=1;i<=nn;i++){ n=nodes[i]; if (!done[n] && indeg[n]==0) layer[++cnt]=n }
      if (cnt==0) break
      batch++
      printf "BATCH %d", batch
      for (j=1;j<=cnt;j++) printf " %s", layer[j]
      printf "\n"
      for (j=1;j<=cnt;j++){
        n=layer[j]; done[n]=1; remaining--
        m=split(succ[n], s, " ")
        for (k=1;k<=m;k++) if (s[k]!="") indeg[s[k]]--
      }
      for (j=1;j<=cnt;j++) delete layer[j]
    }
    if (remaining>0) {
      printf "CYCLE"
      for (i=1;i<=nn;i++){ n=nodes[i]; if (!done[n]) printf " %s", n }
      printf "\n"
    }
  }
' "$NODE_FILE" "$EDGES_GRAPH" > "$SCHED_FILE"

# ─── STEP 5: report ──────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "vdd-schedule"
echo "  input pages: $NODE_COUNT"
echo "═══════════════════════════════════════════════"
echo

EDGE_COUNT="$(grep -c . "$EDGES_GRAPH" || true)"
echo "▼ Precedence edges (FROM before TO):  $EDGE_COUNT"
if [ -s "$EDGES_DISPLAY" ]; then
  sort -u "$EDGES_DISPLAY" | while IFS='|' read -r from to reason; do
    echo "  $from  →  $to   ($reason)"
  done
else
  echo "  (none — all input pages are independent)"
fi
echo

if [ -s "$EXTERNAL" ]; then
  echo "▼ External dependencies (key not broadcast by any in-set page — assumed already settled)"
  sort -u "$EXTERNAL" | while IFS='|' read -r node key kind; do
    echo "  $node   $kind: $key"
  done
  echo
fi

echo "▼ Parallel batch schedule"
BATCH_TOTAL="$(grep -c '^BATCH ' "$SCHED_FILE" || true)"
MAX_WIDTH=0
while IFS= read -r line; do
  case "$line" in
    BATCH\ *)
      n="$(echo "$line" | awk '{print $2}')"
      members="$(echo "$line" | cut -d' ' -f3-)"
      width="$(printf '%s\n' $members | grep -c . | tr -d ' ')"
      [ "$width" -gt "$MAX_WIDTH" ] && MAX_WIDTH="$width"
      if [ "$width" -ge 2 ]; then mode="parallel, $width pages"; else mode="sequential, 1 page"; fi
      echo "  Batch $n ($mode):"
      for m in $members; do echo "    - $m"; done
      ;;
  esac
done < "$SCHED_FILE"

CYCLE_LINE="$(grep '^CYCLE ' "$SCHED_FILE" || true)"
if [ -n "$CYCLE_LINE" ]; then
  cyc_members="$(echo "$CYCLE_LINE" | cut -d' ' -f2-)"
  echo
  echo "  ⚠ CYCLE — contract loop among these pages (cannot order; co-edit or break the loop):"
  for m in $cyc_members; do echo "    - $m"; done
fi
echo

# ─── STEP 6: machine block + dispatch directive ──────────────────────────────
echo "▼ Machine block (for vdd-build)"
grep '^BATCH ' "$SCHED_FILE" | sed 's/^BATCH /SCHEDULE_BATCH /'
[ -n "$CYCLE_LINE" ] && echo "$CYCLE_LINE" | sed 's/^CYCLE /SCHEDULE_CYCLE /'
echo

echo "═══════════════════════════════════════════════"
echo "Dispatch directive"
echo "  batches:     $BATCH_TOTAL"
echo "  max width:   $MAX_WIDTH"
if [ -n "$CYCLE_LINE" ]; then
  echo "  → CYCLE present: resolve the contract loop (vdd-plan Mode C) before dispatch."
elif [ "$MAX_WIDTH" -ge 3 ]; then
  echo "  → vdd-build: dispatch batch-by-batch. Parallel (Phase 3) within batches of width ≥3;"
  echo "    barrier between batches; single _lint.sh after the final batch."
else
  echo "  → vdd-build: max width <3 — dispatch vdd-implementer sequentially in batch order"
  echo "    (parallelism does not pay off below 3); single _lint.sh after the final batch."
fi
echo "═══════════════════════════════════════════════"

[ -n "$CYCLE_LINE" ] && exit 3
exit 0
