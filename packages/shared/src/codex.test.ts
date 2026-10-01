import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CODEX_SLOT_STAT,
  CODEX_CELLS,
  CODEX_MAX_ENHANCE,
  codexCellValue,
  codexFullBonus,
} from './codex.ts';
import { GRADE_MAX, GRADE_MIN } from './items.ts';
import { EQUIP_SLOTS } from './slots.ts';

test('도감 — 부위 여섯이 다 능력치를 갖고, 능력치마다 부위 둘씩', () => {
  assert.deepEqual(Object.keys(CODEX_SLOT_STAT).sort(), [...EQUIP_SLOTS].sort());
  for (const stat of ['attack', 'defense', 'maxHp']) {
    assert.equal(EQUIP_SLOTS.filter((slot) => CODEX_SLOT_STAT[slot] === stat).length, 2, stat);
  }
});

test('도감 — 칸 표: 등급 7 × 강화 +0~+9, 등급·강화가 오를수록 몫이 크다', () => {
  assert.equal(CODEX_CELLS.length, GRADE_MAX - GRADE_MIN + 1);
  for (const row of CODEX_CELLS) {
    assert.equal(row.length, CODEX_MAX_ENHANCE + 1);
    for (let i = 1; i < row.length; i++) assert.ok(row[i] >= row[i - 1], `강화 ${i} 가 앞보다 작다`);
  }
  for (let g = 1; g < CODEX_CELLS.length; g++) assert.ok(CODEX_CELLS[g][0] > CODEX_CELLS[g - 1][0]);
  assert.equal(codexCellValue(1, 0), 0.01);
  assert.equal(codexCellValue(7, 9), 2);
});

test('도감 — 다 채우면 능력치마다 +56.1% (문서의 표)', () => {
  for (const stat of ['attack', 'defense', 'maxHp'] as const) assert.equal(codexFullBonus(stat), 56.1);
});
