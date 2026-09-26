import type { GroundKind, ZoneDef, ZoneEnv } from './zone.ts';
import { bossIdFor, monsterIdFor, tierLevels } from './monsters.ts';
import { dungeonZones } from './dungeons.ts';
import { jobAdvanceZones } from './jobAdvance.ts';

/**
 * 존 배치.
 *
 *   마을 ─┐
 *          ├─ 차원문 ─┬─ 초원(1-10)
 *   사냥터 ┘          ├─ 덤불숲(10-20)
 *                     ├─ …
 *                     └─ 종말의 대지(190-200)
 *
 * **존끼리는 이어져 있지 않다.** 걸어 들어가면 곧장 옆 존으로 넘어가던 사슬
 * 포탈은 전부 없앴다. 지금은 어느 존에서든 차원문 하나를 밟고 목적지를 고른다.
 *
 * 그래서 **모든 존에 차원문이 있어야 한다.** 하나라도 빠지면 그 존은 들어가면
 * 못 나오는 방이 된다 — 예외가 나지 않고 "여기서 어떻게 나가지?" 로만 나타나서
 * `zones.test.ts` 가 전수 검사한다.
 *
 * **표에서 만든다.** 20개를 손으로 적으면 한 곳만 빠져도 조용히 지나간다.
 *
 * 모든 존을 size 66 (이동 가능 영역 58) 로 맞췄다. 원래 92 — 한 화면에 보이는 지면
 * (16:9 기준 약 56.5 유닛, FOV 30 · 거리 40 · 부각 42)의 1.5배 — 였는데 "맵이 너무
 * 크다" 해서 2/3 로 줄였다 (2026-09-23). 이제 맵이 한 화면과 거의 같다.
 */

/**
 * 차원문 자리 — 모든 존에서 같다.
 *
 * 도착 지점(맵 한가운데)에서 동쪽으로 4유닛. 어느 존에 가도 같은 자리에 있어야
 * "나가려면 어디로 가야 하나"를 존마다 다시 찾지 않는다. 스폰을 덮지 않을 만큼
 * 떨어져 있고(반경 2.6), 무리(±16, 반경 13) 가장자리에서 7m 떨어져 있다.
 * 원래 9 였는데 맵을 2/3 로 줄이며 무리가 ±14 로 당겨져 9 에서는 동쪽 두 무리
 * 가장자리와 문이 겹쳐 4 로 당겼다. 무리를 ±16 으로 다시 민 뒤(2026-09-23 "포탈이랑
 * 너무 가깝다")에도 4 에 둔다 — 문과 몬스터 사이를 벌리려고 민 것이라서다.
 * 마을은 NPC 여섯이 전부 서쪽·남쪽에 몰려 있어 이쪽이 비어 있기도 하다.
 */
const GATE_SPOT: [number, number] = [4, 0];

/**
 * 차원문 빛 색과 이름.
 *
 * 파란색 하나로 통일한다. 문이 하나뿐이니 색으로 구분할 상대가 없고, 존마다
 * 색이 다르면 "저건 다른 문인가" 하고 다시 확인하게 된다.
 */
const GATE_COLOR = '#4aa8ff';
const GATE_NAME = '사냥터 이동';

const gateFor = (): ZoneDef['gate'] => ({
  position: [GATE_SPOT[0], GATE_SPOT[1]],
  radius: 2.6,
  color: GATE_COLOR,
  name: GATE_NAME,
});

/** 사냥터 한 곳의 겉모습 */
interface FieldTheme {
  id: string;
  name: string;
  /** 바닥 텍스처. 돌판(stone)은 마을 몫이라 사냥터는 나머지 여섯을 나눠 쓴다 */
  ground: GroundKind;
  sky: string;
  grassDark: string;
  grassLight: string;
  /** 풀밭이 아닌 바닥의 틴트, 그리고 풀밭에 난 흙길의 틴트 */
  dirtLight: string;
  /** 0 = 훤함, 1 = 캄캄함. 안개 거리와 광량, 풀 밀도를 여기서 뽑는다 */
  dim: number;
}

const FIELDS: FieldTheme[] = [
  { id: 'meadow', name: '초원', ground: 'grass', sky: '#b4c6cf', grassDark: '#54663a', grassLight: '#7c8b54', dirtLight: '#b39c77', dim: 0.05 },
  { id: 'thicket', name: '덤불숲', ground: 'grass', sky: '#5f6b63', grassDark: '#2f3a28', grassLight: '#4a5936', dirtLight: '#6b5f49', dim: 0.55 },
  { id: 'canyon', name: '메마른 협곡', ground: 'dirt', sky: '#c4b39a', grassDark: '#6b6142', grassLight: '#8a7d55', dirtLight: '#b09468', dim: 0.2 },
  { id: 'waste', name: '잿빛 황야', ground: 'dirt', sky: '#4a4750', grassDark: '#3a3740', grassLight: '#4e4a55', dirtLight: '#655f6c', dim: 0.7 },
  { id: 'mire', name: '안개 늪', ground: 'grass', sky: '#6d7a6a', grassDark: '#37452f', grassLight: '#4d5c3d', dirtLight: '#5b5b46', dim: 0.6 },
  { id: 'frostmoor', name: '서리 고원', ground: 'snow', sky: '#c8d8e4', grassDark: '#6d7f86', grassLight: '#93a6ae', dirtLight: '#a5b1b6', dim: 0.15 },
  { id: 'blackwood', name: '검은 삼림', ground: 'grass', sky: '#39423a', grassDark: '#1f2a1c', grassLight: '#33422c', dirtLight: '#4a4133', dim: 0.8 },
  { id: 'ruins', name: '무너진 성터', ground: 'cobble', sky: '#8f8d86', grassDark: '#4f5348', grassLight: '#6c705f', dirtLight: '#847e6e', dim: 0.35 },
  { id: 'redsand', name: '붉은 사막', ground: 'sand', sky: '#d8b98a', grassDark: '#9c7c4a', grassLight: '#bd9a63', dirtLight: '#d4aa72', dim: 0.1 },
  // 금 간 마른 땅을 하얗게 물들이면 소금 평원이 된다
  { id: 'saltflat', name: '소금 평원', ground: 'dirt', sky: '#dcdcd4', grassDark: '#9a9a8e', grassLight: '#b8b8ab', dirtLight: '#c8c6b8', dim: 0.1 },
  { id: 'sulfur', name: '유황 분지', ground: 'sand', sky: '#a89448', grassDark: '#6e6428', grassLight: '#8f8240', dirtLight: '#a38c42', dim: 0.3 },
  { id: 'cinder', name: '화산재 언덕', ground: 'lava', sky: '#5a4a46', grassDark: '#3b3230', grassLight: '#524644', dirtLight: '#5f4e48', dim: 0.65 },
  { id: 'glacier', name: '얼어붙은 심연', ground: 'snow', sky: '#8fa6bb', grassDark: '#4a5f6e', grassLight: '#6b8291', dirtLight: '#77848e', dim: 0.55 },
  { id: 'warpwood', name: '뒤틀린 숲', ground: 'grass', sky: '#3f3a2c', grassDark: '#2c2f1f', grassLight: '#42452e', dirtLight: '#4d4433', dim: 0.75 },
  { id: 'shadowvale', name: '그림자 계곡', ground: 'dirt', sky: '#2e2a3d', grassDark: '#232036', grassLight: '#332e48', dirtLight: '#3f394f', dim: 0.85 },
  { id: 'deadcity', name: '폐허 도시', ground: 'cobble', sky: '#7d7d80', grassDark: '#4b4b4d', grassLight: '#666668', dirtLight: '#75726f', dim: 0.45 },
  { id: 'palemoor', name: '빛바랜 고원', ground: 'grass', sky: '#cfd2cf', grassDark: '#7f857c', grassLight: '#9ba296', dirtLight: '#adaa9f', dim: 0.2 },
  { id: 'rift', name: '균열 지대', ground: 'lava', sky: '#4a3358', grassDark: '#332a3d', grassLight: '#473a52', dirtLight: '#523f5c', dim: 0.75 },
  { id: 'abyssgate', name: '심연의 문턱', ground: 'cobble', sky: '#25303c', grassDark: '#1e2730', grassLight: '#2c3846', dirtLight: '#333d48', dim: 0.9 },
  { id: 'endland', name: '종말의 대지', ground: 'lava', sky: '#2e1d22', grassDark: '#26191d', grassLight: '#37232a', dirtLight: '#3d282e', dim: 0.95 },
];

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** 어둠도 하나에서 광량을 만든다 */
function envFor(theme: FieldTheme): ZoneEnv {
  const d = theme.dim;
  return {
    skyColor: theme.sky,
    sunIntensity: Math.round(lerp(2.7, 0.9, d) * 100) / 100,
    hemiIntensity: Math.round(lerp(1.1, 0.55, d) * 100) / 100,

    grassDark: theme.grassDark,
    grassLight: theme.grassLight,

    // 바닥은 이미지 한 장뿐이다. 풀 잎·길은 없다.
    ground: theme.ground,
    // 풀밭은 풀색 칸, 나머지 바닥은 흙색 칸으로 물들인다
    groundTint: theme.ground === 'grass' ? theme.grassLight : theme.dirtLight,
  };
}

/**
 * 보스 자리 — 시계로 6시 방향, 중앙에서 23유닛.
 *
 * 12시를 -z(북)로 놓고 시계방향으로 잰다. 원래 7시·24유닛이었는데 맵을 줄이며
 * 무리가 네 귀퉁이(±16, 반경 13)를 거의 다 덮어, 무리 원 밖으로 남는 자리가
 * 두 무리 사이 축 위뿐이다. 남쪽 두 무리 원(반경 13)과 보스 원(반경 3)이 안 닿고
 * (중심 간 17.5) 벽(29) 안에 든다.
 */
const BOSS_SPOT: [number, number] = [0, 23];

/**
 * 무리 하나의 마릿수와 반경.
 *
 * 밸런스 설계(`docs/features/stat-balance.md`)의 단위가 **한 그룹 50마리**다 —
 * 범위 스킬로 그 50마리를 15초에 정리하고 HP 50% 를 잃는 것이 전 구간의 기준이다.
 * 그래서 무리 하나를 50마리로 놓는다. 존 하나 = 사냥터 하나에 무리 넷 + 보스 하나.
 *
 * 반경 8 에 50마리를 넣으면 `scatterSpawn` 이 빈 자리를 못 찾는다. 한 마리가
 * 차지하는 넓이가 같으려면 반경이 √(50/20) = 1.58 배라야 한다 → 8 × 1.58 ≈ 13.
 * 네 귀퉁이 간격이 32 라 반경 13 끼리는 6m 떨어져 있다.
 */
const PACK_COUNT = 50;
const PACK_RADIUS = 13;

/**
 * 무리를 놓을 자리 — 도착 지점과 차원문을 피해 네 귀퉁이에 둔다.
 *
 * ±28 → ±14 로 당겼다가(2026-09-23, 맵 2/3) "포탈이랑 너무 가깝다" 해서 ±16 으로
 * 다시 밀고, 그만큼 맵을 62 → 66 으로 키웠다 (같은 날, 사용자 선택). 반경 13 ·
 * 50마리는 그대로라 무리 바깥 끝이 16 + 13 = 29 로 **이동 가능 영역 끝(±29)에 딱
 * 닿는다.** 더 밀려면 맵을 또 키워야 한다. 그 대가로 전에 지키던 두 가지를 놓았다.
 *
 * 1. 도착 지점(0,0)이 무리의 **반경 + 인식 범위** 밖이 아니다 — 중심까지 22.6 이라
 *    인식 범위(최대 16)가 닿는다. 사냥터에 들어서면 몬스터가 달려온다.
 * 2. 자동 사냥 반경(`world.gd` 의 `HUNT_RADIUS` 27)이 옆 무리까지 닿는다 — 무리 간격이
 *    32 라 "무리 하나는 통째로(≥26) · 옆 무리는 안" 을 동시에 만족하는 반경이 없다.
 *
 * `zones.test.ts` 가 "무리가 영역 안" 과 "도착 지점이 무리 원 안은 아니다" 를 잡는다.
 */
const PACKS: [number, number][] = [
  [-16, -16],
  [16, -16],
  [-16, 16],
  [16, 16],
];

function buildField(theme: FieldTheme, index: number): ZoneDef {
  const [weak, strong] = tierLevels(index);

  // 도착 지점은 맵 한가운데 하나뿐이다. 사슬 포탈이 없어졌으니 "어느 문으로
  // 들어왔나"를 따질 일이 없고, 이름 붙은 스폰(from_west 등)도 같이 사라졌다.
  return {
    id: theme.id,
    name: theme.name,
    size: 66,
    spawns: { default: [0, 0] },
    gate: gateFor(),
    monsters: [
      // 보스는 사냥터마다 한 마리, 6시 방향에 선다. 15분에 한 번 나온다.
      { kind: bossIdFor(index), x: BOSS_SPOT[0], z: BOSS_SPOT[1], radius: 3, count: 1, respawnMs: 900000 },
      { kind: monsterIdFor(weak), x: PACKS[0]![0], z: PACKS[0]![1], radius: PACK_RADIUS, count: PACK_COUNT, respawnMs: 10000 },
      { kind: monsterIdFor(weak), x: PACKS[1]![0], z: PACKS[1]![1], radius: PACK_RADIUS, count: PACK_COUNT, respawnMs: 10000 },
      { kind: monsterIdFor(strong), x: PACKS[2]![0], z: PACKS[2]![1], radius: PACK_RADIUS, count: PACK_COUNT, respawnMs: 10000 },
      { kind: monsterIdFor(strong), x: PACKS[3]![0], z: PACKS[3]![1], radius: PACK_RADIUS, count: PACK_COUNT, respawnMs: 10000 },
    ],
    env: envFor(theme),
  };
}

/** 마을 — 몬스터가 없는 시작 지점 */
const VILLAGE: ZoneDef = {
  id: 'village',
  name: '마을',
  size: 66,
  spawns: { default: [0, 0] },
  // 사냥터로 나가는 유일한 문. 사냥터에 선 것과 같은 자리·같은 색이다.
  gate: gateFor(),
  // **전직관 한 명만 선다** (2026-09-26 요청: "마을에 불필요한 NPC들은 제거해. 지금은 전직
  // 교관만 있으면 되겠어"). 상인·대장장이·마을 사람 넷을 뺐다. 상점·대장간 판정(`World`)과
  // 창(`NpcPanel`), 모델(`merchant`·`smith`·`villager_*`)은 남아 있다 — 줄만 되살리면 선다
  // → docs/features/npc-town.md
  npcs: [
    // 전직 — 차원문(4, 0) 뒤쪽. 닿는 거리(4.5) 끝에 서도 문(2.6) 밖이다.
    // 누르면 다음 전직 버튼이 뜨고, 레벨이 되면 시험(보스)으로 보낸다 (jobAdvance.ts)
    { name: '전직관 레온', job: 'fighter', look: 'trainer', x: 7, z: 7, role: 'jobs', title: '전직' },
  ],
  env: {
    skyColor: '#b9c9d8',
    sunIntensity: 2.7,
    hemiIntensity: 1.1,

    grassDark: '#5c6a3c',
    grassLight: '#82905a',

    // 돌판 한 장만 깐다
    ground: 'stone',
    groundTint: '#6a665c',
  },
};

export const ZONES: Record<string, ZoneDef> = {
  [VILLAGE.id]: VILLAGE,
  ...Object.fromEntries(FIELDS.map((theme, i) => [theme.id, buildField(theme, i)])),
  // 던전 단계마다 존 하나 — 차원문 목록에는 없고 던전 창으로만 간다 (dungeons.ts)
  ...Object.fromEntries(dungeonZones(gateFor).map((zone) => [zone.id, zone])),
  // 전직 시험마다 존 하나 — 전직 NPC 로만 간다 (jobAdvance.ts)
  ...Object.fromEntries(jobAdvanceZones(gateFor).map((zone) => [zone.id, zone])),
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
