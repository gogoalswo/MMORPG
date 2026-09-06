# 전투

## 무엇

기본 공격과 스킬이 **같은 판정 경로**를 탄다. 치명타·공격 속도는 장비 옵션으로만 붙는다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/combat.ts` | 직업 성장표, 피해 공식, 치명타·공격 속도 규칙 |
| `packages/server/src/combat.ts` | `CombatSystem` — 명중 판정, 몬스터 AI, `HitEvent` |
| `packages/server/src/ZoneRoom.ts` | `handleAttack` / `handleSkill` / `statsOf` / `damagePlayer` |
| `packages/client/src/ui/combatHud.ts` | 피해 숫자, 상태바 |
| `packages/client/src/scene/projectiles.ts` | 화살·마법탄 |
| `packages/client/src/scene/aoeMarkers.ts` | 바닥 범위 예고 원 |

## 규칙

### 스탯
`statsFor(job, level)` → `{ maxHp, maxMp, attack, defense, attackRange, attackCooldown, crit, critDamage, attackSpeed }`

| 직업 | 성격 | 사거리 | 공격 간격 |
|---|---|---|---|
| knight | 단단하고 오래 버틴다 | 2.4 | 900ms |
| mage | 종잇장, 한 대가 아프고 멀리 닿는다 | 9 | 1300ms |
| archer | 중간, 거리를 유지하며 꾸준히 | 12 | 800ms |

- `BASE_CRIT = 0.05`, `BASE_CRIT_DAMAGE = 1.5`, `attackSpeed` 바탕은 0.
  **직업으로 가르지 않는다** — 가르면 장비 때문인지 직업 때문인지 알 수 없어진다.
- 장비를 더한 최종 스탯은 서버 `ZoneRoom.statsOf(sessionId, job, level)` 하나로만
  구한다. 여기를 거치지 않는 계산이 생기면 그 자리만 장비가 안 먹는다.

### 피해
```
computeDamage(attack, defense) = max(1, round(attack * (1 - defense/(defense+45))))
```
- 빼기가 아니라 **비율 감쇠**다. 빼기면 방어가 공격을 넘는 순간 0이 되어 전투가 멈춘다.
- 치명타: `rollCrit(chance, roll)` → 터지면 `round(base * critDamage)`.
  **대상마다 따로 굴린다** — 범위기 한 방이 통째로 터지면 피해가 뭉쳐 숫자가 튄다.
- 공격 간격: `effectiveCooldown(cooldown, attackSpeed) = round(cooldown / (1 + speed))`.

### 상한
- `CRIT_CAP = 0.75`, `ATTACK_SPEED_CAP = 1` (간격 절반까지).
- 여덟 자리에 옵션이 3개씩 붙으므로 상한이 없으면 치명타 100%가 나오고,
  그러면 다른 옵션을 고를 이유가 사라진다.
- 상한은 **쓰는 쪽**(`rollCrit` / `effectiveCooldown`)에서 자른다. `statsOf` 는 합만 낸다.

### 명중 판정 (`resolvePlayerAttack`)
- **대상은 서버가 고른다.** 클라이언트가 대상 id 를 보내게 하면 사거리 밖이나
  벽 너머를 지정할 수 있다.
- 정면 부채꼴 `ATTACK_ARC = 0.6π` 안에서 가까운 순서로 `maxTargets` 만큼.
  `arc >= 2π` 면 전방위(자기 중심 폭발).
- 시그니처 마지막 인자는 이름 붙은 객체다:
  `{ projectile?, crit?, critDamage? }`. 위치 인자를 더 붙이지 말 것.

### HitEvent
`{ targetId, targetKind, amount, killed, sourceId, x, z, crit?, heal?, projectile? }`
- **`x`/`z` 가 들어 있는 이유**: 막타를 맞은 몬스터는 같은 틱에 그리드에서
  빠져 클라이언트가 위치를 못 찾는다. 그래서 숫자가 안 뜬다. 서버가 이미 아는
  좌표를 같이 보낸다. 클라이언트는 렌더 위치를 우선 쓰고 없으면 이 값으로 떨어진다.
- 투사체가 있으면 클라이언트는 **투사체가 도착할 때** 숫자를 띄운다.
  쏘자마자 뜨면 원거리 직업이 근접처럼 보인다.

### 보스 범위 공격 ★
보스만 가진다 (`MonsterKind.aoe`, 수치는 `BOSS_AOE` 하나를 20마리가 같이 쓴다).

```
radius 7 · windupMs 1600 · cooldownMs 9000 · power 2.2 (보스 공격력 배율)
```

- **예고가 전부다.** 즉발이면 피할 수 없어서 "가끔 크게 아픈 평타"와 다르지
  않다. 원을 먼저 그려 주고, 다 차면 그 안에 있는 사람이 맞는다.
- **원은 시전을 시작한 자리에 고정된다.** 보스를 따라다니면 붙어서 때리는
  쪽은 피할 방법이 없다. 그래서 예고 중에는 보스가 **그 자리에 선다**
  (`state = 'cast'`, 이동·평타 모두 멈춤). 리쉬 복귀·대상 재탐색보다 먼저
  본다 — 한번 예고한 것은 대상이 도망가든 죽든 그대로 터진다.
- 거는 조건은 평타 사거리가 아니라 **원 안(7m)에 들어왔을 때**다. "보스 7m
  안은 위험하다" 한 줄로 설명되고, 멀리서 쏘는 직업(마법사 9 · 궁수 12)은
  자기 사거리를 지키는 것만으로 자연히 피한다.
- 수치 근거: 붙어 있던 자리(2.2m)에서 원 밖(7m)까지 4.8m, `RUN_SPEED = 4.6`
  으로 약 1.05초다. 1.6초면 반응할 틈은 있으면서 가만히 서 있으면 반드시 맞는다.
  `power 2.2` 는 전 구간에서 기사 5~15%, 마법사 25~35% 를 깎는다.
  이 관계들은 `combat.test.ts` 가 20마리 × 3직업 전수 검사한다.
- 피해는 **평타와 같은 `damagePlayer`** 를 탄다. 방어 감쇠·`hit` 방송·사망
  처리를 두 벌 만들면 반드시 한쪽만 고치는 실수가 난다.
- 격자 조회는 사각형이라 `burstAoe` 에서 **원으로 다시 자른다.** 안 자르면
  화면에 그린 원 밖에 서 있는데 맞는다.
- 클라이언트는 `aoe` 메시지로 원만 그린다. 판정에 관여하지 않으므로 이 원이
  안 떠도 맞을 사람은 맞고, 잘못 떠도 피해는 달라지지 않는다.

### 사망
- hp 0 → `dead = true`, `RESPAWN_DELAY_MS` 뒤 마을 스폰으로 부활.
- 죽으면 자동 사냥 대상과 클릭 추격이 풀린다.

## 손댈 때

- 피해 공식을 만지면 [monsters-progression.md](monsters-progression.md) 의
  `defense = 2√L` 도 같이 봐야 한다.
- 새 공격 수단을 만들 때 판정을 새로 쓰지 말 것. `handleAttack` / `handleSkill` 을
  타야 쿨타임·마나·정면각 검증이 한 벌로 유지된다. 자동 사냥도 같은 이유로
  이 둘을 그대로 호출한다.

## 관련

[items.md](items.md) · [skills.md](skills.md) · [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md)
