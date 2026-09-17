# 마을 NPC

## 무엇

마을에 서 있는 NPC 둘 — **상점**(상인 보리스), **대장간**(대장장이 군터).
가까이 가면 화면 아래 `F` 버튼이 뜨고, 누르면 창이 열린다.
**상점·전직은 `npcDialog`, 대장간은 `craftWindow`** 로 갈린다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/zones.ts` | NPC 배치 (`role`, `title`, 좌표) |
| `packages/shared/src/items.ts` | `NPC_REACH`, 상점/제작 목록 계산 근거 |
| `packages/server/src/ZoneRoom.ts` | `npcNear` / `shopStock` / `handleNpcOpen·Buy·Sell·Forge·Enhance·Craft·Job` |
| `packages/client/src/ui/npcPrompt.ts` | 말걸기 버튼 (F) |
| `packages/client/src/ui/npcDialog.ts` | 상점·전직 창 |
| `packages/client/src/ui/craftWindow.ts` | 제작창 (대장간) — 탭 3개 + 거르개 |

## 규칙

- 배치: 상인 `(-7, 4)`, 대장장이 `(0, 6.5)`. 머리 위에 이름 + 직함이 뜬다
  (`NameplateTarget.subtitle`).
- `NPC_REACH = 4.5`. **거리는 서버가 다시 잰다** — 창이 열려 있다고 살 수 있는 게 아니다.
- **상점과 전직은 한 창(`npcDialog`)에 둔다.** 하는 일이 "목록에서 고르고
  버튼을 누른다"로 같아서, 나누면 같은 코드가 두 벌이 된다.
- **대장간만 뗐다 (`craftWindow`).** 하는 일이 셋이고 목록이 길다 —
  `forgeableFor` 가 "내 직업 · 내 레벨 이하" 를 전부 돌려주므로 200레벨이면
  새로 만들기에만 160줄이 깔리고, 그 아래로 강화와 등급 올리기가 이어 붙었다.
  탭으로 가르고 거르개를 붙여야 쓸 수 있는 화면이 된다.
- 어느 창을 열지는 `main.ts` 의 `onNpc` 가 `role` 로 가른다.
  서버 메시지(`npc` · `npcForge` · `npcEnhance` · `craft`)는 **그대로다.**

### 상점
- **자기 직업의 1등급 무기만** 판다. 방어구·장신구는 사냥으로 줍거나 대장간에서 만든다.
- 목록은 레벨 상한이 있어 캐릭터 레벨 부근 것만 뜬다.
- 판매가 = `price * 0.4 * gradeMultiplier(grade)`.
- **구입 시 옵션을 굴린다** → [items.md](items.md).

### 대장간 = 제작창 (탭 3개)
1. **새로 만들기** — 재료 5개 + 골드. 1등급 + 옵션 굴림.
2. **강화** — 골드만. 성공 / 유지 / 파괴. 굴림은 서버.
   파괴 확률이 있는 줄은 `.is-risky` 로 테두리가 붉어진다 — 확률을 글로만
   적으면 목록을 훑을 때 안 읽고 누른다.
3. **등급 올리기** — 같은 단계 보스 재료 + 수수료. **옵션 재굴림.**

거르개(새로 만들기 탭):
- **슬롯** / **단계** — 단계 목록에는 실제로 만들 수 있는 단계만 올라온다.
  20개를 다 늘어놓으면 대부분이 빈 목록으로 이어진다.
- **「만들 수 있는 것만」 (기본 켜짐)** — 재료는 보스만 떨구므로, 켜 두면 160줄이
  대개 한 자릿수로 준다. 껐을 때와 켰을 때를 알 수 있게 창 아래에
  `8개 / 만들 수 있는 것 160개` 처럼 항상 적는다.
- 고른 거르개는 `localStorage['mmo.craftFilter']` 에 남는다. 열 때마다 다시
  고르게 하면 창을 나눈 의미가 없다.
- 가진 재료는 **0개인 단계를 빼고** 한 줄로 적는다. 20단계를 전부 적으면
  그 줄이 화면을 차지하면서 정작 "지금 뭘 만들 수 있나"가 안 보인다.

### 전직
- 서버·클라 코드는 **남아 있지만 NPC 를 안 세웠다**(요청). 마을에 `jobs` 역할
  NPC 를 다시 놓으면 그대로 살아난다.
- 전직하면 직업을 타는 장비(무기·보조)가 가방으로 돌아가고, 스킬 쿨타임과
  자동 시전 목록이 초기화된다.

## 손댈 때

- NPC 를 추가하려면 `zones.ts` 의 마을 `npcs` 에 `{ name, job, x, z, role, title }`
  을 넣고, `NpcRole` 과 `handleNpcOpen` 의 분기를 맞춘다.
- 클라이언트에서 새 버튼을 달면 **`main.ts` 에서 콜백을 연결하는 걸 잊지 말 것.**
  `npcDialog.onEnhance` 를 안 이어서 버튼이 조용히 아무 일도 안 한 적이 있다.
- 제작 규칙(재료 수·확률·옵션)은 `craftWindow` 가 아니라 [items.md](items.md) 다.
  창은 `@mmo/shared` 의 `forgeRecipe`/`craftRequirement`/`enhanceOdds` 를 읽어
  그대로 보여주기만 한다 — 창에서 수치를 다시 적으면 서버와 어긋난다.

## 관련

- [godot-migration.md](godot-migration.md) — 고도 쪽에도 같은 NPC 데이터를 쓴다.
  닿는 거리(`NPC_REACH` 4.5)를 `World` 가 다시 재는 규칙도 그대로다. 상점·대장간은
  아이템 표를 다시 만들기로 해서 **창까지만** 있다

[items.md](items.md) · [inventory-equipment.md](inventory-equipment.md) · [world-zones.md](world-zones.md)
