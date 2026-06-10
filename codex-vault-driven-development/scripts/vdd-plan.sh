#!/usr/bin/env bash
#
# vdd-plan.sh — contract delta → affected pages + update TODO
#
# Usage:
#   vdd plan                    # HEAD~1..HEAD
#   vdd plan REF_OLD            # REF_OLD..HEAD
#   vdd plan REF_OLD REF_NEW
#   vdd plan --staged           # staged vs HEAD
#
# Output:
#   - Per-page contract changes (broadcasts/reacts_to/emits_to + / -)
#   - Per-key affected pages list (current reactors/emitters)
#   - TODO templates per affected page
#   - Summary counts
#
# Pairs with vault-planner subagent: this script outputs deterministic facts;
# vault-planner adds intent + prose to produce per-page update plan.

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

# vdd-plan needs git for staged-diff and history walk — ensure project is a git repo.
if ! (cd "$VAULT" && git rev-parse --show-toplevel >/dev/null 2>&1); then
  echo "ERROR: vault is not inside a git repo" >&2
  exit 1
fi

REL_VAULT="${VAULT#$PROJECT_ROOT/}"

# ─── ARG PARSE ──────────────────────────────────────
REF_OLD="HEAD~1"
REF_NEW="HEAD"
STAGED=0
DIFF_MODE=""
DIFF_OLD_DIR=""
DIFF_NEW_DIR=""

if [ $# -ge 1 ]; then
  case "$1" in
    --staged)
      STAGED=1
      ;;
    --diff)
      # --diff OLD_DIR NEW_DIR — bypass git, compare two vault dirs (for gitignored vaults or testing)
      if [ $# -lt 3 ]; then
        echo "ERROR: --diff requires OLD_DIR NEW_DIR" >&2
        exit 1
      fi
      DIFF_MODE=1
      DIFF_OLD_DIR="$(cd "$2" 2>/dev/null && pwd || true)"
      DIFF_NEW_DIR="$(cd "$3" 2>/dev/null && pwd || true)"
      if [ -z "$DIFF_OLD_DIR" ] || [ -z "$DIFF_NEW_DIR" ]; then
        echo "ERROR: both OLD_DIR and NEW_DIR must exist" >&2
        exit 1
      fi
      ;;
    -h|--help)
      sed -n '3,17p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      REF_OLD="$1"
      [ $# -ge 2 ] && REF_NEW="$2"
      ;;
  esac
fi

# Current vault dir for reactor lookups (diff-mode uses NEW_DIR; otherwise live worktree)
CURRENT_VAULT="$VAULT"
[ -n "$DIFF_MODE" ] && CURRENT_VAULT="$DIFF_NEW_DIR"

cd "$CURRENT_VAULT" || exit 1

# ─── HELPERS ────────────────────────────────────────
# extract_list_stdin is provided by the sourced scripts/vdd-yaml-lib.sh
# (canonical — now also handles inline arrays + quoted keys in the diff).

norm() {
  if [[ "$1" == *"#"* ]]; then echo "${1#*#}"; else echo "$1"; fi
}

get_old_content() {
  local page="$1"
  if [ -n "$DIFF_MODE" ]; then
    [ -f "$DIFF_OLD_DIR/$page" ] && cat "$DIFF_OLD_DIR/$page" || true
  elif [ "$STAGED" -eq 1 ]; then
    (cd "$PROJECT_ROOT" && git show "HEAD:$page" 2>/dev/null) || true
  else
    (cd "$PROJECT_ROOT" && git show "$REF_OLD:$page" 2>/dev/null) || true
  fi
}

get_new_content() {
  local page="$1"
  if [ -n "$DIFF_MODE" ]; then
    [ -f "$DIFF_NEW_DIR/$page" ] && cat "$DIFF_NEW_DIR/$page" || true
  elif [ "$STAGED" -eq 1 ]; then
    (cd "$PROJECT_ROOT" && git show ":$page" 2>/dev/null) || true
  else
    if [ "$REF_NEW" = "HEAD" ] || [ "$REF_NEW" = "WORKTREE" ]; then
      [ -f "$PROJECT_ROOT/$page" ] && cat "$PROJECT_ROOT/$page" || true
    else
      (cd "$PROJECT_ROOT" && git show "$REF_NEW:$page" 2>/dev/null) || true
    fi
  fi
}

# ─── STEP 1: list changed vault pages ────────────────
if [ -n "$DIFF_MODE" ]; then
  # diff two directories — list .md files differing between them (path relative to dir root)
  CHANGED=$(
    {
      (cd "$DIFF_OLD_DIR" && find . -type f -name "*.md" 2>/dev/null | sed 's|^\./||')
      (cd "$DIFF_NEW_DIR" && find . -type f -name "*.md" 2>/dev/null | sed 's|^\./||')
    } | sort -u | while IFS= read -r rel; do
      OLD_FILE="$DIFF_OLD_DIR/$rel"
      NEW_FILE="$DIFF_NEW_DIR/$rel"
      if [ ! -f "$OLD_FILE" ] || [ ! -f "$NEW_FILE" ] || ! cmp -s "$OLD_FILE" "$NEW_FILE"; then
        # exclude only auto-rollups + examples + archive
        # _state-contract.md IS included (primary emitter)
        BASE_REL=$(basename "$rel")
        if [[ "$BASE_REL" == "_reverse-index.md" ]] || [[ "$BASE_REL" == "_progress.md" ]] || [[ "$BASE_REL" == "_decisions.md" ]] || [[ "$BASE_REL" == "_open-issues.md" ]]; then
          :
        elif [[ "$rel" == examples/* ]] || [[ "$rel" == */examples/* ]] || [[ "$rel" == _archive/* ]] || [[ "$rel" == */_archive/* ]]; then
          :
        else
          echo "$rel"
        fi
      fi
    done
  )
  RANGE_LABEL="diff: $DIFF_OLD_DIR  ↔  $DIFF_NEW_DIR"
elif [ "$STAGED" -eq 1 ]; then
  # Exclude only auto-rollups + examples + archive. _state-contract.md IS
  # included — it is the primary emitter page and the whole point of a
  # contract-delta plan. (A blanket `grep -v /_` would wrongly drop it.)
  CHANGED=$(cd "$PROJECT_ROOT" && git diff --cached --name-only -- "$REL_VAULT/" 2>/dev/null | grep '\.md$' | grep -vE '/(_reverse-index|_progress|_decisions|_open-issues)\.md$' | grep -vE '(^|/)(examples|_archive)/' || true)
  RANGE_LABEL="staged vs HEAD"
else
  CHANGED=$(cd "$PROJECT_ROOT" && git diff --name-only "$REF_OLD" "$REF_NEW" -- "$REL_VAULT/" 2>/dev/null | grep '\.md$' | grep -vE '/(_reverse-index|_progress|_decisions|_open-issues)\.md$' | grep -vE '(^|/)(examples|_archive)/' || true)
  RANGE_LABEL="$REF_OLD..$REF_NEW"
fi

# ─── HEADER ─────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "vdd-plan: $RANGE_LABEL"
echo "  vault: $REL_VAULT"
echo "═══════════════════════════════════════════════"
echo

if [ -z "$CHANGED" ]; then
  echo "(no vault page changes in range)"
  exit 0
fi

# ─── STEP 2: per-page diff frontmatter graph fields ──
TMPDIR_LOCAL=$(mktemp -d)
trap "rm -rf $TMPDIR_LOCAL" EXIT
CHANGES_FILE="$TMPDIR_LOCAL/changes.txt"  # page|kind|action|key
> "$CHANGES_FILE"

for page in $CHANGED; do
  OLD_CONTENT=$(get_old_content "$page")
  NEW_CONTENT=$(get_new_content "$page")

  for kind in broadcasts reacts_to emits_to; do
    OLD_LIST_FILE="$TMPDIR_LOCAL/old.$kind.txt"
    NEW_LIST_FILE="$TMPDIR_LOCAL/new.$kind.txt"
    > "$OLD_LIST_FILE"
    > "$NEW_LIST_FILE"

    if [ -n "$OLD_CONTENT" ]; then
      while IFS= read -r l; do
        [ -z "$l" ] && continue
        norm "$l"
      done < <(echo "$OLD_CONTENT" | extract_list_stdin "$kind") | sort -u > "$OLD_LIST_FILE"
    fi
    if [ -n "$NEW_CONTENT" ]; then
      while IFS= read -r l; do
        [ -z "$l" ] && continue
        norm "$l"
      done < <(echo "$NEW_CONTENT" | extract_list_stdin "$kind") | sort -u > "$NEW_LIST_FILE"
    fi

    # added = NEW \ OLD
    while IFS= read -r added; do
      [ -z "$added" ] && continue
      echo "$page|$kind|+|$added" >> "$CHANGES_FILE"
    done < <(comm -13 "$OLD_LIST_FILE" "$NEW_LIST_FILE")

    # removed = OLD \ NEW
    while IFS= read -r removed; do
      [ -z "$removed" ] && continue
      echo "$page|$kind|-|$removed" >> "$CHANGES_FILE"
    done < <(comm -23 "$OLD_LIST_FILE" "$NEW_LIST_FILE")
  done
done

# ─── STEP 3: report ──────────────────────────────────
if [ ! -s "$CHANGES_FILE" ]; then
  echo "▼ Pages changed: $(echo "$CHANGED" | wc -l | tr -d ' ')"
  echo "  (no broadcast graph changes — body/code_refs only)"
  echo
  echo "Affected pages:"
  echo "$CHANGED" | sed 's/^/  - /'
  exit 0
fi

echo "▼ Contract changes per page"
echo
LAST_PAGE=""
while IFS='|' read -r page kind action key; do
  if [ "$page" != "$LAST_PAGE" ]; then
    [ -n "$LAST_PAGE" ] && echo
    echo "  $page"
    LAST_PAGE="$page"
  fi
  echo "    $kind: $action $key"
done < <(sort "$CHANGES_FILE")
echo
echo

echo "▼ Affected pages by key (current reactors/emitters)"

# Collect all affected pages globally for summary
AFFECTED_PAGES_FILE="$TMPDIR_LOCAL/affected.txt"
> "$AFFECTED_PAGES_FILE"
TODO_COUNT_FILE="$TMPDIR_LOCAL/todos.txt"
> "$TODO_COUNT_FILE"

# Unique keys
KEYS=$(awk -F'|' '{print $4}' "$CHANGES_FILE" | sort -u)

while IFS= read -r key; do
  [ -z "$key" ] && continue
  echo

  REMOVED_BCAST=$(grep -F "|broadcasts|-|$key" "$CHANGES_FILE" | head -1 || true)
  ADDED_BCAST=$(grep -F "|broadcasts|+|$key" "$CHANGES_FILE" | head -1 || true)

  if [ -n "$REMOVED_BCAST" ]; then
    SOURCE_PAGE="${REMOVED_BCAST%%|*}"
    echo "  ▼ \`$key\` (broadcasts removed from $SOURCE_PAGE)"

    # Find current reactors via current vault state (already up to date)
    REACTOR_FILE="$TMPDIR_LOCAL/reactors.$$.txt"
    > "$REACTOR_FILE"
    while IFS= read -r f; do
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if [[ "$(norm "$r")" == "$key" ]]; then
          echo "$f" >> "$REACTOR_FILE"
          break
        fi
      done < <(extract_list_stdin "reacts_to" < "$f")
    done < <(find . -type f -name "*.md" ! -name "_reverse-index.md" ! -name "_progress.md" ! -name "_decisions.md" ! -name "_open-issues.md" ! -path "./examples/*" ! -path "./_archive/*" ! -path "*.removed.*" ! -path "*.bak.*")

    if [ -s "$REACTOR_FILE" ]; then
      while IFS= read -r rf; do
        slug="$(basename "${rf#./}" .md)"
        path="${rf#./}"
        echo "    - [[$slug]]  ($path)"
        echo "      TODO: remove \`$key\` from reacts_to or migrate to a replacement key"
        echo "      TODO: re-review § dependent logic in body (this signal is gone)"
        echo "      TODO: run vault-verifier after changes to validate consistency"
        echo "$path" >> "$AFFECTED_PAGES_FILE"
        echo "x" >> "$TODO_COUNT_FILE"
        echo "x" >> "$TODO_COUNT_FILE"
        echo "x" >> "$TODO_COUNT_FILE"
      done < "$REACTOR_FILE"
    else
      echo "    (no current reactors — clean removal)"
    fi
  elif [ -n "$ADDED_BCAST" ]; then
    SOURCE_PAGE="${ADDED_BCAST%%|*}"
    echo "  ▼ \`$key\` (broadcasts added to $SOURCE_PAGE)"
    echo "    TODO: identify potential reactors — which layers should respond to this signal?"
    echo "    TODO: add \`reacts_to: $key\` to identified reactor pages"
    echo "    TODO: update reactor matrix on the emitter page (${SOURCE_PAGE})"
    echo "x" >> "$TODO_COUNT_FILE"
    echo "x" >> "$TODO_COUNT_FILE"
    echo "x" >> "$TODO_COUNT_FILE"
  else
    # Only reacts_to / emits_to changes for this key (no broadcast change)
    echo "  ▼ \`$key\` (reactor/emitter graph changed; emitter unchanged)"
    while IFS='|' read -r p k a kk; do
      echo "    - $p  $k: $a $kk"
      echo "$p" >> "$AFFECTED_PAGES_FILE"
    done < <(grep -F "|$key" "$CHANGES_FILE")
    echo "    TODO: state intent of the graph change — add a frontmatter \`decisions:\` entry"
    echo "x" >> "$TODO_COUNT_FILE"
  fi
done <<< "$KEYS"

echo
echo "═══════════════════════════════════════════════"
echo "Summary"
echo "═══════════════════════════════════════════════"
CHANGE_COUNT=$(wc -l < "$CHANGES_FILE" | tr -d ' ')
KEY_COUNT=$(echo "$KEYS" | grep -c . | tr -d ' ')
AFFECTED_COUNT=$(sort -u "$AFFECTED_PAGES_FILE" 2>/dev/null | grep -c . | tr -d ' ')
TODO_COUNT=$(wc -l < "$TODO_COUNT_FILE" | tr -d ' ')
[ -z "$AFFECTED_COUNT" ] && AFFECTED_COUNT=0
[ -z "$TODO_COUNT" ] && TODO_COUNT=0

echo "  contract changes:  $CHANGE_COUNT"
echo "  affected keys:     $KEY_COUNT"
echo "  affected pages:    $AFFECTED_COUNT"
echo "  TODO items:        $TODO_COUNT"
echo
echo "Next:"
echo "  1. note the change intent (why this contract change?)"
echo "  2. pass output above + intent to the vault-planner subagent:"
echo "       \"prose-ify this plan via vault-planner. intent: <...>\""
echo "  3. planner produces an actionable per-page plan"
echo "  4. human applies the plan → batch-validate with vault-verifier"
echo "═══════════════════════════════════════════════"
