import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIELD_ORDER, START_ZONE, ZONES, getSpawn, getZone } from './zones.ts';
import { MONSTER_KINDS } from './monsters.ts';
import { zoneHalfSize } from './movement.ts';

/**
 * 존 연결 검사.
 *
 * 포탈 링크는 어긋나도 예외가 나지 않는다 — getSpawn 이 default 로 떨어뜨리기
 * 때문에 "왜 엉뚱한 데서 시작하지?" 하는 증상으로만 나타난다. 그래서 데이터로
 * 검사한다.
 */

test('모든 포탈이 실재하는 존과 스폰을 가리킨다', () => {
  for (const zone of Object.values(ZONES)) {
    for (const portal of zone.portals) {
      const target = ZONES[portal.target.zone];
      assert.ok(target, `${zone.id}/${portal.id} → 없는 존 '${portal.target.zone}'`);
      assert.ok(
        target.spawns[portal.target.spawn],
        `${zone.id}/${portal.id} → ${target.id} 에 '${portal.target.spawn}' 스폰이 없다`
      );
    }
  }
});

test('포탈은 양방향이다 — 들어간 곳으로 되돌아올 수 있다', () => {
  for (const zone of Object.values(ZONES)) {
    for (const portal of zone.portals) {
      const target = getZone(portal.target.zone);
      const back = target.portals.some((p) => p.target.zone === zone.id);
      assert.ok(back, `${target.id} 에서 ${zone.id} 로 돌아오는 포탈이 없다`);
    }
  }
});

test('스폰과 포탈이 이동 가능 영역 안에 있다', () => {
  for (const zone of Object.values(ZONES)) {
    const half = zoneHalfSize(zone.size);

    for (const [name, [x, z]] of Object.entries(zone.spawns)) {
      assert.ok(
        Math.abs(x) <= half && Math.abs(z) <= half,
        `${zone.id}/${name} (${x}, ${z}) 가 ±${half} 밖이다`
      );
    }

    for (const portal of zone.portals) {
      const [x, z] = portal.position;
      assert.ok(
        Math.abs(x) <= half && Math.abs(z) <= half,
        `${zone.id}/${portal.id} (${x}, ${z}) 가 ±${half} 밖이다`
      );
    }
  }
});

test('도착 지점이 포탈 위가 아니다', () => {
  // 포탈 위에 떨어뜨리면 즉시 되돌아가서 두 존을 무한히 왕복한다
  for (const zone of Object.values(ZONES)) {
    for (const portal of zone.portals) {
      for (const [name, [x, z]] of Object.entries(zone.spawns)) {
        const d = Math.hypot(x - portal.position[0], z - portal.position[1]);
        assert.ok(
          d > portal.radius + 2,
          `${zone.id}/${name} 이 ${portal.id} 판정 안에 있다 (거리 ${d.toFixed(1)})`
        );
      }
    }
  }
});

test('몬스터 무리가 실재하는 종이고 영역 안에 있다', () => {
  for (const zone of Object.values(ZONES)) {
    const half = zoneHalfSize(zone.size);
    for (const spawn of zone.monsters ?? []) {
      assert.ok(MONSTER_KINDS[spawn.kind], `${zone.id}: 없는 몬스터 '${spawn.kind}'`);
      const reach = Math.max(Math.abs(spawn.x) + spawn.radius, Math.abs(spawn.z) + spawn.radius);
      assert.ok(reach <= half, `${zone.id}/${spawn.kind} 무리가 ±${half} 를 넘는다 (${reach})`);
    }
  }
});

test('마을은 안전지대다', () => {
  assert.equal(ZONES[START_ZONE]?.monsters ?? undefined, undefined, '시작 존에 몬스터가 있으면 안 된다');
});

test('모든 존이 시작 존에서 걸어서 닿는다', () => {
  // 어느 한 존이라도 끊겨 있으면 만들어놓고 못 가는 콘텐츠가 된다
  const seen = new Set<string>([START_ZONE]);
  const queue = [START_ZONE];
  while (queue.length > 0) {
    const zone = getZone(queue.shift()!);
    for (const portal of zone.portals) {
      if (seen.has(portal.target.zone)) continue;
      seen.add(portal.target.zone);
      queue.push(portal.target.zone);
    }
  }
  assert.deepEqual([...seen].sort(), Object.keys(ZONES).sort());
});

test('사냥터가 레벨 순서대로 사슬로 이어져 있다', () => {
  // 마을 — 사냥터1 — 사냥터2 — … — 사냥터20 (+ 지름길 하나)
  assert.deepEqual(
    getZone(START_ZONE).portals.map((p) => p.target.zone),
    [FIELD_ORDER[0]],
    '마을은 첫 사냥터에만 붙는다'
  );

  FIELD_ORDER.forEach((id, i) => {
    const links = new Set(getZone(id).portals.map((p) => p.target.zone));
    const expected = new Set<string>();
    expected.add(i === 0 ? START_ZONE : FIELD_ORDER[i - 1]!);
    if (i < FIELD_ORDER.length - 1) expected.add(FIELD_ORDER[i + 1]!);
    // 처음 그린 배치도의 지름길: 첫 사냥터 ↔ 네 번째 사냥터
    if (i === 0) expected.add(FIELD_ORDER[3]!);
    if (i === 3) expected.add(FIELD_ORDER[0]!);

    assert.deepEqual([...links].sort(), [...expected].sort(), `${id} 의 연결이 다르다`);
  });
});

test('사냥터 순서가 몬스터 레벨 순서와 같다', () => {
  // 순서가 어긋나면 레벨 곡선 계산이 통째로 틀어진다
  let previous = 0;
  for (const id of FIELD_ORDER) {
    const levels = (getZone(id).monsters ?? []).map((m) => MONSTER_KINDS[m.kind]!.level);
    const lowest = Math.min(...levels);
    assert.ok(lowest > previous, `${id} 가 앞 사냥터보다 낮은 레벨대다`);
    previous = lowest;
  }
});

test('없는 스폰 이름은 default 로 떨어진다', () => {
  const zone = getZone(START_ZONE);
  assert.deepEqual(getSpawn(zone, '오타난_이름'), zone.spawns.default);
});
