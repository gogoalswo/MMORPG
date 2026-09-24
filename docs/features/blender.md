# 블렌더 (설치 없이 쓰기)

블렌더를 PC 에 깔지 않고, 클라우드 세션에서 **화면 없이(`--background`)** 돌린다.
고도를 쓰는 방식과 같다 — 엔진은 저장소에 넣지 않고, 필요한 곳에서 받아 둔다.

**언제 쓰나 — 사용자가 애니메이션을 만들어 달라고 할 때만.** ★ (2026-09-23 지시.)
GLB 정리·아이콘 렌더처럼 블렌더로 될 것 같은 일이라도 먼저 꺼내지 않는다.

## 어디에 있나

| 파일 | 역할 |
|---|---|
| `scripts/blender.sh` | 블렌더를 찾고, 없으면 받아 두고, 가상 디스플레이 위에서 돌린다 |
| `package.json` 의 `blender` | `npm run blender -- <블렌더 인자>` |
| `~/blender-bin/` | 받은 휴대용 블렌더 (저장소 밖, 1.2GB) |
| `scripts/blender/fighter_moves.py` | **격투가 평타·스킬 동작 6개** — 손발 목표점 + 2본 IK 로 키를 짓는다 → [characters-and-animation.md](characters-and-animation.md) 의 "블렌더 동작" |

## 쓰는 법

```bash
npm run blender -- --version
npm run blender -- --python scripts/blender/무엇.py -- 인자들     # 파이썬 스크립트
npm run blender -- --python-expr "import bpy; print(bpy.app.version_string)"
```

`--background --factory-startup` 은 스크립트가 붙인다. 스크립트 안에서
`sys.argv[sys.argv.index("--") + 1:]` 로 뒤쪽 인자를 받는다.
블렌더용 파이썬 스크립트는 `scripts/blender/` 에 둔다.

확인한 것 (2026-09-23, 4.5.14):
- GLB 읽기(`import_scene.gltf`) · 쓰기(`export_scene.gltf`) — 된다
- Cycles(CPU) 렌더 — 화면 없이 된다
- EEVEE 렌더 — **가상 디스플레이(`xvfb-run`)에서만** 된다. 없으면 에러 없이 죽는다.
  그래서 `xvfb-run` 이 있으면 늘 그 위에서 돌린다.

### 바르코 캐릭터에 동작 더하기 (2026-09-24)
- GLB 는 `bone_heuristic="BLENDER"` 로 들인다 — 뼈 축이 glTF 노드 축 그대로라 내보내도
  기본 자세가 원본과 같다. 그래서 **뼈대+클립만** 내보내고(`use_selection` 으로 아마추어만,
  `export_skins=False`) `scripts/add-clips.mjs` 가 뼈 이름으로 캐릭터 GLB 에 붙인다.
  메시·텍스처를 블렌더로 다시 쓰지 않는다.
- 키마다 보간이 섞여 있으면 내보낼 때 "Baking animation" 경고가 뼈마다 뜬다. 일부러 섞은
  것(부딪히기 전 LINEAR · 뒤 BEZIER)이라 무시한다.

## 설치는 어떻게 되나

찾는 순서는 `$BLENDER` → `~/blender-bin/blender` → `PATH`. 셋 다 없으면
`download.blender.org` 에서 휴대용 tar(380MB)를 `~/blender-bin` 에 푼다.
**처음 한 번 약 30초**이고, 그 세션에서는 다시 받지 않는다.

클라우드 세션은 컨테이너가 매번 새로 뜨므로 세션마다 한 번씩 받는다. 매번 0초로 하려면
환경 설정의 **Setup script** 에 아래 줄을 넣는다 (고도도 그렇게 깔려 있다).
Setup script 는 첫 세션에서 한 번 돌고 스냅샷으로 남는다.

```bash
mkdir -p ~/blender-bin && curl -fsSL https://download.blender.org/release/Blender4.5/blender-4.5.14-linux-x64.tar.xz | tar -xJ -C ~/blender-bin --strip-components=1
```

## 왜 이렇게 했나

- **버전은 LTS(4.5.14) 로 고정한다.** 5.x 가 더 새것이지만 LTS 는 2년 동안 고치기만
  하고 API 를 바꾸지 않는다 — 스크립트가 세션마다 같은 결과를 내야 한다.
  올릴 때는 `scripts/blender.sh` 의 `VERSION` 과 위 Setup script 줄을 같이 고친다.
- **저장소에 넣지 않는다.** 풀면 1.2GB 이고 플랫폼마다 다르다. `node_modules` 와 같은 취급.
- **`--factory-startup`** — 개인 설정·애드온이 결과를 바꾸지 않게 한다.

## 관련 문서

- [godot-migration.md](godot-migration.md) — 고도를 같은 방식으로 받는 법 ("엔진은 저장소에 넣지 않는다")
- [verification.md](verification.md) — 확인하는 방법
