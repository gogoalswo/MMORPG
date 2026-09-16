# 아이템

## 무엇

장비 280종 + 제작 재료 20종. 축이 셋이다 — **단계(레벨)** / **등급(1~10)** / **강화(+0~+10)**,
그리고 물건마다 다른 **랜덤 옵션 1~3개**.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/items.ts` | 전부. 생성·등급·옵션·강화·제작·드롭 |
| `packages/shared/src/items.test.ts` | 규칙 전수 검사 (단계 순서, 옵션 범위, 등급 단조성 등) |
| `packages/server/src/ZoneRoom.ts` | 굴리는 자리 — `handleNpcBuy` / `handleNpcForge` / `handleCraft` / `handleNpcEnhance` / 드롭 |
| `packages/server/src/db.ts` | `toStack` / `withOptions` — 저장값 복원과 마이그레이션 |
| `packages/client/src/ui/itemIcons.ts` | 절차적 SVG 아이콘 (아트 에셋 없음) |
| `packages/client/src/ui/craftWindow.ts` | 제작창 — 탭 3개 + 거르개 |

## 규칙

### 생성
- 단계 20개, 접두어 표(`TIER_PREFIX`: 낡은 → … → 종말).
- `tierLevel(i)` = 0단계는 1, 나머지는 `i * 10`.
- 단계마다 슬롯 8종. 무기·보조는 직업 4벌(격투가는 너클·보호대) → 단계당 6 + 2×4 = 14개 × 20 = **280개**.
- id 규칙: `{슬롯코드}_{직업}_{단계2자리}` 또는 `{슬롯코드}_{단계2자리}`.
  슬롯코드 `w o a h b r n e`, 재료는 `m_{단계}`.
- 기본 능력치는 `bonusFor(slot, level, job)` — 슬롯 성격별 가중치
  (갑옷 > 투구 > 신발 = 1 : 0.6 : 0.45).

### 등급 (1~10)
- **드롭은 7등급까지**(`MAX_DROP_GRADE`), 8~10은 제작으로만. 최상위가 운이 아니라
  쌓아온 결과가 되도록.
- 드롭 등급 가중치: `2^(7-g)` — 한 등급 오를 때마다 절반.
- **등급은 기본 수치에 곱하지 않는다.** (예전에는 곱했다. 바뀌었다.)
  지금 등급이 하는 일은 **옵션 범위를 넓히는 것**뿐이다.
- `gradeMultiplier(g) = 1 + (g-1)*0.3` 은 이제 **값(판매가·제작 수수료)에만** 쓴다.

### 랜덤 옵션 ★
- 종류 6개: `crit` 치명타 / `attackSpeed` 공격 속도 / `critDamage` 치명타 데미지 /
  `maxHp` 체력 / `attack` 공격력 / `defense` 방어력.
- 개수 `OPTION_MIN=1` ~ `OPTION_MAX=3`, **종류는 겹치지 않는다.**
- 범위: `optionRange(kind, grade, level)` = `baseOptionRange(kind, level) × optionGradeScale(grade)`
  - `optionGradeScale(g) = 1 + (g-1)*0.35` → 1등급 1.0, 10등급 4.15
  - 퍼센트 옵션(치명타/공속/치명타데미지)은 **레벨을 안 탄다** — 10%는 어디서나 10%
  - 수치 옵션은 요구 레벨을 탄다. 안 그러면 200레벨 장비의 공격력 +3은 붙으나 마나
  - 1등급 최대가 그 자리 기본의 3할쯤, 10등급 최대가 기본을 조금 넘는 선으로 잡았다
- 저장 형태: `ItemStack.options: { kind, value }[]`. 퍼센트는 **퍼센트 포인트 정수**로
  저장하고, `stackStats` 가 `/100` 해서 비율로 바꾼다. 화면과 판정이 다른 단위를
  쓰면 언젠가 100을 한 번 더 곱하거나 빼먹는다.
- 굴리는 시점(전부 서버): **드롭 · 상점 구입 · 새로 만들기 · 등급 올리기(재굴림)**.
  등급을 올리면 범위가 넓어지므로 다시 굴린다. 안 그러면 10등급인데 1등급 범위
  옵션이 박힌 물건이 남는다.
- `sanitizeOptions(raw, item, grade)` — 저장값을 지금 규칙으로 다시 자른다.
  종류 중복·범위 초과·없는 종류를 걸러낸다.

### 강화 (+0 ~ +10)
- **기본 수치에 곱한다**: `enhanceMultiplier(n) = 1 + n*0.08`.
- 골드만 쓴다: `enhanceCost(item, n) = round(item.price * 2 * (n+1))`.
- 확률(`enhanceOdds`):

  | 구간 | 성공 | 유지 | 파괴 |
  |---|---|---|---|
  | +0~3 | 95% | 5% | 0% |
  | +4~6 | 70% | 30% | 0% |
  | +7~8 | 45% | 45% | 10% |
  | +9~10 | 30% | 50% | 20% |

- 파괴되면 아이템이 가방에서 사라진다. **골드는 결과와 무관하게 항상 소비**된다.
- 굴림은 서버(`rollEnhance(level, Math.random())`). 클라이언트는 결과만 받는다.

### 능력치 계산
```
baseBonus(item, enhance)        기본(고정) × 강화
stackStats(stack)               기본 + 옵션 → ItemStats
equipmentStats(equipped)        장착 8칸 합
```
`ItemStats = { attack, defense, maxHp, crit, critDamage, attackSpeed }`

장신구(반지·목걸이·귀걸이)와 마법서는 원래 **마나를 주던 자리**였다. 마나를
걷어내면서 그 몫을 공격과 체력으로 옮겼다 — 안 그러면 여덟 자리 중 셋이
빈 물건이 된다.

### 제작
창은 `craftWindow.ts` 하나다. 대장간에서만 열리고 탭이 셋이다 —
**새로 만들기 / 강화 / 등급 올리기**. 자세한 건 [npc-town.md](npc-town.md).

- **등급 올리기**: 같은 단계 보스 재료 `targetGrade - 1` 개 + 수수료.
  낮은 단계 재료로 최상위를 올릴 수 있으면 초반 보스만 반복하면 끝난다.
- **새로 만들기(forge)**: 재료 `FORGE_MATERIALS = 5` 개 + `price * 1.5`.
  1등급으로 나온다. 드롭은 슬롯 8종에 퍼지지만 운이라 투구만 끝내 안 나오는
  일이 생긴다. 그때 원하는 자리를 직접 채운다.

### 드롭
- `DROP_CHANCE = 0.14`. **잡은 사람이 쓸 수 있는 것만** 나온다 (직업 무기 필터).
  못 쓰는 물건이 가방을 채우면 정리가 일이 되고, 거래가 없는 지금은 그냥 쓰레기다.
- 보스는 재료 `BOSS_MATERIALS = 3` 개를 **반드시** 떨군다. 최상위로 가는 유일한
  길이라 운에 맡기면 15분을 기다린 값이 안 된다.

## 손댈 때

- 수치 균형을 만질 거면 `optionGradeScale` 하나만 건드려도 옵션 전체가 같이 움직인다.
- 옵션 종류를 추가하면: `OptionKind` → `OPTION_KINDS` → `OPTION_LABEL` →
  `baseOptionRange` → `stackStats` 의 switch → (능력치면) `ItemStats` 와
  `ZoneRoom.statsOf` → 전투에서 소비하는 자리. 여섯 군데다.
- 저장 형식을 바꾸면 `db.ts` 의 `toStack`/`withOptions` 를 반드시 같이 고친다.
  **기존 캐릭터의 가방을 깨뜨리면 안 된다.**

## 관련

[inventory-equipment.md](inventory-equipment.md) · [combat.md](combat.md) · [npc-town.md](npc-town.md) · [persistence.md](persistence.md)
