# 메인 HUD

## 무엇

게임 화면 위에 늘 떠 있는 것들 — **왼쪽 위 상태판**(초상·레벨·체력·경험치),
**오른쪽 위 메뉴**(스킬·가방), **아래 가운데 퀵슬롯 4칸과 자동사냥 칸**이다.

2026-09-19 요청으로 지었다. 그 전에는 화면 왼쪽 위에 `Label` 한 줄로
`마을 1레벨 체력 120/120 경험치 0/55` 를 적고, 그 아래 밋밋한 `ProgressBar`
하나가 있었다. 스킬·가방·자동사냥은 **오른쪽 아래 글자 단추 셋**이었다.

```
┌ [초상 Lv.N] [■■■■ 체력 72/120 ]                     [스킬] [가방] ┐
│             [■■   경험치 12695/31739]                              │
│ 마을  골드 0  몬스터 0/0  60 fps  빌드 <커밋> <시각>                │
│ <마지막에 일어난 일 한 줄>                                          │
│                                                                    │
│                  [퀵1][퀵2][퀵3][퀵4] [자동사냥]                    │
└────────────────────────────────────────────────────────────────────┘
```

## 어디

| 파일 | 역할 |
|---|---|
| `godot/game/game.gd` | `_build_status` / `_make_bar` / `_refresh_status` — 왼쪽 위 상태판 |
| ″ | `_icon_button` — 오른쪽 위 메뉴 단추 하나 (`_menu_cells` 에 담는다) |
| ″ | `_build_skill_bar` — 퀵슬롯 4칸 + 자동사냥 칸(`_auto_cell`)과 고리(`_auto_spin`) |
| ″ | `_refresh_auto` / `_process` — 켜짐 표시와 고리 돌리기, `SpinRing`(그림이 없을 때) |
| `godot/tests/ui_test.gd` | `_case_status` — 자리·숫자·안 겹침·눌러서 창 열기 |
| ″ | `_run_scene` 의 자동사냥 대목 — 켜면 고리가 보이고 **각이 변한다** |
| `godot/tools/shot.gd` | `_hud` — 자동사냥을 켠 채로 화면을 뽑는다 (`npm run shot:godot -- hud`) |
| `scripts/sync-godot-assets.mjs` | `ICONS` — 조각 이름을 여기 적어야 `godot/assets` 로 간다 |
| `scripts/build-item-icons.mjs` | `FRAME_SIZE` · `HOLLOW` — 조각을 굽는 설정 |
| `scripts/fetch-assets.sh` | 조각 일곱 장의 결과물 주소 |

## 규칙

### 조각으로 조립한다 ★

그림 한 장으로 그린 HUD 를 붙이지 않는다 (CLAUDE.md, [portal-ui.md](portal-ui.md)
의 같은 규칙). 해상도가 바뀌어도 앵커로 자리를 잡아야 한다.

```
상태판  HBox(왼쪽 위 20,18)
 ├ PanelContainer(ui_portrait) ─ MarginContainer ─ ui_figure
 │                              └ MarginContainer ─ Label "Lv.N"
 └ VBox ─ PanelContainer(ui_bar_frame) ─ TextureProgressBar(ui_bar_fill) ─ Label
        └ 같은 것 하나 더 (경험치)
메뉴    HBox(오른쪽 위) ─ PanelContainer(ui_button) ─ ui_icon_skill / ui_icon_bag
퀵슬롯  HBox(아래 가운데) ─ 칸 4개 + 자동사냥 칸 (전부 `_make_skill_cell`)
```

- **글자는 이미지에 굽지 않는다.** 레벨·체력·경험치는 전부 `Label` 이다.
- **조각이 없어도 돈다.** `npm run sync:godot` 을 안 돌렸으면 테두리는 코드로 그린
  판(`_frame_box`), 막대 채움은 흰 판(`_white`), 고리는 `SpinRing` 이 그린 화살표
  둘이다 — 모델이 없으면 기둥으로 그리는 것과 같은 규칙이다.

### 막대 채움은 흰 그림 한 장이다 ★

붉은 체력과 금빛 경험치를 따로 뽑지 않는다. 회색 광택 캡슐 한 장(`ui_bar_fill`)을
`tint_progress` 로 물들인다 — 체력 `#d2402c`, 경험치 `#e8c14a`. 광택을 두 번
맞출 필요가 없고, 나중에 기력·물약 막대가 생겨도 색만 정하면 된다.

채움은 끝이 둥글어서 통째로 늘이면 끝이 뭉개진다 → `nine_patch_stretch` 로
좌우 24px 만 남기고 가운데를 늘인다.

### 숫자가 잘리지 않을 높이 ★

경험치 막대를 22px 로 뒀더니 **다섯 자리 숫자가 위아래로 잘렸다**(2026-09-19,
찍어서 봤다). 테두리 안쪽 여백(`BAR_PAD` 5)을 빼면 글자가 쓸 수 있는 높이는
`높이 - 10` 이다. 지금은 체력 32(글자 18) · 경험치 27(글자 14).

### 상태판은 한 곳에서만 그린다

레벨·체력·경험치는 `_refresh_status` 하나가 스냅샷을 보고 그린다. `_label` 에서
같은 값을 지웠다 — 두 곳에 적으면 한 쪽만 고치고 끝난다. `_label` 에 남은 것은
**존 이름·골드·몬스터 수·fps·빌드 표시**다. 빌드 표시는 지우면 안 된다
([godot-migration.md](godot-migration.md) 의 "지금 보는 것이 어느 빌드인지").

### 자동사냥은 퀵슬롯과 같은 칸이다 ★

오른쪽 아래 글자 단추였던 것을 **퀵슬롯 옆 다섯 번째 칸**으로 옮겼다 (요청이
그랬다). 엄지가 퀵슬롯과 같은 높이에서 닿는다. 칸은 스킬 칸과 같은
`_make_skill_cell` 로 짓는다 — 테두리·배지·누르는 자리가 그대로 맞는다.

- **아이콘만 더 물린다** (`AUTO_INSET` 27, 퀵슬롯은 `SKILL_INSET` 11). 11 로 두면
  고리가 아이콘 위를 덮어 **검도 과녁도 안 보였다** (2026-09-19, 찍어서 봤다).
- **칸 가운데 아래 배지**가 `자동` ↔ `켜짐` 으로 바뀐다.
- 켜짐을 **칸 전체 초록 `modulate`** 로 알리던 것은 뺐다 — 고리와 아이콘이 한
  덩어리로 보여 무엇이 도는지 알 수 없었다.

### 켜지면 고리가 돈다 ★

`ui_auto_spin`(서로 쫓는 화살표 둘)을 칸 위에 얹고 `_process` 에서
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

## 조각 일곱 장

바르코로 만들었다 (`nano-banana-pro`). 결과물 주소는 `scripts/fetch-assets.sh` 에
박혀 있다 — 다시 찾을 필요가 없다.

| 이름 | 무엇 | 굽는 설정 |
|---|---|---|
| `ui_portrait` | 육각 초상 테두리 | 192 · 안쪽을 뚫는다(HOLLOW) |
| `ui_bar_frame` | 막대 홈 | 256 · 안쪽을 뚫는다 |
| `ui_bar_fill` | 광택 캡슐 (흰색) | 256 |
| `ui_icon_skill` | 룬이 떠 있는 책 | 128 |
| `ui_icon_bag` | 배낭 | 128 |
| `ui_icon_auto` | 검과 과녁 | 128 |
| `ui_auto_spin` | 도는 화살표 둘 | 192 · 가운데를 뚫는다 |

**참고 그림을 물리려면 업로드가 온전해야 한다** ★ — `ui_slot` 을 참고로 넣어
돌렸더니 다섯 장이 통째로 실패했다 (2026-09-19). 잘린 PNG 를 올린 탓이었고,
참고를 떼고 프롬프트에 스타일을 적어 다시 돌리니 한 번에 나왔다.

## 확인

- `npm run test:godot -- ui` — 자리·숫자·안 겹침·고리가 도는지까지 수치로 본다.
- `npm run shot:godot -- hud` — **눈으로 본다.** 자동사냥을 켜고 액션바를 채운
  채로 세 프레임을 뽑아 `logs/shot_*.png` 에 남긴다. 위의 "잘렸다"·"덮였다" 는
  전부 수치로는 통과한 것들이라 찍어서야 알았다 → [verification.md](verification.md)

## 손댈 때

- 막대를 하나 더 달면 `_make_bar` 에 색과 높이만 준다. 높이는 `글자 + 10` 이상.
- 메뉴 단추를 더하면 `_menu_cells` 에 넣는다 — 테스트가 그 배열을 본다.
- 퀵슬롯 칸 수는 `GameData.combat().skillBarSize` 가 정한다 ([skills.md](skills.md)).

## 관련

- [skills.md](skills.md) — 퀵슬롯 칸·쿨타임 연출·스킬창
- [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md) — 자동 사냥 판정
- [portal-ui.md](portal-ui.md) — 창을 조각으로 조립하는 같은 규칙
- [verification.md](verification.md) — 찍어서 보는 방법
