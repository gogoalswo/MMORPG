/**
 * 트레이너 팔 자세를 입힌다 (2026-10-06, 주먹 쥔 트레이너 — docs/features/trainers.md "주먹 쥔 몸").
 *
 *   node scripts/trainer-arms.mjs <트레이너.glb> <id>
 *
 * **대기에서만** 윗팔 12° 벌리고 · 팔꿈치 8° 굽힌다 (처음 14° · 25° — "주먹을 너무 앞으로 뻗었어. 살짝 골반 방향으로").
 * **모든 클립**에서 아래팔을 제 축(+Y)으로 비틀어 주먹 방향을 맞춘다 — 각도는 **모델마다 다르다** (2026-10-07,
 * "첫 번째 스샷은 주먹 방향이 이상해. 두 번째(n01)처럼"). 모두 ±60° 로 돌렸더니 주먹이 조각된 방향이 모델마다 달라
 * 어떤 모델은 엉뚱한 쪽을 봤다. `godot/tools/fist_twist.gd` 가 대기 자세 손바닥이 n01 과 같은 쪽을 보는 각도를 찾아
 * `twist: [왼, 오른]` 으로 둔다. 벌리기·굽히기 축도 뼈대마다 달라 `godot/tools/arm_axes.gd` 로 잰다 —
 * 둘 다 `scripts/trainer-arm-axes.json`. 굽히기를 비틀기보다 **먼저** 곱한다. 실제 돌리기는 `rotate-bones.mjs`.
 *
 *   node scripts/trainer-arms.mjs <트레이너.glb> <id> [--no-twist]   (--no-twist: 비틀 각도를 잴 때)
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SPREAD = 12;
export const BEND = 8;

const here = dirname(fileURLToPath(import.meta.url));
const noTwist = process.argv.includes('--no-twist');
const [glb, id] = process.argv.slice(2).filter((a) => a !== '--no-twist');
if (!glb || !id) {
  console.error('사용법: node scripts/trainer-arms.mjs <트레이너.glb> <id>');
  process.exit(1);
}
const axes = JSON.parse(readFileSync(join(here, 'trainer-arm-axes.json'), 'utf8'))[id];
if (!axes) throw new Error(`${id} 의 팔 축이 trainer-arm-axes.json 에 없다 — godot/tools/arm_axes.gd 로 잰다`);
const ax = (name) => axes[name].join(',');
// 손목은 **조각된 대로 곧게** — 바르코 대기가 모델마다 손목을 제멋대로 굽혀 주먹이 꺾여 보였다 (2026-10-07 "주먹이 꺾여있고")
const specs = [
  'LeftHand:rest@Idle',
  'RightHand:rest@Idle',
  `LeftArm:${ax('LeftArm')}:${SPREAD}@Idle`,
  `RightArm:${ax('RightArm')}:${SPREAD}@Idle`,
  `LeftForeArm:${ax('LeftForeArm')}:${BEND}@Idle`,
  `RightForeArm:${ax('RightForeArm')}:${BEND}@Idle`,
];
// 발차기(파이터에게서 옮긴 클립)는 **손가락·손목 키까지** 가져와서, 파이터의 편 손이 조각된 주먹 위에 덮여 갈퀴 손이 됐다
// (2026-10-07 "이게 사람 손 이냐?"). 발차기에서도 손가락·손목은 조각된 대로 둔다
const KICKS = 'KickSlapFull+KickSlapIn+KickSlapA+KickSlapB';
for (const s of ['L', 'R']) {
  specs.push(`${s === 'L' ? 'Left' : 'Right'}Hand:rest@${KICKS}`);
  for (let f = 0; f < 5; f++) for (const k of ['', '1', '2']) specs.push(`HandLoRA_Bip01_${s}_Finger${f}${k}:rest@${KICKS}`);
}
if (!noTwist) {
  if (!axes.twist) throw new Error(`${id} 의 주먹 비틀기가 trainer-arm-axes.json 에 없다 — godot/tools/fist_twist.gd 로 잰다`);
  specs.push(`LeftForeArm:0,1,0:${axes.twist[0]}`, `RightForeArm:0,1,0:${axes.twist[1]}`);
}
// 차렷 좌우 대칭 — 바르코 대기가 몸통을 살짝 비틀어 골반 기준 손목이 한쪽만 15% 바깥이었다 (2026-10-07 "왼손이랑 오른손이랑
// 차렷 자세 위치가 다르자나?"). `godot/tools/hand_sym.gd` 가 위 자세를 다 입은 몸에서 잰 윗팔 돌림이라 **맨 뒤에** 곱한다
if (!noTwist && axes.sym) {
  for (const bone of ['LeftArm', 'RightArm']) {
    const [x, y, z, deg] = axes.sym[bone];
    specs.push(`${bone}:${x},${y},${z}:${deg}@Idle`);
  }
}
execFileSync(process.execPath, [join(here, 'rotate-bones.mjs'), glb, glb, ...specs], { stdio: 'inherit' });
