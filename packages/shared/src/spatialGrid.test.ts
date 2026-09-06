import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SpatialGrid, AreaOfInterest, encodeCell, decodeCell } from './spatialGrid.ts';

test('셀 키 인코딩 왕복', () => {
  for (const [cx, cz] of [[0, 0], [-1, -1], [5, -7], [-32768, 32767], [32767, -32768]]) {
    assert.deepEqual(decodeCell(encodeCell(cx!, cz!)), { cx, cz });
  }
});

test('음수 좌표에서 셀 경계가 정확히 갈린다', () => {
  const g = new SpatialGrid<string>(32);
  // 절삭(truncate)으로 구현하면 -1 과 +1 이 같은 셀이 되는 고전적인 버그
  assert.notEqual(g.cellAt(-1, 0), g.cellAt(1, 0));
  assert.equal(g.cellAt(0, 0), g.cellAt(31, 31));
  assert.equal(g.cellAt(-1, -1), g.cellAt(-32, -32));
});

test('반경 질의는 셀이 아니라 실제 거리로 거른다', () => {
  const g = new SpatialGrid<string>(32);
  g.insert('a', 0, 0, 'a');
  g.insert('b', 3, 4, 'b'); // 거리 5, 같은 셀
  g.insert('c', 40, 0, 'c'); // 다른 셀
  g.insert('d', -40, -40, 'd');

  assert.equal(g.size, 4);
  assert.deepEqual(g.queryRadius(0, 0, 5).sort(), ['a', 'b']);
  assert.deepEqual(g.queryRadius(0, 0, 4), ['a']);
  assert.equal(g.queryRadius(0, 0, 60).length, 4);
});

test('셀을 넘나드는 이동', () => {
  const g = new SpatialGrid<string>(32);
  g.insert('a', 0, 0, 'a');
  g.insert('b', 3, 4, 'b');

  assert.equal(g.move('a', 1, 1), false, '같은 셀 안 이동은 재구독이 필요 없다');
  assert.equal(g.move('a', 100, 100), true, '셀이 바뀌면 AoI 재계산 신호');
  assert.deepEqual(g.queryRadius(0, 0, 5), ['b'], '원래 셀에서 빠져야 한다');
  assert.deepEqual(g.queryRadius(100, 100, 2), ['a']);
});

test('삭제는 멱등하다', () => {
  const g = new SpatialGrid<string>(32);
  g.insert('a', 0, 0, 'a');
  g.remove('a');
  g.remove('a');
  g.remove('없는id');
  assert.equal(g.size, 0);
  assert.deepEqual(g.queryRadius(0, 0, 10), []);
});

test('AoI: 셀 경계에서 깜빡이지 않는다 (히스테리시스)', () => {
  const g = new SpatialGrid<string>(32);
  const aoi = new AreaOfInterest(1, 2);

  const first = aoi.update(g, 0, 0);
  assert.equal(first.entered.length, 9, '3x3 구독');
  assert.equal(first.left.length, 0);

  // 경계(x=32)를 넘었다가 되돌아온다 — 실제 플레이어가 경계에 서 있는 상황
  const over = aoi.update(g, 32.5, 0);
  const back = aoi.update(g, 31.5, 0);
  assert.equal(over.entered.length, 3, '새로 보이는 열만 추가');
  assert.equal(over.left.length, 0, '해제 반경이 더 넓으므로 아직 안 버린다');
  assert.equal(back.left.length, 0, '되돌아와도 해제 없음 — 여기가 pop-in 이 생기는 지점');

  const far = aoi.update(g, 300, 300);
  assert.ok(far.left.length > 0, '충분히 멀어지면 해제된다');
  assert.equal(aoi.cells.size, 9);
});

test('200명 존에서 근접 질의가 틱 예산 안에 든다', () => {
  const g = new SpatialGrid<number>(32);
  const positions: [number, number][] = [];
  for (let i = 0; i < 200; i++) {
    const p: [number, number] = [((i * 37) % 220) - 110, ((i * 91) % 220) - 110];
    positions.push(p);
    g.insert(`p${i}`, p[0], p[1], i);
  }

  const out: number[] = [];
  const ticks = 15 * 60; // 60초 분량
  const t0 = performance.now();
  for (let t = 0; t < ticks; t++) {
    for (const [x, z] of positions) g.queryRadius(x, z, 3, out);
  }
  const perTick = (performance.now() - t0) / ticks;

  // 서버 틱 예산은 66ms(15Hz). 공간 질의가 1ms 를 넘으면 설계를 다시 봐야 한다.
  assert.ok(perTick < 1, `틱당 ${perTick.toFixed(3)}ms`);
});
