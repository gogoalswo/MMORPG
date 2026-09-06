import type { ZoneDef, ZoneEnv } from './zone.ts';
import { bossIdFor, monsterIdFor, tierLevels } from './monsters.ts';

/**
 * 존 배치.
 *
 *   마을
 *    │
 *   초원(1-10) ─ 덤불숲(10-20) ─ 협곡(20-30) ─ 잿빛황야(30-40) ─ … ─ 종말의 대지(190-200)
 *    │                                            │
 *    └────────────── 지름길 ──────────────────────┘
 *
 * 사냥터 20개가 사슬로 이어지고, 마을은 첫 사냥터에만 붙는다.
 * 초원 ↔ 잿빛 황야 지름길 하나는 처음 그린 배치도를 그대로 남긴 것이다 —
 * 저레벨이 30레벨대로 바로 넘어갈 수 있는 위험한 문이다.
 *
 * **표에서 만든다.** 20개를 손으로 적으면 포탈 짝이 어긋나도 조용히 지나가고,
 * "왜 엉뚱한 데서 시작하지?" 로만 나타난다. 생성 규칙은 이렇다.
 *   - 포탈은 북(0,-34) 남(0,34) 서(-34,0) 동(34,0) 에만 둔다
 *   - 사슬은 서(뒤) ↔ 동(앞) 으로만 잇는다
 *   - 도착 지점은 그 문 안쪽 8유닛이고 이름은 들어온 방향을 쓴다 (from_west 등)
 * 실제로 맞물렸는지는 `zones.test.ts` 가 전수 검사한다.
 *
 * 한 화면에 보이는 지면이 16:9 기준 약 56.5 유닛 사각형이라(FOV 30, 거리 40, 부각 42),
 * 그 1.5배가 되도록 모든 존을 size 92 (이동 가능 영역 84) 로 맞췄다.
 */

/** 이동 가능 영역이 ±42 이므로 포탈은 34, 도착 지점은 26 에 둔다 */
const PORTAL = 34;
const ARRIVE = 26;

/** 사냥터 한 곳의 겉모습 */
interface FieldTheme {
  id: string;
  name: string;
  sky: string;
  fog: string;
  grassDark: string;
  grassLight: string;
  dirt: string;
  dirtLight: string;
  /** 0 = 훤함, 1 = 캄캄함. 안개 거리와 광량, 풀 밀도를 여기서 뽑는다 */
  dim: number;
}

const FIELDS: FieldTheme[] = [
  { id: 'meadow', name: '초원', sky: '#b4c6cf', fog: '#bcc4ae', grassDark: '#54663a', grassLight: '#7c8b54', dirt: '#a08a66', dirtLight: '#b39c77', dim: 0.05 },
  { id: 'thicket', name: '덤불숲', sky: '#5f6b63', fog: '#48544a', grassDark: '#2f3a28', grassLight: '#4a5936', dirt: '#5a4f3c', dirtLight: '#6b5f49', dim: 0.55 },
  { id: 'canyon', name: '메마른 협곡', sky: '#c4b39a', fog: '#b09c7f', grassDark: '#6b6142', grassLight: '#8a7d55', dirt: '#9c8055', dirtLight: '#b09468', dim: 0.2 },
  { id: 'waste', name: '잿빛 황야', sky: '#4a4750', fog: '#3d3a42', grassDark: '#3a3740', grassLight: '#4e4a55', dirt: '#55505a', dirtLight: '#655f6c', dim: 0.7 },
  { id: 'mire', name: '안개 늪', sky: '#6d7a6a', fog: '#5b6a58', grassDark: '#37452f', grassLight: '#4d5c3d', dirt: '#4a4a38', dirtLight: '#5b5b46', dim: 0.6 },
  { id: 'frostmoor', name: '서리 고원', sky: '#c8d8e4', fog: '#aec2d2', grassDark: '#6d7f86', grassLight: '#93a6ae', dirt: '#8d9aa0', dirtLight: '#a5b1b6', dim: 0.15 },
  { id: 'blackwood', name: '검은 삼림', sky: '#39423a', fog: '#2a322b', grassDark: '#1f2a1c', grassLight: '#33422c', dirt: '#3a3328', dirtLight: '#4a4133', dim: 0.8 },
  { id: 'ruins', name: '무너진 성터', sky: '#8f8d86', fog: '#75736c', grassDark: '#4f5348', grassLight: '#6c705f', dirt: '#6f6a5c', dirtLight: '#847e6e', dim: 0.35 },
  { id: 'redsand', name: '붉은 사막', sky: '#d8b98a', fog: '#c9aa76', grassDark: '#9c7c4a', grassLight: '#bd9a63', dirt: '#c2955c', dirtLight: '#d4aa72', dim: 0.1 },
  { id: 'saltflat', name: '소금 평원', sky: '#dcdcd4', fog: '#c3c3ba', grassDark: '#9a9a8e', grassLight: '#b8b8ab', dirt: '#b5b3a4', dirtLight: '#c8c6b8', dim: 0.1 },
  { id: 'sulfur', name: '유황 분지', sky: '#a89448', fog: '#8e7c36', grassDark: '#6e6428', grassLight: '#8f8240', dirt: '#8a7530', dirtLight: '#a38c42', dim: 0.3 },
  { id: 'cinder', name: '화산재 언덕', sky: '#5a4a46', fog: '#463a37', grassDark: '#3b3230', grassLight: '#524644', dirt: '#4d3f3a', dirtLight: '#5f4e48', dim: 0.65 },
  { id: 'glacier', name: '얼어붙은 심연', sky: '#8fa6bb', fog: '#7089a0', grassDark: '#4a5f6e', grassLight: '#6b8291', dirt: '#5e6d78', dirtLight: '#77848e', dim: 0.55 },
  { id: 'warpwood', name: '뒤틀린 숲', sky: '#3f3a2c', fog: '#302c22', grassDark: '#2c2f1f', grassLight: '#42452e', dirt: '#3d3527', dirtLight: '#4d4433', dim: 0.75 },
  { id: 'shadowvale', name: '그림자 계곡', sky: '#2e2a3d', fog: '#221f2e', grassDark: '#232036', grassLight: '#332e48', dirt: '#302b3f', dirtLight: '#3f394f', dim: 0.85 },
  { id: 'deadcity', name: '폐허 도시', sky: '#7d7d80', fog: '#65656a', grassDark: '#4b4b4d', grassLight: '#666668', dirt: '#605e5c', dirtLight: '#75726f', dim: 0.45 },
  { id: 'palemoor', name: '빛바랜 고원', sky: '#cfd2cf', fog: '#b3b7b4', grassDark: '#7f857c', grassLight: '#9ba296', dirt: '#98978c', dirtLight: '#adaa9f', dim: 0.2 },
  { id: 'rift', name: '균열 지대', sky: '#4a3358', fog: '#392846', grassDark: '#332a3d', grassLight: '#473a52', dirt: '#413349', dirtLight: '#523f5c', dim: 0.75 },
  { id: 'abyssgate', name: '심연의 문턱', sky: '#25303c', fog: '#1c252f', grassDark: '#1e2730', grassLight: '#2c3846', dirt: '#28303a', dirtLight: '#333d48', dim: 0.9 },
  { id: 'endland', name: '종말의 대지', sky: '#2e1d22', fog: '#241619', grassDark: '#26191d', grassLight: '#37232a', dirt: '#301f24', dirtLight: '#3d282e', dim: 0.95 },
];

/** 포탈 빛 색을 돌려 쓴다 — 인접한 존끼리 색이 겹치지 않게만 하면 된다 */
const PORTAL_COLORS = ['#7fd8ff', '#9ae67f', '#ffd18a', '#e6795f', '#c9a0ff', '#8affd1'];

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** 어둠도 하나에서 안개·광량·풀 밀도를 만든다 */
function envFor(theme: FieldTheme): ZoneEnv {
  const d = theme.dim;
  return {
    skyColor: theme.sky,
    fogColor: theme.fog,
    // 캄캄할수록 안개를 바짝 당겨 답답하게 만든다
    fogNear: Math.round(lerp(70, 24, d)),
    fogFar: Math.round(lerp(190, 90, d)),
    sunIntensity: Math.round(lerp(2.7, 0.9, d) * 100) / 100,
    hemiIntensity: Math.round(lerp(1.1, 0.55, d) * 100) / 100,

    grassDark: theme.grassDark,
    grassLight: theme.grassLight,
    dirt: theme.dirt,
    dirtLight: theme.dirtLight,

    grassCount: Math.round(lerp(58000, 20000, d)),
    grassRadius: 42,

    roads: [
      { axis: 'x', offset: 0, width: 5.2, wave: 7, waveFreq: 0.05 },
      { axis: 'z', offset: 0, width: 4.4, wave: 8, waveFreq: 0.06 },
    ],
  };
}

/**
 * 보스 자리 — 시계로 7시 방향, 중앙에서 24유닛.
 *
 * 12시를 -z(북)로 놓고 시계방향으로 잰다. 포탈(±34)과 도착 지점(±26)에서
 * 충분히 떨어져 있어 지나가다 얻어걸리지 않는다.
 */
const BOSS_SPOT: [number, number] = [-12.0, 20.8];

/** 무리를 놓을 자리 — 포탈과 도착 지점을 피해 네 귀퉁이에 둔다 */
const PACKS: [number, number][] = [
  [-20, -20],
  [20, -20],
  [-20, 20],
  [20, 20],
];

function buildField(theme: FieldTheme, index: number): ZoneDef {
  const [weak, strong] = tierLevels(index);
  const last = index === FIELDS.length - 1;

  const spawns: Record<string, [number, number]> = { default: [0, 0] };
  const portals: ZoneDef['portals'] = [];

  // 뒤로 — 첫 사냥터만 마을(북쪽)이고 나머지는 이전 사냥터(서쪽)
  if (index === 0) {
    spawns.from_north = [0, -ARRIVE];
    portals.push({
      id: 'to_village',
      position: [0, -PORTAL],
      radius: 2.4,
      color: '#ffd18a',
      target: { zone: 'village', spawn: 'from_south' },
    });
  } else {
    spawns.from_west = [-ARRIVE, 0];
    portals.push({
      id: 'to_' + FIELDS[index - 1]!.id,
      position: [-PORTAL, 0],
      radius: 2.4,
      color: PORTAL_COLORS[index % PORTAL_COLORS.length]!,
      target: { zone: FIELDS[index - 1]!.id, spawn: 'from_east' },
    });
  }

  // 앞으로 — 마지막 사냥터는 막다른 길
  if (!last) {
    spawns.from_east = [ARRIVE, 0];
    portals.push({
      id: 'to_' + FIELDS[index + 1]!.id,
      position: [PORTAL, 0],
      radius: 2.4,
      color: PORTAL_COLORS[(index + 1) % PORTAL_COLORS.length]!,
      target: { zone: FIELDS[index + 1]!.id, spawn: 'from_west' },
    });
  }

  // 처음 그린 배치도의 지름길: 초원 ↔ 잿빛 황야
  if (index === SHORTCUT_FROM) {
    spawns.from_south = [0, ARRIVE];
    portals.push({
      id: 'to_' + FIELDS[SHORTCUT_TO]!.id,
      position: [0, PORTAL],
      radius: 2.4,
      color: '#e6795f',
      target: { zone: FIELDS[SHORTCUT_TO]!.id, spawn: 'from_north' },
    });
  }
  if (index === SHORTCUT_TO) {
    spawns.from_north = [0, -ARRIVE];
    portals.push({
      id: 'to_' + FIELDS[SHORTCUT_FROM]!.id,
      position: [0, -PORTAL],
      radius: 2.4,
      color: '#7fd8ff',
      target: { zone: FIELDS[SHORTCUT_FROM]!.id, spawn: 'from_south' },
    });
  }

  return {
    id: theme.id,
    name: theme.name,
    size: 92,
    spawns,
    portals,
    monsters: [
      // 보스는 사냥터마다 한 마리, 7시 방향에 선다. 15분에 한 번 나온다.
      { kind: bossIdFor(index), x: BOSS_SPOT[0], z: BOSS_SPOT[1], radius: 3, count: 1, respawnMs: 900000 },
      { kind: monsterIdFor(weak), x: PACKS[0]![0], z: PACKS[0]![1], radius: 8, count: 4, respawnMs: 20000 },
      { kind: monsterIdFor(weak), x: PACKS[1]![0], z: PACKS[1]![1], radius: 8, count: 3, respawnMs: 20000 },
      { kind: monsterIdFor(strong), x: PACKS[2]![0], z: PACKS[2]![1], radius: 8, count: 3, respawnMs: 26000 },
      { kind: monsterIdFor(strong), x: PACKS[3]![0], z: PACKS[3]![1], radius: 8, count: 3, respawnMs: 26000 },
    ],
    env: envFor(theme),
  };
}

/** 지름길 양끝 (배치도의 1-10 ↔ 30-40) */
const SHORTCUT_FROM = 0;
const SHORTCUT_TO = 3;

/** 마을 — 몬스터가 없는 시작 지점 */
const VILLAGE: ZoneDef = {
  id: 'village',
  name: '마을',
  size: 92,
  spawns: {
    default: [0, 0],
    // 포탈 위에 그대로 떨어뜨리면 즉시 되돌아가므로 안쪽에 놓는다
    from_south: [0, ARRIVE],
  },
  portals: [
    {
      id: 'to_meadow',
      position: [0, PORTAL],
      radius: 2.4,
      color: '#7fd8ff',
      target: { zone: 'meadow', spawn: 'from_north' },
    },
  ],
  // 사냥터를 골라 바로 가는 문. 스폰에서 동쪽으로 9유닛 — NPC 여섯이 전부
  // 서쪽·남쪽에 몰려 있어 이쪽이 비어 있고, 걸어 나가는 길목이라 눈에 띈다.
  gate: {
    position: [9, 0],
    radius: 2.6,
    // 사슬 포탈과 색이 겹치면 "저기로 가면 초원" 이라는 학습을 흔든다
    color: '#c9a6ff',
    name: '차원문',
  },
  npcs: [
    // 말을 걸 수 있는 세 사람. 스폰 지점에서 걸어서 바로 닿는 거리에 둔다.
    { name: '상인 보리스', job: 'mage', look: 'merchant', x: -7, z: 4, role: 'shop', title: '상점' },
    { name: '대장장이 군터', job: 'knight', look: 'smith', x: 0, z: 6.5, role: 'smith', title: '대장간' },

    // 배경에 서 있는 마을 사람. 전부 다르게 생겨야 마을로 보인다.
    { name: '아네트', job: 'knight', look: 'villager_sack', x: -8.7, z: -1.3 },
    { name: '요한', job: 'mage', look: 'villager_apron', x: -6.2, z: -3.8, hp: 72 },
    { name: '릴리', job: 'archer', look: 'villager_hood', x: -3.8, z: -6.2 },
    { name: '노인 하르트', job: 'archer', look: 'villager_old', x: -9, z: -12 },
  ],
  env: {
    skyColor: '#b9c9d8',
    fogColor: '#c2c8b8',
    fogNear: 70,
    fogFar: 190,
    sunIntensity: 2.7,
    hemiIntensity: 1.1,

    grassDark: '#5c6a3c',
    grassLight: '#82905a',
    dirt: '#a8916c',
    dirtLight: '#b9a37e',

    grassCount: 60000,
    grassRadius: 44,

    roads: [
      { axis: 'z', offset: 8, width: 4.6, wave: 9, waveFreq: 0.055 },
      { axis: 'x', offset: -14, width: 3.6, wave: 6, waveFreq: 0.045 },
    ],
  },
};

export const ZONES: Record<string, ZoneDef> = {
  [VILLAGE.id]: VILLAGE,
  ...Object.fromEntries(FIELDS.map((theme, i) => [theme.id, buildField(theme, i)])),
};

export const START_ZONE = VILLAGE.id;

/** 사냥터 순서 — 레벨대 순으로 나열한다 (UI 나 문서용) */
export const FIELD_ORDER: string[] = FIELDS.map((f) => f.id);

/**
 * 저장된 존 이름을 실재하는 존으로 되돌린다.
 *
 * 존을 지우거나 이름을 바꾸면 DB·localStorage 에는 옛 이름이 남는다.
 * 그대로 두면 접속하자마자 getZone 이 던져서 캐릭터가 영영 못 들어온다.
 */
export function resolveZoneId(id: string | null | undefined): string {
  return id && id in ZONES ? id : START_ZONE;
}

export function getZone(id: string): ZoneDef {
  const zone = ZONES[id];
  if (!zone) throw new Error('알 수 없는 존: ' + id);
  return zone;
}

/** 스폰 지점 조회. 없는 이름이면 default 로 떨어뜨린다 (링크 오타로 게임이 멈추지 않게) */
export function getSpawn(zone: ZoneDef, name: string): [number, number] {
  return zone.spawns[name] ?? zone.spawns.default ?? [0, 0];
}
