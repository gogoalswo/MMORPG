import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { ItemBonus } from './items.ts';
import {
  slotLabel,
  dropChanceFor,
  EQUIP_SLOTS,
  GRADE_MAX,
  GRADE_MIN,
  ITEMS,
  MAX_DROP_GRADE,
  MAX_ENHANCE,
  baseBonus,
  emptyStats,
  stackStats,
  rollOptions,
  sanitizeOptions,
  optionRange,
  optionGradeScale,
  OPTION_KINDS,
  OPTION_MIN,
  OPTION_MAX,
  isPercentOption,
  describeOption,
  canEnhance,
  enhanceCost,
  enhanceMultiplier,
  enhanceOdds,
  rollEnhance,
  canEquip,
  equipmentStats,
  getItem,
  gradeMultiplier,
  rollBossDrop,
  rollDrop,
  rollGrade,
  dropGradesFor,
  tierForLevel,
  tierLevel,
} from './items.ts';
import { optionCount } from './gear.ts';
import { MONSTER_KINDS } from './monsters.ts';
import { FIELD_ORDER } from './zones.ts';

/** 굴림을 고정해서 검사한다 */
const fixed = (...values: number[]) => {
  let i = 0;
  return () => values[Math.min(i++, values.length - 1)]!;
};

test('단계 수가 사냥터 수와 같다', () => {
  // 어긋나면 마지막 사냥터에서 그 단계 장비가 안 떨어진다
  const tiers = new Set(Object.values(ITEMS).map((i) => i.level));
  assert.equal(tiers.size, FIELD_ORDER.length);
});

test('떨어지는 장비가 슬롯 8종에 고루 퍼진다', () => {
  // 한쪽만 나오면 나머지 자리는 영영 빈다
  const seen = new Set<string>();
  for (let i = 0; i < 3000; i++) {
    const drop = rollDrop(50, 'archer', fixed(0.5, 0, i / 3000, 0.5));
    if (drop.item) seen.add(ITEMS[drop.item.id]!.slot!);
  }
  assert.equal(seen.size, EQUIP_SLOTS.length, `나온 슬롯: ${[...seen].join(', ')}`);
});

test('모든 아이템이 슬롯과 요구 레벨을 갖는다', () => {
  for (const item of Object.values(ITEMS)) {
    assert.ok(item.level >= 1, `${item.id}: 요구 레벨이 ${item.level}`);
    assert.ok(item.price > 0, `${item.id}: 가격이 없다`);

    assert.ok(EQUIP_SLOTS.includes(item.slot!), `${item.id}: 슬롯이 이상하다`);
    const sum = Object.values(item.bonus).reduce((a, b) => a + b, 0);
    assert.ok(sum > 0, `${item.id}: 아무 능력치도 안 올려준다`);
  }
});

test('무기만 직업을 탄다', () => {
  // 보조(보호대·마법서·화살통)를 없애면서 직업을 타는 자리는 무기만 남았다
  const jobSlots = ['weapon'];
  for (const item of Object.values(ITEMS)) {
    if (jobSlots.includes(item.slot!)) assert.ok(item.job, `${item.id}: ${item.slot} 인데 직업이 없다`);
    else assert.equal(item.job, undefined, `${item.id}: ${item.slot} 인데 직업을 탄다`);
  }
});

test('슬롯 6종이 단계마다 다 갖춰져 있다', () => {
  // 하나라도 비면 그 자리는 영영 빈 채로 남는다
  for (const slot of EQUIP_SLOTS) {
    const levels = new Set(
      Object.values(ITEMS)
        .filter((i) => i.slot === slot)
        .map((i) => i.level)
    );
    assert.equal(levels.size, FIELD_ORDER.length, `${slot}: 단계가 ${levels.size}개뿐이다`);
  }
});

test('슬롯 이름은 여섯 개뿐이다', () => {
  // 보조·귀걸이를 없앴다. 남은 것에 이름이 다 붙어 있어야 창이 빈칸으로 안 나온다
  assert.deepEqual(
    EQUIP_SLOTS.map((slot) => slotLabel(slot)),
    ['무기', '갑옷', '투구', '신발', '목걸이', '반지']
  );
  assert.equal(EQUIP_SLOTS.length, 6);
});

test('슬롯 배분이 설계표와 같다 (stat-balance.md)', () => {
  // 스탯마다 예산을 100% 로 보고 슬롯이 나눠 갖는다. 어긋나면 "갈아입을 자리가
  // 목적에 따라 갈린다" 는 설계가 무너진다
  // 단계 레벨은 10 단위(1·10·…·190)라 설계표의 착용 레벨(1·31·61·…)과 자리가 다르다.
  // 배분은 레벨과 무관하므로 아무 단계에서나 재도 같다
  const at = (slot: string) => {
    const item = Object.values(ITEMS).find(
      (i) => i.slot === slot && i.level === 180 && (i.job ?? 'fighter') === 'fighter'
    )!;
    return item.bonus;
  };
  const share = (pick: (b: ItemBonus) => number | undefined) => {
    const total = EQUIP_SLOTS.reduce((sum, s) => sum + (pick(at(s)) ?? 0), 0);
    return (slot: string) => Math.round(((pick(at(slot)) ?? 0) / total) * 100);
  };

  const atk = share((b) => b.attack);
  assert.equal(atk('weapon'), 60, '무기가 공격력 예산의 60%');
  assert.equal(atk('necklace'), 20);
  assert.equal(atk('ring'), 20);

  const def = share((b) => b.defense);
  assert.equal(def('armor'), 40, '갑옷이 방어력 예산의 40%');
  assert.equal(def('helmet'), 20);
  assert.equal(def('boots'), 20);
  assert.equal(def('necklace'), 10);
  assert.equal(def('ring'), 10);

  // HP 는 방어력과 같은 배분을 쓴다 (둘 다 생존 스탯)
  const hp = share((b) => b.maxHp);
  for (const slot of EQUIP_SLOTS) assert.equal(hp(slot), def(slot), `${slot}: HP 배분이 방어력과 다르다`);

  // 치명타는 목걸이, 공격 속도는 반지 전담
  for (const slot of EQUIP_SLOTS) {
    assert.equal(at(slot).crit ?? 0, slot === 'necklace' ? 50 : 0, `${slot}: 치명타`);
    assert.equal(at(slot).attackSpeed ?? 0, slot === 'ring' ? 20 : 0, `${slot}: 공격 속도`);
  }
});

test('치확·공속이 설계표의 등급 곡선을 따라간다', () => {
  // 설계표(stat-balance.md)는 착용 레벨 1·31·61·91·121·151·181 에서
  // 치확 0·8·17·25·33·42·50%p, 공속 0·3·7·10·13·17·20% 를 적는다.
  // 단계 레벨은 10 단위라 30·60·… 에서 재는데, 한 칸(1레벨) 차이라 값이 같거나 1 작다
  const want: Array<[number, number, number]> = [
    // 레벨, 치확, 공속
    [30, 8, 3],
    [60, 17, 7],
    [90, 25, 10],
    [120, 33, 13],
    [150, 41, 17],
    [180, 50, 20],
  ];
  for (const [level, crit, speed] of want) {
    const neck = Object.values(ITEMS).find((i) => i.slot === 'necklace' && i.level === level)!;
    const ring = Object.values(ITEMS).find((i) => i.slot === 'ring' && i.level === level)!;
    // 단계 레벨(30·60·…)은 착용 레벨(31·61·…)보다 한 칸 아래라 1 작을 수 있다
    assert.ok(Math.abs(neck.bonus.crit! - crit) <= 1, `${level}레벨 목걸이 치확 ${neck.bonus.crit}`);
    assert.ok(
      Math.abs(ring.bonus.attackSpeed! - speed) <= 1,
      `${level}레벨 반지 공속 ${ring.bonus.attackSpeed}`
    );
  }
});

test('보조와 귀걸이는 아이템이 안 나온다', () => {
  // 없앤 자리의 아이템이 남아 있으면 못 끼는 물건이 가방에 쌓인다
  for (const item of Object.values(ITEMS)) {
    assert.ok(item.slot !== 'offhand', `${item.id}: 보조가 남아 있다`);
    assert.ok(item.slot !== 'earring', `${item.id}: 귀걸이가 남아 있다`);
  }
});

test('요구 레벨과 직업을 서버가 막는다', () => {
  const highKnuckle = Object.values(ITEMS).find((i) => i.slot === 'weapon' && i.job === 'fighter' && i.level >= 100)!;
  assert.equal(canEquip(highKnuckle, 'fighter', 10), false, '레벨이 모자라면 못 낀다');
  assert.equal(canEquip(highKnuckle, 'mage', 200), false, '다른 직업 무기는 못 낀다');
  assert.equal(canEquip(highKnuckle, 'fighter', 200), true);
});

test('장비 능력치가 합산된다', () => {
  const weapon = ITEMS['w_fighter_05']!;
  const armor = ITEMS['a_05']!;
  const total = equipmentStats({
    weapon: { id: weapon.id, grade: 1 },
    armor: { id: armor.id, grade: 1 },
    accessory: null,
  });

  assert.equal(total.attack, weapon.bonus.attack ?? 0);
  assert.equal(total.maxHp, armor.bonus.maxHp ?? 0);
  assert.equal(total.defense, (armor.bonus.defense ?? 0) + (weapon.bonus.defense ?? 0));
});

test('없는 아이템 id 는 조용히 무시된다', () => {
  // 아이템을 지우거나 이름을 바꿔도 저장된 가방 때문에 접속이 막히면 안 된다
  assert.equal(getItem('없는거'), null);
  const total = equipmentStats({ weapon: { id: '없는거', grade: 3 }, armor: null, accessory: null });
  assert.deepEqual(total, emptyStats());
});

test('단계가 높을수록 더 좋다', () => {
  for (const slot of EQUIP_SLOTS) {
    const sorted = Object.values(ITEMS)
      .filter((i) => i.slot === slot && (!i.job || i.job === 'fighter'))
      .sort((a, b) => a.level - b.level);
    const value = (i: (typeof sorted)[number]) => Object.values(i.bonus).reduce((a, b) => a + b, 0);
    for (let i = 1; i < sorted.length; i++) {
      assert.ok(value(sorted[i]!) > value(sorted[i - 1]!), `${slot}: ${sorted[i]!.id} 가 앞 단계보다 못하다`);
    }
  }
});

test('몬스터 레벨이 해당 단계 아이템으로 이어진다', () => {
  for (const kind of Object.values(MONSTER_KINDS)) {
    const tier = tierForLevel(kind.level);
    const required = tierLevel(tier);
    // 잡은 몬스터보다 한참 높은 레벨을 요구하는 장비가 떨어지면 못 낀다
    assert.ok(required <= kind.level, `${kind.name}(Lv${kind.level}) → 요구 Lv${required} 장비`);
  }
});

test('드롭은 항상 골드를 주고, 아이템은 가끔 준다', () => {
  const onlyGold = rollDrop(20, 'archer', fixed(0.5, 0.99));
  assert.ok(onlyGold.gold > 0);
  assert.equal(onlyGold.item, undefined);

  const withItem = rollDrop(20, 'archer', fixed(0.5, dropChanceFor(20) - 1e-6, 0, 0));
  assert.ok(withItem.item, '확률 안에 들었는데 아이템이 없다');
});

test('드랍률이 설계값이다 — 평면 14% 가 아니다', () => {
  // 2026-09-21 지적: "md 파일 준걸로는 1등급 드랍률 0.3% 라고 했는데 지금은 왜
  // 말도 안 되게 높은거지?" — 설계값이 balance.json 에 있기만 하고 판정이 안
  // 읽고 있었다. 설계 문서 7장의 표를 그대로 박아 둔다 (단위: 퍼센트)
  const want: Record<number, number> = {
    15: 0.2963, // 사냥터 2 — 등급1 만
    45: 0.2963 + 0.08, // 사냥터 5 — 등급1 + 등급2
    75: 0.08 + 0.0321,
    105: 0.0321 + 0.0095,
    135: 0.0095 + 0.0055,
    165: 0.0055 + 0.0016,
    195: 0.0016 + 0.0011, // 사냥터 20 — 등급6 + 등급7
  };
  for (const [level, percent] of Object.entries(want)) {
    const got = dropChanceFor(Number(level)) * 100;
    assert.ok(Math.abs(got - percent) < 1e-9, `Lv${level}: ${got}% (${percent}% 여야 한다)`);
  }
  // 예전 평면값보다 한참 낮다 — 등급1 기준 47배
  assert.ok(dropChanceFor(15) < 0.14 / 40, '아직 평면값 수준이다');
});

test('등급 비율이 설계의 드랍률 비 그대로다', () => {
  // 사냥터 5 = [1, 2] → 0.2963 : 0.08 = 78.7% : 21.3%
  const counts = new Array(GRADE_MAX + 1).fill(0);
  const N = 20000;
  for (let i = 0; i < N; i++) counts[rollGrade(i / N, 45)]++;
  const share = counts[1] / N;
  const want = 0.2963 / (0.2963 + 0.08);
  assert.ok(Math.abs(share - want) < 0.01, `1등급 비중 ${share.toFixed(3)} (${want.toFixed(3)} 여야 한다)`);
});

test('떨어지는 무기는 잡은 사람 직업 것이다', () => {
  // 못 쓰는 무기가 가방을 채우면 정리가 일이 된다
  for (const job of ['fighter', 'mage', 'archer'] as const) {
    const drop = rollDrop(50, job, fixed(0.5, 0, 0, 0));
    const item = getItem(drop.item!.id)!;
    assert.equal(item.slot, 'weapon');
    assert.equal(item.job, job);
  }
});

// ---------------------------------------------------------------- 등급

test('사냥터가 등급을 정한다 — 저레벨에서 최고 등급이 안 나온다', () => {
  // 2026-09-21 지적: "1레벨짜리 잡고 최종템을 먹을수도 있는거자나"
  // 설계 표(gear.ts 의 dropField)를 그대로 박아 둔다
  const want: Record<number, number[]> = {
    1: [1], 5: [1], 40: [1],
    41: [1, 2], 70: [1, 2],
    71: [2, 3], 100: [2, 3],
    101: [3, 4], 130: [3, 4],
    131: [4, 5], 160: [4, 5],
    161: [5, 6], 190: [5, 6],
    191: [6, 7], 200: [6, 7],
  };
  for (const [level, grades] of Object.entries(want)) {
    assert.deepEqual(dropGradesFor(Number(level)), grades, `Lv${level}`);
  }

  // 굴림을 전 구간 훑어도 창 밖은 안 나온다
  for (const level of [1, 25, 55, 95, 145, 200]) {
    const allowed = dropGradesFor(level);
    for (let i = 0; i <= 200; i++) {
      const grade = rollGrade(i / 200, level);
      assert.ok(allowed.includes(grade), `Lv${level} 에서 ${grade}등급이 굴려졌다`);
    }
  }
});

test('최고 등급은 마지막 사냥터에서만 나온다', () => {
  assert.equal(MAX_DROP_GRADE, 7, '설계 등급은 7개다 — 8~10 은 근거가 없었다');
  for (let level = 1; level <= 190; level++) {
    assert.ok(!dropGradesFor(level).includes(MAX_DROP_GRADE), `Lv${level} 에서 최고 등급이 나온다`);
  }
  assert.ok(dropGradesFor(191).includes(MAX_DROP_GRADE), '마지막 사냥터에서도 안 나온다');
});

test('창 안에서는 아래 등급이 더 흔하다 — 비는 설계가 정한다', () => {
  // 예전에는 2^(n-g) 로 임의로 2:1 이었다. 이제 설계의 드랍률 비 그대로다 —
  // 사냥터 20 = [6, 7] 이면 0.0016 : 0.0011 = 1.45 : 1
  const counts = new Array(GRADE_MAX + 1).fill(0);
  const N = 20000;
  for (let i = 0; i < N; i++) counts[rollGrade(i / N, 200)]++;
  assert.ok(counts[6] > counts[7], '아래 등급이 더 흔해야 한다');
  assert.ok(counts[7] > 0, '위 등급이 아예 안 나온다');
  const ratio = counts[6] / counts[7];
  const want = 0.0016 / 0.0011;
  assert.ok(Math.abs(ratio - want) < 0.05, `비가 ${want.toFixed(2)}:1 이어야 하는데 ${ratio.toFixed(2)}:1`);
});

test('기본 능력치는 등급을 타지 않는다', () => {
  // 기본은 고정이고, 등급이 흔드는 건 옵션 범위뿐이다
  const item = ITEMS['a_05']!;
  const first = baseBonus(item);
  for (let g = GRADE_MIN; g <= GRADE_MAX; g++) {
    assert.deepEqual(baseBonus(item), first, `${g}등급에서 기본 수치가 달라졌다`);
  }
  assert.equal(gradeMultiplier(GRADE_MIN), 1, '1등급이 값의 기준이어야 한다');
});

test('등급은 범위를 벗어나도 안전하다', () => {
  assert.equal(gradeMultiplier(0), gradeMultiplier(GRADE_MIN));
  assert.equal(gradeMultiplier(999), gradeMultiplier(GRADE_MAX));
});

test('보스는 금화를 더 준다', () => {
  // 보스 전용 아이템은 아직 없다 — 그때까지 3분을 기다린 값은 금화로만 돌아온다
  for (const level of [9, 99, 199]) {
    const boss = rollBossDrop(level, () => 0.5);
    const normal = rollDrop(level, 'fighter', () => 0.5).gold;
    assert.ok(boss.gold > normal * 5, `보스 ${boss.gold} vs 일반 ${normal}`);
  }
});

test('골드는 몬스터 레벨을 따라 오른다', () => {
  const low = rollDrop(3, 'fighter', fixed(0.5, 0.99)).gold;
  const high = rollDrop(190, 'fighter', fixed(0.5, 0.99)).gold;
  assert.ok(high > low * 10, `저레벨 ${low} → 고레벨 ${high}`);
});

// ---------------------------------------------------------------- 강화

test('강화 확률은 세 갈래로 나뉘고 합이 1 이다', () => {
  for (let level = 0; level <= MAX_ENHANCE; level++) {
    const o = enhanceOdds(level);
    const sum = o.success + o.keep + o.destroy;
    assert.ok(Math.abs(sum - 1) < 1e-9, `+${level}: 합이 ${sum}`);
    assert.ok(o.success > 0, `+${level}: 성공이 0 이면 아무도 시도하지 않는다`);
  }
});

test('성공률이 설계표대로 90% 에서 10% 까지 내려간다', () => {
  // 설계 4장의 성공률 행 그대로. **유지가 없어서 실패는 곧 파괴**다
  const want = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1];
  for (let level = 0; level < want.length; level++) {
    const odds = enhanceOdds(level);
    assert.equal(odds.success, want[level], `+${level} 성공률`);
    assert.equal(odds.keep, 0, `+${level}: 유지 구간이 남아 있다`);
    assert.equal(Math.round(odds.destroy * 100) / 100, Math.round((1 - want[level]!) * 100) / 100);
  }
});

test('실패하면 무조건 파괴된다 — 유지가 없다', () => {
  // 재료도 값도 없으니 실패의 대가는 아이템 하나뿐이고, 무한히 재시도할 수 있다.
  // 그래서 도달 단계는 "아이템이 몇 개 들어오느냐" 로만 결정된다
  for (let level = 0; level < MAX_ENHANCE; level++) {
    const o = enhanceOdds(level);
    assert.equal(rollEnhance(level, 0), 'success');
    assert.equal(rollEnhance(level, o.success - 0.001), 'success');
    assert.equal(rollEnhance(level, o.success + 0.001), 'destroy');
    assert.equal(rollEnhance(level, 0.999999), 'destroy');
    for (let i = 0; i <= 100; i++) {
      assert.notEqual(rollEnhance(level, i / 100), 'keep', `+${level}: 유지가 나온다`);
    }
  }
});

test('강화 총 배수가 ×6 이고 고강화일수록 크게 오른다', () => {
  // 9→10단이 +50% 여야 파괴 위험을 감수할 이유가 생긴다
  assert.equal(Math.round(enhanceMultiplier(0) * 100) / 100, 1);
  assert.equal(Math.round(enhanceMultiplier(MAX_ENHANCE) * 100) / 100, 6);
  const first = enhanceMultiplier(1) / enhanceMultiplier(0) - 1;
  const last = enhanceMultiplier(MAX_ENHANCE) / enhanceMultiplier(MAX_ENHANCE - 1) - 1;
  assert.ok(Math.abs(last / first - 7) < 0.01, `첫 구간 : 마지막 = 1 : ${(last / first).toFixed(2)}`);
});

test('강화하면 세지고, 최고 수치에서 멈춘다', () => {
  const item = ITEMS['a_05']!;
  let previous = 0;
  for (let level = 0; level <= MAX_ENHANCE; level++) {
    const value = Object.values(baseBonus(item, level)).reduce((a, b) => a + b, 0);
    assert.ok(value > previous, `+${level}: 앞 수치보다 못하다`);
    previous = value;
  }
  assert.equal(enhanceMultiplier(MAX_ENHANCE + 5), enhanceMultiplier(MAX_ENHANCE), '범위를 넘어도 안전하다');
  assert.equal(enhanceMultiplier(-3), enhanceMultiplier(0));
  assert.equal(canEnhance(MAX_ENHANCE), false);
  assert.equal(canEnhance(MAX_ENHANCE - 1), true);
});

test('강화는 공짜다 — 값을 매기면 골드를 모으는 일이 된다', () => {
  // 설계는 그 자리에 **드랍**을 놓았다. 실패하면 아이템이 사라지므로 아이템이 연료다
  const item = ITEMS['w_fighter_05']!;
  for (let level = 0; level < MAX_ENHANCE; level++) {
    assert.equal(enhanceCost(item, level), 0, `+${level}: 값이 붙어 있다`);
  }
});

test('강화는 기본 수치를 키운다', () => {
  const item = ITEMS['a_05']!;
  assert.ok(baseBonus(item, 5).maxHp > baseBonus(item, 0).maxHp, '강화가 기본 수치에 붙어야 한다');
});


// ---------------------------------------------------------------- 옵션

/**
 * 랜덤 옵션 검사.
 *
 * 굴리는 코드라 눈으로 보면 "그럴듯해 보인다"에서 멈춘다. 나올 수 있는 값이
 * 범위 안인지, 등급을 올린 게 실제로 이득인지는 규칙으로만 잡힌다.
 */

/** 0,0.1,...,0.9 를 돌려주는 굴림 — 결과를 고정한다 */
function cycleRng(seed = 0): () => number {
  let i = seed;
  return () => ((i = (i + 3) % 10) / 10);
}

test('옵션은 1~3개가 종류 겹치지 않게 붙는다', () => {
  const item = ITEMS['a_05']!;
  for (let seed = 0; seed < 40; seed++) {
    const options = rollOptions(item, 5, cycleRng(seed));
    assert.ok(
      options.length >= OPTION_MIN && options.length <= OPTION_MAX,
      `${options.length}개가 붙었다`
    );
    const kinds = new Set(options.map((o) => o.kind));
    assert.equal(kinds.size, options.length, '같은 종류가 두 번 붙었다');
  }
});

test('굴린 값은 그 등급의 범위 안에 있다', () => {
  for (const id of ['a_05', 'w_fighter_19', 'r_00']) {
    const item = ITEMS[id]!;
    for (let grade = GRADE_MIN; grade <= GRADE_MAX; grade++) {
      for (let seed = 0; seed < 20; seed++) {
        for (const option of rollOptions(item, grade, cycleRng(seed))) {
          const { min, max } = optionRange(option.kind, grade, item.level);
          assert.ok(
            option.value >= min && option.value <= max,
            `${id} ${grade}등급 ${option.kind}: ${option.value} 가 ${min}~${max} 밖이다`
          );
        }
      }
    }
  }
});

test('옵션은 여섯 종이고 전부 퍼센트다', () => {
  // 2026-09-20 요청: 공속·치명타 확률·치명타 데미지·HP·쿨타임 감소·방어력 관통.
  // **공격력·방어력은 뺐다** — 슬롯 기본 수치가 이미 담당하므로 옵션으로 또 주면
  // "같은 것을 두 번" 이다
  assert.deepEqual([...OPTION_KINDS].sort(), [
    'attackSpeed',
    'cooldown',
    'crit',
    'critDamage',
    'maxHp',
    'penetration',
  ]);
  for (const kind of OPTION_KINDS) {
    assert.ok(describeOption({ kind, value: 3 }).endsWith('%'), `${kind} 가 퍼센트가 아니다`);
  }
});

test('품질 등급이 오르면 옵션 개수와 수치가 같이 커진다', () => {
  // 등급을 올릴 이유가 여기밖에 없다 — 둘 중 하나만 키우면 "등급은 높은데 옵션이
  // 하나뿐" 이나 "옵션은 넷인데 값이 시시한" 물건이 생긴다
  for (const kind of OPTION_KINDS) {
    const lowest = optionRange(kind, GRADE_MIN);
    const highest = optionRange(kind, GRADE_MAX);
    assert.ok(lowest.min <= lowest.max, `${kind}: min 이 max 보다 크다`);
    assert.ok(highest.max > lowest.max * 3, `${kind}: 10등급이 1등급의 세 배도 안 된다`);
    let previous = 0;
    for (let grade = GRADE_MIN; grade <= GRADE_MAX; grade++) {
      const { max } = optionRange(kind, grade);
      assert.ok(max >= previous, `${kind} ${grade}등급: 최대가 내려갔다`);
      previous = max;
    }
  }
  // 개수도 같이 오른다 (1개 → 4개)
  assert.deepEqual(optionCount(GRADE_MIN), [1, 1]);
  assert.deepEqual(optionCount(GRADE_MAX), [4, 4]);
  for (let grade = GRADE_MIN + 1; grade <= GRADE_MAX; grade++) {
    assert.ok(optionCount(grade)[1] >= optionCount(grade - 1)[1], `${grade}등급 개수가 줄었다`);
  }
  assert.equal(optionGradeScale(0), optionGradeScale(GRADE_MIN), '범위를 벗어나도 안전해야 한다');
  assert.equal(optionGradeScale(999), optionGradeScale(GRADE_MAX));
});

test('수치 옵션은 요구 레벨을 탄다', () => {
  // 200레벨 장비에 공격력 +3 이 붙으면 붙으나 마나다
  const low = ITEMS['a_00']!;
  const high = ITEMS['a_19']!;
  for (const kind of OPTION_KINDS) {
    const a = optionRange(kind, 1, low.level);
    const b = optionRange(kind, 1, high.level);
    if (isPercentOption(kind)) {
      assert.deepEqual(a, b, `${kind}: 퍼센트인데 레벨을 탔다`);
    } else {
      assert.ok(b.max > a.max, `${kind}: 상위 단계인데 더 안 붙는다`);
    }
  }
});

test('옵션이 능력치에 실제로 더해진다', () => {
  const item = ITEMS['a_05']!;
  const plain = stackStats({ id: item.id, grade: 1 });
  const rolled = stackStats({
    id: item.id,
    grade: 1,
    options: [
      { kind: 'maxHp', value: 10 },
      { kind: 'crit', value: 7 },
      { kind: 'attackSpeed', value: 4 },
      { kind: 'cooldown', value: 3 },
      { kind: 'penetration', value: 6 },
    ],
  });

  // HP 는 기본 스탯에 곱할 % 라 슬롯 기본 수치와 같은 자리에 더한다
  assert.equal(rolled.maxHp, plain.maxHp + 10);
  // 나머지는 비율로 담긴다 — 화면과 판정이 다른 단위를 쓰면 언젠가 어긋난다
  assert.ok(Math.abs(rolled.crit - 0.07) < 1e-9, `치명타가 ${rolled.crit}`);
  assert.ok(Math.abs(rolled.attackSpeed - 0.04) < 1e-9);
  assert.ok(Math.abs(rolled.cooldown - 0.03) < 1e-9, `쿨감이 ${rolled.cooldown}`);
  assert.ok(Math.abs(rolled.penetration - 0.06) < 1e-9, `관통이 ${rolled.penetration}`);
});

test('장착한 것들의 옵션이 합산된다', () => {
  const total = equipmentStats({
    weapon: { id: 'w_fighter_05', grade: 1, options: [{ kind: 'crit', value: 5 }] },
    armor: { id: 'a_05', grade: 1, options: [{ kind: 'crit', value: 3 }] },
  });
  assert.ok(Math.abs(total.crit - 0.08) < 1e-9, `합이 ${total.crit}`);
});

test('저장된 옵션은 지금 규칙으로 다시 잘린다', () => {
  // 예전 규칙으로 저장된 값이나 손댄 값이 그대로 들어오면 안 된다.
  // 없어진 종류(공격력·방어력)도 여기서 걸러진다
  const item = ITEMS['a_05']!;
  const { min, max } = optionRange('penetration', 2);

  const cleaned = sanitizeOptions(
    [
      { kind: 'penetration', value: 999999 },
      { kind: 'penetration', value: 5 },
      { kind: '없는옵션', value: 3 },
      { kind: 'attack', value: 7 },
      { kind: 'defense', value: 7 },
      { kind: 'crit', value: -50 },
      { kind: 'maxHp', value: 1 },
      { kind: 'critDamage', value: 1 },
    ],
    item,
    2
  );

  assert.ok(cleaned.length <= OPTION_MAX, `${cleaned.length}개가 남았다`);
  assert.equal(cleaned[0]!.value, max, '최대를 넘으면 잘려야 한다');
  assert.equal(new Set(cleaned.map((o) => o.kind)).size, cleaned.length, '종류가 겹쳤다');
  // 값은 소수 한 자리다 — 정수로 자르면 낮은 등급에서 0 이 되어 버린다
  assert.ok(min > 0, `최소가 ${min}`);
  for (const option of cleaned) {
    assert.equal(option.value, Math.round(option.value * 10) / 10, `${option.kind} 자릿수`);
  }
  assert.deepEqual(sanitizeOptions('망가진 값', item, 1), []);
});

test('드롭에는 옵션이 함께 굴려진다', () => {
  // 주운 물건만 옵션이 없으면 그것만 못 쓰는 장비가 된다
  let checked = 0;
  for (let seed = 0; seed < 60 && checked < 5; seed++) {
    const drop = rollDrop(50, 'archer', cycleRng(seed));
    if (!drop.item) continue;
    checked++;
    assert.ok((drop.item.options ?? []).length >= OPTION_MIN, '옵션이 안 붙었다');
  }
  assert.ok(checked > 0, '장비가 한 번도 안 떨어져 검사를 못 했다');
});

test('옵션 글은 새 이름으로 나온다', () => {
  assert.equal(describeOption({ kind: 'crit', value: 7 }), '치명타 +7%');
  assert.equal(describeOption({ kind: 'cooldown', value: 1.2 }), '쿨타임 감소 +1.2%');
  assert.equal(describeOption({ kind: 'penetration', value: 3.3 }), '방어력 관통 +3.3%');
});
