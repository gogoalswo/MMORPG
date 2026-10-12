import type { ZoneDef } from './zone.ts';
import type { MonsterKind } from './monsters.ts';
import { DUNGEON_ENV } from './dungeons.ts';

/**
 * **결투장** (2026-10-12) — 남의 캐릭터 **복사본**과 AI 끼리 싸운다. 실시간 PVP 가 아니다.
 *
 * 요청: "샌드백 때리는 것 처럼 내가 조종하는게 아니라 AI로 만들어서 서로 싸우게 할거야. 상대방 데이터는
 * 서버에서 받아서 복사해서 사용할거야" → 둘째 요청 "AI 결투 만들어".
 *
 * - 상대 목록(복사본)은 서버가 준다. 고도 `Arena.board` — 지금은 더미 50명.
 * - 들어오면 `ARENA_COUNTDOWN_SECONDS` 동안 둘 다 선다. 그 뒤 **둘 다 자동으로** 싸운다 — 나는 자동사냥,
 *   상대는 몬스터 AI(쫓기 · 휘두르기). 내 손으로는 못 걷는다.
 * - 상대가 쓰러지면 승리, 내가 쓰러지면 패배. `ARENA_SECONDS` 가 다 되면 **남은 체력 비율**이 높은 쪽이 이긴다
 *   (같으면 패배 — 도전한 쪽이 끝내야 한다).
 * - 점수는 이기면 `ARENA_WIN_SCORE` 만큼 오르고 지면 `ARENA_LOSE_SCORE` 만큼 내린다(0 아래로는 안 간다).
 *
 * → docs/features/arena.md
 */
export const ARENA_ZONE = 'arena';
export const ARENA_COUNTDOWN_SECONDS = 3;
export const ARENA_SECONDS = 60;
/** 샌드백과 같은 좁은 맵 */
export const ARENA_ZONE_SIZE = 30;
export const ARENA_START_SCORE = 1000;
export const ARENA_WIN_SCORE = 20;
export const ARENA_LOSE_SCORE = 10;

/**
 * 둘은 **붙어서 마주 선 채 시작한다** — 샌드백 자리(sandbag.ts `SANDBAG_PLAYER_SPOT` · `SANDBAG_SPOT`)와 같다.
 * 카메라가 남동쪽 45° 에서 보므로 화면에서 좌우로 나란히다. 가운데 거리 1.8m 는 격투가 사거리(2.2)보다 짧아
 * 둘 다 걷지 않고 바로 친다 (2026-10-12 요청 "샌드백처럼 서로 붙어있는 상태에서 시작하도록". 처음엔 7m 떨어져
 * 날라차기로 붙었다)
 */
export const ARENA_PLAYER_SPOT: [number, number] = [-0.64, 0.64];
export const ARENA_FOE_SPOT: [number, number] = [0.64, -0.64];

/**
 * 상대의 틀 — 수치(체력 · 공격력 · 방어력 · 치명타 · 공속)는 **복사본의 장부로** 고도 `Arena.foe` 가 덮어쓴다.
 * 여기 값은 모양 · 움직임만이다. 몬스터 표(`MONSTER_KINDS`)에는 넣지 않는다 (샌드백과 같은 까닭)
 */
export const ARENA_FOE_KIND: MonsterKind = {
  id: 'duelist',
  name: '결투 상대',
  level: 1,
  maxHp: 1,
  attack: 0,
  defense: 0,
  critResist: 0,
  // 격투가 사거리 (combat.ts `JOB_STATS.fighter`) — 복사본 직업의 사거리로 덮어쓴다
  attackRange: 2.2,
  attackCooldown: 700,
  // 맵 어디에 있든 나를 찾고, 맵 끝까지 따라온다
  aggroRange: 99,
  leashRange: 99,
  // 캐릭터 달리기 속도 (constants `runSpeed`)
  moveSpeed: 4.6,
  expReward: 0,
  // 내 캐릭터와 같은 모델 — 키는 beasts.ts `BEAST_HEIGHT.varco_fighter`
  look: 'varco_fighter',
  bodyColor: '#c9a26b',
  accentColor: '#5a4630',
  scale: 1,
  duel: true,
};

export const ARENA_ZONE_DEF: ZoneDef = {
  id: ARENA_ZONE,
  name: '결투장',
  size: ARENA_ZONE_SIZE,
  spawns: { default: ARENA_PLAYER_SPOT },
  // 상대는 표가 아니라 도전할 때 고도 `World._start_duel` 이 세운다
  env: DUNGEON_ENV,
};

/** 결과 뒤 점수 — 0 아래로는 안 간다. 고도 `Arena.next_score` 와 같은 식이다 */
export function arenaNextScore(score: number, won: boolean): number {
  return Math.max(0, score + (won ? ARENA_WIN_SCORE : -ARENA_LOSE_SCORE));
}
