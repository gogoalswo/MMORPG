import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIELD_ORDER, START_ZONE, ZONES, getSpawn, getZone } from './zones.ts';
import { DUNGEON_TYPES, DUNGEON_ZONES } from './dungeons.ts';
import { MONSTER_KINDS } from './monsters.ts';
import { GROUND_KINDS } from './zone.ts';
import { MONSTER_GAP, monsterRadius, scatterSpawn, zoneHalfSize, type Solid } from './movement.ts';

/**
 * 존 연결 검사.
 *
 * 존을 오가는 길은 차원문 하나뿐이다. 문이 빠지거나 목록에서 빠져도 예외가
 * 나지 않고 "여기서 어떻게 나가지?" 로만 나타나므로 데이터로 검사한다.
 */

test('스폰이 이동 가능 영역 안에 있다', () => {
  for (const zone of Object.values(ZONES)) {
    const half = zoneHalfSize(zone.size);
    for (const [name, [x, z]] of Object.entries(zone.spawns)) {
      assert.ok(
        Math.abs(x) <= half && Math.abs(z) <= half,
        `${zone.id}/${name} (${x}, ${z}) 가 ±${half} 밖이다`
      );
    }
  }
});

test('걸어 들어가는 포탈이 남아 있지 않다', () => {
  // 사슬 포탈은 전부 없앴다. 되살아나면 차원문과 이동 경로가 두 벌이 된다.
  for (const zone of Object.values(ZONES)) {
    assert.ok(
      !('portals' in zone),
      `${zone.id} 에 portals 가 남아 있다 — 이동은 차원문 하나로만 한다`
    );
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

test('바닥 텍스처가 전부 쓰이고, 길·풀 잎이 되살아나지 않는다', () => {
  const used = new Set<string>();
  for (const zone of Object.values(ZONES)) {
    const { ground } = zone.env;
    assert.ok(GROUND_KINDS.includes(ground), `${zone.id}: 없는 바닥 '${ground}'`);
    used.add(ground);
    // 바닥은 이미지 한 장만 깐다 (2026-09-10 요청). 길·풀 잎 필드가 돌아오면 여기서 잡는다.
    for (const gone of ['road', 'roads', 'roadTint', 'grassCount', 'grassRadius']) {
      assert.ok(!(gone in zone.env), `${zone.id}: 없앤 '${gone}' 이 env 에 있다`);
    }
  }
  // 아무도 안 쓰는 이미지는 부팅 때 받기만 하는 짐이다
  assert.deepEqual([...used].sort(), [...GROUND_KINDS].sort());
});

test('차원문 목록이 세상의 모든 존을 덮는다', () => {
  // 목록에 없는 존은 만들어놓고 못 가는 콘텐츠가 된다.
  // 창은 마을 + FIELD_ORDER 로 줄을 만든다 (zoneGate.ts).
  // 던전 단계는 차원문이 아니라 던전 창으로 간다 (dungeons.ts)
  const reachable = new Set<string>([START_ZONE, ...FIELD_ORDER, ...DUNGEON_ZONES]);
  assert.deepEqual([...reachable].sort(), Object.keys(ZONES).sort());
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

test('던전 — 종류 셋, 열린 종류는 단계마다 보스 한 마리', () => {
  assert.equal(DUNGEON_TYPES.length, 3);
  assert.ok(DUNGEON_TYPES.some((t) => t.open), '열린 던전이 하나도 없다');
  for (const type of DUNGEON_TYPES) {
    // 닫힌 종류에 단계가 있으면 창에서 못 가는 존이 생긴다
    assert.equal(type.open, type.stages.length > 0, `${type.id}: 열림과 단계 유무가 어긋난다`);
    let previous = 0;
    for (const s of type.stages) {
      const zone = getZone(s.zone);
      const monsters = zone.monsters ?? [];
      assert.equal(monsters.length, 1, `${s.zone}: 보스 한 무리만 있어야 한다`);
      assert.equal(monsters[0]!.count, 1);
      assert.equal(monsters[0]!.kind, s.boss);
      const kind = MONSTER_KINDS[s.boss];
      assert.ok(kind?.boss, `${s.zone}: ${s.boss} 가 보스가 아니다`);
      assert.equal(kind.level, s.level);
      // 단계가 오를수록 보스가 세진다
      assert.ok(s.level > previous, `${s.zone}: 앞 단계보다 낮은 레벨`);
      previous = s.level;
      // 사냥터 창으로 가는 곳과 섞이면 차원문 목록이 던전까지 늘어난다
      assert.ok(!FIELD_ORDER.includes(s.zone));
    }
  }
  assert.equal(new Set(DUNGEON_ZONES).size, DUNGEON_ZONES.length, '단계 존 id 가 겹친다');
});

test('없는 스폰 이름은 default 로 떨어진다', () => {
  const zone = getZone(START_ZONE);
  assert.deepEqual(getSpawn(zone, '오타난_이름'), zone.spawns.default);
});

// --- 차원문 ----------------------------------------------------------------
// 문은 밟아야 열린다. 겹치거나 밖에 놓이면 예외가 나지 않고 "안 열린다" 로만
// 나타나서, 문을 못 찾은 건지 코드가 안 도는 건지 구분이 안 된다.

test('차원문이 모든 존에 있다', () => {
  // 걸어 들어가는 포탈이 없으므로, 문이 없는 존은 들어가면 죽는 것 말고는
  // 나올 방법이 없는 방이 된다.
  const without = Object.values(ZONES).filter((z) => !z.gate);
  assert.deepEqual(without.map((z) => z.id), [], '차원문이 없는 존이 있다');
});

test('차원문이 모든 존에서 같은 자리·같은 색이다', () => {
  // 존마다 다르면 "나가려면 어디로" 를 매번 다시 찾는다
  const gates = Object.values(ZONES).map((z) => z.gate);
  const first = gates[0]!;
  for (const gate of gates) {
    assert.deepEqual(gate.position, first.position);
    assert.equal(gate.radius, first.radius);
    assert.equal(gate.color, first.color);
    assert.equal(gate.name, first.name);
  }
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
    // 무리 안에 놓으면 나가려고 문을 밟는 것 자체가 싸움이 된다.
    // 도착 지점과 달리 여기는 걸어서 가는 자리라 인식 범위까지는 안 본다.
    for (const pack of zone.monsters ?? []) {
      const d = Math.hypot(pack.x - gx, pack.z - gz);
      assert.ok(d > pack.radius + 4, `${zone.id} 차원문이 ${pack.kind} 무리 안에 있다`);
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
    // 도착 지점이 무리 원 안이면 몬스터 사이에 떨어진다. 인식 범위(반경 + aggroRange)
    // 밖까지는 안 본다 — 맵을 2/3 로 줄이며(2026-09-23) 무리가 ±14 로 붙어서, 도착하면
    // 몬스터가 알아채는 것을 받아들였다 (docs/features/world-zones.md "무리 자리")
    for (const pack of zone.monsters ?? []) {
      const d = Math.hypot(pack.x - x, pack.z - z);
      const kind = MONSTER_KINDS[pack.kind];
      assert.ok(kind, `${zoneId} 에 없는 몬스터 ${pack.kind}`);
      assert.ok(
        d > pack.radius,
        `${zoneId}: 도착 지점이 ${kind.name} 무리 안이다 (${d.toFixed(1)}m)`
      );
    }
  }
});

test('무리 안에서 몬스터가 서로 겹치지 않는다', () => {
  /**
   * 스폰 원이 좁은데 마릿수가 많거나 몬스터가 크면 `scatterSpawn` 이 빈 자리를 못 찾고
   * 겹친 채로 놓는다. 몬스터는 가만히 서 있으므로 그게 그대로 화면에 남는다
   * (실제로 한 자리에 두 마리가 포개져 보였다). 무리 정의를 손댈 때 여기서 걸린다.
   *
   * 난수는 씨앗을 고정한다 — 테스트가 어떤 날만 실패하면 아무도 안 믿는다.
   */
  let seed = 12345;
  const random = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };

  for (const zone of Object.values(ZONES)) {
    const half = zoneHalfSize(zone.size);
    for (const spawn of zone.monsters ?? []) {
      const kind = MONSTER_KINDS[spawn.kind];
      const r = monsterRadius(kind.scale);
      const placed: Solid[] = [];
      for (let i = 0; i < spawn.count; i++) {
        const spot = scatterSpawn(spawn, r, placed, half, random);
        for (const other of placed) {
          // other.r 에 이미 MONSTER_GAP 이 들어 있다 — 서버가 보는 목록과 같은 모양이다
          const gap = Math.hypot(spot.x - other.x, spot.z - other.z) - (other.r + r);
          assert.ok(
            gap > -1e-6,
            `${zone.id} 의 ${spawn.kind} 무리(반경 ${spawn.radius}, ${spawn.count}마리)가 ` +
              `${(-gap).toFixed(2)}m 모자란다 — 반경을 넓히거나 마릿수를 줄인다`
          );
        }
        placed.push({ x: spot.x, z: spot.z, r: r + MONSTER_GAP });
      }
    }
  }
});
