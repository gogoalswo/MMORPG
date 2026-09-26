# 던전

## 무엇

오른쪽 위 **가방 옆 "던전" 단추**로 여는 창. 종류 셋 중 하나를 고르면 그 종류의
**단계 목록**이 나오고, 단계를 고르면 그 던전(존)으로 간다. **던전마다 보스가 한
마리** 서 있다.

2026-09-23 요청: "가방 옆에 던전 버튼 → 세 가지 타입 → 타입을 누르면 단계 선택.
일단 한 가지 타입만 구현. 보스를 각 던전마다 배치."

```
[스킬][강화][크리스탈][가방][던전][설계]  ← 오른쪽 위 (강화·크리스탈은 2026-09-24)
          │
          ▼
 ┌ 던전 ──────────────────────── X ┐      ┌ 토벌 던전 ────────── X ┐
 │ ┌──────┐  ┌──────┐  ┌──────┐   │      │ ◎ 뒤로                  │
 │ │ 그림 │  │ 그림 │  │ 그림 │   │ ──▶  │ ☆ 1단계 · Lv.9 <보스>   │
 │ │      │  │(어둡)│  │(어둡)│   │      │ …  20단계 · Lv.199      │
 │ │토벌  │  │시련의│  │보물  │   │      └────────────────────────┘
 │ │20단계│  │준비중│  │준비중│   │
 │ └──────┘  └──────┘  └──────┘   │
 └─────────────────────────────────┘
```

종류는 **세로로 긴 카드 셋을 나란히** 놓는다 (2026-09-23 요청: 세로 네모 셋을 그린
손그림 + "던전 타입별로 나오게 하고 이미지를 넣어"). 처음엔 줄 셋이었다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/dungeons.ts` | **표.** `DUNGEON_TYPES`(종류 셋·열림·단계) · `dungeonZones(gate)`(단계마다 존) · `DUNGEON_ZONES` |
| `packages/shared/src/zones.ts` | `ZONES` 에 던전 존을 섞어 넣는다 (문은 `gateFor` 를 넘겨준다) |
| `packages/shared/src/zones.test.ts` | "던전 — 종류 셋, 열린 종류는 단계마다 보스 한 마리" · 차원문 목록 검사에 던전 존 포함 |
| `scripts/export-shared.mjs` | `zones.json` 의 `dungeons` 로 내보낸다 |
| `godot/world/game_data.gd` | `GameData.dungeons()` |
| `godot/game/dungeon_panel.gd` | `DungeonPanel` — **`GatePanel` 을 물려받는다.** 종류는 `_add_card`(카드 줄 `_cards`), 단계는 물려받은 줄(`_scroll`). 둘이 같은 자리를 번갈아 쓴다 |
| `godot/game/gate_panel.gd` | `_add_row` · `_clear_rows` · `_title` — 두 창이 같이 쓴다 |
| `godot/game/game.gd` | `_menu_cells` 셋째 단추 · `_toggle_dungeon` · `_build_gate_panel`(같은 층에 단다) · `_on_gate_pick`(둘 다 `travel`) |
| `public/assets/icons/ui_icon_dungeon.png` | 단추 그림 (구운 결과, 커밋한다). 원본 주소는 `scripts/fetch-assets.sh` |
| `godot/tests/ui_test.gd` | `_case_dungeon` — 가방 옆인가 · 카드 3장(세로로 긴가 · 나란한가 · 그림 · 화면 안) · 막힌 카드 · 21줄 · 뒤로 · 창 폭 · 글자 · 들어가면 보스 한 마리 |

## 규칙

### 종류는 셋, 지금은 토벌 하나만 연다 ★

`open: false` 인 종류는 창에 이름과 "준비 중" 만 보이고 **막힌 줄**이다(눌러도
아무 일 없다). **시련의 탑 · 보물 창고는 자리를 잡아 둔 가칭이다** — 열 때 이름과
규칙을 정한다. 열면 `stages` 를 채우고 `open: true` 로 바꾼다. 테스트가
"열림 ↔ 단계가 있다" 를 같이 본다.

### 단계 하나 = 존 하나 = 보스 한 마리 ★

- **보스는 사냥터 보스를 그대로 쓴다.** N단계 = N번째 사냥터의 보스(`bossIdFor(N-1)`,
  Lv. `N*10-1`). 새 종·새 모델을 만들지 않았다 — "보스를 배치해" 는 배치이지
  새 보스를 지으라는 말이 아니어서다.
- 그래서 **단계 수 = 보스 수 = 20.** 사냥터를 늘리면 단계도 저절로 는다.
- 존 id 는 `raid_01` … `raid_20`, 이름은 "토벌 던전 N단계".
- 맵은 사냥터와 같은 66, 바닥은 어두운 돌길(`cobble`).
- 보스 자리는 **화면 위쪽(북서) 22.6** (`BOSS_SPOT = [-16, -16]`). 카메라가 남동쪽
  45°(`YAW`)에서 보므로 화면 위쪽이 -x·-z 대각선이다. 사냥터 보스(23)와 거리가 비슷해
  **보스 인식 범위(3 + 18 = 21) 밖**이다 — 들어서자마자 달려들지 않는다.
- 잡으면 15분 뒤에 다시 선다(사냥터와 같다). 바로 다시 싸우려면 나갔다가 창으로
  다시 들어온다 — `World.open` 이 존을 열 때마다 몬스터를 새로 세운다.

### 차원문 목록에는 없다

던전 존은 `FIELD_ORDER` 에 넣지 않았다. 차원문 창은 마을 + 사냥터만 보여 준다.
**나오는 길은 차원문이다** — 던전 존에도 다른 존과 같은 자리(동쪽 4)에 문이 있다
(`zones.test.ts` 의 "차원문이 모든 존에 있다").

### 종류 카드 ★

- 창 폭 **920** (`CARDS_WIDTH`) 일 때 카드 한 장이 **약 276 × 505** — 받은 그림처럼
  세로로 길다. 단계 목록으로 넘어가면 680 으로 돌아온다 (`_set_width`).
- 카드 = 단추 조각(`ui_button`) 틀 + 위에 그림(`Art`) + 아래 이름·단계 수("20단계" /
  "준비 중"). 누르면 줄과 같이 금테가 달아오르고 내용이 `ROW_SINK` 만큼 내려앉는다.
- 카드는 **고도 `Button` 이 직접 누름을 받는다** (`pressed`). 줄처럼 끌기와 가를 일이
  없어서다 — 셋이 한 화면에 다 들어가 스크롤하지 않는다.
- 막힌 카드는 내용을 통째로 어둡게(`LOCKED_TINT`) 하고 `disabled` 라 눌리지 않는다.
- **그림은 `icons/dungeon_<종류 id>.png`** (384²) 를 그림 칸 가운데에 폭을 맞춰 앉힌다
  (`KEEP_ASPECT_CENTERED`). 꽉 채우면(cover) 세로로 긴 칸에 맞추느라 좌우가 잘려
  뿔·상자 끝이 날아간다. 그림이 없으면(`sync:godot` 전) `CARD_FALLBACK` 으로 물러선다.

| 카드 | 그림 | 어디서 |
|---|---|---|
| 토벌 던전 | 뿔 달린 오거 보스 머리 | 바르코 (`dungeon_raid`) — 던전 단추와 **다른 그림**이다 (단추는 아트풍) |
| 시련의 탑 | 뾰족 지붕 돌탑 · 횃불 · 아치 문 | 바르코 (`dungeon_trial`) |
| 보물 창고 | 금테 두른 나무 상자 · 자물쇠 · 금화와 보석 | 바르코 (`dungeon_treasure`) |

**실사풍이다** (2026-09-26 요청: "던전 아이콘이랑 안에 이미지 실사 느낌으로 교체해").
그 전에는 아트풍 문서의 아이콘 틀(상아빛 문장)이었고, 탑·상자 둘은 바르코가 끊긴
세션에서 코드(SVG)로 그렸다 — 그 스크립트(`draw-dungeon-art.mjs`)는 이때 지웠다.
**카드 썸네일만 실사다.** ★ 던전 단추(`ui_icon_dungeon`)까지 실사로 갈았다가 "아이콘은
실사로 바꾸지 말고 기존 아이콘이랑 어울리는걸로" 라는 지적을 받고 아트풍 원본으로
되돌렸다. 아이콘은 [ui-art-style.md](ui-art-style.md) 틀, 창 안의 큰 그림은 실사로 나눈다.

- 프롬프트 틀: `Photorealistic <무엇>, … Cinematic dark fantasy game key art,
  hyper-detailed realistic textures, dramatic rim light … fully inside the frame with
  generous empty margin, centered. Isolated on a pure solid black background (#000000),
  no environment, no text, no border, no frame.` — 참고 그림 없이 `nano-banana-pro`, 1:1, 두 장씩.
- **검은 단색 배경**으로 뽑아야 `build-item-icons.mjs` 가 가장자리부터 걷어 창 바탕에
  녹는다. 풍경을 깔면 카드의 세로로 긴 칸에서 네모난 사진 가장자리가 드러난다.
- 걷힌 배경: 보스 54% · 탑 77% · 상자 42%. 단추는 102x128.

다시 굽기: `bash scripts/fetch-assets.sh && node scripts/build-item-icons.mjs`
(크기는 `build-item-icons.mjs` 의 `FRAME_SIZE` 에 384) → `npm run sync:godot`.

### 창은 차원문 창을 물려받는다 ★

틀(`ui_panel`)·줄(`ui_button`)·누름 표시·**끌어서 내리기**·닫기 X 가 차원문 창과
같아야 해서 `DungeonPanel extends GatePanel` 이다 → [portal-ui.md](portal-ui.md).

- 단계 줄은 `_add_row(글자, 키, 막힘, 아이콘)` 으로 단다. 키가 `back` 이면 종류 카드로
  돌아가고, 그 밖은 존 id 라 `picked` 를 낸다. 카드는 `type:<id>` 로 같은 `_on_pick` 에 온다.
- **열 때는 늘 종류 셋부터**다. 지난번에 펼친 단계 목록이 남으면 어디인지 헷갈린다.
- 지금 들어와 있는 단계는 흐리게 막는다 (같은 존으로의 `travel` 은 `World` 가 버린다).
- 창 폭은 **680** (`DUNGEON_WIDTH`, 차원문은 520). "20단계 · Lv.199 종말의 사자" 가
  한 줄에 들어가야 한다. 넘치면 줄이 창을 밀어 넓히므로 테스트가 폭을 본다.
- 차원문 창과 **같은 층(layer 10)·같은 자리**라 하나를 열면 다른 하나를 닫는다.
- 고른 뒤는 차원문과 같은 `_on_gate_pick` → `travel`. **있는 존인지 `World` 가 다시 본다.**

### 단추 그림 — 보스 머리 ★

`ui_icon_dungeon` (2026-09-23). **아트풍 그대로다** — 2026-09-26 에 실사로 갈았다가
다른 아이콘과 결이 달라 되돌렸다 (위 "종류 카드"). [ui-art-style.md](ui-art-style.md) 의 "아이콘류" 틀에
`<무엇>` 만 "뿔 두 개 달린 도깨비(오거) 보스 머리, 정면" 으로 갈고, 이미 올라가 있는
참고 그림을 물려 `nano-banana-pro` 로 두 장 뽑았다.

- **처음엔 문(돌 아치 + 쇠창살)으로 뽑았다가 "문으로 만들지 말고 보스 몬스터 이미지로"
  라는 지적을 받았다.** 던전의 알맹이는 보스라서다. 문 그림은 밀지 않고 버렸다.
- 두 장 중 **위로 솟은 뿔** 쪽을 골랐다 — 옆으로 말린 양뿔은 가로로 넓어 작은 칸에서
  얼굴이 작아진다.
- 배경은 가장자리에서 번져 들어가는 것만 걷힌다(54%). 굽은 크기는 107x128.
- 주소는 `fetch-assets.sh`, 굽는 것은 `build-item-icons.mjs`(기본 128), 옮기는 것은
  `sync-godot-assets.mjs` 의 `ICONS`. 그림이 없으면 글자 "던전" 으로 물러선다.

## 손댈 때

- 종류를 열 때: `DUNGEON_TYPES` 에 단계를 채우고 `open: true` → `npm run export:godot`
  → `npm test` · `npm run test:godot`. `ui_test` 의 "토벌만 열리고" 검사도 같이 고친다.
- 존 개수가 바뀌므로 `godotExport.test.ts` 의 존 수(지금 45 = 마을 1 + 사냥터 20 + 던전 20 + 전직 시험 4)도 고친다.
- 보스를 던전 전용으로 세게 만들고 싶으면 몬스터 표(`monsters.ts`)에 종을 따로 만든다 —
  사냥터 보스 수치를 바꾸면 사냥터도 같이 흔들린다.

## 관련

- [portal-ui.md](portal-ui.md) — 물려받은 창의 규칙 (줄 누름·끌기·조각)
- [world-zones.md](world-zones.md) — 존·문·보스 자리
- [monsters-progression.md](monsters-progression.md) — 보스 수치
- [hud.md](hud.md) — 오른쪽 위 메뉴 단추
