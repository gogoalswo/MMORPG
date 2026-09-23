# 스킬 강화

## 무엇

스킬마다 **강화가 둘까지** 붙는다. 붙이는 길은 **스킬 강화서**를 가방에서 "사용" 하는
것뿐이고, 한 번 붙으면 계속 남는다(저장된다). 강화서는 나중에 **던전에서 떨어진다** —
지금은 테스트 단추로만 얻는다.

2026-09-23 요청: "각 스킬별로 두 개씩 강화가 가능하게 할거고 스킬 강화서를 먹어서
사용하면 강화할 수 있게". **낙뢰부터** 만들고 있다 — 낙뢰 강화 둘 중 **기절은 붙였고,
범위 50% 는 다음 차례**다.

| 스킬 | 강화 | 효과 | 이펙트 | 상태 |
|---|---|---|---|---|
| 낙뢰 `thunder_fall` | 기절 `stun` | 맞은 몬스터 **3초 기절** — 못 움직이고 못 때린다 | 번개가 **붉게** | 붙었다 |
| 낙뢰 `thunder_fall` | 범위 | 범위 50% 증가 | 커진 범위에 맞게 **번개 두 번 더** | 다음 차례 |

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/skills.ts` `SKILL_UPGRADES` · `SKILL_UPGRADE_MAX` · `scrollId` | **강화 표** — 스킬·id·이름·효과 한 줄·`stunMs`. `skills.json` 의 `upgrades` 로 나간다 |
| `packages/shared/src/items.ts` `MATERIALS` | 강화서를 **강화 표에서 만든다** — `scroll_<스킬>_<강화>`, 이름 `낙뢰 강화서: 기절`, `upgrade: {skill, id}` |
| `packages/shared/src/skills.test.ts` | 강화가 있는 스킬에 붙나 · 스킬마다 둘 이하 · 강화서가 하나씩 있나 |
| `godot/world/skills.gd` `upgrade` · `stun_ms` | 표 읽기 |
| `godot/world/items.gd` `scroll_ids` | 재료 중 `upgrade` 가 있는 것 |
| `godot/world/world.gd` `use_scroll` | 강화서를 쓴다 — **판정은 여기서** (직업·이미 붙었나) |
| `godot/world/world.gd` `cast` | 붙은 강화를 `skill` 이벤트에 싣고(`upgrades`), 기절을 건다 |
| `godot/world/world.gd` `_step_monsters` | `stunned_until` 까지 `state = "stun"` 으로 서 있는다 |
| `godot/world/world.gd` `debug_scrolls` · `debug_reset_upgrades` | 테스트 단추 둘 |
| `godot/world/save.gd` | `skill_upgrades` 칸 |
| `godot/game/game.gd` `_show_scroll_detail` · `_on_bag_action` | 가방 상세 창과 "사용" |
| `godot/game/lightning_fx.gd` `PALETTE_RED` · `Strike.paint` | 붉은 번개 |
| `godot/tests/skill_test.gd` `_case_upgrade` | 강화서 소모·중복 거절·기절 3초·떼면 없음 |
| `godot/tests/save_test.gd` | 저장 왕복 (지금 표에 있는 것만 되살아나나) |
| `godot/tests/lightning_fx_test.gd` `_case_red` | 기절이면 붉은 번개, 떼면 다시 푸른 번개 (풀에 색이 안 남나) |

## 규칙

### 강화서는 강화 하나에 한 종류다 ★ (사용자 선택)

`낙뢰 강화서: 기절` 을 쓰면 **바로** 기절이 붙는다 — 고르는 창이 없다. 스킬마다 한 장,
한 종류로 공용 같은 안도 있었지만 사용자가 이쪽을 골랐다. 던전마다 떨어뜨릴 것을
골라 넣기 쉽다.

- 가방에는 크리스탈처럼 **재료**로 들어가 한 칸에 겹친다 (`{ id, count }`,
  `World._give`). 장비 표(`ITEMS`)에 넣지 않은 이유는 크리스탈과 같다 → [items.md](items.md).
- **이미 붙은 강화의 강화서는 안 쓰인다** — 한 장도 안 준다. 가방 상세 창도 단추를
  "강화 완료" 로 꺼 둔다(화면은 안내일 뿐, 판정은 `use_scroll` 이 다시 본다).
- **남의 직업 스킬 강화서는 안 쓰인다.** 스킬을 **배웠는지는 안 본다** — 강화는
  캐릭터에 남으므로 나중에 배워도 붙어 있다.
- 가방 칸의 그림은 아직 없다 — 칸에는 이름 글자가 찍힌다 (`_item_icon`).

### 강화는 따로 붙고 같이 붙을 수도 있다 ★

"스턴 강화가 안 되고 범위 증가 강화만 했으면 색상은 변경하면 안되겠지" (요청).
그래서 **이펙트도 강화마다 따로** 바꾼다 — 기절은 번개의 **색만**, 범위는 **크기와
줄기 수만** 건드린다. 둘이 섞여도 서로를 덮지 않는다.

- 판정이 `skill` 이벤트에 `upgrades: [강화 id…]` 를 싣는다. 화면은 그것만 보고 고른다
  (`game.gd` `_show_skill`). 화면이 저장값을 따로 읽으면 판정과 어긋날 수 있다.
- 저장은 `skill_upgrades: { 스킬 id: [강화 id…] }` 이다. **없던 칸을 더한 것이라 옛
  저장은 빈 사전으로 읽힌다** — 저장 `VERSION` 을 올리지 않았다 (`granted` 와 같은 방식).
  되살릴 때 **지금 표에 있는 것만** 남긴다 (스킬 표를 자주 갈아엎는다).

### 기절 ★

- **첫 대에서 건다** — 살아남은 놈에게만. 연타가 있어도 다시 걸지 않는다.
- 기절 동안 `_step_monsters` 가 그 놈을 건너뛴다 — 못 움직이고 못 때린다.
  상태는 `"stun"` 이고 화면은 `Idle` 을 돌린다 (모르는 상태는 대기로 본다).
- **예고한 보스 범위 공격은 기절해도 터진다.** 기절 검사를 예고 검사 **뒤**에 둔 이유다 —
  "한번 예고한 것은 그대로 터진다" ([godot-migration.md](godot-migration.md) "예고한 원은
  그 자리에 고정된다")를 기절이 깨면 원이 떠 있는데 안 터지는 일이 생긴다.
- 보스에게도 걸린다. 부활하면 풀린다 (`_respawn`).
- 기절한 놈 머리 위 표시는 **아직 없다** — 멈춰 서 있는 것으로만 보인다.

### 붉은 번개 ★

- 색 한 벌(`PALETTE_BLUE` · `PALETTE_RED`)은 **헤일로 · 색 빛 · 불똥** 셋이다.
  **흰 심과 금·그을림(흙)은 안 바뀐다** — 가장 밝은 자리가 희어야 빛으로 읽히고,
  땅은 번개 색과 상관없이 흙이다.
- 붉은 벌은 푸른 벌과 **밝기 순서를 맞췄다** — 헤일로 `#ff2a1a` 가 가장 짙고 색 빛
  `#ffa090` 이 옅다, 불똥 `#ff8a70`. 번쩍임 빛(`OmniLight3D`)도 헤일로 색이다.
- **풀은 한 벌을 같이 쓰고 되감을 때 색만 칠한다** (`Strike.paint`). 리본·섬광은 매
  프레임 `_pal` 을 읽고, 만들 때 굳는 것(빛·불똥 방출기)만 `paint` 가 바꾼다. 풀
  설명의 "되감을 때 위치·시각·보는 쪽·**색**만 넣는다" 그대로다
  → [skills.md](skills.md) "히치 — 이펙트 풀".

### 테스트 단추 (왼쪽 아래 테스트 줄)

- **"강화서 +1"** — 강화서를 **종류마다 한 장씩** 넣는다 (`debugScrolls`).
- **"강화 떼기"** — 붙은 강화를 전부 뗀다. 강화서는 돌려주지 않는다 (`debugResetUpgrades`).
- 줄이 위로 자라서 둘을 **한 줄에 반씩** 놓았다.

## 손댈 때

- **강화를 더할 때** — `SKILL_UPGRADES` 에 한 줄 → `npm run export:godot`. 강화서는
  저절로 생긴다. 효과가 새 종류면 `cast` 에 판정을, `_show_skill` 에 이펙트 분기를 더한다.
  효과 문구(`desc`)는 **상세 창 300px 한 줄**에 들어가야 한다.
- **이펙트를 바꿀 때** — [effect-rules.md](effect-rules.md) 를 먼저 읽고, 바꾸면
  `npm run shot:godot` 으로 찍어 본다.
- **던전 드랍을 붙일 때** — 떨굴 id 는 `Items.scroll_ids()` / `scrollId()` 에서 고른다.
  테스트 단추는 그때 걷을지 묻는다.
- 옛 Colyseus 서버(`ZoneRoom.ts`)에는 안 붙였다.

## 관련

- [skills.md](skills.md) — 스킬 표, 낙뢰 이펙트
- [items.md](items.md) — 재료(크리스탈), 가방 겹치기
- [dungeons.md](dungeons.md) — 강화서가 떨어질 곳
- [effect-rules.md](effect-rules.md)
