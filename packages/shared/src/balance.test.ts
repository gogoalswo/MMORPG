/**
 * `balance.ts` 가 설계 문서와 같은 값을 내는지 본다.
 *
 * `gear.test.ts` 와 같은 규칙이다 — **기대값은 문서의 표를 손으로 박아 둔 것**이고,
 * 식에서 다시 계산해 비교하지 않는다. 그래야 문서와 코드가 어긋나는 순간 걸린다.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JOB_IDS } from './character.ts';
import {
  CLEAR_TIME,
  EXP_COEF,
  HP_LOSS_PER_CLEAR,
  JOB_MULT,
  K,
  MAX_LEVEL,
  MON_DEF_RATIO,
  ROLE_MULT,
  TARGET_REDUCE,
  TTK_HITS,
  aoeTargets,
  balanceTable,
  base,
  damage,
  dropLevels,
  enhRefStep,
  fieldOf,
  killsPerLevel,
  levelSeconds,
  expToNext,
  meleeAttackers,
  monster,
  refGrade,
  refPlayer,
  refWorn,
  spawnCount,
} from './balance.ts';

test('기본 스탯은 레벨당 복리 ×1.02 다', () => {
  // 문서 2장: Lv1 HP100/공10/방10 → Lv200 맨몸 HP 5,146 / 공 515 / 방 515
  const one = base(1);
  assert.equal(one.hp, 100);
  assert.equal(one.atk, 10);
  assert.equal(one.df, 10);

  const top = base(MAX_LEVEL);
  assert.equal(Math.round(top.hp), 5146);
  assert.equal(Math.round(top.atk), 515);
  assert.equal(Math.round(top.df), 515);

  // 레벨 1개는 언제나 +2% — 구간마다 다르면 "장비 비중" 의 기준이 사라진다
  for (const level of [2, 50, 120, 199]) {
    const step = base(level + 1).atk / base(level).atk;
    assert.ok(Math.abs(step - 1.02) < 1e-12, `Lv${level} 성장률 ${step}`);
  }
});

test('피해 감소율은 전 구간에서 정확히 30% 다', () => {
  // K 를 상수로 두면 후반에 68% 까지 치솟는다. 기준 플레이어에서 역산하므로 고정된다
  for (const level of [1, 10, 50, 100, 150, 200]) {
    const ref = refPlayer(level);
    const reduce = ref.df / (K(level) + ref.df);
    assert.ok(Math.abs(reduce - TARGET_REDUCE) < 1e-12, `Lv${level} 감소율 ${reduce}`);
  }
});

test('피해는 뺄셈이 아니라 나눗셈이다 — 방어력이 커져도 0 이 되지 않는다', () => {
  const huge = damage(1000, 100, 1e9);
  assert.ok(huge >= 1, '최소 피해는 1');
  // 방어력이 두 배면 피해가 절반보다는 많이 남는다 (포화하지 않는다)
  const a = damage(1000, 100, K(100));
  const b = damage(1000, 100, K(100) * 2);
  assert.ok(b > a / 2, '나눗셈식이면 절반 아래로 떨어지지 않는다');
});

test('몬스터 표가 설계 문서 6장과 같다 (사냥터 끝 레벨)', () => {
  // | 사냥터 | 잰 레벨 | 기준 등급 | 몬스터 HP | 몬스터 ATK |
  const rows = [
    { level: 10, grade: 1.0, hp: 71, atk: 2 },
    { level: 50, grade: 1.63, hp: 214, atk: 4 },
    { level: 100, grade: 3.3, hp: 1043, atk: 14 },
    { level: 150, grade: 4.97, hp: 7044, atk: 64 },
    { level: 200, grade: 6.63, hp: 60224, atk: 394 },
  ];
  for (const row of rows) {
    assert.equal(Math.round(refGrade(row.level) * 100) / 100, row.grade, `Lv${row.level} 기준 등급`);
    const m = monster(row.level);
    assert.equal(Math.round(m.hp), row.hp, `Lv${row.level} 몬스터 HP`);
    assert.equal(Math.round(m.atk), row.atk, `Lv${row.level} 몬스터 공격력`);
  }
});

test('기준 장비로는 동레벨 몬스터를 정확히 6타에 잡는다', () => {
  // 여유(TTK_MARGIN) 덕에 기준보다 조금 모자라도 6타를 지킨다 — 경계에 얹히지 않는다
  for (let level = 1; level <= MAX_LEVEL; level += 7) {
    const ref = refPlayer(level);
    const m = monster(level);
    const hits = Math.ceil(m.hp / (damage(ref.atk, level, m.df) * ref.crit));
    assert.equal(hits, TTK_HITS, `Lv${level} 타수`);
  }
});

test('몬스터 방어력은 기준 플레이어의 절반이다 — 체력형이어야 타격감이 산다', () => {
  for (const level of [1, 77, 200]) {
    assert.ok(Math.abs(monster(level).df - refPlayer(level).df * MON_DEF_RATIO) < 1e-9);
  }
});

test('한 그룹을 정리하는 동안 HP 를 절반 잃는다', () => {
  // 몬스터 공격력이 이 목표에서 역산된 값이므로, 되짚으면 50% 가 나와야 한다
  for (const level of [15, 100, 195]) {
    const ref = refPlayer(level);
    const m = monster(level);
    const perHit = damage(m.atk, level, ref.df);
    const taken = (perHit * meleeAttackers(level) * CLEAR_TIME) / m.interval;
    assert.ok(Math.abs(taken / ref.hp - HP_LOSS_PER_CLEAR) < 1e-9, `Lv${level} ${taken / ref.hp}`);
  }
});

test('역할 배수 — 보스는 설계 보류라 임시값이다', () => {
  assert.deepEqual(ROLE_MULT.normal, { hp: 1, atk: 1 });
  assert.deepEqual(ROLE_MULT.elite, { hp: 3, atk: 2 });
  assert.deepEqual(ROLE_MULT.boss, { hp: 7, atk: 5 });
  const normal = monster(100);
  assert.equal(monster(100, 'elite').hp, normal.hp * 3);
  assert.equal(monster(100, 'boss').atk, normal.atk * 5);
  // 역할이 달라도 방어력은 그대로다 (배수는 HP·공격력에만)
  assert.equal(monster(100, 'boss').df, normal.df);
});

test('경험치는 몬스터 HP 에 정비례한다', () => {
  // 지수 1.0 — 아래 사냥터를 손해로 만들고, 위쪽 한계는 경험치가 아니라 사망이 정한다
  for (const level of [1, 60, 200]) {
    const m = monster(level);
    assert.ok(Math.abs(m.exp - m.hp * EXP_COEF) < 1e-9, `Lv${level}`);
  }
});

test('스킬 해금 단계에 그룹 크기가 묶인다', () => {
  // 문서 5장: 1 / 10 / 30 레벨에 15·8·3 → 30·14·4 → 50·20·6
  const want = [
    { level: 1, spawn: 15, aoe: 8, melee: 3 },
    { level: 9, spawn: 15, aoe: 8, melee: 3 },
    { level: 10, spawn: 30, aoe: 14, melee: 4 },
    { level: 29, spawn: 30, aoe: 14, melee: 4 },
    { level: 30, spawn: 50, aoe: 20, melee: 6 },
    { level: 200, spawn: 50, aoe: 20, melee: 6 },
  ];
  for (const row of want) {
    assert.equal(spawnCount(row.level), row.spawn, `Lv${row.level} 스폰`);
    assert.equal(aoeTargets(row.level), row.aoe, `Lv${row.level} 범위`);
    assert.equal(meleeAttackers(row.level), row.melee, `Lv${row.level} 동시 피격`);
  }
  // 50마리 × 6타 ÷ 범위 20 = 15회 시전 = 15초. 이 관계가 설계의 전제다
  assert.equal((50 * TTK_HITS) / 20, CLEAR_TIME);
});

test('기준 강화 단계는 사냥터 구간별로 4 → 7 단이다', () => {
  const want: Array<[number, number]> = [
    [1, 4],
    [6, 4],
    [7, 5],
    [12, 5],
    [13, 6],
    [17, 6],
    [18, 7],
    [20, 7],
  ];
  for (const [field, step] of want) {
    const level = field * 10; // 그 사냥터의 끝 레벨
    assert.equal(fieldOf(level), field, `Lv${level} 사냥터`);
    assert.equal(enhRefStep(level), step, `사냥터 ${field} 기준 강화`);
  }
});

test('시작 장비는 무기 한 자루뿐이고 Lv11 부터 풀세트 기준이 된다', () => {
  // 등급1 은 사냥터 2 에서야 나온다 — 그 전 구간의 몬스터를 이 상태로 낮춘다
  assert.deepEqual(dropLevels(1), [11, 20]);
  for (const level of [1, 5, 10]) {
    assert.deepEqual(refWorn(level), [['weapon', 1, 1]], `Lv${level}`);
  }
  assert.equal(refWorn(11).length, 6, 'Lv11 부터는 여섯 칸');
});

test('기준 등급 보간 — 해금 레벨에서 절벽이 생기지 않는다', () => {
  // 계단식이면 Lv120 → 121 에서 몬스터가 한 번에 1.9배 세진다
  const jump = monster(121).hp / monster(120).hp;
  assert.ok(jump < 1.25, `해금 지점에서 ×${jump.toFixed(2)} 나 뛴다`);
  // 갈아입은 직후엔 이전 등급 수준, 구간 끝에 현재 등급에 도달한다
  assert.equal(Math.round(refGrade(121) * 100) / 100, 4);
  assert.equal(Math.round(refGrade(150) * 100) / 100, 4.97);
});

test('몬스터 HP 는 레벨이 오를수록 커진다', () => {
  // 보간·강화 기준이 구간마다 바뀌므로 어딘가 뒤집히지 않는지 전수로 본다
  for (let level = 2; level <= MAX_LEVEL; level++) {
    assert.ok(monster(level).hp > monster(level - 1).hp, `Lv${level} HP 가 안 올랐다`);
  }
});

test('스킬이 열리는 자리에서 몬스터 1마리 공격력은 오히려 떨어진다', () => {
  // **의도한 것이다.** 공격력은 "동시에 때리는 마릿수" 로 나눠 역산하므로, 동시 피격이
  // 3 → 4 → 6 으로 늘면 한 마리 몫이 그만큼 작아진다. 총량(HP 50% 손실)은 그대로다.
  // 잡몹 한 마리는 위협이 아니고 무리가 위협인 구조가 여기서 나온다.
  for (const level of [10, 30]) {
    assert.ok(monster(level).atk < monster(level - 1).atk, `Lv${level} 에서 안 떨어졌다`);
    assert.ok(meleeAttackers(level) > meleeAttackers(level - 1), `Lv${level} 동시 피격`);
  }
  // 단계 안에서는 레벨을 따라 오른다
  for (let level = 31; level <= MAX_LEVEL; level++) {
    assert.ok(monster(level).atk >= monster(level - 1).atk, `Lv${level} 공격력이 줄었다`);
  }
});

test('성장 곡선 — 만렙까지 정확히 2,880시간(120일)이다', () => {
  // 목표 총 시간을 먼저 정하고 레벨당 킬 수를 거기서 역산한다
  let seconds = 0;
  for (let level = 1; level < MAX_LEVEL; level++) seconds += levelSeconds(level);
  assert.equal(Math.round((seconds / 3600) * 10) / 10, 2880);

  // 문서 7장 표의 "레벨당 킬 수" 열
  const want: Array<[number, number]> = [
    [1, 138],
    [11, 338],
    [21, 506],
    [31, 2011],
    [91, 22911],
    [141, 173980],
    [191, 1321164],
  ];
  for (const [level, kills] of want) {
    assert.equal(Math.round(killsPerLevel(level)), kills, `Lv${level} 킬 수`);
  }

  // 초반 세 구간은 레벨당 2 / 3 / 4.5분
  for (const [level, minutes] of [[1, 2], [11, 3], [21, 4.5]] as Array<[number, number]>) {
    assert.equal(Math.round((levelSeconds(level) / 60) * 10) / 10, minutes, `Lv${level} 분`);
  }
});

test('경험치 표는 레벨이 오를수록 커지고 만렙에서 끝난다', () => {
  const table = balanceTable().expTable;
  assert.equal(table.length, MAX_LEVEL);
  assert.equal(table[MAX_LEVEL - 1], 0, '만렙 다음은 없다');
  for (let i = 1; i < MAX_LEVEL - 1; i++) {
    assert.ok(table[i]! > table[i - 1]!, `Lv${i + 1} 요구량이 안 올랐다`);
  }
  // 표는 공식과 같아야 한다 (반올림만 다르다)
  assert.equal(table[99], Math.round(expToNext(100)));
});

test('직업 배수가 설계 문서 2장 표와 같다', () => {
  // 기사(knight)는 설계 문서에 있지만 게임에서는 2026-09-17 에 지웠다
  assert.deepEqual(Object.keys(JOB_MULT).sort(), [...JOB_IDS].sort());
  assert.deepEqual(JOB_MULT.fighter, { atk: 1.0, hp: 1.0, df: 1.0, interval: 0.9 });
  assert.deepEqual(JOB_MULT.mage, { atk: 1.35, hp: 0.8, df: 0.75, interval: 1.0 });
  assert.deepEqual(JOB_MULT.archer, { atk: 1.35, hp: 0.9, df: 0.85, interval: 1.2 });
});

test('직업 전투력(DPS × 버티는 시간)이 서로 ±15% 안이다', () => {
  // 어느 직업을 골라도 손해가 아니어야 한다
  const level = 100;
  const m = monster(level);
  const powers = JOB_IDS.map((job) => {
    const mult = JOB_MULT[job];
    const ref = refPlayer(level);
    const atk = (ref.atk / 1) * mult.atk;
    const hp = ref.hp * mult.hp;
    const df = ref.df * mult.df;
    const dps = (damage(atk, level, m.df) * ref.crit) / (mult.interval / 1);
    const taken = (damage(m.atk, level, df) * meleeAttackers(level)) / m.interval;
    return dps * (hp / taken);
  });
  const lo = Math.min(...powers);
  const hi = Math.max(...powers);
  assert.ok(hi / lo <= 1.15, `전투력 격차 ${(hi / lo).toFixed(2)} 배`);
});
