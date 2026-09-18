import type { MonsterSpawnDef } from './monsters.ts';

/**
 * 존(맵) 정의.
 *
 * 월드는 연속된 하나의 공간이 아니라 독립된 존 여러 개이고, 차원문으로 이동한다.
 * 이 정의는 클라이언트(씬 구성)와 서버(룸 생성)가 함께 쓴다.
 *
 * JSON 파일이 아니라 TS 객체로 두는 이유: 타입 검사가 되고,
 * Vite 와 Node 양쪽에서 import 방식이 동일하다. 존이 수십 개로 늘고
 * 월드 에디터가 생기면 그때 파일/DB 로 옮긴다.
 */

/**
 * 바닥 텍스처 종류. 이미지 한 장이 한 종류다 (바르코로 만든 타일 7장,
 * docs/ASSETS.md). 사냥터 20곳이 이 중 여섯을 나눠 쓰고, 돌판은 마을이 쓴다.
 */
export const GROUND_KINDS = ['stone', 'grass', 'snow', 'dirt', 'sand', 'cobble', 'lava'] as const;
export type GroundKind = (typeof GROUND_KINDS)[number];

/**
 * 바닥 텍스처마다 다른 것 — 이미지가 가진 성질이라 존 데이터가 아니라 여기 둔다.
 *
 * 이미지 한 장(1024²)에 무엇이 몇 개 그려져 있느냐가 종류마다 달라서 타일
 * 크기도 따로다. 돌판은 한 장에 판석이 일고여덟 줄이라 6m 로 펴야 한 장이
 * 80cm 쯤 되고, 자갈은 스무 개 남짓이라 8m 에 한 알이 35cm 다 — 4m 로 두면
 * 기본 카메라 거리에서 알이 안 보이고 모래 같은 잡티가 된다. 용암은 재 얼룩이
 * 크게 몇 개뿐이라 12m 보다 좁히면 얼룩이 격자로 늘어선 게 보인다.
 */
export interface GroundLook {
  /** 타일 한 장이 덮는 실제 크기(m) */
  tile: number;
  /**
   * 배율이 다른 두 샘플을 섞는 비율 (0 = 안 섞음).
   *
   * 같은 타일을 스무 번 넘게 깔면 격자가 드러난다. 배율 0.37 짜리를 겹치면
   * 반복 주기가 어긋나 깨진다 — 풀·눈·모래처럼 무늬가 흩어진 것에만 쓴다.
   * 돌판·자갈·용암 균열처럼 **모양이 뚜렷한 것**에 쓰면 판석이 두 겹으로
   * 비쳐 보인다.
   */
  blend: number;
  roughness: number;
  /**
   * 텍스처 평균색 (sRGB). build-ground-textures.mjs 가 출력하는 값.
   * 존 틴트는 "이 색을 그 존의 색 쪽으로" 끌어당기는 비율로 건다.
   */
  mean: string;
  /** 스스로 빛나는 정도 — 용암 균열 */
  glow: number;
}

export const GROUND_LOOKS: Record<GroundKind, GroundLook> = {
  stone: { tile: 6, blend: 0, roughness: 0.85, mean: '#51504f', glow: 0 },
  grass: { tile: 4, blend: 0.45, roughness: 0.95, mean: '#4e6536', glow: 0 },
  snow: { tile: 6, blend: 0.45, roughness: 0.7, mean: '#d6dee6', glow: 0 },
  dirt: { tile: 6, blend: 0.45, roughness: 0.95, mean: '#9f8467', glow: 0 },
  sand: { tile: 6, blend: 0.45, roughness: 0.9, mean: '#e6ca9d', glow: 0 },
  cobble: { tile: 8, blend: 0, roughness: 0.8, mean: '#746b5c', glow: 0 },
  lava: { tile: 12, blend: 0, roughness: 0.9, mean: '#3e3837', glow: 1 },
};

/**
 * 존의 분위기 — 색, 바닥.
 *
 * **안개는 없다** (2026-09-18 요청: "안개를 넣으라고 한 적이 없는데 왜 넣은거야?
 * 그냥 안개를 없애버려"). `fogColor`/`fogNear`/`fogFar` 를 데이터째 걷어냈다 —
 * 안개는 곱이 아니라 더하기라 돌 틈처럼 어두운 데를 들어올려 바닥 무늬를 씻는다.
 */
export interface ZoneEnv {
  skyColor: string;
  sunIntensity: number;
  hemiIntensity: number;

  /**
   * 하늘·반구광의 땅 쪽 색. 이름은 풀 잎을 심던 때의 것이다 — 풀 잎과 길은
   * 2026-09-10 에 없앴다(요청: 바닥 이미지만 깐다).
   */
  grassDark: string;
  grassLight: string;

  /** 바닥 텍스처 — 존 전체에 이 한 장만 깐다 */
  ground: GroundKind;
  /**
   * 바닥 평균색을 이 색 쪽으로 끌어당긴다. 사냥터 20곳이 텍스처 여섯을
   * 나눠 쓰므로, 같은 텍스처를 쓰는 곳끼리는 이 색으로 갈린다.
   */
  groundTint: string;
}

/**
 * 바닥에 놓인 빛나는 문 하나의 생김새와 크기.
 *
 * 그리는 쪽(`createPortal`)은 이것만 안다 — 밟았을 때 무슨 일이 일어나는지는
 * 모른다. 지금 세상에 있는 문은 차원문(`GateDef`) 하나뿐이다.
 */
export interface PortalVisual {
  /** [x, z] */
  position: [number, number];
  /** 진입 판정 반경 */
  radius: number;
  /** 포탈 빛 색 */
  color: string;
}

/**
 * 목적지를 고르는 문. 밟으면 곧바로 이동하지 않고 목록을 연다.
 *
 * **존을 오가는 유일한 길이다.** 예전에는 존끼리 사슬 포탈로 이어져 있어서
 * 밟으면 곧장 옆 사냥터로 넘어갔지만, 걸어 들어가는 포탈은 전부 없앴다.
 * 그래서 문은 **모든 존에** 있어야 한다 — 하나라도 빠지면 그 존에 들어간
 * 캐릭터가 죽는 것 말고는 나올 방법이 없다. `zones.test.ts` 가 검사한다.
 */
export interface GateDef extends PortalVisual {
  /** 문 위에 띄우는 이름 */
  name: string;
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
  /** 목적지를 고르는 문. 존을 오가는 유일한 길이라 모든 존에 있다 */
  gate: GateDef;
  npcs?: NpcDef[];
  monsters?: MonsterSpawnDef[];
  env: ZoneEnv;
}
