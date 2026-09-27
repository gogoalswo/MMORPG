import { test } from 'node:test';
import assert from 'node:assert/strict';

import { TOOTH_ITEMS, toothId, toothLifesteal } from './tooth.ts';
import { ITEMS, gradeLevel } from './items.ts';

test('이빨은 등급 7개 = 7종, 흡혈은 등급마다 1%씩 (일반 1% → 태초 7%)', () => {
  const teeth = Object.values(TOOTH_ITEMS);
  assert.equal(teeth.length, 7);
  for (let grade = 1; grade <= 7; grade++) {
    const tooth = TOOTH_ITEMS[toothId(grade)]!;
    assert.equal(tooth.grade, grade);
    assert.equal(tooth.bonus.lifesteal, grade, `${tooth.id}: 흡혈 ${grade}%`);
    assert.equal(toothLifesteal(grade), grade);
    assert.equal(tooth.level, gradeLevel(grade), '착용 레벨은 다른 장비와 같다');
    assert.equal(tooth.fixed, true, '강화·크리스탈·판매가 없다');
    assert.equal(tooth.price, 0);
    assert.ok(tooth.name.endsWith('이빨'));
  }
});

test('이빨은 장비 표(ITEMS)에 없다 — 드랍·상점·강화 표에 섞이지 않는다', () => {
  for (const id of Object.keys(TOOTH_ITEMS)) assert.equal(ITEMS[id], undefined, id);
});
