import { ZONE_SIZE, type GateDef, type GroundKind, type ZoneDef, type ZoneEnv } from './zone.ts';
import { monsterIdFor, tierLevels } from './monsters.ts';
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
 * 모든 존을 `ZONE_SIZE` 66 (이동 가능 영역 ±29) 로 맞췄다. 원래 92 — 한 화면에 보이는
 * 지면(16:9 기준 약 56.5 유닛, FOV 30 · 거리 40 · 부각 42)의 1.5배 — 였는데 "맵이 너무
 * 크다" 해서 2/3(62 → 66)로 줄였고 (2026-09-23), 한 변을 반(33)으로 줄였다가 같은 날
 * 다시 두 배(66)로 키웠다 (2026-09-28, "맵 크기를 지금보다 두 배 키우고, 몬스터 간격을 넓혀").
 *
 * **화면 방향** — 카메라가 남동쪽 45°에서 내려다보므로(`camera_rig.gd` 의 `YAW`) 정사각
 * 맵이 화면에는 마름모로 선다. 화면 위 = (-x, -z) 귀퉁이, 아래 = (+x, +z), 오른쪽 =
 * (+x, -z), 왼쪽 = (-x, +z). 아래 "위·아래" 는 전부 화면 기준이다.
 */

/**
 * 차원문 자리 — 모든 존에서 같다. **화면 맨 위 귀퉁이**(-x, -z).
 *
 * 2026-09-28 요청 "포탈을 맨 위 방향에 설치해". 몬스터는 화면 아래 귀퉁이에서만 나오니
 * 문과 몬스터가 맵의 양 끝으로 갈린다. 맵을 33 → 66 으로 키우며 (-9, -9) 를 두 배로
 * 옮겼다 — 도착 지점(가운데)에서 25.5, 이동 가능 영역 끝(±29) 안쪽이다.
 * 어느 존에 가도 같은 자리에 있어야 "나가려면 어디로 가야 하나"를 존마다 다시 찾지 않는다.
 * (이전: (9, 0) → (4, 0) — 네 귀퉁이 무리 사이에 끼워 넣던 자리.)
 */
const GATE_SPOT: [number, number] = [-18, -18];

/**
 * 차원문 빛 색과 이름.
 *
 * 파란색 하나로 통일한다. 문이 하나뿐이니 색으로 구분할 상대가 없고, 존마다
 * 색이 다르면 "저건 다른 문인가" 하고 다시 확인하게 된다.
 */
const GATE_COLOR = '#4aa8ff';
const GATE_NAME = '사냥터 이동';

const gateFor = (): GateDef => ({
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
 * 사냥터 몬스터 — **맵 전체에 한 마리씩 듬성듬성**, 강한 종 (2026-09-29).
 *
 * 요청: 동그라미(시작 지점) 둘레에 네모(몬스터)를 흩어 그린 그림 + "여러 마리가 한 번에 붙지 않도록
 * 듬성듬성 배치하고, 어그로 범위로 수정해", 이어서 "그 정도 간격으로 배치하라고 한 거야. 그 숫자만
 * 배치하라고 한게 아니야. 몬스터를 더 많이". 그림 한 장을 **한 화면**(가로 약 25m · 세로 약 23m —
 * `camera_rig.gd` 거리 26.7 · FOV 30 · 부각 42°)으로 재면 이웃까지 평균 5.8m 다.
 *
 * - 자리는 **표에서 생성**한다 (`fieldSpots`) — 존마다 씨앗을 달리해 아무 자리나 뽑고, 이미 뽑은
 *   자리와 `FIELD_SPACING` 안이면 버린다. 사냥터마다 35~38마리, 이웃까지 평균 8.7m.
 * - `radius: 0` · `count: 1` — 흩뿌리지 않고 **그 자리에 한 마리**. 되살아나도 같은 자리다.
 * - 한 번에 한 마리만 붙는 조건: 두 자리 사이(≥ 8) − 순찰 반경 1 × 2 − 근접 사거리 2.5 = 3.5
 *   > 어그로 3 (`monsters.ts` 의 `AGGRO_RANGE`). 한 놈 옆에서 싸워도 이웃은 알아채지 않는다.
 *   `zones.test.ts` 가 20곳 전부 본다.
 * - 도착 지점(0,0) 둘레 `FIELD_CLEAR` 안에는 세우지 않는다 — 들어서자마자 달려오지 않게.
 * - 자리 끝 ±27.5 — 이동 끝(±29)에서 순찰 반경만큼 안쪽.
 * - 전에는 화면 아래 귀퉁이 (16, 16)·반경 13 원에 16마리를 흩뿌린 무리 하나였다.
 * - 보스는 없다. 보스 종(`boss00`~)은 던전·전직 시험에서만 선다.
 */
const FIELD_SPACING = 8;
const FIELD_EDGE = 27.5;
const FIELD_CLEAR = 6;
const FIELD_TRIES = 6000;

export function fieldSpots(index: number): [number, number][] {
  let seed = 1000 + index * 7919;
  const random = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };
  const out: [number, number][] = [];
  for (let t = 0; t < FIELD_TRIES; t++) {
    const x = Math.round((random() * 2 - 1) * FIELD_EDGE * 10) / 10;
    const z = Math.round((random() * 2 - 1) * FIELD_EDGE * 10) / 10;
    if (Math.hypot(x, z) < FIELD_CLEAR) continue;
    if (out.every(([a, b]) => Math.hypot(a - x, b - z) >= FIELD_SPACING)) out.push([x, z]);
  }
  return out;
}

function buildField(theme: FieldTheme, index: number): ZoneDef {
  const strong = tierLevels(index)[1];

  // 도착 지점은 맵 한가운데 하나뿐이다. 사슬 포탈이 없어졌으니 "어느 문으로
  // 들어왔나"를 따질 일이 없고, 이름 붙은 스폰(from_west 등)도 같이 사라졌다.
  return {
    id: theme.id,
    name: theme.name,
    size: ZONE_SIZE,
    spawns: { default: [0, 0] },
    // 차원문이 없다 (2026-09-29 요청 "사냥터에 들어가면 포탈을 제거해") — 마을로는 HUD 위쪽
    // "마을가기" 단추로 간다 (docs/features/hud.md "마을가기")
    // 맵 전체에 한 마리씩 (위 fieldSpots). 보스는 없다
    monsters: fieldSpots(index).map(([x, z]) => ({
      kind: monsterIdFor(strong), x, z, radius: 0, count: 1, respawnMs: 10000,
    })),
    env: envFor(theme),
  };
}

/** 마을 — 몬스터가 없는 시작 지점 */
const VILLAGE: ZoneDef = {
  id: 'village',
  name: '마을',
  size: ZONE_SIZE,
  spawns: { default: [0, 0] },
  // 사냥터로 나가는 유일한 문. 사냥터에 선 것과 같은 자리·같은 색이다.
  gate: gateFor(),
  // **전직관 한 명만 선다** (2026-09-26 요청: "마을에 불필요한 NPC들은 제거해. 지금은 전직
  // 교관만 있으면 되겠어"). 상인·대장장이·마을 사람 넷을 뺐다. 상점·대장간 판정(`World`)과
  // 창(`NpcPanel`), 모델(`merchant`·`smith`·`villager_*`)은 남아 있다 — 줄만 되살리면 선다
  // → docs/features/npc-town.md
  npcs: [
    // 전직 — 화면 아래 귀퉁이 쪽. 문(화면 맨 위 (-9, -9))과 맵 반대편이다.
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
