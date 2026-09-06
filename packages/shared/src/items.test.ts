import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BOSS_MATERIALS,
  slotLabel,
  DROP_CHANCE,
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
  canCraftUp,
  canEnhance,
  enhanceCost,
  enhanceMultiplier,
  enhanceOdds,
  rollEnhance,
  canEquip,
  craftRequirement,
  equipmentStats,
  getItem,
  gradeMultiplier,
  materialIdFor,
  materialsNeeded,
  rollBossDrop,
  rollDrop,
  rollGrade,
  tierForLevel,
  tierLevel,
} from './items.ts';
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

    if (item.material) {
      assert.equal(item.slot, null, `${item.id}: 재료인데 슬롯이 있다`);
      continue;
    }

    assert.ok(EQUIP_SLOTS.includes(item.slot!), `${item.id}: 슬롯이 이상하다`);
    const sum = Object.values(item.bonus).reduce((a, b) => a + b, 0);
    assert.ok(sum > 0, `${item.id}: 아무 능력치도 안 올려준다`);
  }
});

test('무기와 보조만 직업을 탄다', () => {
  // 보조는 기사 방패 / 궁수 화살통 / 마법사 마법서로 갈린다
  const jobSlots = ['weapon', 'offhand'];
  for (const item of Object.values(ITEMS)) {
    if (item.material) continue;
    if (jobSlots.includes(item.slot!)) assert.ok(item.job, `${item.id}: ${item.slot} 인데 직업이 없다`);
    else assert.equal(item.job, undefined, `${item.id}: ${item.slot} 인데 직업을 탄다`);
  }
});

test('슬롯 8종이 단계마다 다 갖춰져 있다', () => {
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

test('보조 슬롯 이름이 직업마다 다르다', () => {
  assert.equal(slotLabel('offhand', 'knight'), '방패');
  assert.equal(slotLabel('offhand', 'archer'), '화살통');
  assert.equal(slotLabel('offhand', 'mage'), '마법서');
  assert.equal(slotLabel('helmet'), '투구', '직업과 무관한 슬롯은 이름이 하나다');
});

test('직업별 보조 장비는 성격이 다르다', () => {
  const at = (job: string) => ITEMS[`o_${job}_05`]!.bonus;
  assert.ok((at('knight').defense ?? 0) > 0, '기사 방패는 방어를 준다');
  assert.ok((at('mage').maxMp ?? 0) > 0, '마법사 마법서는 마나를 준다');
  assert.ok((at('archer').attack ?? 0) > 0, '궁수 화살통은 공격을 준다');
});

test('요구 레벨과 직업을 서버가 막는다', () => {
  const highSword = Object.values(ITEMS).find((i) => i.slot === 'weapon' && i.job === 'knight' && i.level >= 100)!;
  assert.equal(canEquip(highSword, 'knight', 10), false, '레벨이 모자라면 못 낀다');
  assert.equal(canEquip(highSword, 'mage', 200), false, '다른 직업 무기는 못 낀다');
  assert.equal(canEquip(highSword, 'knight', 200), true);
});

test('장비 능력치가 합산된다', () => {
  const weapon = ITEMS['w_knight_05']!;
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
      .filter((i) => !i.material && i.slot === slot && (!i.job || i.job === 'knight'))
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

  const withItem = rollDrop(20, 'archer', fixed(0.5, DROP_CHANCE - 0.01, 0, 0));
  assert.ok(withItem.item, '확률 안에 들었는데 아이템이 없다');
});

test('떨어지는 무기는 잡은 사람 직업 것이다', () => {
  // 못 쓰는 무기가 가방을 채우면 정리가 일이 된다
  for (const job of ['knight', 'mage', 'archer'] as const) {
    const drop = rollDrop(50, job, fixed(0.5, 0, 0, 0));
    const item = getItem(drop.item!.id)!;
    assert.equal(item.slot, 'weapon');
    assert.equal(item.job, job);
  }
});

// ---------------------------------------------------------------- 등급

test('등급은 8 이상이 드롭으로 나오지 않는다', () => {
  // 최상위는 제작으로만 — 운이 아니라 쌓아온 결과여야 한다
  for (let i = 0; i <= 100; i++) {
    const grade = rollGrade(i / 100);
    assert.ok(grade >= GRADE_MIN && grade <= MAX_DROP_GRADE, `${grade}등급이 굴려졌다`);
  }
});

test('낮은 등급일수록 흔하다', () => {
  const counts = new Array(GRADE_MAX + 1).fill(0);
  for (let i = 0; i < 10000; i++) counts[rollGrade(i / 10000)]++;
  for (let g = GRADE_MIN; g < MAX_DROP_GRADE; g++) {
    assert.ok(counts[g] > counts[g + 1], `${g}등급이 ${g + 1}등급보다 드물다`);
  }
  assert.ok(counts[MAX_DROP_GRADE] > 0, '최고 드롭 등급이 아예 안 나온다');
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

test('재료는 착용할 수 없다', () => {
  const material = ITEMS[materialIdFor(0)]!;
  assert.equal(material.material, true);
  assert.equal(canEquip(material, 'knight', 200), false);
});

test('보스는 재료를 반드시 준다', () => {
  // 최상위로 가는 유일한 길이라 운에 맡기면 3분 기다린 값이 없다
  for (const level of [9, 99, 199]) {
    const drop = rollBossDrop(level, () => 0.5);
    assert.ok(drop.gold > 0);
    assert.equal(drop.count, BOSS_MATERIALS);
    assert.ok(ITEMS[drop.materialId]?.material, `${drop.materialId} 가 재료가 아니다`);
  }
});

test('일반 몬스터는 재료를 주지 않는다', () => {
  for (let i = 0; i < 50; i++) {
    const drop = rollDrop(50, 'knight', fixed(0.5, 0, i / 50, i / 50));
    if (drop.item) assert.ok(!ITEMS[drop.item.id]?.material, '일반 드롭에 재료가 섞였다');
  }
});

test('제작에는 같은 단계의 재료가 든다', () => {
  const item = ITEMS['w_knight_05']!;
  const need = craftRequirement(item, 3)!;
  assert.equal(need.targetGrade, 4);
  assert.equal(need.materialId, materialIdFor(5), '장비와 같은 단계 재료여야 한다');
  assert.equal(need.materialCount, materialsNeeded(4));
  assert.ok(need.gold > 0);
});

test('등급이 높아질수록 재료가 더 든다', () => {
  const item = ITEMS['a_05']!;
  let previous = 0;
  for (let g = GRADE_MIN; g < GRADE_MAX; g++) {
    const need = craftRequirement(item, g)!;
    assert.ok(need.materialCount >= previous, `${g}→${g + 1} 이 더 싸다`);
    previous = need.materialCount;
  }
  assert.equal(craftRequirement(item, GRADE_MAX), null, '최고 등급은 더 못 올린다');
});

test('재료 자체는 제작할 수 없다', () => {
  const material = ITEMS[materialIdFor(3)]!;
  assert.equal(craftRequirement(material, 1), null);
});

test('최고 등급에서는 더 제작할 수 없다', () => {
  assert.equal(canCraftUp(GRADE_MAX), false);
  assert.equal(canCraftUp(GRADE_MAX - 1), true);
  assert.equal(canCraftUp(MAX_DROP_GRADE), true, '드롭 최고 등급에서 위로 올릴 수 있어야 한다');
});

test('제작 비용은 등급이 오를수록 비싸진다', () => {
  const item = ITEMS['w_knight_05']!;
  let previous = 0;
  for (let g = GRADE_MIN; g < GRADE_MAX; g++) {
    const cost = craftRequirement(item, g)!.gold;
    assert.ok(cost > previous, `${g}등급 제작비가 더 싸다`);
    previous = cost;
  }
});

test('드롭 최고 등급에서 제작으로 만렙 등급까지 이어진다', () => {
  // 7등급까지만 떨어지므로 여기서 길이 끊기면 8~10 은 도달 불가가 된다
  let materials = 0;
  for (let g = MAX_DROP_GRADE; g < GRADE_MAX; g++) {
    const need = craftRequirement(ITEMS['a_05']!, g);
    assert.ok(need, `${g}등급에서 제작이 막힌다`);
    materials += need!.materialCount;
  }
  assert.ok(materials > 0, `7 → ${GRADE_MAX} 에 재료 ${materials}개`);
});

test('골드는 몬스터 레벨을 따라 오른다', () => {
  const low = rollDrop(3, 'knight', fixed(0.5, 0.99)).gold;
  const high = rollDrop(190, 'knight', fixed(0.5, 0.99)).gold;
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

test('올라갈수록 어려워지고, 낮은 구간에서는 부서지지 않는다', () => {
  // 처음부터 부서지면 강화를 아예 안 하게 된다
  for (let level = 0; level <= 3; level++) {
    assert.equal(enhanceOdds(level).destroy, 0, `+${level}: 초반부터 부서진다`);
  }
  assert.ok(enhanceOdds(0).success > enhanceOdds(9).success, '높은 수치가 더 쉬우면 안 된다');
  assert.ok(enhanceOdds(9).destroy > 0, '끝까지 안 부서지면 골드만 있으면 되는 일이 된다');
});

test('굴림값이 확률대로 갈린다', () => {
  const level = 8;
  const o = enhanceOdds(level);
  assert.equal(rollEnhance(level, 0), 'success');
  assert.equal(rollEnhance(level, o.success - 0.001), 'success');
  assert.equal(rollEnhance(level, o.success + 0.001), 'keep');
  assert.equal(rollEnhance(level, o.success + o.keep + 0.001), 'destroy');
  assert.equal(rollEnhance(level, 0.999999), 'destroy');
});

test('부서지지 않는 구간에서는 어떤 굴림도 파괴가 아니다', () => {
  for (let i = 0; i <= 100; i++) {
    assert.notEqual(rollEnhance(2, i / 100), 'destroy');
  }
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

test('강화 값은 올라갈수록 비싸진다', () => {
  const item = ITEMS['w_knight_05']!;
  let previous = 0;
  for (let level = 0; level < MAX_ENHANCE; level++) {
    const cost = enhanceCost(item, level);
    assert.ok(cost > previous, `+${level}: 더 싸다`);
    previous = cost;
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
  for (const id of ['a_05', 'w_knight_19', 'r_00']) {
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

test('등급이 오르면 옵션 범위가 넓어진다', () => {
  // 등급을 올릴 이유가 여기밖에 없다 — 여기서 안 오르면 제작이 무의미해진다
  const item = ITEMS['a_05']!;
  for (const kind of OPTION_KINDS) {
    let previousMax = 0;
    let previousMin = 0;
    for (let grade = GRADE_MIN; grade <= GRADE_MAX; grade++) {
      const { min, max } = optionRange(kind, grade, item.level);
      assert.ok(min <= max, `${kind} ${grade}등급: min 이 max 보다 크다`);
      assert.ok(max > previousMax, `${kind} ${grade}등급: 최대가 안 올랐다`);
      assert.ok(min >= previousMin, `${kind} ${grade}등급: 최소가 내려갔다`);
      previousMax = max;
      previousMin = min;
    }
  }
  assert.equal(optionGradeScale(GRADE_MIN), 1, '1등급이 기준이어야 한다');
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
      { kind: 'attack', value: 10 },
      { kind: 'crit', value: 7 },
      { kind: 'attackSpeed', value: 4 },
    ],
  });

  assert.equal(rolled.attack, plain.attack + 10);
  // 퍼센트는 비율로 담긴다 — 화면과 판정이 다른 단위를 쓰면 언젠가 어긋난다
  assert.ok(Math.abs(rolled.crit - 0.07) < 1e-9, `치명타가 ${rolled.crit}`);
  assert.ok(Math.abs(rolled.attackSpeed - 0.04) < 1e-9);
});

test('장착한 것들의 옵션이 합산된다', () => {
  const total = equipmentStats({
    weapon: { id: 'w_knight_05', grade: 1, options: [{ kind: 'crit', value: 5 }] },
    armor: { id: 'a_05', grade: 1, options: [{ kind: 'crit', value: 3 }] },
  });
  assert.ok(Math.abs(total.crit - 0.08) < 1e-9, `합이 ${total.crit}`);
});

test('재료에는 옵션이 붙지 않는다', () => {
  const material = ITEMS[materialIdFor(3)]!;
  assert.deepEqual(rollOptions(material, 7, cycleRng()), []);
});

test('저장된 옵션은 지금 규칙으로 다시 잘린다', () => {
  // 예전 규칙으로 저장된 값이나 손댄 값이 그대로 들어오면 안 된다
  const item = ITEMS['a_05']!;
  const { min, max } = optionRange('attack', 2, item.level);

  const cleaned = sanitizeOptions(
    [
      { kind: 'attack', value: 999999 },
      { kind: 'attack', value: 5 },
      { kind: '없는옵션', value: 3 },
      { kind: 'crit', value: -50 },
      { kind: 'defense', value: max },
      { kind: 'maxHp', value: 1 },
      { kind: 'critDamage', value: 1 },
    ],
    item,
    2
  );

  assert.ok(cleaned.length <= OPTION_MAX, `${cleaned.length}개가 남았다`);
  assert.equal(cleaned[0]!.value, max, '최대를 넘으면 잘려야 한다');
  assert.equal(new Set(cleaned.map((o) => o.kind)).size, cleaned.length, '종류가 겹쳤다');
  assert.ok(min >= 1);
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

test('옵션 글은 퍼센트와 수치를 구분해 쓴다', () => {
  assert.equal(describeOption({ kind: 'crit', value: 7 }), '치명타 +7%');
  assert.equal(describeOption({ kind: 'attack', value: 7 }), '공격력 +7');
});
