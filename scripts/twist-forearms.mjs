/**
 * 아래팔을 **제 축(뼈 방향, 로컬 +Y)으로 비튼다** — 모든 클립의 `LeftForeArm` · `RightForeArm` 회전 키와 기본 자세에.
 *
 * 왜 (2026-10-06 요청: "주먹이 너무 정면으로 되어 있는데, 허리에 붙이고 있는 것 처럼 살짝 돌릴 수 있어?") —
 * 트레이너를 주먹 쥔 A 자세로 다시 뽑았더니 원화대로 **주먹 안쪽(손가락)이 정면**을 봤다. 사람이 팔뚝을 안으로
 * 돌리듯(엎침) 아래팔째 돌리면 손바닥이 허벅지 쪽, 주먹 등이 바깥을 본다. 손 뼈만 돌리면 손목이 꽈배기처럼 꼬인다.
 *
 *   node scripts/twist-forearms.mjs <입력.glb> <출력.glb> <각도(도)>
 *
 * 왼팔은 +각도, 오른팔은 −각도 (좌우 거울). 키 값만 같은 자리에서 바꾸므로 파일 크기는 그대로다.
 * 뼈 축이 +Y 인지는 손 뼈의 이동(부모 기준)이 +Y 쪽인지로 확인하고, 아니면 멈춘다.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const [input, output, degText] = process.argv.slice(2);
if (!input || !output || degText === undefined) {
  console.error('사용법: node scripts/twist-forearms.mjs <입력.glb> <출력.glb> <각도(도)>');
  process.exit(1);
}
const deg = Number(degText);

const buf = readFileSync(input);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const binStart = 20 + jsonLen + 8;
const bin = buf.subarray(binStart);

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

const sides = [
  ['Left', deg],
  ['Right', -deg],
];
let keys = 0;
for (const [side, angle] of sides) {
  const arm = byName.get(`${side}ForeArm`);
  const hand = byName.get(`${side}Hand`);
  if (arm === undefined || hand === undefined) throw new Error(`${side}ForeArm / ${side}Hand 뼈가 없다`);
  const t = json.nodes[hand].translation ?? [0, 0, 0];
  if (!(t[1] > Math.abs(t[0]) * 5 && t[1] > Math.abs(t[2]) * 5)) {
    throw new Error(`${side}Hand 가 아래팔의 +Y 쪽에 있지 않다 (${t}) — 뼈 축이 다르다`);
  }
  const half = (angle * Math.PI) / 360;
  const twist = [0, Math.sin(half), 0, Math.cos(half)];
  // 기본 자세 — 클립이 안 도는 순간(창의 정지 그림 등)에도 같은 쪽을 보게
  const node = json.nodes[arm];
  node.rotation = mul(node.rotation ?? [0, 0, 0, 1], twist);
  for (const anim of json.animations ?? []) {
    for (const ch of anim.channels) {
      if (ch.target.node !== arm || ch.target.path !== 'rotation') continue;
      const acc = json.accessors[anim.samplers[ch.sampler].output];
      const view = json.bufferViews[acc.bufferView];
      if (acc.componentType !== 5126 || acc.type !== 'VEC4') throw new Error('회전 키가 float VEC4 가 아니다');
      const stride = view.byteStride ?? 16;
      const base = (view.byteOffset ?? 0) + (acc.byteOffset ?? 0);
      for (let i = 0; i < acc.count; i++) {
        const at = base + i * stride;
        const q = [0, 1, 2, 3].map((k) => bin.readFloatLE(at + k * 4));
        const r = mul(q, twist);
        r.forEach((v, k) => bin.writeFloatLE(v, at + k * 4));
        keys++;
      }
    }
  }
}

// JSON 길이가 바뀌므로(기본 자세 숫자) 다시 싼다 — 4바이트 맞춤
let text = JSON.stringify(json);
while (Buffer.byteLength(text) % 4) text += ' ';
const jsonBuf = Buffer.from(text);
const head = Buffer.alloc(12);
head.writeUInt32LE(0x46546c67, 0);
head.writeUInt32LE(2, 4);
const binChunk = buf.subarray(20 + jsonLen); // 길이·종류 머리 포함
head.writeUInt32LE(12 + 8 + jsonBuf.length + binChunk.length, 8);
const jsonHead = Buffer.alloc(8);
jsonHead.writeUInt32LE(jsonBuf.length, 0);
jsonHead.writeUInt32LE(0x4e4f534a, 4);
writeFileSync(output, Buffer.concat([head, jsonHead, jsonBuf, binChunk]));
console.log(`${output}: 아래팔 ±${deg}° 비틀기 — 키 ${keys}개`);
