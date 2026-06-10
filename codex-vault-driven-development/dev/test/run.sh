#!/usr/bin/env bash
#
# run.sh — golden + exit-code regression tests for the VDD deterministic scripts.
#
# Locks the behavior of the graph-computation core that has NO other guard:
#   - scripts/vdd-yaml-lib.sh   (frontmatter extractors — every script depends on it)
#   - scripts/vdd-blast.sh      (broadcast key → reactor/emitter graph)
#   - scripts/vdd-impact.sh     (code file → owner pages + intent_refs closure)
#   - scripts/vdd-plan.sh       (contract delta → affected pages, via --diff)
#   - scripts/vdd-schedule.sh   (owner_page set → parallel batch schedule; cycle → exit 3)
#   - _lint.sh                  (error DETECTION — exit-code only, output is date-dependent)
#
# Two assertion kinds:
#   golden  — normalized stdout diffed against dev/test/golden/<name>.txt
#   exit    — exit code of a run against a fixture
#
# Why _lint is exit-code only: it stamps `updated: $(date)` into generated
# rollups and its staleness check is time-relative, so its stdout is not
# reproducible. The valuable, stable contract is its exit code (0 = clean,
# 1 = schema/reference violation).
#
# Regenerate goldens after an INTENTIONAL behavior change:
#   UPDATE_GOLDEN=1 bash dev/test/run.sh
# then review the diff before committing (golden-master rule: never blind-update).
#
# Run: bash dev/test/run.sh   (also wired into CI smoke.yml)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FX="$ROOT/dev/test/fixtures"
GOLDEN="$ROOT/dev/test/golden"
LINT="$ROOT/scripts/_lint.sh"
SCRIPTS="$ROOT/scripts"
UPDATE="${UPDATE_GOLDEN:-0}"

mkdir -p "$GOLDEN"

PASS=0
FAIL=0
TMPDIRS=()
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Normalize machine-specific paths so goldens are portable across checkouts.
# $1 = a tmp dir to mask (may be empty).
normalize() {
  local tmp="${1:-}"
  if [ -n "$tmp" ]; then
    sed -e "s|$tmp|<TMP>|g" -e "s|$ROOT|<REPO>|g"
  else
    sed -e "s|$ROOT|<REPO>|g"
  fi
}

# golden <name> <normalized-output>
golden() {
  local name="$1" actual="$2" gf="$GOLDEN/$1.txt"
  if [ "$UPDATE" = "1" ]; then
    printf '%s\n' "$actual" > "$gf"
    echo "  UPDATED  $name"
    return
  fi
  if [ ! -f "$gf" ]; then
    echo "  MISSING  $name  (no golden file — run UPDATE_GOLDEN=1 bash dev/test/run.sh)"
    FAIL=$((FAIL+1))
    return
  fi
  if diff -u "$gf" <(printf '%s\n' "$actual") >/tmp/vdd-golden-diff.$$ 2>&1; then
    echo "  ok       $name"
    PASS=$((PASS+1))
  else
    echo "  DIFF     $name"
    sed 's/^/         /' /tmp/vdd-golden-diff.$$
    FAIL=$((FAIL+1))
  fi
  rm -f /tmp/vdd-golden-diff.$$
}

# expect_exit <name> <expected-code> <actual-code>
expect_exit() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    echo "  ok       $name  (exit $got)"
    PASS=$((PASS+1))
  else
    echo "  FAIL     $name  (exit $got, want $want)"
    FAIL=$((FAIL+1))
  fi
}

# prep_sample — copy sample-vault to a fresh tmp project root, generate
# _reverse-index via _lint (required by vdd-blast), echo the tmp path.
prep_sample() {
  local t; t="$(mktemp -d)"
  TMPDIRS+=("$t")
  cp -R "$FX/sample-vault/." "$t/"
  CLAUDE_PROJECT_DIR="$t" bash "$LINT" >/dev/null 2>&1 || true
  echo "$t"
}

echo "── vdd-yaml-lib extractors ──"
# Source the canonical extractors and probe against the committed fixture page.
( . "$SCRIPTS/vdd-yaml-lib.sh"
  CONN="$FX/sample-vault/docs/vault/connection/connection.md"
  {
    echo "# reacts_to";   extract_list "$CONN" reacts_to
    echo "# intent_refs"; extract_list "$CONN" intent_refs
    echo "# code_refs";   extract_list "$CONN" code_refs
    echo "# status";      extract_scalar "$CONN" status
  }
) > /tmp/vdd-yaml.$$ 2>&1
golden "yaml-lib-extractors" "$(normalize '' < /tmp/vdd-yaml.$$)"
rm -f /tmp/vdd-yaml.$$

echo "── vdd-blast ──"
T="$(prep_sample)"
OUT="$(CLAUDE_PROJECT_DIR="$T" bash "$SCRIPTS/vdd-blast.sh" auth:expired 2>&1)"
golden "blast-auth-expired" "$(printf '%s' "$OUT" | normalize "$T")"
# absent key → no reactor/emitter → exit 1
CLAUDE_PROJECT_DIR="$T" bash "$SCRIPTS/vdd-blast.sh" nonexistent:key >/dev/null 2>&1
expect_exit "blast-absent-key-exit" 1 "$?"

echo "── vdd-impact ──"
T="$(prep_sample)"
OUT="$(CLAUDE_PROJECT_DIR="$T" bash "$SCRIPTS/vdd-impact.sh" src/connection/socket.ts 2>&1)"
golden "impact-socket-ts" "$(printf '%s' "$OUT" | normalize "$T")"
# unowned file → graceful "no vault page" + exit 0
OUT="$(CLAUDE_PROJECT_DIR="$T" bash "$SCRIPTS/vdd-impact.sh" src/nope/unowned.ts 2>&1)"
golden "impact-unowned" "$(printf '%s' "$OUT" | normalize "$T")"

echo "── vdd-plan --diff ──"
# --diff bypasses git for the delta, but the script still requires PROJECT_ROOT
# to carry a docs/vault inside a git repo — use the in-place sample fixture
# (it lives in this repo's git tree). --diff reads OLD/NEW read-only.
OUT="$(CLAUDE_PROJECT_DIR="$FX/sample-vault" bash "$SCRIPTS/vdd-plan.sh" --diff "$FX/plan-delta/old" "$FX/plan-delta/new" 2>&1)"
golden "plan-diff-add-remove" "$(printf '%s' "$OUT" | normalize '')"

echo "── vdd-schedule ──"
# Acyclic: 3 owner_pages over the sample broadcast graph. Output is path-free
# (node ids are vault-relative), so no tmp dir / lint / git needed — point
# CLAUDE_PROJECT_DIR straight at the in-repo fixture.
OUT="$(CLAUDE_PROJECT_DIR="$FX/sample-vault" bash "$SCRIPTS/vdd-schedule.sh" auth/_state-contract auth/auth connection/connection 2>&1)"
golden "schedule-3page" "$(printf '%s' "$OUT" | normalize '')"
# Cycle fixture → residual CYCLE batch + exit 3.
OUT="$(CLAUDE_PROJECT_DIR="$FX/schedule-cycle" bash "$SCRIPTS/vdd-schedule.sh" a/a b/b 2>&1)"
golden "schedule-cycle" "$(printf '%s' "$OUT" | normalize '')"
CLAUDE_PROJECT_DIR="$FX/schedule-cycle" bash "$SCRIPTS/vdd-schedule.sh" a/a b/b >/dev/null 2>&1
expect_exit "schedule-cycle-exit" 3 "$?"
# Unresolvable page → usage error exit 1.
CLAUDE_PROJECT_DIR="$FX/sample-vault" bash "$SCRIPTS/vdd-schedule.sh" no/such-page >/dev/null 2>&1
expect_exit "schedule-missing-exit" 1 "$?"

echo "── _lint exit codes ──"
T="$(prep_sample)"
CLAUDE_PROJECT_DIR="$T" bash "$LINT" >/dev/null 2>&1
expect_exit "lint-sample-clean" 0 "$?"
for fx in broken-dangling-reactor broken-missing-coderef; do
  t="$(mktemp -d)"; TMPDIRS+=("$t"); cp -R "$FX/$fx/." "$t/"
  CLAUDE_PROJECT_DIR="$t" bash "$LINT" >/dev/null 2>&1
  expect_exit "lint-$fx" 1 "$?"
done

echo
echo "═══════════════════════════════════════════════"
if [ "$UPDATE" = "1" ]; then
  echo "goldens updated — review the diff before committing."
  exit 0
fi
echo "vdd script tests:  $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════"
[ "$FAIL" -eq 0 ]
