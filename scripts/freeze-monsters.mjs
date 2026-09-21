/**
 * 몬스터 표를 **손으로 고칠 수 있는 고정 수치**로 굽는다.
 *
 *   node scripts/freeze-monsters.mjs
 *
 * 2026-09-21 지시: "몬스터 능력치가 자동으로 역산 되면 안돼. 고정 된 수치로 하고
 * 혹시나 너무 밸런스가 안 맞으면 그때 직접 수치를 계산해서 변경하자."
 *
 * 그전에는 `monsters.json` 을 구울 때마다 **그 자리에서** 장비 설계로 역산했다.
 * 그래서 장비 지분을 손대면 몬스터 체력이 소리 없이 따라 움직였다 (2026-09-21 에
 * 치확 버킷을 걷자 Lv200 이 -30% 가 됐다).
 *
 * **이 스크립트는 자동으로 돌지 않는다.** `npm run export:godot` 도, CI 도 안 부른다.
 * 밸런스를 다시 잡기로 **정했을 때만** 사람이 부르고, 나온 표를 눈으로 보고 커밋한다.
 */
import { writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { monsterByDesign, MAX_LEVEL } from '../packages/shared/src/balance.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'packages/shared/src/monsterTable.ts');

const rows = [];
for (let level = 1; level <= MAX_LEVEL; level++) {
  const m = monsterByDesign(level);
  const r = (v) => Math.round(v * 100) / 100;
  rows.push(`  [${r(m.hp)}, ${r(m.atk)}, ${r(m.df)}],`);
}

writeFileSync(
  OUT,
  `/**
 * 몬스터 능력치 — **고정 표다.** ★★
 *
 * 2026-09-21 지시: "몬스터 능력치가 자동으로 역산 되면 안돼. 고정 된 수치로 하고
 * 혹시나 너무 밸런스가 안 맞으면 그때 직접 수치를 계산해서 변경하자."
 *
 * 레벨 1부터 ${MAX_LEVEL} 까지 \`[HP, 공격력, 방어력]\` 이다. 역할 배수(정예·보스)와
 * 경험치(HP × 0.2)는 여기 없다 — \`balance.ts\` 의 \`monster()\` 가 얹는다.
 *
 * **이 파일은 손으로 고치는 파일이다.** 한 줄만 고쳐도 되고, 전부 다시 뽑고 싶으면
 * \`node scripts/freeze-monsters.mjs\` 를 **사람이** 부른다 (설계 역산값으로 덮어쓴다).
 * 빌드도 CI 도 이 스크립트를 부르지 않는다.
 *
 * 처음 구운 값은 설계 역산(\`monsterByDesign\`)이고, 그 근거는
 * [stat-balance.md](../../../docs/features/stat-balance.md) 6장이다.
 */
export const MONSTER_STATS: Array<[hp: number, atk: number, df: number]> = [
${rows.join('\n')}
];
`,
  'utf8'
);
console.log(`몬스터 표 ${rows.length}줄 -> packages/shared/src/monsterTable.ts`);
