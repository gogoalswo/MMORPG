#!/usr/bin/env bash
# 이펙트를 **눈으로 보려고** 게임 화면을 뽑는다 (`godot/tools/shot.gd`).
#
# 고도는 `--headless` 로는 아무것도 그리지 않는다. 그래서 가상 디스플레이
# (`xvfb`)에 띄우고 **Compatibility(OpenGL)** 로 굽는다 — 웹 익스포트와 같은
# 렌더러라 화면에서 보이는 것과 같다. Vulkan(mobile)은 소프트웨어 GL 에서 안 뜬다.
#
#   npm run shot:godot                  낙뢰
#   npm run shot:godot -- rising_kick    스킬 id 를 주면 그것
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
if ! command -v xvfb-run >/dev/null; then
  echo "xvfb-run 이 없다 — 화면 없는 곳에서 그리려면 필요하다 (apt install xvfb)"
  exit 1
fi

mkdir -p logs
rm -f logs/shot_*.png
xvfb-run -a "$GODOT" --path godot --rendering-driver opengl3 --resolution 1280x720 \
  --script tools/shot.gd -- "${1:-}" "${2:-}" 2>&1 |
  grep -vE 'Leaked|ObjectDB|RID|ALSA|audio|^$|Godot Engine|WARNING:|ERROR: Condition'
