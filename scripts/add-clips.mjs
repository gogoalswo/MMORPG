/**
 * 다른 GLB 의 클립을 캐릭터 GLB 에 **옮겨 붙인다** — 메시·텍스처는 그대로 둔다.
 *
 *   node scripts/add-clips.mjs <출력.glb> <캐릭터.glb> <클립.glb>
 *
 * 블렌더로 지은 동작(`scripts/blender/fighter_moves.py` → `public/assets/anim/fighter_moves.glb`)
 * 을 `varco_fighter.glb` 에 붙일 때 쓴다. `build-varco-character.mjs` 와 같이 채널은
 * **뼈 이름으로** 다시 잇는다. 다른 점:
 *
 * - 캐릭터에 이미 있는 클립은 **남긴다.** 이름이 같은 것만 갈아끼운다 — 다시 돌려도 쌓이지 않는다.
 * - 텍스처를 다시 누르지 않는다. 이미 줄여 둔 JPEG 을 또 누르면 돌릴 때마다 뭉개진다.
 * - **캐릭터 클립이 키로 가진 채널만 남긴다.** 바르코 클립은 뼈 20개 회전 + `Root` 이동뿐이다.
 *   새 클립이 그 밖의 채널(`Hips` 이동, 발가락, 크기)을 가지면 다른 클립으로 넘어갈 때
 *   아무도 되돌려 주지 않아 그 자세로 굳는다. 그래서 버리는데, **버리는 채널이 기본 자세에서
 *   벗어나 있으면 멈춘다** — 그 동작은 버리면 모양이 바뀐다.
 * - 뼈의 기본 자세(노드 이동·회전)가 캐릭터와 다르면 멈춘다. 채널 값은 부모 기준 절대값이라
 *   기본 자세가 다른 뼈대에서 온 값은 팔을 엉뚱한 데로 보낸다.
 * - 끝에서 아무도 안 쓰는 접근자·버퍼 조각을 치운다.
 *
 * `--retarget` (맨 끝에 붙인다) — **다른 몸에 같은 동작을 입힌다** (2026-09-26, 팬티 차림 격투가).
 * 뼈 이름은 같은데 기본 자세가 다른 뼈대로 옮긴다. 채널 값을 그대로 쓰면 팔이 엉뚱한 데로
 * 가므로, 뼈마다 **월드 회전이 기본 자세에서 얼마나 돌았나**(D = G(t)·G_rest⁻¹)를 재서
 * 새 뼈대의 기본 자세에 똑같이 입힌다. `Root` 이동은 다리 길이 비로 줄인다.
 * 이때는 기본 자세 검사와 "캐릭터 클립이 가진 채널만" 규칙을 건너뛴다 (새 몸엔 클립이 없다).
 *
 * `--align` (`--retarget` 과 같이) — 새 몸의 기본 자세가 **T 포즈가 아닐 때** (2026-09-26, 주먹 쥔
 * 채 팔을 내리고 뽑은 격투가). 새 뼈대의 기본 자세 대신 **뼈 방향을 클립 뼈대에 맞춘 가상 자세**
 * (`align-rest.mjs`)에 돈 만큼을 입힌다. 클립이 키로 안 가진 뼈도 가상 자세로 가야 하므로 클립 뼈대에
 * 있는 뼈는 **전부** 채널을 쓴다 (손가락은 가상 자세에서도 안 돌아 주먹이 그대로다).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { alignedRest } from './align-rest.mjs';

const GLB_MAGIC = 0x46546c67;
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;
const FLOAT = 5126;
const SIZE = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
// 기본 자세와 이만큼 넘게 다르면 "다르다" 로 본다
const REST_EPS = 1e-3;

const ALIGN = process.argv.includes('--align');
const RETARGET = ALIGN || process.argv.includes('--retarget');
const [output, base, clips] = process.argv.slice(2).filter((a) => a !== '--retarget' && a !== '--align');
if (!output || !base || !clips) {
  console.error('사용법: node scripts/add-clips.mjs <출력.glb> <캐릭터.glb> <클립.glb> [--retarget | --align]');
  process.exit(1);
}

function readGlb(path) {
  const src = readFileSync(path);
  if (src.readUInt32LE(0) !== GLB_MAGIC) throw new Error(`${path}: glb 가 아니다`);
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
  if (!json) throw new Error(`${path}: JSON 청크가 없다`);
  return { json, bin };
}

const dst = readGlb(base);
const src = readGlb(clips);
const json = dst.json;

// bufferView 를 조각째 들고 다니다 마지막에 한 번 잇는다 (build-varco-character 와 같다)
let views = json.bufferViews.map((v) => ({
  meta: { ...(v.byteStride !== undefined ? { byteStride: v.byteStride } : {}), ...(v.target ? { target: v.target } : {}) },
  data: dst.bin.subarray(v.byteOffset ?? 0, (v.byteOffset ?? 0) + v.byteLength),
}));

function floats(file, index) {
  const acc = file.json.accessors[index];
  const view = file.json.bufferViews[acc.bufferView];
  if (acc.componentType !== FLOAT) throw new Error('float 이 아닌 접근자');
  const n = SIZE[acc.type];
  const stride = view.byteStride ?? n * 4;
  const start = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
  const out = new Float32Array(acc.count * n);
  for (let i = 0; i < acc.count; i += 1)
    for (let k = 0; k < n; k += 1) out[i * n + k] = file.bin.readFloatLE(start + i * stride + k * 4);
  return out;
}

// ---------------------------------------------------------------- 뼈 맞추기

const nodeByName = new Map(json.nodes.map((n, i) => [n.name, i]));
const REST = { rotation: [0, 0, 0, 1], translation: [0, 0, 0], scale: [1, 1, 1] };
const restOf = (node, path) => node[path] ?? REST[path];

for (const node of RETARGET ? [] : src.json.nodes) {
  const at = nodeByName.get(node.name);
  if (at === undefined) continue;
  for (const path of ['rotation', 'translation']) {
    const a = restOf(node, path);
    const b = restOf(json.nodes[at], path);
    let diff = Math.max(...a.map((v, i) => Math.abs(v - b[i])));
    if (path === 'rotation') diff = Math.min(diff, Math.max(...a.map((v, i) => Math.abs(v + b[i]))));
    if (diff > REST_EPS) throw new Error(`${node.name} 의 기본 ${path} 가 캐릭터와 다르다 (${diff.toFixed(4)}) — 같은 뼈대에서 지은 클립이 아니다`);
  }
}

// 캐릭터 클립이 키로 가진 채널 — 새 클립도 이것만 남긴다
const keyed = new Set();
for (const anim of json.animations ?? [])
  for (const ch of anim.channels) keyed.add(`${ch.target.node}/${ch.target.path}`);

// ---------------------------------------------------------------- 옮기기

const incoming = new Set(src.json.animations.map((a) => a.name));
json.animations = (json.animations ?? []).filter((a) => !incoming.has(a.name));

const addFloats = (data, type) => {
  const n = SIZE[type];
  const min = Array(n).fill(Infinity);
  const max = Array(n).fill(-Infinity);
  for (let i = 0; i < data.length; i += 1) {
    min[i % n] = Math.min(min[i % n], data[i]);
    max[i % n] = Math.max(max[i % n], data[i]);
  }
  views.push({ meta: {}, data: Buffer.from(data.buffer, data.byteOffset, data.byteLength) });
  json.accessors.push({ bufferView: views.length - 1, componentType: FLOAT, count: data.length / n, type, min, max });
  return json.accessors.length - 1;
};

// ---------------------------------------------------------------- --retarget

const qmul = (a, b) => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
];
const qinv = (q) => [-q[0], -q[1], -q[2], q[3]];
const qnorm = (q) => {
  const l = Math.hypot(...q) || 1;
  return q.map((v) => v / l);
};
const parentsOf = (nodes) => {
  const parent = new Map();
  nodes.forEach((n, i) => (n.children ?? []).forEach((c) => parent.set(c, i)));
  return parent;
};

// 한 파일의 뼈마다 월드 회전 — local(i) 가 그 뼈의 부모 기준 회전을 준다
function globals(nodes, parent, local) {
  const out = new Map();
  const walk = (i) => {
    if (out.has(i)) return out.get(i);
    const p = parent.get(i);
    const g = p === undefined ? local(i) : qmul(walk(p), local(i));
    out.set(i, g);
    return g;
  };
  nodes.forEach((_, i) => walk(i));
  return out;
}

// 채널 하나를 시각 t 에서 읽는다 (LINEAR — 회전은 부호를 맞춘 nlerp)
function sample(times, values, n, t, rot) {
  let k = 0;
  while (k < times.length - 2 && times[k + 1] <= t) k += 1;
  const a = times[k];
  const b = times[Math.min(k + 1, times.length - 1)];
  const f = b > a ? Math.min(Math.max((t - a) / (b - a), 0), 1) : 0;
  const va = Array.from(values.subarray(k * n, k * n + n));
  const vb = Array.from(values.subarray(Math.min(k + 1, times.length - 1) * n, Math.min(k + 1, times.length - 1) * n + n));
  if (rot && va.reduce((s, v, i) => s + v * vb[i], 0) < 0) vb.forEach((v, i) => (vb[i] = -v));
  const out = va.map((v, i) => v + (vb[i] - v) * f);
  return rot ? qnorm(out) : out;
}

function retarget(anim) {
  const sNodes = src.json.nodes;
  const dNodes = json.nodes;
  const sParent = parentsOf(sNodes);
  const dParent = parentsOf(dNodes);
  const tracks = anim.channels.map((ch) => {
    const s = anim.samplers[ch.sampler];
    return { node: ch.target.node, path: ch.target.path, times: floats(src, s.input), values: floats(src, s.output) };
  });
  const times = [...new Set(tracks.flatMap((t) => Array.from(t.times)))].sort((a, b) => a - b);
  const sRestG = globals(sNodes, sParent, (i) => restOf(sNodes[i], 'rotation'));
  const dRestG = ALIGN
    ? new Map([...alignedRest(dNodes, sNodes)].map(([i, g]) => [i, g.q]))
    : globals(dNodes, dParent, (i) => restOf(dNodes[i], 'rotation'));
  const dIndex = (i) => nodeByName.get(sNodes[i].name);
  const keyedRot = tracks.filter((t) => t.path === 'rotation' && dIndex(t.node) !== undefined);
  // --align: 키가 없는 뼈도 가상 자세로 보내야 하므로 클립 뼈대의 (몸에도 있는) 뼈를 전부 쓴다
  const skinJoints = new Set((json.skins ?? []).flatMap((s) => s.joints));
  const rotTracks = ALIGN
    ? [
        ...keyedRot,
        ...sNodes
          .map((_, i) => ({ node: i, rest: true }))
          .filter((t) => !keyedRot.some((k) => k.node === t.node) && skinJoints.has(dIndex(t.node))),
      ]
    : keyedRot;
  const leg = (nodes, byName) =>
    ['LeftLeg', 'LeftFoot'].reduce((s, n) => s + Math.hypot(...restOf(nodes[byName(n)], 'translation')), 0);
  const sByName = (n) => sNodes.findIndex((x) => x.name === n);
  const k = leg(dNodes, (n) => nodeByName.get(n)) / leg(sNodes, sByName);

  const out = rotTracks.map((t) => ({ name: sNodes[t.node].name, path: 'rotation', values: [] }));
  const moves = tracks
    .filter((t) => t.path === 'translation' && dIndex(t.node) !== undefined)
    .map((t) => ({ t, name: sNodes[t.node].name, path: 'translation', values: [] }));
  for (const time of times) {
    const at = new Map(rotTracks.filter((t) => !t.rest).map((t) => [t.node, sample(t.times, t.values, 4, time, true)]));
    const sG = globals(sNodes, sParent, (i) => at.get(i) ?? restOf(sNodes[i], 'rotation'));
    // 새 뼈대의 월드 회전 = (옛 뼈가 기본 자세에서 돈 만큼) · 새 기본 자세
    const dG = new Map();
    dNodes.forEach((n, i) => {
      const si = sByName(n.name);
      dG.set(i, si >= 0 ? qmul(qmul(sG.get(si), qinv(sRestG.get(si))), dRestG.get(i)) : null);
    });
    const worldOf = (i) => {
      if (i === undefined) return [0, 0, 0, 1];
      if (dG.get(i)) return dG.get(i);
      const p = dParent.get(i);
      return qmul(worldOf(p), restOf(dNodes[i], 'rotation'));
    };
    rotTracks.forEach((t, j) => {
      const d = dIndex(t.node);
      const local = qnorm(qmul(qinv(worldOf(dParent.get(d))), dG.get(d)));
      out[j].values.push(...local);
    });
    for (const m of moves) {
      const v = sample(m.t.times, m.t.values, 3, time, false);
      const sRest = restOf(sNodes[m.t.node], 'translation');
      const dRest = restOf(dNodes[dIndex(m.t.node)], 'translation');
      m.values.push(...dRest.map((r, i) => r + (v[i] - sRest[i]) * k));
    }
  }
  return { times: Float32Array.from(times), tracks: [...out, ...moves], k };
}

if (RETARGET) {
  const incoming2 = new Set(src.json.animations.map((a) => a.name));
  json.animations = (json.animations ?? []).filter((a) => !incoming2.has(a.name));
  for (const anim of src.json.animations) {
    const { times, tracks, k } = retarget(anim);
    const input = addFloats(times, 'SCALAR');
    const samplers = [];
    const channels = [];
    for (const t of tracks) {
      samplers.push({ input, output: addFloats(Float32Array.from(t.values), t.path === 'rotation' ? 'VEC4' : 'VEC3') });
      channels.push({ sampler: samplers.length - 1, target: { node: nodeByName.get(t.name), path: t.path } });
    }
    json.animations.push({ name: anim.name, samplers, channels });
    console.log(`  ~ ${anim.name.padEnd(12)} ${times[times.length - 1].toFixed(2)}s  채널 ${channels.length}  (이동 ×${k.toFixed(3)})`);
  }
}

for (const anim of RETARGET ? [] : src.json.animations) {
  const samplers = [];
  const channels = [];
  const timeCache = new Map();
  let dropped = 0;
  for (const ch of anim.channels) {
    const name = src.json.nodes[ch.target.node]?.name;
    const to = nodeByName.get(name);
    const sampler = anim.samplers[ch.sampler];
    const values = floats(src, sampler.output);
    if (to === undefined || !keyed.has(`${to}/${ch.target.path}`)) {
      // 버려도 되는지 — 처음부터 끝까지 기본 자세여야 한다
      const rest = to === undefined ? null : restOf(json.nodes[to], ch.target.path);
      if (rest) {
        const n = rest.length;
        for (let i = 0; i < values.length; i += 1) {
          const k = i % n;
          const off = Math.abs(values[i] - rest[k]);
          const flip = ch.target.path === 'rotation' ? Math.abs(values[i] + rest[k]) : Infinity;
          if (Math.min(off, flip) > REST_EPS)
            throw new Error(`${anim.name}: ${name}.${ch.target.path} 가 기본 자세에서 벗어나는데 캐릭터 클립은 이 채널이 없다 — 버리면 모양이 바뀐다`);
        }
      }
      dropped += 1;
      continue;
    }
    let input = timeCache.get(sampler.input);
    if (input === undefined) {
      input = addFloats(floats(src, sampler.input), 'SCALAR');
      timeCache.set(sampler.input, input);
    }
    const output = addFloats(values, src.json.accessors[sampler.output].type);
    samplers.push({ input, output, ...(sampler.interpolation ? { interpolation: sampler.interpolation } : {}) });
    channels.push({ sampler: samplers.length - 1, target: { node: to, path: ch.target.path } });
  }
  json.animations.push({ name: anim.name, samplers, channels });
  const times = floats(src, anim.samplers[0].input);
  console.log(`  + ${anim.name.padEnd(12)} ${times[times.length - 1].toFixed(2)}s  채널 ${channels.length} (버린 채널 ${dropped})`);
}

// ---------------------------------------------------------------- 안 쓰는 조각 치우기

const usedAcc = new Set();
for (const mesh of json.meshes ?? [])
  for (const prim of mesh.primitives) {
    Object.values(prim.attributes).forEach((i) => usedAcc.add(i));
    if (prim.indices !== undefined) usedAcc.add(prim.indices);
    for (const t of prim.targets ?? []) Object.values(t).forEach((i) => usedAcc.add(i));
  }
for (const skin of json.skins ?? []) if (skin.inverseBindMatrices !== undefined) usedAcc.add(skin.inverseBindMatrices);
for (const anim of json.animations) for (const s of anim.samplers) (usedAcc.add(s.input), usedAcc.add(s.output));

const accMap = new Map();
const accessors = [];
json.accessors.forEach((acc, i) => {
  if (!usedAcc.has(i)) return;
  accMap.set(i, accessors.length);
  accessors.push(acc);
});
const usedView = new Set(accessors.map((a) => a.bufferView).filter((v) => v !== undefined));
for (const image of json.images ?? []) if (image.bufferView !== undefined) usedView.add(image.bufferView);
const viewMap = new Map();
const kept = [];
views.forEach((v, i) => {
  if (!usedView.has(i)) return;
  viewMap.set(i, kept.length);
  kept.push(v);
});
for (const acc of accessors) if (acc.bufferView !== undefined) acc.bufferView = viewMap.get(acc.bufferView);
for (const image of json.images ?? []) if (image.bufferView !== undefined) image.bufferView = viewMap.get(image.bufferView);
const remap = (i) => accMap.get(i);
for (const mesh of json.meshes ?? [])
  for (const prim of mesh.primitives) {
    for (const k of Object.keys(prim.attributes)) prim.attributes[k] = remap(prim.attributes[k]);
    if (prim.indices !== undefined) prim.indices = remap(prim.indices);
    for (const t of prim.targets ?? []) for (const k of Object.keys(t)) t[k] = remap(t[k]);
  }
for (const skin of json.skins ?? []) if (skin.inverseBindMatrices !== undefined) skin.inverseBindMatrices = remap(skin.inverseBindMatrices);
for (const anim of json.animations) for (const s of anim.samplers) ((s.input = remap(s.input)), (s.output = remap(s.output)));
json.accessors = accessors;

// ---------------------------------------------------------------- 다시 싸기

const chunks = [];
let offset = 0;
json.bufferViews = kept.map(({ meta, data }) => {
  const pad = (4 - (offset % 4)) % 4;
  if (pad) (chunks.push(Buffer.alloc(pad)), (offset += pad));
  const view = { buffer: 0, byteOffset: offset, byteLength: data.length, ...meta };
  chunks.push(data);
  offset += data.length;
  return view;
});
const bin = Buffer.concat(chunks);
json.buffers = [{ byteLength: bin.length }];

const pad4 = (buf, filler) => {
  const pad = (4 - (buf.length % 4)) % 4;
  return pad ? Buffer.concat([buf, Buffer.alloc(pad, filler)]) : buf;
};
const jsonChunk = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
const binChunk = pad4(bin, 0);
const chunkHeader = (length, type) => {
  const h = Buffer.alloc(8);
  h.writeUInt32LE(length, 0);
  h.writeUInt32LE(type, 4);
  return h;
};
const body = Buffer.concat([chunkHeader(jsonChunk.length, CHUNK_JSON), jsonChunk, chunkHeader(binChunk.length, CHUNK_BIN), binChunk]);
const header = Buffer.alloc(12);
header.writeUInt32LE(GLB_MAGIC, 0);
header.writeUInt32LE(2, 4);
header.writeUInt32LE(12 + body.length, 8);
writeFileSync(output, Buffer.concat([header, body]));
console.log(`${output}: 클립 ${json.animations.map((a) => a.name).join(' ')} · ${((12 + body.length) / 1048576).toFixed(2)}MB`);
