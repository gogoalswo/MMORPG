import type { MonsterSpawnDef } from './monsters.ts';

/**
 * 존(맵) 정의.
 *
 * 월드는 연속된 하나의 공간이 아니라 독립된 존 여러 개이고, 포탈로 이동한다.
 * 이 정의는 클라이언트(씬 구성)와 서버(룸 생성·포탈 검증)가 함께 쓴다.
 *
 * JSON 파일이 아니라 TS 객체로 두는 이유: 타입 검사가 되고,
 * Vite 와 Node 양쪽에서 import 방식이 동일하다. 존이 수십 개로 늘고
 * 월드 에디터가 생기면 그때 파일/DB 로 옮긴다.
 */

/** 지면에 난 길 하나. 사인 곡선으로 완만하게 사행한다. */
export interface RoadDef {
  /** 길이 뻗는 축 */
  axis: 'x' | 'z';
  /** 반대 축에서의 중심 위치 */
  offset: number;
  /** 길 반폭 */
  width: number;
  /** 사행 진폭 */
  wave: number;
  /** 사행 주기 */
  waveFreq: number;
}

/** 존의 분위기 — 색, 안개, 식생 밀도 */
export interface ZoneEnv {
  skyColor: string;
  fogColor: string;
  fogNear: number;
  fogFar: number;
  sunIntensity: number;
  hemiIntensity: number;

  grassDark: string;
  grassLight: string;
  dirt: string;
  dirtLight: string;

  /** 잔디 인스턴스 수와 배치 반경 */
  grassCount: number;
  grassRadius: number;

  roads: RoadDef[];
}

export interface PortalDef {
  id: string;
  /** [x, z] */
  position: [number, number];
  /** 진입 판정 반경 */
  radius: number;
  /** 포탈 빛 색 */
  color: string;
  target: { zone: string; spawn: string };
}

/**
 * 말을 걸 수 있는 NPC 가 하는 일.
 *
 * 없으면 그냥 서 있는 사람이다. 서버는 상호작용 요청이 올 때마다 **그 존에
 * 그 역할의 NPC 가 있는지, 그리고 가까이 있는지**를 다시 확인한다.
 */
export type NpcRole = 'shop' | 'smith' | 'jobs';

/** 말을 걸 수 있는 거리 (m) */
export const NPC_REACH = 4.5;

export interface NpcDef {
  name: string;
  /** 직업 id. look 이 없을 때 외형의 기준이 된다 */
  job: string;
  /**
   * 고유 외형 이름 (대장장이, 상인, 마을 사람 …).
   *
   * 없으면 직업 외형을 쓴다. 마을 사람이 플레이어와 똑같이 생기면 누가
   * 사람이고 누가 NPC 인지 구분이 안 된다.
   */
  look?: string;
  x: number;
  z: number;
  hp?: number;
  /** 있으면 말을 걸 수 있다 */
  role?: NpcRole;
  /** 머리 위에 띄울 직함 */
  title?: string;
}

export interface ZoneDef {
  id: string;
  /** 화면에 보여줄 이름 */
  name: string;
  /** 한 변 길이 */
  size: number;
  /** 이름 붙은 스폰 지점들. 'default' 는 반드시 있어야 한다 */
  spawns: Record<string, [number, number]>;
  portals: PortalDef[];
  npcs?: NpcDef[];
  monsters?: MonsterSpawnDef[];
  env: ZoneEnv;
}
