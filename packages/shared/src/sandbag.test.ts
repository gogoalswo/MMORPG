import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SANDBAG_COUNTDOWN_SECONDS,
  SANDBAG_KIND,
  SANDBAG_REWARDS,
  SANDBAG_SECONDS,
  SANDBAG_RANK_REFRESH_SECONDS,
  SANDBAG_ZONE,
  sandbagReward,
  sandbagWeek,
} from './sandbag.ts';
import { ZONES } from './zones.ts';
import { MONSTER_KINDS } from './monsters.ts';

test('샌드백 랭킹전 — 3초 카운트 → 15초, 과녁 하나', () => {
  // 2026-10-02 요청: "3초 카운트를 세. 그리고 15초 동안 얼마만큼 데미지를 입히는지 누적해서"
  assert.equal(SANDBAG_COUNTDOWN_SECONDS, 3);
  assert.equal(SANDBAG_SECONDS, 15);
  assert.equal(SANDBAG_RANK_REFRESH_SECONDS, 60);
  const zone = ZONES[SANDBAG_ZONE]!;
  assert.deepEqual(zone.monsters!.map((m) => [m.kind, m.count]), [[SANDBAG_KIND.id, 1]]);
  assert.equal(zone.gate, undefined, '차원문 없음 — 결과창 확인이 마을로 보낸다');
  // 누구나 같은 과녁을 친다 — 막는 수치가 없고, 안 움직이고 안 때린다
  assert.equal(SANDBAG_KIND.defense, 0);
  assert.equal(SANDBAG_KIND.critResist, 0);
  assert.equal(SANDBAG_KIND.moveSpeed, 0);
  assert.equal(SANDBAG_KIND.attack, 0);
  assert.equal(MONSTER_KINDS[SANDBAG_KIND.id], undefined, '몬스터 표(60종)에는 없다');
  // 둘이 격투가 사거리(2.2) 안에 나란히 선다
  const [sx, sz] = zone.spawns.default!;
  const m = zone.monsters![0]!;
  assert.ok(Math.hypot(m.x - sx, m.z - sz) < 2.2);
});

test('주는 월요일 0시(한국)에 바뀐다', () => {
  // 2026-10-05(월) 00:00 KST = 2026-10-04 15:00 UTC
  const monday = Date.UTC(2026, 9, 4, 15, 0, 0) / 1000;
  assert.equal(sandbagWeek(monday) - sandbagWeek(monday - 1), 1);
  assert.equal(sandbagWeek(monday + 7 * 86400 - 1), sandbagWeek(monday));
  assert.equal(sandbagWeek(monday + 7 * 86400), sandbagWeek(monday) + 1);
});

test('순위 보상 — 줄이 빈틈없이 이어지고 순위가 낮을수록 적다', () => {
  for (let i = 1; i < SANDBAG_REWARDS.length; i++) {
    assert.equal(SANDBAG_REWARDS[i]!.from, SANDBAG_REWARDS[i - 1]!.to! + 1);
    assert.ok(SANDBAG_REWARDS[i]!.yellowCrystals < SANDBAG_REWARDS[i - 1]!.yellowCrystals);
  }
  assert.equal(SANDBAG_REWARDS.at(-1)!.to, null, '마지막 줄은 참가 보상');
  assert.equal(sandbagReward(1), 30);
  assert.equal(sandbagReward(7), 15);
  assert.equal(sandbagReward(5000), 2);
  assert.equal(sandbagReward(0), 0);
});
