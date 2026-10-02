# UI 아트풍 (굳힌 것)

## 무엇

2026-09-20 에 사용자가 **"지금 느낌 좋다, 이렇게 아트풍 저장해"** 라고 한 그 결이다.
HUD 와 NPC 창이 이것으로 되어 있고, **앞으로 만드는 UI 는 전부 여기에 맞춘다.**
**스킬창은 2026-09-28 에 던전 창 결(닳은 돌판)로 바꿨다** → [skills.md](skills.md) "스킬창과 퀵슬롯".
**단, 가방의 세 창은 2026-09-23 에 받은 그림대로 "인벤토리 결" 로 바꿨다** → 아래 절.
**2026-09-28 에 가방 창과 스킬창, 이어서 나머지 창까지 전부 "던전 결"(닳은 돌판)로 바꿨다** → 아래 "창은 던전 결".

한 줄로: **어두운 판 + 머리카락처럼 얇은 금테 + 상아빛으로 칠한 아이콘.**

> ★★★ **HUD 아이콘은 아래 "HUD 아이콘 기준 (2026-09-29)" 이 앞으로의 기준이다** — 사용자가 "지금 느낌 좋다.
> HUD는 앞으로도 지금 스타일로 만들자" 라고 했다. 이 인용 블록의 나머지와 "아이콘 결 (2026-09-28)" 절은 그 전 기록이다.
>
> ★★ **아이콘은 2026-09-28 부터 기준이 바뀌었다 — "리니지풍 칠한 아이콘".** 사용자가 다른 게임의
> 메뉴 스크린샷(상점 돈주머니 · 인벤토리 가방 · 스펠 마법서 · 퀘스트 두루마리)을 주며 "지금 아이콘
> 마음에 안 들으니까 저런식으로", 이어서 "**앞으로 기준**" 으로 삼으라고 했다.
> **2026-09-29 에 HUD 아이콘을 한 번 더 받은 그림(세력 탑 · 커뮤니티 · 랭킹 트로피 · PVP 검)대로 갈았다** —
> 부드럽게 칠한 반실사이고, **색은 전부 세피아 단색조 한 줄기**(`#24170a` ~ `#ddd0b3`, 상아·카키·바랜 놋쇠)다 —
> 아이콘마다 제 색을 칠했다가 "색감이 통일되어 있자나" 라는 지적을 받고 다시 칠했다. 참고 그림 · 팔레트 띠 주소와
> 프롬프트는 [hud.md](hud.md) "지금은 칠한 반실사 결". **새 HUD 아이콘은 그 틀을 쓴다** (청동 문장 결은 폐기).
> (그 전 문장: 새로 만드는 아이콘은 전부 "아이콘 결 (2026-09-28)" 절을 따른다 — **지금은 "HUD 아이콘 기준 (2026-09-29)"**.) 판·칸·테두리(어두운 판 +
> 얇은 금테)는 그대로다 — 받은 그림은 아이콘만 보여 줬다. 이 절 아래의 "아이콘류" 프롬프트와
> 상아빛 참고 그림은 **옛 결**이라 새 아이콘에 쓰지 않는다.

## HUD 아이콘 기준 (2026-09-29) ★★★

**"지금 느낌 좋다. HUD는 앞으로도 지금 스타일로 만들자"** (2026-09-29). 오른쪽 위 메뉴 · 자동사냥 · 물약 ·
던전 문 열한 장이 이 결이다. **HUD 에 새 아이콘을 넣거나 갈 때는 이 절 그대로 한다 — 결을 새로 짓지 않는다.**

| | |
|---|---|
| 그림 | 손으로 부드럽게 칠한 반실사 **물건 하나**. 실루엣이 단순하고 잔세공이 적다 (42~62px 에서 읽혀야 한다) |
| 색 ★ | **세피아 단색조 한 줄기** — `#24170a` · `#504330` · `#6a5b47` · `#847965` · `#a59a82` · `#c2baa5` · `#ddd0b3` (상아·카키·바랜 놋쇠). 물건 제 색(파랑·보라·빨강·번쩍이는 금)을 칠하지 않는다. 색은 **점 하나**(흐린 청록·검붉은 보석, 3% 미만)까지만 |
| 빛·각 | 왼쪽 위 부드러운 빛, 약간 비스듬한 3/4 (해골·X 검·문처럼 정면이 읽히는 것은 정면) |
| 바탕 | 흰 바탕으로 받아 `build-item-icons.mjs` 가 걷는다. 판·원판·테 없음 |
| 글자 | 그림에 안 굽는다 — 메뉴는 아래 줄 `Label` ([hud.md](hud.md) "메뉴 아이콘") |

**참고 그림 둘을 같이 물린다** (둘 다 바르코에 올라가 있다 — 다시 올리지 않는다):

1. 받은 스크린샷(세력 탑 · 커뮤니티 · 랭킹 트로피 · PVP 검): `https://3d.varco.ai/api/objects/7cb46959217839da3aa126a3a6a909eb.jpg`
2. 팔레트 띠(위 일곱 색): `https://3d.varco.ai/api/objects/ba3adc8e23e0f960db7f48563bb129da.png`

**노드** (카탈로그를 다시 안 읽어도 되게): `TextInput`(`value` = 프롬프트) → `GenerateImage.prompt`,
`ImageInput`(`value` = 위 주소) 둘 → `GenerateImage.reference` (**스크린샷을 먼저** 잇는다 — "FIRST REFERENCE"),
`GenerateImage` 의 intrinsic 은 `count` · `aspectRatio` · `model`. 결과는 `get_output_downloads` 에 `nodeId` 를 줘서 받는다.

**프롬프트** — `GenerateImage`, `nano-banana-pro`, 1:1, **세 장**. `<무엇>` · `<쓰임>` 만 간다
(정면인 것은 `Slight three-quarter view` 를 `Front view` 로):

```
Mobile MMORPG HUD menu icon: <무엇>, meaning '<쓰임>'. MATCH THE FIRST REFERENCE IMAGE'S ART STYLE EXACTLY
(its castle tower, group of people, trophy and crossed swords): a softly hand-painted semi-realistic game
icon with gentle light from the upper left, smooth soft matte shading and a clean, simple, bold silhouette
with little fine detail. COLOR: use ONE unified, muted sepia palette, shown as swatches in the second
reference image: dark umber shadows (#24170a, #504330), khaki-taupe midtones (#6a5b47, #847965), pale
parchment-ivory highlights (#a59a82, #c2baa5, #ddd0b3) — like aged bone and pale worn brass, low saturation.
No bright red, no saturated blue, no purple, no orange, no vivid yellow gold, no pure white highlights.
At most one tiny accent spot of muted teal or deep dull red, covering less than 3% of the icon.
Slight three-quarter view, centered, fills the frame, readable at 60 pixels. One object standing alone —
it must NOT sit on any disc, circle, plate, badge, frame or panel. Isolated on a flat pure white background;
everything outside the object is pure white, the four corners must be pure white. Do not copy the swatches,
captions or dark background of the references: no text, no letters, no numbers.
```

고르고 넣는 법:

- **팔레트 띠를 그려 오는 장이 가끔 있다** (던전 문 세 장 중 하나) — 그래서 세 장을 뽑아 거른다.
- 모양이 마음에 드는데 색이 튀면 새로 뽑지 말고 **`EditImage` 로 색만 다시 칠한다** — 지시문은 [hud.md](hud.md) "색은 한 줄기".
- 굽고 나서 **받은 스크린샷 옆에 42px 로 나란히 놓고** 색감이 한 줄기인지, 작게도 읽히는지 본다 (확인용 한 장).
- 고른 해시는 `scripts/fetch-assets.sh`, 그림 표는 [hud.md](hud.md) "지금은 칠한 반실사 결".

## 아이콘 결 (2026-09-28) — 옛 기준, 기록

| | |
|---|---|
| 그림 | **손으로 칠한 반실사** 물건 하나 — 선화·문장(紋章)이 아니다 |
| 색 | 낡은 가죽 갈색 · 양피지 베이지 · 바랜 금 · 짙은 빨강. 물건 제 색(크리스탈 보라, 물약 빨강)이 초점 |
| 빛 | 왼쪽 위, 부드러운 어두운 그늘 가장자리 |
| 각 | 약간 비스듬한 3/4 (정면 기호인 X·해골은 정면) |
| 바탕 | **흰 바탕으로 받아** 굽는 스크립트가 걷는다 — 그늘이 검어서 검은 바탕이면 그늘까지 먹힌다 |
| 글자 | 메뉴 단추는 아이콘 **아래 줄**에 `Label` 로 (흰 글자 + 검은 테) → [hud.md](hud.md) "메뉴 아이콘" |

- **참고 그림**(받은 스크린샷 그대로): `https://3d.varco.ai/api/objects/6c80e88d6bc567159a81261d4b2f02b6.jpg`
  — `ImageInput` 에 넣어 물린다. 한글 글자가 들어 있어서 프롬프트에 `Ignore the captions in the reference` 를 넣는다.
- **프롬프트 틀**은 [hud.md](hud.md) "메뉴 아이콘" 에 있다 (`<무엇>` · `<쓰임>` 만 간다).
- 이 결로 만든 것: 오른쪽 위 메뉴 일곱 장, 이어서 HUD 나머지 셋 — 자동사냥(`ui_icon_auto`) ·
  물약(`ui_icon_potion`) · 창 닫기 X(`ui_close`) (모두 2026-09-28). 그 뒤 청동 문장 결을 거쳐
  **2026-09-29 에 "칠한 반실사 결"** 로 다시 갈았다 → [hud.md](hud.md) "지금은 칠한 반실사 결". 참고 그림은 그쪽 주소를 쓴다.

여기까지 오는 데 네 바퀴가 걸렸다. 지적받은 것을 순서대로 적어 둔다 —
**다시 만들 때 같은 길을 또 돌지 않으려고** 남기는 문서다.

| 시도 | 지적 |
|---|---|
| 청록 발광 + 두꺼운 테 | — (첫 판) |
| 낡은 쇠 + 두꺼운 금테 | "테두리가 너무 두꺼워" |
| 얇은 금선 + 검은 선화 아이콘 | "가방이랑 스킬 아이콘이 왜 검정색이야" |
| 얇은 금선 + 칠한 아이콘 | "아까 칼/가방처럼. 아예 새로운 풍으로 만들지 말고" |
| **지금** | "지금 느낌 좋다" |

## 창은 던전 결 (2026-09-28) ★★

요청 셋이 이어졌다: "스킬 UI도 던전 UI와 비슷한 아트풍으로" → "가방 UI도" → "**나머지 창들도**".
그래서 **창(떠서 닫는 것)은 전부 던전 창의 결**이다. HUD(퀵슬롯·메뉴·체력 막대)는 창이 아니라 그대로다.

| 조각 | 무엇 | 어디 |
|---|---|---|
| 틀 | 던전 카드 틀 `ui_dungeon_card` 9조각 (여백 `GatePanel.CARD_MARGIN` 34, 안쪽 30 안팎) | `game.gd` `_window_panel` · `GatePanel._build` · 전직/NPC 창 `_build` |
| 제목 | 왼쪽 **문장**(그 창의 메뉴 아이콘) + 상아빛 글자(`PAGE_TITLE_COLOR` `#ece4cc`) + 밑에 가는 선(`HEAD_LINE`) | `_stone_title` · `GatePanel._restyle_title` |
| 칸·상자 | 어두운 평판 + 가는 흙금빛 선 (`CELL_BG` · `CELL_LINE` `#3d3729`) | `_stone_cell_box` · 전직 `_stone_cell` |
| 목록 줄·탭 | 평평한 줄, 고른 것만 옅은 금빛 바탕 + 왼쪽 금 막대 | `GatePanel._row_box` · `_stone_tab_box` |
| 단추 | **청록 돌판** `ui_button` + 주황빛 금 글자(`BUTTON_TEXT` `#f8c878`, 검은 테) — 아래 "단추 결" 절. 40px 단추는 조각을 줄여 쓴다 | `_inv_button` · `_small_button_texture` · `GatePanel._button_box` · `GatePanel.paint_button_text` |

- **상수는 `GatePanel` 한 곳에 있다.** 던전 창이 차원문 창을 물려받아서 거기 두면 둘 다 쓰고,
  다른 창은 `GatePanel.X` 로 가져다 쓴다. 한 곳을 고치면 모든 창이 같이 바뀐다.
- 틀 가장자리가 찢긴 종이처럼 반투명이다. **전체 화면 창(던전·스킬)은 뒤에 불투명한 판**을 깐다.
- 돌판 테가 26~36px 라 **X 를 24px 에 두면 테에 걸친다** — 새 창은 `_close_button(…, 0)` 로 안쪽 모서리에 붙인다.
- 아이콘 칸(스킬 칸 `ui_skill_slot`·`ui_slot`, 고른 칸 금테)은 그대로다 — 던전 보상 칸의 아이콘 테와 결이 같다.
- 아래 "얇은 금테" · "인벤토리 결" 은 **옛 창 결**로 남겨 둔 기록이다 (색·아이콘 규칙은 여전히 쓴다).
- 확인: `npm run shot:godot -- skills|bag|gate|job|shop|char|rank|potion|auto|debug|dungeon`.

## 단추 결 (2026-09-29) ★

사용자가 단추 그림 한 장("인챈트")을 주며 **"UI 버튼을 이런 스타일로"** 라고 했다.
그래서 모든 창이 같이 쓰는 단추 조각 `ui_button` 을 둥근 금테에서 **청록 돌판**으로 갈았다.

한 줄로: **닳은 청록 돌판 + 깨진 모서리 + 안쪽에 새긴 가는 선 + 주황빛 금 글자.**

**테두리가 핵심이다.** 첫 판(반듯한 청록 판)은 "느낌이 달라. 테두리 쪽에 이미지를 추가로 그려놔서
심심하지 않게 만들었다" 는 지적을 받았다. 그래서 두 번째 그림을 물려 다시 뽑았다 — 가장자리가
조금 울퉁불퉁하고, **오른쪽 위·왼쪽 아래 모서리가 깨져 옅게 긁힌 자국과 가는 금**이 있고,
가장자리 안쪽을 따라 **새긴 선**이 한 바퀴 돈다. 가운데 면은 글자가 앉도록 고르다.

| 쓰임 | 값 (받은 그림에서 뽑았다) |
|---|---|
| 판 | 위 `#486662` → 아래 `#3e5755`, 자글자글한 돌 결, 좌우 끝이 조금 어둡다 |
| 위 가장자리 밝은 선 | `#628481` (1~2px) |
| 아래 그늘선 | `#181b1b` ~ `#242f2e` |
| 글자 | `#f8c878` + 검은 테 `#141816` 4px (`GatePanel.BUTTON_TEXT` · `BUTTON_OUTLINE`) |

- **참고 그림**(두 번째로 받은 그림의 단추 부분만 240px JPEG 로 자른 것, 2.1KB, 다시 받아 `cmp` 로
  같음을 봤다): `https://3d.varco.ai/api/objects/6d5f295f2e2f9f84e1ced92151ac76ee.jpg`
  (첫 그림 `ad26567a…jpg` 는 테두리가 작아 안 보여서 반듯한 판만 나왔다)
- 프롬프트는 `MATCH THE REFERENCE IMAGE'S STYLE EXACTLY — the weathered teal stone button in the
  reference, but EMPTY` 로 시작하고 색 값을 박은 뒤 **`THE EDGES ARE THE POINT`** 로 테두리를 하나씩
  적었다 (울퉁불퉁한 윤곽 · 안쪽에 새긴 선 · 깨지고 긁힌 모서리와 가는 금 · 위 밝은 선 · 아래 그늘).
  `All of this detail stays within a narrow band near the border` 로 무늬를 9조각 여백 안에 가뒀고,
  `NO gold rim, NO metal frame, NO gems` 를 넣었다. 16:9 로 두 장 뽑아 모서리가 받은 그림처럼
  오른쪽 위·왼쪽 아래만 깨진 장을 골랐다.
- 구우면 **192x83** 이다 (옛 금테는 192x58). 깨진 자리가 가장자리 14~21px 안에 있어 **9조각 여백 28 이
  무늬를 그대로 품는다** — 가운데만 늘어난다.
- **`WIDE_TOLERANCE` 에서 뺐다.** 모서리의 옅게 긁힌 자국이 흰 배경과 가까워서다.
- 글자색은 `GatePanel.paint_button_text` 한 곳에서 칠한다 — 가방·스킬 단추(`_gold_text`),
  던전 입장, 전직 단추가 이걸 부른다. 옅은 `CARD_GOLD` 는 청록 위에서 묻힌다.
- 조각이 없으면 `_inv_box` 가 같은 청록(`#45605d`)으로 판을 그린다.
- 상점 창의 탭·값표(`npc_panel.gd` `_tag_box`)도 같은 조각이다. 탭 글자색(고름/안 고름)은 그대로 뒀다.

### 단추 움직임 (`godot/game/button_fx.gd` `ButtonFx`, 2026-09-29)

요청: "버튼에 press, release, click 애니메이션 넣어". 청록 단추는 전부 붙어 있다 —
`paint_button_text` · `_make_button` · 상점 탭이 `ButtonFx.attach` 를 부른다.

| 때 | 움직임 |
|---|---|
| 누름 (`button_down`) | 가운데를 축으로 0.92배 (0.07초) |
| 뗌 — 밖에서 떼어 안 눌림 | 튕기듯 제 크기로 (`TRANS_BACK`, 0.18초) |
| 클릭 — 안에서 뗌 (`pressed`) | 1.06배로 부풀었다 제 크기로 + 따뜻하게 번쩍(`self_modulate`, 0.25초) |

- **`scale` 로만 움직인다** — 컨테이너가 안 건드리는 값이라 옆 칸이 안 밀린다.
- 번쩍임은 `self_modulate` 다. `modulate` 는 창이 흐리게 할 때 쓰고 글자까지 번진다.
- `pressed` 와 `button_up` 은 같은 프레임에 오고 순서를 믿을 수 없다. 그래서 뗌은 한 프레임 미뤄서
  클릭인지 보고, 클릭 표시는 **누를 때** 지운다 (뗄 때 지웠더니 `pressed` 가 먼저 오면 클릭을 잃었다).
- **HUD 아이콘도 같은 움직임이다** (같은 날 "HUD 아이콘은 애니메이션 안 들어갔어" 지적).
  메뉴 아이콘(`_icon_button`)·퀵슬롯·자동사냥·물약 칸(`_make_skill_cell`)은 그림 위에 **투명한 `hit`
  단추**를 덮어 누름을 받는다 — 그래서 `ButtonFx.attach(hit, cell)` 로 **칸을 움직인다.** 칸이면 번쩍임은
  `modulate`(아이콘까지 밝게)이고, 원래 색은 클릭하는 순간에 읽는다 — 숨긴 설계 칸(`_design_cell`,
  알파 0)이 붙일 때의 흰색으로 돌아가 보이게 되는 걸 막는다. 칸의 작은 "설정" 단추도 붙였다.
- 검사: `godot/tests/button_fx_test.gd` — 크기·색을 시간에 따라 읽고, 게임 안 청록 단추(27개)와
  HUD 칸(12개)에 전부 붙었는지, 숨긴 칸이 숨은 채인지 본다.

## 색

조각에서 실제로 뽑은 값이다. 새 조각이 이 언저리로 나오면 결이 맞은 것이다.

| 쓰임 | 값 |
|---|---|
| 판 안쪽 (칸·창·배지) | `#191a19` ~ `#202321` (거의 검정에 가까운 **중성** 어두운 회갈색) |
| 테두리 금색 | `#b9a46c` ~ `#dfc97a` |
| 고른 탭·밝은 강조 | `#e3d092` (**글자는 어둡게 얹는다** — `#241f16`) |
| 아이콘 밝은 면 | `#eeead7` (상아) |
| 아이콘 그늘·금속 | `#86714d` |
| 체력 막대 채움 | `#c33122` (흰 채움에 `tint_progress`) |
| 경험치 글자 | `#e8c14a` |

## 규칙 ★★

1. **테는 얇다.** 머리카락 한 올 굵기의 금선 하나. 두꺼운 금속도 리벳도 장식 띠도
   안 쓴다. 모서리 장식은 창 바탕(`ui_panel`)에만 조금 있다.
2. **안쪽은 어두운 판이고, 뚫지 않는다.** 채움·숫자·아이콘이 그 위에 올라간다.
   뚫으면 게임 바닥이 비친다.
3. **아이콘은 테두리 없이 제 색으로 선다.** 원판·배지·액자 위에 앉히지 않는다.
   칠하는 결은 위 "HUD 아이콘 기준 (2026-09-29)" — 상아빛 + 금색 선화 · 청동 문장은 옛 결이다.
4. **글자는 그림에 굽지 않는다.** 전부 `Label` 로 얹는다.
5. **조각이 없어도 돌아간다.** `sync:godot` 을 안 돌린 사람에게는 코드로 그린 판과
   테두리가 나온다 (`_frame_box` 의 폴백, `_white`, `SpinRing`).

## 프롬프트 ★

바르코(`nano-banana-pro`)에 **이 틀을 그대로 넣는다.** `<무엇>` 만 갈아 끼운다.

**판·칸·테두리류**

```
Game UI asset in the reference's style — ivory white and pale gold line work with
thin dark outlines on a dark ground: <무엇>. A dark charcoal <모양> with a THIN pale
gold edge. The edge stays slim — no thick metal, no rivets, no ornament. The inside
is plain dark charcoal, completely empty. Flat 2D, straight-on front view, fills the
frame, isolated on a plain solid white background. No text, no letters, no numbers.
```

**아이콘류**

```
Game menu icon: <무엇>. MATCH THE REFERENCE IMAGE'S STYLE EXACTLY: a flat emblem
filled with ivory white and pale gold, drawn with a thin dark outline. Bold simple
shape that stays readable at small size, straight-on front view, centered, fills the
frame. It stands alone — no disc, no circle, no plate, no frame, no panel behind it.
Everything around the emblem is flat pure black. No text, no letters.
```

빼면 안 되는 문구 넷:

- `it must NOT sit on any disc, circle, plate, badge, frame or panel`
  — 빼면 아이콘이 **크림색 원판 위에 앉아** 나온다.
- `NOT a dark silhouette, NOT black` (아이콘)
  — 빼면 **검은 실루엣**이 되어 밤 사냥터 바닥에 묻힌다.
- `everything outside is pure white, the four corners must be pure white`
  (배경을 걷어야 하는 조각)
  — 빼면 모서리가 검게 남아 화면에 **검은 사각 판**으로 뜬다.
- **어두운 판에는 값과 함께 `NO blue, NO slate, NO grey-blue tint` 를 박는다.** ★
  "dark charcoal" 만 쓰면 모델이 **푸른 슬레이트**(`#2d363d`)로 그린다. 레벨 배지가
  그래서 혼자 푸른기가 돌았고, "다른 UI 들이랑 비슷한 색상으로" 라는 지적을 받았다
  (2026-09-20). 값을 적고(`#191a19`) "칸과 같은 톤" 이라고 쓰면 맞게 나온다.

## 참고 그림 ★★

**말로 설명하지 말고 그림을 물린다.** 말로 고치다 네 바퀴를 돌았고, 그림을 물리니
한 번에 맞았다.

- **오른쪽 위 메뉴 일곱 장은 2026-09-28 에 이 결에서 빠졌다** — 받은 그림대로 리니지풍 칠한
  아이콘 + 아래 글자로 갈았다 → [hud.md](hud.md) "메뉴 아이콘". 그래서 `ui_icon_bag` 은 더 이상
  이 결의 본보기가 아니다 (아래 다시 만드는 명령은 가방 대신 차원문 별 `ui_gate_go` 를 쓴다).
- 지금 결의 참고 그림(X자 검 · 배낭 아이콘 두 장을 어두운 바탕에 붙인 것)은
  **이미 바르코에 올라가 있다. 다시 올릴 필요 없이 이 주소를 `ImageInput` 에 넣으면 된다:**

  ```
  https://3d.varco.ai/api/objects/26d7516cbd9971ad06060eb9da7254da.jpg
  ```

- 이 주소를 그대로 물려 만든 것: 차원문 창의 줄 아이콘 둘
  (`ui_gate_here` 소용돌이 · `ui_gate_go` 별, 2026-09-21), 오른쪽 위 메뉴 셋
  (`ui_icon_character` 투구 · `ui_icon_enhance` 모루 · `ui_icon_design` 컴퍼스, 2026-09-26 — 셋 다 2026-09-28 에 리니지풍으로 갈렸다). **한 번에 맞았다** —
  프롬프트는 아래 "아이콘류" 틀에서 `<무엇>` 만 갈았다 ([portal-ui.md](portal-ui.md)).
- 새로 만들어야 하면 **지금 쓰는 아이콘으로 다시 만든다.**

  ```bash
  node -e "
  const sharp=require('sharp');
  Promise.all([
    sharp('public/assets/icons/ui_gate_here.png').resize(64,64,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).toBuffer(),
    sharp('public/assets/icons/ui_gate_go.png').resize(64,64,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).toBuffer(),
  ]).then(([a,b])=>sharp({create:{width:136,height:72,channels:3,background:{r:26,g:24,b:22}}})
    .composite([{input:a,left:4,top:4},{input:b,left:68,top:4}])
    .jpeg({quality:40}).toFile('/tmp/ref.jpg'));
  "
  ```

- **작아야 올라간다.** `upload_image` 는 바이트를 base64 로 손수 옮기는 길뿐이라
  크면 깨진다. 1024 PNG 는 잘린 채 올라가 다섯 장이 통째로 실패했고(2026-09-19),
  7KB 짜리도 거절당했다. **2KB 남짓(base64 3천 자)이 한 번에 올라간 크기다.**
- **올린 뒤 주소에서 다시 받아 원본과 바이트를 대 본다**(`cmp`). 안 하면 잘린 그림으로
  돌린 것을 결과가 이상해진 다음에야 안다.

## 굽는 설정 (`scripts/build-item-icons.mjs`)

| 설정 | 무엇 | 넣는 것 |
|---|---|---|
| `FRAME_SIZE` | 구울 크기 | 창 바탕 256 · 탭/단추 192 · 칸 128 |
| `SINGLE_LAYER` | 배경을 **한 겹만** 걷는다 | 안쪽이 어두운 판인 것 전부 |
| `WIDE_TOLERANCE` | 배경을 **넓은 폭(96)으로** 걷는다 | 테 바깥에 밝은 회색 번짐이 있는 것 |
| `HOLLOW` | 가운데를 뚫는다 | 고른 칸 테(`ui_slot_pick`) · 고리(`ui_auto_spin`) |
| `FULL` | 배경을 안 걷는다 | 칸을 꽉 채운 그림 (`skill_*`) |

밟은 함정 둘:

- **`ui_panel` 을 `WIDE_TOLERANCE` 에 넣으면 안 된다.** 창 바탕까지 걷혀 금테만
  남고 안이 뚫렸다.
- 두 겹 이상 걷으면 **안쪽 어두운 판을 먹는다.** 그래서 `SINGLE_LAYER` 다.

## 코드에서 쓸 때

- 테 두께(`_frame_box` 의 `margin`)는 **조각마다 다르다.** 실제보다 크게 주면
  9조각 모서리가 겹쳐 칸을 먹는다 → [hud.md](hud.md) 의 표.
- **9조각은 테두리용이다.** 가운데에 그림이 있는 조각(배지 같은 것)은
  `TextureRect` 한 장으로 비율 그대로 깐다.
- **칸의 실제 크기는 `CELL + 안쪽 여백 * 2`** 다. 격자 높이를 `CELL * 줄수` 로 잡으면
  마지막 줄이 잘린다 → [inventory-equipment.md](inventory-equipment.md).
- **테두리 안을 채울 때는 `clip_children` 을 마스크로 쓴다.** ★★ 테두리와 채움은
  모양이 어긋나기 마련이라(비스듬히 잘린 홈 ↔ 직사각 채움), 그냥 겹치면 모서리마다
  바닥이 비쳐 "빈 공간" 으로 보인다. **채움을 테 모양에 맞춰 그리지 말고**, 테를 그린
  부모에 `clip_children = CLIP_CHILDREN_AND_DRAW` 를 주면 **부모 알파 안에서만 자식이
  보인다** — 테가 곧 마스크다. 채움은 직사각 한 장이면 된다 → [hud.md](hud.md).

## 확인

**찍어서 본다.** 위의 함정은 전부 수치로는 통과한 것들이었다.

```bash
npm run shot:godot -- hud      # 아래 묶음·오른쪽 위 메뉴·자동사냥 고리
npm run shot:godot -- bag      # 인벤토리
npm run shot:godot -- skills   # 스킬창
```

## 인벤토리 결 (2026-09-23) ★

사용자가 인벤토리 그림 한 장을 주며 **"아트풍도 저런 식으로, 바르코로 이미지를 만들어
UI 를 구성해"** 라고 했다. 그래서 **장비·상세·인벤토리 세 창만** 이 결로 바꿨다 —
**2026-09-28 에 그 창들은 던전 결로 옮겨 갔고, 지금 이 결은 캐릭터 정보·랭킹·물약·자동사냥 창에 남아 있다** —
HUD·NPC 창은 위의 "얇은 금테" 그대로다 (스킬창은 던전 결 → [dungeons.md](dungeons.md)).

한 줄로: **거의 검은 판 + 녹슨 청동빛 쇠테(빗각) + 작은 모서리 쇠장식 + 금빛 제목.**

| 쓰임 | 값 (받은 그림에서 뽑았다) |
|---|---|
| 창 안쪽 | `#161b1a` |
| 칸 안쪽 / 칸 테 | `#111313` / `#292d27` |
| 창 테 | `#2a241c` ~ `#4a3f30` |
| 고른 탭 | `#4a4232` ~ `#5c523e` + 금선 `#c9a95c` |
| 제목·금빛 글자 | `#ceb474` (고른 탭 글자 `#f1dc9c`) |
| 본문 / 흐린 글자 | `#ddd6c4` / `#948c7a` |
| 고른 칸 금테 | `#e8b449` |

- **참고 그림은 받은 스크린샷 통째다.** 160x144 JPEG(3.1KB)로 줄여 올렸고, 다시 받아
  `cmp` 로 같은 것을 확인했다. 주소:

  ```
  https://3d.varco.ai/api/objects/922372c96e43cd2e9dc8ffe0bec9d132.jpg
  ```
- 프롬프트 틀은 "판·칸·테두리류" 와 같고, 앞에 **`MATCH THE REFERENCE IMAGE'S STYLE
  EXACTLY — <그림 속 어느 조각인지>`** 를 적고 색 값을 박았다. 여섯 장 중 다섯 장이
  한 번에 맞았다 (두 장씩 뽑아 골랐다).
- **고른 칸 금테는 바르코에서 세 번 실패했다.** "테만 그리고 안쪽은 흰색으로 비워라,
  뚫을 것이다" 를 길게 적은 프롬프트였다. 짧게 "안쪽은 그냥 흰색" 으로만 적으니
  나왔다. 안쪽 번짐이 옅은 선으로 조금 남는데 어두운 칸 위에서는 빛으로 읽힌다.
- 조각: `inv_panel`(창 바탕) · `inv_slot`(칸) · `inv_slot_pick`(고른 칸 금테) ·
  `inv_tab_on`/`inv_tab_off`(세로 탭) · `inv_button`(단추). 주소는 `fetch-assets.sh`.
- **작게 굽는다.** 칸이 58px 라 칸 조각은 64, 탭 96, 단추 128, 창 256.
  구운 크기에서 테 두께를 재서 9조각 여백을 정했다(창 12 · 칸 4 · 탭 4 · 단추 6 —
  `INV_*_MARGIN`). 원본 1024 에서 재면 네 배가 된다.
- **조각이 없으면 `_inv_box` 가 같은 색으로 판을 그린다** — 조각을 안 받은 사람도
  같은 결로 보인다 (찍어서 봤다, 테만 평평하다).
- **등급은 칸 안쪽 가는 선 색**으로 보인다(`_grade_box`). 등급 색 표(shared 의
  `GRADE_COLOR`)가 흙빛이라 30% 밝혀 쓴다.

## 창은 오른쪽 위 X 로 닫는다 ★

2026-09-20 요청 — **"모든 ui 의 닫기 버튼은 오른쪽 위로 통일할거야, x버튼으로 만들어".**
가방·NPC 창이 전부 `_close_button(panel, on_press)` 하나를 쓴다. 스킬창·던전 창은 X 를
제목 줄 오른쪽 끝에 둔다 (자리는 똑같이 오른쪽 위다).

- 창 테두리(`PANEL_MARGIN` 26)보다 **안쪽으로 들인다**(`CLOSE_PAD` 24). 10 으로 뒀더니
  모서리 장식 위에 걸쳐 있었다.
- 아래쪽에 있던 "닫기" 글자 단추는 **지웠다.** 남은 단추는 장착/해제 하나뿐이다.
- 검사는 `ui_test.gd` 가 한다 — 오른쪽 위인지, 창 안에 있는지, 눌러서 닫히는지.

## 아직 안 맞춘 것

- 오른쪽 위 메뉴 일곱 장은 리니지풍(칠한 반실사)이고, 퀵슬롯 옆 자동사냥·창 안 아이콘은 상아빛 결이다.
  나머지도 그쪽으로 옮길지는 안 정했다 → [hud.md](hud.md) "메뉴 아이콘".

- 창은 2026-09-28 에 전부 던전 결로 맞췄다 → 위 "창은 던전 결".
- 상점·대장간 창(`npc_panel.gd`)과 전직 창(`job_panel.gd`)은 2026-09-26 에 이 결로 다시
  지었다 (그 전엔 고도 기본 패널에 글자·단추만) → [npc-town.md](npc-town.md) · [job-advance.md](job-advance.md).
- `ui_tab_on`/`ui_tab_off` 는 인벤토리 결로 바꾼 뒤 아무도 안 쓴다 (파일은 남겨 뒀다).

- 차원문 창(`ui/panel.png`, `gate_*`)은 따로 논다 → [portal-ui.md](portal-ui.md).

## 관련

- [hud.md](hud.md) — HUD 조각과 테 두께 표
- [inventory-equipment.md](inventory-equipment.md) — 창 조각과 칸 크기 세는 법
- [verification.md](verification.md) — 찍어서 보는 방법
