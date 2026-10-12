import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ARENA_FOE_KIND,
  ARENA_FOE_SPOT,
  ARENA_LOSE_SCORE,
  ARENA_PLAYER_SPOT,
  ARENA_START_SCORE,
  ARENA_WIN_SCORE,
  ARENA_ZONE,
  arenaNextScore,
} from './arena.ts';
import { ZONES } from './zones.ts';
import { MONSTER_KINDS } from './monsters.ts';

test('결투장 존 — 표에 몬스터가 없다 (상대는 도전할 때 세운다)', () => {
  const zone = ZONES[ARENA_ZONE];
  assert.ok(zone, '존이 없다');
  assert.equal(zone.monsters, undefined);
  assert.equal(MONSTER_KINDS[ARENA_FOE_KIND.id], undefined, '몬스터 표(60종)에는 없다');
  assert.equal(ARENA_FOE_KIND.duel, true);
});

test('둘은 맵 안에서 떨어져 선다 — 날라차기 거리(4 ~ 10m)', () => {
  const gap = Math.hypot(ARENA_FOE_SPOT[0] - ARENA_PLAYER_SPOT[0], ARENA_FOE_SPOT[1] - ARENA_PLAYER_SPOT[1]);
  assert.ok(gap >= 4 && gap <= 10, `거리 ${gap}`);
});

test('점수 — 이기면 오르고 지면 내리고 0 아래로는 안 간다', () => {
  assert.equal(arenaNextScore(ARENA_START_SCORE, true), ARENA_START_SCORE + ARENA_WIN_SCORE);
  assert.equal(arenaNextScore(ARENA_START_SCORE, false), ARENA_START_SCORE - ARENA_LOSE_SCORE);
  assert.equal(arenaNextScore(3, false), 0);
});
