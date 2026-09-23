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

import { balanceTable } from '../packages/shared/src/balance.ts';
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
  COOLDOWN_CAP,
  PENETRATION_CAP,
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
  dropGradesFor,
  OPTION_KINDS,
  OPTION_MIN,
  OPTION_MAX,
  OPTION_TIERS,
  MATERIALS,
  CRYSTAL_ID,
  CRYSTAL_DROP_CHANCE,
  OPTION_LABEL,
  LEGACY_OPTION_LABEL,
  MAX_ENHANCE,
  gradeLevel,
  gradeName,
  GRADE_COLOR,
} from '../packages/shared/src/index.ts';
// `index.ts` 가 gear.ts 를 다시 내보내지 않는다 — 설계 표는 직접 가져온다
import { GEAR_DROP_RATE } from '../packages/shared/src/gear.ts';

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
    // 밸런스 설계(stat-balance.md)의 수치. **아직 게임이 안 읽는다** — 판정은
    // 여전히 combat.json 으로 돈다. 설계 문서 9장 순서대로 stats.gd 가 먼저 서야 한다
    'balance.json': balanceTable(),
    'combat.json': {
      jobs: JOB_IDS,
      // [체력, 공격, 방어, 사거리, 공격간격, 레벨당 체력, 레벨당 공격, 레벨당 방어]
      jobStats: JOB_STATS,
      baseCrit: BASE_CRIT,
      baseCritDamage: BASE_CRIT_DAMAGE,
      // 치확·공속은 상한이 없다 (2026-09-23). 이 둘만 90% 에서 멈춘다
      cooldownCap: COOLDOWN_CAP,
      penetrationCap: PENETRATION_CAP,
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
      // 드롭이 후보 id 를 만들 때 쓴다 (`g{등급}_{슬롯코드}`)
      slotCode: SLOT_CODE,
      jobSlots: JOB_SLOTS,
      bagSize: INVENTORY_SIZE,
      gradeMin: GRADE_MIN,
      gradeMax: GRADE_MAX,
      maxDropGrade: MAX_DROP_GRADE,
      // 사냥터(1~20)마다 나오는 등급들 — 고도는 표만 읽고 역산하지 않는다.
      // 칸 0 은 안 쓴다(사냥터 번호가 1부터다)
      dropGrades: [[], ...Array.from({ length: 20 }, (_, i) => dropGradesFor(i * 10 + 1))],
      optionKinds: OPTION_KINDS,
      optionMin: OPTION_MIN,
      optionMax: OPTION_MAX,
      // 옵션 차수 — 1차는 드랍, 2차는 크리스탈, 3차는 비워 둔다 (2026-09-23)
      optionTiers: OPTION_TIERS,
      // 장비가 아닌 가방 물건 (크리스탈). 가방에는 `{ id, count }` 로 겹쳐 쌓인다
      materials: MATERIALS,
      crystalId: CRYSTAL_ID,
      crystalDropChance: CRYSTAL_DROP_CHANCE,
      optionLabel: OPTION_LABEL,
      // 저장된 옛 아이템에만 남은 옵션(공격력·방어력)의 이름 — 판정은 세지 않는다
      legacyOptionLabel: LEGACY_OPTION_LABEL,
      maxEnhance: MAX_ENHANCE,
      // 등급별 킬당 드랍률 — **퍼센트 단위**다 (0.2963 = 0.2963%).
      // 설계(stat-balance.md 7장)가 "그 사냥터 체류 중에 목표 개수를 채운다"
      // 에서 역산한 값이라, 합계 하나로는 못 줄이고 등급마다 따로 둔다
      gradeDropRate: GEAR_DROP_RATE,
      // 등급별 착용 레벨 (1·31·61·91·121·151·181). 고도는 이걸로 "이 레벨에서
      // 낄 수 있는 최고 등급" 을 찾는다 — 30레벨 간격을 두 곳에 적지 않으려고 표로 준다
      gradeLevels: Array.from({ length: MAX_DROP_GRADE }, (_, i) => gradeLevel(i + 1)),
      // 등급 이름과 색 (일반 → 태초). 가방 상세 창이 이름을 이 색으로 적는다
      gradeNames: Array.from({ length: MAX_DROP_GRADE }, (_, i) => gradeName(i + 1)),
      gradeColors: GRADE_COLOR,
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
