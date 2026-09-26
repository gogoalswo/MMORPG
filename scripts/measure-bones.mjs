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

const [path, ...only] = process.argv.slice(2);
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
        const p = [0, 1, 2].map((r) => m[r] * x + m[4 + r] * y + m[8 + r] * z + m[12 + r]);
        const b = boxes[j];
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
