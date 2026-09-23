# UI 아트풍 (굳힌 것)

## 무엇

2026-09-20 에 사용자가 **"지금 느낌 좋다, 이렇게 아트풍 저장해"** 라고 한 그 결이다.
HUD 와 스킬창·NPC 창이 이것으로 되어 있고, **앞으로 만드는 UI 는 전부 여기에 맞춘다.**
**단, 가방의 세 창은 2026-09-23 에 받은 그림대로 "인벤토리 결" 로 바꿨다** → 아래 절.

한 줄로: **어두운 판 + 머리카락처럼 얇은 금테 + 상아빛으로 칠한 아이콘.**

여기까지 오는 데 네 바퀴가 걸렸다. 지적받은 것을 순서대로 적어 둔다 —
**다시 만들 때 같은 길을 또 돌지 않으려고** 남기는 문서다.

| 시도 | 지적 |
|---|---|
| 청록 발광 + 두꺼운 테 | — (첫 판) |
| 낡은 쇠 + 두꺼운 금테 | "테두리가 너무 두꺼워" |
| 얇은 금선 + 검은 선화 아이콘 | "가방이랑 스킬 아이콘이 왜 검정색이야" |
| 얇은 금선 + 칠한 아이콘 | "아까 칼/가방처럼. 아예 새로운 풍으로 만들지 말고" |
| **지금** | "지금 느낌 좋다" |

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
3. **아이콘은 테두리 없이, 밝게 칠한다.** 상아빛 + 금색에 얇고 어두운 윤곽선.
   원판·배지·액자 위에 앉히지 않는다.
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

- 지금 결의 참고 그림(X자 검 · 배낭 아이콘 두 장을 어두운 바탕에 붙인 것)은
  **이미 바르코에 올라가 있다. 다시 올릴 필요 없이 이 주소를 `ImageInput` 에 넣으면 된다:**

  ```
  https://3d.varco.ai/api/objects/26d7516cbd9971ad06060eb9da7254da.jpg
  ```

- 이 주소를 그대로 물려 만든 것: 차원문 창의 줄 아이콘 둘
  (`ui_gate_here` 소용돌이 · `ui_gate_go` 별, 2026-09-21). **한 번에 맞았다** —
  프롬프트는 아래 "아이콘류" 틀에서 `<무엇>` 만 갈았다 ([portal-ui.md](portal-ui.md)).
- 새로 만들어야 하면 **지금 쓰는 아이콘으로 다시 만든다.**

  ```bash
  node -e "
  const sharp=require('sharp');
  Promise.all([
    sharp('public/assets/icons/ui_icon_auto.png').resize(64,64,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).toBuffer(),
    sharp('public/assets/icons/ui_icon_bag.png').resize(64,64,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).toBuffer(),
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
HUD·스킬창·NPC 창은 위의 "얇은 금테" 그대로다.

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
가방·스킬창·NPC 창이 전부 `_close_button(panel, on_press)` 하나를 쓴다.

- 창 테두리(`PANEL_MARGIN` 26)보다 **안쪽으로 들인다**(`CLOSE_PAD` 24). 10 으로 뒀더니
  모서리 장식 위에 걸쳐 있었다.
- 아래쪽에 있던 "닫기" 글자 단추는 **지웠다.** 남은 단추는 장착/해제 하나뿐이다.
- 검사는 `ui_test.gd` 가 한다 — 오른쪽 위인지, 창 안에 있는지, 눌러서 닫히는지.

## 아직 안 맞춘 것

- 스킬창·NPC 창은 얇은 금테 결이다. 인벤토리 결로 맞출지는 안 정했다.
- `ui_tab_on`/`ui_tab_off` 는 인벤토리 결로 바꾼 뒤 아무도 안 쓴다 (파일은 남겨 뒀다).

- 차원문 창(`ui/panel.png`, `gate_*`)은 따로 논다 → [portal-ui.md](portal-ui.md).

## 관련

- [hud.md](hud.md) — HUD 조각과 테 두께 표
- [inventory-equipment.md](inventory-equipment.md) — 창 조각과 칸 크기 세는 법
- [verification.md](verification.md) — 찍어서 보는 방법
