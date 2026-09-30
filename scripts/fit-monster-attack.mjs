/**
 * 몬스터 표의 **공격력 열만** "한 마리 잡는 동안 HP 10%" 로 다시 굽는다.
 *
 *   node scripts/fit-monster-attack.mjs
 *
 * 2026-09-30 지시: "한 마리 잡는동안 체력을 10% 정도 잃게 만들면 좋겠는데?"
 * 역산식은 `packages/shared/src/monsterAttack.ts` 에 있다. HP·방어력 열과 표 머리 주석은
 * 건드리지 않는다 (`freeze-monsters.mjs` 는 파일을 통째로 다시 써서 그 이력을 지운다).
 *
 * 레벨이 오를 때 역산값이 반올림 탓에 1~2% 내려가는 자리가 있어서 **앞 레벨보다 낮아지지
 * 않게** 누적 최대값을 쓴다 — 그 자리는 10% 를 아주 조금 넘는다.
 *
 * **자동으로 돌지 않는다.** 장비·패시브를 바꿨다고 몬스터가 소리 없이 따라 움직이면 안 된다
 * (표가 고정인 이유). 다시 맞추기로 **정했을 때만** 사람이 부른다.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAX_LEVEL } from '../packages/shared/src/balance.ts';
import { monsterAtkForLoss } from '../packages/shared/src/monsterAttack.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FILE = join(ROOT, 'packages/shared/src/monsterTable.ts');

const fit = [];
let top = 0;
for (let level = 1; level <= MAX_LEVEL; level++) {
  top = Math.max(top, monsterAtkForLoss(level));
  fit.push(Math.round(top * 100) / 100);
}

let row = 0;
const text = readFileSync(FILE, 'utf8').replace(
  /^(\s*\[[\d.]+, )([\d.]+)(, [\d.]+\],)$/gm,
  (_all, head, _atk, tail) => `${head}${fit[row++]}${tail}`
);
if (row !== MAX_LEVEL) throw new Error(`표 줄 수가 ${row} — ${MAX_LEVEL} 이어야 한다`);
writeFileSync(FILE, text, 'utf8');
console.log(`공격력 ${row}줄 -> packages/shared/src/monsterTable.ts (Lv1 ${fit[0]} · Lv100 ${fit[99]} · Lv200 ${fit[199]})`);
