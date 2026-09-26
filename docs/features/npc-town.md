# 마을 NPC

## 무엇

마을에 서 있는 NPC 셋 — **상점**(상인 보리스), **대장간**(대장장이 군터), **전직**(전직관 레온).
가까이 가면 화면 아래 `F` 버튼이 뜨고, 누르면 창이 열린다.
**상점·전직은 `npcDialog`, 대장간은 `craftWindow`** 로 갈린다.
대장간은 2026-09-20 에 제작을 걷으면서 **강화 하나만** 남았다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/zones.ts` | NPC 배치 (`role`, `title`, 좌표) |
| `packages/shared/src/items.ts` | `NPC_REACH`, 상점 목록 계산 근거 |
| `packages/server/src/ZoneRoom.ts` | `npcNear` / `shopStock` / `handleNpcOpen·Buy·Sell·Enhance·Job` |
| `packages/client/src/ui/npcPrompt.ts` | 말걸기 버튼 (F) |
| `packages/client/src/ui/npcDialog.ts` | 상점·전직 창 |

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
