/**
 * 기본 자세가 다른 두 뼈대를 **뼈 방향으로 맞춘다** — 가상의 기본 자세를 계산할 뿐, 파일은 안 고친다.
 *
 * 2026-09-26: 격투가 몸을 바르코가 **주먹을 쥔 채 팔을 내리고** 뽑은 모델(`fighter_fist_pose`)로 바꿨다
 * ("바르코 보면 정상적으로 주먹을 잘 쥐고 있는데 왜 이대로 적용을 못 하는거야"). T 포즈로 뽑으면
 * 바르코가 손을 펴서 조각하기 때문에 주먹은 이 모델에만 있다. 그런데 동작(옛 몸 클립·블렌더 대기)과
 * 장비 모델은 **T 포즈 뼈대**에서 왔다. "기본 자세에서 돈 만큼" 을 그대로 입히면 이미 내린 팔이
 * 한 번 더 내려가 몸을 뚫는다.
 *
 * 그래서 몸 뼈대를 위에서부터 차례로 **그 뼈가 가리키는 방향(자식 관절 쪽)만** 기준 뼈대와 같게
 * 돌린(스윙) 가상 자세를 만든다. 비틀림은 건드리지 않는다 — 내린 팔을 옆으로 들면 손등이 위로 가는,
 * 사람 몸 그대로다. 손 아래(손가락)는 돌리지 않아 주먹이 그대로 따라간다.
 *
 * 메시는 조각된 자세(팔 내림) 그대로 두고, 이 가상 자세는
 * - `add-clips.mjs --align` 이 동작을 옮길 때 새 뼈대의 "기본 자세" 로 쓰고,
 * - `build-gear-parts.mjs` 가 T 포즈 장비를 옮기고 장비 스킨의 역바인드를 만들 때 쓴다.
 */

// 방향을 재는 자식 — 뼈 이름 → 자식 이름. 없는 뼈(손·머리·발가락·Root)는 돌리지 않는다
const AIM = {
  Hips: 'Spine', Spine: 'Spine1', Spine1: 'Spine2', Spine2: 'Neck', Neck: 'Head',
  LeftShoulder: 'LeftArm', LeftArm: 'LeftForeArm', LeftForeArm: 'LeftHand',
  RightShoulder: 'RightArm', RightArm: 'RightForeArm', RightForeArm: 'RightHand',
  LeftUpLeg: 'LeftLeg', LeftLeg: 'LeftFoot', LeftFoot: 'LeftToeBase',
  RightUpLeg: 'RightLeg', RightLeg: 'RightFoot', RightFoot: 'RightToeBase',
};

export const qmul = (a, b) => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
];
const qnorm = (q) => {
  const l = Math.hypot(...q) || 1;
  return q.map((v) => v / l);
};
export const qrot = (q, v) => {
  const p = qmul(qmul(q, [v[0], v[1], v[2], 0]), [-q[0], -q[1], -q[2], q[3]]);
  return [p[0], p[1], p[2]];
};
const unit = (v) => {
  const l = Math.hypot(...v) || 1;
  return v.map((x) => x / l);
};
// a 를 b 로 돌리는 가장 짧은 회전
function fromTo(a, b) {
  const d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  if (d < -0.999999) return [1, 0, 0, 0];
  return qnorm([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0], 1 + d]);
}

const rest = (n, path) => n[path] ?? (path === 'rotation' ? [0, 0, 0, 1] : path === 'scale' ? [1, 1, 1] : [0, 0, 0]);

/** 노드마다 월드 회전·자리·크기 (기본 자세). `swing(i, q, p)` 가 돌려준 회전을 그 뼈 월드 회전 앞에 곱한다 */
export function worldRest(nodes, swing = () => null) {
  const parent = new Map();
  nodes.forEach((n, i) => (n.children ?? []).forEach((c) => parent.set(c, i)));
  const out = new Map();
  const walk = (i) => {
    if (out.has(i)) return out.get(i);
    const p = parent.get(i);
    const up = p === undefined ? { q: [0, 0, 0, 1], p: [0, 0, 0], s: 1 } : walk(p);
    const t = qrot(up.q, rest(nodes[i], 'translation')).map((v) => v * up.s);
    let q = qnorm(qmul(up.q, rest(nodes[i], 'rotation')));
    const pos = up.p.map((v, k) => v + t[k]);
    const turn = swing(i, q);
    if (turn) q = qnorm(qmul(turn, q));
    const g = { q, p: pos, s: up.s * rest(nodes[i], 'scale')[0] };
    out.set(i, g);
    return g;
  };
  nodes.forEach((_, i) => walk(i));
  return out;
}

/**
 * `nodes` 뼈대를 `ref` 뼈대의 뼈 방향에 맞춘 가상 기본 자세 — 노드 번호 → { q, p, s } (월드).
 * 이름이 `ref` 에 없거나 `AIM` 에 없는 뼈는 부모를 따라갈 뿐 스스로 돌지 않는다.
 */
export function alignedRest(nodes, ref) {
  const refIndex = new Map(ref.map((n, i) => [n.name, i]));
  const refWorld = worldRest(ref);
  const aimOf = (list, i) => {
    const child = AIM[list[i].name];
    if (!child) return null;
    const c = (list[i].children ?? []).find((k) => list[k].name === child);
    return c === undefined ? null : rest(list[c], 'translation');
  };
  return worldRest(nodes, (i, q) => {
    const r = refIndex.get(nodes[i].name);
    const mine = aimOf(nodes, i);
    const theirs = r === undefined ? null : aimOf(ref, r);
    if (!mine || !theirs) return null;
    return fromTo(unit(qrot(q, mine)), unit(qrot(refWorld.get(r).q, theirs)));
  });
}

/** { q, p, s } → 열 우선 4×4 (glTF 행렬 순서) */
export function matrixOf({ q, p, s }) {
  const [x, y, z, w] = q;
  return [
    (1 - 2 * (y * y + z * z)) * s, 2 * (x * y + z * w) * s, 2 * (x * z - y * w) * s, 0,
    2 * (x * y - z * w) * s, (1 - 2 * (x * x + z * z)) * s, 2 * (y * z + x * w) * s, 0,
    2 * (x * z + y * w) * s, 2 * (y * z - x * w) * s, (1 - 2 * (x * x + y * y)) * s, 0,
    p[0], p[1], p[2], 1,
  ];
}
