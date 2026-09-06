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

// --- 마을 차원문 -----------------------------------------------------------
// 문은 밟아야 열린다. 겹치거나 밖에 놓이면 예외가 나지 않고 "안 열린다" 로만
// 나타나서, 문을 못 찾은 건지 코드가 안 도는 건지 구분이 안 된다.

test('차원문은 마을에만 있다', () => {
  const withGate = Object.values(ZONES).filter((z) => z.gate);
  assert.deepEqual(
    withGate.map((z) => z.id),
    [START_ZONE],
    '사냥터에도 문이 생기면 죽어도 곧장 제자리로 돌아와 존을 나눈 의미가 없어진다'
  );
});

test('차원문이 이동 가능 영역 안에 있고 다른 것과 겹치지 않는다', () => {
  for (const zone of Object.values(ZONES)) {
    const gate = zone.gate;
    if (!gate) continue;
    const half = zoneHalfSize(zone.size);
    const [gx, gz] = gate.position;
    assert.ok(
      Math.abs(gx) <= half && Math.abs(gz) <= half,
      `${zone.id} 차원문이 걸어갈 수 없는 자리에 있다`
    );

    // 사슬 포탈과 겹치면 밟는 순간 둘 다 발동해 창이 열리자마자 존이 바뀐다
    for (const portal of zone.portals) {
      const d = Math.hypot(portal.position[0] - gx, portal.position[1] - gz);
      assert.ok(d > gate.radius + portal.radius, `${zone.id} 차원문이 ${portal.id} 과 겹친다`);
    }
    // 스폰 위에 놓으면 접속하자마자 창이 열린다
    for (const [name, [sx, sz]] of Object.entries(zone.spawns)) {
      const d = Math.hypot(sx - gx, sz - gz);
      assert.ok(d > gate.radius, `${zone.id} 차원문이 '${name}' 스폰을 덮는다`);
    }
    // NPC 위에 놓으면 말걸기와 문이 같은 자리에서 다툰다
    for (const npc of zone.npcs ?? []) {
      const d = Math.hypot(npc.x - gx, npc.z - gz);
      assert.ok(d > gate.radius + 1, `${zone.id} 차원문이 ${npc.name} 과 겹친다`);
    }
  }
});

test('차원문 목록의 사냥터가 전부 default 스폰을 가진다', () => {
  // 창은 항상 'default'(맵 한가운데)로 보낸다. 없으면 getSpawn 이 조용히
  // 떨어뜨려서 엉뚱한 자리에 도착한다.
  for (const zoneId of FIELD_ORDER) {
    const zone = getZone(zoneId);
    assert.ok(zone.spawns.default, `${zoneId} 에 default 스폰이 없다`);
    const [x, z] = getSpawn(zone, 'default');
    // 한가운데는 무리(±20)에서 충분히 떨어져 있어야 도착하자마자 안 물린다
    for (const pack of zone.monsters ?? []) {
      const d = Math.hypot(pack.x - x, pack.z - z);
      const kind = MONSTER_KINDS[pack.kind];
      assert.ok(kind, `${zoneId} 에 없는 몬스터 ${pack.kind}`);
      assert.ok(
        d > pack.radius + kind.aggroRange,
        `${zoneId}: 도착 지점이 ${kind.name} 무리의 인식 범위 안이다 (${d.toFixed(1)}m)`
      );
    }
  }
});
