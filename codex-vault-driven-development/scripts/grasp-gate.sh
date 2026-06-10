#!/usr/bin/env bash
# grasp-gate — Grasp note 가 touched 페이지의 *모든* decision 을 평가했는지 결정론 검사.
#
# 안 본 decision = note 에 그 date 가 없음 = 적발. (verdict 가 *맞는지*는 못 봄 —
# 그건 confabulation 가능, 사람 confirm 의 몫. 여기는 "다뤘나"의 구조 floor 만.)
# coverage-gate 와 같은 모양: 구조는 결정론, 의미는 사람.
#
# usage: grasp-gate.sh <grasp-note-file> <page.md> [<page.md>...]
#   note 파일은 Grasp note 텍스트 (각 decision date 가 verdict 라인에 등장해야).
set -euo pipefail
if [ "$#" -lt 2 ]; then
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
NOTE="$1"; shift
[ -f "$NOTE" ] || { echo "grasp note 파일 없음: $NOTE"; exit 2; }

# 한 페이지 frontmatter 의 decisions: 블록에서 date 추출
dates_of() {
  awk '/^decisions:/{f=1;print;next} f&&/^[a-zA-Z_]+:/{f=0} f{print}' "$1" \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u
}

missing=0; total=0
for page in "$@"; do
  if [ ! -f "$page" ]; then echo "  WARN page 없음: $page"; continue; fi
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    total=$((total+1))
    if ! grep -qF "$d" "$NOTE"; then
      echo "  UNADDRESSED  $page  decision [$d] — Grasp note 에 verdict 없음 (안 봤거나 누락)"
      missing=$((missing+1))
    fi
  done < <(dates_of "$page")
done

echo
if [ "$missing" -gt 0 ]; then
  echo "FAIL: $total 중 $missing decision 미평가. 각 조건에 verdict{HOLDS/BROKEN/N-A}+근거를 적어라."
  echo "      (안 본 decision 을 결정론으로 적발. verdict 가 *맞는지*는 step 11 사람 confirm 의 몫.)"
  exit 1
fi
echo "PASS: touched 페이지의 $total decision 모두 Grasp note 에서 평가됨 (구조 floor)."
exit 0
