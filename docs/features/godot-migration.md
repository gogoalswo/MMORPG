# 고도(Godot) 이관

## 무엇

three.js 웹 클라이언트를 **고도 엔진으로 갈아타는 중**이다. 목적은 **모바일 앱**이다.

작업은 `godot/` 안에서만 한다. 기존 `packages/client` 는 고도 쪽이 따라잡을 때까지
그대로 둔다 — 중간에 그만두기로 해도 `godot/` 만 지우면 원래대로다.

## 어디

| 파일 | 역할 |
|---|---|
| `godot/project.godot` | 프로젝트 설정. 렌더러는 `mobile`, 주 화면은 `main.tscn` |
| `godot/main.tscn` | 시작 화면. `game/game.gd` 하나를 달고 나머지는 코드가 짓는다 |
| `godot/world/world.gd` | **판정.** `ZoneRoom.ts` 의 자리다. 네트워크 얘기가 없다 |
| `godot/world/movement.gd` | `shared/movement.ts` 이식본. TS 와 값이 같아야 한다 |
| `godot/world/combat.gd` | `shared/combat.ts` 이식본 — 피해·치명타·경직·경험치. **수치는 `data/combat.json` 에서 읽는다** |
| `godot/world/game_data.gd` | `data/*.json` 로더 |
| `godot/net/transport.gd` | 화면과 판정 사이의 유일한 통로 |
| `godot/net/local_transport.gd` | 서버 없이 `World` 를 이 자리에서 돌린다 |
| `godot/game/game.gd` | 화면. 바닥·카메라·모델·터치 이동. **`World` 를 직접 안 만진다** |
| `godot/game/rig.gd` | `.glb` 하나를 씌우고 클립을 트는 껍데기. **없으면 `null`** |
| `scripts/sync-godot-assets.mjs` | `public/assets` → `godot/assets` 복사. 모델은 텍스처를 줄여 넣는다 (`npm run sync:godot`) |
| `scripts/shrink-glb-textures.mjs` | `.glb` 안 텍스처를 512px 로 줄인다 |
| `scripts/build-korean-font.py` | 한글 폰트를 완성형 2350자로 줄인다. 결과물은 커밋한다 |
| `godot/tests/*.gd` | 헤드리스 검사 — 이동 공식·World·터치 이동·몬스터 |
| `godot/export_presets.cfg` | 안드로이드·웹 익스포트 설정. **비밀은 없다** — 아래 "서명" 참고 |
| `.github/workflows/android.yml` | push 하면 APK 를 구워 Actions 산출물로 올린다 |
| `.github/workflows/pages.yml` | 같은 사이트의 **`/game/`** 아래에 웹 빌드를 같이 올린다 (웹 클라이언트는 `/` 그대로) |
| `scripts/export-shared.mjs` | `packages/shared` 의 표를 `godot/data/*.json` 으로 내보낸다 (`npm run export:godot`) |
| `godot/data/*.json` | 내보낸 결과. **손으로 고치지 않는다** — 고치면 테스트가 잡는다 |
| `packages/shared/src/godotExport.test.ts` | 위 JSON 이 TS 표와 같은지 전수 검사 |

## 규칙

### 왜 서버까지 고도로 가나 ★

처음에는 "클라만 고도, 서버는 Node Colyseus 유지" 를 생각했다. **취소했다.**

순서를 **로컬 게임 먼저, 서버 나중**으로 잡았기 때문이다. 로컬 판정을 GDScript 로
써 놓고 서버는 TS `ZoneRoom` 을 쓰면 **판정이 두 언어로 두 벌**이 된다. 수치 하나를
고칠 때마다 두 군데를 고쳐야 하고, 어긋나면 "로컬에선 잡히는데 서버에선 안 잡힌다"
가 된다. 이 저장소가 제일 경계하는 것이다 (CLAUDE.md, `docs/features/README.md`).

그래서 **판정은 GDScript 한 벌**이고, 나중에 붙일 서버는 **고도 헤드리스**다.
로컬 게임을 만드는 일이 곧 서버 코드를 만드는 일이 된다.

### `shared` 를 둘로 가른다 ★

`packages/shared` 4,545줄을 전부 이식하지 않는다.

| | 무엇 | 어떻게 |
|---|---|---|
| **생성기** | `items.ts` `skills.ts` `monsters.ts` `zones.ts` `beasts.ts` `zone.ts` (약 2,140줄) | **TS 에 그대로 둔다.** 아이템 280·스킬 34·몬스터 60·존 21 을 JSON 으로 내보내고 고도는 결과만 읽는다 |
| **런타임 공식** | `combat.ts` `movement.ts` `spatialGrid.ts` `autoHunt.ts` `character.ts` `constants.ts` (약 830줄) | **GDScript 로 이식.** 피해 공식·정면 판정·경직·경험치 곡선·격자 |

이렇게 가르면 `*.test.ts` 1,559줄(데이터 전수 검사)이 **그대로 살아 있다.** 생성기가
TS 에 남으니 표가 어긋나면 `npm test` 가 잡는다. 전부 GDScript 로 옮겼으면 이 그물이
통째로 없어진다.

내보낸 JSON 이 낡는 것도 `godotExport.test.ts` 가 막는다 — 수치를 고치고 내보내기를
잊으면 **웹과 고도가 조용히 다른 게임이 된다.** 깨지면 `npm run export:godot` 을 돌린다.

**아이템은 내보내지 않는다.** 나중에 다시 만들기로 했다 (2026-09-16). `items.ts` 는
웹 클라이언트가 아직 쓰고 있어서 지우지 않았다. 다시 만들 때 `export-shared.mjs` 에
줄을 더하면 된다.

`JOB_STATS` 는 이 일로 `combat.ts` 에서 `export` 만 붙였다. 값도 자리도 그대로다.

### `World` 를 클라이언트가 직접 만지지 않는다 ★

판정은 `World` 노드 한 곳에 몰고, **네트워크 얘기는 한 줄도 넣지 않는다.**
"입력 받음 → 판정 → 이벤트 뱉음" 만 한다. 그 앞에 `Transport` 를 두고, 로컬은
`World` 를 직접 부르고 나중에 서버용 구현을 하나 더 끼운다.

지금 웹 클라의 `net/transport.ts` `RoomLike` 와 같은 모양이다
([local-mode.md](local-mode.md)).

**이 규칙을 어기면 "로컬 먼저" 가 나중에 전면 재작성으로 돌아온다.** 화면 코드가
`World` 내부 상태를 직접 읽기 시작하면, 서버를 붙일 때 그 자리가 전부 터진다.

### 엔진은 저장소에 넣지 않는다

고도 바이너리는 140MB 이고 플랫폼마다 다르다. `node_modules` 와 같은 취급이다.

- **개발 세션** — claude.ai 클라우드 환경의 Setup script 가 설치한다. 첫 세션에서
  한 번 돌고 파일시스템 스냅샷이 떠지므로 그 뒤로는 0초다 (약 7일마다 다시 빌드).
- **CI** — `android.yml` 이 받아서 캐시한다. 첫 빌드만 느리다.
- **손으로** — `curl -fsSL -o /tmp/godot.zip "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=linux.x86_64.zip&platform=linux.64"`

버전은 **4.7.2** 로 맞춘다. 올릴 때는 `project.godot` 의 `config/features`,
`android.yml` 의 `GODOT_VERSION`, 이 문서를 같이 고친다.

### 서명

`export_presets.cfg` 는 커밋한다. 대신 **비밀은 넣지 않는다** — 디버그 키스토어
경로와 비밀번호는 CI 가 `~/.config/godot/editor_settings-4.tres` 로 넣는다.
스토어에 낼 릴리스 키는 GitHub Secrets 로 간다 (아직 안 만들었다).

### 에셋은 복사해 쓰고 커밋하지 않는다 ★

고도는 프로젝트 폴더(`res://`) 밖의 파일을 임포트하지 못한다. 그렇다고 같은 GLB 를
저장소에 두 벌 두면 24MB 가 이력에 두 번 쌓이므로, **`godot/assets/` 는 커밋하지 않고
`npm run sync:godot` 으로 만든다** (`fetch-assets.sh` 와 같은 방식).

**쓰는 것만 복사한다.** 웹 빌드는 `godot/assets/` 를 통째로 담는다. 직업이 늘면
`sync-godot-assets.mjs` 의 `MODELS` 에 줄을 더한다.

### 텍스처를 512px 로 줄여서 넣는다 ★

varco 모델은 1024² 텍스처를 셋씩 들고 있는데, 고도가 임포트하면서 데스크톱·모바일
두 포맷으로 구워 **원본 1MB 가 10MB 로 불어난다.** 폰 화면에서 512 와 1024 는 거의
구분되지 않으므로 `sync-godot-assets.mjs` 가 줄여서 넣는다 —
**`index.pck` 12.96MB → 5.58MB.**

고도 설정으로 줄이려던 시도는 둘 다 실패했다 (2026-09-17). 다시 하지 말 것:

| 시도 | 결과 |
|---|---|
| `gltf/embedded_image_handling=2` (Basis Universal) | pck 13MB → **21.8MB**. 더 커졌다 |
| 익스포트 프리셋 `vram_texture_compression/for_desktop=false` | 변화 없음 |

원본을 줄이는 쪽이 고도를 판올림해도 안 깨진다. `model_test.gd` 가 텍스처가 512 를
넘으면 잡는다 — 안 그러면 조용히 13MB 로 돌아간다.

### 모델이 없으면 기둥으로 그린다 ★

`Rig.create` 는 파일이 없으면 **`null` 을 준다.** 화면은 그때 캡슐을 대신 그린다.
`npm run sync:godot` 을 안 돌린 사람도 게임은 돌아가야 하기 때문이고, 애초에 파일이
있는 `look` 이 둘뿐이다 — 보스(`trex`)를 비롯한 나머지는 웹 클라이언트에서도
절차적 리그다 → [characters-and-animation.md](characters-and-animation.md).

초원 81마리 중 **모델 80 · 기둥 1**(보스)이 이 규칙의 결과다.

### 얼마나 크게 그릴지는 데이터가 정한다

모델은 **높이 1 로 정규화돼** 나온다. 사람은 `Rig.HUMAN_HEIGHT`(1.8), 짐승은
`monsters.json` 의 `heights` × `kind.scale` 이다. 이 표를 쓰려고 `beasts.ts` 의
`BEAST_HEIGHT` 에 `export` 를 붙여 내보내기에 넣었다 (값은 그대로).
초원 들늑대 2.2 × 1.01 = **2.22m**.

### 공격 클립 구간은 아직 안 맞췄다

기사 `Attack` 은 5.07초짜리라 통째로 틀면 한 번 휘두르는 데 5초가 걸린다. 웹
클라이언트는 0.8~1.60초만 1.6배로 트는데(`modelRig` 의 `ATTACK_CLIPS`), 여기서도
같은 자리에서 시작하기만 했다. **발이 미끄러지거나 동작이 어긋나면 그때 재서 고친다.**

### 죽으면 저절로 살아나지 않는다 ★

체력이 0 이 되면 `dead` 로 두고 **가만히 둔다.** 사람이 화면을 눌러야 마을에서
되살아난다 (`World.revive`). 예전 웹 클라에서 5초 뒤 제자리에서 일으켜 세웠더니
**죽은 걸 읽기도 전에 화면이 사라져서 죽은 줄도 몰랐다** → `ZoneRoom` 의 같은 주석.

죽어 있는 동안 이동 입력은 **순번만 갱신하고 위치는 안 옮긴다.** 안 갱신하면
나중에 서버를 붙였을 때 클라이언트 보정이 그 구간 내내 멈춘다.

### 몬스터는 `World.make_monster` 하나로만 만든다 ★

스폰과 테스트가 **같은 함수**를 쓴다. 테스트가 시험용 몬스터를 손으로 만들었더니
`World` 에 칸을 더할 때마다 조용히 어긋났다 — 범위 공격을 넣으면서 `burst_at` 이
없어 어그로 테스트 4개가 한꺼번에 깨졌다 (2026-09-17). 겸사겸사 테스트가 **진짜
몬스터 수치**(들늑대 공격 9, 보스 25)를 쓰게 됐다.

### 예고한 원은 그 자리에 고정된다 ★

보스가 범위 공격을 걸면 **그 자리에 서고, 원은 시전을 시작한 자리에 박힌다.**
보스를 따라 움직이면 표시와 터지는 자리가 어긋나 붙어 있는 쪽은 피할 방법이 없다.
한번 예고한 것은 대상이 도망가든 죽든 그대로 터진다 — 리쉬·대상 재탐색보다 먼저
보는 이유도 같다.

터질 때 **원으로 다시 자른다.** 화면에 그린 테두리 밖에 서 있는데 맞으면 안 된다.

수치는 보스 20종이 전부 같다 (`BOSS_AOE` — 반지름 7 · 예고 1.6초 · 쿨타임 9초 ·
평타의 2.2배). 종마다 다르면 어느 보스에서 몇 초 만에 피해야 하는지 외울 수가 없다.

### 대상은 서버가 고른다 ★

클라이언트가 "이놈을 쳐라" 하고 **대상 id 를 보내게 하면 사거리 밖이나 벽 너머의
적을 지정할 수 있다.** 그래서 화면이 보내는 건 `attack` 한 줄뿐이고, 누구를 맞출지는
`World._pick_target` 이 정한다 — 정면 부채꼴(`attackArc`) 안에서 가장 가까운 하나다.

**무리가 빽빽하면 "노린 놈"보다 가까운 놈이 맞는다.** 이건 판정이 맞는 것이다
(초원에서 실제로 그랬다). 그래서 전투 테스트는 사냥터 배치에 기대지 않고 마을에
시험용 한 마리만 놓고 본다.

### 차원문은 알리기만 한다 ★

`World._check_gate` 는 문 안에 서면 **`gate` 이벤트를 한 번 보낼 뿐**이고, 어디로
갈지는 사람이 고른다 (마을 + 사냥터 20곳, 순서는 `zones.json` 의 `fieldOrder`).
고른 곳은 `travel` 로 요청하고 **있는 존인지 `World` 가 다시 본다.**

매 프레임 알리면 화면이 깜빡이므로 문을 벗어날 때까지 한 번만 알린다
(`player.at_gate`).

### 몬스터 자리는 판정하는 쪽이 정한다

`World._spawn_monsters` 가 존 이름으로 난수 씨앗을 고정한다. 같은 존이면 언제나
같은 자리다 — 나중에 서버를 붙여도 자리를 정하는 건 서버 한 곳이어야 하고,
지금 테스트도 이것에 기댄다.

무리를 흩을 때 `scatter_spawn` 이 몸 반지름에 `MONSTER_GAP`(0.2)을 더해 자리를
고른다. 초원 81마리 중 **가장 가까운 둘 사이 여유가 0.213m** 로, 겹친 놈이 없다.

### 아직 예측·보정이 없다

화면은 `Transport` 가 준 상태를 **그대로 그린다.** 로컬이라 지연이 0 이라서
매끄럽다. 서버를 붙이는 단계에서 `networking-state.md` 의 예측·보정을 넣는다.
그때 손댈 자리는 `game.gd` 의 `_draw_state` 하나다.

### 한글 폰트 ★

고도 기본 폰트에 한글 글리프가 없어 그냥 쓰면 **네모로 나온다.** Noto Sans KR 을
**완성형(KS X 1001) 2350자 + ASCII 로 줄여**(5.9MB → 436KB) 테마의 기본 폰트로 깐다
→ [ASSETS.md](../ASSETS.md#한글-폰트--noto-sans-kr-sil-ofl-11).

줄인 이유는 웹 빌드가 이미 51MB 라서다. 2350자면 현대 한국어는 사실상 전부
나온다 — 존 21곳·몬스터 60종 이름에 빠진 글자가 없는 것을 `ui_test.gd` 가 본다.

## 확인

**화면 확인은 브라우저나 폰의 APK 로 한다.** `--headless` 는 더미 렌더러라
화면을 못 그린다.

| 어디 | 무엇 |
|---|---|
| 이동 공식이 TS 와 같은가 | `godot --headless --path godot --script tests/movement_test.gd` |
| World 와 Transport | `... tests/world_test.gd` |
| 눌러서 걸어가기 | `... tests/touch_test.gd` |
| 몬스터 스폰·충돌·차원문 | `... tests/monster_test.gd` |
| 전투 공식과 실제 전투 | `... tests/combat_test.gd` |
| 어그로·추적·반격·사망·부활 | `... tests/aggro_test.gd` |
| 모델·클립·기둥 대체 | `... tests/model_test.gd` |
| 한글 폰트·체력바·사냥터 고르기 | `... tests/ui_test.gd` |
| 보스 범위 공격 (실제 시간 1.8초를 기다린다) | `... tests/aoe_test.gd` |

아홉 다 `pages.yml` 이 배포 전에 돌린다. 하나라도 깨지면 배포까지 가지 않는다.

기준값은 `movement.ts` 를 node 로 직접 돌려 뽑았다 (2026-09-16). 두 쪽이 갈라지면
나중에 서버를 붙였을 때 매 틱 보정이 튄다.

| 어디 | 주소 |
|---|---|
| 브라우저 | `https://gogoalswo.github.io/MMORPG/game/` — 39MB 받는다. 폰 브라우저에서도 열린다 |
| 안드로이드 | Actions → `Android APK` 실행 → 산출물 `mmorpg-apk` |

**웹 빌드는 스레드를 꺼야 한다.** 스레드를 켜면 `SharedArrayBuffer` 가 필요하고,
그러려면 서버가 COOP/COEP 응답 헤더를 보내야 하는데 **GitHub Pages 는 헤더를
못 넣는다.** 켠 채로 올리면 흰 화면만 나온다 → `godot/export_presets.cfg` 의
`variant/thread_support=false`.

로직 확인은 글로 한다 — 웹 쪽 `npm run probe` 와 같은 자리다
([verification.md](verification.md)).

```bash
godot --headless --path godot --import          # 에셋 임포트
godot --headless --path godot --script check.gd # 상태를 글로 찍는다
```

## 단계

1. ~~**골격** — 프로젝트·임시 화면·APK 워크플로우~~ 끝 (2026-09-16)
2. ~~**데이터 내보내기** — `scripts/export-shared.mjs` + 대조 테스트~~ 끝 (2026-09-16)
3. ~~**`World` 와 걸어다니기** — 판정·Transport·마을 한 곳·터치 이동~~ 끝 (2026-09-16)
4. ~~**몬스터** — 스폰·충돌·표시, 임시 차원문~~ 끝 (2026-09-17)
5. ~~**전투** — 공격·피해·사망·경험치, 되살아나기~~ 끝 (2026-09-17)
6. ~~**몬스터 반격** — 어그로·추적·공격, 사망·부활~~ 끝 (2026-09-17)
7. ~~**모델 붙이기** — `varco_*.glb`, 클립, 기둥 대체~~ 끝 (2026-09-17)
8. ~~**UI** — 한글 폰트, 체력바, 사냥터 고르는 화면~~ 끝 (2026-09-17)
9. ~~**보스 범위 공격** — 예고 원, 고정된 자리, 원 밖은 안 맞음~~ 끝 (2026-09-17)
10. **남은 것** ← 지금 여기. 스킬 34종, 아이템·인벤토리(다시 만들기로 한 것),
    NPC·상점·대장간, 저장(`user://`), 그다음 서버

## 용량

폰이 받는 양이다. GitHub Pages 가 gzip 으로 보내므로 파일 크기와 다르다.

| | 파일 | 받는 양 |
|---|---|---|
| `index.wasm` (고도 엔진) | 37.7MB | **10.2MB** — 만드는 것과 무관하게 고정 |
| `index.pck` (게임) | 5.6MB | 5.5MB (이미 압축된 텍스처라 gzip 이 안 먹는다) |

**엔진은 배포할 때마다 다시 받는다.** 내용이 한 글자도 안 바뀌어도 그렇다 —
GitHub Pages 가 배포 시각을 ETag 에 넣기 때문이다 (`6aab3f31-25af282` →
`6aab4267-25af282`, 뒤쪽 크기는 같다). 헤더를 우리가 못 고치므로 웹에서는 방법이
없다. **APK 는 엔진이 앱 안에 있어서 이 문제가 없다** — 원래 목적이 모바일 앱이고
웹은 확인용이라는 점을 기억할 것.

캐시는 `max-age=600` 이라 **10분이면 저절로 풀린다.** 그 안에 확인하려면 강력
새로고침을 한다. 파일명에 해시를 붙이는 방법도 있지만, 고도 로더가 `index.html`
설정에서 `index.wasm`·`index.pck` 이름을 만들어 내므로 판올림 때 깨지기 쉽다 —
얻는 게 "10분을 0분으로" 라 하지 않았다.
5. **모델·애니메이션** — `varco_*.glb` (아래 참고)
6. **전투 표현 → UI → 이펙트**
7. **서버** — 고도 헤드리스. `Transport` 에 구현을 하나 더 끼운다

## 손댈 때

- 에셋은 이미 커밋돼 있다 — `public/assets/models/varco_*.glb` 9개(24MB)와 텍스처.
  `fetch-assets.sh` 를 다시 돌릴 필요 없다.
- **`varco_knight.glb` 는 고도에서 23본, 클립 이름이 그대로 나온다** (`Idle` 8.97초 ·
  `Run` 0.70초 · `Attack` 5.07초 · `Attack_Heavy` 31.97초 · `Attack_Spin` 5.07초 ·
  `Death` 2.03초). three.js 쪽 문서에 적힌 "이름이 비어 있다" 는 고도에는 해당하지
  않는다 → [characters-and-animation.md](characters-and-animation.md).
- `public/assets/textures/*.ktx2` 는 고도가 그대로 못 읽을 수 있다. 원본에서 다시
  구워야 한다 → [world-zones.md](world-zones.md).
- 익스포트 템플릿(약 1GB)과 안드로이드 SDK 는 **CI 에만** 둔다. 개발 세션 Setup
  script 는 5분 제한이 있다.

## 관련

- [local-mode.md](local-mode.md) — 지금의 로컬 모드. 고도로 가면 이 방식(브라우저가
  TS `ZoneRoom` 을 그대로 돌림)은 쓸 수 없다. 고도는 TS 를 실행할 수단이 없다
- [networking-state.md](networking-state.md) — 메시지 목록. `Transport` 가 나를 대신할 자리
- [combat.md](combat.md) — 이식할 런타임 공식이 있는 곳
- [verification.md](verification.md) — 글로 확인하는 방식
