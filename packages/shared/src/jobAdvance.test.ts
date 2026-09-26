import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JOB_ADVANCES, JOB_TIER_MAX } from './jobAdvance.ts';
import { ZONES, START_ZONE } from './zones.ts';
import { MONSTER_KINDS } from './monsters.ts';
import { JOB_SKILLS, SKILLS, canLearn } from './skills.ts';

test('전직 — 30 · 70 · 120 · 180, 단계는 1부터 차례로', () => {
  assert.deepEqual(JOB_ADVANCES.map((a) => a.level), [30, 70, 120, 180]);
  assert.deepEqual(JOB_ADVANCES.map((a) => a.tier), [1, 2, 3, 4]);
  assert.equal(JOB_TIER_MAX, 4);
});

test('전직 시험마다 존이 있고 보스가 한 마리, 전직 레벨보다 한 급 아래다', () => {
  for (const a of JOB_ADVANCES) {
    const zone = ZONES[a.zone];
    assert.ok(zone, `${a.zone} 존이 없다`);
    const packs = zone.monsters ?? [];
    assert.equal(packs.length, 1, `${a.zone}: 무리가 ${packs.length}`);
    assert.equal(packs[0]!.count, 1);
    const kind = MONSTER_KINDS[packs[0]!.kind];
    assert.ok(kind?.boss, `${a.zone}: 보스가 아니다`);
    assert.equal(kind!.level, a.bossLevel);
    assert.equal(a.bossLevel, a.level - 1, `${a.tier}차: 보스 Lv.${a.bossLevel}`);
  }
});

test('전직 NPC 가 마을에 있다', () => {
  const npcs = ZONES[START_ZONE]!.npcs ?? [];
  assert.equal(npcs.filter((n) => n.role === 'jobs').length, 1);
});

test('격투가 — 할퀴기는 기본, 낙뢰 1차 · 빙주각 2차 · 천붕각 3차', () => {
  const tierOf = (id: string) => SKILLS[id]!.tier ?? 0;
  assert.equal(tierOf('rising_kick'), 0);
  assert.equal(tierOf('thunder_fall'), 1);
  assert.equal(tierOf('frost_pillar'), 2);
  assert.equal(tierOf('sky_breaker'), 3);
  // 요구 레벨이 그 단계의 전직 레벨과 같다 — 스킬창의 "Lv.N" 이 전직 레벨을 가리킨다
  for (const id of JOB_SKILLS.fighter) {
    const tier = tierOf(id);
    if (tier > 0) assert.equal(SKILLS[id]!.reqLevel, JOB_ADVANCES[tier - 1]!.level, id);
  }
});

test('전직이 모자라면 레벨이 넉넉해도 못 배운다', () => {
  const thunder = SKILLS.thunder_fall!;
  assert.equal(canLearn(thunder, 'fighter', 200, 0), false);
  assert.equal(canLearn(thunder, 'fighter', 200, 1), true);
  assert.equal(canLearn(SKILLS.rising_kick!, 'fighter', 1, 0), true);
});
