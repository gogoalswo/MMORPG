import type { ZoneDef } from './zone.ts';
import type { MonsterKind } from './monsters.ts';
import { DUNGEON_ENV } from './dungeons.ts';

/**
 * **샌드백 랭킹전** (2026-10-02) — 누가 더 센 피해를 넣는지 겨룬다.
 *
 * 요청: "맵 입장하면 캐릭터와 샌드백이 나란히 서 있고, 3초 카운트를 세. 그리고 15초 동안 얼마만큼
 * 데미지를 입히는지 누적해서 랭킹에 따라 보상을 지급할거야." 입장은 HUD 단추, 정산은 매주,
 * 보상은 3차 옵션 재료 **옐로우 크리스탈**(items.ts `YELLOW_CRYSTAL_ID`) — 사용자가 골랐다.
 *
 * - 샌드백은 **안 죽고 안 움직이고 안 때린다.** 방어력·치명타 저항이 0 이라 누구나 같은 과녁을 친다.
 * - 들어오면 `SANDBAG_COUNTDOWN_SECONDS` 동안 공격이 막히고, 그 뒤 `SANDBAG_SECONDS` 동안 넣은 피해를 더한다.
 * - 랭킹에 오르는 값은 **그 주의 최고 기록 한 판**이다. 입장 횟수는 묶지 않는다.
 * - 주는 **월요일 0시(한국 시각)** 에 바뀐다. 바뀌면 지난주 순위로 `SANDBAG_REWARDS` 만큼 준다.
 *
 * → docs/features/sandbag.md
 */
export const SANDBAG_ZONE = 'sandbag';
export const SANDBAG_COUNTDOWN_SECONDS = 3;
export const SANDBAG_SECONDS = 15;
/** 이번 주 순위를 다시 세는 간격(초). 그 사이 낸 기록은 다음 갱신에 순위에 잡힌다 (2026-10-02 요청 "1분마다") */
export const SANDBAG_RANK_REFRESH_SECONDS = 60;
/** 시련의 탑과 같은 좁은 맵 — 둘만 서 있으면 된다 */
export const SANDBAG_ZONE_SIZE = 30;

/**
 * 캐릭터와 샌드백이 **화면에서 나란히** 선다. 카메라가 남동쪽 45° 에서 보므로(`CameraRig.YAW`)
 * 화면 오른쪽이 +x·-z 대각선이다 — 캐릭터는 왼쪽, 샌드백은 오른쪽. 가운데 거리 1.8m 는
 * 격투가 사거리(2.2)보다 짧아 걷지 않고 바로 친다
 */
export const SANDBAG_PLAYER_SPOT: [number, number] = [-0.64, 0.64];
export const SANDBAG_SPOT: [number, number] = [0.64, -0.64];

/** 샌드백 — 몬스터 표(`MONSTER_KINDS`, 60종)에는 넣지 않는다. 레벨·드랍·경험치 검사가 다 걸려서다 */
export const SANDBAG_KIND: MonsterKind = {
  id: 'sandbag',
  name: '샌드백',
  level: 1,
  // 피해를 받아도 체력이 줄지 않는다 (`World._hit_monster`). 막대가 가득 찬 채로 보이도록 둔 값이다
  maxHp: 1_000_000_000,
  attack: 0,
  defense: 0,
  critResist: 0,
  attackRange: 0,
  attackCooldown: 999_999,
  aggroRange: 0,
  leashRange: 0,
  moveSpeed: 0,
  expReward: 0,
  look: 'sandbag',
  bodyColor: '#8a6a44',
  accentColor: '#4a3a2a',
  scale: 1.3,
  dummy: true,
};

export const SANDBAG_ZONE_DEF: ZoneDef = {
  id: SANDBAG_ZONE,
  name: '샌드백 랭킹전',
  size: SANDBAG_ZONE_SIZE,
  spawns: { default: SANDBAG_PLAYER_SPOT },
  monsters: [{ kind: SANDBAG_KIND.id, x: SANDBAG_SPOT[0], z: SANDBAG_SPOT[1], radius: 0, count: 1, respawnMs: 900_000 }],
  env: DUNGEON_ENV,
};

/**
 * 주간 순위 보상 — 옐로우 크리스탈 개수. `to` 까지가 그 줄이다 (마지막 줄은 끝이 없다 = 참가 보상).
 * 2026-10-02 에 제안한 값이다 — 손볼 곳은 이 표 하나다
 */
export const SANDBAG_REWARDS: { from: number; to: number | null; yellowCrystals: number }[] = [
  { from: 1, to: 1, yellowCrystals: 30 },
  { from: 2, to: 2, yellowCrystals: 25 },
  { from: 3, to: 3, yellowCrystals: 20 },
  { from: 4, to: 10, yellowCrystals: 15 },
  { from: 11, to: 50, yellowCrystals: 10 },
  { from: 51, to: 100, yellowCrystals: 5 },
  { from: 101, to: null, yellowCrystals: 2 },
];

export function sandbagReward(rank: number): number {
  if (rank < 1) return 0;
  const row = SANDBAG_REWARDS.find((r) => rank >= r.from && (r.to === null || rank <= r.to));
  return row?.yellowCrystals ?? 0;
}

/**
 * 주 번호 — **월요일 0시(한국 시각, UTC+9)** 에 하나 오른다. 1970-01-01 은 목요일이라 사흘을 더한다.
 * 고도도 같은 식이다 (`Sandbag.week`) — `sandbag.test.ts` 가 경계를 박아 둔다
 */
export const SANDBAG_WEEK_SHIFT_SECONDS = 9 * 3600 + 3 * 86400;
export const WEEK_SECONDS = 7 * 86400;

export function sandbagWeek(unixSeconds: number): number {
  return Math.floor((unixSeconds + SANDBAG_WEEK_SHIFT_SECONDS) / WEEK_SECONDS);
}
