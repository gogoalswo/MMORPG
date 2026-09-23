# 던전

## 무엇

오른쪽 위 **가방 옆 "던전" 단추**로 여는 창. 종류 셋 중 하나를 고르면 그 종류의
**단계 목록**이 나오고, 단계를 고르면 그 던전(존)으로 간다. **던전마다 보스가 한
마리** 서 있다.

2026-09-23 요청: "가방 옆에 던전 버튼 → 세 가지 타입 → 타입을 누르면 단계 선택.
일단 한 가지 타입만 구현. 보스를 각 던전마다 배치."

```
[스킬][가방][던전][설계]  ← 오른쪽 위
          │
          ▼
 ┌ 던전 ─────────────── X ┐      ┌ 토벌 던전 ────────── X ┐
 │ ☆ 토벌 던전            │ ──▶  │ ◎ 뒤로                  │
 │ ◎ 시련의 탑 · 준비 중  │      │ ☆ 1단계 · Lv.9 <보스>   │
 │ ◎ 보물 창고 · 준비 중  │      │ …  20단계 · Lv.199      │
 └────────────────────────┘      └────────────────────────┘
```

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/dungeons.ts` | **표.** `DUNGEON_TYPES`(종류 셋·열림·단계) · `dungeonZones(gate)`(단계마다 존) · `DUNGEON_ZONES` |
| `packages/shared/src/zones.ts` | `ZONES` 에 던전 존을 섞어 넣는다 (문은 `gateFor` 를 넘겨준다) |
| `packages/shared/src/zones.test.ts` | "던전 — 종류 셋, 열린 종류는 단계마다 보스 한 마리" · 차원문 목록 검사에 던전 존 포함 |
| `scripts/export-shared.mjs` | `zones.json` 의 `dungeons` 로 내보낸다 |
| `godot/world/game_data.gd` | `GameData.dungeons()` |
| `godot/game/dungeon_panel.gd` | `DungeonPanel` — **`GatePanel` 을 물려받는다.** `_fill` 만 두 겹(종류 / 단계)으로 바꿨다 |
| `godot/game/gate_panel.gd` | `_add_row` · `_clear_rows` · `_title` — 두 창이 같이 쓴다 |
| `godot/game/game.gd` | `_menu_cells` 셋째 단추 · `_toggle_dungeon` · `_build_gate_panel`(같은 층에 단다) · `_on_gate_pick`(둘 다 `travel`) |
| `godot/tests/ui_test.gd` | `_case_dungeon` — 가방 옆인가 · 3줄 · 막힌 줄 · 21줄 · 뒤로 · 창 폭 · 글자 · 들어가면 보스 한 마리 |

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

### 창은 차원문 창을 물려받는다 ★

틀(`ui_panel`)·줄(`ui_button`)·누름 표시·**끌어서 내리기**·닫기 X 가 차원문 창과
같아야 해서 `DungeonPanel extends GatePanel` 이다 → [portal-ui.md](portal-ui.md).

- 줄은 `_add_row(글자, 키, 막힘, 아이콘)` 으로 단다. 키가 `type:<id>` 면 단계
  목록으로, `back` 이면 종류로 돌아가고, 그 밖은 존 id 라 `picked` 를 낸다.
- **열 때는 늘 종류 셋부터**다. 지난번에 펼친 단계 목록이 남으면 어디인지 헷갈린다.
- 지금 들어와 있는 단계는 흐리게 막는다 (같은 존으로의 `travel` 은 `World` 가 버린다).
- 창 폭은 **680** (`DUNGEON_WIDTH`, 차원문은 520). "20단계 · Lv.199 종말의 사자" 가
  한 줄에 들어가야 한다. 넘치면 줄이 창을 밀어 넓히므로 테스트가 폭을 본다.
- 차원문 창과 **같은 층(layer 10)·같은 자리**라 하나를 열면 다른 하나를 닫는다.
- 고른 뒤는 차원문과 같은 `_on_gate_pick` → `travel`. **있는 존인지 `World` 가 다시 본다.**

### 단추 그림은 아직 없다

`_icon_button("ui_icon_dungeon", "던전", …)` — 그림이 없으면 글자 "던전" 이 나온다.
아이콘을 만들면 [ui-art-style.md](ui-art-style.md) 의 "아이콘류" 프롬프트로 뽑아
`ui_icon_dungeon` 이름으로 넣으면 바로 그림으로 바뀐다.

## 손댈 때

- 종류를 열 때: `DUNGEON_TYPES` 에 단계를 채우고 `open: true` → `npm run export:godot`
  → `npm test` · `npm run test:godot`. `ui_test` 의 "토벌만 열리고" 검사도 같이 고친다.
- 존 개수가 바뀌므로 `godotExport.test.ts` 의 존 수(지금 41 = 마을 1 + 사냥터 20 + 던전 20)도 고친다.
- 보스를 던전 전용으로 세게 만들고 싶으면 몬스터 표(`monsters.ts`)에 종을 따로 만든다 —
  사냥터 보스 수치를 바꾸면 사냥터도 같이 흔들린다.

## 관련

- [portal-ui.md](portal-ui.md) — 물려받은 창의 규칙 (줄 누름·끌기·조각)
- [world-zones.md](world-zones.md) — 존·문·보스 자리
- [monsters-progression.md](monsters-progression.md) — 보스 수치
- [hud.md](hud.md) — 오른쪽 위 메뉴 단추
