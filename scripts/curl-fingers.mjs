/**
 * 손가락 뼈의 **기본 자세를 말아 주먹을 쥐게** 한다 — 캐릭터 GLB 를 제자리에서 고친다.
 *
 *   node scripts/curl-fingers.mjs public/assets/models/varco_fighter.glb [말기 배율]
 *
 * 바르코 `Rig`(humanoid-fingers)는 손가락 뼈를 주지만, 3D 생성(`tPose` 1)이 손을 **펴서** 준다
 * (주먹 쥔 원화를 넣어도 펴진다, 2026-09-26). 동작 클립에는 손가락 채널이 없으므로 기본 자세를
 * 말아 두면 **어느 동작에서든 주먹**이다. 스킨은 편 손(inverseBindMatrix)에 묶여 있어서 노드
 * 회전만 바꾸면 메시가 따라 말린다.
 *
 * 뼈 이름: `HandLoRA_Bip01_<L|R>_Finger<손가락><마디>` — 손가락 0 = 엄지, 1~4 = 검지~새끼,
 * 마디는 없음(뿌리)·1·2. 각 마디를 **자기 X 축으로** 돌린다 (손가락이 +Y 로 뻗어 있다).
 */
import { readFileSync, writeFileSync } from 'node:fs';

const [path, scaleArg] = process.argv.slice(2);
const scale = Number(scaleArg ?? 1);
// 마디별 말기 각도(도) — [뿌리, 가운데, 끝]. 부호는 손바닥 쪽 (찍어 보고 정했다)
export const CURL = { finger: [80, 95, 65], thumb: [20, 35, 40] };
export const SIGN = 1;

const buf = readFileSync(path);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf8'));
const rest = buf.subarray(20 + jsonLen);

const qmul = (a, b) => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
];
let count = 0;
for (const node of json.nodes) {
  const m = /Finger(\d)(\d?)$/.exec(node.name ?? '');
  if (!m) continue;
  const joint = m[2] === '' ? 0 : Number(m[2]) % 10 === 1 ? 1 : 2;
  const deg = (m[1] === '0' ? CURL.thumb : CURL.finger)[joint] * scale * SIGN;
  const half = (deg * Math.PI) / 360;
  node.rotation = qmul(node.rotation ?? [0, 0, 0, 1], [Math.sin(half), 0, 0, Math.cos(half)]);
  count += 1;
}
if (!count) throw new Error(`${path}: 손가락 뼈(…Finger…)가 없다 — Rig 를 humanoid-fingers 로 했나`);

let text = Buffer.from(JSON.stringify(json), 'utf8');
const pad = (4 - (text.length % 4)) % 4;
text = Buffer.concat([text, Buffer.alloc(pad, 0x20)]);
const head = Buffer.alloc(20);
head.writeUInt32LE(0x46546c67, 0);
head.writeUInt32LE(2, 4);
head.writeUInt32LE(20 + text.length + rest.length, 8);
head.writeUInt32LE(text.length, 12);
head.writeUInt32LE(0x4e4f534a, 16);
writeFileSync(path, Buffer.concat([head, text, rest]));
console.log(`${path}: 손가락 마디 ${count}개를 말았다 (×${scale})`);
