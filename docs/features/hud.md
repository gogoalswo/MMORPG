# 메인 HUD

## 무엇

게임 화면 위에 늘 떠 있는 것들 — **아래 가운데 한 묶음**(레벨 배지 · 경험치 % ·
체력 막대 · 퀵슬롯 4칸 + **물약 칸** + 자동사냥 칸)과 **오른쪽 위 메뉴**다. 메뉴는 평소에 **정보·스킬·가방·던전 + ≡** 만
서고, ≡ 를 누르면 판이 펼쳐져 **강화·크리스탈·헬스·도감·샌드백·(랭킹)·설정** 이 4열로 나열된다 → 아래 "메뉴 판".

**2026-09-29** — 격투가가 스킬 없이 평타만 쓰게 되어 **퀵슬롯 스킬 칸 네 개는 숨는다**(물약·자동사냥 칸만 남는다,
`Skills.actives_shown`). **스킬 아이콘에 레드닷**이 붙는다 — 배울 수 있는 패시브 단계가 있으면 켜진다
(`_skill_dot`, `_refresh_status` 가 매 프레임 맞춘다) → [passives.md](passives.md).
설계 단추는 오른쪽 맨 아래 모서리에 **안 보이게** 숨어 있다 ("설계 재현 창").
물약 칸은 2026-09-26 에 더했고, 같은 날 퀵슬롯 **왼쪽**으로 옮겼다 → 아래 "물약 칸".
정보 단추는 2026-09-25 에 메뉴 맨 앞(스킬 왼쪽)에 더했다 — 캐릭터 정보 창을 따로 띄운다
→ [inventory-equipment.md](inventory-equipment.md). 그림은 기사 투구(`ui_icon_character`, 2026-09-26).
던전 단추는 2026-09-23 에 가방 오른쪽 옆에 더했다 → [dungeons.md](dungeons.md).
강화 단추는 2026-09-24 에 가방 **왼쪽** 옆에 더했다 (오른쪽 옆은 던전 자리) — 강화 팝업을
다중 강화 · 전체 목록으로 연다 → [items.md](items.md) "강화". 그림은 모루를 내리치는 망치(`ui_icon_enhance`, 2026-09-26).
크리스탈 단추는 같은 날 가방 **바로 왼쪽**에 더했다 (강화는 한 칸 왼쪽으로 밀렸다) — 인벤토리·장비
창과 크리스탈 강화 창을 같이 연다 → [items.md](items.md) "크리스탈".
**메뉴 일곱 단추는 2026-09-28 에 그림을 전부 갈고 아래에 이름 글자를 달았다** → 아래 "메뉴 아이콘".

2026-09-19 에 처음 짓고, **2026-09-20 에 받은 그림(모바일 MMORPG HUD)대로 다시
지었다.** 그 사이 한 번은 왼쪽 위에 초상과 막대 둘을 세운 상태판이 있었는데,
"HP 바도 퀵슬롯 위로, 그 위에 레벨, 레벨 아래에 경험치 %" 라는 요청으로 전부
아래로 내렸다. 초상(`ui_portrait`)은 그때 빠졌다.

```
┌ 마을  골드 0  몬스터 0/0 … 빌드   [마을가기]   [정보][스킬]…[던전] ┐  ← 마을가기는 마을 밖에서만
│ <마지막에 일어난 일 한 줄>                                           │
│                                                                     │
│ [테스트 단추 묶음]  ← 접을 수 있다 (play-mode.md)                     │
│ [치트 목록 열기/닫기]                                                │
│ ┌채팅창 ───────┐  ← 왼쪽 아래 구석 (아래 "채팅창")                   │
│                          ( Lv.58 )        ← 레벨 배지                │
│                  [■■■■■ 72 / 120 ─────────]  ← 체력 막대             │
│                  [물약] [퀵1][퀵2][퀵3][퀵4] [자동사냥]               │
├■■■■■■■■──── 경험치 40.00% ────────────────────┤ ← 맨 아래 경험치 띠   │
└─────────────────────────────────────────────────────────────────────┘
```

## 어디

| 파일 | 역할 |
|---|---|
| `godot/game/game.gd` | `_build_level_badge` / `_make_bar` / `_refresh_status` — 퀵슬롯 위 묶음 |
| ″ | `_icon_button` — 오른쪽 위 메뉴 단추 하나 (`_menu_cells` 에 담는다). `caption` 이면 아이콘 네모 · 이름 글자를 세로로 쌓는다(`MENU_CAPTION_*`) |
| ″ | `_build_skill_bar` — 묶음 전체(세로 상자) · 퀵슬롯 4칸 + 자동사냥 칸(`_auto_cell`)과 고리(`_auto_spin`) |
| ″ | `_refresh_auto` / `_process` — 켜짐 표시와 고리 돌리기, `SpinRing`(그림이 없을 때) |
| ″ | `_build_potion_cell` · `_refresh_potion` · `_build_potion_panel` · `_potion_step` — **물약 칸**과 설정 창(−/+ · 슬라이더). 아래 "물약 칸" |
| `godot/world/world.gd` | `drink_potion` · `set_potion_pct` · `_drive_potions` — 물약 판정 (저절로 마시기는 `step` 에서) |
| `godot/game/sound_settings.gd` | **소리 크기** (`SoundSettings`) — Master 버스 볼륨 0~100, `user://settings.cfg` 에 저장. 아래 "소리 설정" |
| `godot/game/game.gd` | `_build_sound_panel` · `_sound_step` · `_set_sound` · `_show_sound` — 메뉴 "설정" 으로 뜨는 소리 창 |
| `godot/tests/ui_test.gd` | `_case_sound` — 설정 단추로 창 · +/− · 슬라이더가 버스 볼륨을 바꾸고 0 이면 음소거 |
| `godot/tests/potion_test.gd` | 저절로 마시기 · 쿨타임 10초 · 직접 마시기 · 기준 자르기 · 저장 |
| `godot/tests/ui_test.gd` | `_case_potion` — 퀵슬롯 옆 자리 · 설정 창 +/− · 눌러서 마시고 쿨타임이 돈다. `_case_auto_priority` — 자동사냥 스킬 순서 창 |
| `godot/game/chat_log.gd` | **채팅창** (`ChatLog`) — 왼쪽 아래 구석, 장비 획득·강화·말을 한 줄씩 적는다. 아래 "채팅창" |
| `godot/game/exp_toast.gd` | **경험치 알림** (`ExpToast`) — 오른쪽 아래, 잠깐 떴다 사라진다. 아래 "경험치 알림" |
| `godot/game/game.gd` `_on_event` | `reward` → `_exp_toast.add_exp`, `loot`(장비가 있을 때) → `_chat.add_item` |
| `godot/tests/ui_test.gd` | `_case_status` — 자리·숫자·안 겹침·눌러서 창 열기 |
| `godot/tests/chat_log_test.gd` | 잡아도 경험치 줄은 **안** 적히나 · 장비 줄 · 구석 자리·안 겹침 · 안 사라짐 · 50줄 상한 |
| `godot/tests/exp_toast_test.gd` | 진짜로 잡으면 알림이 뜨나 · 오른쪽 아래 자리·안 겹침 · 3.1초 뒤 사라짐 · 6줄 상한 |
| ″ | `_run_scene` 의 자동사냥 대목 — 켜면 고리가 보이고 **각이 변한다** |
| `godot/tools/shot.gd` | `_hud` — 자동사냥을 켠 채로 화면을 뽑는다 (`npm run shot:godot -- hud`) |
| `scripts/sync-godot-assets.mjs` | `ICONS` — 조각 이름을 여기 적어야 `godot/assets` 로 간다 |
| `scripts/build-item-icons.mjs` | `FRAME_SIZE` · `HOLLOW` — 조각을 굽는 설정 |
| `scripts/fetch-assets.sh` | 조각들의 결과물 주소 |

## 규칙

### 조각으로 조립한다 ★

그림 한 장으로 그린 HUD 를 붙이지 않는다 (CLAUDE.md, [portal-ui.md](portal-ui.md)
의 같은 규칙). 해상도가 바뀌어도 앵커로 자리를 잡아야 한다.

```
묶음  VBox(아래 가운데, 바닥에서 경험치 띠 높이 + 8 = 28 — 16 이면 칸이 띠에 가렸다)
 ├ Control(LEVEL_BADGE) ─ TextureRect(ui_level_badge) + Label "58"
 ├ Label "경험치 40.00%"
 ├ PanelContainer(ui_bar_frame) ─ TextureProgressBar(ui_bar_fill) ─ Label "72 / 120"
 └ HBox ─ 칸 4개 + 자동사냥 칸 (전부 `_make_skill_cell`, 테두리는 ui_quick_slot)
메뉴  HBox(오른쪽 위) ─ PanelContainer(ui_menu_btn) ─ ui_icon_skill / ui_icon_bag
```

- **막대 길이를 안 정한다** — 세로 상자가 가장 넓은 자식(퀵슬롯 줄)에 맞춰 늘여
  준다. 칸 수가 바뀌어도 막대가 따라온다.
- **글자는 이미지에 굽지 않는다.** 레벨·체력·경험치는 전부 `Label` 이다.
- **조각이 없어도 돈다.** `npm run sync:godot` 을 안 돌렸으면 테두리는 코드로 그린
  판(`_frame_box`), 막대 채움은 흰 판(`_white`), 고리는 `SpinRing` 이 그린 화살표
  둘이다 — 모델이 없으면 기둥으로 그리는 것과 같은 규칙이다.

### 채움은 직사각, 홈이 마스크 ★★

홈(`ui_bar_frame`)은 끝이 **비스듬히 잘려** 있다. 여기에 모양이 다른 채움을 겹치면
모서리마다 홈 바닥이 비쳐 **"빈 공간"** 으로 보인다 (2026-09-20 지적 — "테두리랑
그걸 채우는 슬라이드 이미지가 달라서 생기는 문제").

**채움을 홈 모양에 맞춰 그릴 필요는 없다. 자르는 것은 고도가 한다:**

```gdscript
frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
```

부모가 그린 **알파 안에서만 자식이 보인다.** 홈이 곧 마스크라, 채움은 직사각
한 장이면 되고 비스듬한 끝은 홈이 잘라 준다. 길이·높이가 어떻게 바뀌어도 맞는다.

- 채움 그림(`ui_bar_fill`)은 **`build-item-icons.mjs` 가 직접 그린다** — 위가 밝고
  아래로 어두워지는 직사각 그라데이션이라 바르코에서 받을 것이 없다. 색은
  `tint_progress` 가 입힌다 (체력 `#c33122`, 경험치 `#e8c14a`).
- `BAR_PAD` 는 0 이다. 조금이라도 주면 그 틈으로 홈 바닥이 비친다.
- 빈 쪽 바닥은 **홈 그림 안에 있다** — 조각을 뚫지 않고 어두운 안쪽째로 받는다.
  맨 아래 경험치 띠만 홈이 없어서 `tint_under`(`#26241f`)로 직접 깐다.

### 금테는 채움 **위에** 한 번 더 얹는다 ★★

마스크는 자르기만 한다 — 그리는 순서는 그대로다. 홈이 부모라서 **채움이 홈 위에
그려지고, 찬 쪽의 금테를 덮었다.** 테가 빈 쪽에만 남아 막대가 반으로 갈린 것처럼
보였다 (2026-09-20 지적 — "HP 가 차 있는 상태에서도 황금 테두리는 동일하게 있어야
하고, 피가 닳면 테두리는 그대로 유지된 상태에서 회색 배경이 나와야지").

```gdscript
var edge := _frame_box("ui_bar_frame", BAR_FRAME_MARGIN, 0)
edge.draw_center = false        # 가운데(채움)는 그대로 두고 테만 다시 그린다
frame.add_child(border)         # 채움 **다음**에 붙여야 위로 온다
```

- **조각을 새로 만들지 않는다.** 같은 홈 그림을 9조각으로 다시 깔되 가운데 조각만
  건너뛰면 테만 남는다. 비스듬히 잘린 끝은 **모서리 조각에 들어 있어** 따라온다.
- 순서가 전부다 — `frame` 에 `bar` 를 먼저, `border` 를 나중에 붙인다.
- 테는 `frame` 의 알파 안에 있으므로 `clip_children` 에 잘리지 않는다.
- 숫자(`text`)는 `bar` 의 자식이라 테보다 아래에 그려지는데, 테는 가장자리 5px
  뿐이고 글자는 가운데 정렬이라 겹치지 않는다.

### 늘여 쓸 것과 한 장으로 깔 것 ★★

9조각(`_frame_box`)은 **테두리**용이다. 가운데를 늘여 채우므로, 가운데에 그림이
있는 조각에 쓰면 그 그림이 사라진다.

- 레벨 배지를 9조각으로 깔았더니 **둥근 테가 없어지고 좌우 날개만 남았다**
  (2026-09-20, 찍어서 봤다) → `TextureRect` 한 장으로 비율 그대로 깔고 숫자를 얹는다.
- 막대 홈은 테두리라 9조각이 맞지만, **테 두께의 두 배보다 높아야 한다.**
  높이 34 에 여백 18 을 줬더니 위아래 조각이 겹쳐 홈이 안 보였다 → 높이 40,
  여백 `BAR_FRAME_MARGIN` 12.

### 숫자가 잘리지 않을 높이 ★

글자가 쓸 수 있는 높이는 막대 높이에서 안쪽 여백(`BAR_PAD`)의 두 배를 뺀 값이다.
체력 막대는 40(글자 18). 경험치를 22px 막대에 넣었을 때 **다섯 자리 숫자가
위아래로 잘린** 적이 있다 (2026-09-19) — 지금 경험치는 막대가 아니라 퍼센트다.

### 경험치는 화면 맨 아래 띠다 ★

2026-09-20 에 받은 그림대로 **화면 바닥을 가로지르는 가는 게이지**(`_build_exp_gauge`,
높이 `EXP_GAUGE_H` 7)를 깔았다. 홈(테두리)을 두르지 않는다 — 화면 끝까지 닿아야 한다.

- **앵커만 잡고 여백은 손으로 준다.** `PRESET_BOTTOM_WIDE` 를 `PRESET_MODE_MINSIZE`
  로 걸었더니 띠가 화면 **아래로 제 높이만큼 삐져나갔다** (테스트가 잡았다).
  `offset_top = -EXP_GAUGE_H`, 나머지 0 이 맞다.
- 퍼센트 글자(`_exp_text`)는 **띠 가운데에 얹는다** (2026-09-20 요청). 배지 아래에
  있던 것을 옮겼다 — 띠만으로는 몇 퍼센트인지 못 읽는다. 글자가 들어가야 하므로
  띠 높이는 20 이다.
- **채움은 단색 판(`_white`)이다.** 광택 캡슐(`ui_bar_fill`)은 위아래에 투명 여백이
  있어 가는 띠에 넣으면 **띠 높이를 다 못 채우고 위쪽이 빈다** (2026-09-20 지적).
- 안 채운 쪽은 `#26241f` — 체력 막대 홈 바닥과 같은 톤이라야 한 벌로 보인다.

### 경험치 퍼센트 글자

받은 그림이 그랬다 (2026-09-20). `_exp_text` 한 줄에 `경험치 40.00%` 로 적는다
(`_exp_bar` 는 지웠다). 레벨은 배지 안에 **`Lv.N`** 으로 적는다 — 숫자만 넣었다가
"레벨도 Lv.2 이런식으로 넣어" 라는 요청을 받았다 (2026-09-20).

### 상태는 한 곳에서만 그린다

레벨·체력·경험치는 `_refresh_status` 하나가 스냅샷을 보고 그린다. `_label` 에서
같은 값을 지웠다 — 두 곳에 적으면 한 쪽만 고치고 끝난다. `_label` 에 남은 것은
**존 이름·골드·몬스터 수·fps·빌드 표시**다. 빌드 표시는 지우면 안 된다
([godot-migration.md](godot-migration.md) 의 "지금 보는 것이 어느 빌드인지").

### 크기는 두 번 줄였다 ★

2026-09-20 에 "UI 크기를 좀 줄여" 로 한 뼘, 다시 **"이쪽 UI 가 너무 커, 크기 반으로
줄여"** 로 아래 묶음만 반으로 줄였다. **창 칸(`SKILL_CELL` 100)과 오른쪽 위 메뉴는
그대로다** — 창은 열었을 때 크게 보는 것이고, 지적받은 것은 아래 묶음이다.

| | 처음 | 한 뼘 | 반으로 |
|---|---|---|---|
| 퀵슬롯 칸 `QUICK_CELL` | 104 | 84 | **52** |
| 자동사냥 칸 `AUTO_CELL` | — | 106 | **64** |
| 레벨 배지 `LEVEL_BADGE` | 86 | 64 | **50** |
| 체력 막대 높이 `HP_BAR_H` | 40 | 30 | **22** |
| 레벨 글자 · 경험치 · 체력 | 30 · 17 · 18 | 23 · 15 · 15 | **13 · 11 · 12** |

줄이면서 밟은 것 셋 (전부 찍어서 봤다):

- **칸 안 글자의 최소 높이가 칸보다 크면 칸이 늘어난다.** 쿨타임 초를 28 로 둔 채
  칸을 44 로 줄였더니 **퀵슬롯이 세로로 길쭉해졌다** → 글자도 16 으로.
- **배지 글자는 배지 안에 들어가야 한다.** `Lv.200` 여섯 자가 지름 34 를 넘쳐서
  배지를 50 으로 키웠다.
- **고리를 칸 바닥에서 띄운다**(`SPIN_LIFT` 13). 칸을 꽉 채우면 아래쪽 화살표가
  "자동사냥" 글자와 겹친다.

### 테두리 두께는 조각마다 다르다 ★

`_frame_box(name, margin, content)` 의 `margin` 은 **그림에서 테가 차지하는
픽셀**이다. 실제보다 크게 주면 9조각의 모서리가 서로 겹쳐 칸을 먹는다.

| 쓰는 곳 | 값 |
|---|---|
| 창·스킬창 칸 (`ui_slot` 등, 두꺼운 테) | 26 (`_make_skill_cell` 의 기본값) |
| 퀵슬롯·자동사냥 칸 (`ui_quick_slot`, 얇은 선) | `QUICK_MARGIN` 10 |
| 체력 막대 홈 | `BAR_FRAME_MARGIN` 7 |
| 오른쪽 위 메뉴 단추 | **없다** — `StyleBoxEmpty` |

### 자동사냥은 퀵슬롯 옆이되 테가 없다 ★

오른쪽 아래 글자 단추였던 것을 **퀵슬롯 옆**으로 옮겼다 (요청이 그랬다). 엄지가
퀵슬롯과 같은 높이에서 닿는다. 칸은 스킬 칸과 같은 `_make_skill_cell` 로 짓는다 —
배지·누르는 자리가 그대로 맞는다.

- **테두리는 지운다**(`StyleBoxEmpty`)**, 그리고 `AUTO_GAP`(14)만큼 띄운다.** ★
  같은 테를 두르고 붙여 놨더니 **다섯 번째 스킬 칸으로 보였다** (2026-09-20 지적).
  스킬을 쓰는 칸과 상태를 켜는 단추는 생김새가 달라야 한다.

- **칸이 퀵슬롯보다 크다** (`AUTO_CELL` 106, 퀵슬롯은 84) ★ — 고리가 **너무 작아서
  잘 안 보인다**는 지적을 받았다 (2026-09-20). 테가 없으니 커도 스킬 칸으로 안 보인다.
- **아이콘만 더 물린다** (`AUTO_INSET` 21). 퀵슬롯과 같은 값으로 두면 고리가 아이콘
  위를 덮어 **검이 안 보였다** (2026-09-19, 찍어서 봤다).
- 아이콘은 **검 두 자루가 X자로 엇갈린 문장**이다 (2026-09-20 요청).
- **칸 가운데 아래 배지는 늘 `자동사냥`** 이다 (2026-09-20 요청 — "자동 텍스트로
  넣었는데, 자동사냥 이라고 넣어"). 켜졌는지는 **고리가 도는 것으로** 안다.
- 켜짐을 **칸 전체 초록 `modulate`** 로 알리던 것은 뺐다 — 고리와 아이콘이 한
  덩어리로 보여 무엇이 도는지 알 수 없었다.
- **칸 오른쪽 위 "설정"** (2026-09-27) → 가운데에 **자동사냥 스킬 순서** 창. 단추는 물약 칸과
  같은 `_cell_setting` 이다. 창은 퀵슬롯 스킬을 쓸 순서대로 한 줄씩(순번 · 아이콘 · 이름·쿨타임 ·
  "위"/"아래") 세우고, 아래 "쿨타임 긴 순으로" 가 기본으로 되돌린다. 줄은 **순서가 바뀔 때만**
  다시 짓는다(`_auto_shown`) — 매 프레임 지으면 누르는 단추가 사라진다. 옛 줄은 `remove_child`
  하고 지운다 — 트리에 남으면 새 줄 이름이 겹쳐 바뀐다. **▲▼ 는 글꼴에 없어 "위"/"아래"** 다.
  판정 쪽 규칙은 [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md) 의 "스킬도 쓴다".

### 켜지면 고리가 돈다 ★

`ui_auto_spin`(**굵은 화살표 둘이 서로를 쫓는 고리**)을 칸 위에 얹고 `_process` 에서
`rotation += delta * SPIN_SPEED`(1.6 rad/s) 한다.

- **칸 안에서 돈다.** `PanelContainer` 는 자식을 칸 전체 크기로 다시 잡으므로
  칸보다 크게 둘 수 없다. 고리는 가운데가 뚫려 있어 아이콘이 그대로 보인다.
- 축은 매 프레임 `pivot_offset = size / 2` 로 잡는다 — 컨테이너가 크기를 다시
  잡으면 축이 어긋난다.
- 고리는 **아이콘 바로 위, 글자 아래**다 (`move_child(_auto_spin, 1)`). 맨 뒤에
  두면 고리가 "켜짐" 을 덮는다.
- 끄면 각을 0 으로 되돌린다 — 다음에 켤 때 늘 같은 자리에서 시작한다.
- **판정은 여기서 하지 않는다.** 켜짐은 서버가 준 `me.auto` 로만 정한다
  ([auto-hunt-and-targeting.md](auto-hunt-and-targeting.md)).

## 조각 여덟 장

바르코로 만들었다 (`nano-banana-pro`). 결과물 주소는 `scripts/fetch-assets.sh` 에
박혀 있다 — 다시 찾을 필요가 없다.

**아트는 2026-09-20 에 두 번 갈았다.** 처음 뽑은 "낡은 쇠 + 금테" 는 **테가 너무
두껍다**는 지적을 받았다. 받은 그림을 다시 뜯어보니 규칙이 둘이었다:

- **칸·막대·배지는 머리카락처럼 얇은 금색 선** 하나다. 두꺼운 금속도 리벳도 없고,
  안쪽은 그냥 어두운 판이다. 프롬프트에 쓴 말:
  `extremely thin pale gold hairline outline, no thick metal, no rivets, no ornament,
  the inside filled with flat dark charcoal grey`
- **메뉴 아이콘은 테두리가 아예 없다.** 크림색 선화 문장(紋章)만 떠 있다:
  `it must NOT sit on any disc, circle, plate, badge, frame or panel`
  — 이 문장을 안 넣으면 **아이콘이 크림색 원판 위에 앉아 나온다.**
- **아이콘은 밝게 칠한다.** ★ "선화(line-art)" 로 시켰더니 검은 실루엣에 금색
  윤곽만 남아 **밤 사냥터 바닥에 묻혔다** (2026-09-20 지적). 테 없는 아이콘은
  제 색으로 서 있어야 보인다:
  `FULLY COLORED and BRIGHT, warm ivory and gold with soft highlights,
  NOT a dark silhouette, NOT black, NOT a flat outline drawing`

**퀵슬롯 칸은 `ui_quick_slot` 으로 따로 둔다** ★ `ui_skill_slot` 은 스킬창 장착 칸이라
쓰임이 다르다. 2026-09-20 에 창을 다시 지으면서 **둘 다 같은 결로 맞췄지만**,
칸 크기와 테 두께가 달라 그림은 계속 따로 둔다.

| 이름 | 무엇 | 굽는 설정 |
|---|---|---|
| `ui_bar_frame` | 체력 막대 홈 (얇은 금선 + 어두운 안쪽) | 256 · 한 겹만 걷는다 |
| `ui_bar_fill` | 막대 채움 (직사각 그라데이션) | **굽는 스크립트가 그린다** |
| `ui_level_badge` | 레벨 배지 (얇은 금색 원 + 어두운 판) | 192 · 한 겹만 걷는다 |
| `ui_quick_slot` | 퀵슬롯·자동사냥 칸 (얇은 선, 위 모서리 잘림) | 128 · 한 겹만 걷는다 |
| `ui_icon_skill` · `ui_icon_bag` · `ui_icon_dungeon` | 메뉴 — **2026-09-28 에 리니지풍으로 갈았다** → 아래 "메뉴 아이콘" | 128 |
| `ui_icon_auto` | **검 두 자루가 X자** — 2026-09-28 에 리니지풍으로 갈았다 | 128 |
| `ui_auto_spin` | 굵은 화살표 고리 (얇은 것은 안 보였다) | 192 · 가운데를 뚫는다 |
| `ui_close` | 창 오른쪽 위 닫기 X — **가늘고 끝이 뾰족한 금빛 막대 두 개, 테두리 없음** (2026-09-28) | 128 |
| `ui_portrait` | 옛 초상 테두리 (**미사용**) | 192 |

**안쪽을 뚫지 않고 어두운 채로 받는다** ★ 막대 홈·배지·칸은 안쪽이 어두운 판이고,
그 위에 채움·숫자·아이콘이 올라간다. 뚫으면 땅이 비친다. 대신 배경을 걷을 때
**한 겹만** 걷어야 한다(`SINGLE_LAYER`) — 그림이 화면을 꽉 채워 첫 겹이 조금밖에
못 걷으면, 얇은 여백을 벗기는 규칙이 한 겹 더 들어가 **안쪽 어두운 판까지 먹는다.**

**참고 그림은 작게 줄여서 올린다** ★★ 바르코에 로컬 그림을 넣는 길은
`upload_image` 하나뿐인데, **바이트를 base64 로 손수 옮겨야 해서 크면 깨진다.**
1024 짜리 PNG 를 올렸더니 잘린 채 올라가 다섯 장이 통째로 실패했고(2026-09-19),
7KB 짜리도 "not valid base64" 로 거절당했다(2026-09-20).

- 받은 화면에서 **필요한 자리만 잘라** 폭 200 안팎, JPEG 품질 45 로 줄인다
  (2KB 남짓, base64 3천 자). 이 크기는 한 번에 올라갔다.
- 올린 뒤 **주소를 다시 받아 원본과 바이트를 대 본다** (`cmp`). 이것을 안 하면
  잘린 그림으로 돌린 것을 결과가 이상해진 다음에야 안다.
- 아이콘 셋(스킬·가방·자동사냥)은 이렇게 물려서 한 번에 결이 맞았다. **프롬프트로
  스타일을 설명하는 것보다 훨씬 빠르다** — 말로 고치다 네 번을 돌렸다.

## 메뉴 아이콘 (2026-09-28) ★★

요청: "UI HUD 버튼을 보면 어떤 버튼인지 텍스트가 없어서 헷갈려. 이런식으로 텍스트 넣도록 변경하고.
지금 아이콘 마음에 안 들으니까 스크린샷 보고 아트풍 저런식으로 변경해" — 받은 그림은 다른 게임의
메뉴 넷(상점 돈주머니 · 인벤토리 가방 · 스펠 마법서 · 퀘스트 두루마리)이고, **아이콘 아래에 흰 글자**가 붙어 있다.

### 지금은 칠한 반실사 결 (2026-09-29, 세 번째) ★★

> ★★★ **앞으로의 HUD 기준이다** ("지금 느낌 좋다. HUD는 앞으로도 지금 스타일로 만들자", 2026-09-29).
> 새 HUD 아이콘은 [ui-art-style.md](ui-art-style.md) "HUD 아이콘 기준 (2026-09-29)" 의 완성 프롬프트 한 벌로 뽑는다 —
> 아래는 여기까지 온 기록(첫 판 프롬프트 → 색 통일 → 던전 문)이다.

요청: 다른 게임의 HUD 아이콘 넷(세력 탑 · 커뮤니티 사람들 · 랭킹 트로피 · PVP북 엇갈린 검) 그림 +
"HUD 아이콘이 내가 원하는 아트풍이 아니야. 스크린샷 참고해서 다시 만들어봐" — 아래의 **청동 문장 결을 갈았다.**
청동 결은 세공이 빽빽해서 작게 보면 뭉개졌다. 받은 그림은 **단순한 실루엣을 부드럽게 칠한 반실사**이고,
**색은 네 장 모두 상아·카키·바랜 놋쇠 한 줄기**다(아래 "색은 한 줄기"). 왼쪽 위 빛, 약간 비스듬한 각, 판·원판 없음.

- 갈린 것: 메뉴 여덟 장 + 자동사냥 + 물약 (청동 결과 같은 열 장). **닫기 X(`ui_close`)는 그대로**다.
- **참고 그림**: 받은 스크린샷 그대로(245×56, JPEG 45, 1.9KB) —
  `https://3d.varco.ai/api/objects/7cb46959217839da3aa126a3a6a909eb.jpg`. 같은 결로 한 장 더 만들 때 이것을 물린다.
- **프롬프트** (`<무엇>` · `<쓰임>` 만 간다. 해골·X 검처럼 정면인 것은 `Slight three-quarter view` 를 `Front view` 로),
  1:1, `nano-banana-pro`, 두 장씩:

  ```
  Mobile MMORPG HUD menu icon: <무엇>, meaning '<쓰임>'. MATCH THE REFERENCE IMAGE'S ART STYLE EXACTLY
  (its castle tower, group of people, trophy and crossed swords): a softly hand-painted semi-realistic game
  icon in natural material colors — weathered grey stone, warm brown wood and leather, soft polished gold,
  pale silver steel — with gentle warm light from the upper left, smooth soft shading and a clean, simple,
  bold silhouette with little fine detail. NOT an engraved bronze relief, NOT monochrome sepia, NOT ornate
  filigree. Slight three-quarter view, centered, fills the frame, readable at 60 pixels. One object standing
  alone — it must NOT sit on any disc, circle, plate, badge, frame or panel. Isolated on a flat pure white
  background; everything outside the object is pure white, the four corners must be pure white. Ignore the
  captions and the dark background in the reference: no text, no letters, no numbers.
  ```

  `NOT an engraved bronze relief, NOT monochrome sepia` 는 빼지 않는다 — 앞 결(청동 문장)로 되돌아가지 않게 막는 문구다.
- 고른 것은 `scripts/fetch-assets.sh` 주석에 있다.
- **던전은 문이다** (2026-09-29 요청: "던전 UI 아이콘을 던전 문으로"). 처음엔 뿔 해골이었다.
  아래 "색은 한 줄기" 대로 **처음부터 팔레트 문장 + 팔레트 띠를 물려** 한 번에 같은 색으로 나왔다.
  세 장 중 **셋째는 팔레트 띠를 그림 아래에 그려 왔다** — 띠를 물릴 때는 `Do not copy the swatches` 를 넣어도
  가끔 이렇게 나오니 여러 장 뽑아 거른다. 둘째를 골랐다 (문이 더 열려 안쪽 어둠이 커서 42px 에서도 입구로 읽힌다).

#### 색은 한 줄기 — 세피아 단색조 ★★ (같은 날 고침)

위 프롬프트로 뽑은 첫 판은 **"아트 느낌을 보면 색감이 통일되어 있자나. 지금은 색감이 전혀 달라"** 는 지적을 받았다.
`natural material colors` 라고 시켰더니 아이콘마다 제 색(파란 룬 · 보라 결정 · 빨간 가방·물약 · 번쩍이는 금)이 나왔다.
받은 그림은 **네 장이 전부 상아·카키·바랜 놋쇠 한 줄기**이고, 색은 탑 깃발 청록 · 칼자루 보석 같은 **점 하나**뿐이다.

- **팔레트** (받은 그림의 아이콘 픽셀을 밝기 5·20·40·60·80·95·99% 에서 뽑은 값):
  `#24170a` · `#504330` · `#6a5b47` · `#847965` · `#a59a82` · `#c2baa5` · `#ddd0b3`.
  띠로 만들어 올린 것: `https://3d.varco.ai/api/objects/ba3adc8e23e0f960db7f48563bb129da.png` (140×20, 176B).
- **고친 방법**: 모양은 그대로 두고 `EditImage` 로 색만 다시 칠했다 — 원본(첫 판에서 고른 것) + 참고 그림 두 장
  (받은 스크린샷, 팔레트 띠) + 아래 지시문, `nano-banana-pro`, 두 장씩. 두 장 중 **팔레트와 색 거리가 작은 쪽**을
  골랐다 (7 분위 RGB 거리 평균 20~33).
- **새 아이콘은 처음부터 같은 줄기로 뽑는다** — 위 `GenerateImage` 프롬프트의 `in natural material colors — …` 를
  아래 지시문의 팔레트 문장(`ONE unified, muted sepia palette … no bright red, no saturated blue …`)으로 바꾸고
  팔레트 띠를 두 번째 참고 그림으로 물린다. 안 하면 또 제각각 색이 나온다.

  ```
  Recolor this game icon so its colors match the first reference image EXACTLY (the castle tower, group of
  people, trophy and crossed swords). Those reference icons all share ONE unified, muted sepia palette, shown
  as swatches in the second reference image: dark umber shadows (#24170a, #504330), khaki-taupe midtones
  (#6a5b47, #847965), pale parchment-ivory highlights (#a59a82, #c2baa5, #ddd0b3) — like aged bone and pale
  worn brass, low saturation, soft matte paint. Repaint the WHOLE object using only these tones: no bright
  red, no saturated blue, no purple, no orange, no vivid yellow gold, no pure white highlights. At most one
  tiny accent spot of muted teal or deep dull red (like the small gems on the reference swords), covering
  less than 3% of the icon. Keep the exact same object, shape, pose, composition, size and soft painted
  shading — change only the colors. Keep the flat pure white background; everything outside the object and
  the four corners stay pure white. Do not copy the swatches, captions or dark background of the references.
  No text, no letters.
  ```

그림 (전부 위 팔레트 한 줄기 — 색 이름을 따로 적지 않는다):

| 단추 | 그림 | 이름 |
|---|---|---|
| 정보 | 깃 단 기사 투구 | `ui_icon_character` |
| 스킬 | 룬 새긴 가죽 마법서 | `ui_icon_skill` |
| 강화 | 모루를 내리치는 망치 · 불티 | `ui_icon_enhance` |
| 크리스탈 | 바위에서 솟은 결정 | `ui_icon_crystal` |
| 가방 | 버클 가죽 배낭 | `ui_icon_bag` |
| 던전 | 돌 아치에 반쯤 열린 나무 문 — 안쪽이 어둡다 (2026-09-29 "던전 문으로" 요청, 전엔 뿔 해골) | `ui_icon_dungeon` |
| 헬스 | 쇠 덤벨 — 던전 옆 (2026-09-30, [fitness.md](fitness.md)) | `ui_icon_fitness` |
| 도감 | 방패 문장이 든 펼친 책 (2026-10-01, [codex.md](codex.md)) | `ui_icon_codex` |
| 샌드백 | 받침에 선 가죽 샌드백 — 도감 옆 (2026-10-02, [sandbag.md](sandbag.md)). 세 장 중 둘째(단순한 실루엣) | `ui_icon_sandbag` |
| 메뉴 ≡ | 놋쇠 막대 셋 — 평소 줄 맨 오른쪽 (2026-10-01, 아래 "메뉴 판") | `ui_icon_menu` |
| 메뉴 X | 엇갈린 두 검 — 판이 펼쳐지면 ≡ 자리에 선다 | `ui_icon_menu_close` |
| 설계 | 두루마리 도면 위 컴퍼스 | `ui_icon_design` |
| 랭킹 | 받침 달린 트로피 | `ui_icon_rank` |
| 자동사냥 | 장검 둘이 X자 | `ui_icon_auto` |
| 물약 | 코르크 막은 둥근 병 | `ui_icon_potion` |

### 그 전: 청동 문장 결 (2026-09-28 두 번째) — 프롬프트를 되살리지 않는다

요청: 다른 게임의 메뉴 아이콘 판(변신 · 혈맹 · 랭킹 · 던전 · 몬스터도감 …) 그림 + "HUD의 아이콘들을
이런 아트풍을 원하는거야. 지금은 너무 다른 것 같아." — 아래의 **칠한 가죽·양피지 결에서 한 번 더 갈았다.**
**바랜 청동·금을 새긴 금속 문장**, 거의 한 색(갈색 도는 청동)이고 **작은 색 포인트 하나**(붉은·푸른 보석,
보라 결정, 붉은 물약)만 있다. 정면, 판·원판 없음.

- 갈린 것: 메뉴 여덟 장(정보 · 스킬 · 강화 · 크리스탈 · 가방 · 던전 · 설계 · 랭킹) + 자동사냥 + 물약.
  **닫기 X(`ui_close`)는 그대로**다 (가는 금빛 막대라 결이 이미 가깝다).
- **참고 그림**: 받은 판의 윗부분(아이콘 세 줄)을 170px JPEG 35(2.0KB)로 줄여 올린 것 —
  `https://3d.varco.ai/api/objects/0e1d54254853852286fe67f37ff1c36b.jpg`. 같은 결로 한 장 더 만들 때 이것을 물린다.
- **프롬프트** (`<무엇>` · `<쓰임>` · `<포인트>` 만 간다), 1:1, `nano-banana-pro`, 두 장씩:

  ```
  Mobile MMORPG HUD menu icon: <무엇>, meaning '<쓰임>'. MATCH THE REFERENCE IMAGE'S ART STYLE EXACTLY:
  an engraved antique metal emblem — aged bronze and worn dull gold in brown-sepia tones, finely sculpted
  relief detail, soft metallic highlights and dark engraved recesses, mostly monochrome bronze with at most
  one small colored accent (<포인트>). Straight-on front view, centered, bold readable silhouette at small
  size, fills the frame. One emblem standing alone — it must NOT sit on any disc, circle, plate, badge,
  frame or panel. Isolated on a flat pure white background; everything outside the emblem is pure white,
  the four corners must be pure white. Ignore the captions and the dark background in the reference:
  no text, no letters, no numbers.
  ```

  `Ignore … the dark background in the reference` 는 빼지 않는다 — 참고 그림 바탕이 어두워서 안 쓰면
  바탕째 그려 온다. 흰 바탕이라 굽는 스크립트가 걷는다(기본 설정 그대로).
- 한 번에 결이 맞았다. **강화는 둘째를 골랐다 — 첫째는 모루 뒤에 원판이 붙어 나왔다.**
  고른 것은 `scripts/fetch-assets.sh` 주석에 있다.

아래는 그 전(같은 날 첫 번째) 결의 기록이다 — 프롬프트를 되살리지 않는다.

**오른쪽 위 메뉴 일곱 장만 이 결이었다.** 상아빛 선화 결([ui-art-style.md](ui-art-style.md))이 아니라
**손으로 칠한 반실사 아이콘** — 낡은 가죽 갈색 · 양피지 · 바랜 금 · 짙은 빨강, 왼쪽 위 빛, 약간 비스듬한 각.
같은 날 "앞으로 기준 + HUD 나머지" 로 넓혀서 **자동사냥(`ui_icon_auto`) · 물약(`ui_icon_potion`) ·
창 닫기 X(`ui_close`)** 도 같은 참고 그림 · 같은 틀로 다시 뽑았다. 창 안 아이콘(차원문 줄 등)은 아직 옛 결이다.
- ★ **닫기 X 는 테두리를 두르지 않는다.** 처음 뽑은 "청동 테 + 붉은 칠 X" 는 "테두리가 있어서 이상해"
  라는 지적을 받았다. 사용자가 준 두 번째 그림(가늘고 양끝이 뾰족한 금빛 막대 둘이 X 로 겹친 것,
  `https://3d.varco.ai/api/objects/ad3bd8cdbd5081ca5e380dbb42a3d9e4.jpg`)을 참고로 물려 다시 뽑았다.
  프롬프트에 `NO border, NO outline frame, NO rim, NO enamel inlay` 와 `THIN ... NOT thick` 를 넣는다.

그때(청동 문장 결) 그림 — 지금 그림은 위 "칠한 반실사 결" 표:

| 단추 | 그림 | 이름 |
|---|---|---|
| 정보 | 붉은 깃 단 기사 투구 | `ui_icon_character` |
| 스킬 | 푸른 룬이 새겨진 금속 표지 마법서 | `ui_icon_skill` |
| 강화 | 모루를 내리치는 망치 · 불티 | `ui_icon_enhance` |
| 크리스탈 | 청동 받침에 박힌 보랏빛 결정 | `ui_icon_crystal` (**새 이름** — 전엔 아이템 그림 `crystal` 을 빌려 썼다) |
| 가방 | 버클 달린 가방 · 붉은 보석 | `ui_icon_bag` |
| 던전 | 뿔 달린 악마 해골 | `ui_icon_dungeon` |
| 설계 | 톱니 위 컴퍼스 · 푸른 보석 | `ui_icon_design` |
| 랭킹 | 월계관 두른 트로피 · 붉은 보석 | `ui_icon_rank` |
| 자동사냥 | 검 두 자루가 X자 · 붉은 보석 | `ui_icon_auto` |
| 물약 | 청동 세공 둥근 병 · 붉은 물약 | `ui_icon_potion` |

- **랭킹 단추는 서버에 붙었을 때만 선다** (던전 옆, 메뉴 맨 끝, 2026-09-28) — 혼자 노는 판에는 견줄 사람이
  없다. 그래서 GitHub Pages 화면에는 안 보인다. 그림은 2026-09-29 에 칠한 반실사 결로 갈았다(받침 달린 금 트로피)
  → [server.md](server.md) "랭킹"

- **글자는 그림에 굽지 않고 `Label`(이름 `caption`)로 얹는다.** 칸 안을 `VBoxContainer` 로 나눠
  **아이콘 네모(62) 아래 줄**에 둔다 (간격 `MENU_CAPTION_GAP` 1). 14px · 상아(`#eeead7`) · 검은 테 5.
  닫기 X 는 같은 `_icon_button` 을 쓰지만 글자를 안 단다.
  - ★ 처음엔 칸을 16px 늘이고 아이콘 발치와 4px 겹치게 했는데, 14px 글자의 줄 높이가 16 을 넘어
    **글자가 아이콘을 덮었다** ("아이콘이랑 글씨가 겹쳐 있는데, 스크린샷처럼 아래에 넣어", 같은 날).
    세로 상자는 글자 줄 높이만큼 칸을 알아서 늘이므로 겹칠 수가 없다. `ui_test` 가 글자 위끝이
    아이콘 아래끝보다 아래인지 본다.
- 그림이 없으면(동기화 안 함) 가운데 대신 글자를 띄우던 것은 `caption` 단추에서는 안 띄운다 — 아래 글자가 이미 있다.
- **참고 그림**: 받은 스크린샷 그대로 올린 것 — `https://3d.varco.ai/api/objects/6c80e88d6bc567159a81261d4b2f02b6.jpg`
  (238×62, JPEG 45, 2.5KB). 같은 결로 한 장 더 만들 때 이 주소를 `ImageInput` 에 넣는다.
- **프롬프트** (`<무엇>` 만 간다). 배경은 **흰색**으로 받는다 — 칠한 아이콘은 그늘이 검어서, 검은 바탕이면
  걷을 때 그늘까지 먹힌다:

  ```
  Mobile MMORPG HUD menu button icon: <무엇>, meaning '<쓰임>'. MATCH THE REFERENCE IMAGE'S ART STYLE
  EXACTLY: richly hand-painted, semi-realistic classic Korean fantasy MMORPG menu icon (Lineage style) —
  detailed painterly rendering, warm muted earthy palette (aged leather brown, parchment beige, worn gold,
  deep red accents), soft top-left light, a subtle soft dark shadow edge, strong readable silhouette at
  small size. Slight three-quarter view, centered, fills the frame. One object standing alone — it must
  NOT sit on any disc, circle, plate, badge, frame or panel. Isolated on a flat pure white background;
  everything outside the object is pure white, the four corners must be pure white. Ignore the captions
  in the reference: no text, no letters, no numbers.
  ```

  `Ignore the captions in the reference` 는 빼지 않는다 — 참고 그림에 한글 글자가 있다.
- 일곱 장을 각 두 장씩 뽑아 한 번에 결이 맞았다. 고른 것은 `scripts/fetch-assets.sh` 주석에 있다.
- `ui_test` `_case_status` 가 여섯 단추의 글자(정보·스킬·강화·크리스탈·가방·던전)와 **칸보다 안 넓은지**,
  그림이 붙었는지를 본다. 설계 단추는 오른쪽 아래로 옮겨서 같은 곳에서 따로 본다.

### 가방 빨간 점 (2026-09-28) ★

요청: "신규 아이템 획득하면 가방에 레드닷 표시해줘".

- **장비를 얻으면**(`loot` 이벤트에 `item` 이 있으면) 가방 단추 **아이콘 네모 오른쪽 위 모서리**에
  빨간 점(`_bag_dot`, 14px · `#e3342b` · 짙은 테 2px)을 켠다. **가방을 열면**(`_toggle_bag`) 끈다.
- 가방을 열어 둔 채 얻으면 켜지 않는다 — 이미 보고 있다.
- **골드·크리스탈만 떨어지면 켜지 않는다.** 크리스탈은 자주 떨어지는 재료라 점이 늘 켜져 있게 된다.
- 점은 그림이 아니라 `StyleBoxFlat` 동그라미다 (`_add_red_dot`) — 알림 표시라 에셋을 받지 않은 사람도
  보여야 한다. 메뉴 칸은 컨테이너라 자리를 못 잡으므로 아이콘 네모(`inset`)를 채운 빈 `Control` 에 앵커로 붙인다.
- 저장하지 않는다 — 다시 접속하면 꺼져 있다.
- `ui_test` `_case_bag_dot` 이 켜짐·안 켜짐·꺼짐과 **점이 아이콘 오른쪽 위에 있는지**를 본다.

## 설계 재현 창 ★

**"설계"** 단추 — 그림은 톱니바퀴 위 제도용 컴퍼스(`ui_icon_design`, 2026-09-26).
- **자리는 화면 오른쪽 맨 아래 모서리이고, 안 보인다** (2026-09-28 요청: "설계 버튼을 오른쪽 맨 아래로
  위치 변경하고, 아이콘이랑 텍스트 안 보이게 알파0으로"). 오른쪽 위 메뉴에서 빼서 `_design_cell` 로 따로
  세웠고 `modulate.a = 0` 이다 — 그림·글자는 안 보이지만 **누르면 그대로 열린다.** 알파만 0 이지
  `visible = false` 가 아니다 (그러면 못 누른다). `ui_test` `_case_status` 가 모서리에 붙었는지 · 알파 0 인지 ·
  눌러서 열리는지를 본다.
[stat-balance.md](stat-balance.md) 9장 5번이
요구한 디버그 수단이다 — 시뮬레이터와 같은 조건을 게임에서 세워 놓고 대조한다.

- **레벨 ±1/±10** 을 누르면 `World.debug_level` 이 레벨만 맞춘다 (체력은 새 최대치로).
- **장비는 자동으로 입히지 않는다** (2026-09-26 요청: "설계버튼 누르면 장비를 자동
  장착하는데 이 부분 없애"). 예전에는 등급 ±1 · 강화 ±1 단추가 있어서, 무엇을 누르든
  `World.debug_gear` 가 여섯 칸을 "등급 N 풀세트 + 강화 n" 으로 갈아입혔다 — 그 두 줄을
  걷었다. 스탯은 **지금 입은 장비 그대로** 찍힌다. `debug_gear` 는 테스트
  (`gear_test`·`stats_test`)가 세트를 입히는 데만 쓴다.
- **"설계" 단추로 창을 열기만 해서는 캐릭터가 안 바뀐다** (2026-09-26 요청: "버튼
  누른다고 세팅을 바꾸지 마"). 예전에는 여는 순간 `debugGear` 를 보내 100레벨·4등급
  풀세트로 갈아입혔다. 지금은 열 때 레벨 칸을 **지금 레벨**에 맞추고 값만 찍는다
  (`_toggle_debug` → `_refresh_debug`). 보내는 건 레벨 단추(`_apply_debug` → `debugLevel`)뿐이다.
- 아래에 **설계가 말하는 값**을 같이 찍는다 — 내 스탯 / 기준 플레이어 / 몬스터 수치 /
  1마리 타수(설계 6타) / 한 그룹 정리 시간·HP 손실(설계 목표 15초 / 50%).
- **수치로만 맞다고 믿으면 안 된다.** 붙이자마자 "고도의 맨몸 스탯만 옛 선형 공식"
  이라는 버그가 잡혔다 — 몬스터는 새 설계로 도는데 플레이어만 옛 곡선이었다.
- `godot/tests/ui_test.gd` 의 `_case_design_panel` 이 눌러서 확인한다 (레벨이 맞춰지고,
  **장비는 그대로**이며, 등급·강화 줄이 없는지까지).

## 물약 칸 (2026-09-26) ★

요청: "퀵슬롯 옆에 물약 슬롯 만들고, 설정한 HP 퍼센트가 되면 물약을 마시도록 설정해.
물약 설정 버튼 누르면 HP가 몇 퍼센트때 사용 될 건지 설정할 수 있도록 만들어. 그리고 물약
쿨타임은 10초로 하고 클릭하면 직접 사용도 할 수 있게 만들어."

- **자리** — 퀵슬롯 4칸 **왼쪽**, `AUTO_GAP` 만큼 띄운다 (처음엔 오른쪽 옆이었다 — 같은 날
  "물약을 퀵슬롯 왼쪽에 두고" 요청으로 옮겼다). 붙이면 다섯 번째 스킬 칸으로 보인다 (자동사냥 칸과
  같은 이유). 칸은 퀵슬롯과 같은 `_make_skill_cell(QUICK_CELL, …)` 이라 쿨타임 어둠·바늘·남은 초·
  다 돌면 번쩍이 그대로다. 묶음 가운데는 **물약 칸 왼쪽 끝 ~ 자동사냥 칸 오른쪽 끝**으로 잰다 (`ui_test`).
- **누르면 마신다** (`potion` 요청 → `World.drink_potion`). 쿨타임 중이면 "물약 쿨타임 N초",
  HP 가 가득하면 "HP 가 가득 찼습니다" 만 알리고 **쿨타임을 안 쓴다**.
- **저절로 마신다** — HP 가 기준(%) **이하**가 되면 `World._drive_potions` 가 `step` 마다 본다.
  자동 사냥처럼 **판정 쪽에서 돈다** — 화면이 꺼져도(모바일) 마셔야 한다.
- **칸 오른쪽 위 "설정"** → 가운데에 설정 창. -/+ 단추와 **슬라이더**(`HSlider`, 같은 날 요청)로
  기준을 **10%p 씩, 0 ~ 90%** 고른다. 0 이 "자동 끔". 슬라이더를 끌면 칸마다 `potionPct` 를 보내고,
  돌아온 값은 `set_value_no_signal` 로 손잡이에 맞춘다 (신호를 내면 되보내는 되먹임이 된다).
- **빼기 단추 글자는 ASCII `-`** 다 ★ — 빼기 기호 `−`(U+2212)는 한글 폰트 부분집합
  (`NotoSansKR-subset.ttf`)에 없어 **빈 단추로 나왔다** (2026-09-26 지적). `ui_test` 가 글리프를 본다.
  칸 아래 배지가 지금 기준(`HP 90%` / `자동 끔`)을 적는다. 값은 `potionPct` 요청으로 보내고
  **판정(`set_potion_pct`)이 잘라서** 스냅샷으로 돌아온 값만 그린다 (자동사냥 칸과 같은 규칙).
- **수치**는 shared `combat.ts` 의 `POTION_*` → `combat.json` 의 `potion*`:
  쿨타임 10초 · 한 병에 **최대 HP 10%** · 처음 기준 **90%** · 폭 10 · 상한 90.
  (처음에는 30% · 50% 였다 — 같은 날 "초기값 70%로 하고 물약 한번 마시면 10% 차도록" 요청으로 바꿨다. 2026-09-30 에 "물약 사용 기본 설정을 90%로" 요청으로 90% 가 됐다.)
- **개수는 세지 않는다** — 요청에 개수·구매가 없었다. 쿨타임만 막는다. 상점에서 사게 하려면
  아이템·가방 칸이 같이 흔들린다 ([items.md](items.md), [npc-town.md](npc-town.md)).
- 회복은 회복기와 같은 `hit`(`heal: true`) 이벤트로 알린다 — 초록 숫자가 뜬다. 이때 **움찔 동작
  (`_start_hit`)은 틀지 않는다** (회복을 맞은 것으로 치던 것을 같이 막았다).
- 기준은 **저장에 남는다** (`save.gd` 의 `potion_pct`, 없던 칸이라 옛 저장은 처음 값 90).
  쿨타임은 존을 옮겨도 이어진다 (`join` 의 `kept`) — 차원문을 오가며 연달아 못 마신다.
- 아이콘 `ui_icon_potion` — 둥근 유리병 · 코르크 · 붉은 물약 (2026-09-26, 바르코). **2026-09-28 에
  리니지풍으로 다시 뽑았다** (위 "메뉴 아이콘" 의 참고 그림 · 틀). 주소는 `fetch-assets.sh`, 등록은
  `sync-godot-assets.mjs` 의 `ICONS`. 그림을 안 받은 사람에게는 글자 "물약" 이 나온다.

## 소리 설정 (2026-09-30)

요청: "볼륨 조절 하는 기능 추가해".

- **자리** — 오른쪽 위 메뉴 **맨 끝**의 "설정" 단추 → 가운데 창. 물약 설정 창과 같은 틀
  (-/+ 단추 · 가운데 글자 · `HSlider`). 0 ~ 100, **10 씩**. **처음 값은 70** (`SoundSettings.DEFAULT` —
  처음엔 100 이었는데 같은 날 "기본 볼륨을 지금의 70%로" 요청으로 줄였다. 이미 고른 기기는 제 값 그대로).
  0 이면 "소리 끔" — 버스를 음소거한다
  (`linear_to_db(0)` 이 -inf 라 따로 막는다).
- **전체(Master 버스) 하나만** 둔다 — 지금 소리가 타격음(`hit.wav`) 하나뿐이다. 배경음이 생기면
  버스를 나누고 줄을 더한다.
- **판정이 아니라 기기 설정이다** ★ — 서버에 보내지 않고, 캐릭터 저장(`save.gd`, 판정 값만)에도
  넣지 않는다. `user://settings.cfg` 의 `[sound] volume` 에 둔다 (웹은 브라우저마다 따로).
  게임을 켤 때 `_ready` 가 저장된 값을 버스에 건다.
- **아이콘 `ui_icon_settings` 는 아직 없다** — 그림이 없으면 네모가 비고 이름 글자 "설정" 만 선다.
  그리면 HUD 아이콘 기준("메뉴 아이콘")대로 바르코로 뽑아 `ICONS` 에 올린다.

## 채팅창 (2026-09-23) ★

**화면 왼쪽 아래 구석**, 경험치 띠 바로 위(380×170). 장비를 얻으면
`장비 획득 희귀 무기` 가 한 줄씩 적힌다 (`ChatLog`). **경험치는 2026-09-28 에 여기서 뺐다** —
아래 "경험치 알림".

```
│ [테스트: 스킬 범위] … [테스트: 쿨타임 0]   ← 채팅창 바로 위로 올렸다
│ ┌ 장비 획득  희귀 무기 ──────┐
│ │ 강화 성공  +3 흑철 건틀릿   │  ← 새 줄이 맨 아래, 창은 늘 맨 아래를 따라간다
│ └───────────────────────────┘          [Lv.1] [체력] [퀵슬롯]
├■■■■──── 경험치 0.73% ─────────────────────────────┤
```

- **왜 여기인가.** 같은 날 두 번 옮겼다. 쓰러진 자리의 3D `+n EXP` →
  **"데미지랑 같이 뜨니까 안 보여. 왼쪽에 ui 를 만들어서 넣어"** → 왼쪽 위에
  잠깐 떴다 지는 띠 → **"왼쪽 아래 채팅창 만들어서 거기에 넣어"**.
  가운데는 전투(피해 숫자)가 쓴다 → [hit-effects.md](hit-effects.md)
- **줄은 사라지지 않는다** — 채팅창이라 지나간 것도 남는다. `MAX_LINES` 50 줄을
  넘으면 오래된 것부터 지운다.
- **테스트 단추 묶음은 채팅창 위로 올렸다** (`_build_test_switches` 의 `lift`).
  구석이 채팅창 자리가 됐기 때문이다. 2026-09-25 부터는 채팅창 바로 위에
  **치트 목록 여닫기 단추**가 서고 묶음은 그 위다 → [play-mode.md](play-mode.md).
  `ui_test` 가 "여닫기 단추가 채팅창 바로 위 · 쿨타임 단추가 여닫기 단추 바로 위" 를 본다.
- **결** — `ui-art-style.md` 의 어두운 판(`#191a19`, 72% 불투명) + 1px 금테
  (`#b9a46c`). 조각 그림 없이 `StyleBoxFlat`. 글자는 `RichTextLabel` —
  머리말은 눌린 상아빛, 값만 색을 준다 (경험치 **청록 `#62e0cc`** · 장비는 **등급 색**).
- **경험치는 청록이다.** 처음엔 경험치 띠와 같은 금빛이었는데 영웅 등급 금색과
  나란히 서면 구분이 안 됐다. 흰빛은 고급(옅은 회청)과 가까웠다. 청록은 등급 일곱 색
  어디에도 없다 — `chat_log_test` 가 등급 색과의 거리를 잰다.
- **장비 이름에는 등급 글자가 없다**("흑철 건틀릿") — **색이 등급을 알린다**
  (`ChatLog.grade_text_color`). 표의 등급 색(`Items.grade_color`)은 어두운 흙빛이라
  그대로면 판에 묻히므로 **색상은 그대로 두고 밝기만 올린다.** 흰색을 섞으면 등급끼리
  다 옅어져 비슷해 보인다 → [items.md](items.md) 의 이름 표.
  **가방 칸 테두리·상세 창 이름(`game.gd` 의 `_grade_tint`)도 같은 식을 쓴다** (2026-09-23 에 맞췄다).
- **골드는 안 적는다** — 요청이 경험치와 장비였다. 골드는 위 글자줄에 그대로 있다.
  가방이 꽉 차 장비를 못 받으면 `loot` 에 `item` 이 없어서 줄도 안 생긴다.
- **창은 입력을 받지 않는다**(`MOUSE_FILTER_IGNORE`) — 창을 눌러도 밑의 땅이 눌려야 창 뒤로 걸어간다.
- **서버에 붙었을 때만 맨 아래에 입력칸이 선다** (2026-09-28, `set_online` ← `Transport.online`).
  혼자 노는 판(GitHub Pages)에는 말 걸 사람이 없어서 안 보인다. **입력칸만** 터치를 받는다.
  결은 창과 같다 — 어두운 판(90%) + 1px 금테, 누르면 테가 `#dfc97a` 로 밝아진다, 글자 상아빛,
  빈 칸에 흐린 "말하기". 100자까지. 보내면(Enter · 폰 키보드 완료) 칸을 비우고 **손을 뗀다** —
  폰 키보드가 내려가고 퀵슬롯 단축키(1~4)가 다시 먹는다.
- **남의 말**은 머리말 자리에 이름(`모험가#AB12`) + 상아빛 말, **알림**은 `알림` + 금빛(`#e3d092`)
  — 강화 +7 이상 성공 같은 것. 말은 **글자 그대로** 적힌다(BBCode 로 읽지 않는다) → [server.md](server.md) "채팅".
- **스크롤은 아직 없다** — 창이 터치를 받으면 창 뒤로 못 걷는다. 지나간 줄을 올려 보게 하려면
  스크롤 막대만 터치를 받게 하는 식으로 따로 짓는다.

## 경험치 알림 (2026-09-28) ★

**화면 오른쪽 아래**, 경험치 띠 바로 위. 몬스터를 잡으면 `경험치를 얻었습니다 (+12)` 한 줄이
떠서 **2.5초 머물고 0.6초 동안 옅어져 사라진다** (`ExpToast`).

```
│                                       경험치를 얻었습니다 (+8)  │ ← 앞 줄은 위로 밀린다
│   [Lv.1] [체력] [퀵슬롯]               경험치를 얻었습니다 (+12) │ ← 새 줄이 맨 아래
├■■■■──── 경험치 0.73% ─────────────────────────────────────────┤
```

- **왜 여기인가.** 요청: "경험치를 채팅창에 띄우지 말고, 스크린샷에 파란 박스와 같은 위치에 …
  잠깐 텍스트가 나왔다 사라지는 형식으로". 받은 스크린샷(메이플의 "메소를 얻었습니다 (+1955)")의
  파란 상자가 오른쪽 아래, 단축키 줄 바로 위였다. 채팅창에 쌓이던 경험치(한 마리에 한 줄)가 장비 줄을
  밀어 올려 묻었다.
- **판 없이 글자만**, 오른쪽 끝에 맞춘다 — 스크린샷대로. 땅 위에서 읽히게 **검은 테**(4px)를 두른다.
  색은 스크린샷의 **옅은 금빛 `#f3dc7a`** (채팅창 시절의 청록은 등급 색과 섞이지 않게 고른 것이라
  장비 줄이 없는 여기서는 쓸 까닭이 없다. 청록은 순위표의 내 줄에 남아 있다).
- 너비 320px, 글자 16. 한꺼번에 여럿 잡아도 **6줄까지** — 넘으면 가장 오래된 줄부터 지운다.
- **터치를 받지 않는다**(`MOUSE_FILTER_IGNORE`) — 글자 뒤의 땅이 눌려야 한다.
- 장비 획득·강화 결과는 그대로 채팅창에 적힌다 (요청이 경험치만이었다).

## 확인

- `npm run test:godot -- ui` — 자리·숫자·안 겹침·고리가 도는지까지 수치로 본다.
- `npm run test:godot -- chat_log` — 채팅창.
- `npm run test:godot -- exp_toast` — 경험치 알림.
- `npm run shot:godot -- kill` — 한 대 잡고 장비 두 개를 넣은 화면
  (`logs/shot_kill_*.png`, 채팅창은 왼쪽 끝이라 `shot_sheet` 에서는 잘린다).
- `npm run shot:godot -- hud` — **눈으로 본다.** 자동사냥을 켜고 액션바를 채운
  채로 세 프레임을 뽑아 `logs/shot_*.png` 에 남긴다. 위의 "잘렸다"·"덮였다" 는
  전부 수치로는 통과한 것들이라 찍어서야 알았다 → [verification.md](verification.md)

## 메뉴 판 (2026-10-01) ★

요청: 다른 게임의 메뉴 스크린샷 둘 + "이런식으로 나열해. 오른쪽 위에 x버튼을 평소에는 … 3줄 짜리 ui 아이콘
만들고 누르면 … 아이콘 나열되게 바꿔". 평소 그림은 아이콘 넷 + ≡, 누른 그림은 어두운 판에 그 넷 + X 가 맨 위에,
구분선 아래로 나머지가 4열이다.

```
 평소   [정보][스킬][가방][던전][≡]
 펼침 ┌─────────────────────────────┐
      │[정보][스킬][가방][던전][X] │ ← 평소 줄이 판 위에 그대로 얹힌다 (판 맨 위는 빈 자리 `bar_room`)
      │─────────────────────────────│
      │[강화][크리스탈][헬스][도감]│ ← `MENU_SHEET_COLUMNS` 4열, 열 간격 6 = 평소 줄과 같아 칸이 줄 아래에 맞는다
      │[샌드백][랭킹][설정]        │ ← 샌드백(랭킹전)은 2026-10-02 (sandbag.md). 랭킹은 서버에 붙었을 때만
      └─────────────────────────────┘
```

- 어느 것이 평소 줄에 서는지는 **이름으로** 고른다 — `MENU_QUICK`(정보 · 스킬 · 가방 · 던전). 빨간 점이 붙는 둘
  (스킬 · 가방)이 늘 보이게 했다. `_menu_cells` 순서(정보 · 스킬 · 강화 · …)는 그대로 둔다 — 테스트가 번호로 본다.
- 판은 `_build_menu_sheet` 가 짓는다. 어두운 판 + 얇은 금테(`StyleBoxFlat`, [ui-art-style.md](ui-art-style.md)).
  평소 줄보다 **먼저** 달아서 줄이 판 위에 얹힌다. 판 맨 위 빈 자리는 줄의 `resized` 를 따라 크기가 맞는다.
- **판 안 단추를 누르면 그 창이 열리고 판은 접힌다** (`_close_menu` 를 같이 잇는다). X 로도 접힌다.
- ≡ · X 는 글자 줄이 없어서 `SIZE_SHRINK_BEGIN` — 아이콘 높이(위)에 맞춘다.
- **왜:** 단추가 아홉이 되자(도감 추가) 기준 화면(1280)에서 줄이 위쪽 가운데 "마을가기" 와 겹쳤다. 판으로 접으니
  평소 줄은 다섯 칸이다.
- 테스트: `ui_test` — 평소 줄 구성 · 처음엔 접힘 · ≡ → 판·X · 판이 화면 안 · 판 첫 칸이 줄 첫 칸 아래 · 판 안 강화 ·
  크리스탈이 나란함 · 판 안 단추를 누르면 접힘 · X 로 접힘. 마을가기 겹침 검사는 **보이는 칸만** 본다.
- 확인 사진: `npm run shot:godot -- menu` → `logs/shot_menu.png`.

## 마을가기 (2026-09-29) ★

요청: "사냥터에 들어가면 포탈을 제거해. HUD 윗 부분에 마을가기 버튼을 만들어서 마을 갈 수 있는 기능
만들어". 사냥터에 차원문이 없어져서 **사냥터에서 나오는 길은 이 단추뿐**이다 ([world-zones.md](world-zones.md) "차원문").

- 자리: **위쪽 가운데** (`PRESET_CENTER_TOP`, 위에서 20px), 140 × 48 (`HOME_BUTTON_SIZE`). 왼쪽 위는
  상태 글자 줄, 오른쪽 위는 메뉴라 가운데가 비어 있다.
- 생김새: 단추 조각(`ui_button`) 9조각 + `Label` 글자 "마을가기" (`_make_button` — 던전 "입장" 과 같은
  조각). 그림이 없으면 `_frame_box` 가 코드로 그린 판을 준다. **새 그림은 만들지 않았다** — 아이콘이
  필요하면 [ui-art-style.md](ui-art-style.md) 의 메뉴 아이콘 결로 바르코에서 뽑는다.
- **마을 밖에서만 보인다** — 존을 지을 때(`_build_zone`)마다 `_refresh_home_button` 이 다시 본다.
  던전·전직 시험에서도 보인다.
- 누르면 `_go_village` → `_on_gate_pick(GameData.start_zone())` — 차원문 창에서 마을을 고른 것과 같은
  `travel` 요청이고, World 가 다시 본다.
- 테스트: `ui_test` 의 `_check_home_button`(위쪽 가운데 · 화면 안 · 메뉴와 글자 줄과 안 겹침)과
  `_case_home`(던전에서 눌러 마을로, 마을에선 숨음). 차원문 목록에서 사냥터를 고른 뒤에도 이 단추로 돌아온다.

## 손댈 때

- 막대를 하나 더 달면 `_make_bar` 에 색과 높이만 준다. 높이는 `글자 + 10` 이상이고
  **테 두께의 두 배**보다 높아야 한다.
- 메뉴 단추를 더하면 `_menu_cells` 에 넣는다 — 테스트가 그 배열을 본다.
- 퀵슬롯 칸 수는 `GameData.combat().skillBarSize` 가 정한다 ([skills.md](skills.md)).

## 관련

- [skills.md](skills.md) — 퀵슬롯 칸·쿨타임 연출·스킬창
- [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md) — 자동 사냥 판정
- [portal-ui.md](portal-ui.md) — 창을 조각으로 조립하는 같은 규칙
- [verification.md](verification.md) — 찍어서 보는 방법
