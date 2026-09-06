import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  HUNT_RADIUS,
  HUNT_RADIUS_MAX,
  HUNT_RADIUS_MIN,
  clampHuntRadius,
  huntLeash,
  pickHuntTarget,
  standoffPoint,
} from './autoHunt.ts';

const mob = (id: string, x: number, z: number, hp = 10) => ({ id, x, z, hp });

test('앵커에서 가장 가까운 몬스터를 고른다', () => {
  const picked = pickHuntTarget(0, 0, [mob('a', 10, 0), mob('b', 3, 0), mob('c', 8, 0)], null);
  assert.equal(picked, 'b');
});

test('반경 밖은 아예 고르지 않는다', () => {
  const picked = pickHuntTarget(0, 0, [mob('far', HUNT_RADIUS + 5, 0)], null);
  assert.equal(picked, null, '멀리 있는 몬스터를 향해 걸어가면 앵커에서 이탈한다');
});

test('죽은 몬스터는 고르지 않는다', () => {
  const picked = pickHuntTarget(0, 0, [mob('dead', 1, 0, 0), mob('alive', 9, 0)], null);
  assert.equal(picked, 'alive');
});

test('잡고 있던 대상을 더 가까운 놈이 나타나도 유지한다', () => {
  // 매 틱 가장 가까운 놈으로 갈아타면 둘 사이에서 진동하다 아무것도 못 죽인다
  const picked = pickHuntTarget(0, 0, [mob('near', 2, 0), mob('current', 12, 0)], 'current');
  assert.equal(picked, 'current');
});

test('잡고 있던 대상이 리쉬를 넘어가면 포기하고 다시 고른다', () => {
  const beyond = huntLeash(HUNT_RADIUS) + 1;
  const picked = pickHuntTarget(0, 0, [mob('near', 2, 0), mob('current', beyond, 0)], 'current');
  assert.equal(picked, 'near');
});

test('잡고 있던 대상이 죽으면 다른 놈으로 넘어간다', () => {
  const picked = pickHuntTarget(0, 0, [mob('current', 3, 0, 0), mob('next', 7, 0)], 'current');
  assert.equal(picked, 'next');
});

test('후보가 없으면 null', () => {
  assert.equal(pickHuntTarget(0, 0, [], null), null);
});

test('스탠드오프는 대상에서 딱 그 거리만큼 떨어진 점이다', () => {
  const p = standoffPoint(10, 0, 0, 0, 3);
  assert.ok(Math.abs(Math.hypot(p.x, p.z) - 3) < 1e-6);
  assert.ok(p.x > 0, '내가 있는 쪽으로 물러난 점이어야 한다');
});

test('스탠드오프는 대상과 겹쳐 있어도 좌표가 깨지지 않는다', () => {
  const p = standoffPoint(5, 5, 5, 5, 2);
  assert.ok(Number.isFinite(p.x) && Number.isFinite(p.z));
  assert.ok(Math.abs(Math.hypot(p.x - 5, p.z - 5) - 2) < 1e-6);
});

test('사냥 반경은 정해진 범위로 잘린다', () => {
  // 사람이 보낸 값을 그대로 쓰면 반경 9999 로 맵 전체를 긁는다
  assert.equal(clampHuntRadius(1), HUNT_RADIUS_MIN);
  assert.equal(clampHuntRadius(9999), HUNT_RADIUS_MAX);
  assert.equal(clampHuntRadius('스물'), HUNT_RADIUS);
  assert.equal(clampHuntRadius(undefined), HUNT_RADIUS);
  assert.equal(clampHuntRadius(Number.NaN), HUNT_RADIUS);
  assert.equal(clampHuntRadius(18.6), 19);
});

test('리쉬는 사냥 반경보다 넉넉하다', () => {
  // 같으면 경계에 걸친 몬스터를 잡았다 놓았다 반복한다
  for (const r of [HUNT_RADIUS_MIN, HUNT_RADIUS, HUNT_RADIUS_MAX]) {
    assert.ok(huntLeash(r) > r, `반경 ${r} 에서 리쉬가 좁다`);
  }
});

test('반경을 좁히면 먼 몬스터를 고르지 않는다', () => {
  const mobs = [mob('near', 5, 0), mob('far', 25, 0)];
  assert.equal(pickHuntTarget(0, 0, mobs, null, 30), 'near', '가까운 쪽이 우선이다');
  assert.equal(pickHuntTarget(0, 0, [mob('far', 25, 0)], null, 10), null, '반경 밖은 안 고른다');
  assert.equal(pickHuntTarget(0, 0, [mob('far', 25, 0)], null, 30), 'far');
});
