#!/usr/bin/env bash
#
# check-counts.sh — surface-count regression lock (root-cause #2)
#
# The skill / agent / hook / lint-check counts are stated in prose across
# README, docs/, dev/MIGRATION. They have drifted on every refactor
# (13 → 14 → 11 → 10) because each is a hand-copied derived fact with no
# gate. This pins the *canonical* count statements — the exact lines that
# kept breaking — to ground truth derived from the repo itself.
#
# This is NOT a universal scanner. It is a regression lock on a declared
# list of sites (the `chk` table below). Adding a new canonical count
# statement to a doc means adding one `chk` line here — that pairing IS
# the discipline (same shape as _lint.sh V-09 / Check 4c, marker-free).
#
# CHANGELOG.md is excluded by design: it is point-in-time history and its
# released sections are frozen (Keep a Changelog). Correcting a shipped
# release's numbers would falsify history; the [Unreleased] section is
# reconciled editorially, not mechanically.
#
# Run locally: bash dev/check-counts.sh   (also wired into CI smoke.yml)

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# ─── ground truth — every value derived, never hand-typed ───
SKILLS=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
INTERNAL=$(grep -rlE '^user-invocable:[[:space:]]*false' skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
INVOCABLE=$((SKILLS - INTERNAL))
AGENTS=$(find agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
HOOKS=$(find hooks -maxdepth 1 -name '*.sh' | wc -l | tr -d ' ')
CHECKS=$(grep -oE 'Checks \([0-9]+ total' scripts/_lint.sh | grep -oE '[0-9]+' | head -1)

echo "ground truth: skills=$SKILLS invocable=$INVOCABLE agents=$AGENTS hooks=$HOOKS checks=$CHECKS"

fail=0

# tok <file> <anchor-ERE> <token-ERE> — first integer of <token-ERE> on the
# first line of <file> matching <anchor-ERE>. Empty if the anchor is gone.
tok() { grep -E "$2" "$1" 2>/dev/null | head -1 | grep -oE "$3" | grep -oE '[0-9]+' | head -1; }

# chk <label> <file> <anchor-ERE> <token-ERE> <expected>
chk() {
  local a; a="$(tok "$2" "$3" "$4")"
  if [ "$a" != "$5" ]; then
    echo "DRIFT  $1  ($2)  found '${a:-∅}', expect '$5'"
    fail=1
  fi
}

# ─── pinned sites = the lines that drifted 4× ───
chk "README skills"        README.md           '\*\*[0-9]+ skills, [0-9]+ user-invocable\*\*' '[0-9]+ skills'         "$SKILLS"
chk "README invocable"     README.md           '\*\*[0-9]+ skills, [0-9]+ user-invocable\*\*' '[0-9]+ user-invocable' "$INVOCABLE"
chk "README agents"        README.md           '\*\*[0-9]+ agents\*\*'                        '[0-9]+ agents'         "$AGENTS"
chk "README hook"          README.md           'hook \([0-9]+\):'                             '[0-9]+'                "$HOOKS"
chk "README checks"        README.md           '_lint\.sh.*[0-9]+ checks'                     '[0-9]+ checks'         "$CHECKS"

chk "QUICKSTART skills"    docs/QUICKSTART.md  'loads [0-9]+ skills'                          '[0-9]+ skills'         "$SKILLS"
chk "QUICKSTART agents"    docs/QUICKSTART.md  'loads [0-9]+ skills'                          '[0-9]+ agents'         "$AGENTS"
chk "QUICKSTART hook"      docs/QUICKSTART.md  'loads [0-9]+ skills'                          '[0-9]+ hook'           "$HOOKS"
chk "QUICKSTART checks"    docs/QUICKSTART.md  '_lint\.sh.*[0-9]+ checks'                     '[0-9]+ checks'         "$CHECKS"
chk "QUICKSTART route"     docs/QUICKSTART.md  'skills route by prompt'                       '[0-9]+'                "$INVOCABLE"

chk "INTEGRATION skills"   docs/INTEGRATION.md '^### Skills \('                               '[0-9]+'                "$SKILLS"
chk "INTEGRATION agents"   docs/INTEGRATION.md '^### Agents \('                               '[0-9]+'                "$AGENTS"
chk "INTEGRATION checks"   docs/INTEGRATION.md '_lint\.sh.*[0-9]+ checks'                     '[0-9]+ checks'         "$CHECKS"

chk "MIGRATION skills"     dev/MIGRATION.md    'skills/.*[0-9]+ skills \(all vdd'             '[0-9]+ skills'         "$SKILLS"
chk "MIGRATION agents"     dev/MIGRATION.md    'agents/.*[0-9]+ agents \(.*vault'             '[0-9]+ agents'         "$AGENTS"
chk "MIGRATION ships skl"  dev/MIGRATION.md    'now ships \*\*[0-9]+ skills'                  '[0-9]+ skills'         "$SKILLS"
chk "MIGRATION ships inv"  dev/MIGRATION.md    'now ships \*\*[0-9]+ skills'                  '[0-9]+ user-invocable' "$INVOCABLE"

if [ "$fail" -eq 0 ]; then
  echo "✓ surface counts consistent with repo ground truth"
  exit 0
else
  echo "✗ surface-count drift — fix the doc(s) above or update the chk site if a count legitimately changed"
  exit 1
fi
