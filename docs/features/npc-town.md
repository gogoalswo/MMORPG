# 마을 NPC

## 무엇

**지금 마을에는 전직관 레온 한 명만 선다** (2026-09-26 요청: "마을에 불필요한 NPC들은
제거해. 지금은 전직 교관만 있으면 되겠어"). 상인 보리스·대장장이 군터·마을 사람 넷
(아네트·요한·릴리·노인 하르트)을 `zones.ts` 의 마을 `npcs` 에서 뺐다.

- **뺀 것은 줄뿐이다.** 상점·대장간 판정(`World.npc_buy`·`npc_sell`·`npc_enhance`), 창
  (`NpcPanel`), 모델(`merchant`·`smith`·`villager_*` — 아래 "외형")은 그대로 있다.
  줄을 되살리면 곧바로 다시 선다 (`git log -p packages/shared/src/zones.ts` 에 옛 줄이 있다).
- 그래서 상점·대장간 테스트(`shop_test`·`npc_test`)는 **시험용 상인·대장장이를 세워** 본다 —
  `shop_test.stand_shops(w)` 가 존 표를 복사해 두 줄을 붙인다 (GameData 의 표는 한 벌이라
  복사 없이 고치면 다른 테스트로 샌다. `npc_test._case_list` 가 새지 않았는지도 본다).
  `npm run shot:godot -- shop` · `smith` 도 같은 것을 세워 찍는다.
- 가방의 강화는 대장간 없이도 된다 (가방 상세 창의 강화 팝업 → [items.md](items.md)).

아래는 상인·대장장이가 서 있던 때의 규칙이다 — 되살리면 그대로 돈다.

가까이 가면 화면 아래 `F` 버튼이 뜨고, 누르면 창이 열린다.
**상점·전직은 `npcDialog`, 대장간은 `craftWindow`** 로 갈린다.
대장간은 2026-09-20 에 제작을 걷으면서 **강화 하나만** 남았다.

## 외형 ★ (2026-09-26 — 바르코 모델)

요청: "마을에 있는 NPC들 모델링을 만들어". 그 전까지 고도에서는 **기둥 + 이름표**였다.
마을 7명이 전부 제 모델로 서서 **대기 동작**을 튼다. 외형은 코드로 짓지 않는다(CLAUDE.md).

| look | 누구 | 키(m) | 대기 |
|---|---|---|---|
| `merchant` | 상인 보리스 — 녹색 털깃 외투, 동전 주머니·저울 | 1.75 | `standing_idle_1` |
| `smith` | 대장장이 군터 — 민머리, 땋은 붉은 수염, 가죽 앞치마 | 1.95 | `standing_idle_2` |
| `trainer` | 전직관 레온 — 은발 교관, 금 문장 남색 겉옷 + 사슬갑옷, 붉은 망토 | 1.8 | `standing_idle_1` |
| `villager_sack` | 아네트 — 머릿수건, 등에 곡식 자루 | 1.66 | `standing_idle_2` |
| `villager_apron` | 요한 — 제빵사 모자·흰 앞치마 | 1.8 | `standing_idle_1` |
| `villager_hood` | 릴리 — 붉은 두건 망토, 허리에 약초 바구니 | 1.55 | `standing_idle_2` |
| `villager_old` | 노인 하르트 — 긴 흰 수염, 숄 두른 잿빛 로브 | 1.68 | `standing_idle_1` |

- **만드는 법** (바르코 워크플로우, 격투가와 같은 설정):
  1. `GenerateImage`(`nano-banana-pro`, 9:16) — 참고 그림 = **격투가 원화**(`bffec01b…jpg`, `docs/art/fighter_concept.png`
     와 같은 그림)로 아니메풍 채색 결을 맞춘다. 프롬프트는 사람마다 옷차림 + 공통 꼬리("정면, 팔은 몸에서 조금 떨어뜨려
     내리고 **두 손은 비우고**, 발은 어깨너비, 흰 바탕"). 손에 든 물건은 T자세 3D 에서 뭉개지므로 소품은 **허리·등에 단다.**
  2. **원화를 먼저 보여 주고** 3D 로 넘긴다 (원화 20 크레딧, 3D 200). 원화는 `docs/art/npc/<look>.jpg`.
  3. `Generate3D`(`tPose` 1, 3만 면, 2048) → `Rig`(`humanoid`) → `Animate`(`standing_idle_1`/`_2` 번갈아, `inPlace` 1).
  4. 결과물 주소는 `scripts/fetch-assets.sh` 의 `fetch_npc` 줄. 대기 하나뿐이라 **오우거처럼 대기 파일을 기본 메시로도
     쓴다** → `public/assets/models/npc_<look>.glb` (텍스처 1024, 고도로 갈 때 512).
- **게임에서** (`game.gd` 의 존 짓기) — `Rig.create(look, NPC_HEIGHTS[look])`. 파일이 없으면 예전처럼 기둥이다.
  **마을 가운데(0, 0)를 본다** (`rot = atan2(-x, -z)`, 모델 앞 +Z). 다 같이 숨 쉬면 복제인간이라 사람마다 클립 중간
  다른 자리(`i × 1.7초`)에서 튼다. 대기 동작도 둘을 번갈아 줬다. 키는 `game.gd` 의 `NPC_HEIGHTS`(없으면 1.8).
- 말 걸기 판정은 모델과 상관없다 — 누른 **바닥 점**이 NPC 자리 1.2 안이면 된다(`_npc_at`).
- 확인: `npm run test:godot -- model` 의 `_case_npcs` — 마을 NPC 전원이 모델로 만들어지고 `Idle` 이 있고 키가 맞다.
- 새 NPC 를 더하면: 원화 → 3D → 리깅 → 대기를 같은 설정으로 뽑고, `fetch_npc <해시> <look>` 한 줄,
  `rig.gd` 의 `FILES`, `sync-godot-assets.mjs` 의 `MODELS`, `zones.ts` 의 `look` 을 맞춘다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/zones.ts` | NPC 배치 (`role`, `title`, 좌표) |
| `packages/shared/src/items.ts` | `NPC_REACH`, 상점 목록 계산 근거 |
| `packages/server/src/ZoneRoom.ts` | `npcNear` / `shopStock` / `handleNpcOpen·Buy·Sell·Enhance·Job` |
| `packages/client/src/ui/npcPrompt.ts` | 말걸기 버튼 (F) |
| `packages/client/src/ui/npcDialog.ts` | 상점·전직 창 (옛 웹 — 지워짐) |
| **`godot/game/npc_panel.gd`** | ★ **고도 상점·대장간 창** (`NpcPanel`) — 아래 "창 (고도)" |
| `godot/game/game.gd` `_build_npc_panel` · `_show_npc` | 창을 HUD 위 층(`NpcLayer`, 10)에 달고 신호를 요청(`npcBuy`·`npcSell`·`npcEnhance`)으로 잇는다. `jobs` 면 전직 창(`JobPanel`)을 연다 |
| `godot/tools/shot.gd` `_npc_window` | `npm run shot:godot -- shop` · `smith` |

## 규칙

- 배치: 상인 `(-7, 4)`, 대장장이 `(0, 6.5)`. 머리 위에 이름 + 직함이 뜬다
  (`NameplateTarget.subtitle`).
- `NPC_REACH = 4.5`. **거리는 서버가 다시 잰다** — 창이 열려 있다고 살 수 있는 게 아니다.
- **상점과 전직은 한 창(`npcDialog`)에 둔다.** 하는 일이 "목록에서 고르고
  버튼을 누른다"로 같아서, 나누면 같은 코드가 두 벌이 된다.
- **대장간은 따로 뗐다 (`craftWindow`).** 원래 하는 일이 셋이라 탭과 거르개가
  필요했는데, 제작을 걷은 지금은 **강화 탭 하나**뿐이다. 창을 합치지 않고 둔 건
  보스 전용 아이템이 붙을 자리가 여기이기 때문이다.
- 어느 창을 열지는 `main.ts` 의 `onNpc` 가 `role` 로 가른다.
  서버 메시지는 `npc` · `npcEnhance` 둘만 남았다 (`npcForge` · `craft` 는 없앴다).

### 창 (고도) ★ (2026-09-26 다시 지음)

```
┌ 상점                                             [X] ┐   ui_panel
│ 상인 보리스                                          │
│ ──────────────────────────────────────────────────── │
│ [사기] [팔기]                  골드 12,345  가방 8/200 │   탭 = ui_button (고른 것은 달아오름)
│ ┌──────────────────────────────────────────────────┐ │   목록 = ui_slot, 끌어서 내림
│ │ [아이콘] 가죽 건틀릿            [  32 G  ]        │ │   줄 = 어두운 판 + 가는 테
│ │          무기 · Lv.1                             │ │   아이콘 테 = 등급 색
│ └──────────────────────────────────────────────────┘ │
│        줄을 누르면 삽니다 · 살 때 옵션이 붙습니다       │
└──────────────────────────────────────────────────────┘
```

- **처음 판은 고도 기본 패널에 글자·단추만 쌓았다** → 전직 창을 다시 지은 뒤 "상점이랑
  대장간 창도 같은 결로 다시 만들어" (2026-09-26). 전직 창(`JobPanel`)과 같은 조각·색이다
  → [ui-art-style.md](ui-art-style.md) · [job-advance.md](job-advance.md).
- **줄 전체가 누르는 자리다** (`hit`). 가방·스킬 목록과 같은 `DragScroll` 이 끌기(스크롤)와
  누르기를 가른다. 오른쪽 값표(`tag`)는 단추처럼 보이는 표일 뿐 따로 눌리지 않는다.
  `DragScroll` 은 `disabled` 를 안 보고 `pressed` 를 내서, 막힌 줄은 `hit` 의 콜백이 거른다.
- 값표: 사기 = 가격(골드가 모자라면 붉게) · 팔기 = 판매가 · 강화 = `+N → +N+1`(최대면 "최대",
  흐리게). 강화 줄의 설명은 "성공 N% · 실패 시 파괴" — **값표는 붉히지 않는다.** 모든 단계에
  파괴 확률이 있어서 값표까지 붉히면 전부 붉다 (찍어서 봤다).
- 팔기·강화 목록은 **가방의 장비 전부**다 (재료 — 크리스탈·물약 — 는 뺀다). 옛 창은 앞 12칸만
  보였다. 넘치면 끌어서 내린다.
- **HUD 위 층(`CanvasLayer` 10)** 에 단다 — 전직 창에서 체력 막대·퀵슬롯이 아래쪽을 덮는 걸
  봤다. 한글 폰트는 `_ui_root.theme` 을 물려준다.
- 창은 그리기만 한다. 파는 목록은 World 가 주고(`npc` 이벤트의 `items`), 사고팔고 두드리는
  판정·거리는 World 가 다시 본다. 창은 `me` 를 `game._me` 로 매번 새로 읽는다.
- 테스트(`npc_test._check_shop`): 화면 가운데 안 · HUD 위 층 · X 오른쪽 위 · 줄이 창 안 ·
  줄을 누르면 산다 · 팔기 탭 · 대장간은 강화 탭 하나에 "+0 → +1".

### 상점
- **무기만** 판다. 방어구·장신구는 **사냥으로만** 줍는다.
  **2026-09-21 부터 직업을 안 가른다** — 장비가 전 직업 공용이라 재고가 같다.
  낄 수 있는 등급과 그 아래 하나까지 선다(강화 여벌).
- 목록은 레벨 상한이 있어 캐릭터 레벨 부근 것만 뜬다.
- 판매가 = `price * 0.4 * gradeMultiplier(grade)`.
- **구입 시 옵션을 굴린다** → [items.md](items.md).

### 대장간 = 강화 (탭 1개)
- **강화** — **공짜다.** 성공 / 파괴 둘뿐이고 굴림은 판정하는 쪽이 한다.
  파괴 확률이 있는 줄은 `.is-risky` 로 테두리가 붉어진다 — 확률을 글로만
  적으면 목록을 훑을 때 안 읽고 누른다.
- 새로 만들기 · 등급 올리기 · 거르개는 **2026-09-20 에 제작과 함께 걷었다.**
  → [items.md](items.md) "제작 — 없앴다".

### 전직
- **2026-09-26 에 고도 쪽에 `전직관 레온`(`role: 'jobs'`, (7, 7))을 세웠다.** 직업을 바꾸는
  옛 전직이 아니라 **단계를 올리는 전직**이다 — 다음 전직 버튼 하나 → 보스 시험 → 잡으면
  전직 · 스킬 해금 → [job-advance.md](job-advance.md).
- 자리는 차원문(4, 0) 뒤쪽이다. 닿는 거리(4.5) 끝에 서도 문 반경(2.6) 밖이라, 말 걸러
  가다가 차원문 창이 뜨지 않는다.
- 옛 Colyseus 서버의 `handleNpcJob`(직업 바꾸기)은 그대로 남아 있다 — 고도는 안 쓴다.

## 손댈 때

- NPC 를 추가하려면 `zones.ts` 의 마을 `npcs` 에 `{ name, job, x, z, role, title }`
  을 넣고, `NpcRole` 과 `handleNpcOpen` 의 분기를 맞춘다.
- 클라이언트에서 새 버튼을 달면 **`main.ts` 에서 콜백을 연결하는 걸 잊지 말 것.**
  `npcDialog.onEnhance` 를 안 이어서 버튼이 조용히 아무 일도 안 한 적이 있다.
- 강화 규칙(확률·배수)은 `craftWindow` 가 아니라 [items.md](items.md) 다.
  창은 `@mmo/shared` 의 `enhanceOdds` 를 읽어 그대로 보여주기만 한다 —
  창에서 수치를 다시 적으면 서버와 어긋난다.

## 관련

- [godot-migration.md](godot-migration.md) — 고도 쪽에도 같은 NPC 데이터를 쓴다.
  닿는 거리(`NPC_REACH` 4.5)를 `World` 가 다시 재는 규칙도, 상점이 자기 직업 무기만
  파는 것도, 대장간에 강화만 남은 것도 그대로다.

[items.md](items.md) · [inventory-equipment.md](inventory-equipment.md) · [world-zones.md](world-zones.md)
