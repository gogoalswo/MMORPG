/**
 * 캐릭터 GLB 의 뼈마다 **그 뼈에 묶인 정점**의 상자를 뼈 좌표로 잰다.
 *
 *   node scripts/measure-bones.mjs public/assets/models/varco_fighter.glb [뼈 이름 ...]
 *
 * 무기·장비를 뼈에 붙일 때(`BoneAttachment3D`) 어디에 얼마만 한 크기로 둘지를 정한다.
 * 가중치 0.5 넘게 그 뼈에 묶인 정점만 센다. 좌표는 **바인드 자세의 뼈 좌표**
 * (inverseBindMatrix 를 곱한 것)이고 단위는 모델 단위다 (게임에서 1.85배쯤 커진다).
 * 모델을 갈아 끼우면 `gauntlet.gd` 의 `FIST_*` · `armor.gd` 의 `FIT` 를 이걸로 다시 잰다.
 */
import { readFileSync } from 'node:fs';

const posed = process.argv.includes('--posed');
const [path, ...only] = process.argv.slice(2).filter((a) => a !== '--posed');
const buf = readFileSync(path);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const bin = buf.subarray(28 + jsonLen);
const SIZE = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };

function read(index) {
  const acc = json.accessors[index];
  const view = json.bufferViews[acc.bufferView];
  const n = SIZE[acc.type];
  const bytes = { 5126: 4, 5123: 2, 5121: 1, 5125: 4 }[acc.componentType];
  const stride = view.byteStride ?? n * bytes;
  const start = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
  const out = new Float64Array(acc.count * n);
  for (let i = 0; i < acc.count; i += 1)
    for (let k = 0; k < n; k += 1) {
      const at = start + i * stride + k * bytes;
      let v = acc.componentType === 5126 ? bin.readFloatLE(at) : acc.componentType === 5123 ? bin.readUInt16LE(at) : acc.componentType === 5121 ? bin.readUInt8(at) : bin.readUInt32LE(at);
      if (acc.normalized) v /= acc.componentType === 5123 ? 65535 : 255;
      out[i * n + k] = v;
    }
  return out;
}

const skin = json.skins[0];
const ibm = read(skin.inverseBindMatrices);

// --posed: 정점을 **기본 자세(노드 TRS)로 스키닝한 뒤** 뼈 좌표로 잰다. 손가락을 말아 둔 모델
// (`curl-fingers.mjs`)은 바인드 자세가 편 손이라, 이걸 안 쓰면 편 손 크기가 나온다
const mat = (n) => {
  const [x, y, z, w] = n.rotation ?? [0, 0, 0, 1];
  const [tx, ty, tz] = n.translation ?? [0, 0, 0];
  const [sx, sy, sz] = n.scale ?? [1, 1, 1];
  return [
    (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0,
    2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0,
    2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
    tx, ty, tz, 1,
  ];
};
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c += 1) for (let r = 0; r < 4; r += 1) for (let k = 0; k < 4; k += 1) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return o;
};
const parent = new Map();
json.nodes.forEach((n, i) => (n.children ?? []).forEach((c) => parent.set(c, i)));
const world = (i) => (parent.has(i) ? mul(world(parent.get(i)), mat(json.nodes[i])) : mat(json.nodes[i]));
const jointWorld = skin.joints.map((j) => world(j));
// 스키닝 행렬 = 월드 · 역바인드, 그리고 뼈 좌표로 되돌릴 역월드
const skinMat = skin.joints.map((_, k) => mul(jointWorld[k], Array.from(ibm.subarray(k * 16, k * 16 + 16))));
const invert = (m) => {
  // 강체+균일 배율이라고 보고 전치로 뒤집는다
  const s2 = m[0] * m[0] + m[1] * m[1] + m[2] * m[2];
  const r = [m[0], m[4], m[8], 0, m[1], m[5], m[9], 0, m[2], m[6], m[10], 0, 0, 0, 0, 1].map((v, i) => (i % 4 < 3 && i < 12 ? v / s2 : v));
  const t = [0, 1, 2].map((row) => -(r[row] * m[12] + r[4 + row] * m[13] + r[8 + row] * m[14]));
  return [r[0], r[1], r[2], 0, r[4], r[5], r[6], 0, r[8], r[9], r[10], 0, t[0], t[1], t[2], 1];
};
const jointInv = jointWorld.map(invert);
const apply = (m, p) => [0, 1, 2].map((r) => m[r] * p[0] + m[4 + r] * p[1] + m[8 + r] * p[2] + m[12 + r]);
const names = skin.joints.map((j) => json.nodes[j].name);
const boxes = names.map(() => ({ min: [Infinity, Infinity, Infinity], max: [-Infinity, -Infinity, -Infinity], sum: [0, 0, 0], n: 0 }));

for (const mesh of json.meshes)
  for (const prim of mesh.primitives) {
    const pos = read(prim.attributes.POSITION);
    const joints = read(prim.attributes.JOINTS_0);
    const weights = read(prim.attributes.WEIGHTS_0);
    for (let v = 0; v < pos.length / 3; v += 1)
      for (let k = 0; k < 4; k += 1) {
        if (weights[v * 4 + k] <= 0.5) continue;
        const j = joints[v * 4 + k];
        const m = ibm.subarray(j * 16, j * 16 + 16); // 열 우선
        const [x, y, z] = [pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]];
        let p = [0, 1, 2].map((r) => m[r] * x + m[4 + r] * y + m[8 + r] * z + m[12 + r]);
        let into = j;
        if (posed) {
          // 손가락 뼈 정점은 그 손 몫으로 센다 — 주먹 전체의 상자가 필요하다
          const side = /_([LR])_Finger/.exec(names[j]);
          if (side) into = names.indexOf(side[1] === 'R' ? 'RightHand' : 'LeftHand');
          const moved = [0, 0, 0];
          for (let q = 0; q < 4; q += 1) {
            const w = weights[v * 4 + q];
            if (!w) continue;
            apply(skinMat[joints[v * 4 + q]], [x, y, z]).forEach((c, i) => (moved[i] += c * w));
          }
          p = apply(jointInv[into], moved);
        }
        const b = boxes[into];
        p.forEach((c, i) => ((b.min[i] = Math.min(b.min[i], c)), (b.max[i] = Math.max(b.max[i], c)), (b.sum[i] += c)));
        b.n += 1;
      }
  }

const f = (a) => `(${a.map((v) => v.toFixed(3)).join(', ')})`;
names.forEach((name, j) => {
  const b = boxes[j];
  if (!b.n || (only.length && !only.includes(name))) return;
  const center = b.min.map((v, i) => (v + b.max[i]) / 2);
  const half = b.min.map((v, i) => (b.max[i] - v) / 2);
  console.log(`${name.padEnd(14)} 정점 ${String(b.n).padStart(5)}  가운데 ${f(center)}  반 크기 ${f(half)}`);
});
