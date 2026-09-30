import { ZONE_SIZE, type GateDef, type ZoneDef } from './zone.ts';
import { MONSTER_KINDS, bossIdFor, bossLevel, monsterIdFor, tierLevels } from './monsters.ts';
import { DUNGEON_PROTEIN_PER_STAGE } from './fitness.ts';

/**
 * 던전 — 가방 옆 "던전" 단추로 들어간다 (차원문 목록에는 없다).
 *
 *   던전 단추 ─┬─ 토벌 던전 ─┬─ 1단계 (첫 티어 보스 Lv.9)
 *              │             ├─ …
 *              │             └─ 20단계
 *              ├─ 시련의 탑 ─┬─ 1단계 (뿔토끼 Lv.8 × 10, 30초에 7마리)
 *              │             └─ … 20단계
 *              └─ (준비 중)
 *
 * **종류는 셋인데 토벌과 시련의 탑을 연다** (토벌 2026-09-23, 시련의 탑 2026-09-29).
 * 보물 창고는 창에 이름만 보이고 눌리지 않는다 — `open: false`. 이름은 가칭이다.
 *
 * **단계 하나 = 존 하나 = 보스 한 마리.** 보스는 사냥터 보스를 그대로 쓴다 —
 * N단계는 N번째 사냥터의 보스다. 새 종을 만들지 않으니 몬스터 표·모델이 그대로다.
 * 그래서 단계 수 = 사냥터 수(20)이고, 사냥터를 늘리면 단계도 저절로 는다.
 */

export interface DungeonStage {
  /** 들어갈 존 id — `ZONES` 에 있다 */
  zone: string;
  /** 1부터 */
  stage: number;
  /** 토벌만 — 그 단계 보스 */
  boss?: string;
  level: number;
  /** 깨면(보스를 잡으면) 들어오는 **스킬 경험치** — 단계 × `DUNGEON_SKILL_EXP_PER_STAGE` */
  skillExp: number;
  /**
   * 깨면 들어오는 **프로틴** — 세 종(파워·디펜스·헬스)을 **각각** 이만큼. 단계 × `DUNGEON_PROTEIN_PER_STAGE`.
   * 토벌·시련의 탑 둘 다 준다 → 헬스(fitness.ts)
   */
  protein: number;
  /** 시련의 탑만 — 나오는 일반 몬스터 종 (토벌은 `boss`) */
  monster?: string;
  /** 시련의 탑만 — `seconds` 안에 `kills` 마리를 잡으면 통과, 크리스탈 `crystals` 개 */
  kills?: number;
  seconds?: number;
  crystals?: number;
}

export interface DungeonType {
  id: string;
  name: string;
  /** false 면 창에 이름만 보이고 눌리지 않는다 */
  open: boolean;
  stages: DungeonStage[];
}

/**
 * 던전 안의 보스 자리 — **화면 아래 귀퉁이**(+x, +z), 도착 지점에서 11.3.
 *
 * 카메라가 남동쪽 45°에서 내려다보므로(`camera_rig.gd` 의 `YAW`) 화면 아래는 +x·+z
 * 대각선이다. 원래 화면 위쪽 (-16, -16) 이었는데 2026-09-28 에 맵을 반(33)으로 줄이고
 * 차원문을 화면 맨 위(-9, -9)로 옮기면서 사냥터 몬스터와 같은 아래쪽으로 옮겼다 —
 * 나가려고 문을 밟는 길이 보스 앞이면 안 된다. 같은 날 맵을 다시 66 으로 키우며 두 배
 * (16, 16) 로 옮겼다 — 반경 3 까지 19 로 이동 가능 영역(±29) 안이고, 도착 지점에서 22.6 이라
 * 보스 인식 범위(3 + 18 = 21) 밖이다.
 */
export const DUNGEON_BOSS_SPOT: [number, number] = [16, 16];

export const DUNGEON_ENV: ZoneDef['env'] = {
  skyColor: '#2a2530',
  sunIntensity: 1.2,
  hemiIntensity: 0.6,
  grassDark: '#2a2830',
  grassLight: '#3a3640',
  ground: 'cobble',
  groundTint: '#4a4550',
};

/**
 * **던전 클리어 보상 — 스킬 경험치.** N단계를 깨면 N × 1000 (2026-09-28 요청:
 * "1단계는 1000, 2단계는 2000, 3단계는 3000"). 캐릭터에 하나로 쌓이고 스킬창에서
 * 골라 강화에 넣는다 → [skill-upgrades.md]. 잡을 때마다 들어온다 — 보스가 다시 서면
 * (15분 · 나갔다 들어오면 바로) 또 받는다
 */
export const DUNGEON_SKILL_EXP_PER_STAGE = 1000;

const raidZoneId = (stage: number) => `raid_${String(stage).padStart(2, '0')}`;

/** 보스 수 = 사냥터 수. 사냥터를 늘리면 보스가 늘고 단계도 따라 는다 */
const BOSS_COUNT = Object.values(MONSTER_KINDS).filter((k) => k.boss).length;

const RAID_STAGES: DungeonStage[] = Array.from({ length: BOSS_COUNT }, (_, i) => ({
  zone: raidZoneId(i + 1),
  stage: i + 1,
  boss: bossIdFor(i),
  level: bossLevel(i),
  skillExp: (i + 1) * DUNGEON_SKILL_EXP_PER_STAGE,
  protein: (i + 1) * DUNGEON_PROTEIN_PER_STAGE,
}));

/**
 * **시련의 탑 — 30초 안에 7마리** (2026-09-29 요청: "30초 동안 여러 몬스터를 잡으면 통과하는
 * 던전", "7마리 잡는걸로 하고, 맵 크기를 줄여", "크리스탈을 보상으로").
 *
 * - 7마리는 설계의 "동레벨 한 마리 4초"(`KILL_SECONDS`, stat-balance.md 7장)에서 나왔다 —
 *   30 ÷ 4 = 7.5. 동레벨 평타만으로는 5~6마리라 스킬을 섞어야 통과한다.
 * - N단계 = N번째 사냥터의 **강한 일반 몬스터**(`tierLevels(N-1)[1]`, Lv.10N-2). 새 종을 만들지 않는다.
 * - 맵은 `TRIAL_ZONE_SIZE`(30, 이동 가능 ±11) — 사냥터(66)의 절반이 안 된다. 사냥터의 4초에는
 *   다음 몬스터까지 8m 걷는 시간이 들어 있는데, 좁은 맵에서는 그 시간이 거의 빠진다.
 * - 몬스터는 도착 지점을 둘러싼 **반경 `TRIAL_RING` 원에 `TRIAL_MONSTERS` 마리**, 되살아나지
 *   않는다(시험 동안). 7마리보다 셋 많게 둬 한두 마리가 멀리 떠돌아도 모자라지 않다.
 * - 통과 판정은 기기(`World._trial`)가 하고, 크리스탈은 장부(`Ledger.trial_clear`)가 준다.
 *   서버는 들어온 뒤 30초 안에 인정한 처치 수를 제 명단으로 다시 센다 (server.md).
 * - 보상 = 단계 × `TRIAL_CRYSTALS_PER_STAGE` 개 (사용자가 고른 안: "단계 × 1개").
 * - 차원문이 없다 — 나가는 길은 결과창 **확인**(마을로)과 HUD **마을가기** 다.
 */
export const TRIAL_KILLS = 7;
export const TRIAL_SECONDS = 30;
export const TRIAL_CRYSTALS_PER_STAGE = 1;
export const TRIAL_ZONE_SIZE = 30;
export const TRIAL_MONSTERS = 10;
export const TRIAL_RING = 7;

const trialZoneId = (stage: number) => `trial_${String(stage).padStart(2, '0')}`;

const TRIAL_STAGES: DungeonStage[] = Array.from({ length: BOSS_COUNT }, (_, i) => {
  const level = tierLevels(i)[1];
  return {
    zone: trialZoneId(i + 1),
    stage: i + 1,
    monster: monsterIdFor(level),
    level,
    skillExp: 0,
    protein: (i + 1) * DUNGEON_PROTEIN_PER_STAGE,
    kills: TRIAL_KILLS,
    seconds: TRIAL_SECONDS,
    crystals: (i + 1) * TRIAL_CRYSTALS_PER_STAGE,
  };
});

/** 시련 몬스터 자리 — 도착 지점(0, 0)을 둘러싼 원에 고르게. 한 자리에 한 마리 */
export function trialSpots(): [number, number][] {
  return Array.from({ length: TRIAL_MONSTERS }, (_, i) => {
    const a = (i / TRIAL_MONSTERS) * Math.PI * 2;
    return [Math.round(Math.cos(a) * TRIAL_RING * 10) / 10, Math.round(Math.sin(a) * TRIAL_RING * 10) / 10];
  });
}

export const DUNGEON_TYPES: DungeonType[] = [
  { id: 'raid', name: '토벌 던전', open: true, stages: RAID_STAGES },
  { id: 'trial', name: '시련의 탑', open: true, stages: TRIAL_STAGES },
  { id: 'treasure', name: '보물 창고', open: false, stages: [] },
];

/**
 * 던전 단계마다 존 하나. 문은 `zones.ts` 가 넘겨준다 — 모든 존이 같은 자리·같은 문을
 * 써야 해서(`zones.test.ts`) 그 규칙을 한 곳에 둔다. **문이 있어야 나온다.**
 *
 * 보스는 한 번 잡으면 15분 뒤에 다시 선다(사냥터와 같다). 다시 싸우려면 나갔다가
 * 던전 창으로 다시 들어온다 — `World.open` 이 존을 열 때마다 몬스터를 새로 세운다.
 */
export function dungeonZones(gate: () => GateDef): ZoneDef[] {
  const out: ZoneDef[] = [];
  for (const type of DUNGEON_TYPES) {
    for (const s of type.stages) {
      const name = `${type.name} ${s.stage}단계`;
      if (s.monster) {
        // 시련의 탑 — 좁은 맵, 차원문 없음, 되살아나지 않는 몬스터 원
        out.push({
          id: s.zone,
          name,
          size: TRIAL_ZONE_SIZE,
          spawns: { default: [0, 0] },
          monsters: trialSpots().map(([x, z]) => ({ kind: s.monster!, x, z, radius: 0, count: 1, respawnMs: 900000 })),
          env: DUNGEON_ENV,
        });
        continue;
      }
      out.push({
        id: s.zone,
        name,
        size: ZONE_SIZE,
        spawns: { default: [0, 0] },
        gate: gate(),
        monsters: [{ kind: s.boss!, x: DUNGEON_BOSS_SPOT[0], z: DUNGEON_BOSS_SPOT[1], radius: 3, count: 1, respawnMs: 900000 }],
        env: DUNGEON_ENV,
      });
    }
  }
  return out;
}

/** 던전 단계 존 id 전부 — 창에서 갈 수 있는 곳 */
export const DUNGEON_ZONES: string[] = DUNGEON_TYPES.flatMap((t) => t.stages.map((s) => s.zone));
