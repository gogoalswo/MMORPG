# 가방과 장비

## 무엇

가방 200칸, 장비 8슬롯. 창은 격자 5칸씩 + 아래 상세 칸.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/client/src/ui/inventory.ts` | 가방·장비 창 전부 |
| `packages/client/src/ui/itemIcons.ts` | 절차적 SVG 아이콘 13종 |
| `packages/server/src/ZoneRoom.ts` | `handleEquip` / `handleUnequip` / `sendInventory` / `refreshMax` |
| `packages/shared/src/items.ts` | `EQUIP_SLOTS`, `slotLabel`, `canEquip` |

## 규칙

### 슬롯 8종
`weapon · offhand · helmet · armor · boots · ring · necklace · earring`
- **보조(offhand)는 직업마다 다른 물건**: 기사 방패 / 마법사 마법서 / 궁수 화살통.
  `OFFHAND_NAME` 과 `slotLabel(slot, job)` 이 이름을 갈라 준다.
- 무기와 보조만 직업을 탄다. 나머지는 아무나 낀다.
- 착용 조건은 `canEquip(item, job, level)` — **서버가 다시 본다.**

### 창 레이아웃
- 장비 8칸 → 요약 줄 → 가방 격자(`COLUMNS = 5`) → 상세 칸.
- **같은 물건은 한 칸에 겹친다.** 열쇠는 `id#등급#강화#옵션` (`stackKey`).
  옵션이 다르면 성능이 다르므로 겹치지 않는다. 재료는 옵션이 없어 잘 뭉친다.
- 칸이 작아 이름을 다 못 쓴다. 이름·능력치·버튼은 **아래 상세 칸**에서 보여준다.
- 배지: 등급 숫자 / `+N` 강화 / 개수.
- 상세 칸의 옵션 칩은 `title` 로 `N등급 범위 min~max` 를 보여준다.
  잘 뽑은 물건인지 알 수 있어야 등급을 올릴 이유가 생긴다.
- **요약 줄**(`.bag-gear-sum`)은 상태바에 안 나오는 것만 적는다 —
  치명타 / 치명타 데미지 / 공격 속도. 옵션으로만 붙는 값이라 여기가 없으면
  무엇을 끼웠는지 알 방법이 없다.

### 서버
- 인벤토리는 **본인에게만** `inventory` 메시지로 보낸다 (상태 스키마에 없음).
- 장비가 바뀌면 `refreshMax` 가 최대 HP/MP 를 다시 계산한다.
- 가방이 꽉 차면(`INVENTORY_SIZE = 200`) 벗기·구입·드롭이 거부된다.

## 손댈 때

- 아이템에 필드를 더하면 `stackKey` 에 넣을지 판단할 것. 성능이 달라지는
  필드인데 안 넣으면 다른 물건이 한 칸에 겹쳐 보인다.
- 슬롯을 추가하면 `EQUIP_SLOTS`, `SLOT_CODE`, `bonusFor`, `FIXED_SLOT_LABEL`,
  아이콘, 창 CSS 격자를 같이 봐야 한다.

## 관련

[items.md](items.md) · [client-ui.md](client-ui.md) · [npc-town.md](npc-town.md)
