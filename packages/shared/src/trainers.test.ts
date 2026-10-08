import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TRAINERS, TRAINER_GRADES, TRAINER_FUSE_COST, TRAINER_FUSE_SLOTS, trainerOwnedBonus } from './trainers.ts';

test('트레이너 — 등급별 인원이 요청대로다 (20 · 15 · 10 · 5 · 3)', () => {
  const counts = TRAINER_GRADES.map((g) => TRAINERS.filter((t) => t.grade === g.grade).length);
  assert.deepEqual(counts, [20, 15, 10, 5, 3]);
  assert.deepEqual(counts, TRAINER_GRADES.map((g) => g.count));
});

test('트레이너 — 계승 % 는 요청대로다 (20 · 30 · 40 · 60 · 80)', () => {
  assert.deepEqual(TRAINER_GRADES.map((g) => g.inherit), [20, 30, 40, 60, 80]);
});

test('트레이너 — id 와 이름이 겹치지 않는다', () => {
  assert.equal(new Set(TRAINERS.map((t) => t.id)).size, TRAINERS.length);
  assert.equal(new Set(TRAINERS.map((t) => t.name)).size, TRAINERS.length);
});

test('트레이너 — 뽑기 확률 합이 100 이다', () => {
  const sum = TRAINER_GRADES.reduce((s, g) => s + g.chance, 0);
  assert.ok(Math.abs(sum - 100) < 1e-9, `합 ${sum}`);
});

test('트레이너 — 53명을 다 모은 보유 효과', () => {
  const all = trainerOwnedBonus(TRAINERS.map((t) => t.id));
  // 공격력: 일반 4×1 + 고급 3×2 + 희귀 2×3 + 영웅 1×5 + 전설 1×8 = 29
  assert.equal(all.attack, 29);
  for (const v of Object.values(all)) assert.ok(v > 0 && v <= 30);
  assert.deepEqual(trainerOwnedBonus(['n01', 'zz']).attack, 1);
});

test('트레이너 합성 — 확률은 사용자가 정한 20 · 20 · 10 · 10 %, 전설은 더 위가 없다', () => {
  assert.deepEqual(TRAINER_GRADES.map((g) => g.fuse), [20, 20, 10, 10, 0]);
  // 등록 칸은 3장 줄로 나뉜다 — 칸 한 줄이 도전 한 번
  assert.equal(TRAINER_FUSE_SLOTS % TRAINER_FUSE_COST, 0);
});
