import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ATTACK_ROOT_MS,
  ATTACK_SPEED_CAP,
  attackRootMs,
  MONSTER_SWING_MS,
  monsterRootMs,
  BASE_CRIT,
  BASE_CRIT_DAMAGE,
  CRIT_CAP,
  MAX_LEVEL,
  applyExp,
  computeDamage,
  effectiveCooldown,
  expReward,
  expToNext,
  rollCrit,
  statsFor,
} from './combat.ts';
import { JOB_IDS } from './character.ts';

test('직업마다 성격이 수치로 갈린다', () => {
  const fighter = statsFor('fighter', 1);
  const mage = statsFor('mage', 1);
  const archer = statsFor('archer', 1);

  assert.ok(fighter.maxHp > mage.maxHp, '격투가가 마법사보다 단단하다');
  assert.ok(fighter.defense > archer.defense, '격투가가 궁수보다 방어가 높다');
  // 설계에서 마법사와 궁수는 공격 배수가 같다(1.35). 대신 궁수가 더 단단하고,
  // 사거리(카이팅) 이점이 있어 공격 간격이 느리다 — 전투력은 ±10% 안에 든다
  assert.equal(mage.attack, archer.attack, '마법사와 궁수는 공격 배수가 같다');
  assert.ok(archer.maxHp > mage.maxHp, '궁수가 마법사보다 단단하다');
  assert.ok(archer.defense > mage.defense, '궁수가 마법사보다 방어가 높다');
  assert.ok(archer.attackRange > fighter.attackRange, '궁수가 더 멀리 닿는다');
  assert.ok(fighter.attackCooldown < mage.attackCooldown, '격투가가 더 자주 때린다');

  assert.ok(fighter.attackCooldown < archer.attackCooldown, '격투가가 가장 자주 때린다');
  assert.ok(fighter.attackRange < archer.attackRange, '격투가가 가장 붙어서 싸운다');
  assert.ok(fighter.maxHp > archer.maxHp, '격투가가 궁수보다 단단하다');
});

test('레벨이 오르면 스탯이 오른다', () => {
  const low = statsFor('fighter', 1);
  const high = statsFor('fighter', 10);
  assert.ok(high.maxHp > low.maxHp);
  assert.ok(high.attack > low.attack);
  // 사거리와 쿨타임은 레벨로 변하지 않는다 (장비/스킬의 몫)
  assert.equal(high.attackRange, low.attackRange);
  assert.equal(high.attackCooldown, low.attackCooldown);
});

test('방어가 아무리 높아도 피해는 0 이 되지 않는다', () => {
  // 0 이 되면 전투가 영원히 끝나지 않는다
  assert.ok(computeDamage(10, 9999) >= 1);
  assert.ok(computeDamage(1, 1000) >= 1);
});

test('방어는 피해를 줄이되 역전시키지 않는다', () => {
  const noArmor = computeDamage(100, 0);
  const someArmor = computeDamage(100, 45);
  const heavyArmor = computeDamage(100, 200);

  assert.equal(noArmor, 100, '방어가 없으면 그대로 들어간다');
  assert.ok(someArmor < noArmor);
  assert.ok(heavyArmor < someArmor);
  assert.ok(heavyArmor > 0);
});

test('경험치가 넘치면 레벨이 오른다', () => {
  const need = expToNext(1);
  const stay = applyExp(1, 0, need - 1);
  assert.equal(stay.level, 1);
  assert.equal(stay.exp, need - 1);

  const up = applyExp(1, 0, need);
  assert.equal(up.level, 2);
  assert.equal(up.exp, 0);
});

test('한 번에 여러 레벨이 오를 수 있다', () => {
  const huge = applyExp(1, 0, expToNext(1) + expToNext(2) + expToNext(3));
  assert.equal(huge.level, 4);
  assert.equal(huge.exp, 0);
});

test('최대 레벨에서는 경험치가 쌓이지 않는다', () => {
  const capped = applyExp(MAX_LEVEL, 0, 999999);
  assert.equal(capped.level, MAX_LEVEL);
  assert.equal(capped.exp, 0, '더 오를 곳이 없으면 남은 경험치도 버린다');
});

test('경험치는 음수로 줄지 않는다', () => {
  const result = applyExp(3, 10, -500);
  assert.equal(result.level, 3);
  assert.equal(result.exp, 10);
});

test('경험치에는 레벨 차이 보정이 없다', () => {
  // 설계에서 경험치는 몬스터 HP 에 정비례한다 — 약한 몬스터는 HP 가 작아 이미
  // 보상이 작으므로 따로 깎을 이유가 없다. 위쪽 한계는 경험치가 아니라 **사망**이
  // 정한다(+20레벨이면 그룹을 정리하기 전에 죽는다).
  for (const monsterLevel of [1, 6, 10, 14, 200]) {
    assert.equal(expReward(monsterLevel, 10, 100), 100, `Lv${monsterLevel} 에서 깎였다`);
  }
  // 몬스터 HP 가 곧 보상이라, 아래 사냥터는 저절로 손해가 된다
  assert.ok(MONSTER_KINDS['mob003']!.expReward < MONSTER_KINDS['mob098']!.expReward);
});

test('레벨업 직전 경험치는 다음 레벨로 이월된다', () => {
  const need = expToNext(1);
  // 절반 쌓인 상태에서 딱 필요한 만큼 더 받으면, 남는 만큼이 다음 레벨로 넘어간다
  const half = Math.floor(need / 2);
  const result = applyExp(1, half, need);
  assert.equal(result.level, 2);
  assert.equal(result.exp, half, '초과분이 사라지지 않는다');
});

test('공격 경직은 공격 간격보다 짧다 — 때리는 사이에 움직일 틈이 남는다', () => {
  for (const job of JOB_IDS) {
    // 공격 속도 상한까지 붙은 최악의 경우로 본다 (간격이 절반이 된다)
    const cooldown = effectiveCooldown(statsFor(job, 1).attackCooldown, ATTACK_SPEED_CAP);
    const root = attackRootMs(cooldown);
    assert.ok(root > 0, `${job}: 경직이 0 이면 휘두르며 달린다`);
    assert.ok(root <= cooldown, `${job}: 경직 ${root} 이 간격 ${cooldown} 을 넘으면 영영 못 움직인다`);
  }
  // 간격이 넉넉하면 경직은 모션 길이(ATTACK_ROOT_MS)로 고정이다
  assert.equal(attackRootMs(5000), ATTACK_ROOT_MS);
});

test('몬스터 경직은 공격 간격보다 짧다 — 때리는 사이에 쫓아올 틈이 남는다', () => {
  for (const [id, kind] of Object.entries(MONSTER_KINDS)) {
    const root = monsterRootMs(kind.attackCooldown);
    assert.ok(root > 0, `${id}: 경직이 0 이면 휘두르며 달린다`);
    assert.ok(
      root <= kind.attackCooldown,
      `${id}: 경직 ${root} 이 간격 ${kind.attackCooldown} 을 넘으면 붙어서 굳는다`
    );
    // 클라이언트가 공격 클립에서 잘라 트는 창과 같은 길이여야 한다 (modelRig 의 BEAST_ATTACK_WINDOWS)
    assert.equal(root, Math.min(MONSTER_SWING_MS, kind.attackCooldown));
  }
});

// ---------------------------------------------------------------- 레벨 곡선
// 곡선은 숫자 하나만 바꿔도 체감이 크게 달라지는데, 플레이로 확인하려면 몇 시간이
// 걸린다. 그래서 "1 → 만렙까지 몇 마리를 잡아야 하는가" 를 계산으로 붙잡아 둔다.

import { MONSTER_KINDS } from './monsters.ts';
import { RUN_SPEED } from './constants.ts';
import { killsPerLevel, monster as designMonster } from './balance.ts';

// 레벨당 필요 마릿수는 더 이상 여기서 재구성하지 않는다 — 설계(balance.ts)가
// 목표 시간(2,880시간)에서 역산한 값을 갖고 있으므로, 그것과 맞물리는지만 본다

test('필요 경험치는 레벨이 오를수록 늘어난다', () => {
  for (let level = 1; level < MAX_LEVEL; level++) {
    assert.ok(expToNext(level + 1) > expToNext(level), `Lv${level} 에서 역전된다`);
  }
});

test('몬스터 레벨이 5 간격으로 놓여 있다', () => {
  // 간격이 벌어지면 그 사이 레벨에서 경험치 감쇠가 커져 레벨당 마릿수가 튄다
  // 보스는 사냥터마다 한 마리씩 따로 끼어 있으므로 간격 검사에서 뺀다
  const levels = Object.values(MONSTER_KINDS)
    .filter((k) => !k.boss)
    .map((k) => k.level)
    .sort((a, b) => a - b);
  for (let i = 1; i < levels.length; i++) {
    assert.equal(levels[i]! - levels[i - 1]!, 5, `${levels[i - 1]} → ${levels[i]} 간격이 5가 아니다`);
  }
  assert.ok(levels[levels.length - 1]! >= MAX_LEVEL - 4, '만렙 직전에 잡을 몬스터가 없다');
});

test('필요 경험치와 몬스터 보상이 설계 곡선과 맞물린다', () => {
  // `expToNext` 는 balance.ts 의 성장 곡선에서, 몬스터 보상은 같은 곳의 HP×0.2 에서
  // 나온다. 둘을 나누면 설계가 정한 "레벨당 필요 킬 수" 가 그대로 나와야 한다 —
  // 어느 한쪽만 손대면 여기서 걸린다
  for (const level of [1, 11, 31, 91, 141, 191]) {
    const perKill = designMonster(level).exp;
    const got = expToNext(level) / perKill;
    const want = killsPerLevel(level);
    assert.ok(
      Math.abs(got / want - 1) < 0.01,
      `Lv${level}: ${Math.round(got)}마리인데 설계는 ${Math.round(want)}마리`
    );
  }
});

test('레벨당 마릿수는 초반이 가볍고 뒤로 갈수록 가파르다', () => {
  // 첫 레벨은 138마리(2분), 마지막은 132만 마리(101시간). 초반 세 구간이 2 → 3 →
  // 4.5분으로 완만히 오르고 Lv31 에서 ×2.3 뛰는데, 그 자리는 **의도적**이다 —
  // Lv30 에 3번째 스킬이 열리고 Lv31 에 등급2 장비가 열려 두 단계 강해진다
  assert.ok(killsPerLevel(1) < 200, `첫 레벨에 ${Math.round(killsPerLevel(1))}마리는 많다`);
  // 한 사냥터 안에서는 요구량이 같으므로 **구간 경계**에서만 오른다
  for (const field of [2, 4, 10, 16, 20]) {
    const start = (field - 1) * 10 + 1;
    assert.ok(
      killsPerLevel(start) > killsPerLevel(start - 1),
      `사냥터 ${field} 초입(Lv${start})에서 역전된다`
    );
  }
  assert.ok(killsPerLevel(199) > killsPerLevel(1) * 1000, '마지막이 첫 레벨보다 훨씬 무겁다');
});


// ---------------------------------------------------------------- 치명타·공격 속도

/**
 * 옵션으로만 붙는 두 축.
 *
 * 여덟 자리에 옵션이 3개씩 붙으므로 상한이 없으면 치명타 100%, 공격 간격 0 이
 * 나온다. 상한이 실제로 작동하는지는 눈으로 못 본다.
 */

test('치명타 확률은 상한에서 멈춘다', () => {
  assert.equal(rollCrit(0, 0), false, '0% 는 절대 안 터진다');
  assert.equal(rollCrit(1, 0.5), true);
  // 굴림값이 상한보다 크면, 확률을 아무리 올려도 안 터진다
  assert.equal(rollCrit(999, CRIT_CAP + 0.01), false, `상한(${CRIT_CAP})을 넘었다`);
  assert.equal(rollCrit(999, CRIT_CAP - 0.01), true);
  assert.equal(rollCrit(-5, 0), false, '음수여도 안전해야 한다');
});

test('공격 속도는 간격을 줄이되 0 으로 만들지 않는다', () => {
  const base = 900;
  assert.equal(effectiveCooldown(base, 0), base, '옵션이 없으면 그대로여야 한다');
  assert.ok(effectiveCooldown(base, 0.2) < base, '빨라지지 않았다');
  assert.equal(effectiveCooldown(base, ATTACK_SPEED_CAP), Math.round(base / (1 + ATTACK_SPEED_CAP)));
  assert.equal(
    effectiveCooldown(base, 99),
    effectiveCooldown(base, ATTACK_SPEED_CAP),
    `상한(+${ATTACK_SPEED_CAP * 100}%)을 넘어도 더 빨라지면 안 된다`
  );
  assert.ok(effectiveCooldown(base, 99) > 0);
});

test('치명타·공속은 맨몸에서 0 이다 — 전부 장비에서 온다', () => {
  // 설계에서 치확은 목걸이, 공속은 반지 전담이다. 맨몸에 바탕값을 주면
  // 등급 1~2 에서도 치명타가 터져 몬스터 HP 가 작은 초반에 타수 편차가 커진다
  for (const job of JOB_IDS) {
    const stats = statsFor(job, 50);
    assert.equal(stats.crit, 0, `${job} 의 바탕 치명타가 0 이 아니다`);
    assert.equal(stats.critDamage, 1, '맨몸 치명타 피해는 배수 1');
    assert.equal(stats.attackSpeed, 0, '공격 속도는 장비로만 얻는다');
  }
});

// --- 보스 범위 공격 -------------------------------------------------------
// 예고하고 터지는 공격은 "피할 수 있는가" 하나로 서고 넘어진다. 반지름을 키우거나
// 예고 시간을 줄이면 어느 순간 붙어 있는 직업은 절대 못 피하게 되는데, 그건
// 화면에서 "가끔 크게 아프다"로만 보여서 수치를 봐야 알 수 있다. 그래서 검사한다.

test('범위 공격은 보스만 가진다', () => {
  for (const kind of Object.values(MONSTER_KINDS)) {
    if (kind.boss) {
      assert.ok(kind.aoe, `${kind.id} 보스인데 범위 공격이 없다`);
    } else {
      assert.equal(kind.aoe, undefined, `${kind.id} 일반 몬스터에 범위 공격이 붙었다`);
    }
  }
});

test('붙어서 때리던 자리에서 예고 시간 안에 원 밖으로 나갈 수 있다', () => {
  for (const kind of Object.values(MONSTER_KINDS)) {
    if (!kind.aoe) continue;
    // 평타를 맞고 있던 거리에서 출발한다 (그게 가장 불리한 자리다)
    const escape = kind.aoe.radius - kind.attackRange;
    const need = escape / RUN_SPEED;
    const have = kind.aoe.windupMs / 1000;
    assert.ok(have > need, `${kind.id}: 빠져나가는 데 ${need.toFixed(2)}초 걸리는데 예고는 ${have}초`);
    // 반대로 너무 넉넉하면 걸어 나가도 피해져서 공격이 아니라 연출이 된다
    assert.ok(have < need * 3, `${kind.id}: 예고가 ${have}초로 너무 길다`);
  }
});

test('범위 공격 반경이 화면 안에 들어온다', () => {
  // 자기 중심 범위기는 8 이하라는 스킬 쪽 규칙과 같은 눈금을 쓴다.
  // 더 넓으면 화면 밖에서 맞아 무슨 일이 일어났는지 알 수 없다.
  for (const kind of Object.values(MONSTER_KINDS)) {
    if (!kind.aoe) continue;
    assert.ok(kind.aoe.radius > kind.attackRange, `${kind.id}: 범위가 평타 사거리보다 좁다`);
    assert.ok(kind.aoe.radius <= 8, `${kind.id}: 범위 ${kind.aoe.radius} 는 화면 밖까지 닿는다`);
  }
});

test('범위 공격은 평타보다 아프지만 한 방에 죽이지는 않는다', () => {
  for (const kind of Object.values(MONSTER_KINDS)) {
    if (!kind.aoe) continue;
    const aoeAttack = Math.round(kind.attack * kind.aoe.power);
    assert.ok(aoeAttack > kind.attack, `${kind.id}: 범위 공격이 평타보다 약하다`);

    // 그 보스를 잡으러 올 만한 레벨(보스 레벨 ±1)의 직업들로 본다.
    for (const job of JOB_IDS) {
      const stats = statsFor(job, Math.max(1, kind.level));
      const taken = computeDamage(aoeAttack, stats.defense);
      const share = taken / stats.maxHp;
      assert.ok(
        share < 0.5,
        `${kind.id} → ${job}: 한 방에 최대 체력의 ${(share * 100).toFixed(0)}% 가 날아간다`
      );
      assert.ok(share > 0.02, `${kind.id} → ${job}: 피할 이유가 없을 만큼 안 아프다 (${(share * 100).toFixed(1)}%)`);
    }
  }
});
