/**
 * 뼈를 **제 로컬 축으로 더 돌린다** — 고른 클립의 회전 키마다 `q' = q · r` (기본 자세에도 같이).
 *
 * 왜 (2026-10-06, 주먹 쥔 트레이너 시안) — "주먹이 너무 정면 … 바깥쪽으로 돌려야지. 팔도 너무 몸에 딱 붙이지
 * 말고 자연스럽게 … 팔꿈치를 살짝 구부리고". 다시 뽑지 않고 동작 키만 고친다: 아래팔을 제 축(+Y)으로 비틀어
 * 주먹 방향을 바꾸고, 대기에서만 윗팔을 벌리고 팔꿈치를 굽힌다. 키 값만 같은 자리에서 바꾸므로 크기는 그대로다.
 *
 *   node scripts/rotate-bones.mjs <입력.glb> <출력.glb> <뼈>:<x>,<y>,<z>:<도>[@클립+클립] ...
 *
 *   예) LeftForeArm:0,1,0:-60            모든 클립 + 기본 자세
 *       LeftArm:1,0,-0.774:12@Idle        대기만 (기본 자세는 안 건드린다)
 *       LeftHand:rest@Idle                대기의 회전 키를 **전부 기본 자세 값으로** (손목을 조각된 대로 편다, 2026-10-07)
 *
 * 축은 그 뼈의 **로컬** 축이다 (정규화한다). 같은 뼈를 여러 번 주면 적은 순서대로 곱한다.
 * 축은 손 뼈가 실제로 어디로 가는지 재서 고른다 — docs/features/trainers.md "주먹 쥔 몸".
 */
import { readFileSync, writeFileSync } from 'node:fs';

const [input, output, ...specs] = process.argv.slice(2);
if (!input || !output || specs.length === 0) {
  console.error('사용법: node scripts/rotate-bones.mjs <입력.glb> <출력.glb> <뼈>:<x>,<y>,<z>:<도>[@클립+클립] ...');
  process.exit(1);
}

const buf = readFileSync(input);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const bin = buf.subarray(20 + jsonLen + 8);
const byName = new Map(json.nodes.map((n, i) => [n.name, i]));

/** 쿼터니언 곱 a·b ([x, y, z, w]) */
function mul(a, b) {
  const [ax, ay, az, aw] = a;
  const [bx, by, bz, bw] = b;
  return [
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz,
  ];
}

for (const spec of specs) {
  const [left, clipPart] = spec.split('@');
  const [bone, axisText, degText] = left.split(':');
  const at = byName.get(bone);
  if (at === undefined) throw new Error(`뼈가 없다: ${bone}`);
  if (axisText === 'rest') {
    // 그 클립의 회전 키를 기본 자세 값으로 덮는다 — 바르코 대기가 손목을 모델마다 제멋대로 굽혀서
    const rest = json.nodes[at].rotation ?? [0, 0, 0, 1];
    const clips = clipPart ? clipPart.split('+') : null;
    let keys = 0;
    for (const anim of json.animations ?? []) {
      if (clips && !clips.includes(anim.name)) continue;
      for (const ch of anim.channels) {
        if (ch.target.node !== at || ch.target.path !== 'rotation') continue;
        const acc = json.accessors[anim.samplers[ch.sampler].output];
        const view = json.bufferViews[acc.bufferView];
        const stride = view.byteStride ?? 16;
        const base = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
        for (let i = 0; i < acc.count; i++) rest.forEach((v, k) => bin.writeFloatLE(v, base + i * stride + k * 4));
        keys += acc.count;
      }
    }
    console.log(`  ${bone} 기본 자세로 ${clips ? clips.join('+') : '전부'} — 키 ${keys}개`);
    continue;
  }
  const axis = axisText.split(',').map(Number);
  const len = Math.hypot(...axis);
  if (axis.length !== 3 || !(len > 0)) throw new Error(`축이 이상하다: ${axisText}`);
  const half = (Number(degText) * Math.PI) / 360;
  const r = [...axis.map((v) => (v / len) * Math.sin(half)), Math.cos(half)];
  const clips = clipPart ? clipPart.split('+') : null;
  if (!clips) json.nodes[at].rotation = mul(json.nodes[at].rotation ?? [0, 0, 0, 1], r);
  let keys = 0;
  for (const anim of json.animations ?? []) {
    if (clips && !clips.includes(anim.name)) continue;
    for (const ch of anim.channels) {
      if (ch.target.node !== at || ch.target.path !== 'rotation') continue;
      const acc = json.accessors[anim.samplers[ch.sampler].output];
      const view = json.bufferViews[acc.bufferView];
      if (acc.componentType !== 5126 || acc.type !== 'VEC4') throw new Error('회전 키가 float VEC4 가 아니다');
      const stride = view.byteStride ?? 16;
      const base = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
      for (let i = 0; i < acc.count; i++) {
        const p = base + i * stride;
        const q = [0, 1, 2, 3].map((k) => bin.readFloatLE(p + k * 4));
        mul(q, r).forEach((v, k) => bin.writeFloatLE(v, p + k * 4));
        keys++;
      }
    }
  }
  if (clips && keys === 0) throw new Error(`${bone} 회전 키가 ${clips.join('+')} 에 없다`);
  console.log(`  ${bone} ${axisText} ${degText}° ${clips ? clips.join('+') : '전부 + 기본 자세'} — 키 ${keys}개`);
}

// JSON 길이가 바뀌므로(기본 자세 숫자) 다시 싼다 — 4바이트 맞춤
let text = JSON.stringify(json);
while (Buffer.byteLength(text) % 4) text += ' ';
const jsonBuf = Buffer.from(text);
const binChunk = buf.subarray(20 + jsonLen); // 길이·종류 머리 포함
const head = Buffer.alloc(20);
head.writeUInt32LE(0x46546c67, 0);
head.writeUInt32LE(2, 4);
head.writeUInt32LE(20 + jsonBuf.length + binChunk.length, 8);
head.writeUInt32LE(jsonBuf.length, 12);
head.writeUInt32LE(0x4e4f534a, 16);
writeFileSync(output, Buffer.concat([head, jsonBuf, binChunk]));
console.log(output);
