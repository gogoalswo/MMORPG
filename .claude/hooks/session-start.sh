#!/bin/bash
# 클라우드 세션이 열릴 때 고도 테스트 준비를 끝내 둔다 (2026-10-02).
#
# 새 컨테이너에는 node_modules · godot/assets · 임포트 캐시(godot/.godot)가 없다.
# 그대로 병합 직전에 `npm run test:godot` 을 돌리면 에셋을 못 찾아 깨졌다.
# 테스트 스크립트도 스스로 갖추지만(scripts/godot-test.sh), 여기서 미리 해 두면
# 첫 테스트가 몇 분 빨라진다. 컨테이너 상태가 훅 뒤에 캐시되므로 `npm install` 을 쓴다.
# 내 PC 에서는 돌지 않는다 — 원격(CLAUDE_CODE_REMOTE)에서만.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

npm install --no-audit --no-fund --silent
node scripts/sync-godot-assets.mjs --quiet

# 고도가 없는 환경이면 임포트는 건너뛴다 — 테스트 스크립트가 찾을 때 알려 준다
GODOT="$(command -v godot || true)"
[ -z "$GODOT" ] && [ -x "$HOME/godot-bin/godot" ] && GODOT="$HOME/godot-bin/godot"
if [ -n "$GODOT" ]; then
  "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
  touch godot/.godot/global_script_class_cache.cfg
fi
