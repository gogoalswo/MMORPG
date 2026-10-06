/**
 * 트레이너 팔 자세를 입힌다 (2026-10-06, 주먹 쥔 트레이너 — docs/features/trainers.md "주먹 쥔 몸").
 *
 *   node scripts/trainer-arms.mjs <트레이너.glb> <id>
 *
 * 사용자가 n01 시안으로 고른 값: **대기에서만** 윗팔 14° 벌리고 · 팔꿈치 25° 굽히고, **모든 클립**에서 주먹을
 * 바깥으로 60° (왼 아래팔 −60 · 오른 +60, 로컬 +Y). 벌리기·굽히기 축은 뼈대마다 달라서 `godot/tools/arm_axes.gd`
 * 로 잰 값을 `scripts/trainer-arm-axes.json` 에 두고 여기서 읽는다. 굽히기를 비틀기보다 **먼저** 곱한다
 * (비튼 뒤의 축으로 굽히면 손이 엉뚱한 데로 간다). 실제 돌리기는 `rotate-bones.mjs`.
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SPREAD = 14;
export const BEND = 25;
export const TWIST = 60;

const here = dirname(fileURLToPath(import.meta.url));
const [glb, id] = process.argv.slice(2);
if (!glb || !id) {
  console.error('사용법: node scripts/trainer-arms.mjs <트레이너.glb> <id>');
  process.exit(1);
}
const axes = JSON.parse(readFileSync(join(here, 'trainer-arm-axes.json'), 'utf8'))[id];
if (!axes) throw new Error(`${id} 의 팔 축이 trainer-arm-axes.json 에 없다 — godot/tools/arm_axes.gd 로 잰다`);
const ax = (name) => axes[name].join(',');
execFileSync(
  process.execPath,
  [
    join(here, 'rotate-bones.mjs'),
    glb,
    glb,
    `LeftArm:${ax('LeftArm')}:${SPREAD}@Idle`,
    `RightArm:${ax('RightArm')}:${SPREAD}@Idle`,
    `LeftForeArm:${ax('LeftForeArm')}:${BEND}@Idle`,
    `RightForeArm:${ax('RightForeArm')}:${BEND}@Idle`,
    `LeftForeArm:0,1,0:${-TWIST}`,
    `RightForeArm:0,1,0:${TWIST}`,
  ],
  { stdio: 'inherit' },
);
