# 몬스터와 레벨 곡선

## 무엇

일반 몬스터 40종(존당 2종) + 보스 20종. 능력치는 전부 **레벨에서 뽑는다.**

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/monsters.ts` | 종류 60개 생성, 능력치 공식 |
| `packages/shared/src/combat.ts` | 레벨 곡선(`expToNext`), 경험치 보상(`expReward`) |
| `packages/shared/src/combat.test.ts` | 곡선이 감당 범위인지 검사 |
| `packages/server/src/combat.ts` | 몬스터 AI (idle → chase → attack → 복귀) |

## 규칙

### 배치
- 존 인덱스 `i` 의 일반 몬스터 레벨: `tierLevels(i)` → 5 간격 (3, 8, 13, … 198).
- 보스 레벨: `bossLevel(i) = i * 10 + 9`.
- 5 간격인 이유: 사냥감보다 5레벨 이상 앞서면 경험치 감쇠가 급격히 붙어
  레벨당 필요 마릿수가 몇 배로 뛴다. 5 간격이면 항상 4레벨 안쪽에 상대가 있다.

### 능력치 (`statsForLevel`)
```
maxHp     = 20 * level + 40
attack    = 1.8 * level + 4
defense   = 2 * sqrt(level)
expReward = 4 + 7 * level
```
- **`defense` 가 √ 인 이유**: 피해 공식이 `defense/(defense+45)` 로 포화한다.
  선형으로 올리면 고레벨에서 피해가 1로 수렴해 한 마리에 40대씩 때리게 된다.
  √ 로 두면 전 구간에서 10~15대에 잡힌다.
- 보스: `maxHp ×8`, `attack ×1.25`, `scale ×1.8`, `boss: true`,
  그리고 **범위 공격 `aoe: BOSS_AOE`** — 예고하고 터지는 원.
  일반 몬스터에는 붙이지 않는다. 사냥터를 지나다니는 것 자체가 피하기 놀이가
  되면 정작 보스를 만났을 때 특별하지 않다. 규칙은 [combat.md](combat.md).

### 레벨 곡선
- `MAX_LEVEL = 200`, `expToNext(L) = round(55 * L^1.2)`.
- `expReward` 는 레벨 차이로 감쇠한다. 차이가 크면 0이 된다 (파워레벨링 방지).

## 손댈 때

- 몬스터 수치를 만지면 **반드시** `npm test` — 레벨당 필요 마릿수와 1→만렙
  총량이 설계 범위 안인지 검사한다.
- 피해 공식([combat.md](combat.md))을 바꾸면 `defense` 공식도 같이 봐야 한다.
  둘은 짝이다.

## 관련

[combat.md](combat.md) · [world-zones.md](world-zones.md) · [items.md](items.md)
