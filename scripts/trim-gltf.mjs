/**
 * .glb 에서 필요 없는 애니메이션을 잘라낸다.
 *
 * KayKit 캐릭터 한 개가 3.6MB 인데 그 중 **80% 가 애니메이션**이다 (76개).
 * 우리가 쓰는 건 대기·걷기·달리기·공격·피격·사망 정도라, 안 쓰는 걸 들고 다닐
 * 이유가 없다. 게다가 다섯 캐릭터가 **같은 뼈대**를 쓰므로 애니메이션은
 * 한 파일에만 남기고 나머지는 통째로 비운다.
 *
 *   node scripts/trim-gltf.mjs 입력.glb 출력.glb Idle Walking_A Running_A
 *   node scripts/trim-gltf.mjs 입력.glb 출력.glb --none        # 전부 제거
 *
 * 자르고 나면 참조가 끊긴 accessor / bufferView 가 남으므로, 실제로 쓰이는
 * 것만 골라 바이너리를 다시 싼다. 그냥 JSON 에서 animations 만 지우면
 * 파일 크기는 그대로다.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const [input, output, ...keepArgs] = process.argv.slice(2);
if (!input || !output) {
  console.error('사용법: node scripts/trim-gltf.mjs <입력.glb> <출력.glb> [남길 애니메이션 이름...] | --none');
  process.exit(1);
}
const keepNone = keepArgs.includes('--none');
const keep = new Set(keepArgs.filter((a) => a !== '--none'));

const GLB_MAGIC = 0x46546c67;
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;

// ---------------------------------------------------------------- 읽기

const src = readFileSync(input);
if (src.readUInt32LE(0) !== GLB_MAGIC) throw new Error(`${input}: glb 가 아니다`);

let json = null;
let bin = Buffer.alloc(0);
for (let at = 12; at + 8 <= src.length; ) {
  const length = src.readUInt32LE(at);
  const type = src.readUInt32LE(at + 4);
  const data = src.subarray(at + 8, at + 8 + length);
  if (type === CHUNK_JSON) json = JSON.parse(data.toString('utf8'));
  else if (type === CHUNK_BIN) bin = data;
  at += 8 + length;
}
if (!json) throw new Error(`${input}: JSON 청크가 없다`);

const before = { size: src.length, anims: (json.animations ?? []).length };

// ---------------------------------------------------------------- 애니메이션 선별

// 팩마다 클립 이름 앞에 아마추어 이름이 붙는다 ("AnimalArmature|Idle").
// 부르는 쪽이 그것까지 알 필요는 없으므로 | 뒤만 보고 고른다.
const shortName = (name) => name.slice(name.lastIndexOf('|') + 1);

const kept = keepNone ? [] : (json.animations ?? []).filter((a) => keep.has(shortName(a.name)));
if (!keepNone) {
  const found = new Set(kept.map((a) => shortName(a.name)));
  for (const name of keep) if (!found.has(name)) console.warn(`  ! 없는 애니메이션: ${name}`);
}
if (kept.length > 0) json.animations = kept;
else delete json.animations;

// ---------------------------------------------------------------- 살아남은 accessor 찾기

const liveAccessors = new Set();
const useAccessor = (i) => {
  if (typeof i === 'number') liveAccessors.add(i);
};

for (const mesh of json.meshes ?? []) {
  for (const prim of mesh.primitives ?? []) {
    for (const i of Object.values(prim.attributes ?? {})) useAccessor(i);
    useAccessor(prim.indices);
    for (const target of prim.targets ?? []) for (const i of Object.values(target)) useAccessor(i);
  }
}
for (const skin of json.skins ?? []) useAccessor(skin.inverseBindMatrices);
for (const anim of json.animations ?? []) {
  for (const sampler of anim.samplers ?? []) {
    useAccessor(sampler.input);
    useAccessor(sampler.output);
  }
}

// sparse accessor 는 별도 bufferView 를 더 참조한다
const liveViews = new Set();
for (const i of liveAccessors) {
  const acc = json.accessors[i];
  if (acc.bufferView !== undefined) liveViews.add(acc.bufferView);
  if (acc.sparse) {
    liveViews.add(acc.sparse.indices.bufferView);
    liveViews.add(acc.sparse.values.bufferView);
  }
}
for (const image of json.images ?? []) if (image.bufferView !== undefined) liveViews.add(image.bufferView);

// ---------------------------------------------------------------- 다시 싸기

const viewOrder = [...liveViews].sort((a, b) => a - b);
const viewMap = new Map(viewOrder.map((old, i) => [old, i]));
const chunks = [];
const newViews = [];
let offset = 0;

for (const old of viewOrder) {
  const view = json.bufferViews[old];
  const start = view.byteOffset ?? 0;
  const slice = bin.subarray(start, start + view.byteLength);
  // 모든 bufferView 는 4바이트 경계에서 시작해야 한다
  const pad = (4 - (offset % 4)) % 4;
  if (pad) {
    chunks.push(Buffer.alloc(pad));
    offset += pad;
  }
  chunks.push(slice);
  newViews.push({
    buffer: 0,
    byteOffset: offset,
    byteLength: view.byteLength,
    ...(view.byteStride !== undefined ? { byteStride: view.byteStride } : {}),
    ...(view.target !== undefined ? { target: view.target } : {}),
    ...(view.name !== undefined ? { name: view.name } : {}),
  });
  offset += view.byteLength;
}

const accessorOrder = [...liveAccessors].sort((a, b) => a - b);
const accessorMap = new Map(accessorOrder.map((old, i) => [old, i]));

json.accessors = accessorOrder.map((old) => {
  const acc = { ...json.accessors[old] };
  if (acc.bufferView !== undefined) acc.bufferView = viewMap.get(acc.bufferView);
  if (acc.sparse) {
    acc.sparse = {
      ...acc.sparse,
      indices: { ...acc.sparse.indices, bufferView: viewMap.get(acc.sparse.indices.bufferView) },
      values: { ...acc.sparse.values, bufferView: viewMap.get(acc.sparse.values.bufferView) },
    };
  }
  return acc;
});
json.bufferViews = newViews;

const remap = (i) => (typeof i === 'number' ? accessorMap.get(i) : i);
for (const mesh of json.meshes ?? []) {
  for (const prim of mesh.primitives ?? []) {
    for (const [key, i] of Object.entries(prim.attributes ?? {})) prim.attributes[key] = remap(i);
    if (prim.indices !== undefined) prim.indices = remap(prim.indices);
    for (const target of prim.targets ?? []) {
      for (const [key, i] of Object.entries(target)) target[key] = remap(i);
    }
  }
}
for (const skin of json.skins ?? []) {
  if (skin.inverseBindMatrices !== undefined) skin.inverseBindMatrices = remap(skin.inverseBindMatrices);
}
for (const anim of json.animations ?? []) {
  for (const sampler of anim.samplers ?? []) {
    sampler.input = remap(sampler.input);
    sampler.output = remap(sampler.output);
  }
}
for (const image of json.images ?? []) {
  if (image.bufferView !== undefined) image.bufferView = viewMap.get(image.bufferView);
}

const newBin = Buffer.concat(chunks);
json.buffers = newBin.length > 0 ? [{ byteLength: newBin.length }] : [];

// ---------------------------------------------------------------- 쓰기

const pad4 = (buf, filler) => {
  const rest = (4 - (buf.length % 4)) % 4;
  return rest ? Buffer.concat([buf, Buffer.alloc(rest, filler)]) : buf;
};

const jsonChunk = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
const binChunk = pad4(newBin, 0);

const parts = [];
const header = Buffer.alloc(12);
header.writeUInt32LE(GLB_MAGIC, 0);
header.writeUInt32LE(2, 4);

const chunkHeader = (length, type) => {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(length, 0);
  b.writeUInt32LE(type, 4);
  return b;
};

parts.push(chunkHeader(jsonChunk.length, CHUNK_JSON), jsonChunk);
if (binChunk.length > 0) parts.push(chunkHeader(binChunk.length, CHUNK_BIN), binChunk);

const body = Buffer.concat(parts);
header.writeUInt32LE(12 + body.length, 8);

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, Buffer.concat([header, body]));

const kb = (n) => (n / 1024).toFixed(0) + 'KB';
console.log(
  `${input} -> ${output}  ${kb(before.size)} -> ${kb(12 + body.length)}` +
    `  (애니메이션 ${before.anims} -> ${kept.length})`
);
