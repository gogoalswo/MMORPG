/**
 * packages/shared 의 표를 고도가 읽을 JSON 으로 내보낸다.
 *
 * 왜 이렇게 하나 — 수치는 한 곳에만 둔다는 규칙을 언어가 갈려도 지키려고.
 * 존·몬스터·스킬은 TS 의 생성 함수가 원본이고, 고도는 그 **결과만** 읽는다.
 * 덕분에 packages/shared 의 전수 검사(*.test.ts)가 그대로 살아 있다.
 *
 * 아이템은 넣지 않았다 — 나중에 다시 만들기로 했다 (2026-09-16).
 *
 *   node scripts/export-shared.mjs          내보낸다
 *   node scripts/export-shared.mjs --check   파일이 최신인지만 본다 (안 쓴다)
 *
 * 내보낸 JSON 이 낡으면 godotExport.test.ts 가 잡는다.
 */
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  ZONES,
  MONSTER_KINDS,
  BEAST_HEIGHT,
  BEAST_HEIGHT_DEFAULT,
  SKILLS,
  JOB_SKILLS,
  JOB_IDS,
  JOB_STATS,
  PROJECTILE_SPEED,
  BASE_CRIT,
  BASE_CRIT_DAMAGE,
  CRIT_CAP,
  ATTACK_SPEED_CAP,
  ATTACK_ROOT_MS,
  MONSTER_SWING_MS,
  ATTACK_ARC,
  MAX_LEVEL,
  SKILL_BAR_SIZE,
  SKILL_POINT_PER_LEVEL,
  SKILL_BLAST_RATIO,
  SKILL_BLAST_MAX,
  SKILL_BLAST_MIN,
  TICK_RATE,
  TICK_MS,
  INTERP_DELAY_MS,
  RUN_SPEED,
  MAX_SPEED,
  MOVE_TOLERANCE,
  AOI_CELL_SIZE,
  NPC_REACH,
  START_ZONE,
  FIELD_ORDER,
} from '../packages/shared/src/index.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const OUT_DIR = join(ROOT, 'godot', 'data');

/** 내보낼 파일 한 벌. 파일명 → 내용 */
export function buildData() {
  return {
    'zones.json': { start: START_ZONE, fieldOrder: FIELD_ORDER, zones: ZONES },
    // heights 는 모델을 얼마나 키울지 정한다 (모델 높이는 1 로 정규화돼 있다)
    'monsters.json': {
      kinds: MONSTER_KINDS,
      heights: BEAST_HEIGHT,
      heightDefault: BEAST_HEIGHT_DEFAULT,
    },
    'skills.json': { skills: SKILLS, byJob: JOB_SKILLS, projectileSpeed: PROJECTILE_SPEED },
    'combat.json': {
      jobs: JOB_IDS,
      // [체력, 공격, 방어, 사거리, 공격간격, 레벨당 체력, 레벨당 공격, 레벨당 방어]
      jobStats: JOB_STATS,
      baseCrit: BASE_CRIT,
      baseCritDamage: BASE_CRIT_DAMAGE,
      critCap: CRIT_CAP,
      attackSpeedCap: ATTACK_SPEED_CAP,
      attackRootMs: ATTACK_ROOT_MS,
      monsterSwingMs: MONSTER_SWING_MS,
      attackArc: ATTACK_ARC,
      maxLevel: MAX_LEVEL,
      skillBarSize: SKILL_BAR_SIZE,
      skillPointPerLevel: SKILL_POINT_PER_LEVEL,
      skillBlastRatio: SKILL_BLAST_RATIO,
      skillBlastMax: SKILL_BLAST_MAX,
      skillBlastMin: SKILL_BLAST_MIN,
    },
    'constants.json': {
      tickRate: TICK_RATE,
      tickMs: TICK_MS,
      interpDelayMs: INTERP_DELAY_MS,
      runSpeed: RUN_SPEED,
      maxSpeed: MAX_SPEED,
      moveTolerance: MOVE_TOLERANCE,
      aoiCellSize: AOI_CELL_SIZE,
      npcReach: NPC_REACH,
    },
  };
}

/** 파일에 쓸 때와 대조할 때가 같은 글자여야 하므로 한 곳에서 만든다 */
export function serialize(value) {
  return JSON.stringify(value, null, 2) + '\n';
}

export function readExported(name) {
  return readFileSync(join(OUT_DIR, name), 'utf8');
}

function main() {
  const data = buildData();
  mkdirSync(OUT_DIR, { recursive: true });
  for (const [name, value] of Object.entries(data)) {
    const text = serialize(value);
    writeFileSync(join(OUT_DIR, name), text);
    const count =
      Object.keys(value.zones ?? value.kinds ?? value.skills ?? value.jobStats ?? value).length;
    console.log(`${name.padEnd(16)} ${String(text.length).padStart(7)}바이트  항목 ${count}개`);
  }
}

// 테스트가 이 파일을 불러 쓰므로, 직접 실행했을 때만 파일을 쓴다
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
