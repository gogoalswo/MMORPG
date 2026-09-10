/**
 * VARCO(바르코) 커스텀 워크플로우가 뱉은 캐릭터를 게임에 넣을 수 있는 .glb 하나로 합친다.
 *
 * 바르코의 Animate 노드는 **동작 하나마다 파일을 하나씩** 준다. 그런데 그 파일에는
 * 메시와 2048² 텍스처 세 장이 통째로 다시 들어 있어서 동작 하나가 14MB 다.
 * 다섯 동작을 그대로 받으면 83MB — 브라우저 게임에 올릴 수 있는 크기가 아니다.
 *
 * 다섯 파일의 뼈대가 **완전히 같다**(Root/Hips/Spine.../RightToeBase 23본).
 * 그래서 메시는 리깅 결과물 하나만 쓰고, 나머지 파일에서는 **애니메이션만 뽑아
 * 옮겨 붙인다.** 채널이 가리키는 노드는 인덱스가 아니라 **이름으로 다시 잇는다** —
 * 인덱스는 파일마다 같다는 보장이 없고, 어긋나면 팔이 다리처럼 움직인다.
 *
 * 텍스처는 2048² PNG 세 장이 11.9MB 다. 쿼터뷰에서 캐릭터는 화면상 100px 남짓이라
 * 그 해상도가 화면에 닿지 않는다. 1024² JPEG 으로 줄인다.
 *
 *   node scripts/build-varco-character.mjs 출력.glb 기본.glb Idle=대기.glb Run=달리기.glb#loop ...
 *   node scripts/build-varco-character.mjs ... Run=달리기.glb#loop      # 한 주기로 잘라 루프를 닫는다
 *   node scripts/build-varco-character.mjs ... --tex 512      # 텍스처 한 변(기본 1024)
 *
 * 클립 이름은 `이름=파일` 의 왼쪽이다. 부르는 쪽(modelRig)이 역할로 찾으므로
 * (pickClip) `Idle` `Run` `Attack` 처럼 역할이 드러나는 이름을 준다.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import sharp from 'sharp';

const GLB_MAGIC = 0x46546c67;
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;
const LOOP_MARK = '#loop';
// 프레임당 평균 이동량의 이 비율보다 덜 움직인 키는 '멈춰 있는 키'로 본다.
const HELD_KEY = 0.2;
const MARKS = new Set(['loop', 'face']);

// ---------------------------------------------------------------- 인자

const args = process.argv.slice(2);
let texSize = 1024;
const texAt = args.indexOf('--tex');
if (texAt >= 0) {
  texSize = Number(args[texAt + 1]);
  args.splice(texAt, 2);
}

const [output, base, ...pairs] = args;
if (!output || !base) {
  console.error('사용법: node scripts/build-varco-character.mjs <출력.glb> <기본.glb> [이름=애니.glb ...] [--tex 1024]');
  process.exit(1);
}

// ---------------------------------------------------------------- glb 읽기

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
  return { json, bin, size: src.length };
}

const src = readGlb(base);
const json = src.json;

/**
 * bufferView 를 오프셋이 아니라 **버퍼 조각 자체**로 들고 다닌다.
 *
 * 애니메이션을 붙일 때마다 오프셋을 다시 계산하면 실수가 나기 쉽다. 조각으로
 * 두었다가 마지막에 한 번만 이어 붙이면 정렬(4바이트)도 그 자리에서 끝난다.
 */
const views = (json.bufferViews ?? []).map((view) => ({
  meta: {
    ...(view.byteStride !== undefined ? { byteStride: view.byteStride } : {}),
    ...(view.target !== undefined ? { target: view.target } : {}),
  },
  data: src.bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength),
}));

const addView = (data, meta = {}) => {
  views.push({ meta, data });
  return views.length - 1;
};

// ---------------------------------------------------------------- 애니메이션 옮겨 붙이기

/** 이름 -> 이 파일에서의 노드 번호. 채널을 다시 잇는 기준이다 */
const nodeByName = new Map();
(json.nodes ?? []).forEach((node, i) => {
  if (node.name) nodeByName.set(node.name, i);
});

// ---------------------------------------------------------------- 루프 닫기

const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
const FLOAT = 5126;

/** 애니메이션 샘플러의 접근자를 Float32Array 로 읽는다. 여기 값은 전부 float 이다. */
function readFloats(from, index) {
  const acc = from.json.accessors[index];
  const n = COMPONENTS[acc.type];
  if (acc.componentType !== FLOAT || !n) throw new Error(`샘플러가 float ${acc.type} 이 아니다`);
  if (acc.sparse) throw new Error('sparse accessor 는 다루지 않는다');
  const view = from.json.bufferViews[acc.bufferView];
  const at = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
  const data = new Float32Array(acc.count * n);
  for (let i = 0; i < data.length; i += 1) data[i] = from.bin.readFloatLE(at + i * 4);
  return { data, n, count: acc.count };
}

/**
 * 반복 재생할 클립을 **한 주기로 잘라 닫는다.**
 *
 * 바르코 Animate 가 준 달리기는 1.633s / 49프레임인데 한 걸음 주기는 21프레임이다.
 * 2.35주기라 끝에서 걸음 중간에 뚝 끊긴다. 게다가 클립이 진행될수록 상체가 서서히
 * 펴진다 (허리 x 0.044 → 0.010). 둘이 겹쳐서 화면에는 **앞으로 달리다 → 허리를
 * 펴다 → 다시 수그리며 툭 튀는** 것으로 보인다. 생성형 애니메이션은 시작과 끝을
 * 맞춰 줄 이유가 없으므로 이건 이 워크플로우를 쓰는 한 계속 나온다.
 *
 * 두 가지를 한다.
 *   1. 프레임 0 과 자세가 가장 가까워지는 지점을 찾아 거기서 자른다 (= 한 주기)
 *   2. 남은 흐름을 시간에 비례해 빼서 마지막 프레임을 첫 프레임에 정확히 맞춘다
 *
 * **주기의 길이는 그대로**라서 클립 속도를 이동 속도에 맞추는 쪽
 * (`modelRig` 의 `RUN_CLIP_SPEED`)은 건드릴 필요가 없다. 자르는 건 여분의 주기뿐이다.
 *
 * 앞 30% 는 후보에서 뺀다 — 시작 근처는 당연히 자세가 비슷해서 언제나 이긴다.
 */
function closeLoop(from, anim, name, { face, hips }) {
  const tracks = anim.samplers.map((s) => {
    if ((s.interpolation ?? 'LINEAR') !== 'LINEAR') {
      throw new Error(`${name}: LINEAR 보간만 자를 수 있다 (${s.interpolation})`);
    }
    return { time: readFloats(from, s.input), value: readFloats(from, s.output) };
  });

  const keys = tracks[0].time.count;
  for (const t of tracks) {
    if (t.time.count !== keys || t.value.count !== keys) {
      throw new Error(`${name}: 샘플러마다 키 개수가 다르다 — 잘라 붙일 수 없다`);
    }
  }

  // 사원수는 q 와 -q 가 같은 회전이다. 부호가 뒤집힌 키가 섞여 있으면 그 사이를
  // 선형 보간하는 순간 몸이 한 바퀴 돈다. 자세를 비교하기 전에 부호부터 맞춘다.
  for (const t of tracks) {
    if (t.value.n !== 4) continue;
    for (let f = 1; f < keys; f += 1) {
      let dot = 0;
      for (let k = 0; k < 4; k += 1) dot += t.value.data[(f - 1) * 4 + k] * t.value.data[f * 4 + k];
      if (dot < 0) for (let k = 0; k < 4; k += 1) t.value.data[f * 4 + k] *= -1;
    }
  }

  // 클립에 구워진 **몸 전체의 방향**을 없앤다.
  //
  // 바르코 Animate 는 동작마다 캐릭터를 제멋대로 돌려놓고 굽는다. 그 방향이
  // 골반(Hips)에 통째로 들어 있어서, 클립을 틀면 몸이 그만큼 돌아간 채로 선다.
  // 달리기는 **-83.2°** 였다 — 9시를 클릭했는데 12시를 보고 달리던 이유다.
  // 대기는 -1.3°(사실상 0) 라, 대기↔달리기를 가중치로 섞는 동안에는 그 중간각이
  // 나온다. "45도쯤 돌아가 있다" 로 보이던 게 이것이다.
  //
  // Y축 twist 만 뽑아 **평균 방향**을 구하고 그만큼 되돌린다. 걸음마다 골반이
  // 좌우로 흔들리는 ±12.8° 는 진짜 동작이라, 평균만 빼면 그대로 남는다.
  // 기준은 0 — 모델 바인드 방향(+Z) 이다. 부르는 쪽(modelRig)이
  // `rotY = atan2(dx, dz)` 를 그대로 먹이므로 모델 정면이 곧 기준이 된다.
  let leveled = 0;
  if (face) {
    const track = tracks[hips];
    if (!track || track.value.n !== 4) throw new Error(`${name}: 방향을 없앨 Hips 회전 채널이 없다`);
    const { data } = track.value;
    let sx = 0;
    let sy = 0;
    for (let f = 0; f < keys; f += 1) {
      const yaw = 2 * Math.atan2(data[f * 4 + 1], data[f * 4 + 3]);
      sx += Math.cos(yaw);
      sy += Math.sin(yaw);
    }
    const mean = Math.atan2(sy, sx);
    // 부모(Root)는 회전이 없으므로, 골반 회전 앞에 곱하면 몸 전체가 그만큼 돈다.
    const c = Math.cos(-mean / 2);
    const sn = Math.sin(-mean / 2);
    for (let f = 0; f < keys; f += 1) {
      const x = data[f * 4];
      const y = data[f * 4 + 1];
      const z = data[f * 4 + 2];
      const w = data[f * 4 + 3];
      data[f * 4] = c * x + sn * z;
      data[f * 4 + 1] = c * y + sn * w;
      data[f * 4 + 2] = c * z - sn * x;
      data[f * 4 + 3] = c * w - sn * y;
    }
    leveled = (mean * 180) / Math.PI;
  }

  // 자세 거리는 **회전만으로** 잰다. 위치 채널은 Root 하나뿐이고 단위가 달라서
  // 같이 더하면 그쪽이 기준을 끌고 간다.
  const rot = tracks.filter((t) => t.value.n === 4);
  const poseDist = (a, b) => {
    let sum = 0;
    for (const t of rot) {
      for (let k = 0; k < 4; k += 1) {
        const d = t.value.data[a * 4 + k] - t.value.data[b * 4 + k];
        sum += d * d;
      }
    }
    return Math.sqrt(sum);
  };

  // 멈춰 있는 키를 버린다.
  //
  // 바르코 생성기는 **첫 프레임과 끝 프레임을 한 번 더 찍어 놓는다.** 달리기에서
  // 0→1 의 이동량이 0.017 인데 프레임당 평균은 0.318 이었다 — 그 자리에서 33ms
  // 서 있는 것이다. 자세를 맞춰 루프를 닫아 놓으면 끝 프레임 = 첫 프레임이라,
  // 되감기는 자리에서 같은 자세가 연달아 나와 **달리다 멈칫하는 것으로 보인다.**
  //
  // 버린 뒤 남은 키는 **원래 구간 길이 그대로**에 고르게 다시 편다. 구간을 같이
  // 줄이면 한 걸음이 5% 빨라져서, 발 미끄러짐을 맞춰 둔 `RUN_CLIP_SPEED`(modelRig)
  // 가 어긋난다. 없앨 것은 멈칫이지 걸음의 빠르기가 아니다.
  const steps = [];
  for (let f = 1; f < keys; f += 1) steps.push(poseDist(f - 1, f));
  const median = [...steps].sort((a, b) => a - b)[steps.length >> 1];
  const live = [0];
  for (let f = 1; f < keys; f += 1) if (steps[f - 1] >= median * HELD_KEY) live.push(f);

  let cut = live.length - 1;
  let best = Infinity;
  for (let i = Math.ceil(live.length * 0.3); i < live.length; i += 1) {
    const d = poseDist(live[0], live[i]);
    if (d < best) {
      best = d;
      cut = i;
    }
  }

  const kept = cut + 1;
  // 시간은 **버리기 전 원래 타임스탬프**로 재고, 남은 키를 그 위에 고르게 편다.
  const span = tracks[0].time.data[live[cut]] - tracks[0].time.data[live[0]];
  const time = new Float32Array(kept);
  for (let f = 0; f < kept; f += 1) time[f] = (span * f) / cut;

  const values = tracks.map(({ value }) => {
    const { n, data } = value;
    const out = new Float32Array(kept * n);
    const src = (f, k) => data[live[f] * n + k];
    for (let f = 0; f < kept; f += 1) {
      const w = cut === 0 ? 0 : f / cut;
      for (let k = 0; k < n; k += 1) {
        out[f * n + k] = src(f, k) - (src(cut, k) - src(0, k)) * w;
      }
    }
    // 흐름을 빼면 사원수 길이가 1 에서 벗어난다. 그대로 두면 뼈가 조금씩 줄어든다.
    if (n === 4) {
      for (let f = 0; f < kept; f += 1) {
        let len = 0;
        for (let k = 0; k < 4; k += 1) len += out[f * 4 + k] ** 2;
        len = Math.sqrt(len) || 1;
        for (let k = 0; k < 4; k += 1) out[f * 4 + k] /= len;
      }
    }
    return out;
  });

  return { time, values, keys, kept, held: keys - live.length, leveled, dist: best, seam: poseDist(0, keys - 1) };
}

json.animations = [];

for (const pair of pairs) {
  const at = pair.indexOf('=');
  if (at < 0) throw new Error(`이름=파일 형태가 아니다: ${pair}`);
  const name = pair.slice(0, at);
  // `이름=파일#loop#face` — 파일 뒤에 손볼 것을 표시로 붙인다.
  //   #loop  반복 재생이라 시작과 끝을 맞춰야 한다
  //   #face  클립에 구워진 몸 방향을 없앤다
  let file = pair.slice(at + 1);
  const marks = new Set();
  for (;;) {
    const hash = file.lastIndexOf('#');
    if (hash < 0 || !MARKS.has(file.slice(hash + 1))) break;
    marks.add(file.slice(hash + 1));
    file = file.slice(0, hash);
  }
  const cyclic = marks.has('loop');

  const from = readGlb(file);
  const anim = (from.json.animations ?? [])[0];
  if (!anim) {
    console.warn(`  ! ${file} 에 애니메이션이 없다 — 건너뛴다`);
    continue;
  }

  // 같은 bufferView 를 두 번 복사하지 않는다 (입력 시간축은 샘플러끼리 공유한다)
  const viewMap = new Map();
  const copyView = (i) => {
    const found = viewMap.get(i);
    if (found !== undefined) return found;
    const view = from.json.bufferViews[i];
    const start = view.byteOffset ?? 0;
    const at = addView(from.bin.subarray(start, start + view.byteLength), {
      ...(view.byteStride !== undefined ? { byteStride: view.byteStride } : {}),
    });
    viewMap.set(i, at);
    return at;
  };

  const copyAccessor = (i) => {
    const acc = { ...from.json.accessors[i] };
    if (acc.sparse) throw new Error(`${file}: sparse accessor 는 다루지 않는다`);
    if (acc.bufferView !== undefined) acc.bufferView = copyView(acc.bufferView);
    json.accessors.push(acc);
    return json.accessors.length - 1;
  };

  let samplers;
  let closed = null;
  if (cyclic) {
    const hipsChannel = anim.channels.findIndex(
      (c) => c.target.path === 'rotation' && from.json.nodes[c.target.node]?.name === 'Hips'
    );
    closed = closeLoop(from, anim, name, {
      face: marks.has('face'),
      hips: hipsChannel < 0 ? -1 : anim.channels[hipsChannel].sampler,
    });
    const addFloats = (data, n, type) => {
      const min = Array.from({ length: n }, (_, k) => Infinity);
      const max = Array.from({ length: n }, (_, k) => -Infinity);
      for (let i = 0; i < data.length; i += 1) {
        const k = i % n;
        if (data[i] < min[k]) min[k] = data[i];
        if (data[i] > max[k]) max[k] = data[i];
      }
      const view = addView(Buffer.from(data.buffer, data.byteOffset, data.byteLength));
      // 시간축 접근자는 min/max 가 스펙상 필수다. 값 쪽은 있어도 해롭지 않다.
      json.accessors.push({ bufferView: view, componentType: FLOAT, count: data.length / n, type, min, max });
      return json.accessors.length - 1;
    };
    const timeAt = addFloats(closed.time, 1, 'SCALAR');
    samplers = anim.samplers.map((s, i) => ({
      input: timeAt,
      output: addFloats(closed.values[i], COMPONENTS[from.json.accessors[s.output].type], from.json.accessors[s.output].type),
    }));
  } else {
    samplers = anim.samplers.map((s) => ({
      input: copyAccessor(s.input),
      output: copyAccessor(s.output),
      ...(s.interpolation ? { interpolation: s.interpolation } : {}),
    }));
  }

  // 채널은 **이름으로** 다시 잇는다. 그쪽 파일에만 있는 뼈는 버린다.
  const channels = [];
  let dropped = 0;
  for (const ch of anim.channels) {
    const srcNode = from.json.nodes[ch.target.node];
    const to = srcNode?.name !== undefined ? nodeByName.get(srcNode.name) : undefined;
    if (to === undefined) {
      dropped += 1;
      continue;
    }
    channels.push({ sampler: ch.sampler, target: { node: to, path: ch.target.path } });
  }

  json.animations.push({ name, samplers, channels });
  const loopNote = closed
    ? `  루프닫기 ${closed.keys}→${closed.kept}키 (멈춘 키 ${closed.held} 버림, 끝 이음새 ${closed.seam.toFixed(2)} → 자른 자리 ${closed.dist.toFixed(2)} → 흐름 빼고 0)${closed.leveled ? `, 구워진 방향 ${closed.leveled.toFixed(1)}° 되돌림` : ''}`
    : '';
  console.log(`  + ${name.padEnd(12)} 채널 ${channels.length}${dropped ? ` (버린 채널 ${dropped})` : ''}  ← ${file}${loopNote}`);
}

// ---------------------------------------------------------------- 텍스처 줄이기

/**
 * 노멀맵은 조금 더 곱게 남긴다.
 *
 * JPEG 은 색차 성분을 먼저 버리는데, 노멀맵은 그 성분이 곧 기울기다. 색 텍스처와
 * 같은 품질로 누르면 평평한 갑옷에 얼룩진 요철이 생긴다.
 */
const NORMAL_QUALITY = 92;
const COLOR_QUALITY = 84;

const normalImages = new Set();
for (const mat of json.materials ?? []) {
  const tex = mat.normalTexture?.index;
  if (tex !== undefined) normalImages.add(json.textures[tex].source);
}

for (const [i, image] of (json.images ?? []).entries()) {
  if (image.bufferView === undefined) continue;
  const before = views[image.bufferView].data;
  const isNormal = normalImages.has(i);
  const out = await sharp(before)
    .resize(texSize, texSize, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: isNormal ? NORMAL_QUALITY : COLOR_QUALITY, chromaSubsampling: '4:4:4' })
    .toBuffer();
  views[image.bufferView] = { meta: {}, data: out };
  image.mimeType = 'image/jpeg';
  console.log(
    `  텍스처 ${i}${isNormal ? ' (노멀)' : ''}: ${(before.length / 1048576).toFixed(2)}MB → ${(out.length / 1048576).toFixed(2)}MB`
  );
}

// ---------------------------------------------------------------- 다시 싸기

const chunks = [];
let offset = 0;
json.bufferViews = views.map(({ meta, data }) => {
  const pad = (4 - (offset % 4)) % 4;
  if (pad) {
    chunks.push(Buffer.alloc(pad));
    offset += pad;
  }
  chunks.push(data);
  const view = { buffer: 0, byteOffset: offset, byteLength: data.length, ...meta };
  offset += data.length;
  return view;
});

const bin = Buffer.concat(chunks);
json.buffers = [{ byteLength: bin.length }];

const pad4 = (buf, filler) => {
  const rest = (4 - (buf.length % 4)) % 4;
  return rest ? Buffer.concat([buf, Buffer.alloc(rest, filler)]) : buf;
};

const jsonChunk = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
const binChunk = pad4(bin, 0);

const chunkHeader = (length, type) => {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(length, 0);
  b.writeUInt32LE(type, 4);
  return b;
};

const body = Buffer.concat([chunkHeader(jsonChunk.length, CHUNK_JSON), jsonChunk, chunkHeader(binChunk.length, CHUNK_BIN), binChunk]);
const header = Buffer.alloc(12);
header.writeUInt32LE(GLB_MAGIC, 0);
header.writeUInt32LE(2, 4);
header.writeUInt32LE(12 + body.length, 8);

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, Buffer.concat([header, body]));

console.log(
  `${output}  ${(src.size / 1048576).toFixed(2)}MB → ${((12 + body.length) / 1048576).toFixed(2)}MB, 클립 ${json.animations.length}개`
);
