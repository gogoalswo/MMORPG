import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  FITNESS_KINDS,
  FITNESS_MAX_STAGE,
  FITNESS_STEPS,
  DUNGEON_PROTEIN_PER_STAGE,
  fitnessBonus,
  fitnessExpectedCost,
} from './fitness.ts';
import { DUNGEON_TYPES } from './dungeons.ts';

test('헬스 — 운동 셋이 공격력·방어력·체력을 하나씩 맡고 프로틴도 하나씩', () => {
  assert.deepEqual(FITNESS_KINDS.map((k) => k.name), ['벤치프레스', '데드리프트', '스쿼트']);
  assert.deepEqual(FITNESS_KINDS.map((k) => k.stat), ['attack', 'defense', 'maxHp']);
  assert.deepEqual(FITNESS_KINDS.map((k) => k.proteinName), ['파워 프로틴', '디펜스 프로틴', '헬스 프로틴']);
  assert.equal(new Set(FITNESS_KINDS.map((k) => k.protein)).size, 3, '프로틴 id 가 겹친다');
});

test('헬스 — 단계 표: 확률은 내려가고 비용은 오르며 끝 단계 합은 +50%', () => {
  assert.equal(FITNESS_STEPS.length, FITNESS_MAX_STAGE);
  for (let i = 1; i < FITNESS_STEPS.length; i++) {
    const [a, b] = [FITNESS_STEPS[i - 1], FITNESS_STEPS[i]];
    assert.ok(b.chance < a.chance, `${b.stage}단계 확률이 안 내려간다`);
    assert.ok(b.cost > a.cost, `${b.stage}단계 비용이 안 오른다`);
    assert.ok(b.gain >= a.gain, `${b.stage}단계 몫이 줄었다`);
    assert.equal(b.total, a.total + b.gain);
  }
  for (const s of FITNESS_STEPS) {
    assert.ok(s.chance > 0 && s.chance <= 100, `${s.stage}단계 확률 ${s.chance}`);
    assert.ok(Number.isInteger(s.cost) && s.cost > 0, `${s.stage}단계 비용 ${s.cost}`);
  }
  assert.equal(FITNESS_STEPS[0].cost, 10);
  assert.equal(fitnessBonus(0), 0);
  assert.equal(fitnessBonus(1), 1);
  assert.equal(fitnessBonus(FITNESS_MAX_STAGE), 50);
  assert.equal(fitnessBonus(99), 50, '끝을 넘는 단계는 끝 단계로 친다');
  // 문서(fitness.md)의 "끝까지 약 3만 9천 개" — 표를 고치면 문서도 고친다
  assert.ok(Math.abs(fitnessExpectedCost() - 38_700) < 1_000, `기댓값 ${Math.round(fitnessExpectedCost())}`);
});

test('헬스 — 던전 단계마다 프로틴 = 단계 × 5 (토벌만, 시련의 탑은 크리스탈만)', () => {
  for (const type of DUNGEON_TYPES.filter((t) => t.open)) {
    for (const stage of type.stages) {
      const want = type.id === 'trial' ? 0 : stage.stage * DUNGEON_PROTEIN_PER_STAGE;
      assert.equal(stage.protein, want, `${type.id} ${stage.stage}단계`);
    }
  }
});
