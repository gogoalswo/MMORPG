#!/usr/bin/env bash
# 고도 테스트를 전부 돌리고 **실패한 것만** 찍는다.
#
# 통과한 열다섯 개를 매번 열다섯 줄로 받으면, 읽는 값이 고치는 값보다 커진다
# (2026-09-17 에 지적받았다). 통과는 한 줄로 요약하고, 깨진 것만 자세히 편다.
#
#   npm run test:godot            전부
#   npm run test:godot -- combat  하나만
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-}"
for candidate in "$GODOT" "$HOME/godot-bin/godot" "$(command -v godot || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && GODOT="$candidate" && break
done
if [ -z "$GODOT" ]; then
  echo "고도를 못 찾았다 — docs/features/godot-migration.md 의 '엔진은 저장소에 넣지 않는다' 참고"
  exit 1
fi

only="${1:-}"
passed=0
failed=0
names=""

for path in godot/tests/*_test.gd; do
  name="$(basename "$path" _test.gd)"
  [ -n "$only" ] && [ "$name" != "$only" ] && continue
  out="$("$GODOT" --headless --path godot --script "tests/$name""_test.gd" 2>&1)"
  if [ $? -eq 0 ]; then
    passed=$((passed + 1))
    names="$names $name"
  else
    failed=$((failed + 1))
    echo "=== $name 실패"
    # 고도가 종료할 때 뱉는 누수 경고는 테스트와 무관하다
    echo "$out" | grep -vE 'Leaked|RID allocation|ObjectDB|resources still in use|^$' | tail -20
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "고도 테스트 ${passed}개 전부 통과:$names"
else
  echo "고도 테스트 ${passed}개 통과, ${failed}개 실패"
  exit 1
fi
