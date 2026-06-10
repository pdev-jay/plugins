#!/usr/bin/env bash
#
# vault lint — validate wiki consistency + generate reverse-index
#
# Usage: vdd lint
#
# Checks (15 total + 4 auto-rollups — see body for exact markers):
#   1. frontmatter exists + LF-only (CRLF vault page = err)
#   2. wikilink resolution (basename matching) + basename uniqueness
#      (Hard Rule 3 — duplicate page basename = err)
#   3. code_refs path exists (missing file/dir = err — V-03, gates V-06)
#   4. code_refs symbol anchors (two-tier: broad presence + declaration
#      grep; heuristic — stays warn, not err)
#   5. broadcast / reacts_to / emits_to key consistency (undefined key
#      reference = err — V-02, gates V-06)
#   6. lint coverage (CONSTRAINTS ### V-XX ↔ # V-XX markers; a
#      `# V-XX: MANUAL` marker = acknowledged-uncovered, NOT counted as
#      an automated check; warn-only)
#   7. layer index diagram sections (zoom 0 page has ## Structure + ## Flow)
#   8. orphan broadcasts (declared with no reactor — V-05 partial)
#   9. stale `updated:` (active page untouched beyond threshold)
#  10. empty `decisions:` on non-trivial active page (V-04 partial)
#  11. oversized layer page body (zoom:0 over content threshold)
#  12. oversized `decisions[*].note` > 200 chars (V-08); plus 12b decisions
#      count cap (V-08 decay — too many active entries → archive nudge)
#  13. broadcast → code producer (V-09 — page declares broadcasts: but none
#      of its own code_refs files textually back the key; heuristic → warn)
#  14. review freshness (V-10 — page's code_refs content changed since its
#      reviewed_code_hash stamp; warn. `--stamp` writes the stamp)
#  15. silent layer detection (V-11 — layer with zero broadcasts/reacts_to/
#      emits_to/intent_refs across all its pages; INFO triage input, never warn)
#
# Auto-rollups (regenerated each run):
#   - _reverse-index.md     cross-layer broadcast → reactor map
#   - _progress.md          status + tasks rollup
#   - _decisions.md         chronological decision log
#   - _open-issues.md       tasks + drift watch rollup
#   - _digest-frontmatter.md  LLM-readable single-file snapshot of every
#                             page's frontmatter (index table + per-page
#                             broadcasts / reacts_to / code_refs + top
#                             decisions / tasks). Designed to be read in
#                             one shot for vault-only grounding without
#                             paging every layer page.
#   - _dependency-rules.md    Cross-cutting layer / dependency convention
#                             rollup. Aggregates every `decisions:` entry
#                             tagged `type: dependency-rule` across pages —
#                             subject-prefix must-not-import-forbidden-prefix
#                             rules. Section 6c additionally greps import-
#                             like lines under each subject and reports
#                             violations as warnings (never errors during
#                             introduction).
#
# bash 3.2 compatible (macOS default). No associative arrays.

set -uo pipefail

# Plugin-only SoT layout — this script lives in the plugin's scripts/ and is
# invoked via `vdd lint` against the user's project vault (resolved from
# $CODEX_PROJECT_DIR / $CLAUDE_PROJECT_DIR / $PWD), never copied into the project.
#
# LIB_DIR  = this script's own dir (plugin scripts/)         — for self-grep + sourcing the sibling vdd-yaml-lib.sh
# VAULT_DIR = the caller's project vault                    — derived from $CODEX_PROJECT_DIR, $CLAUDE_PROJECT_DIR, or $PWD
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
VAULT_DIR="$PROJECT_ROOT/docs/vault"

if [ ! -d "$VAULT_DIR" ]; then
  echo "ERROR: no docs/vault/ at $PROJECT_ROOT — run from a project root or set CODEX_PROJECT_DIR or CLAUDE_PROJECT_DIR" >&2
  exit 1
fi

# Canonical YAML extractors — single source of truth (the sibling vdd-yaml-lib.sh
# in this same plugin scripts/ dir). Sourced from the plugin path (LIB_DIR), not
# from the project — the project carries no tooling copy under plugin-only SoT.
# Provides extract_list / extract_list_stdin / extract_scalar / extract_obj_list.
_VDD_LIB="$LIB_DIR/vdd-yaml-lib.sh"
# shellcheck source=/dev/null
if ! . "$_VDD_LIB" 2>/dev/null; then
  echo "ERROR: $_VDD_LIB not found — plugin install may be corrupt (re-run claude plugin install vault-driven-development@pdev-jay)" >&2
  exit 1
fi

cd "$VAULT_DIR" || exit 1

ERRORS=0
WARNINGS=0
err()  { echo "  ERR  $*"; ERRORS=$((ERRORS+1)); }
warn() { echo "  WARN $*"; WARNINGS=$((WARNINGS+1)); }

# ─── helper: list pages ──────────────────────────────────
# Exclude auto-generated rollups + archive + migration artifacts.
# CLAUDE.md / CONSTRAINTS.md are no longer per-project (plugin-owned), but a
# stray copy or a pruned `.removed.<ts>` from an older install must never be
# linted — hence the name + path guards below.
list_pages() {
  find . -type f -name "*.md" \
    ! -name "_reverse-index.md" \
    ! -name "_progress.md" \
    ! -name "_decisions.md" \
    ! -name "_open-issues.md" \
    ! -name "_digest-frontmatter.md" \
    ! -name "_dependency-rules.md" \
    ! -name "CLAUDE.md" \
    ! -name "CONSTRAINTS.md" \
    ! -name "README.md" \
    ! -path "./examples/*" \
    ! -path "./_archive/*" \
    ! -path "*.removed.*" \
    ! -path "*.bak.*"
}

# extract_list / extract_scalar / extract_obj_list are provided by the sourced
# scripts/vdd-yaml-lib.sh (canonical — handles inline arrays, quoted items,
# CRLF, BOM uniformly; the former local copies handled none of these).

# ─── helper: normalize broadcast key ─────────────────────
# Inputs (raw):
#   bare:         "native:loggedIn"     (declared inside auth/_state-contract.md broadcasts)
#   prefixed:     "feature:idle"        (declared inside per-feature pages)
#   anchor-ref:   "auth/_state-contract#native:expired"  (used in reacts_to/emits_to)
# Output: canonical key (the colon-form after #)
normalize_key() {
  local k="$1"
  # if has '#', take the part after
  if [[ "$k" == *"#"* ]]; then echo "${k#*#}"; return; fi
  echo "$k"
}

# ─── helper: a page's code_refs that resolve to an existing project file ─
# Emits project-root-relative file paths (anchor stripped; dirs / missing
# skipped). Shared by the V-09 (Check 13) and V-10 (Check 14) sections.
page_ref_files() {
  local f="$1" ref rp
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    rp="${ref%%#*}"
    [[ -z "$rp" ]] && continue
    [[ "$rp" == */ ]] && continue
    [[ -f "$PROJECT_ROOT/$rp" ]] && echo "$rp"
  done < <(extract_list "$f" "code_refs")
}

# ─── helper: content fingerprint of a page's code_refs (V-10) ────
# Aggregate sha256 over the page's resolving code_refs FILES. The per-file digest
# is content-only (no path in the hashed material → machine / clone independent);
# the relative path is included as a stable, locale-sorted label so adding /
# removing a ref changes the fingerprint. Whole-file granularity (anchors
# stripped) matches Check 13's grep model — editing any part of a referenced file
# re-raises the review prompt. Empty (no resolving file) → empty string.
compute_code_hash() {
  local f="$1" rp abs h had=0 acc
  acc="$(
    page_ref_files "$f" | LC_ALL=C sort | while IFS= read -r rp; do
      abs="$PROJECT_ROOT/$rp"
      h="$( { shasum -a 256 "$abs" 2>/dev/null || sha256sum "$abs" 2>/dev/null; } | awk '{print $1}')"
      [[ -n "$h" ]] && printf '%s %s\n' "$rp" "$h"
    done
  )"
  [[ -z "$acc" ]] && { echo ""; return; }
  printf '%s' "$acc" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}'
}

# ─── --stamp: record review freshness (V-10) ─────────────────────
# `vdd lint --stamp [page]` writes reviewed_code_hash (content
# fingerprint of the page's code_refs, computed now) + reviewed_at (today) into
# the page frontmatter via byte-level field replace / inject (no YAML re-emit —
# Hard Rule on frontmatter writes). With no page arg, stamps every page. This is
# how a passing /vdd-review marks "this page's intent was confirmed against THIS
# code"; Check 14 below recomputes the fingerprint and warns on mismatch. The
# fingerprint is content-based (not git), so a stamp is fresh immediately after
# review — no commit required — and survives clone / rebase.
if [[ "${1:-}" == "--stamp" ]]; then
  TODAY="$(date +%Y-%m-%d)"
  stamp_one() {
    local page="$1" tmp ch
    ch="$(compute_code_hash "$page")"
    tmp="$(mktemp "$(dirname "$page")/.stamp.XXXXXX")" || return 1
    awk -v ch="$ch" -v today="$TODAY" '
      NR==1 && $0=="---" { infm=1; print; next }
      infm==1 && $0=="---" {
        if (!seen_date) print "reviewed_at: " today
        if (!seen_hash && ch != "") print "reviewed_code_hash: " ch
        infm=2; print; next
      }
      infm==1 && /^reviewed_code_hash:/ { if (ch != "") print "reviewed_code_hash: " ch; seen_hash=1; next }
      infm==1 && /^reviewed_at:/        { print "reviewed_at: " today; seen_date=1; next }
      { print }
    ' "$page" > "$tmp" && mv "$tmp" "$page" \
      && echo "  stamped ${page#./} → ${ch:0:12}${ch:+…} ($TODAY)${ch:+}" \
      && [[ -z "$ch" ]] && echo "    (no resolving code_refs — date only, freshness not tracked)"
    return 0
  }
  if [[ -n "${2:-}" ]]; then
    if   [[ -f "$2" ]]; then stamp_one "$2"
    elif [[ -f "$VAULT_DIR/$2" ]]; then stamp_one "$VAULT_DIR/$2"
    else echo "ERROR: page not found: $2" >&2; exit 1; fi
  else
    while IFS= read -r p; do stamp_one "$p"; done < <(list_pages)
  fi
  exit 0
fi

# ───────────────────────────────────────────────────────────
# 1. frontmatter exists
# ───────────────────────────────────────────────────────────
echo "▼ 1. frontmatter check"
while IFS= read -r f; do
  rel="${f#./}"
  head -1 "$f" | grep -q '^---$' || err "$rel: missing frontmatter"
  # CRLF is out-of-spec: the awk parsers normalize it for extraction, but a
  # CRLF page is silently fragile across other tools — hard-fail it.
  if LC_ALL=C grep -q $'\r' "$f" 2>/dev/null; then
    err "$rel: CRLF line endings — convert to LF (plain-markdown SoT, LF only)"
  fi
done < <(list_pages)

# ───────────────────────────────────────────────────────────
# 2. wikilink resolution
# ───────────────────────────────────────────────────────────
echo "▼ 2. wikilink resolution"
SCHEMA_PLACEHOLDERS="wikilink wikilinks name slug key"
PAGE_BASENAMES="$(list_pages | sed 's|.*/||;s|\.md$||' | LC_ALL=C sort -u)"
# Hard Rule 3: wikilinks resolve by basename, so basenames MUST be unique.
# A collision silently resolves links / vdd-impact closures to the wrong page.
#
# EXCEPTION — layer-scoped system pages: a `_`-prefixed page (system page per
# Hard Rule 4) that lives inside a layer folder (depth ≥ 2, never at vault
# root) is convention-by-design — each layer carries its own copy (e.g.
# every layer has its own `_state-contract.md`). References to these are
# always written as full path `<layer>/<basename>`, never as bare
# `<basename>`, so basename collision is intentional and harmless. The
# wikilink resolver below (Section 2 continued) enforces full-path form for
# colliding basenames so the convention is not silently broken.
DUP_BASENAMES="$(list_pages | sed 's|.*/||;s|\.md$||' | LC_ALL=C sort | uniq -d)"
LAYER_SCOPED_DUPS=""   # space-separated list of exempt basenames (used by Section 2 ambiguity check)
if [ -n "$DUP_BASENAMES" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    # Collect all files sharing this basename.
    collision_files="$(list_pages | awk -v b="$d" '
      { n=split($0, p, "/"); fname=p[n]; sub(/\.md$/, "", fname); if (fname == b) print $0 }
    ')"
    # Exception test: basename starts with `_` AND every collision file is at
    # depth ≥ 2 (inside a layer folder, never at vault root).
    exempt=0
    if [[ "$d" == _* ]]; then
      all_layer_scoped=1
      while IFS= read -r cf; do
        [ -z "$cf" ] && continue
        cf="${cf#./}"
        # depth = number of "/" + 1 (e.g. "auth/_state-contract.md" = 2)
        depth=$(awk -F/ '{print NF}' <<< "$cf")
        if [ "$depth" -lt 2 ]; then
          all_layer_scoped=0
          break
        fi
      done <<< "$collision_files"
      [ "$all_layer_scoped" = "1" ] && exempt=1
    fi
    if [ "$exempt" = "1" ]; then
      echo "  INFO Hard Rule 3 exception: '$d' (layer-scoped system page — references must use full path \`<layer>/$d\`)"
      LAYER_SCOPED_DUPS="$LAYER_SCOPED_DUPS $d"
    else
      err "duplicate page basename '$d' (Hard Rule 3 — rename so wikilink basenames stay unique)"
    fi
  done <<< "$DUP_BASENAMES"
fi
while IFS= read -r line; do
  file="${line%%:*}"
  link="${line#*:}"
  link="${link#*\[\[}"
  link="${link%%\]\]*}"
  basename="${link##*/}"
  basename="${basename%%#*}"
  skip=0
  for ph in $SCHEMA_PLACEHOLDERS; do
    [[ "$basename" == "$ph" ]] && skip=1 && break
  done
  [[ $skip -eq 1 ]] && continue
  # Ambiguity guard for layer-scoped system pages (Hard Rule 3 exception):
  # if the link is bare (no `/` separator) AND the basename matches one of
  # the exempt collision sets, the reference is ambiguous — the resolver
  # can't tell which layer is meant. Require full path `<layer>/<basename>`.
  if [[ "$link" != */* ]]; then
    for dup in $LAYER_SCOPED_DUPS; do
      if [[ "$basename" == "$dup" ]]; then
        err "$file: ambiguous wikilink [[$link]] — '$basename' exists in multiple layers; use full path '<layer>/$basename'"
        skip=1
        break
      fi
    done
    [[ $skip -eq 1 ]] && continue
  fi
  if ! echo "$PAGE_BASENAMES" | grep -qx "$basename"; then
    err "$file: broken wikilink [[$link]]"
  fi
done < <(
  list_pages | while IFS= read -r f; do
    grep -ohnE "\[\[[a-zA-Z0-9_./#-]+\]\]" "$f" 2>/dev/null | sed "s|^|$f:|"
  done | sort -u | sed 's|^\./||'
)

# ───────────────────────────────────────────────────────────
# 3. code_refs path + #SymbolName grep
# ───────────────────────────────────────────────────────────
# V-03: vault page code_refs 가 실재하지 않는 파일 / 심볼 — 자동 감지.
echo "▼ 3. code_refs validation"
while IFS= read -r f; do
  rel="${f#./}"
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    # split path and anchor
    path="${ref%%#*}"
    anchor=""
    if [[ "$ref" == *"#"* ]]; then
      anchor="${ref#*#}"
    fi
    [[ -z "$path" ]] && continue
    target="$PROJECT_ROOT/$path"
    if [[ "$path" == */ ]]; then
      # V-03: a missing path is an ERROR (blocks the V-06 lint-PASS gate) —
      # a dead code_refs link makes the page's anchors lies.
      [[ ! -d "$target" ]] && err "$rel: dir not found: $path"
    else
      if [[ ! -e "$target" ]]; then
        err "$rel: file not found: $path"
      else
        # ── Anchor validation ──
        # formats: #symbol | #L\d+(-L?\d+)? | #symbol:LINE-LINE | #symbol:LINE
        # extract just the symbol part and grep
        if [[ -n "$anchor" ]]; then
          # symbol = anchor before any ':' or pure form
          symbol="${anchor%%:*}"
          # skip pure line anchors (L42 or L42-L80)
          if [[ "$symbol" =~ ^L[0-9]+(-L?[0-9]+)?$ ]]; then
            : # line-only anchor, skip grep
          elif [[ -n "$symbol" ]]; then
            # symbol grep — two-tier check, false-negative safe.
            # Tier A (broad): symbol appears somewhere in the file.
            # Tier B (strict): symbol appears as a declaration (preceded by a
            # keyword from a multi-language list). Strict failure is a *softer*
            # warning because rare languages or unusual constructs may
            # legitimately escape the keyword set.
            if ! grep -qE "(\b|_)${symbol}(\b|\()" "$target" 2>/dev/null; then
              warn "$rel: code_refs symbol '#$symbol' not found in $path"
            else
              # Multi-language declaration keywords (Kotlin/Java/Swift/Dart/TS/JS/
              # Python/Go/Rust/C#/Scala/Elixir/PHP/Ruby).
              decl_kw='(class|interface|type|struct|trait|impl|object|record|enum|fun|func|function|def|method|const|let|var|val|module|namespace|export|public|private|protected|internal|abstract|static|async|override|final|extension|sealed|inline|inner|companion)'
              if ! grep -qE "(^|[[:space:]])${decl_kw}[[:space:]]+${symbol}\\b" "$target" 2>/dev/null; then
                warn "$rel: code_refs symbol '#$symbol' appears in $path but not as a declaration (renamed?)"
              fi
            fi
          fi
        fi
      fi
    fi
  done < <(extract_list "$f" "code_refs")
done < <(list_pages)

# ───────────────────────────────────────────────────────────
# 4. broadcast/reacts_to/emits_to consistency
# ───────────────────────────────────────────────────────────
# V-02: broadcast key 변경 시 reactor 페이지 동기화 누락 — reacts_to / emits_to
#       가 어디서도 broadcasts: 로 선언되지 않은 key 를 가리키면 warn.
# V-05: 새 broadcast key 도입 전 reactor 미결정 — 아래 4d orphan-broadcast
#       검사가 broadcasts: 에 선언됐지만 어떤 page 도 reacts_to / emits_to
#       하지 않는 key 를 warn 한다.
echo "▼ 4. broadcast key integrity"

# 4a. collect declared keys (every page that has broadcasts:)
KEYS_FILE=$(mktemp)
KEYS_PAGES_FILE=$(mktemp)   # key|page — for orphan-broadcast reporting (4d)
while IFS= read -r f; do
  rel="${f#./}"
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    nk="$(normalize_key "$k")"
    echo "$nk" >> "$KEYS_FILE"
    echo "$nk|$rel" >> "$KEYS_PAGES_FILE"
  done < <(extract_list "$f" "broadcasts")
done < <(list_pages)
sort -u "$KEYS_FILE" -o "$KEYS_FILE"

# 4b. validate referenced keys
while IFS= read -r f; do
  rel="${f#./}"
  for kind in reacts_to emits_to; do
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      # references take the form 'layer/_state-contract#key', bare 'key', or 'layer/_signals:foo'
      norm=$(normalize_key "$ref")
      # exact match against declared keys
      if ! grep -qFx "$norm" "$KEYS_FILE"; then
        # _signals:* are layer-internal — OK if not in broadcasts (warn only)
        if [[ "$norm" == *"_signals:"* ]]; then
          : # silent — _signals:* are layer-internal, OK if not in broadcasts
        else
          # V-02: a dangling reactor edge is an ERROR (blocks the V-06 gate) —
          # at runtime the reactor waits for a key no one emits.
          err "$rel: $kind references undefined key '$norm' (raw: $ref)"
        fi
      fi
    done < <(extract_list "$f" "$kind")
  done
done < <(list_pages)

# ───────────────────────────────────────────────────────────
# 4d. orphan broadcast detection (V-05)
# ───────────────────────────────────────────────────────────
# Every key declared in a broadcasts: list must be referenced by at least
# one page's reacts_to: or emits_to:. A declared emitter with zero reactors
# is a half-defined contract — CONSTRAINTS V-05 forbids it. WARN (not ERR):
# a "TBD — see <issue>" reactor placeholder is allowed and surfaces here as
# a reminder, not a hard failure.
echo "▼ 4d. orphan broadcast detection (V-05)"
REFS_FILE=$(mktemp)
while IFS= read -r f; do
  for kind in reacts_to emits_to; do
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      normalize_key "$ref" >> "$REFS_FILE"
    done < <(extract_list "$f" "$kind")
  done
done < <(list_pages)
sort -u "$REFS_FILE" -o "$REFS_FILE"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  if ! grep -qFx "$key" "$REFS_FILE"; then
    src_page="$(grep -F "${key}|" "$KEYS_PAGES_FILE" | head -1 | cut -d'|' -f2)"
    warn "${src_page:-?}: orphan broadcast '$key' — declared in broadcasts: but no page reacts_to / emits_to it (V-05 — declare a reactor or mark 'TBD — see <issue>')"
  fi
done < "$KEYS_FILE"
rm -f "$REFS_FILE"

# ───────────────────────────────────────────────────────────
# 4e. silent layer detection (V-11)
# ───────────────────────────────────────────────────────────
# V-11: a layer (folder) whose pages collectively declare NO broadcasts /
# reacts_to / emits_to / intent_refs is "silent" — it participates in neither
# the broadcast graph nor the intent graph. Frequently legitimate (cross-cutting
# layers: error, permission, infrastructure), but can hide a real gap: a layer
# that SHOULD emit (e.g. a native bridge producing events) yet declares nothing
# is invisible to V-02 / V-05, which only check declared edges — never the
# ABSENCE of one. Aggregated PER LAYER, not per page: auth/auth.md on its own is
# empty, but the auth LAYER is connected through _state-contract.md + feature
# pages, so auth is not silent. INFO-only — never WARN (silence is often
# intentional) and never blocks the V-06 gate. This is the deterministic triage
# input for vdd-review Mode B, which decides standalone-vs-gap per layer.
echo "▼ 4e. silent layer detection (V-11)"
SIGNAL_LAYERS=$(mktemp)
while IFS= read -r f; do
  layer="${f#./}"; layer="${layer%%/*}"
  case "$layer" in ""|*.md) continue ;; esac   # skip top-level files (no layer folder)
  for kind in broadcasts reacts_to emits_to intent_refs; do
    if [ -n "$(extract_list "$f" "$kind" | head -1)" ]; then
      echo "$layer" >> "$SIGNAL_LAYERS"; break
    fi
  done
done < <(list_pages)
sort -u "$SIGNAL_LAYERS" -o "$SIGNAL_LAYERS"
# layer-index layers = folders holding a zoom:0 page (Hard Rule 1)
SILENT=""
while IFS= read -r idx; do
  layer="${idx#./}"; layer="${layer%%/*}"
  case "$layer" in ""|*.md) continue ;; esac
  if ! grep -qFx "$layer" "$SIGNAL_LAYERS"; then
    case " $SILENT " in *" $layer "*) : ;; *) SILENT="${SILENT} ${layer}" ;; esac
  fi
done < <(grep -rlE "^zoom:[[:space:]]*0([[:space:]]|$)" --include="*.md" . 2>/dev/null | grep -vE "^\./(examples|_archive)/")
SILENT="${SILENT# }"
if [ -n "$SILENT" ]; then
  echo "  INFO: silent layers (no broadcasts/reacts_to/emits_to/intent_refs in any page):"
  for l in $SILENT; do echo "    · $l"; done
  echo "  → triage each (vdd-review Mode B): intentionally standalone (cross-cutting) OR a missing graph edge?"
else
  echo "  (none — every layer participates in the broadcast/intent graph)"
fi
rm -f "$SIGNAL_LAYERS"

# ───────────────────────────────────────────────────────────
# 4c. CONSTRAINTS V-XX ↔ _lint.sh coverage (plugin-internal self-check)
# ───────────────────────────────────────────────────────────
# Pattern lifted from the personal harness system (CONSTRAINTS.md ↔ lint_check.sh):
#   - rule headings `### V-XX` declared in the plugin CONSTRAINTS.md
#   - automated checks `# V-XX` declared in this lint script
#   - a `# V-XX: MANUAL —` marker = the rule is acknowledged-uncovered
#     (skill/hook-enforced, no lint detection). It is NOT counted as an
#     automated check, so a MANUAL token can never masquerade as coverage.
#   - mismatch = some rule has neither an automated check nor a MANUAL
#     marker — fixable by adding a grep check below or a MANUAL marker.
# Soft signal only (WARN, never ERR). Both sides ship in the plugin, so this is
# a plugin-self-consistency check, not a per-project one.
# CONSTRAINTS.md is plugin-owned and universal (V-XX only — C-XX project rules
# were retired; there is no per-project CONSTRAINTS copy). Both the rule
# declarations and the lint markers ship in the plugin, so 4c is now a
# plugin-internal self-consistency check: does the shipped _lint.sh cover every
# shipped V-XX?
CONSTRAINTS_FILE="$LIB_DIR/../scaffold/CONSTRAINTS.md"
# V-01: MANUAL — owner vault page Read before code edit. Lint cannot see
#       Read-before-edit ordering; enforced by skill body (vdd-impact call).
#       No hook backstop — discipline is the model's responsibility. The
#       MANUAL token makes 4c report this as acknowledged-uncovered, NOT
#       falsely "covered".
# V-07: MANUAL — per-member verdict on the impact set. Verdict correctness
#       is not automatable; enforced by workflow skill bodies' Impact
#       Analysis step. MANUAL token = acknowledged-uncovered (not gamed).
# V-08: vault page bloat / decisions note 비대화 — 부분 감지 (Check 12).
#       decisions[*].note 가 200자 초과면 _decisions.md rollup 이 깨끗하지 않게
#       되고, vault 가 점차 narrative 화 → SoT 권위 상실. WARN.
if [ -f "$CONSTRAINTS_FILE" ]; then
  echo "▼ 4c. CONSTRAINTS ↔ lint coverage (plugin-internal)"
  for prefix in V; do
    # grep -c always prints a number; exit 1 on no-match. Use `|| true` so
    # set -uo pipefail doesn't abort, and DO NOT add `echo 0` — it would
    # concatenate with grep's own "0" output.
    declared=$(grep -cE "^### ${prefix}-[0-9]+:" "$CONSTRAINTS_FILE" 2>/dev/null || true)
    # Self-grep MUST use the absolute path: BASH_SOURCE[0] is the (possibly
    # relative) invocation path, and this script has already cd'd into
    # $VAULT_DIR — a relative BASH_SOURCE no longer resolves. $VAULT_DIR was
    # resolved to absolute at the top, before the cd.
    markers=$(grep -cE "^# ${prefix}-[0-9]+:" "$LIB_DIR/_lint.sh" 2>/dev/null || true)
    manual=$(grep -cE "^# ${prefix}-[0-9]+: MANUAL" "$LIB_DIR/_lint.sh" 2>/dev/null || true)
    declared=${declared:-0}
    markers=${markers:-0}
    manual=${manual:-0}
    covered=$((markers - manual))   # real automated checks (MANUAL excluded)
    # Transparency: name the acknowledged-uncovered rules so a MANUAL token
    # can never masquerade as coverage (the 4c self-check honesty fix).
    if [ "$manual" -gt 0 ]; then
      manual_list=$(grep -oE "^# ${prefix}-[0-9]+: MANUAL" "$LIB_DIR/_lint.sh" 2>/dev/null \
        | grep -oE "${prefix}-[0-9]+" | tr '\n' ' ')
      echo "  INFO ${prefix}-XX MANUAL (skill/hook-enforced, no lint detection): ${manual_list}"
    fi
    # Unaccounted = declared rules with NEITHER an automated check NOR a
    # MANUAL marker. Soft signal (WARN, never ERR).
    if [ "$declared" -gt "$((covered + manual))" ]; then
      warn "CONSTRAINTS.md: $prefix-XX declared=$declared automated=$covered manual=$manual — $((declared - covered - manual)) rule(s) with NO check and NO MANUAL marker (add a # $prefix-XX check to _lint.sh, or a '# $prefix-XX: MANUAL —' line)"
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# 4b. vault quality checks (LLM 작성 검증 강화)
# ───────────────────────────────────────────────────────────
echo "▼ 4b. vault quality (orphan broadcasts / stale updated / filler decisions / oversized pages)"

# Cross-platform helpers — macOS BSD / GNU
_epoch_from_date() {
  date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}
_file_mtime() {
  # GNU first: `stat -f` is NOT an error on GNU coreutils — it means "filesystem
  # status" and prints a multi-line dump (exit 0), so a BSD-first `stat -f %m ||
  # stat -c %Y` never falls through on Linux and returns garbage. BSD `stat -c`
  # cleanly errors (illegal option), so GNU-first is safe on both.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

STALE_THRESHOLD_DAYS=7
EMPTY_DECISIONS_BODY_THRESHOLD=20
OVERSIZE_THRESHOLD_BYTES=40960
DECISIONS_COUNT_CAP=25   # active decisions: entries before nudging to archive (V-08 decay)

while IFS= read -r f; do
  rel="${f#./}"
  dir="$(dirname "$f")"
  fname="$(basename "$f")"

  # skip system pages — these don't follow normal frontmatter rules
  case "$fname" in
    _reverse-index.md|_progress.md|_decisions.md|_open-issues.md|index.md|CLAUDE.md)
      continue ;;
  esac

  # collect frontmatter (between first two ---)
  frontmatter=$(awk '/^---$/{c++; next} c==1' "$f" 2>/dev/null)
  [[ -z "$frontmatter" ]] && continue

  # ─── Check 8: orphan broadcasts ────────────────────────────
  # broadcasts: 비어있지 않음 + 페이지 자체가 _state-contract.md 가 아님 +
  # 같은 layer 디렉토리에 _state-contract.md 부재 → warn
  if [[ "$fname" != "_state-contract.md" ]]; then
    has_broadcasts=0
    if echo "$frontmatter" | grep -qE '^broadcasts:[[:space:]]*\[[^]]*[^][:space:]][^]]*\]'; then
      has_broadcasts=1
    elif echo "$frontmatter" | awk '
      /^broadcasts:[[:space:]]*$/ { f=1; next }
      f && /^[[:space:]]+-[[:space:]]/ { found=1; exit }
      f && /^[^[:space:]]/ { f=0 }
      END { exit !found }
    '; then
      has_broadcasts=1
    fi
    if [[ "$has_broadcasts" = "1" ]] && [[ ! -f "$dir/_state-contract.md" ]]; then
      warn "$rel: declares non-empty broadcasts: but layer has no _state-contract.md (cross-layer contract page missing)"
    fi
  fi

  # ─── Check 9: stale updated ────────────────────────────────
  # updated: 가 page 의 code_refs 파일 mtime 보다 7일 이상 뒤처짐 → warn
  upd=$(echo "$frontmatter" | sed -n 's/^updated:[[:space:]]*\([0-9-]*\).*/\1/p' | head -1)
  if [[ -n "$upd" ]]; then
    upd_epoch=$(_epoch_from_date "$upd")
    if [[ -n "$upd_epoch" ]]; then
      newest_code=0
      while IFS= read -r ref; do
        path="${ref%%#*}"
        [[ -z "$path" ]] && continue
        # skip dir refs (path ends in /)
        [[ "$path" == */ ]] && continue
        target="$PROJECT_ROOT/$path"
        if [[ -f "$target" ]]; then
          mt=$(_file_mtime "$target")
          # Guard the arithmetic: a non-numeric mt (e.g. a tool printing a dump
          # instead of an epoch) would crash `-gt` under `set -u`.
          [[ "$mt" =~ ^[0-9]+$ && "$mt" -gt "$newest_code" ]] && newest_code="$mt"
        fi
      done < <(extract_list "$f" "code_refs")
      if [[ "$newest_code" -gt 0 ]]; then
        diff_sec=$((newest_code - upd_epoch))
        threshold_sec=$((STALE_THRESHOLD_DAYS * 86400))
        if [[ "$diff_sec" -gt "$threshold_sec" ]]; then
          diff_days=$((diff_sec / 86400))
          warn "$rel: 'updated: $upd' is ${diff_days}d older than youngest code_refs mtime (vault behind code)"
        fi
      fi
    fi
  fi

# V-04: 작업 중 architectural decision 을 vault 에 기록하지 않음 — 부분 감지 (Check 10).
  # ─── Check 10: empty decisions in non-trivial active page ──
  # decisions: [] (또는 부재) + status: active + body 50줄 초과 → warn
  # heuristic — LLM padding prose without capturing decisions 의 신호
  is_active=0
  echo "$frontmatter" | grep -qE '^status:[[:space:]]*active' && is_active=1
  if [[ "$is_active" = "1" ]]; then
    # decisions: 가 비어있거나 부재?
    decisions_empty=1
    if echo "$frontmatter" | grep -qE '^decisions:[[:space:]]*\[[[:space:]]*[^][:space:]\]]'; then
      decisions_empty=0  # inline non-empty
    elif echo "$frontmatter" | awk '
      /^decisions:[[:space:]]*$/ { f=1; next }
      f && /^[[:space:]]+-[[:space:]]/ { found=1; exit }
      f && /^[^[:space:]]/ { f=0 }
      END { exit !found }
    '; then
      decisions_empty=0  # block non-empty
    fi
    if [[ "$decisions_empty" = "1" ]]; then
      # body lines after second ---
      body_lines=$(awk '/^---$/{c++; next} c==2 && NF{n++} END{print n+0}' "$f" 2>/dev/null)
      if [[ "${body_lines:-0}" -gt "$EMPTY_DECISIONS_BODY_THRESHOLD" ]]; then
        warn "$rel: active page has ${body_lines} body lines but decisions: is empty (LLM filler risk?)"
      fi
    fi
  fi

  # ─── Check 11: oversized layer page ────────────────────────
  # Rule 0 의 "Read the layer page" 가 깨지는 게 본 검사의 본래 목적.
  # 따라서 **zoom: 0 layer index page 만** 검사. zoom 1+ child page (특히
  # decision-log 같은 *의도된 archive*) 는 layer-Read 대상 아니라 크기 무관.
  # 40KB ≈ 25K-token Read 한도 근처 (136KB / 67K-token page 는 Read 자체 불가).
  page_zoom=$(echo "$frontmatter" | sed -n 's/^zoom:[[:space:]]*\(-\?[0-9]*\).*/\1/p' | head -1)
  if [[ "$page_zoom" = "0" ]]; then
    page_bytes=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    if [[ -n "$page_bytes" && "$page_bytes" -gt "$OVERSIZE_THRESHOLD_BYTES" ]]; then
      warn "$rel: layer page is ${page_bytes} bytes (> ${OVERSIZE_THRESHOLD_BYTES}) — approaches the Read token limit; split into child pages so Rule 0 stays possible"
    fi
  fi

  # ─── Check 12: oversized decisions note (V-08) ─────────────
  # decisions[*].note 는 ≤200자 한 줄이 권장 (rollup _decisions.md 가 깔끔).
  # 길어지면 vault 가 narrative 화 → SoT 권위 상실. WARN.
  # block: `      note: "<text>"` / `      note: <text>` / inline: `- {... note: "<text>" ...}`
  while IFS= read -r dline; do
    [[ -z "$dline" ]] && continue
    nval=""
    if [[ "$dline" =~ note:[[:space:]]*\"([^\"]*)\" ]]; then
      nval="${BASH_REMATCH[1]}"
    elif [[ "$dline" =~ note:[[:space:]]*\'([^\']*)\' ]]; then
      nval="${BASH_REMATCH[1]}"
    elif [[ "$dline" =~ ^[[:space:]]*note:[[:space:]]*(.*)$ ]]; then
      nval="${BASH_REMATCH[1]}"
      # strip trailing comment/whitespace
      nval="${nval%%  #*}"
      nval="${nval%"${nval##*[![:space:]]}"}"
    fi
    [[ -z "$nval" ]] && continue
    nlen=${#nval}
    if [[ "$nlen" -gt 200 ]]; then
      warn "$rel: decisions note ${nlen} chars (> 200) — trim to one line; long rationale belongs in body or commit message (V-08)"
    fi
  done < <(extract_obj_list "$f" "decisions")

  # ─── Check 12b: decisions count cap (V-08 decay) ───────────
  # decisions: is the SoT for *currently-active* rationale. Past a soft cap it
  # stops being scannable and the page drifts toward archaeology — the decay
  # the archive-child-page pattern exists to prevent. Count entries (one `date:`
  # per entry, block- or inline-style) and nudge toward archival. WARN-only:
  # research-heavy layers legitimately accumulate, and the V-08 escape valve
  # (move to <layer>/decision-log.md + decisions: []) clears it.
  dcount=$(extract_obj_list "$f" "decisions" | grep -cE '(^|[,{[:space:]])date:' 2>/dev/null || true)
  dcount=${dcount:-0}
  if [[ "$dcount" -gt "$DECISIONS_COUNT_CAP" ]]; then
    warn "$rel: ${dcount} active decisions in frontmatter (> ${DECISIONS_COUNT_CAP}) — archive older entries to <layer>/decision-log.md (decisions: []) so the page stays scannable (V-08 archive pattern)"
  fi

done < <(list_pages)

# ───────────────────────────────────────────────────────────
# 13. broadcast → code producer (cross-artifact: contract ↔ code)
# ───────────────────────────────────────────────────────────
# V-09: a page declares broadcasts: but NONE of its own code_refs files
#       textually back the key — the contract claims an emitter the code
#       does not provide. The key→token match is a heuristic (token = the
#       segment after the last ':' in the normalized key) and notation-agnostic
#       (case-insensitive, kebab/snake separators optional — a kebab vault key
#       matches its PascalCase/camelCase/snake_case code symbol), so this is
#       WARN-only: a false positive must never block the V-06 lint gate.
#       The binding cross-artifact verdict is the vdd-review skill (Mode B Analyze)'s
#       batch pass; this check is its deterministic floor (zero-token,
#       reproducible, CI-portable). Pages with no concrete code_refs file
#       (spec-first / directory-only) are skipped — nothing to match yet.
echo "▼ 13. broadcast → code producer (V-09)"
while IFS= read -r f; do
  rel="${f#./}"

  # Collect this page's own code_refs that resolve to an existing FILE
  # (strip #anchor; skip directory refs and missing paths — Check 3 owns
  # missing-path errors, here we only need real producer files to grep).
  REFS_TMP=$(mktemp)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    rp="${ref%%#*}"
    [[ -z "$rp" ]] && continue
    [[ "$rp" == */ ]] && continue
    tgt="$PROJECT_ROOT/$rp"
    [[ -f "$tgt" ]] && echo "$tgt" >> "$REFS_TMP"
  done < <(extract_list "$f" "code_refs")

  # No concrete producer file → unverifiable here, skip (no false alarm).
  if [[ ! -s "$REFS_TMP" ]]; then
    rm -f "$REFS_TMP"
    continue
  fi

  while IFS= read -r bk; do
    [[ -z "$bk" ]] && continue
    nk="$(normalize_key "$bk")"   # strip any '#'-prefix → colon-form
    leaf="${nk##*:}"              # token after last ':'  (phase:idle → idle)
    leaf="${leaf##*/}"            # defensive: drop any residual path prefix
    # Too-short / empty token → unsearchable (garbage-match risk), skip.
    [[ -z "$leaf" || ${#leaf} -le 2 ]] && continue
    # Notation-agnostic match. V-09 verifies the key's *concept* is backed by
    # code, not that the spelling is identical: a kebab vault key
    # (`distances-received`) legitimately maps to a PascalCase / camelCase /
    # snake_case code symbol (`DistancesReceived` / `distancesReceived` /
    # `distances_received`). So drop case-sensitivity (-i) and let each
    # kebab/snake separator match an optional separator (or none) between
    # segments — `distances[-_]?received`. The contiguous-segment requirement
    # keeps false-negatives minimal (the words must still appear together).
    pat="$(printf '%s' "$leaf" | sed 's/[-_]/[-_]?/g')"
    found=0
    while IFS= read -r cf; do
      if grep -qiE "(\b|_)${pat}(\b|_|\()" "$cf" 2>/dev/null; then
        found=1
        break
      fi
    done < "$REFS_TMP"
    if [[ "$found" -eq 0 ]]; then
      warn "$rel: broadcasts key '$bk' (token '$leaf') not found in any of this page's code_refs files — contract may claim an emitter the code does not back (V-09; heuristic — confirm via vdd-review Mode B)"
    fi
  done < <(extract_list "$f" "broadcasts")

  rm -f "$REFS_TMP"
done < <(list_pages)

# ───────────────────────────────────────────────────────────
# 14. review freshness (vault page intent vs. code drift since last review)
# ───────────────────────────────────────────────────────────
# V-10: a page carries reviewed_code_hash (written by `--stamp` on a passing
#       /vdd-review) — a content fingerprint of its code_refs at review time. If
#       the current fingerprint differs, the code the page describes has moved
#       since it was last reviewed: the page's intent claims may be stale. This
#       turns "was this page re-reviewed after the code changed?" from an
#       unverifiable procedure into a visible signal. WARN-only: a content change
#       is a *re-review prompt*, not a schema violation, so it must never block
#       the V-06 gate. Renames / whitespace also trip it — by design; the prompt
#       is "confirm intent still holds", cleared cheaply by re-stamping once
#       re-confirmed. Content-based (no git) → fresh immediately after review,
#       survives clone / rebase.
echo "▼ 14. review freshness (V-10)"
V10_UNSTAMPED=0
while IFS= read -r f; do
  rel="${f#./}"
  # only meaningful for pages that anchor real code
  cur="$(compute_code_hash "$f")"
  [[ -z "$cur" ]] && continue
  rh="$(awk '
    NR==1 && $0=="---"{fm=1; next}
    fm && $0=="---"{exit}
    fm && /^reviewed_code_hash:/{sub(/^reviewed_code_hash:[[:space:]]*/,""); print; exit}
  ' "$f")"
  if [[ -z "$rh" ]]; then
    V10_UNSTAMPED=$((V10_UNSTAMPED+1))
    continue
  fi
  if [[ "$rh" != "$cur" ]]; then
    warn "$rel: code_refs changed since last review (fingerprint ${rh:0:8} → ${cur:0:8}) — intent may be stale; re-review then \`_lint.sh --stamp $rel\` (V-10)"
  fi
done < <(list_pages)
if [[ "$V10_UNSTAMPED" -gt 0 ]]; then
  echo "  INFO $V10_UNSTAMPED page(s) with code_refs have no reviewed_code_hash — run \`_lint.sh --stamp\` after a /vdd-review to enable freshness tracking (V-10)"
fi

# ───────────────────────────────────────────────────────────
# 5. generate _reverse-index.md
# ───────────────────────────────────────────────────────────
echo "▼ 5. generating _reverse-index.md"

REACTORS_FILE=$(mktemp)
EMITTERS_FILE=$(mktemp)

while IFS= read -r f; do
  rel="${f#./}"
  slug="$(basename "$rel" .md)"
  for kind in reacts_to emits_to; do
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      norm=$(normalize_key "$ref")
      if [[ "$kind" == "reacts_to" ]]; then
        echo "$norm|$slug" >> "$REACTORS_FILE"
      else
        echo "$norm|$slug" >> "$EMITTERS_FILE"
      fi
    done < <(extract_list "$f" "$kind")
  done
done < <(list_pages)

{
  echo "---"
  echo "title: reverse-index (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# reverse-index (auto-generated)"
  echo
  echo "_Auto-generated by _lint.sh by grepping \`broadcasts\`/\`reacts_to\`/\`emits_to\` frontmatter. Do not edit manually._"
  echo
  echo "## broadcast → reactors"
  echo
  ALL_KEYS=$( (cut -d'|' -f1 "$REACTORS_FILE"; cut -d'|' -f1 "$EMITTERS_FILE") | sort -u | grep -v '^$' )
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    reactors=$(grep "^${key}|" "$REACTORS_FILE" | cut -d'|' -f2 | sort -u)
    emitters=$(grep "^${key}|" "$EMITTERS_FILE" | cut -d'|' -f2 | sort -u)
    [[ -z "$reactors" && -z "$emitters" ]] && continue
    echo "### \`$key\`"
    echo
    if [[ -n "$reactors" ]]; then
      echo "**Reactors** (subscribers):"
      while IFS= read -r r; do echo "- [[$r]]"; done <<< "$reactors"
      echo
    fi
    if [[ -n "$emitters" ]]; then
      echo "**Indirect emitters** (side-effect triggers):"
      while IFS= read -r e; do echo "- [[$e]]"; done <<< "$emitters"
      echo
    fi
  done <<< "$ALL_KEYS"
} > _reverse-index.md

rm -f "$KEYS_FILE" "$KEYS_PAGES_FILE" "$REACTORS_FILE" "$EMITTERS_FILE"

# ───────────────────────────────────────────────────────────
# 6. Auto-rollup: _progress.md / _decisions.md / _open-issues.md
# ───────────────────────────────────────────────────────────

echo "▼ 6. generating rollups (_progress.md / _decisions.md / _open-issues.md / _digest-frontmatter.md / _dependency-rules.md)"

PROGRESS_FILE=$(mktemp)
DECISIONS_FILE=$(mktemp)
ISSUES_FILE=$(mktemp)

while IFS= read -r f; do
  rel="${f#./}"
  slug="$(basename "$rel" .md)"
  status=$(extract_scalar "$f" "status")
  title=$(extract_scalar "$f" "title")
  updated=$(extract_scalar "$f" "updated")

  # ── progress: pages with status:in_progress or draft ──
  if [[ "$status" == "in_progress" || "$status" == "draft" ]]; then
    echo "$status|$slug|$title|$rel|$updated" >> "$PROGRESS_FILE"
  fi

  # ── decisions: page-level decisions: entries, time-ordered ──
  current_date=""; current_note=""
  fm_decision_count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # new entry (starts with -)
    if [[ "$line" =~ ^[[:space:]]+- ]]; then
      if [[ -n "$current_date" ]]; then
        echo "$current_date|$slug|$current_note" >> "$DECISIONS_FILE"
        fm_decision_count=$((fm_decision_count+1))
      fi
      current_date=""; current_note=""
      # extract date: or note: if present on the same line
      line="${line#*-}"
    fi
    # extract date:
    if [[ "$line" =~ date: ]]; then
      d="${line#*date:}"
      d="${d// /}"
      d="${d//\"/}"
      current_date="$d"
    fi
    # extract note:
    if [[ "$line" =~ note: ]]; then
      n="${line#*note:}"
      n="${n# }"
      n="${n%\"}"
      n="${n#\"}"
      current_note="$n"
    fi
    # inline form: - {date: X, note: "Y"}
    if [[ "$line" =~ \{.*date: ]]; then
      d=$(echo "$line" | sed -n 's/.*date:[[:space:]]*\([0-9-]*\).*/\1/p')
      n=$(echo "$line" | sed -n 's/.*note:[[:space:]]*"\([^"]*\)".*/\1/p')
      [[ -z "$n" ]] && n=$(echo "$line" | sed -n "s/.*note:[[:space:]]*'\([^']*\)'.*/\1/p")
      if [[ -n "$d" && -n "$n" ]]; then
        echo "$d|$slug|$n" >> "$DECISIONS_FILE"
        fm_decision_count=$((fm_decision_count+1))
      fi
      current_date=""; current_note=""
    fi
  done < <(extract_obj_list "$f" "decisions")
  # flush last
  if [[ -n "$current_date" && -n "$current_note" ]]; then
    echo "$current_date|$slug|$current_note" >> "$DECISIONS_FILE"
    fm_decision_count=$((fm_decision_count+1))
  fi

  # ── decisions fallback: body heading scan ──
  # When frontmatter `decisions:` is empty (typical of *archive* / *decision-log*
  # child pages where rationale is preserved as body markdown), scan the body
  # for `## YYYY-MM-DD — title` or `### YYYY-MM-DD — title` headings and feed
  # them into the rollup. This restores chronological scan for archive pages
  # without forcing narrative back into frontmatter (V-08 정신 유지).
  if [[ "$fm_decision_count" = "0" ]]; then
    while IFS= read -r heading; do
      [[ -z "$heading" ]] && continue
      # Match `## YYYY-MM-DD — <title>` or `### YYYY-MM-DD — <title>` (em-dash)
      if [[ "$heading" =~ ^#{2,3}[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+—[[:space:]]+(.+)$ ]]; then
        d="${BASH_REMATCH[1]}"
        n="${BASH_REMATCH[2]}"
        # cap title length so rollup stays scannable
        [[ ${#n} -gt 120 ]] && n="${n:0:120}…"
        echo "$d|$slug|$n" >> "$DECISIONS_FILE"
      fi
    done < <(grep -E '^#{2,3}[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+—' "$f" 2>/dev/null)
  fi

  # ── open issues: page-level tasks: entries ──
  current_priority="med"; current_todo=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[[:space:]]+- ]]; then
      if [[ -n "$current_todo" ]]; then
        echo "$current_priority|$slug|$current_todo" >> "$ISSUES_FILE"
      fi
      current_priority="med"; current_todo=""
      line="${line#*-}"
    fi
    if [[ "$line" =~ todo: ]]; then
      t="${line#*todo:}"
      t="${t# }"
      t="${t%\"}"
      t="${t#\"}"
      current_todo="$t"
    fi
    if [[ "$line" =~ priority: ]]; then
      p="${line#*priority:}"
      p="${p// /}"
      current_priority="$p"
    fi
    # inline: - {todo: "...", priority: high}
    if [[ "$line" =~ \{.*todo: ]]; then
      t=$(echo "$line" | sed -n 's/.*todo:[[:space:]]*"\([^"]*\)".*/\1/p')
      [[ -z "$t" ]] && t=$(echo "$line" | sed -n "s/.*todo:[[:space:]]*'\([^']*\)'.*/\1/p")
      p=$(echo "$line" | sed -n 's/.*priority:[[:space:]]*\([a-z]*\).*/\1/p')
      [[ -z "$p" ]] && p="med"
      [[ -n "$t" ]] && echo "$p|$slug|$t" >> "$ISSUES_FILE"
      current_priority="med"; current_todo=""
    fi
  done < <(extract_obj_list "$f" "tasks")
  if [[ -n "$current_todo" ]]; then
    echo "$current_priority|$slug|$current_todo" >> "$ISSUES_FILE"
  fi
done < <(list_pages)

# ── _progress.md ──
{
  echo "---"
  echo "title: progress (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# progress (auto-generated)"
  echo
  echo "_Auto-generated by _lint.sh by grepping page frontmatter \`status:\`. Do not edit manually._"
  echo
  echo "## In progress"
  echo
  if grep -q "^in_progress|" "$PROGRESS_FILE" 2>/dev/null; then
    sort -u "$PROGRESS_FILE" | awk -F'|' '$1=="in_progress"' | while IFS='|' read -r st slug title rel upd; do
      echo "- [[$slug]] — $title  *(updated: $upd)*"
    done
  else
    echo "_(none)_"
  fi
  echo
  echo "## Draft"
  echo
  if grep -q "^draft|" "$PROGRESS_FILE" 2>/dev/null; then
    sort -u "$PROGRESS_FILE" | awk -F'|' '$1=="draft"' | while IFS='|' read -r st slug title rel upd; do
      echo "- [[$slug]] — $title  *(updated: $upd)*"
    done
  else
    echo "_(none)_"
  fi
} > _progress.md

# ── _decisions.md (newest first) ──
{
  echo "---"
  echo "title: decisions (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# decisions (auto-generated, newest first)"
  echo
  echo "_Auto-generated by _lint.sh by grepping page frontmatter \`decisions:\`, sorted reverse-chronological. Do not edit manually._"
  echo
  if [[ -s "$DECISIONS_FILE" ]]; then
    sort -r -u "$DECISIONS_FILE" | while IFS='|' read -r date slug note; do
      echo "## $date  ·  [[$slug]]"
      echo
      echo "$note"
      echo
    done
  else
    echo "_(no decisions yet)_"
  fi
} > _decisions.md

# ── _open-issues.md (grouped by priority + page) ──
{
  echo "---"
  echo "title: open issues (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# open issues (auto-generated)"
  echo
  echo "_Auto-generated by _lint.sh by grepping page frontmatter \`tasks:\`. Do not edit manually._"
  echo
  for prio in high med low; do
    label="$prio"
    [[ "$prio" == "high" ]] && label="🔴 high"
    [[ "$prio" == "med" ]] && label="🟡 med"
    [[ "$prio" == "low" ]] && label="🟢 low"
    echo "## $label"
    echo
    if grep -q "^${prio}|" "$ISSUES_FILE" 2>/dev/null; then
      sort -u "$ISSUES_FILE" | awk -F'|' -v p="$prio" '$1==p' | while IFS='|' read -r p slug todo; do
        echo "- [[$slug]] — $todo"
      done
    else
      echo "_(none)_"
    fi
    echo
  done
} > _open-issues.md

# ── _digest-frontmatter.md (LLM-readable single-file snapshot) ──
# Designed to be read in one shot. Combines:
#   1. Vault-level counts (pages / layers / contracts / in-progress).
#   2. Page index table — one row per page with field counts; lets the LLM
#      spot the high-traffic pages (most broadcasts / decisions / tasks)
#      without reading every page.
#   3. Per-page detail — broadcasts / reacts_to / emits_to / code_refs in
#      full, plus the latest 3 decisions and top 3 tasks (by priority).
#      That covers the deterministic frontmatter ground truth; narrative
#      sections (Capability boundary, Hot risks, conventions) are still
#      drilled per-page when needed.
# Reuses $DECISIONS_FILE / $ISSUES_FILE collected by the rollups above —
# do not move this block below the temp-file cleanup.
{
  echo "---"
  echo "title: digest-frontmatter (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# digest-frontmatter (auto-generated)"
  echo
  echo "_Auto-generated by \`_lint.sh\`. Deterministic frontmatter-only snapshot of every vault page — designed to be read in one shot for LLM grounding. Drill into the individual page for narrative (Capability boundary, Hot risks, Architectural conventions, etc.)._"
  echo

  # Stats
  TOTAL_PG=0; LAYER_PG=0; CONTRACT_PG=0; INPROG_PG=0; DEPRECATED_PG=0
  while IFS= read -r f; do
    rel="${f#./}"
    TOTAL_PG=$((TOTAL_PG+1))
    zm=$(extract_scalar "$f" "zoom")
    st=$(extract_scalar "$f" "status")
    [[ "$zm" == "0" ]] && LAYER_PG=$((LAYER_PG+1))
    base=$(basename "$rel" .md)
    [[ "$base" == "_state-contract" ]] && CONTRACT_PG=$((CONTRACT_PG+1))
    [[ "$st" == "in_progress" ]] && INPROG_PG=$((INPROG_PG+1))
    [[ "$st" == "deprecated" ]] && DEPRECATED_PG=$((DEPRECATED_PG+1))
  done < <(list_pages)

  TOTAL_DEC=$(wc -l < "$DECISIONS_FILE" 2>/dev/null | tr -d ' ')
  TOTAL_TSK=$(wc -l < "$ISSUES_FILE" 2>/dev/null | tr -d ' ')
  [[ -z "$TOTAL_DEC" ]] && TOTAL_DEC=0
  [[ -z "$TOTAL_TSK" ]] && TOTAL_TSK=0

  echo "## Vault summary"
  echo
  echo "- pages: $TOTAL_PG"
  echo "- layer indexes (zoom=0): $LAYER_PG"
  echo "- state contracts: $CONTRACT_PG"
  echo "- in-progress: $INPROG_PG"
  echo "- deprecated: $DEPRECATED_PG"
  echo "- decisions recorded: $TOTAL_DEC"
  echo "- open tasks: $TOTAL_TSK"
  echo "- lint run: $(date +%Y-%m-%d)"
  echo

  # Page index table
  echo "## Page index"
  echo
  echo "_Field counts let you spot heavy pages before reading them. brd=broadcasts, rxt=reacts_to, emt=emits_to, refs=code_refs, dec=decisions, tsk=tasks._"
  echo
  echo "| slug | status | zoom | parent | brd | rxt | emt | refs | dec | tsk | updated |"
  echo "|---|---|---|---|---:|---:|---:|---:|---:|---:|---|"

  while IFS= read -r f; do
    rel="${f#./}"
    slug=$(basename "$rel" .md)
    status=$(extract_scalar "$f" "status")
    zoom=$(extract_scalar "$f" "zoom")
    parent=$(extract_scalar "$f" "parent")
    updated=$(extract_scalar "$f" "updated")
    brd=$(extract_list "$f" "broadcasts" | grep -c .)
    rxt=$(extract_list "$f" "reacts_to" | grep -c .)
    emt=$(extract_list "$f" "emits_to" | grep -c .)
    refs=$(extract_list "$f" "code_refs" | grep -c .)
    dec=$(grep -c "|${slug}|" "$DECISIONS_FILE" 2>/dev/null); dec=${dec:-0}
    tsk=$(grep -c "|${slug}|" "$ISSUES_FILE" 2>/dev/null); tsk=${tsk:-0}

    # Compact parent: [[foo]] → foo, null/empty → (root)
    pshort="${parent//\[\[/}"
    pshort="${pshort//\]\]/}"
    [[ -z "$pshort" || "$pshort" == "null" ]] && pshort="(root)"

    # Default missing scalars to a single dash for table readability
    [[ -z "$status" ]] && status="-"
    [[ -z "$zoom" ]] && zoom="-"
    [[ -z "$updated" ]] && updated="-"

    echo "| [[$slug]] | $status | $zoom | $pshort | $brd | $rxt | $emt | $refs | $dec | $tsk | $updated |"
  done < <(list_pages | sort)

  echo
  echo "## Per-page detail"
  echo

  while IFS= read -r f; do
    rel="${f#./}"
    slug=$(basename "$rel" .md)
    status=$(extract_scalar "$f" "status")
    title=$(extract_scalar "$f" "title")
    [[ -z "$status" ]] && status="-"

    echo "### [[$slug]] — $status"
    [[ -n "$title" && "$title" != "$slug" ]] && echo "_${title}_"
    echo

    has_any=0

    # broadcasts
    blist=$(extract_list "$f" "broadcasts")
    if [[ -n "$blist" ]]; then
      echo "- broadcasts:"
      while IFS= read -r b; do
        [[ -z "$b" ]] && continue
        echo "    - \`$b\`"
      done <<< "$blist"
      has_any=1
    fi

    # reacts_to
    rlist=$(extract_list "$f" "reacts_to")
    if [[ -n "$rlist" ]]; then
      echo "- reacts_to:"
      while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        echo "    - \`$r\`"
      done <<< "$rlist"
      has_any=1
    fi

    # emits_to
    elist=$(extract_list "$f" "emits_to")
    if [[ -n "$elist" ]]; then
      echo "- emits_to:"
      while IFS= read -r e; do
        [[ -z "$e" ]] && continue
        echo "    - \`$e\`"
      done <<< "$elist"
      has_any=1
    fi

    # code_refs
    cflist=$(extract_list "$f" "code_refs")
    if [[ -n "$cflist" ]]; then
      cf_count=$(grep -c . <<< "$cflist")
      echo "- code_refs ($cf_count):"
      while IFS= read -r cr; do
        [[ -z "$cr" ]] && continue
        echo "    - \`$cr\`"
      done <<< "$cflist"
      has_any=1
    fi

    # decisions: latest 3 by date (DECISIONS_FILE format: date|slug|note)
    dec_total=$(grep -c "|${slug}|" "$DECISIONS_FILE" 2>/dev/null); dec_total=${dec_total:-0}
    if [[ "$dec_total" -gt 0 ]]; then
      show_n=3
      [[ "$dec_total" -lt 3 ]] && show_n=$dec_total
      echo "- decisions ($dec_total total, latest $show_n):"
      grep "|${slug}|" "$DECISIONS_FILE" | sort -r | head -n "$show_n" | while IFS='|' read -r d _ n; do
        # Trim long notes for digest scannability
        if [[ ${#n} -gt 140 ]]; then n="${n:0:137}…"; fi
        echo "    - $d: $n"
      done
      has_any=1
    fi

    # tasks: top 3 by priority (ISSUES_FILE format: priority|slug|todo)
    tsk_total=$(grep -c "|${slug}|" "$ISSUES_FILE" 2>/dev/null); tsk_total=${tsk_total:-0}
    if [[ "$tsk_total" -gt 0 ]]; then
      show_n=3
      [[ "$tsk_total" -lt 3 ]] && show_n=$tsk_total
      echo "- tasks ($tsk_total total, top $show_n by priority):"
      # Sort priority: high(1) < med(2) < low(3); stable within a priority.
      grep "|${slug}|" "$ISSUES_FILE" \
        | awk -F'|' 'BEGIN{p["high"]=1;p["med"]=2;p["low"]=3} {print (p[$1]?p[$1]:9) "\t" $0}' \
        | sort -k1,1n -s \
        | cut -f2- \
        | head -n "$show_n" \
        | while IFS='|' read -r pr _ td; do
            if [[ ${#td} -gt 140 ]]; then td="${td:0:137}…"; fi
            echo "    - [$pr] $td"
          done
      has_any=1
    fi

    [[ $has_any -eq 0 ]] && echo "_(no broadcast graph, code_refs, decisions, or tasks)_"
    echo
  done < <(list_pages | sort)
} > _digest-frontmatter.md

# ── _dependency-rules.md (cross-cutting layer / dependency convention rollup) ──
# Decisions tagged with `type: dependency-rule` declare layered convention
# (which subject paths must not import which forbidden paths). Two-stage flow:
#   - Stage 1 (this block): parse + collect rules, generate the rollup view.
#   - Stage 2 (section 6c below): grep import-like lines in each subject and
#     warn on any line containing a forbidden prefix as substring.
# The page that hosts the decision is irrelevant to enforcement; lint scans
# every page's `decisions:` for the type tag and aggregates here. The owning
# page is recorded so the rule's audit trail (date + page + note) stays
# discoverable from the rollup.
#
# Decision schema (inline form is the only one MVP supports — block style with
# multi-line objects is messier to parse and rare for rules in practice):
#   decisions:
#     - {date: YYYY-MM-DD, type: dependency-rule,
#        subject: "<path-prefix>",
#        forbidden: "<prefix>[, <prefix>...]",
#        note: "<one-line rationale>"}
#
# Example (would belong on the layer page most affected by the rule):
#   - {date: 2026-05-21, type: dependency-rule,
#      subject: "lib/domain/",
#      forbidden: "lib/features/, lib/data/",
#      note: "domain layer stays pure — no Flutter / no storage"}
DEP_RULES_FILE=$(mktemp)

while IFS= read -r f; do
  rel="${f#./}"
  slug=$(basename "$rel" .md)

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Only inline form for MVP (single line containing every field).
    [[ "$line" =~ \{.*type:[[:space:]]*dependency-rule ]] || continue

    d=$(echo "$line" | sed -n 's/.*date:[[:space:]]*\([0-9-]*\).*/\1/p')
    s=$(echo "$line" | sed -n 's/.*subject:[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -z "$s" ]] && s=$(echo "$line" | sed -n "s/.*subject:[[:space:]]*'\([^']*\)'.*/\1/p")
    fb=$(echo "$line" | sed -n 's/.*forbidden:[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -z "$fb" ]] && fb=$(echo "$line" | sed -n "s/.*forbidden:[[:space:]]*'\([^']*\)'.*/\1/p")
    n=$(echo "$line" | sed -n 's/.*note:[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -z "$n" ]] && n=$(echo "$line" | sed -n "s/.*note:[[:space:]]*'\([^']*\)'.*/\1/p")

    # Schema-level lint: subject + forbidden required; date + note optional but
    # warned about because audit trail value drops without them.
    if [[ -z "$s" || -z "$fb" ]]; then
      warn "$rel: dependency-rule decision missing subject or forbidden field — skipped (line: $line)"
      continue
    fi
    if [[ -z "$d" ]]; then
      warn "$rel: dependency-rule (subject=$s) has no date — rollup will sort poorly; add 'date: YYYY-MM-DD'"
    fi
    if [[ -z "$n" ]]; then
      warn "$rel: dependency-rule (subject=$s) has no note — rule's rationale is lost; add 'note: \"...\"'"
    fi

    # Record: date|slug|subject|forbidden|note
    echo "${d:-0000-00-00}|$slug|$s|$fb|$n" >> "$DEP_RULES_FILE"
  done < <(extract_obj_list "$f" "decisions")
done < <(list_pages)

RULE_COUNT=$(grep -c . "$DEP_RULES_FILE" 2>/dev/null); RULE_COUNT=${RULE_COUNT:-0}

{
  echo "---"
  echo "title: dependency-rules (auto-generated)"
  echo "zoom: -1"
  echo "parent: [[index]]"
  echo "status: auto"
  echo "updated: $(date +%Y-%m-%d)"
  echo "---"
  echo
  echo "# dependency-rules (auto-generated)"
  echo
  echo "_Auto-generated by \`_lint.sh\`. Aggregates every \`decisions:\` entry tagged \`type: dependency-rule\` across the vault — declares which subject paths must not import which forbidden paths. Enforcement is **active** via grep-based scan of import-like lines under each subject; violations appear as lint warnings (never errors during introduction phase)._"
  echo
  echo "## Active rules ($RULE_COUNT)"
  echo
  if [[ "$RULE_COUNT" -gt 0 ]]; then
    echo "| date | subject | forbidden | note | recorded in |"
    echo "|---|---|---|---|---|"
    # Sort newest-first so the table shows recent intent at the top
    sort -r -u "$DEP_RULES_FILE" | while IFS='|' read -r d slug s fb n; do
      # Escape pipes inside fields so the markdown table stays well-formed
      s_esc="${s//|/\\|}"
      fb_esc="${fb//|/\\|}"
      n_esc="${n//|/\\|}"
      [[ -z "$n_esc" ]] && n_esc="_(no rationale)_"
      echo "| $d | \`$s_esc\` | \`$fb_esc\` | $n_esc | [[$slug]] |"
    done
  else
    echo "_(no dependency rules recorded yet — add an entry to any page's \`decisions:\` with \`type: dependency-rule\`)_"
  fi
  echo
  echo "## How to add a rule"
  echo
  echo "On the page that best owns the convention (often the layer index page most affected), append to \`decisions:\`:"
  echo
  echo "\`\`\`yaml"
  echo "decisions:"
  echo "  - {date: $(date +%Y-%m-%d), type: dependency-rule,"
  echo "     subject: \"<path-prefix>\","
  echo "     forbidden: \"<prefix>[, <prefix>...]\","
  echo "     note: \"<one-line rationale>\"}"
  echo "\`\`\`"
  echo
  echo "Field semantics:"
  echo
  echo "- **subject** — path prefix (file or directory) whose contents the rule constrains. Glob \`**\` is not used; a trailing slash is the directory convention (\`lib/domain/\`)."
  echo "- **forbidden** — comma-separated list of path prefixes that any file under \`subject\` must not depend on (in MVP semantics: must not reference textually). The grep-based enforcement will treat each entry as a substring match against import lines."
  echo "- **note** — one-line WHY for the rule. Same ≤200 char convention as regular decisions."
  echo
  echo "## Limits"
  echo
  echo "- MVP supports only inline-form decision entries (single line with all fields). Block-style multi-line objects are skipped."
  echo "- Enforcement is **substring-based** on import-like lines (leading \`import\` / \`from\` / \`use\` / \`require\`). False positives possible when a forbidden prefix appears as a comment or string in an import statement; refine \`subject\` / \`forbidden\` to scope down."
  echo "- Violations are reported as **warnings**, never errors — the V-06 lint-PASS gate is not blocked. Tighten to error once the rule corpus stabilizes (manual: change \`warn\` to \`err\` in section 6c)."
  echo "- Missing \`subject\` path under \`\$PROJECT_ROOT\` triggers a warning and skips enforcement for that rule."
  echo "- The owning page (\`recorded in\` column) is not enforced — rules apply globally regardless of where they live. The column is informational (audit trail)."
} > _dependency-rules.md

# ───────────────────────────────────────────────────────────
# 6c. dependency-rule enforcement (import grep, warn-only)
# ───────────────────────────────────────────────────────────
# For each rule recorded above: resolve subject path against $PROJECT_ROOT,
# grep import-like lines in files under subject for any forbidden prefix as
# a fixed substring. Each hit becomes one warning (never error — false
# positive tolerance during rule introduction; user refines subject/forbidden
# or moves the file).
#
# Import-like line heuristic — leading whitespace, then one of:
#   `import`  (Dart / Kotlin / Java / Swift / TypeScript / JS / Go / Python)
#   `from`    (Python `from X import Y`)
#   `use`     (Rust / PHP)
#   `require` (Ruby / Node)
# Misses some niches (CMake `include()`, C `#include`) — acceptable for MVP.
#
# Performance: one grep -rIn per (rule × forbidden-prefix). For projects with
# a small handful of rules this is negligible compared to the rollup scans
# above.
if [[ "$RULE_COUNT" -gt 0 ]]; then
  echo "▼ 6c. enforcing dependency-rule decisions ($RULE_COUNT rule(s))"
  DEPRULE_VIOLATIONS=0
  while IFS='|' read -r dr_date dr_slug dr_subject dr_forbidden dr_note; do
    [[ -z "$dr_subject" ]] && continue
    abs_subject="$PROJECT_ROOT/$dr_subject"
    if [[ ! -e "$abs_subject" ]]; then
      warn "dependency-rule (subject=$dr_subject) — path missing under \$PROJECT_ROOT; enforcement skipped"
      continue
    fi

    # Split forbidden CSV into individual prefixes
    OLD_IFS="$IFS"
    IFS=','
    set -f   # temporarily disable glob so a prefix like 'lib/*' isn't expanded
    forbid_array=($dr_forbidden)
    set +f
    IFS="$OLD_IFS"

    for forbid in "${forbid_array[@]}"; do
      # Trim leading/trailing whitespace
      forbid_trim="${forbid#"${forbid%%[![:space:]]*}"}"
      forbid_trim="${forbid_trim%"${forbid_trim##*[![:space:]]}"}"
      [[ -z "$forbid_trim" ]] && continue

      # grep import-like lines, then filter for forbidden substring.
      #   -r recurse, -I skip binary, -n line numbers, -E extended regex.
      # Both GNU grep (Linux) and BSD grep (macOS) support -rInE.
      hits=$(grep -rInE "^[[:space:]]*(import|from|use|require)([[:space:]]|\()" \
               "$abs_subject" 2>/dev/null \
             | grep -F "$forbid_trim" || true)

      [[ -z "$hits" ]] && continue

      while IFS=: read -r v_file v_line v_content; do
        [[ -z "$v_file" ]] && continue
        rel_file="${v_file#$PROJECT_ROOT/}"
        # Truncate echoed line so logs stay readable
        v_short="${v_content## }"
        if [[ ${#v_short} -gt 100 ]]; then v_short="${v_short:0:97}…"; fi
        warn "dep-rule violation: $rel_file:$v_line imports '$forbid_trim' (rule [[$dr_slug]] $dr_date: $dr_note) — line: $v_short"
        DEPRULE_VIOLATIONS=$((DEPRULE_VIOLATIONS+1))
      done <<< "$hits"
    done
  done < "$DEP_RULES_FILE"
  if [[ $DEPRULE_VIOLATIONS -gt 0 ]]; then
    echo "    $DEPRULE_VIOLATIONS violation(s) reported as warnings"
  else
    echo "    no violations"
  fi
fi

rm -f "$PROGRESS_FILE" "$DECISIONS_FILE" "$ISSUES_FILE" "$DEP_RULES_FILE"

# ───────────────────────────────────────────────────────────
# 7. Layer index (zoom 0) diagram-section check
# ───────────────────────────────────────────────────────────
echo "▼ 7. layer index diagram sections (zoom 0)"

while IFS= read -r f; do
  rel="${f#./}"
  zoom=$(extract_scalar "$f" "zoom")
  [[ "$zoom" != "0" ]] && continue

  # exclude system pages (filenames starting with _) — they have their own structural expectations (variants table, etc.)
  base=$(basename "$rel")
  [[ "$base" == _* ]] && continue

  status=$(extract_scalar "$f" "status")
  [[ "$status" == "deprecated" ]] && continue

  has_struct=0
  has_flow=0
  grep -qE '^## Structure( |$)' "$f" && has_struct=1
  grep -qE '^## Flow( |$)' "$f" && has_flow=1

  if [[ $has_struct -eq 0 ]]; then
    warn "$rel: zoom 0 layer index missing '## Structure' ASCII diagram (bootstrap.sh creates the stub)"
  fi
  if [[ $has_flow -eq 0 ]]; then
    warn "$rel: zoom 0 layer index missing '## Flow' ASCII diagram (pick the best fit: broadcast/state-machine/sequence/decision-tree)"
  fi
done < <(list_pages)

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
TOTAL_PAGES=$(list_pages | wc -l | tr -d ' ')
echo
echo "═══════════════════════════════════════════════"
echo "vault lint summary"
echo "  pages:    $TOTAL_PAGES"
echo "  errors:   $ERRORS"
echo "  warnings: $WARNINGS"
echo "  generated:"
echo "    - _reverse-index.md"
echo "    - _progress.md"
echo "    - _decisions.md"
echo "    - _open-issues.md"
echo "    - _digest-frontmatter.md"
echo "    - _dependency-rules.md"
echo "═══════════════════════════════════════════════"

# V-06: 작업 종료 전 `_lint.sh` PASS 미확인 — exit code 가 그 검사 자체.
#       ERRORS > 0 면 exit 1, /vdd-done skill body 가 이 exit code 를 점검한다.
[[ $ERRORS -gt 0 ]] && exit 1 || exit 0
