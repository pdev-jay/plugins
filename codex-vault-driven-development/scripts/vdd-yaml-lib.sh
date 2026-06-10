#!/usr/bin/env bash
#
# vdd-yaml-lib.sh — canonical frontmatter YAML extractors (SOURCED, not run)
#
# Single source of truth for list / scalar / object-list extraction shared by
# _lint.sh and the deterministic vdd-* scripts. Replaces four divergent
# `extract_list` copies (only one of which handled inline arrays + quotes).
#
# Handles, uniformly:
#   - block-style:   key:
#                      - itemA
#                      - itemB
#   - inline-style:  key: [itemA, itemB]
#   - empty inline:  key: []                 → no items
#   - quoted items:  'phase:idle' / "x"      → quotes stripped (MCP YAML
#                                               writers add these)
#   - trailing note: key: [a]  # comment     → comment stripped, while a
#                                               '#' INSIDE a value (wikilink
#                                               anchor) is preserved
#   - CRLF line endings + a leading UTF-8 BOM → normalized before parsing
#                                               (otherwise /^---$/ never
#                                               matches and parsing silently
#                                               yields nothing)
#
# The Codex adapter instructions intentionally do NOT source this — they keep
# self-contained parsing by design. This library is for the scripts only.
#
# API:
#   extract_list <file> <key>      list items, one per line (file input)
#   extract_list_stdin <key>       same, reading stdin (pipe or `< file`)
#   extract_scalar <file> <key>    single scalar frontmatter value
#   extract_obj_list <file> <key>  raw object-list lines (tasks: / decisions:)
#
# Function names match the pre-consolidation call sites so callers are
# unchanged — each script only drops its local copy and sources this.
#
# bash 3.2 compatible. No associative arrays. Deterministic: input order is
# preserved; callers sort where ordering matters.

# Normalize an input stream: strip a leading UTF-8 BOM (first line only) and
# every CR. LC_ALL=C keeps byte semantics consistent across GNU / BSD.
_vdd_norm() { LC_ALL=C sed $'1s/^\xEF\xBB\xBF//' | tr -d '\r'; }

# Canonical list-extraction awk program — the ONE definition. Both the file
# and stdin wrappers run this exact program (zero drift by construction).
_VDD_LIST_AWK='
  BEGIN { in_block = 0 }
  /^---$/ { fm = !fm; next }
  !fm { exit }
  $0 ~ "^" key ":" {
    val = $0
    sub("^" key ":[[:space:]]*", "", val)
    # Strip trailing comment only when whitespace-preceded, so an in-value
    # "#" (wikilink anchor layer/_state-contract#key) survives.
    sub(/[[:space:]]+#.*$/, "", val)
    sub(/[[:space:]]+$/, "", val)
    if (val ~ /^\[.*\]$/) {
      sub(/^\[/, "", val); sub(/\]$/, "", val)
      n = split(val, items, ",")
      for (i = 1; i <= n; i++) {
        item = items[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
        gsub(/^["\047]|["\047]$/, "", item)
        if (item != "") print item
      }
      in_block = 0
    } else if (val == "") {
      in_block = 1
    } else {
      in_block = 0
    }
    next
  }
  in_block {
    if ($0 ~ /^[a-zA-Z_]+:/ || $0 == "---") { in_block = 0; next }
    if ($0 ~ /^[[:space:]]+-/) {
      sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
      sub(/[[:space:]]+#.*$/, "", $0)
      sub(/[[:space:]]+$/, "", $0)
      gsub(/^["\047]|["\047]$/, "", $0)
      if ($0 != "") print
    } else {
      in_block = 0
    }
  }
'

extract_list()       { [ -f "$1" ] || return 0; _vdd_norm < "$1" | awk -v key="$2" "$_VDD_LIST_AWK"; }
extract_list_stdin() { _vdd_norm | awk -v key="$1" "$_VDD_LIST_AWK"; }

# Scalar field — behavior identical to the pre-consolidation extract_scalar
# (no quote/comment stripping, to preserve titles containing '#' etc.); only
# CRLF/BOM normalization is added.
_VDD_SCALAR_AWK='
  BEGIN { fm = 0 }
  /^---$/ { fm = !fm; if (!fm) exit; next }
  fm && $0 ~ "^" key ":" {
    sub("^" key ":[[:space:]]*", "", $0)
    sub(/[[:space:]]+$/, "", $0)
    print $0; exit
  }
'
extract_scalar() { [ -f "$1" ] || return 0; _vdd_norm < "$1" | awk -v key="$2" "$_VDD_SCALAR_AWK"; }

# Object-list (tasks: / decisions:) — raw entry lines for downstream parsing.
# Behavior identical to the pre-consolidation extract_obj_list + CRLF/BOM.
_VDD_OBJ_AWK='
  BEGIN { fm = 0; in_block = 0 }
  /^---$/ { fm = !fm; if (!fm) exit; next }
  !fm { next }
  $0 ~ "^" key ":" { in_block = 1; next }
  in_block {
    if ($0 ~ /^[a-zA-Z_]+:/ || $0 == "---") { in_block = 0; next }
    if ($0 ~ /^[[:space:]]+-/) { print; next }
    if ($0 ~ /^[[:space:]]+[a-z]+:/) { print; next }
  }
'
extract_obj_list() { [ -f "$1" ] || return 0; _vdd_norm < "$1" | awk -v key="$2" "$_VDD_OBJ_AWK"; }
