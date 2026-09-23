import type { GateDef, ZoneDef } from './zone.ts';
import { MONSTER_KINDS, bossIdFor, bossLevel } from './monsters.ts';

/**
 * 던전 — 가방 옆 "던전" 단추로 들어간다 (차원문 목록에는 없다).
 *
 *   던전 단추 ─┬─ 토벌 던전 ─┬─ 1단계 (초원 보스 Lv.9)
 *              │             ├─ …
 *              │             └─ 20단계
 *              ├─ (준비 중)
 *              └─ (준비 중)
 *
 * **종류는 셋인데 지금은 토벌 하나만 연다** (2026-09-23 요청: "일단 한 가지 타입만
 * 구현하자"). 나머지 둘은 창에 이름만 보이고 눌리지 않는다 — `open: false`.
 * 이름은 자리를 잡아 둔 가칭이다. 열 때 정한다.
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
  boss: string;
  level: number;
}

export interface DungeonType {
  id: string;
  name: string;
  /** false 면 창에 이름만 보이고 눌리지 않는다 */
  open: boolean;
  stages: DungeonStage[];
}

/**
 * 던전 안의 보스 자리 — **화면 위쪽**(북서), 도착 지점에서 22.6.
 *
 * 카메라가 남동쪽 45°에서 내려다보므로(`camera_rig.gd` 의 `YAW`) 화면 위쪽은 -x·-z
 * 대각선이다. 거리는 사냥터 보스(23)와 비슷하게 두어 보스 인식 범위(무리 반경 3 +
 * 18 = 21) 밖이라, 들어서자마자 달려들지 않고 한 걸음 나가야 싸움이 시작된다.
 */
const BOSS_SPOT: [number, number] = [-16, -16];

const RAID_ENV: ZoneDef['env'] = {
  skyColor: '#2a2530',
  sunIntensity: 1.2,
  hemiIntensity: 0.6,
  grassDark: '#2a2830',
  grassLight: '#3a3640',
  ground: 'cobble',
  groundTint: '#4a4550',
};

const raidZoneId = (stage: number) => `raid_${String(stage).padStart(2, '0')}`;

/** 보스 수 = 사냥터 수. 사냥터를 늘리면 보스가 늘고 단계도 따라 는다 */
const BOSS_COUNT = Object.values(MONSTER_KINDS).filter((k) => k.boss).length;

const RAID_STAGES: DungeonStage[] = Array.from({ length: BOSS_COUNT }, (_, i) => ({
  zone: raidZoneId(i + 1),
  stage: i + 1,
  boss: bossIdFor(i),
  level: bossLevel(i),
}));

export const DUNGEON_TYPES: DungeonType[] = [
  { id: 'raid', name: '토벌 던전', open: true, stages: RAID_STAGES },
  { id: 'trial', name: '시련의 탑', open: false, stages: [] },
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
      out.push({
        id: s.zone,
        name: `${type.name} ${s.stage}단계`,
        size: 66,
        spawns: { default: [0, 0] },
        gate: gate(),
        monsters: [{ kind: s.boss, x: BOSS_SPOT[0], z: BOSS_SPOT[1], radius: 3, count: 1, respawnMs: 900000 }],
        env: RAID_ENV,
      });
    }
  }
  return out;
}

/** 던전 단계 존 id 전부 — 창에서 갈 수 있는 곳 */
export const DUNGEON_ZONES: string[] = DUNGEON_TYPES.flatMap((t) => t.stages.map((s) => s.zone));
