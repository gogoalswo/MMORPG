/**
 * godot/data/*.json 이 이 패키지의 표와 같은지 본다.
 *
 * 고도는 TS 를 실행할 수 없어서 표를 JSON 으로 내보내 읽는다
 * (docs/features/godot-migration.md). 그래서 여기 수치를 고치고 내보내기를
 * 잊으면 **웹과 고도가 다른 게임이 된다** — 조용히 갈라지는 종류의 사고라
 * 전수 검사로 막는다.
 *
 * 깨졌으면: node scripts/export-shared.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { buildData, serialize, readExported } from '../../../scripts/export-shared.mjs';

const data = buildData();

for (const [name, value] of Object.entries(data)) {
  test(`godot/data/${name} 이 최신이다`, () => {
    assert.equal(
      readExported(name),
      serialize(value),
      `${name} 이 낡았다 — node scripts/export-shared.mjs 를 돌려라`,
    );
  });
}

test('내보낸 개수가 문서와 맞는다', () => {
  assert.equal(Object.keys(data['zones.json'].zones).length, 21, '존 21곳');
  assert.equal(Object.keys(data['monsters.json'].kinds).length, 60, '몬스터 60종');
  assert.equal(Object.keys(data['skills.json'].skills).length, 34, '스킬 34종');
});

test('아이템도 내보낸다 — 등급·랜덤옵션·강화를 그대로 가기로 했다 (2026-09-17)', () => {
  const items = data['items.json'].items;
  const ids = Object.keys(items);
  const materials = ids.filter((id) => items[id].material);
  assert.equal(ids.length - materials.length, 280, '장비 280종 (단계 20 x 슬롯 13~14)');
  assert.equal(materials.length, 20, '단계마다 제작 재료 하나');
  // 드롭이 후보 id 를 만들 때 쓰는 표가 같이 있어야 한다
  assert.equal(data['items.json'].slots.length, 8, '장비 슬롯 8종');
  assert.ok(data['items.json'].slotCode.weapon === 'w', '슬롯 코드');
});
