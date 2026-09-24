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

# **클래스 캐시가 낡았으면 먼저 임포트한다** ★ (2026-09-24). 다른 세션이 `class_name` 을
# 새로 넣은 것(`DragScroll`)을 받으면 캐시(`godot/.godot`)가 그 이름을 몰라 `game.gd` 가
# 파스 에러를 낸다. CI 는 늘 `--import` 부터 해서 안 걸리고, 로컬만 걸렸다.
# 스크립트가 캐시보다 새로울 때만 한다 — 바뀐 게 없으면 8초를 안 쓴다
cache="godot/.godot/global_script_class_cache.cfg"
if [ ! -f "$cache" ] || [ -n "$(find godot -name '*.gd' -newer "$cache" -not -path 'godot/.godot/*' -print -quit)" ]; then
  "$GODOT" --headless --path godot --import >/dev/null 2>&1
  touch "$cache"
fi

# **테스트 하나에 시간 제한을 건다** ★ (2026-09-24). 스크립트 에러가 나면 `quit()` 에
# 닿지 못해 고도가 **끝나지 않고 기다린다** — 낡은 캐시로 camera·chat_log 가 20분 넘게
# 멈춰 전체가 안 끝났다. 가장 긴 것이 9초(lightning_fx)라 넉넉히 잡았다
limit="${GODOT_TEST_TIMEOUT:-120}"
run_one() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$limit" "$@"
  else
    "$@"
  fi
}

only="${1:-}"
passed=0
failed=0
names=""

for path in godot/tests/*_test.gd; do
  name="$(basename "$path" _test.gd)"
  [ -n "$only" ] && [ "$name" != "$only" ] && continue
  out="$(run_one "$GODOT" --headless --path godot --script "tests/$name""_test.gd" 2>&1)"
  code=$?
  if [ $code -eq 124 ]; then
    out="$out
  실패 ${limit}초 안에 안 끝났다 — 스크립트 에러로 quit() 을 못 불렀을 수 있다 (위 SCRIPT ERROR 를 본다)"
  fi
  if [ $code -eq 0 ]; then
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
