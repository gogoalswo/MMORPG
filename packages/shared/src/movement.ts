import { RUN_SPEED } from './constants.ts';

/**
 * 이동 계산. **클라이언트와 서버가 반드시 이 함수를 함께 쓴다.**
 *
 * 클라이언트는 입력 즉시 이 함수로 자기 위치를 예측하고,
 * 서버는 같은 입력에 같은 함수를 돌려 권위 위치를 만든다.
 * 두 쪽 계산이 한 글자라도 다르면 매 틱 보정이 튀면서 캐릭터가 떨린다.
 */

/** 입력 하나가 담을 수 있는 최대 시간. 이걸 안 막으면 dt 를 부풀려 순간이동할 수 있다 */
export const MAX_INPUT_DT = 0.1;

export interface MoveInput {
  /** 입력 순번. 서버가 마지막 처리 번호를 돌려주면 클라가 그 이전 것을 버린다 */
  seq: number;
  /** 이동 방향 (단위벡터, 정지면 0) */
  dx: number;
  dz: number;
  /** 이 입력이 커버하는 시간 (초) */
  dt: number;
}

export interface MovableState {
  x: number;
  z: number;
}

function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

/**
 * 입력 하나를 적용한다. 신뢰할 수 없는 값이 들어와도 여기서 전부 걸러진다 —
 * 서버는 클라이언트가 보낸 dx/dz/dt 를 그대로 믿지 않는다.
 */
export function applyMove(state: MovableState, input: MoveInput, halfSize: number): void {
  let dx = input.dx;
  let dz = input.dz;

  if (!Number.isFinite(dx) || !Number.isFinite(dz)) return;

  // 방향은 단위벡터를 넘을 수 없다 (길이를 부풀린 속도 핵 차단)
  const len = Math.hypot(dx, dz);
  if (len > 1) {
    dx /= len;
    dz /= len;
  } else if (len < 1e-4) {
    return;
  }

  const dt = Number.isFinite(input.dt) ? clamp(input.dt, 0, MAX_INPUT_DT) : 0;

  state.x = clamp(state.x + dx * RUN_SPEED * dt, -halfSize, halfSize);
  state.z = clamp(state.z + dz * RUN_SPEED * dt, -halfSize, halfSize);
}

/** 존 경계까지의 거리 (지면 가장자리에서 조금 안쪽) */
export function zoneHalfSize(zoneSize: number): number {
  return zoneSize / 2 - 4;
}
