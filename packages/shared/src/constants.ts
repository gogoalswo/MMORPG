/**
 * 클라이언트와 서버가 공유하는 상수/타입.
 * 이동속도·데미지 공식처럼 "예측과 검증이 반드시 일치해야 하는" 값만 여기에 둔다.
 */

/** 서버 시뮬레이션 틱 (Hz) */
export const TICK_RATE = 15;
export const TICK_MS = 1000 / TICK_RATE;

/** 다른 플레이어 보간 지연 버퍼 (ms) */
export const INTERP_DELAY_MS = 120;

/** 이동속도 (units/sec). 이동은 항상 달리기 한 가지다. */
export const RUN_SPEED = 4.6;

/** 서버 이동 검증에 쓰는 상한 (탈것/버프가 생기면 여기를 올린다) */
export const MAX_SPEED = RUN_SPEED;

/** 서버 이동 검증 허용 오차 (1.0 = 오차 없음) */
export const MOVE_TOLERANCE = 1.15;

/** 관심영역(AoI) 그리드 셀 크기 (units) */
export const AOI_CELL_SIZE = 32;

export interface Vec2 {
  x: number;
  z: number;
}

export interface PlayerState {
  id: string;
  name: string;
  x: number;
  z: number;
  rotY: number;
  hp: number;
  maxHp: number;
}
