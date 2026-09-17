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
| `godot/game/game.gd` | 화면. 바닥·카메라·캡슐·터치 이동. **`World` 를 직접 안 만진다** |
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

### 대상은 서버가 고른다 ★

클라이언트가 "이놈을 쳐라" 하고 **대상 id 를 보내게 하면 사거리 밖이나 벽 너머의
적을 지정할 수 있다.** 그래서 화면이 보내는 건 `attack` 한 줄뿐이고, 누구를 맞출지는
`World._pick_target` 이 정한다 — 정면 부채꼴(`attackArc`) 안에서 가장 가까운 하나다.

**무리가 빽빽하면 "노린 놈"보다 가까운 놈이 맞는다.** 이건 판정이 맞는 것이다
(초원에서 실제로 그랬다). 그래서 전투 테스트는 사냥터 배치에 기대지 않고 마을에
시험용 한 마리만 놓고 본다.

### 차원문은 임시다 ★

진짜 게임은 차원문에서 **사냥터 20곳을 골라** 가게 되어 있다 (웹 클라의
`ui/zoneGate.ts`). 고르는 화면이 아직 없어서, 지금은 `World._check_gate` 가
**마을 ↔ 첫 사냥터(초원)** 만 오간다. 마을에는 몬스터 정의가 없어서 사냥터로
가야 몬스터가 보이기 때문에 넣은 것이다. UI 단계에서 고르는 화면으로 바꾼다.

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

### 한글 폰트가 없다

고도 기본 폰트에 한글 글리프가 없다. 한글을 넣으면 **폰에서 네모로 나온다.**
UI 를 만들기 전에 폰트 리소스를 먼저 붙여야 한다. `game.gd` 의 글자가 ASCII 만
쓰는 이유이고, 화면에 존 이름("마을") 대신 id(`village`)를 찍는 이유다.

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

다섯 다 `pages.yml` 이 배포 전에 돌린다. 하나라도 깨지면 배포까지 가지 않는다.

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
6. **몬스터 반격** ← 지금 여기. 어그로·추적·공격, 캐릭터 사망
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
