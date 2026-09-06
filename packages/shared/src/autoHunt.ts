/**
 * 자동 사냥의 판단 부분.
 *
 * **서버에서 돈다.** 클라이언트에서 돌리면 탭을 옮기는 순간 브라우저가
 * requestAnimationFrame 을 멈추고 타이머를 1Hz 로 조여서 캐릭터가 선다.
 * 서버는 이미 15Hz 로 몬스터 AI 를 돌리고 있으니 같은 자리에 얹는 게 맞다.
 *
 * 여기 있는 두 함수는 순수 계산이라 테스트로 묶어둔다. 실제로 때리는 일
 * (쿨타임·마나·정면각 검증)은 기존 공격/스킬 경로를 그대로 쓴다.
 */

/**
 * 앵커에서 이 반경 안의 몬스터만 고른다.
 *
 * 사람이 조절한다. 좁히면 한 자리에 붙어 안전하게 돌고, 넓히면 사냥터를
 * 크게 돌지만 여러 무리를 한꺼번에 달고 다니게 된다.
 */
export const HUNT_RADIUS = 22;

/** 조절 가능한 범위. 이동 가능 영역이 ±42 라 그보다 넓힐 이유가 없다 */
export const HUNT_RADIUS_MIN = 6;
export const HUNT_RADIUS_MAX = 40;

/** 사람이 넣은 값을 쓸 수 있는 값으로 만든다 — 서버가 반드시 다시 거친다 */
export function clampHuntRadius(value: unknown): number {
  const n = typeof value === 'number' && Number.isFinite(value) ? Math.round(value) : HUNT_RADIUS;
  return Math.min(HUNT_RADIUS_MAX, Math.max(HUNT_RADIUS_MIN, n));
}

/**
 * 쫓던 대상을 포기하는 거리.
 *
 * 사냥 반경보다 넉넉해야 한다. 같으면 경계에 걸친 몬스터를 잡았다 놓았다
 * 반복하며 제자리걸음만 한다.
 */
export function huntLeash(radius: number): number {
  return radius + 8;
}
/**
 * 클릭으로 직접 지정한 대상을 포기하는 거리.
 *
 * 자동 사냥과 달리 돌아갈 앵커가 없어서, 도망치는 몬스터를 그냥 따라가면
 * 존 끝까지 끌려간다. **누른 순간 그놈이 서 있던 자리**에서 이만큼 달아나면
 * 놓는다. 플레이어 기준으로 재면 멀리 보이는 놈을 눌렀을 때 누르자마자 풀린다.
 */
export const CHASE_LEASH = 45;

/** 사거리의 몇 할까지 붙을지. 꽉 채우면 몬스터가 조금만 움직여도 빠진다 */
export const HUNT_STANDOFF = 0.7;
/** 목표 지점에 이만큼 붙으면 도착으로 본다 */
export const HUNT_ARRIVE_EPS = 0.25;
/** 체력이 이 아래로 떨어지면 자기 회복 스킬을 쓴다 */
export const HUNT_HEAL_BELOW = 0.5;

export interface HuntCandidate {
  id: string;
  x: number;
  z: number;
  hp: number;
}

/**
 * 이번 틱에 때릴 대상을 고른다.
 *
 * 이미 잡고 있던 대상을 우선 유지한다 — 매 틱 "가장 가까운 놈"으로 갈아타면
 * 두 마리 사이에서 왔다갔다하다가 아무것도 못 죽인다.
 *
 * 앵커(사냥을 켠 자리)를 기준으로 고르는 이유는, 플레이어 기준으로 고르면
 * 한 마리씩 끌려가며 앵커에서 무한히 멀어지기 때문이다.
 */
export function pickHuntTarget(
  anchorX: number,
  anchorZ: number,
  candidates: Iterable<HuntCandidate>,
  currentId: string | null,
  radius = HUNT_RADIUS,
  leash = huntLeash(radius)
): string | null {
  let bestId: string | null = null;
  let bestDist = radius;

  for (const c of candidates) {
    if (c.hp <= 0) continue;
    const dist = Math.hypot(c.x - anchorX, c.z - anchorZ);

    // 잡고 있던 놈은 리쉬 안에 있는 한 계속 잡는다
    if (c.id === currentId && dist <= leash) return c.id;

    if (dist < bestDist) {
      bestDist = dist;
      bestId = c.id;
    }
  }

  return bestId;
}

/**
 * 대상에서 distance 만큼 떨어진, 지금 위치에서 가장 가까운 지점.
 *
 * 대상 위로 겹쳐 서지 않으려고 반대쪽으로 물러난 점을 잡는다.
 * 이미 겹쳐 있으면 방향을 정할 수 없으므로 임의의 축을 쓴다.
 */
export function standoffPoint(
  fromX: number,
  fromZ: number,
  targetX: number,
  targetZ: number,
  distance: number
): { x: number; z: number } {
  let dx = fromX - targetX;
  let dz = fromZ - targetZ;
  const length = Math.hypot(dx, dz);

  if (length < 1e-4) {
    dx = 0;
    dz = 1;
  } else {
    dx /= length;
    dz /= length;
  }

  return { x: targetX + dx * distance, z: targetZ + dz * distance };
}
