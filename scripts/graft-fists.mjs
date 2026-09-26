/**
 * 바르코가 **주먹을 조각한** 모델에서 손만 떼어 격투가 몸에 **이식한다** — 몸 GLB 를 제자리에서 고친다.
 *
 *   node scripts/graft-fists.mjs public/assets/models/varco_fighter.glb <주먹 모델(리깅).glb> [--tex 1024]
 *
 * 왜: `Generate3D`(`tPose` 1)는 주먹 쥔 그림을 넣어도 **손을 펴서** 만든다. 편 손가락을 뼈로 말았더니
 * (`curl-fingers.mjs`) 뭉개진 덩어리가 **발굽·발가락처럼** 보였다 (2026-09-26 지적: "주먹 쥔 손이
 * 이상한데?? 꼭 발 같은데?"). 그래서 같은 그림을 **T 포즈 없이** 한 번 더 만들어(손이 주먹 모양으로
 * 조각된다) `humanoid-fingers` 로 리깅하고, 거기서 손만 가져온다.
 *
 * - 주먹 모델에서 손 뼈 + 손가락 뼈에 묶인 가중치 합이 `CUT` 를 넘는 정점을 뗀다 (손목을 조금 넘겨
 *   떼어 이음새를 덮는다).
 * - **손 뼈에 딱딱하게 붙인다** — 정점을 `우리 손 뼈 바인드 · 주먹 모델 손 뼈 역바인드` 로 옮기고 가중치는
 *   손 뼈 하나에 1. 주먹 모델의 손가락 뼈는 주먹 모양으로 굳어 있고, 동작도 손가락을 움직이지 않는다.
 * - 몸 메시에서는 손 뼈 + 손가락 뼈에 절반 넘게 묶인 정점이 낀 삼각형을 뺀다 (편 손을 숨긴다).
 * - 주먹 메시는 `fists` 노드로 몸과 같은 스킨에 붙이고, 재질은 주먹 모델의 텍스처(1024 JPEG)다.
 * 모델을 바꾸면 건틀릿 `FIST_*` 를 다시 잰다 (`measure-bones.mjs <glb> RightHand`).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';

const args = process.argv.slice(2);
const texAt = args.indexOf('--tex');
const TEX = texAt >= 0 ? Number(args[texAt + 1]) : 1024;
const [basePath, fistPath] = args.filter((_, i) => texAt < 0 || (i !== texAt && i !== texAt + 1));
if (!basePath || !fistPath) {
  console.error('사용법: node scripts/graft-fists.mjs <몸.glb> <주먹 모델.glb> [--tex 1024]');
  process.exit(1);
}
// 손을 떼는 문턱 — 손 뼈 + 손가락 뼈 가중치 합. 0.5 보다 낮춰 손목 이음새를 덮는다
const CUT = 0.35;
const isHand = (name, side) => name === `${side}Hand` || new RegExp(`_${side[0]}_Finger`).test(name);

function readGlb(path) {
  const src = readFileSync(path);
  let json = null;
  let bin = Buffer.alloc(0);
  for (let at = 12; at + 8 <= src.length; ) {
    const length = src.readUInt32LE(at);
    const type = src.readUInt32LE(at + 4);
    const data = src.subarray(at + 8, at + 8 + length);
    if (type === 0x4e4f534a) json = JSON.parse(data.toString('utf8'));
    else if (type === 0x004e4942) bin = data;
    at += 8 + length;
  }
  return { json, bin };
}
const SIZE = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
function read(file, index) {
  const acc = file.json.accessors[index];
  const view = file.json.bufferViews[acc.bufferView];
  const n = SIZE[acc.type];
  const bytes = { 5126: 4, 5125: 4, 5123: 2, 5121: 1 }[acc.componentType];
  const stride = view.byteStride ?? n * bytes;
  const start = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
  const out = new Float64Array(acc.count * n);
  for (let i = 0; i < acc.count; i += 1)
    for (let k = 0; k < n; k += 1) {
      const at = start + i * stride + k * bytes;
      let v =
        acc.componentType === 5126 ? file.bin.readFloatLE(at)
        : acc.componentType === 5125 ? file.bin.readUInt32LE(at)
        : acc.componentType === 5123 ? file.bin.readUInt16LE(at)
        : file.bin.readUInt8(at);
      if (acc.normalized) v /= acc.componentType === 5123 ? 65535 : 255;
      out[i * n + k] = v;
    }
  return out;
}
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c += 1) for (let r = 0; r < 4; r += 1) for (let k = 0; k < 4; k += 1) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return o;
};
// 4x4 역행렬 (열 우선) — build-gear-parts.mjs 와 같다. 강체 가정으로 전치해 뒤집었다가 행·열을 뒤바꿔
// 손이 엉뚱한 데로 갔다 (T 포즈 팔은 크게 돌아가 있어서 티가 났다)
function invert(m) {
  const a = m;
  const inv = new Array(16);
  inv[0] = a[5] * a[10] * a[15] - a[5] * a[11] * a[14] - a[9] * a[6] * a[15] + a[9] * a[7] * a[14] + a[13] * a[6] * a[11] - a[13] * a[7] * a[10];
  inv[4] = -a[4] * a[10] * a[15] + a[4] * a[11] * a[14] + a[8] * a[6] * a[15] - a[8] * a[7] * a[14] - a[12] * a[6] * a[11] + a[12] * a[7] * a[10];
  inv[8] = a[4] * a[9] * a[15] - a[4] * a[11] * a[13] - a[8] * a[5] * a[15] + a[8] * a[7] * a[13] + a[12] * a[5] * a[11] - a[12] * a[7] * a[9];
  inv[12] = -a[4] * a[9] * a[14] + a[4] * a[10] * a[13] + a[8] * a[5] * a[14] - a[8] * a[6] * a[13] - a[12] * a[5] * a[10] + a[12] * a[6] * a[9];
  inv[1] = -a[1] * a[10] * a[15] + a[1] * a[11] * a[14] + a[9] * a[2] * a[15] - a[9] * a[3] * a[14] - a[13] * a[2] * a[11] + a[13] * a[3] * a[10];
  inv[5] = a[0] * a[10] * a[15] - a[0] * a[11] * a[14] - a[8] * a[2] * a[15] + a[8] * a[3] * a[14] + a[12] * a[2] * a[11] - a[12] * a[3] * a[10];
  inv[9] = -a[0] * a[9] * a[15] + a[0] * a[11] * a[13] + a[8] * a[1] * a[15] - a[8] * a[3] * a[13] - a[12] * a[1] * a[11] + a[12] * a[3] * a[9];
  inv[13] = a[0] * a[9] * a[14] - a[0] * a[10] * a[13] - a[8] * a[1] * a[14] + a[8] * a[2] * a[13] + a[12] * a[1] * a[10] - a[12] * a[2] * a[9];
  inv[2] = a[1] * a[6] * a[15] - a[1] * a[7] * a[14] - a[5] * a[2] * a[15] + a[5] * a[3] * a[14] + a[13] * a[2] * a[7] - a[13] * a[3] * a[6];
  inv[6] = -a[0] * a[6] * a[15] + a[0] * a[7] * a[14] + a[4] * a[2] * a[15] - a[4] * a[3] * a[14] - a[12] * a[2] * a[7] + a[12] * a[3] * a[6];
  inv[10] = a[0] * a[5] * a[15] - a[0] * a[7] * a[13] - a[4] * a[1] * a[15] + a[4] * a[3] * a[13] + a[12] * a[1] * a[7] - a[12] * a[3] * a[5];
  inv[14] = -a[0] * a[5] * a[14] + a[0] * a[6] * a[13] + a[4] * a[1] * a[14] - a[4] * a[2] * a[13] - a[12] * a[1] * a[6] + a[12] * a[2] * a[5];
  inv[3] = -a[1] * a[6] * a[11] + a[1] * a[7] * a[10] + a[5] * a[2] * a[11] - a[5] * a[3] * a[10] - a[9] * a[2] * a[7] + a[9] * a[3] * a[6];
  inv[7] = a[0] * a[6] * a[11] - a[0] * a[7] * a[10] - a[4] * a[2] * a[11] + a[4] * a[3] * a[10] + a[8] * a[2] * a[7] - a[8] * a[3] * a[6];
  inv[11] = -a[0] * a[5] * a[11] + a[0] * a[7] * a[9] + a[4] * a[1] * a[11] - a[4] * a[3] * a[9] - a[8] * a[1] * a[7] + a[8] * a[3] * a[5];
  inv[15] = a[0] * a[5] * a[10] - a[0] * a[6] * a[9] - a[4] * a[1] * a[10] + a[4] * a[2] * a[9] + a[8] * a[1] * a[6] - a[8] * a[2] * a[5];
  const det = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12];
  return inv.map((v) => v / det);
}

const base = readGlb(basePath);
const fist = readGlb(fistPath);
if (base.json.nodes.some((n) => n.name === 'fists')) throw new Error(`${basePath}: 이미 주먹을 이식했다 — 몸부터 다시 지어라`);
const baseSkin = base.json.skins[0];
const fistSkin = fist.json.skins[0];
const baseNames = baseSkin.joints.map((j) => base.json.nodes[j].name);
const fistNames = fistSkin.joints.map((j) => fist.json.nodes[j].name);
const baseIbm = read(base, baseSkin.inverseBindMatrices);
const fistIbm = read(fist, fistSkin.inverseBindMatrices);
const mat = (arr, k) => Array.from(arr.subarray(k * 16, k * 16 + 16));

// ---------------------------------------------------------------- 주먹 떼기

const fp = fist.json.meshes[0].primitives[0];
const fPos = read(fist, fp.attributes.POSITION);
const fNor = read(fist, fp.attributes.NORMAL);
const fUv = read(fist, fp.attributes.TEXCOORD_0);
const fJ = read(fist, fp.attributes.JOINTS_0);
const fW = read(fist, fp.attributes.WEIGHTS_0);
const fIdx = read(fist, fp.indices);
const fCount = fPos.length / 3;
const sideOf = new Array(fCount).fill(null);
for (let v = 0; v < fCount; v += 1)
  for (const side of ['Right', 'Left']) {
    let s = 0;
    for (let k = 0; k < 4; k += 1) if (isHand(fistNames[fJ[v * 4 + k]], side)) s += fW[v * 4 + k];
    if (s > CUT) sideOf[v] = side;
  }

const P = [];
const N = [];
const T = [];
const J = [];
const W = [];
const I = [];
const made = { Right: 0, Left: 0 };
for (const side of ['Right', 'Left']) {
  const bi = baseNames.indexOf(`${side}Hand`);
  const fi = fistNames.indexOf(`${side}Hand`);
  const m = mul(invert(mat(baseIbm, bi)), mat(fistIbm, fi));
  const remap = new Map();
  // **가장 큰 한 덩어리만** — 주먹 모델은 주먹이 반바지에 붙어 있어서 반바지 조각도 손 뼈 가중치를 받아
  // 같이 떨어져 왔다 (검은 조각이 주먹 옆에 떴다). 같은 자리 정점을 한 점으로 묶어 이은 덩어리를 센다
  const tris = [];
  for (let t = 0; t < fIdx.length; t += 3) {
    const tri = [fIdx[t], fIdx[t + 1], fIdx[t + 2]];
    if (tri.every((v) => sideOf[v] === side)) tris.push(tri);
  }
  const key = (v) => `${fPos[v * 3].toFixed(5)},${fPos[v * 3 + 1].toFixed(5)},${fPos[v * 3 + 2].toFixed(5)}`;
  const parent = new Map();
  const find = (x) => {
    while (parent.get(x) !== x) {
      parent.set(x, parent.get(parent.get(x)));
      x = parent.get(x);
    }
    return x;
  };
  for (const tri of tris) for (const v of tri) if (!parent.has(key(v))) parent.set(key(v), key(v));
  for (const tri of tris) {
    const a = find(key(tri[0]));
    for (const v of tri.slice(1)) parent.set(find(key(v)), a);
  }
  const size = new Map();
  for (const tri of tris) size.set(find(key(tri[0])), (size.get(find(key(tri[0]))) ?? 0) + 1);
  const biggest = [...size.entries()].sort((p, q) => q[1] - p[1])[0][0];
  for (const tri of tris) {
    if (find(key(tri[0])) !== biggest) continue;
    for (const v of tri) {
      if (!remap.has(v)) {
        remap.set(v, P.length / 3);
        const [x, y, z] = [fPos[v * 3], fPos[v * 3 + 1], fPos[v * 3 + 2]];
        const [a, b, c] = [fNor[v * 3], fNor[v * 3 + 1], fNor[v * 3 + 2]];
        const n = [0, 1, 2].map((r) => m[r] * a + m[4 + r] * b + m[8 + r] * c);
        const len = Math.hypot(...n) || 1;
        for (let r = 0; r < 3; r += 1) {
          P.push(m[r] * x + m[4 + r] * y + m[8 + r] * z + m[12 + r]);
          N.push(n[r] / len);
        }
        T.push(fUv[v * 2], fUv[v * 2 + 1]);
        J.push(bi, 0, 0, 0);
        W.push(1, 0, 0, 0);
      }
      I.push(remap.get(v));
    }
    made[side] += 1;
  }
}
if (!made.Right || !made.Left) throw new Error(`주먹을 못 뗐다 (오른손 ${made.Right} · 왼손 ${made.Left})`);

// ---------------------------------------------------------------- 몸에서 편 손 빼기

const body = base.json.meshes[base.json.nodes.find((n) => n.mesh !== undefined).mesh];
const bp = body.primitives[0];
const bJ = read(base, bp.attributes.JOINTS_0);
const bW = read(base, bp.attributes.WEIGHTS_0);
const bIdx = read(base, bp.indices);
const handVert = (v) => {
  let s = 0;
  for (let k = 0; k < 4; k += 1) {
    const name = baseNames[bJ[v * 4 + k]];
    if (isHand(name, 'Right') || isHand(name, 'Left')) s += bW[v * 4 + k];
  }
  return s > 0.5;
};
const keep = [];
let dropped = 0;
for (let t = 0; t < bIdx.length; t += 3) {
  // 세 정점이 다 손일 때만 뺀다 — 하나라도 손이면 빼니 손목 팔뚝이 톱니처럼 파였다 (주먹이 손목을 덮는다)
  if (handVert(bIdx[t]) && handVert(bIdx[t + 1]) && handVert(bIdx[t + 2])) dropped += 1;
  else keep.push(bIdx[t], bIdx[t + 1], bIdx[t + 2]);
}

// ---------------------------------------------------------------- 다시 싸기

const json = base.json;
let views = json.bufferViews.map((v) => ({
  meta: { ...(v.byteStride !== undefined ? { byteStride: v.byteStride } : {}), ...(v.target ? { target: v.target } : {}) },
  data: base.bin.subarray(v.byteOffset ?? 0, (v.byteOffset ?? 0) + v.byteLength),
}));
const addAcc = (arr, type, componentType, target, minmax) => {
  views.push({ meta: target ? { target } : {}, data: Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength) });
  const n = SIZE[type];
  const acc = { bufferView: views.length - 1, componentType, count: arr.length / n, type };
  if (minmax) {
    acc.min = Array(n).fill(Infinity);
    acc.max = Array(n).fill(-Infinity);
    for (let i = 0; i < arr.length; i += 1) {
      acc.min[i % n] = Math.min(acc.min[i % n], arr[i]);
      acc.max[i % n] = Math.max(acc.max[i % n], arr[i]);
    }
  }
  json.accessors.push(acc);
  return json.accessors.length - 1;
};

bp.indices = addAcc(new Uint32Array(keep), 'SCALAR', 5125, 34963);

// 주먹 재질 — 주먹 모델의 색·노멀 텍스처
const fmat = fist.json.materials[fp.material ?? 0];
json.images ??= [];
json.textures ??= [];
json.materials ??= [];
json.samplers ??= [{}];
async function addImage(info) {
  if (!info) return undefined;
  const img = fist.json.images[fist.json.textures[info.index].source];
  const view = fist.json.bufferViews[img.bufferView];
  const src = fist.bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
  const jpg = await sharp(src).resize(TEX, TEX).jpeg({ quality: 85 }).toBuffer();
  views.push({ meta: {}, data: jpg });
  json.images.push({ bufferView: views.length - 1, mimeType: 'image/jpeg' });
  json.textures.push({ source: json.images.length - 1, sampler: 0 });
  return { index: json.textures.length - 1 };
}
const baseColorTexture = await addImage(fmat.pbrMetallicRoughness?.baseColorTexture);
const normalTexture = await addImage(fmat.normalTexture);
json.materials.push({
  name: 'fists',
  pbrMetallicRoughness: {
    ...(baseColorTexture ? { baseColorTexture } : {}),
    metallicFactor: fmat.pbrMetallicRoughness?.metallicFactor ?? 0,
    roughnessFactor: fmat.pbrMetallicRoughness?.roughnessFactor ?? 0.8,
  },
  ...(normalTexture ? { normalTexture } : {}),
});
json.meshes.push({
  name: 'fists',
  primitives: [{
    attributes: {
      POSITION: addAcc(new Float32Array(P), 'VEC3', 5126, 34962, true),
      NORMAL: addAcc(new Float32Array(N), 'VEC3', 5126, 34962),
      TEXCOORD_0: addAcc(new Float32Array(T), 'VEC2', 5126, 34962),
      JOINTS_0: addAcc(new Uint16Array(J), 'VEC4', 5123, 34962),
      WEIGHTS_0: addAcc(new Float32Array(W), 'VEC4', 5126, 34962),
    },
    indices: addAcc(new Uint32Array(I), 'SCALAR', 5125, 34963),
    material: json.materials.length - 1,
  }],
});
json.nodes.push({ name: 'fists', mesh: json.meshes.length - 1, skin: 0 });
json.scenes[json.scene ?? 0].nodes.push(json.nodes.length - 1);

// 옛 몸 인덱스 접근자는 아무도 안 가리키지만 그대로 둔다 (0.3MB 쯤 — 다시 짜면 번호가 흔들린다)
const chunks = [];
let offset = 0;
json.bufferViews = views.map(({ meta, data }) => {
  const pad = (4 - (offset % 4)) % 4;
  if (pad) (chunks.push(Buffer.alloc(pad)), (offset += pad));
  const view = { buffer: 0, byteOffset: offset, byteLength: data.length, ...meta };
  chunks.push(data);
  offset += data.length;
  return view;
});
const bin = Buffer.concat(chunks);
json.buffers = [{ byteLength: bin.length }];
const pad4 = (buf, fill) => {
  const p = (4 - (buf.length % 4)) % 4;
  return p ? Buffer.concat([buf, Buffer.alloc(p, fill)]) : buf;
};
const jsonChunk = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
const binChunk = pad4(bin, 0);
const head = (len, type) => {
  const h = Buffer.alloc(8);
  h.writeUInt32LE(len, 0);
  h.writeUInt32LE(type, 4);
  return h;
};
const out = Buffer.concat([head(jsonChunk.length, 0x4e4f534a), jsonChunk, head(binChunk.length, 0x004e4942), binChunk]);
const header = Buffer.alloc(12);
header.writeUInt32LE(0x46546c67, 0);
header.writeUInt32LE(2, 4);
header.writeUInt32LE(12 + out.length, 8);
writeFileSync(basePath, Buffer.concat([header, out]));
console.log(`${basePath}: 주먹 이식 — 오른손 ${made.Right} · 왼손 ${made.Left} 삼각형, 몸에서 편 손 ${dropped} 삼각형을 뺐다 · ${((12 + out.length) / 1048576).toFixed(2)}MB`);
