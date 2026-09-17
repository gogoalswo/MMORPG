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

test('아이템은 내보내지 않는다 (나중에 다시 만든다)', () => {
  const names = Object.keys(data);
  assert.ok(!names.some((n) => n.includes('item')), `아이템 파일이 생겼다: ${names}`);
});
