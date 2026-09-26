/**
 * 바르코로 뽑은 **장비 입은 격투가**에서 갑옷·투구·신발만 떼어 **우리 몸의 뼈대로 옮긴다**.
 *
 *   node scripts/build-gear-parts.mjs <출력.glb> <몸.glb> <장비 입은 몸(리깅).glb> [--tex 1024]
 *
 * 2026-09-26 요청: "지금 몸에 등급 아이콘 파츠별로 바르코에 넣어서 모델 만들도록 해" — 외형은 코드로
 * 짓지 않는다 (CLAUDE.md). 등급마다 바르코가 **몸 그림 + 그 등급 아이콘 셋**으로 장비를 갖춰 입은
 * 격투가를 뽑고(`humanoid-fingers` 리깅), 이 스크립트가 부위를 떼어 `gear_g<등급>.glb` 로 싼다.
 *
 * - **부위는 장비 모델의 뼈 가중치로 고른다** — 투구 = 머리 뼈(얼굴째. 우리 몸 머리는 게임에서 숨긴다),
 *   신발 = 정강이·발·발가락 뼈, 갑옷 = 몸통·어깨·위팔 뼈 + 허리선 위 몸통(`armor.gd` 의 규칙과 같다).
 *   세 정점이 다 그 부위인 삼각형만 남긴다.
 * - **정점을 우리 몸의 바인드 자세로 옮긴다.** 두 모델은 같은 그림에서 나와 T 포즈 비율이 거의 같지만
 *   관절 자리가 조금씩 다르다. 정점마다 `Σ w · (우리 뼈 바인드 · 장비 뼈 역바인드)` 를 곱해 뼈에 붙은
 *   자리 그대로 우리 뼈대로 옮기고, 스킨은 **우리 몸의 것**(뼈 순서·역바인드)을 그대로 쓴다.
 *   그래서 게임에서 우리 뼈대에 바로 묶이고 동작도 우리 것을 탄다.
 * - 뼈대 노드는 몸 파일에서 그대로 복사하고, 메시 노드 셋에 부위 이름(`armor` `helmet` `boots`)을 붙인다.
 * - 텍스처는 1024² JPEG 으로 줄인다 (색·노멀).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';

const args = process.argv.slice(2);
const texAt = args.indexOf('--tex');
const TEX = texAt >= 0 ? Number(args[texAt + 1]) : 1024;
const [outPath, basePath, gearPath] = args.filter((_, i) => texAt < 0 || (i !== texAt && i !== texAt + 1));
if (!outPath || !basePath || !gearPath) {
  console.error('사용법: node scripts/build-gear-parts.mjs <출력.glb> <몸.glb> <장비 입은 몸.glb> [--tex 1024]');
  process.exit(1);
}

// 부위 → 뼈 (이름). 갑옷은 가중치 합이 0.3, 나머지는 0.5 를 넘어야 한다
const ARMOR = ['Spine', 'Spine1', 'Spine2', 'LeftShoulder', 'RightShoulder', 'LeftArm', 'RightArm'];
const BOOTS = ['LeftLeg', 'RightLeg', 'LeftFoot', 'RightFoot', 'LeftToeBase', 'RightToeBase'];
const LOWER = ['Hips', 'LeftUpLeg', 'RightUpLeg'];
// 허리선 — 골반 뼈 자리에서 이만큼 위 (armor.gd 의 WAIST 와 같다)
const WAIST = 0.025;

// ---------------------------------------------------------------- glb

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

// 4x4 열 우선
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c += 1) for (let r = 0; r < 4; r += 1) for (let k = 0; k < 4; k += 1) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return o;
};
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

// ---------------------------------------------------------------- 뼈 맞추기

const base = readGlb(basePath);
const gear = readGlb(gearPath);
const baseSkin = base.json.skins[0];
const gearSkin = gear.json.skins[0];
const baseNames = baseSkin.joints.map((j) => base.json.nodes[j].name);
const gearNames = gearSkin.joints.map((j) => gear.json.nodes[j].name);
const baseIbm = read(base, baseSkin.inverseBindMatrices);
const gearIbm = read(gear, gearSkin.inverseBindMatrices);
const mat = (arr, k) => Array.from(arr.subarray(k * 16, k * 16 + 16));
// 장비 뼈 k → 우리 뼈 번호, 그리고 옮기는 행렬 (우리 바인드 · 장비 역바인드)
const toBase = gearNames.map((name) => {
  const at = baseNames.indexOf(name);
  if (at < 0) throw new Error(`장비 모델의 뼈 ${name} 가 몸에 없다 — 둘 다 humanoid-fingers 로 리깅했나`);
  return at;
});
const move = gearNames.map((_, k) => mul(invert(mat(baseIbm, toBase[k])), mat(gearIbm, k)));
// 장비 모델의 골반 뼈 자리 (허리선)
const gearHipsY = invert(mat(gearIbm, gearNames.indexOf('Hips')))[13];

// ---------------------------------------------------------------- 부위 떼기

const mesh = gear.json.meshes[0];
const prim = mesh.primitives[0];
const pos = read(gear, prim.attributes.POSITION);
const nor = read(gear, prim.attributes.NORMAL);
const uv = read(gear, prim.attributes.TEXCOORD_0);
const joints = read(gear, prim.attributes.JOINTS_0);
const weights = read(gear, prim.attributes.WEIGHTS_0);
const index = read(gear, prim.indices);
const count = pos.length / 3;

const on = (v, list) => {
  let s = 0;
  for (let k = 0; k < 4; k += 1) if (list.includes(gearNames[joints[v * 4 + k]])) s += weights[v * 4 + k];
  return s;
};
const part = new Array(count);
for (let v = 0; v < count; v += 1) {
  if (on(v, ['Head']) > 0.5) part[v] = 'helmet';
  else if (on(v, BOOTS) > 0.5) part[v] = 'boots';
  else {
    const a = on(v, ARMOR);
    const torso = a + on(v, LOWER) > 0.9 && pos[v * 3 + 1] - gearHipsY > WAIST;
    part[v] = a > 0.3 || torso ? 'armor' : null;
  }
}

// 정점을 우리 바인드 자세로
const moved = new Float32Array(count * 3);
const movedN = new Float32Array(count * 3);
for (let v = 0; v < count; v += 1) {
  const p = [0, 0, 0];
  const n = [0, 0, 0];
  for (let k = 0; k < 4; k += 1) {
    const w = weights[v * 4 + k];
    if (!w) continue;
    const m = move[joints[v * 4 + k]];
    const [x, y, z] = [pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]];
    const [a, b, c] = [nor[v * 3], nor[v * 3 + 1], nor[v * 3 + 2]];
    for (let r = 0; r < 3; r += 1) {
      p[r] += w * (m[r] * x + m[4 + r] * y + m[8 + r] * z + m[12 + r]);
      n[r] += w * (m[r] * a + m[4 + r] * b + m[8 + r] * c);
    }
  }
  const len = Math.hypot(...n) || 1;
  for (let r = 0; r < 3; r += 1) {
    moved[v * 3 + r] = p[r];
    movedN[v * 3 + r] = n[r] / len;
  }
}

// ---------------------------------------------------------------- 싸기

const views = [];
const accessors = [];
const pushView = (buf, target) => {
  views.push({ data: Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength), target });
  return views.length - 1;
};
const addAcc = (arr, type, componentType, target, minmax) => {
  const view = pushView(arr, target);
  const n = SIZE[type];
  const acc = { bufferView: view, componentType, count: arr.length / n, type };
  if (minmax) {
    acc.min = Array(n).fill(Infinity);
    acc.max = Array(n).fill(-Infinity);
    for (let i = 0; i < arr.length; i += 1) {
      acc.min[i % n] = Math.min(acc.min[i % n], arr[i]);
      acc.max[i % n] = Math.max(acc.max[i % n], arr[i]);
    }
  }
  accessors.push(acc);
  return accessors.length - 1;
};

const meshes = [];
const made = {};
for (const name of ['armor', 'helmet', 'boots']) {
  const remap = new Int32Array(count).fill(-1);
  const keep = [];
  const tris = [];
  for (let t = 0; t < index.length; t += 3) {
    const [a, b, c] = [index[t], index[t + 1], index[t + 2]];
    if (part[a] !== name || part[b] !== name || part[c] !== name) continue;
    for (const v of [a, b, c]) {
      if (remap[v] < 0) {
        remap[v] = keep.length;
        keep.push(v);
      }
      tris.push(remap[v]);
    }
  }
  made[name] = tris.length / 3;
  if (!tris.length) continue;
  const P = new Float32Array(keep.length * 3);
  const N = new Float32Array(keep.length * 3);
  const T = new Float32Array(keep.length * 2);
  const J = new Uint16Array(keep.length * 4);
  const W = new Float32Array(keep.length * 4);
  keep.forEach((v, i) => {
    for (let r = 0; r < 3; r += 1) {
      P[i * 3 + r] = moved[v * 3 + r];
      N[i * 3 + r] = movedN[v * 3 + r];
    }
    T[i * 2] = uv[v * 2];
    T[i * 2 + 1] = uv[v * 2 + 1];
    for (let k = 0; k < 4; k += 1) {
      J[i * 4 + k] = toBase[joints[v * 4 + k]];
      W[i * 4 + k] = weights[v * 4 + k];
    }
  });
  const attributes = {
    POSITION: addAcc(P, 'VEC3', 5126, 34962, true),
    NORMAL: addAcc(N, 'VEC3', 5126, 34962),
    TEXCOORD_0: addAcc(T, 'VEC2', 5126, 34962),
    JOINTS_0: addAcc(J, 'VEC4', 5123, 34962),
    WEIGHTS_0: addAcc(W, 'VEC4', 5126, 34962),
  };
  const indices = addAcc(new Uint32Array(tris), 'SCALAR', 5125, 34963);
  meshes.push({ name, primitives: [{ attributes, indices, material: 0 }] });
}

// 텍스처 — 장비 모델의 색·노멀을 줄여 싣는다
const gmat = gear.json.materials[prim.material ?? 0];
const images = [];
const textures = [];
async function addImage(texInfo) {
  if (!texInfo) return undefined;
  const img = gear.json.images[gear.json.textures[texInfo.index].source];
  const view = gear.json.bufferViews[img.bufferView];
  const src = gear.bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
  const jpg = await sharp(src).resize(TEX, TEX).jpeg({ quality: 85 }).toBuffer();
  images.push({ bufferView: pushView(new Uint8Array(jpg)), mimeType: 'image/jpeg' });
  textures.push({ source: images.length - 1 });
  return { index: textures.length - 1 };
}
const baseColorTexture = await addImage(gmat.pbrMetallicRoughness?.baseColorTexture);
const normalTexture = await addImage(gmat.normalTexture);
const material = {
  name: 'gear',
  pbrMetallicRoughness: {
    ...(baseColorTexture ? { baseColorTexture } : {}),
    metallicFactor: gmat.pbrMetallicRoughness?.metallicFactor ?? 0,
    roughnessFactor: gmat.pbrMetallicRoughness?.roughnessFactor ?? 0.8,
  },
  ...(normalTexture ? { normalTexture } : {}),
};

// 뼈대 — 몸 파일의 노드를 그대로, 메시 노드만 부위 셋으로 바꾼다
const nodes = base.json.nodes.map((n) => {
  const copy = { ...n };
  delete copy.mesh;
  delete copy.skin;
  return copy;
});
const ibmAcc = addAcc(new Float32Array(baseIbm), 'MAT4', 5126);
const meshNodes = meshes.map((m, i) => {
  nodes.push({ name: m.name, mesh: i, skin: 0 });
  return nodes.length - 1;
});
const sceneRoots = base.json.scenes[base.json.scene ?? 0].nodes.filter((i) => base.json.nodes[i].mesh === undefined);
const json = {
  asset: { version: '2.0', generator: 'build-gear-parts.mjs' },
  scene: 0,
  scenes: [{ nodes: [...sceneRoots, ...meshNodes] }],
  nodes,
  skins: [{ joints: baseSkin.joints, inverseBindMatrices: ibmAcc, ...(baseSkin.skeleton !== undefined ? { skeleton: baseSkin.skeleton } : {}) }],
  meshes,
  materials: [material],
  textures,
  images,
  samplers: [{}],
  accessors,
};
for (const t of textures) t.sampler = 0;

const chunks = [];
let offset = 0;
json.bufferViews = views.map(({ data, target }) => {
  const pad = (4 - (offset % 4)) % 4;
  if (pad) (chunks.push(Buffer.alloc(pad)), (offset += pad));
  const view = { buffer: 0, byteOffset: offset, byteLength: data.length, ...(target ? { target } : {}) };
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
const body = Buffer.concat([head(jsonChunk.length, 0x4e4f534a), jsonChunk, head(binChunk.length, 0x004e4942), binChunk]);
const header = Buffer.alloc(12);
header.writeUInt32LE(0x46546c67, 0);
header.writeUInt32LE(2, 4);
header.writeUInt32LE(12 + body.length, 8);
writeFileSync(outPath, Buffer.concat([header, body]));
console.log(`${outPath}: 갑옷 ${made.armor} · 투구 ${made.helmet} · 신발 ${made.boots} 삼각형 · ${((12 + body.length) / 1048576).toFixed(2)}MB`);
