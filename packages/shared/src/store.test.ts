import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DIAMOND_PRODUCTS } from './store.ts';

test('다이아 상품 — id 가 겹치지 않고 개수는 양의 정수', () => {
  const ids = new Set(DIAMOND_PRODUCTS.map((p) => p.id));
  assert.equal(ids.size, DIAMOND_PRODUCTS.length, '상품 id 가 겹친다');
  for (const p of DIAMOND_PRODUCTS) {
    assert.ok(/^[a-z0-9_.]+$/.test(p.id), `플레이 상품 id 는 소문자·숫자·_·. 만: ${p.id}`);
    assert.ok(Number.isInteger(p.diamonds) && p.diamonds > 0, `${p.id} 다이아 ${p.diamonds}`);
  }
});
