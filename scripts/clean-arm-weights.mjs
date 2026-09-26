/**
 * 반바지 정점에 묻은 **팔 뼈 가중치를 뗀다** — 캐릭터 GLB 를 제자리에서 고친다.
 *
 *   node scripts/clean-arm-weights.mjs public/assets/models/varco_fighter.glb
 *
 * 2026-09-26: 격투가 몸을 **주먹 쥔 채 팔을 내리고** 뽑은 바르코 모델로 바꿨더니(`align-rest.mjs`)
 * 주먹이 반바지 옆에 붙어 조각돼서, 바르코 리깅이 주먹 옆 반바지 정점을 아래팔·손 뼈에 묶었다.
 * 대기에서 팔을 조금만 벌려도 반바지 옆이 **치마처럼 벌어졌다**.
 *
 * 정점이 반바지인지는 **텍스처 색**으로 가린다: 반바지는 채도 낮은 짙은 회색이고, 피부 윤곽선은
 * 짙어도 붉은 갈색(채도 높음)이라 섞이지 않는다. 반바지 정점에서 팔 뼈(위팔·아래팔·손·손가락)
 * 가중치를 빼고 남은 뼈로 다시 나눈다. 남는 뼈가 없으면 그쪽 허벅지 뼈에 준다.
 * 머리칼·수염도 회색이지만 팔 뼈에 묶이지 않으니 걸리지 않는다.
 *
 * 색만 보면 아래팔 윤곽선의 짙은 점도 반바지로 잡혀 팔에서 가시가 튀었다. 그래서 **반바지에서 번져 나간다**:
 * 팔 가중치가 없는 반바지색 정점에서 시작해, 메시를 따라 반바지색 정점으로만 이어 간다. 팔의 음영은
 * 반바지와 이어져 있지 않으니 안 걸린다. (뼈까지 거리로 가르는 것도 해 봤는데 주먹 옆 반바지가 손 뼈에
 * 더 가까워 막이 남았다.)
 * 반바지 밑단 옆 **허벅지 살**도 주먹에 딸려 나왔다. 살은 색으로 못 가르니 여기는 **뼈까지 거리**로 번진다 —
 * 아래팔·손·손가락 뼈 선분보다 허벅지·골반 뼈 선분에 가까운(`NEAR` 배) 정점으로만, 그리고 **반바지 밑단
 * 아래에서만** — 밑단 위의 살색은 주먹이 반바지에 닿아 칠해진 자리라, 반바지로 넘기면 반바지 옆에
 * 살색 얼룩이 남았다. 그건 주먹에 두고 잇는 삼각형만 끊는다.
 * 주먹과 반바지는 **붙어 조각돼** 둘을 잇는 삼각형이 있다. 팔이 벌어지면 그게 늘어나 검은 막이 되므로
 * 뗀 정점과 팔에 묶인 정점(팔 가중치 0.5 넘게)을 같이 가진 삼각형은 지운다 (빈 삼각형으로 만든다).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';

const path = process.argv[2];
if (!path) {
  console.error('사용법: node scripts/clean-arm-weights.mjs <캐릭터.glb>');
  process.exit(1);
}
// 반바지 색 — HSV 채도·명도가 이 아래
const SHORTS_SAT = 0.25;
const SHORTS_VAL = 0.45;
// 허벅지 살 = 팔 뼈까지 거리 > 다리 뼈까지 거리 × NEAR
const NEAR = 0.8;
// 밑단에서 이만큼 위까지는 허벅지로 본다 (밑단 둘레 정점)
const HEM = 0.01;
const ARM = /^(Left|Right)(Arm|ForeArm|Hand)$|Finger/;

const buf = readFileSync(path);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const bin = buf.subarray(28 + jsonLen);
const view = (acc) => {
  const a = json.accessors[acc];
  const v = json.bufferViews[a.bufferView];
  return { a, off: (v.byteOffset ?? 0) + (a.byteOffset ?? 0), stride: v.byteStride };
};

const skin = json.skins[0];
const names = skin.joints.map((j) => json.nodes[j].name);
const arm = names.map((n) => ARM.test(n));
// 그쪽 허벅지 — 왼 허벅지 뼈가 x 어느 쪽에 있나로 가른다
const leftX = Math.sign(json.nodes.find((n) => n.name === 'LeftUpLeg').translation[0]);
const legOf = (x) => names.indexOf(Math.sign(x) === leftX ? 'LeftUpLeg' : 'RightUpLeg');

const tex = json.images[json.textures[json.materials[0].pbrMetallicRoughness.baseColorTexture.index].source];
const tv = json.bufferViews[tex.bufferView];
const { data: px, info } = await sharp(bin.subarray(tv.byteOffset ?? 0, (tv.byteOffset ?? 0) + tv.byteLength))
  .removeAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });

// 뼈 자리 (바인드) — 역바인드의 역. 뼈마다 크기 1 이라 회전의 전치로 뒤집는다
const ibmV = view(skin.inverseBindMatrices);
const at = names.map((_, k) => {
  const m = [...Array(16)].map((_, i) => bin.readFloatLE(ibmV.off + (k * 16 + i) * 4));
  return [0, 1, 2].map((c) => -(m[c * 4] * m[12] + m[c * 4 + 1] * m[13] + m[c * 4 + 2] * m[14]));
});
const bone = (n) => at[names.indexOf(n)];
const sideArm = (s) => [
  [`${s}ForeArm`, `${s}Hand`],
  ...names.filter((n) => n.includes(`_${s[0]}_Finger`)).map((n) => [`${s}Hand`, n]),
];
const ARM_SEGS = [...sideArm('Left'), ...sideArm('Right')].map(([a, b]) => [bone(a), bone(b)]);
const LEG_SEGS = [['Hips', 'LeftUpLeg'], ['Hips', 'RightUpLeg'], ['LeftUpLeg', 'LeftLeg'], ['RightUpLeg', 'RightLeg']]
  .map(([a, b]) => [bone(a), bone(b)]);
const distTo = (p, list) =>
  Math.min(
    ...list.map(([a, b]) => {
      const ab = b.map((v, i) => v - a[i]);
      const ap = p.map((v, i) => v - a[i]);
      const l2 = ab.reduce((s, v) => s + v * v, 0) || 1;
      const t = Math.min(1, Math.max(0, ap.reduce((s, v, i) => s + v * ab[i], 0) / l2));
      return Math.hypot(...ap.map((v, i) => v - ab[i] * t));
    }),
  );

let cleaned = 0;
let cut = 0;
for (const prim of json.meshes.flatMap((m) => m.primitives)) {
  const W = view(prim.attributes.WEIGHTS_0);
  const J = view(prim.attributes.JOINTS_0);
  const T = view(prim.attributes.TEXCOORD_0);
  const P = view(prim.attributes.POSITION);
  if (W.a.componentType !== 5126 || J.a.componentType !== 5123) throw new Error('가중치 float · 뼈 번호 ushort 만 다룬다');
  const I = view(prim.indices);
  const size = { 5125: 4, 5123: 2 }[I.a.componentType];
  const get = (i) => (size === 4 ? bin.readUInt32LE(I.off + i * 4) : bin.readUInt16LE(I.off + i * 2));
  const put = (i, v) => (size === 4 ? bin.writeUInt32LE(v, I.off + i * 4) : bin.writeUInt16LE(v, I.off + i * 2));
  const count = W.a.count;
  const weightsOf = (v) => [0, 1, 2, 3].map((k) => bin.readFloatLE(W.off + v * 16 + k * 4));
  const jointsOf = (v) => [0, 1, 2, 3].map((k) => bin.readUInt16LE(J.off + v * 8 + k * 2));
  const posOf = (v) => [0, 1, 2].map((c) => bin.readFloatLE(P.off + v * 12 + c * 4));
  const armW = new Float32Array(count);
  const shorts = new Uint8Array(count);
  for (let v = 0; v < count; v += 1) {
    const w = weightsOf(v);
    const j = jointsOf(v);
    armW[v] = w.reduce((s, x, k) => s + (arm[j[k]] ? x : 0), 0);
    const u = bin.readFloatLE(T.off + v * 8);
    const t = bin.readFloatLE(T.off + v * 8 + 4);
    const x = Math.min(info.width - 1, Math.max(0, Math.floor((u - Math.floor(u)) * info.width)));
    const y = Math.min(info.height - 1, Math.max(0, Math.floor((t - Math.floor(t)) * info.height)));
    const [r, g, b] = [0, 1, 2].map((c) => px[(y * info.width + x) * 3 + c] / 255);
    const max = Math.max(r, g, b);
    const sat = max ? (max - Math.min(r, g, b)) / max : 0;
    shorts[v] = sat <= SHORTS_SAT && max <= SHORTS_VAL ? 1 : 0;
  }
  // 이웃 — UV 이음매에서 갈라진 같은 자리 정점은 하나로 본다
  const same = new Map();
  const key = (v) => posOf(v).map((c) => Math.round(c * 1e5)).join(',');
  const group = new Int32Array(count);
  for (let v = 0; v < count; v += 1) {
    const k = key(v);
    if (!same.has(k)) same.set(k, same.size);
    group[v] = same.get(k);
  }
  const members = [...Array(same.size)].map(() => []);
  for (let v = 0; v < count; v += 1) members[group[v]].push(v);
  const near = [...Array(same.size)].map(() => new Set());
  for (let f = 0; f < I.a.count; f += 3) {
    const tri = [get(f), get(f + 1), get(f + 2)].map((v) => group[v]);
    for (const a of tri) for (const b of tri) if (a !== b) near[a].add(b);
  }
  // 팔 가중치 없는 정점에서 번진다 — ok(무리) 인 이웃으로만
  const spread = (ok) => {
    const seen = new Uint8Array(same.size);
    const queue = [];
    for (let v = 0; v < count; v += 1)
      if (ok(group[v]) && armW[v] === 0 && !seen[group[v]]) {
        seen[group[v]] = 1;
        queue.push(group[v]);
      }
    while (queue.length) {
      const g = queue.pop();
      for (const n of near[g])
        if (!seen[n] && ok(n)) {
          seen[n] = 1;
          queue.push(n);
        }
    }
    return seen;
  };
  const cloth = spread((g) => members[g].some((v) => shorts[v]));
  // 밑단 — 허벅지 뼈보다 바깥쪽 반바지 정점 중 가장 낮은 것 (주먹이 닿는 쪽이 바깥이다).
  // 가장 낮은 것 대신 아래에서 3% 자리 — 짙은 윤곽선을 타고 무릎·발끝까지 번진 조각이 있다
  const legX = Math.abs(bone('LeftUpLeg')[0]);
  const ys = [];
  for (let g = 0; g < same.size; g += 1) {
    const p = posOf(members[g][0]);
    if (cloth[g] && Math.abs(p[0]) > legX) ys.push(p[1]);
  }
  const hem = ys.sort((a, b) => a - b)[Math.floor(ys.length * 0.03)];
  const thigh = spread((g) => {
    const p = posOf(members[g][0]);
    return p[1] < hem + HEM && distTo(p, ARM_SEGS) > distTo(p, LEG_SEGS) * NEAR;
  });
  const seen = cloth.map((c, g) => c | thigh[g]);
  const gone = new Uint8Array(count);
  for (let v = 0; v < count; v += 1) {
    if (!seen[group[v]] || armW[v] <= 0) continue;
    const w = weightsOf(v);
    const j = jointsOf(v);
    const keep = w.map((x, k) => (arm[j[k]] ? 0 : x));
    const sum = keep.reduce((s, x) => s + x, 0);
    if (sum > 1e-4) keep.forEach((x, k) => (keep[k] = x / sum));
    else {
      keep.fill(0);
      keep[0] = 1;
      bin.writeUInt16LE(legOf(posOf(v)[0]), J.off + v * 8);
    }
    keep.forEach((x, k) => bin.writeFloatLE(x, W.off + v * 16 + k * 4));
    gone[v] = 1;
    cleaned += 1;
  }
  // 뗀 정점과 팔에 묶인 정점을 잇는 삼각형 → 빈 삼각형
  for (let f = 0; f < I.a.count; f += 3) {
    const tri = [get(f), get(f + 1), get(f + 2)];
    if (tri.some((v) => gone[v]) && tri.some((v) => armW[v] > 0.5)) {
      tri.forEach((_, k) => put(f + k, tri[0]));
      cut += 1;
    }
  }
}
writeFileSync(path, buf);
console.log(`${path}: 반바지 정점 ${cleaned}개에서 팔 뼈 가중치를 뗐다 · 잇는 삼각형 ${cut}개를 지웠다`);
