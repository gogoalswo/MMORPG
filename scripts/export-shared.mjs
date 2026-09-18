/**
 * packages/shared 의 표를 고도가 읽을 JSON 으로 내보낸다.
 *
 * 왜 이렇게 하나 — 수치는 한 곳에만 둔다는 규칙을 언어가 갈려도 지키려고.
 * 존·몬스터·스킬은 TS 의 생성 함수가 원본이고, 고도는 그 **결과만** 읽는다.
 * 덕분에 packages/shared 의 전수 검사(*.test.ts)가 그대로 살아 있다.
 *
 * 아이템도 내보낸다. 한때 뺐지만(2026-09-16) 등급·랜덤옵션·강화를 그대로 가기로
 * 해서 생성기가 그대로 유효하다 (2026-09-17). 표를 고치면 다시 내보내면 된다.
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
  SKILL_COOLDOWN_OFF,
  SKILL_UNLOCK_ALL,
  AUTO_SKILL_TEST_GAP,
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
  GROUND_KINDS,
  GROUND_LOOKS,
  ITEMS,
  EQUIP_SLOTS,
  SLOT_CODE,
  slotLabel,
  JOB_SLOTS,
  INVENTORY_SIZE,
  GRADE_MIN,
  GRADE_MAX,
  MAX_DROP_GRADE,
  OPTION_KINDS,
  OPTION_MIN,
  OPTION_MAX,
  OPTION_LABEL,
  MAX_ENHANCE,
  DROP_CHANCE,
  BOSS_MATERIALS,
  FORGE_MATERIALS,
  TIER_COUNT,
} from '../packages/shared/src/index.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const OUT_DIR = join(ROOT, 'godot', 'data');

/** 내보낼 파일 한 벌. 파일명 → 내용 */
export function buildData() {
  return {
    // groundLooks 는 텍스처에 딸린 성질이다 (타일 크기·러프니스·평균색).
    // 존이 아니라 이미지가 정하는 것이라 존 표와 나란히 둔다
    'zones.json': {
      start: START_ZONE,
      fieldOrder: FIELD_ORDER,
      zones: ZONES,
      groundKinds: GROUND_KINDS,
      groundLooks: GROUND_LOOKS,
    },
    // heights 는 모델을 얼마나 키울지 정한다 (모델 높이는 1 로 정규화돼 있다)
    'monsters.json': {
      kinds: MONSTER_KINDS,
      heights: BEAST_HEIGHT,
      heightDefault: BEAST_HEIGHT_DEFAULT,
    },
    'skills.json': {
      skills: SKILLS,
      byJob: JOB_SKILLS,
      projectileSpeed: PROJECTILE_SPEED,
      // 테스트 스위치. 켜져 있으면 쿨타임 0 · 요구 레벨과 포인트 없음
      cooldownOff: SKILL_COOLDOWN_OFF,
      unlockAll: SKILL_UNLOCK_ALL,
      autoTestGapMs: AUTO_SKILL_TEST_GAP,
    },
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
    'items.json': {
      items: ITEMS,
      slots: EQUIP_SLOTS,
      // 창에 적는 칸 이름
      slotLabels: Object.fromEntries(EQUIP_SLOTS.map((slot) => [slot, slotLabel(slot)])),
      // 드롭이 후보 id 를 만들 때 쓴다 (슬롯 코드 + 직업 + 단계)
      slotCode: SLOT_CODE,
      jobSlots: JOB_SLOTS,
      bagSize: INVENTORY_SIZE,
      gradeMin: GRADE_MIN,
      gradeMax: GRADE_MAX,
      maxDropGrade: MAX_DROP_GRADE,
      optionKinds: OPTION_KINDS,
      optionMin: OPTION_MIN,
      optionMax: OPTION_MAX,
      optionLabel: OPTION_LABEL,
      maxEnhance: MAX_ENHANCE,
      dropChance: DROP_CHANCE,
      bossMaterials: BOSS_MATERIALS,
      forgeMaterials: FORGE_MATERIALS,
      tierCount: TIER_COUNT,
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
