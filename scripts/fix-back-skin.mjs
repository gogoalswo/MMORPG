/**
 * 캐릭터 **등 쪽 살색을 앞쪽 살색에 맞춘다** — 캐릭터 GLB 의 색 텍스처를 제자리에서 고친다.
 *
 *   node scripts/fix-back-skin.mjs public/assets/models/varco_fighter.glb
 *
 * 2026-09-26 "캐릭터 뒷모습 색상이 왜이렇게 빨개". 바르코 `Generate3D` 는 **앞모습 그림 한 장**으로
 * 뒤를 지어내는데, 애니풍 그림의 그림자 색(적갈·주황)을 등 전체에 칠했다. 조명 탓이 아니다 —
 * 같은 빛 아래서 앞은 상아빛, 뒤는 적갈색이었다.
 *
 * - 텍스처 칸마다 **어느 쪽을 보는 면인가**를 잰다 — 삼각형을 UV 에 그려 정점 노멀의 z(모델은 +z 를 본다)를
 *   보간한다.
 * - 살색 칸만 센다: 반바지(채도·명도 낮음)와 머리칼(채도 낮음)은 뺀다.
 * - 앞(z > 0.3)과 뒤(z < -0.3) 살색의 채널별 평균·표준편차를 재서, 뒤 칸을 앞 분포로 옮긴다
 *   (`(c - 뒤평균) / 뒤편차 · 앞편차 + 앞평균`). 근육 윤곽선은 상대 명암이 남아 그대로 보인다.
 *   옆면은 z 에 따라 섞어 경계가 안 보이게 한다.
 * - 모델을 새로 뽑아도 같은 일이 생기므로 짓는 절차(`fetch-assets.sh`)에 넣었다.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';

const path = process.argv[2];
if (!path) {
  console.error('사용법: node scripts/fix-back-skin.mjs <캐릭터.glb>');
  process.exit(1);
}
const FRONT = 0.3;
const BACK = -0.3;
// 섞기 — z 가 SIDE 에서 BACK 으로 갈수록 0 → 1
const SIDE = 0.1;
const JPEG_Q = 88;

const buf = readFileSync(path);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const bin = buf.subarray(28 + jsonLen, 28 + jsonLen + buf.readUInt32LE(20 + jsonLen));
const acc = (i) => {
  const a = json.accessors[i];
  const v = json.bufferViews[a.bufferView];
  const off = (v.byteOffset ?? 0) + (a.byteOffset ?? 0);
  const n = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type];
  if (a.componentType === 5126) return new Float32Array(bin.buffer.slice(bin.byteOffset + off, bin.byteOffset + off + a.count * n * 4));
  if (a.componentType === 5125) return new Uint32Array(bin.buffer.slice(bin.byteOffset + off, bin.byteOffset + off + a.count * 4));
  return new Uint16Array(bin.buffer.slice(bin.byteOffset + off, bin.byteOffset + off + a.count * 2));
};

const texIndex = json.materials[0].pbrMetallicRoughness.baseColorTexture.index;
const image = json.images[json.textures[texIndex].source];
const iv = json.bufferViews[image.bufferView];
const { data: px, info } = await sharp(bin.subarray(iv.byteOffset ?? 0, (iv.byteOffset ?? 0) + iv.byteLength))
  .removeAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });
const W = info.width;
const H = info.height;

// 칸마다 노멀 z (NaN = 어느 삼각형에도 안 덮인 칸)
const facing = new Float32Array(W * H).fill(NaN);
for (const prim of json.meshes.flatMap((m) => m.primitives)) {
  const uv = acc(prim.attributes.TEXCOORD_0);
  const nor = acc(prim.attributes.NORMAL);
  const idx = acc(prim.indices);
  for (let f = 0; f < idx.length; f += 3) {
    const t = [idx[f], idx[f + 1], idx[f + 2]];
    const x = t.map((v) => uv[v * 2] * W);
    const y = t.map((v) => uv[v * 2 + 1] * H);
    const z = t.map((v) => nor[v * 3 + 2]);
    const area = (x[1] - x[0]) * (y[2] - y[0]) - (x[2] - x[0]) * (y[1] - y[0]);
    if (Math.abs(area) < 1e-9) continue;
    const x0 = Math.max(0, Math.floor(Math.min(...x)));
    const x1 = Math.min(W - 1, Math.ceil(Math.max(...x)));
    const y0 = Math.max(0, Math.floor(Math.min(...y)));
    const y1 = Math.min(H - 1, Math.ceil(Math.max(...y)));
    for (let py = y0; py <= y1; py += 1)
      for (let pxl = x0; pxl <= x1; pxl += 1) {
        const cx = pxl + 0.5;
        const cy = py + 0.5;
        const a = ((x[1] - cx) * (y[2] - cy) - (x[2] - cx) * (y[1] - cy)) / area;
        const b = ((x[2] - cx) * (y[0] - cy) - (x[0] - cx) * (y[2] - cy)) / area;
        const c = 1 - a - b;
        if (a < -0.01 || b < -0.01 || c < -0.01) continue;
        facing[py * W + pxl] = a * z[0] + b * z[1] + c * z[2];
      }
  }
}

const skin = (i) => {
  const r = px[i * 3] / 255;
  const g = px[i * 3 + 1] / 255;
  const b = px[i * 3 + 2] / 255;
  const max = Math.max(r, g, b);
  const sat = max ? (max - Math.min(r, g, b)) / max : 0;
  return sat > 0.25 && r >= b;
};
const stats = (pick) => {
  const sum = [0, 0, 0];
  const sq = [0, 0, 0];
  let n = 0;
  for (let i = 0; i < W * H; i += 1) {
    if (!pick(facing[i]) || !skin(i)) continue;
    for (let c = 0; c < 3; c += 1) {
      sum[c] += px[i * 3 + c];
      sq[c] += px[i * 3 + c] ** 2;
    }
    n += 1;
  }
  const mean = sum.map((s) => s / n);
  return { n, mean, sd: sq.map((s, c) => Math.sqrt(Math.max(1, s / n - mean[c] ** 2))) };
};
const front = stats((z) => z > FRONT);
const back = stats((z) => z < BACK);

let changed = 0;
for (let i = 0; i < W * H; i += 1) {
  const z = facing[i];
  if (!(z < SIDE) || !skin(i)) continue;
  const w = Math.min(1, (SIDE - z) / (SIDE - BACK));
  for (let c = 0; c < 3; c += 1) {
    const v = px[i * 3 + c];
    const to = ((v - back.mean[c]) / back.sd[c]) * front.sd[c] + front.mean[c];
    px[i * 3 + c] = Math.round(Math.min(255, Math.max(0, v + (to - v) * w)));
  }
  changed += 1;
}
const jpeg = await sharp(px, { raw: { width: W, height: H, channels: 3 } }).jpeg({ quality: JPEG_Q }).toBuffer();

// 텍스처 조각만 갈아 끼우고 뒤 조각들을 민다
const pad = (b) => Buffer.concat([b, Buffer.alloc((4 - (b.length % 4)) % 4)]);
const parts = json.bufferViews.map((v, k) =>
  k === image.bufferView ? jpeg : bin.subarray(v.byteOffset ?? 0, (v.byteOffset ?? 0) + v.byteLength),
);
let at = 0;
const chunks = parts.map((p, k) => {
  json.bufferViews[k].byteOffset = at;
  json.bufferViews[k].byteLength = p.length;
  const padded = pad(p);
  at += padded.length;
  return padded;
});
image.mimeType = 'image/jpeg';
json.buffers[0].byteLength = at;
const outJson = Buffer.from(JSON.stringify(json), 'utf8');
const jsonChunk = Buffer.concat([outJson, Buffer.alloc((4 - (outJson.length % 4)) % 4, 0x20)]);
const binChunk = Buffer.concat(chunks);
const head = Buffer.alloc(12);
head.writeUInt32LE(0x46546c67, 0);
head.writeUInt32LE(2, 4);
head.writeUInt32LE(12 + 8 + jsonChunk.length + 8 + binChunk.length, 8);
const ch = (len, type) => {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(len, 0);
  b.writeUInt32LE(type, 4);
  return b;
};
writeFileSync(path, Buffer.concat([head, ch(jsonChunk.length, 0x4e4f534a), jsonChunk, ch(binChunk.length, 0x004e4942), binChunk]));
const f = (s) => s.mean.map((v) => v.toFixed(0)).join(',');
console.log(`${path}: 등 살색 ${f(back)} → 앞 ${f(front)} 로 옮겼다 (칸 ${changed})`);
