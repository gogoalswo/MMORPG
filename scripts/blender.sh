#!/usr/bin/env bash
# 블렌더를 **설치하지 않고** 화면 없이 돌린다 — 고도처럼 쓴다.
#
# 찾는 순서: $BLENDER → ~/blender-bin/blender → PATH. 셋 다 없으면 공식 서버에서
# 휴대용 tar 를 ~/blender-bin 에 풀어 둔다 (380MB 받기 · 풀기, 약 40초. 한 번뿐이다).
# 가상 디스플레이(xvfb)가 있으면 그 위에서 돌린다 — EEVEE 는 GL 없이는 조용히 죽는다.
#
#   npm run blender -- --version
#   npm run blender -- --python scripts/blender/무엇.py -- 인자들
#   npm run blender -- 파일.blend --python-expr "import bpy; print(bpy.data.objects[:])"
set -u
cd "$(dirname "$0")/.."

VERSION=4.5.14   # LTS. 올릴 때는 docs/features/blender.md 도 같이 고친다
DIR="$HOME/blender-bin"

BLENDER="${BLENDER:-}"
# 윈도(Git Bash)에서는 윈도판 zip 을 받는다 — 리눅스판 tar 는 심볼릭 링크를 못 풀어 실패했다 (2026-09-29)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; *) WINDOWS= ;; esac
for candidate in "$BLENDER" "$DIR/blender.exe" "$DIR/blender" "$(command -v blender || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && BLENDER="$candidate" && break
done

if [ -z "$BLENDER" ] || [ ! -x "$BLENDER" ]; then
  echo "블렌더 $VERSION 을 $DIR 에 받는다 (처음 한 번)" >&2
  if [ -n "$WINDOWS" ]; then
    url="https://download.blender.org/release/Blender${VERSION%.*}/blender-$VERSION-windows-x64.zip"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/b.zip" "$url" || { echo "받기 실패: $url" >&2; rm -rf "$tmp"; exit 1; }
    unzip -q "$tmp/b.zip" -d "$tmp" || { echo "풀기 실패" >&2; rm -rf "$tmp"; exit 1; }
    rm -rf "$DIR"
    mv "$tmp/blender-$VERSION-windows-x64" "$DIR"
    rm -rf "$tmp"
    BLENDER="$DIR/blender.exe"
  else
    url="https://download.blender.org/release/Blender${VERSION%.*}/blender-$VERSION-linux-x64.tar.xz"
    tmp="$(mktemp)"
    curl -fsSL -o "$tmp" "$url" || { echo "받기 실패: $url" >&2; rm -f "$tmp"; exit 1; }
    mkdir -p "$DIR"
    tar -xJf "$tmp" -C "$DIR" --strip-components=1 || { echo "풀기 실패" >&2; rm -f "$tmp"; exit 1; }
    rm -f "$tmp"
    BLENDER="$DIR/blender"
  fi
fi

if command -v xvfb-run >/dev/null; then
  exec xvfb-run -a "$BLENDER" --background --factory-startup "$@"
fi
exec "$BLENDER" --background --factory-startup "$@"
