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

/**
 * 지나갈 수 없는 둥근 것 — 몬스터와 **다른 캐릭터**.
 *
 * 사각형이 아니라 원인 이유: 몬스터가 어느 쪽을 보고 있든 밀려나는 방향이 같아야
 * 서버와 클라이언트가 같은 답을 낸다. 회전이 들어가면 두 쪽 각이 한 프레임만 어긋나도
 * 캐릭터가 떨린다.
 */
export interface Solid {
  x: number;
  z: number;
  /** 반지름 */
  r: number;
}

/** 캐릭터가 차지하는 반지름 — 충돌 판정에만 쓴다 (모델 크기와는 별개다) */
export const PLAYER_RADIUS = 0.4;

/**
 * **몬스터끼리만** 추가로 벌려 두는 거리. 캐릭터가 낀 판정에는 안 들어간다.
 *
 * 몬스터는 한 사람을 쫓아 우르르 모이기 때문에, 몸끼리 딱 붙기만 해도 뭉쳐 보인다.
 * 사람은 자기가 조종하니 그렇게까지 몰리지 않는다 — 그래서 캐릭터 반지름을 키우는
 * 대신(그쪽은 사거리 한계가 빠듯하다) 몬스터 사이에만 여유를 넣는다.
 *
 * 이 값은 **공격 사거리와 무관하다.** 사람이 몬스터에 붙는 거리는 그대로이고,
 * 몬스터끼리는 서로 때릴 일이 없기 때문이다.
 */
export const MONSTER_GAP = 0.2;

/**
 * 몬스터가 차지하는 반지름. 모델 크기(`MonsterKind.scale`)에 비례한다.
 *
 * **0.38 을 곱하는 이유는 붙어서 때릴 수 있어야 하기 때문이다.** 가장 큰 보스(scale 3.42)
 * 라도 1.30 이라 캐릭터 반지름(0.4)을 더하면 1.70 인데, 가장 짧은 공격 사거리
 * (격투가 2.2 · 몬스터 1.9)보다 작다. 이보다 크게 잡으면 **충돌이 공격을 막아** 서로
 * 못 때리는 상황이 된다 — 몸집이 큰 보스부터 그렇게 된다.
 */
export function monsterRadius(scale: number): number {
  return 0.38 * scale;
}

/**
 * 겹친 만큼 밖으로 민다. **미는 쪽은 언제나 움직이는 쪽이다** —
 * 몬스터를 밀면 그 위치를 다시 모두에게 보내야 하고, 그러면 서버가 권위인 값이
 * 클라이언트 예측 때문에 흔들린다.
 *
 * 캐릭터끼리도 같다. 이 함수는 **이동을 계산하는 그 캐릭터만** 움직이고, 서 있는
 * 쪽은 입력이 없어 애초에 계산을 돌지 않는다. 그래서 둘이 서로 밀치며 떨지 않는다.
 *
 * 순서대로 한 번씩만 민다. 여러 마리 사이에 끼면 완전히 빠져나오지 못할 수 있는데,
 * 다음 입력에서 또 밀리므로 몇 프레임이면 풀린다. 반복해서 수렴시키는 쪽이 정확하지만,
 * **서버와 클라이언트가 같은 횟수를 돌아야** 하므로 단순한 쪽을 골랐다.
 */
export function pushOutOfSolids(
  state: MovableState,
  solids: Iterable<Solid>,
  halfSize: number,
  /** 밀려나는 쪽의 반지름. 몬스터가 몬스터를 피할 때는 캐릭터 반지름이 아니다 */
  radius: number = PLAYER_RADIUS,
  /**
   * 정확히 한가운데 겹쳤을 때 밀려날 방향(라디안).
   *
   * **겹친 둘이 서로 다른 값을 줘야 풀린다.** 같은 값이면 둘 다 같은 자리로 밀려
   * 계속 겹친 채로 남는다 (몬스터 여럿이 한 사람을 쫓을 때 실제로 그랬다).
   * 캐릭터는 기본값(+x)을 쓴다 — 서버와 클라이언트가 같은 답을 내야 하기 때문이다.
   */
  tieAngle = 0
): void {
  for (const solid of solids) {
    const dx = state.x - solid.x;
    const dz = state.z - solid.z;
    const min = solid.r + radius;
    const squared = dx * dx + dz * dz;
    if (squared >= min * min) continue;

    const distance = Math.sqrt(squared);
    if (distance < 1e-4) {
      // 한가운데 정확히 겹쳤다 — 밀 방향이 없다. `tieAngle` 쪽으로 밀어낸다
      state.x = clamp(solid.x + Math.cos(tieAngle) * min, -halfSize, halfSize);
      state.z = clamp(solid.z + Math.sin(tieAngle) * min, -halfSize, halfSize);
      continue;
    }
    state.x = clamp(solid.x + (dx / distance) * min, -halfSize, halfSize);
    state.z = clamp(solid.z + (dz / distance) * min, -halfSize, halfSize);
  }
}

/**
 * 무리 안에서 **다른 몸과 겹치지 않는 자리**를 고른다. 몬스터 스폰·리스폰이 쓴다.
 *
 * 그냥 원 안에 무작위로 뿌리면 몇 마리는 반드시 겹친다 — 몬스터는 겹친 채로 가만히
 * 서 있으므로 그게 그대로 화면에 남는다 (한 자리에 두 마리가 포개져 보이던 문제).
 *
 * 빈 자리를 `tries` 번 찍어 보고, 전부 겹치면 **가장 여유 있는 후보**를 골라 한 번 민다.
 * 무리가 빽빽해 자리가 없을 수도 있어서 "될 때까지" 돌리지 않는다 — 그건 서버가 멈추는
 * 길이다. 미는 쪽은 이번에 놓이는 놈이고, 이미 서 있는 놈은 건드리지 않는다.
 */
export function scatterSpawn(
  center: { x: number; z: number; radius: number },
  myRadius: number,
  taken: Iterable<Solid>,
  halfSize: number,
  random: () => number = Math.random,
  tries = 12
): { x: number; z: number } {
  const others = [...taken];
  let best = { x: center.x, z: center.z };
  let bestClearance = -Infinity;

  for (let i = 0; i < tries; i++) {
    const angle = random() * Math.PI * 2;
    // 제곱근을 씌워야 원 안에 고르게 퍼진다 (안 씌우면 가운데로 몰린다)
    const dist = Math.sqrt(random()) * center.radius;
    const spot = {
      x: clamp(center.x + Math.cos(angle) * dist, -halfSize, halfSize),
      z: clamp(center.z + Math.sin(angle) * dist, -halfSize, halfSize),
    };

    // 가장 가까운 몸까지 남는 여유. 0 이상이면 안 겹친다
    let clearance = Infinity;
    for (const other of others) {
      const gap = Math.hypot(spot.x - other.x, spot.z - other.z) - (other.r + myRadius);
      if (gap < clearance) clearance = gap;
    }
    if (clearance >= 0) return spot;
    if (clearance > bestClearance) {
      bestClearance = clearance;
      best = spot;
    }
  }

  pushOutOfSolids(best, others, halfSize, myRadius);
  return best;
}

function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

/**
 * 입력 하나를 적용한다. 신뢰할 수 없는 값이 들어와도 여기서 전부 걸러진다 —
 * 서버는 클라이언트가 보낸 dx/dz/dt 를 그대로 믿지 않는다.
 */
export function applyMove(
  state: MovableState,
  input: MoveInput,
  halfSize: number,
  /** 지나갈 수 없는 것들. **서버와 클라이언트가 같은 목록을 줘야 한다** */
  solids?: Iterable<Solid>
): void {
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

  // 움직인 다음에 민다. 움직이기 전에 밀면 이미 빠져나온 자리에서 또 밀려 제자리걸음이 된다
  if (solids) pushOutOfSolids(state, solids, halfSize);
}

/** 존 경계까지의 거리 (지면 가장자리에서 조금 안쪽) */
export function zoneHalfSize(zoneSize: number): number {
  return zoneSize / 2 - 4;
}
