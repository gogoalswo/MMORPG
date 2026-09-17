# 몬스터와 레벨 곡선

## 무엇

일반 몬스터 40종(존당 2종) + 보스 20종. 능력치는 전부 **레벨에서 뽑는다.**

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/monsters.ts` | 종류 60개 생성, 능력치 공식 |
| `packages/shared/src/combat.ts` | 레벨 곡선(`expToNext`), 경험치 보상(`expReward`) |
| `packages/shared/src/combat.test.ts` | 곡선이 감당 범위인지 검사 |
| `packages/server/src/combat.ts` | 옛 몬스터 AI (idle → chase → attack → 복귀). 이식 원본 |
| `godot/world/world.gd` | **지금 도는 몬스터 AI** — `_step_monsters`(상태 기계) · `_patrol`(순찰) |
| `godot/tests/aggro_test.gd` | 어그로·추적·반격·사망 확인 |
| `godot/tests/patrol_test.gd` | 순찰 확인 (목적지·반경·쉬는 시각·어그로 우선) |

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

### 순찰 (쫓을 사람이 없을 때) ★

쫓을 사람이 없는 몬스터는 **집 주변을 서성인다.** `godot/world/world.gd` 의
`_patrol` 이고, 상수도 그 파일 위쪽에 있다.

| 상수 | 값 | 뜻 |
|---|---|---|
| `PATROL_RADIUS` | 4.0 m | 집에서 이 반경 안에서만 돈다 |
| `PATROL_SPEED` | 0.35 | 제 이동 속도의 이만큼 (걷는 것처럼) |
| `PATROL_ARRIVE` | 0.3 m | 이만큼 붙으면 도착 |
| `PATROL_REST_MIN/MAX_MS` | 2000~6000 | 한 다리 걷고 쉬는 시간 |

한 다리 = `[반경×0.4, 반경]` 안의 아무 자리로 걸어가기. 닿으면 다음 자리를 뽑고
`REST` 만큼 쉰다. 쉬는 동안 상태는 `idle`, 걷는 동안은 `patrol` 이다.

- **왜 돌아다니나** — 선 채로 굳어 있으면 죽은 것처럼 보인다.
- **왜 반경이 어그로(보통 9m)보다 작나** — 순찰이 사람에게 먼저 닿으면
  "가만히 있었는데 몬스터가 찾아와 때렸다" 가 된다. 4m 를 다 걸어 나와도
  어그로 범위 안쪽이라, 먼저 거는 쪽은 여전히 어그로다.
- **왜 쉬는 시각을 놈마다 다르게 뽑나** — 같으면 무리가 한 몸처럼 움직인다.
  처음에는 `patrol_rest_until` 이 0 이라 첫 판정에서 곧바로 목적지를 뽑고
  각자 다른 시각까지 쉬기 시작한다.
- **왜 쉬는 시간이 있나** — 쉬는 동안은 `_move_monster` 를 안 부르니
  몬스터끼리 미는 계산도 쉬어 간다. 한 존에 80마리라 폰에서는 이게 크다.
- 집에서 반경보다 멀리 나와 있으면(쫓다가 대상을 잃은 뒤) 먼저 집 쪽으로
  **반 속도**로 걸어 돌아온다. 상태는 `patrol` 이다.
- 순찰보다 먼저 보는 것들: 예고해 둔 범위 공격, 공격 경직, leash 복귀, 대상 탐색.
  즉 **어그로가 순찰을 언제나 이긴다.**

화면(`godot/game/game.gd`)은 `patrol` 을 **달리기 클립 반 배속**으로 그린다 —
걷기 클립이 따로 없다.

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
