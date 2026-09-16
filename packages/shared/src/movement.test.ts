import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_INPUT_DT,
  PLAYER_RADIUS,
  applyMove,
  monsterRadius,
  pushOutOfSolids,
  scatterSpawn,
  zoneHalfSize,
  type Solid,
} from './movement.ts';
import { RUN_SPEED } from './constants.ts';
import { statsFor } from './combat.ts';
import { JOB_IDS } from './character.ts';
import { MONSTER_KINDS } from './monsters.ts';

/**
 * 이동과 충돌 검사.
 *
 * 이 두 가지는 **클라이언트와 서버가 같은 함수를 돌려야** 하는 곳이라, 한쪽만 고치면
 * 보정이 튀면서 캐릭터가 떨린다. 떨림은 눈으로 보고 원인을 짚기가 어려우니 규칙으로 잡는다.
 */

const HALF = zoneHalfSize(92);

test('입력 dt 는 잘린다 — 부풀려도 순간이동 못 한다', () => {
  const state = { x: 0, z: 0 };
  applyMove(state, { seq: 1, dx: 1, dz: 0, dt: 100 }, HALF);
  assert.ok(state.x <= RUN_SPEED * MAX_INPUT_DT + 1e-6, `${state.x} 까지 갔다`);
});

test('존 밖으로는 못 나간다', () => {
  const state = { x: HALF - 0.1, z: 0 };
  applyMove(state, { seq: 1, dx: 1, dz: 0, dt: MAX_INPUT_DT }, HALF);
  assert.equal(state.x, HALF);
});

test('겹치면 밖으로 밀린다', () => {
  const solid: Solid = { x: 0, z: 0, r: 1 };
  const state = { x: 0.2, z: 0 };
  pushOutOfSolids(state, [solid], HALF);
  const distance = Math.hypot(state.x - solid.x, state.z - solid.z);
  assert.ok(
    Math.abs(distance - (solid.r + PLAYER_RADIUS)) < 1e-6,
    `닿기만 해야 하는데 거리가 ${distance}`
  );
});

test('정확히 한가운데 겹쳐도 빠져나온다', () => {
  // 방향이 없어서 0 으로 나누면 NaN 이 되고, 그 순간 캐릭터가 화면에서 사라진다
  const state = { x: 0, z: 0 };
  pushOutOfSolids(state, [{ x: 0, z: 0, r: 1 }], HALF);
  assert.ok(Number.isFinite(state.x) && Number.isFinite(state.z), '좌표가 NaN 이 됐다');
  assert.ok(Math.hypot(state.x, state.z) > 1, '아직 안에 있다');
});

test('닿지 않으면 건드리지 않는다', () => {
  const state = { x: 5, z: 0 };
  pushOutOfSolids(state, [{ x: 0, z: 0, r: 1 }], HALF);
  assert.deepEqual(state, { x: 5, z: 0 });
});

test('몬스터를 향해 걸어가면 몸에서 멈춘다', () => {
  const solid: Solid = { x: 2, z: 0, r: monsterRadius(1) };
  const state = { x: 0, z: 0 };
  for (let i = 0; i < 60; i++) {
    applyMove(state, { seq: i + 1, dx: 1, dz: 0, dt: MAX_INPUT_DT }, HALF, [solid]);
  }
  const distance = Math.hypot(state.x - solid.x, state.z - solid.z);
  assert.ok(
    Math.abs(distance - (solid.r + PLAYER_RADIUS)) < 1e-6,
    `뚫고 지나갔거나 못 붙었다 — 거리 ${distance}`
  );
});

test('아무리 큰 몬스터라도 붙어서 때릴 수 있다', () => {
  /**
   * 충돌 반지름이 공격 사거리보다 크면 **서로 영원히 못 때린다.**
   * 가장 큰 몬스터와 가장 짧은 사거리를 맞대 본다 — 이 줄이 깨지면
   * `monsterRadius` 의 계수(0.38)를 줄여야 한다.
   */
  const kinds = Object.values(MONSTER_KINDS);
  const shortestJob = Math.min(...JOB_IDS.map((job) => statsFor(job, 1).attackRange));

  /**
   * **종마다 따로 본다.** 가장 큰 몬스터와 가장 짧은 몬스터 사거리를 맞대는 식으로 재면
   * 실제로 만나지 않는 짝을 검사하게 돼서, 통과해도 통과한 게 아니고 실패해도 고칠
   * 곳이 없다. 작은 놈은 사거리가 짧아도 몸이 얇아서 문제가 없다.
   */
  for (const kind of kinds) {
    const reach = monsterRadius(kind.scale) + PLAYER_RADIUS;
    assert.ok(
      reach < shortestJob,
      `${kind.id} 의 몸(${reach.toFixed(2)})이 직업 사거리(${shortestJob})보다 두껍다`
    );
    assert.ok(
      reach < kind.attackRange,
      `${kind.id} 의 몸(${reach.toFixed(2)})이 제 사거리(${kind.attackRange})보다 두껍다`
    );
  }
});

test('캐릭터끼리도 겹치지 않는다 — 몸 두 개만큼 떨어져 선다', () => {
  const other: Solid = { x: 2, z: 0, r: PLAYER_RADIUS };
  const me = { x: 0, z: 0 };
  for (let i = 0; i < 60; i++) {
    applyMove(me, { seq: i + 1, dx: 1, dz: 0, dt: MAX_INPUT_DT }, HALF, [other]);
  }
  const distance = Math.hypot(me.x - other.x, me.z - other.z);
  assert.ok(
    Math.abs(distance - PLAYER_RADIUS * 2) < 1e-6,
    `뚫고 지나갔거나 못 붙었다 — 거리 ${distance}`
  );
});

test('서 있는 캐릭터는 밀리지 않는다', () => {
  /**
   * 캐릭터끼리 충돌에서 **한쪽만 미는 규칙**이 이것으로 성립한다. 둘 다 밀면 서로
   * 밀치며 떨고, 그 떨림은 서버·클라 보정과 섞여 원인을 짚기가 어려워진다.
   */
  const me = { x: 0, z: 0 };
  applyMove(me, { seq: 1, dx: 0, dz: 0, dt: MAX_INPUT_DT }, HALF, [{ x: 0, z: 0, r: PLAYER_RADIUS }]);
  assert.deepEqual(me, { x: 0, z: 0 });
});

test('캐릭터 몸 두께가 공격 사거리를 막지 않는다', () => {
  // 서로 못 때리게 되는 순간을 막는다 — 몬스터 쪽과 같은 이유다
  const reach = PLAYER_RADIUS * 2;
  const shortest = Math.min(...JOB_IDS.map((job) => statsFor(job, 1).attackRange));
  assert.ok(reach < shortest, `몸(${reach})이 직업 사거리(${shortest})보다 두껍다`);
});

test('스폰 자리는 이미 서 있는 몸을 피한다', () => {
  const taken: Solid[] = [{ x: 0, z: 0, r: 1 }];
  const spot = scatterSpawn({ x: 0, z: 0, radius: 6 }, 0.5, taken, HALF);
  const gap = Math.hypot(spot.x, spot.z) - 1.5;
  assert.ok(gap >= -1e-6, `겹친 자리에 놓였다 — ${gap.toFixed(2)}m 모자란다`);
});

test('자리가 없어도 멈추지 않고 가장 나은 자리를 낸다', () => {
  // 무리가 빽빽하면 빈 자리가 없다. "될 때까지" 돌리면 서버가 그대로 멈춘다
  const wall: Solid[] = [];
  for (let x = -3; x <= 3; x++) for (let z = -3; z <= 3; z++) wall.push({ x, z, r: 1 });
  const spot = scatterSpawn({ x: 0, z: 0, radius: 1 }, 1, wall, HALF);
  assert.ok(Number.isFinite(spot.x) && Number.isFinite(spot.z), '좌표가 NaN 이 됐다');
});

test('몬스터끼리 밀 때는 캐릭터 반지름을 쓰지 않는다', () => {
  // pushOutOfSolids 의 넷째 인자를 빠뜨리면 큰 몬스터가 서로 파고든 채로 선다
  const big = monsterRadius(3);
  const me = { x: 0, z: 0 };
  pushOutOfSolids(me, [{ x: 0.5, z: 0, r: big }], HALF, big);
  const distance = Math.hypot(me.x - 0.5, me.z);
  assert.ok(Math.abs(distance - big * 2) < 1e-6, `거리 ${distance}, 기대 ${big * 2}`);
});

test('같은 자리에 겹친 둘은 서로 다른 쪽으로 빠진다', () => {
  /**
   * 밀 방향이 같으면 둘 다 같은 자리로 밀려 영원히 겹친 채로 남는다. 몬스터 여럿이 한
   * 사람을 쫓을 때 실제로 그랬다 — 앞줄에 막힌 두 마리가 정확히 같은 점에 포개졌다.
   */
  const wall: Solid[] = [{ x: 0, z: 0, r: 1 }];
  const a = { x: 2.5, z: 0 };
  const b = { x: 2.5, z: 0 };
  pushOutOfSolids(a, [...wall, { x: b.x, z: b.z, r: 0.5 }], HALF, 0.5, 0.3);
  pushOutOfSolids(b, [...wall, { x: a.x, z: a.z, r: 0.5 }], HALF, 0.5, 3.4);
  assert.ok(Math.hypot(a.x - b.x, a.z - b.z) > 0.9, `아직 겹쳐 있다 (${a.x}, ${a.z})`);
});
