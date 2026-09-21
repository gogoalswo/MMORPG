/**
 * `gear.ts` 가 설계 문서와 같은 값을 내는지 전수로 본다.
 *
 * **기대값은 [stat-balance.md](../../../docs/features/stat-balance.md) 의 표를 손으로
 * 박아 둔 것이다.** 식에서 다시 계산해 비교하면 식이 틀려도 통과하므로 의미가 없다 —
 * 문서에 적힌 숫자 그대로를 적어야 둘이 어긋나는 순간 여기서 걸린다.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EQUIP_SLOTS } from './items.ts';
import {
  ENH_MAX,
  ENH_ODDS,
  GEAR_DROP_RATE,
  GEAR_ITEMS,
  GRADE_COUNT,
  SLOT_SHARE,
  dropField,
  enhanceMultiplier,
  enhanceReach,
  equipLevel,
  fullSet,
  gradeOf,
  gradeRatio,
  gradeSum,
  slotStats,
  statBudget,
  type GearStat,
} from './gear.ts';

/** 문서 3장 "등급 = 등비수열" 표의 왼쪽 세 열 */
const GRADE_TABLE = [
  { grade: 1, level: 1, sum: 35 },
  { grade: 2, level: 31, sum: 60 },
  { grade: 3, level: 61, sum: 102 },
  { grade: 4, level: 91, sum: 173 },
  { grade: 5, level: 121, sum: 295 },
  { grade: 6, level: 151, sum: 502 },
  { grade: 7, level: 181, sum: 856 },
];

test('등급 표가 설계 문서와 같다 (착용 레벨·풀셋 합)', () => {
  assert.equal(GRADE_COUNT, GRADE_TABLE.length);
  for (const row of GRADE_TABLE) {
    assert.equal(equipLevel(row.grade), row.level, `등급 ${row.grade} 착용 레벨`);
    assert.equal(Math.round(gradeSum(row.grade)), row.sum, `등급 ${row.grade} 풀셋 합`);
  }
});

test('등급은 등비수열이다 — 간격이 후반에 좁아지지 않는다', () => {
  // 문서: "등급마다 x1.7037". 등비가 아니면 최종 등급 무기를 먹어도 체감이 죽는다
  assert.equal(Math.round(gradeRatio() * 10000) / 10000, 1.7037);
  for (let g = 2; g <= GRADE_COUNT; g++) {
    const step = gradeSum(g) / gradeSum(g - 1);
    assert.ok(Math.abs(step - gradeRatio()) < 1e-9, `등급 ${g} 간격이 등비가 아니다`);
  }
});

test('레벨에서 낄 수 있는 최고 등급 — 경계가 착용 레벨과 맞는다', () => {
  for (const row of GRADE_TABLE) {
    assert.equal(gradeOf(row.level), row.grade, `Lv${row.level}`);
    if (row.grade > 1) {
      assert.equal(gradeOf(row.level - 1), row.grade - 1, `Lv${row.level - 1}`);
    }
  }
  assert.equal(gradeOf(1), 1);
  assert.equal(gradeOf(200), GRADE_COUNT, '만렙은 최고 등급');
});

test('스탯 예산 — 등급7 풀세트가 문서의 값과 같다', () => {
  // 문서: "공격력 856% / 방어력 514% / HP 300% / 치확 50% / 치피 +100% / 공속 +20% / 이동 +25%"
  const b = statBudget(7);
  assert.equal(Math.round(b.atk), 856);
  assert.equal(Math.round(b.df), 514);
  assert.equal(Math.round(b.hp), 300);
  assert.equal(b.crit, 0.5);
  assert.equal(b.critDamage, 1);
  assert.equal(b.aspd, 0.2);
  assert.equal(b.move, 0.25);
});

test('치명타·공속은 등급에 선형이다 — 등급1 은 0 이다', () => {
  // 초반에 치명타가 붙으면 몬스터 HP 가 작아 타수 편차가 커진다
  const one = statBudget(1);
  assert.equal(one.crit, 0);
  assert.equal(one.aspd, 0);
  assert.equal(one.move, 0);
  // 문서 표의 치확 열: 0 / 8 / 17 / 25 / 33 / 42 / 50 (%)
  const want = [0, 8, 17, 25, 33, 42, 50];
  for (let g = 1; g <= GRADE_COUNT; g++) {
    assert.equal(Math.round(statBudget(g).crit * 100), want[g - 1], `등급 ${g} 치확`);
  }
});

test('슬롯 지분은 스탯마다 합이 100% 다', () => {
  // 2026-09-21 에 치확·치피·공속 버킷을 걷었다 — 장비 기본은 공/방/HP 셋뿐이고
  // 이동속도만 신발 전담으로 남았다. 걷은 스탯은 지분이 0 이라 합을 안 본다
  const stats: GearStat[] = ['atk', 'df', 'hp', 'move'];
  for (const stat of stats) {
    const total = EQUIP_SLOTS.reduce((sum, slot) => sum + (SLOT_SHARE[slot][stat] ?? 0), 0);
    assert.ok(Math.abs(total - 1) < 1e-9, `${stat} 지분 합이 ${total}`);
  }
  for (const stat of ['crit', 'critDamage', 'aspd'] as GearStat[]) {
    const total = EQUIP_SLOTS.reduce((sum, slot) => sum + (SLOT_SHARE[slot][stat] ?? 0), 0);
    assert.equal(total, 0, `${stat} 는 장비 기본에서 걷었다`);
  }
});

test('목걸이·반지가 무기·갑옷의 정확히 절반이다', () => {
  // 2026-09-21 지시: "공격력 방어력 hp를 무기랑 방어구의 수치 반만 넣어"
  for (const grade of [1, 4, 7]) {
    const w = slotStats('weapon', grade);
    const a = slotStats('armor', grade);
    for (const slot of ['necklace', 'ring'] as const) {
      const s = slotStats(slot, grade);
      assert.ok(Math.abs(s.atk - w.atk / 2) < 1e-9, `${slot} 공격력이 무기의 절반이 아니다`);
      assert.ok(Math.abs(s.df - a.df / 2) < 1e-9, `${slot} 방어력이 갑옷의 절반이 아니다`);
      assert.ok(Math.abs(s.hp - a.hp / 2) < 1e-9, `${slot} HP 가 갑옷의 절반이 아니다`);
    }
  }
});

test('등급7 슬롯 수치 (무강 → 강화 4단)', () => {
  // 2026-09-21 에 배분을 바꿨다 — 무기 0.6→0.5, 갑옷 0.4→1/3,
  // 장신구가 그 절반(0.25 / 1/6). **풀세트 합은 그대로**다
  const at = (slot: Parameters<typeof slotStats>[0], step: number) => slotStats(slot, 7, step);
  const r = (v: number) => Math.round(v);

  assert.equal(r(at('weapon', 1).atk), 428);
  assert.equal(r(at('weapon', 4).atk), 558);

  assert.equal(r(at('armor', 1).df), 171);
  assert.equal(r(at('armor', 4).df), 223);
  assert.equal(r(at('armor', 1).hp), 100);
  assert.equal(r(at('armor', 4).hp), 130);

  assert.equal(r(at('helmet', 1).df), 86);
  assert.equal(r(at('helmet', 4).df), 112);
  assert.equal(r(at('helmet', 1).hp), 50);
  assert.equal(r(at('helmet', 4).hp), 65);

  // 신발은 투구와 같은 수치에 이동속도만 더 붙는다
  assert.equal(r(at('boots', 4).df), 112);
  assert.equal(r(at('boots', 1).move * 100), 25);

  for (const slot of ['necklace', 'ring'] as const) {
    assert.equal(r(at(slot, 1).atk), 214, `${slot} 공격력`);
    assert.equal(r(at(slot, 4).atk), 279, `${slot} 공격력(4단)`);
    assert.equal(r(at(slot, 1).df), 86, `${slot} 방어력`);
    assert.equal(r(at(slot, 4).df), 112, `${slot} 방어력(4단)`);
    assert.equal(r(at(slot, 1).hp), 50, `${slot} HP`);
    assert.equal(r(at(slot, 4).hp), 65, `${slot} HP(4단)`);
  }
  // 치확·공속은 장비 기본에서 걷었다 — 랜덤 옵션으로만 붙는다
  assert.equal(at('necklace', 1).crit, 0);
  assert.equal(at('ring', 1).aspd, 0);
});

test('강화는 %스탯에만 곱한다 — 치명타·공속은 그대로다', () => {
  // 두 곱산 버킷이 동시에 강화되면 총 배수 상한을 관리할 수 없다
  const bare = slotStats('necklace', 7, 1);
  const maxed = slotStats('necklace', 7, ENH_MAX);
  assert.ok(maxed.atk > bare.atk * 5, '공격력은 커져야 한다');
  assert.equal(maxed.crit, bare.crit);
  assert.equal(maxed.critDamage, bare.critDamage);
  assert.equal(slotStats('ring', 7, ENH_MAX).aspd, slotStats('ring', 7, 1).aspd);
  assert.equal(slotStats('boots', 7, ENH_MAX).move, slotStats('boots', 7, 1).move);
});

test('강화 배수·도달률이 문서 4장 표와 같다', () => {
  // 배수 행: x1.00 1.07 1.17 1.30 1.50 1.78 2.20 2.88 4.00 6.00
  const mult = [1.0, 1.07, 1.17, 1.3, 1.5, 1.78, 2.2, 2.88, 4.0, 6.0];
  for (let step = 1; step <= ENH_MAX; step++) {
    const got = Math.round(enhanceMultiplier(step) * 100) / 100;
    assert.equal(got, mult[step - 1], `${step}단 배수`);
  }
  // 도달률 행: 100 / 90 / 72 / 50 / 30 / 15 / 6.0 / 1.8 / 0.36 / 0.036 (%)
  const reach = [100, 90, 72, 50.4, 30.24, 15.12, 6.048, 1.8144, 0.36288, 0.036288];
  for (let step = 1; step <= ENH_MAX; step++) {
    const got = enhanceReach(step) * 100;
    assert.ok(Math.abs(got - reach[step - 1]!) < 1e-9, `${step}단 도달률 ${got}`);
  }
  assert.equal(ENH_ODDS.length, ENH_MAX - 1, '성공률은 2단부터라 아홉 개다');
});

test('드랍 사냥터는 착용 레벨보다 한 구간 위다', () => {
  // 문서 3장 "드랍 사냥터" 표: 2 / 5 / 8 / 11 / 14 / 17 / 20
  const want = [2, 5, 8, 11, 14, 17, 20];
  for (let g = 1; g <= GRADE_COUNT; g++) {
    assert.equal(dropField(g), want[g - 1], `등급 ${g}`);
  }
  assert.equal(GEAR_DROP_RATE.length, GRADE_COUNT);
  for (let g = 1; g < GRADE_COUNT; g++) {
    assert.ok(GEAR_DROP_RATE[g]! < GEAR_DROP_RATE[g - 1]!, `등급 ${g + 1} 드랍률이 더 높다`);
  }
});

test('아이템은 42종 — 등급 7 x 슬롯 6', () => {
  const items = Object.values(GEAR_ITEMS);
  assert.equal(items.length, GRADE_COUNT * EQUIP_SLOTS.length);
  assert.equal(items.length, 42);

  for (const item of items) {
    assert.equal(item.id, item.id.toLowerCase(), `${item.id} 는 소문자여야 한다`);
    assert.equal(item.level, equipLevel(item.grade), `${item.id} 착용 레벨`);
    assert.ok(item.name.length > 0, `${item.id} 이름`);
    // 2026-09-21: 장비가 직업을 안 탄다 — 무기도 한 벌이다
    assert.equal(item.job, undefined, `${item.id} 가 직업을 탄다`);
  }

  // 같은 이름이 둘 있으면 가방에서 구분이 안 된다
  const names = items.map((i) => i.name);
  assert.equal(new Set(names).size, names.length, '이름이 겹친다');
});

test('풀세트 6칸이 등급 예산을 정확히 나눠 갖는다', () => {
  for (let g = 1; g <= GRADE_COUNT; g++) {
    const set = fullSet(g);
    assert.equal(set.length, EQUIP_SLOTS.length);
    const sum = set.reduce((t, item) => t + item.stats.atk, 0);
    assert.ok(Math.abs(sum - gradeSum(g)) < 1e-9, `등급 ${g} 공격력 합이 ${sum}`);
  }
});

test('등급이 오르면 모든 슬롯이 모든 축에서 세진다', () => {
  // 어느 한 칸이라도 뒤집히면 "갈아입을 이유" 가 사라진다
  for (const slot of EQUIP_SLOTS) {
    for (let g = 2; g <= GRADE_COUNT; g++) {
      const lo = slotStats(slot, g - 1);
      const hi = slotStats(slot, g);
      for (const stat of Object.keys(hi) as GearStat[]) {
        if (lo[stat] === 0 && hi[stat] === 0) continue;
        assert.ok(hi[stat] > lo[stat], `${slot} ${stat} 이 등급 ${g} 에서 안 올랐다`);
      }
    }
  }
});
