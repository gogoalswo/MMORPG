/**
 * 장비 표 — 밸런스 설계의 **등급 체계**를 그대로 옮긴 것.
 *
 * 원본은 [stat-balance.md](../../../docs/features/stat-balance.md) 3·4장이고,
 * 검증기는 `tools/balance_sim.py` 다. **이 파일의 식은 그 스크립트와 같아야 한다** —
 * 수치를 두 곳에 두지 않으려고 상수도 이름을 맞춰 뒀다(`P` 의 키와 1:1).
 * `gear.test.ts` 가 설계 문서의 표를 그대로 박아 두고 전수로 대조한다.
 *
 * ## 기존 `items.ts` 와 무엇이 다른가
 *
 * | | `items.ts` (지금 도는 것) | 여기 (설계) |
 * |---|---|---|
 * | 축 | 단계 20개(요구 레벨) × 등급 1~10 | **등급 7개**뿐 |
 * | 카탈로그 | 180종 (재료 20 포함) | **56종** |
 *
 * **수치는 2026-09-20 에 붙였다.** `items.ts` 가 `slotStats()` 를 불러 단계마다 %를
 * 뽑고(요구 레벨을 연속 등급으로 보간), 강화 배수·성공률도 여기 표를 쓴다.
 * 그래서 게임은 이미 설계의 숫자로 돈다.
 *
 * **아직 안 바꾼 것은 카탈로그다.** 56종으로 갈아끼우려면 설계 문서 10장이 남겨 둔
 * 세 가지를 먼저 정해야 한다 — 랜덤 옵션을 남길지 · 제작과 재료를 어떻게 할지 ·
 * 보스가 무엇을 떨굴지.
 */
import { JOB_IDS, type JobId } from './character.ts';
import { EQUIP_SLOTS, SLOT_CODE, type EquipSlot } from './slots.ts';

/** 등급 수. 사냥터 20개와 1:1 이 아니다 — 등급 하나가 사냥터 3개(30레벨)를 덮는다 */
export const GRADE_COUNT = 7;
/** 착용 레벨 간격 → 등급 1..7 = Lv 1/31/61/91/121/151/181 */
export const GRADE_LV_SPAN = 30;
/** 등급 1 풀세트의 공격력 % 합계 */
export const GRADE_SUM_START = 35;
/** 등급 7 풀세트의 공격력 % 합계. 치명타·공속 버킷을 뺀 나머지 예산이다 */
export const GRADE_SUM_END = 856;

/**
 * 장비 % 가 축마다 다른 비율로 들어간다.
 *
 * **사냥터 진입을 막는 것은 "맞아서 죽느냐" 이므로 생존은 레벨 쪽에 묶어 둔다.**
 * 저레벨 캐릭이 고등급 장비를 껴도 상위 사냥터에서 두 대 맞고 죽어야 게이팅이
 * 자동으로 걸린다. 반대로 공격력을 장비 쪽에 몰면 파밍이 **사냥 속도**를 올려 줄
 * 뿐 게이팅을 부수지 않는다.
 */
export const GEAR_ATK_FACTOR = 1.0;
export const GEAR_DEF_FACTOR = 0.6;
export const GEAR_HP_FACTOR = 0.35;

/** 등급 7 에서의 치명타 확률 (등급 1 = 0, 그 사이는 선형) */
export const CRIT_RATE_MAX = 0.5;
/** 등급 7 에서의 치명타 추가 피해 */
export const CRIT_DMG_MAX = 1.0;
/** 등급 7 에서의 공격 속도 증가. 애니메이션 클립 재생 속도와 묶여 있어 좁게 잡았다 */
export const ASPD_MAX = 0.2;
/** 등급 7 에서의 이동 속도 증가 */
export const MOVE_SPD_MAX = 0.25;

/** 강화 단계 수 (1단 = 무강이므로 강화는 9번) */
export const ENH_MAX = 10;
/** 1단 → 10단 총 배수 */
export const ENH_TOTAL = 6;
/** 마지막 구간 증가율 / 첫 구간 증가율 — 고강화일수록 크게 */
export const ENH_ACCEL = 7;
/** 2단부터의 성공률. 실패하면 아이템이 파괴된다 (재료 없음) */
export const ENH_ODDS = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1];

/**
 * 슬롯이 스탯 예산에서 가져가는 지분. **스탯마다 열 합계가 1.0 이다.**
 * 설계 문서 "슬롯 6개 — 슬롯마다 주는 스탯이 다르다" 를 그대로 옮겼다.
 *
 * HP 는 방어력과 같은 배분을 쓴다(둘 다 생존 스탯). 치명타는 목걸이, 공속은 반지,
 * 이동속도는 신발 전담이라 **갈아입을 자리가 목적에 따라 갈린다** — 정리 속도는
 * 무기·목걸이·반지가, 생존은 갑옷·투구·신발이 맡는다.
 */
export const SLOT_SHARE: Record<EquipSlot, Partial<Record<GearStat, number>>> = {
  weapon: { atk: 0.6 },
  armor: { df: 0.4, hp: 0.4 },
  helmet: { df: 0.2, hp: 0.2 },
  boots: { df: 0.2, hp: 0.2, move: 1.0 },
  necklace: { atk: 0.2, df: 0.1, hp: 0.1, crit: 1.0, critDamage: 1.0 },
  ring: { atk: 0.2, df: 0.1, hp: 0.1, aspd: 1.0 },
};

export type GearStat = 'atk' | 'df' | 'hp' | 'crit' | 'critDamage' | 'aspd' | 'move';

/** 강화가 곱해지는 스탯. **치명타·공속에는 안 곱한다** — 두 곱산 버킷이 동시에 */
/** 커지면 총 배수 상한을 관리할 수 없다 */
const ENHANCED: GearStat[] = ['atk', 'df', 'hp'];

/** 등급 하나당 풀세트 합계가 몇 배가 되는가. (856/35)^(1/6) = 1.7037 */
export function gradeRatio(): number {
  return (GRADE_SUM_END / GRADE_SUM_START) ** (1 / (GRADE_COUNT - 1));
}

/**
 * 등급 g 풀세트의 공격력 % 합계.
 *
 * **등비가 아니면 후반이 죽는다.** 합산 % 는 수익 체감이 있어서, 등급 간격이
 * 후반에 좁아지는 표를 쓰면 최종 등급 무기를 먹어도 총 피해가 +1.2% 밖에 안 오른다.
 */
export function gradeSum(grade: number): number {
  if (grade <= 0) return 0;
  return GRADE_SUM_START * gradeRatio() ** (Math.min(grade, GRADE_COUNT) - 1);
}

/** 등급 g 를 낄 수 있는 레벨 */
export function equipLevel(grade: number): number {
  return 1 + GRADE_LV_SPAN * (grade - 1);
}

/** 레벨 L 에서 낄 수 있는 최고 등급 */
export function gradeOf(level: number): number {
  const g = 1 + Math.floor((level - 1) / GRADE_LV_SPAN);
  return Math.max(1, Math.min(GRADE_COUNT, g));
}

/** 보조 스탯용 등급 진행도. 등급 1 = 0, 등급 7 = 1 (선형) */
export function gradeProgress(grade: number): number {
  return Math.max(0, (Math.min(grade, GRADE_COUNT) - 1) / (GRADE_COUNT - 1));
}

/**
 * 등급 g 풀세트가 주는 스탯별 **총량**. atk/df/hp 는 기본 스탯 대비 %,
 * 나머지는 비율 그대로다 (치확 0.5 = 50%p).
 *
 * 치명타·공속을 **선형**으로 둔 이유: 등급 1~2 에서 치명타가 거의 없어야 몬스터 HP 가
 * 작은 초반에 타수 편차가 커지지 않는다.
 */
export function statBudget(grade: number): Record<GearStat, number> {
  const s = gradeSum(grade);
  const r = gradeProgress(grade);
  return {
    atk: s * GEAR_ATK_FACTOR,
    df: s * GEAR_DEF_FACTOR,
    hp: s * GEAR_HP_FACTOR,
    crit: CRIT_RATE_MAX * r,
    critDamage: CRIT_DMG_MAX * r,
    aspd: ASPD_MAX * r,
    move: MOVE_SPD_MAX * r,
  };
}

/**
 * 단계별 증가율. 첫 구간 : 마지막 구간 = 1 : `ENH_ACCEL` 이고 전체 곱이 `ENH_TOTAL`.
 * 닫힌 식이 없어 이분법으로 첫 구간을 찾는다 (시뮬레이터와 같은 방법).
 */
export function enhanceGains(): number[] {
  const n = ENH_MAX - 1;
  const k = ENH_ACCEL ** (1 / (n - 1));
  let lo = 1e-5;
  let hi = 1;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    let t = 1;
    for (let j = 0; j < n; j++) t *= 1 + mid * k ** j;
    if (t < ENH_TOTAL) lo = mid;
    else hi = mid;
  }
  return Array.from({ length: n }, (_, i) => lo * k ** i);
}

/** 강화 단계(1~10)의 배수. 1단 = ×1.0, 10단 = ×6.0 */
export function enhanceMultiplier(step: number): number {
  const s = Math.max(1, Math.min(Math.trunc(step), ENH_MAX));
  return enhanceGains()
    .slice(0, s - 1)
    .reduce((m, g) => m * (1 + g), 1);
}

/**
 * 아이템 하나를 굴려 그 단계에 **도달할** 확률. 실패하면 파괴되므로 성공률의 곱이다.
 * 그래서 도달 단계는 "아이템이 몇 개 들어오느냐" 로만 결정된다 — 강화가 공짜인
 * 설계에서는 **드랍률이 경험치 공식과 같은 급의 밸런스 손잡이**다.
 */
export function enhanceReach(step: number): number {
  const s = Math.max(1, Math.min(Math.trunc(step), ENH_MAX));
  return ENH_ODDS.slice(0, s - 1).reduce((p, o) => p * o, 1);
}

/**
 * 슬롯 하나가 주는 수치 — 설계 문서의 `item_pct(grade, slot)` 이 이것이다.
 * atk/df/hp 는 % (기본 스탯에 곱할 값), 치확·치피·공속·이동은 비율.
 */
export function slotStats(
  slot: EquipSlot,
  grade: number,
  enhance = 1
): Record<GearStat, number> {
  const share = SLOT_SHARE[slot];
  const budget = statBudget(grade);
  const mult = enhanceMultiplier(enhance);
  const out = {} as Record<GearStat, number>;
  for (const stat of Object.keys(budget) as GearStat[]) {
    const v = budget[stat] * (share[stat] ?? 0);
    out[stat] = ENHANCED.includes(stat) ? v * mult : v;
  }
  return out;
}

/**
 * 등급 g 아이템이 나오는 사냥터 번호. **착용 레벨보다 한 구간(10레벨) 위**다.
 *
 * 상향 압력의 정체가 이것이다 — 착용 레벨에 도달해도 바로는 얻을 수 없고, 한 구간
 * 더 올라가 **이전 등급으로 뚫어야** 한다.
 */
export function dropField(grade: number): number {
  return Math.min(20, Math.ceil(equipLevel(grade) / 10) + 1);
}

/**
 * 등급별 드랍률(%). **킬당 고정 확률로는 못 정한다** — 드랍 사냥터의 체류 킬 수가
 * 3,375(등급1) ~ 1,189만(등급7)으로 3,500배 차이나기 때문이다. 그래서 "그 사냥터에
 * 머무는 동안 강화 기준 단계를 달성할 만큼" 에서 역산한 값이고, 원본은
 * `python tools/balance_sim.py --drops` 다. 성장 곡선이 바뀌면 다시 뽑아야 한다.
 */
export const GEAR_DROP_RATE = [0.2963, 0.08, 0.0321, 0.0095, 0.0055, 0.0016, 0.0011];

/** 등급 접두어. `items.ts` 의 단계 접두어에서 일곱 개를 골라 톤을 맞췄다 */
const GRADE_PREFIX = ['낡은', '단단한', '강철', '은빛', '고대', '심연', '종말'];

/** 직업을 타는 슬롯은 무기 하나다 */
const WEAPON_NAME: Record<JobId, string> = {
  fighter: '너클',
  mage: '지팡이',
  archer: '활',
};

const SLOT_LABEL: Record<EquipSlot, string> = {
  weapon: '무기',
  armor: '갑옷',
  helmet: '투구',
  boots: '신발',
  necklace: '목걸이',
  ring: '반지',
};

export interface GearDef {
  id: string;
  name: string;
  slot: EquipSlot;
  grade: number;
  /** 착용 레벨 */
  level: number;
  /** 무기만 직업을 탄다 */
  job?: JobId;
  /** 무강(1단) 기준 수치. 강화는 `slotStats(slot, grade, step)` 로 다시 구한다 */
  stats: Record<GearStat, number>;
}

/**
 * 등급 7 × 슬롯 6 = **56종**. 무기만 직업 3벌이라 7 × (3 + 5) 다.
 *
 * 단계 20개짜리 옛 표(180종)보다 훨씬 적다. **아이템 레벨 축을 없앴기 때문**이고,
 * 그게 설계의 핵심이다 — 등급 하나가 30레벨을 덮으므로 그 안에서는 갈아입을 것이
 * 없고, 대신 **강화**와 **다음 등급 착용 레벨**이 성장을 맡는다.
 */
function buildGear(): Record<string, GearDef> {
  const out: Record<string, GearDef> = {};
  for (let grade = 1; grade <= GRADE_COUNT; grade++) {
    const prefix = GRADE_PREFIX[grade - 1]!;
    const level = equipLevel(grade);
    for (const slot of EQUIP_SLOTS) {
      const stats = slotStats(slot, grade);
      if (slot === 'weapon') {
        for (const job of JOB_IDS) {
          const id = `g${grade}_${SLOT_CODE[slot]}_${job}`;
          out[id] = {
            id,
            name: `${prefix} ${WEAPON_NAME[job]}`,
            slot,
            grade,
            level,
            job,
            stats,
          };
        }
        continue;
      }
      const id = `g${grade}_${SLOT_CODE[slot]}`;
      out[id] = { id, name: `${prefix} ${SLOT_LABEL[slot]}`, slot, grade, level, stats };
    }
  }
  return out;
}

export const GEAR_ITEMS: Record<string, GearDef> = buildGear();

/** 그 등급·직업으로 맞출 수 있는 풀세트 6칸 */
export function fullSet(grade: number, job: JobId): GearDef[] {
  return EQUIP_SLOTS.map((slot) =>
    slot === 'weapon'
      ? GEAR_ITEMS[`g${grade}_${SLOT_CODE[slot]}_${job}`]!
      : GEAR_ITEMS[`g${grade}_${SLOT_CODE[slot]}`]!
  );
}
