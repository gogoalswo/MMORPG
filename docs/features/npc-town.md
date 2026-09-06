# 마을 NPC

## 무엇

마을에 서 있는 NPC 둘 — **상점**(상인 보리스), **대장간**(대장장이 군터).
가까이 가면 화면 아래 `F` 버튼이 뜨고, 누르면 창이 열린다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/zones.ts` | NPC 배치 (`role`, `title`, 좌표) |
| `packages/shared/src/items.ts` | `NPC_REACH`, 상점/제작 목록 계산 근거 |
| `packages/server/src/ZoneRoom.ts` | `npcNear` / `shopStock` / `handleNpcOpen·Buy·Sell·Forge·Enhance·Craft·Job` |
| `packages/client/src/ui/npcPrompt.ts` | 말걸기 버튼 (F) |
| `packages/client/src/ui/npcDialog.ts` | 창 하나로 상점·대장간·전직을 다 그린다 |

## 규칙

- 배치: 상인 `(-7, 4)`, 대장장이 `(0, 6.5)`. 머리 위에 이름 + 직함이 뜬다
  (`NameplateTarget.subtitle`).
- `NPC_REACH = 4.5`. **거리는 서버가 다시 잰다** — 창이 열려 있다고 살 수 있는 게 아니다.
- 창을 셋으로 나누지 않은 이유: 하는 일이 전부 "목록에서 고르고 버튼을 누른다"로
  같다. 나누면 같은 코드가 세 벌이 된다.

### 상점
- **자기 직업의 1등급 무기만** 판다. 방어구·장신구는 사냥으로 줍거나 대장간에서 만든다.
- 목록은 레벨 상한이 있어 캐릭터 레벨 부근 것만 뜬다.
- 판매가 = `price * 0.4 * gradeMultiplier(grade)`.
- **구입 시 옵션을 굴린다** → [items.md](items.md).

### 대장간 (섹션 3개)
1. **새로 만들기** — 재료 5개 + 골드. 1등급 + 옵션 굴림.
2. **강화** — 골드만. 성공 / 유지 / 파괴. 굴림은 서버.
3. **등급 올리기** — 같은 단계 보스 재료 + 수수료. **옵션 재굴림.**

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

## 관련

[items.md](items.md) · [inventory-equipment.md](inventory-equipment.md) · [world-zones.md](world-zones.md)
