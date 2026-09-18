# 가방과 장비

## 무엇

가방 200칸, 장비 8슬롯. 창은 격자 5칸씩 + 아래 상세 칸.

## 어디

| 파일 | 역할 |
|---|---|
| `godot/game/game.gd` | **고도 창 전부** — `_build_bag_panel` 이 틀을 짓고 `_redraw_bag` 이 채운다 |
| `godot/world/items.gd` | `slot_label(slot, job)` — 칸 이름 |
| `scripts/build-item-icons.mjs` | 바르코 아이콘 원본 → `public/assets/icons` (배경 걷기 + 128px) |
| `packages/client/src/ui/inventory.ts` | 옛 웹 창 (지워짐) |
| `packages/client/src/ui/itemIcons.ts` | 옛 절차적 SVG 아이콘 13종 (지워짐) |
| `packages/server/src/ZoneRoom.ts` | `handleEquip` / `handleUnequip` / `sendInventory` / `refreshMax` |
| `packages/shared/src/items.ts` | `EQUIP_SLOTS`, `slotLabel`, `canEquip` |

## 규칙

### 슬롯 8종
`weapon · offhand · helmet · armor · boots · ring · necklace · earring`
- **보조(offhand)는 직업마다 다른 물건**: 격투가 보호대 / 마법사 마법서 / 궁수 화살통.
  `OFFHAND_NAME` 과 `slotLabel(slot, job)` 이 이름을 갈라 준다.
- 무기와 보조만 직업을 탄다. 나머지는 아무나 낀다.
- 착용 조건은 `canEquip(item, job, level)` — **서버가 다시 본다.**

### 창 레이아웃
- 장비 8칸 → 요약 줄 → 가방 격자(`COLUMNS = 5`) → 상세 칸.
  고도도 같다 — `GEAR_COLUMNS = 4`(8칸이 두 줄), `BAG_COLUMNS = 5`, 칸 한 변 `CELL = 84`.
  창은 444x663 이라 1280x720 안에 들어온다 (`ui_test` 가 잰다).
- **같은 물건은 한 칸에 겹친다.** 열쇠는 `id#등급#강화#옵션` (`stackKey`).
  옵션이 다르면 성능이 다르므로 겹치지 않는다. 재료는 옵션이 없어 잘 뭉친다.
- 칸이 작아 이름을 다 못 쓴다. 이름·능력치·버튼은 **아래 상세 칸**에서 보여준다.
- 배지: 등급 숫자 / `+N` 강화 / 개수.
- 상세 칸의 옵션 칩은 `title` 로 `N등급 범위 min~max` 를 보여준다.
  잘 뽑은 물건인지 알 수 있어야 등급을 올릴 이유가 생긴다.
- **요약 줄**(`.bag-gear-sum`)은 상태바에 안 나오는 것만 적는다 —
  치명타 / 치명타 데미지 / 공격 속도. 옵션으로만 붙는 값이라 여기가 없으면
  무엇을 끼웠는지 알 방법이 없다.

### 아이콘 ★
바르코 커스텀 워크플로우 **"인벤토리 UI"** 로 만든 연한 청백색 선화 한 벌이다.
주소는 `scripts/fetch-assets.sh` 에 박혀 있고, `build-item-icons.mjs` 가 굽는다.

- **파일 이름 = 슬롯 이름.** `weapon.png` `offhand.png` `helmet.png` `armor.png`
  `boots.png` `ring.png` `necklace.png` + 머리 줄용 `bag.png` `gold.png`.
  칸을 채울 때 슬롯 이름으로 바로 찾는다 — 표를 따로 두지 않는다.
- **귀걸이(earring)는 아직 그림이 없다.** 그 칸은 글자("귀걸이")로 나온다.
  받아만 두고 안 쓰는 것이 둘 더 있다 — `glove` `belt` (어느 칸에 쓸지 안 정했다).
- **없으면 글자로 나온다.** `npm run sync:godot` 을 안 돌린 사람도 창은 돌아가야 한다
  (모델이 없으면 기둥으로 그리는 것과 같은 규칙).
- 바르코가 준 원본은 **배경이 검은 것과 흰 것이 섞여 있다.** 그대로 쓰면 어두운 창에서
  흰 사각형이 번쩍이므로 굽는 단계에서 걷어낸다. 걷는 방법이 까다로워 세 번 고쳤다:
  밝기로 자르면 동전 속이 비고, 모서리 색만 보면 둥근 사각형 배경(반지·벨트·검)이
  안 걷히고, 겹을 무조건 세 번 벗기면 동전이 통째로 지워졌다(100%). 지금은
  **테두리에서 색을 모아 이어진 것만 걷고, 첫 겹이 25% 미만일 때만 한 겹 더** 들어간다.

### 서버
- 인벤토리는 **본인에게만** `inventory` 메시지로 보낸다 (상태 스키마에 없음).
- 장비가 바뀌면 `refreshMax` 가 최대 HP/MP 를 다시 계산한다.
- 가방이 꽉 차면(`INVENTORY_SIZE = 200`) 벗기·구입·드롭이 거부된다.

## 손댈 때

- 아이템에 필드를 더하면 `stackKey` 에 넣을지 판단할 것. 성능이 달라지는
  필드인데 안 넣으면 다른 물건이 한 칸에 겹쳐 보인다.
- 슬롯을 추가하면 `EQUIP_SLOTS`, `SLOT_CODE`, `bonusFor`, `FIXED_SLOT_LABEL`,
  아이콘, 창 격자를 같이 봐야 한다. 칸 이름은 `slotLabels`·`offhandNames` 로
  `items.json` 에 나가므로 `npm run export:godot` 을 다시 돌린다.
- **아직 기능은 안 붙였다.** 창·칸·아이콘·고르기·끼기/벗기까지다. 겹치기(`stackKey`),
  200칸 스크롤, 옵션 칩의 등급 범위 안내는 웹 클라에 있던 것이고 고도에는 아직 없다.

## 관련

[items.md](items.md) · 옛 client-ui.md(지워짐) · [npc-town.md](npc-town.md)
