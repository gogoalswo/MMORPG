import type { JobId } from './character.ts';
import { SKILL_EXP_BOOKS } from './skills.ts';

/**
 * 아이템과 드롭.
 *
 * 몬스터와 같은 방식으로 **표에서 만든다.** 축은 **등급 7개 하나뿐**이고
 * (일반 → 태초), 등급마다 슬롯 6칸을 채워 **42종**이다. 수치는 설계 표
 * (`gear.ts`)가 내는 것을 그대로 담는다 — 여기서 새로 짓지 않는다.
 *
 * ## 2026-09-21 — 단계 20개 축을 없앴다 ★★
 *
 * 그 전에는 사냥터 20곳에 맞춘 **단계 20개 × 등급 1~10** 이라 160종이었다.
 * 설계([stat-balance.md](../../../docs/features/stat-balance.md))는 처음부터
 * 등급 7개짜리였는데 카탈로그만 옛 축에 남아 있었고, 두 축이 겹쳐 "단계는
 * 높은데 등급이 낮은 물건" 의 자리를 설명할 수 없었다. 지시대로 **7등급으로
 * 합쳤다.**
 *
 * 같이 정한 것:
 * - **직업별로 나누지 않는다** — 전 직업이 같은 장비를 쓴다. 무기도 한 벌이다.
 * - **랜덤 옵션은 남긴다** — 같은 등급 안의 편차를 옵션이 맡는다.
 * - 등급 하나가 30레벨을 덮으므로(착용 Lv 1·31·61·91·121·151·181) 그 안에서
 *   갈아입을 것이 없다. 대신 **강화**가 그 구간의 성장을 맡는다.
 */

// 슬롯 정의는 `slots.ts` 로 옮겼다 — 여기서 `gear.ts` 를 임포트하게 되면서
// 서로를 부르는 순환이 되기 때문이다. 그대로 다시 내보내니 부르는 쪽은 그대로다
export { EQUIP_SLOTS, SLOT_CODE, slotLabel, type EquipSlot } from './slots.ts';
import { EQUIP_SLOTS, SLOT_CODE, type EquipSlot } from './slots.ts';
import { fieldOf } from './balance.ts';
import {
  ENH_MAX as GEAR_ENH_MAX,
  ENH_ODDS as GEAR_ENH_ODDS,
  OPTION_KINDS,
  optionCount as gearOptionCount,
  optionRange as gearOptionRange,
  optionScale as gearOptionScale,
  type OptionKind,
  GRADE_COUNT as GEAR_GRADE_COUNT,
  GRADE_NAME,
  gearName,
  equipLevel as gearEquipLevel,
  gradeOf as gearGradeOf,
  enhanceMultiplier as gearEnhanceMultiplier,
  slotStats,
  dropGrades as gearDropGrades,
  GEAR_DROP_RATE,
} from './gear.ts';

/** 장비가 더해주는 능력치 */
export interface ItemBonus {
  attack?: number;
  defense?: number;
  maxHp?: number;
  /** 치명타 확률, **퍼센트 포인트 정수** (50 = +50%p). 목걸이 전담 */
  crit?: number;
  /** 공격 속도, **퍼센트 정수** (20 = +20%). 반지 전담 */
  attackSpeed?: number;
}

export interface ItemDef {
  id: string;
  name: string;
  /** 지금은 전부 장비다. `null` 자리는 착용 못 하는 물건을 위해 남겨 뒀다 */
  slot: EquipSlot | null;
  /** 등급 1~7. **이게 유일한 성능 축이다** */
  grade: number;
  /** 착용 가능한 최소 레벨 — 등급이 정한다 (1·31·61·91·121·151·181) */
  level: number;
  /**
   * 직업 전용 장비 — **지금은 아무도 안 쓴다.** 2026-09-21 에 장비를 전 직업
   * 공용으로 바꾸면서 비었다. 막는 자리(`canEquip`)는 남겨 둔다
   */
  job?: JobId;
  bonus: ItemBonus;
  /** 상점에 팔 때 받는 금액 */
  price: number;
}

/** 가방 칸 수 */
export const INVENTORY_SIZE = 200;

/**
 * 등급별 색.
 *
 * 갑옷·신발은 모델에 갈아입힐 메시가 없다. 그래서 **몸통과 다리 색을 바꾼다** —
 * 등급이 오르며 색이 변하면 "다른 걸 입었다"로는 읽힌다. 흙빛에서 시작해
 * 태초에서 가장 밝다. 단계 20색짜리 옛 표에서 일곱 칸을 고른 것이다.
 */
export const GRADE_COLOR = [
  '#8a7a5e', '#7f8a92', '#6f8a5a', '#c9a94a', '#b054b0', '#3f6e8c', '#a83a44',
];

/** 등급 번호(1~7)에서 착용 레벨 — 1·31·61·91·121·151·181 */
export function gradeLevel(grade: number): number {
  return gearEquipLevel(grade);
}

/** 등급 이름 (일반 → 태초) */
export function gradeName(grade: number): string {
  return GRADE_NAME[Math.max(0, Math.min(GRADE_NAME.length - 1, Math.trunc(grade) - 1))]!;
}

/**
 * 슬롯마다 성격이 다르다. **배분은 설계 문서의 슬롯 표를 그대로 쓴다**
 * ([stat-balance.md](../../../docs/features/stat-balance.md) 의 "슬롯 6개").
 * 스탯마다 예산을 100% 로 보고 슬롯이 나눠 갖는다:
 *
 * | 슬롯 | 공격력 | 방어력·HP | 치명타 | 공속 |
 * |---|---|---|---|---|
 * | 무기 | **60%** | — | — | — |
 * | 갑옷 | — | **40%** | — | — |
 * | 투구 | — | 20% | — | — |
 * | 신발 | — | 20% | — | — |
 * | 목걸이 | 20% | 10% | **100%** | — |
 * | 반지 | 20% | 10% | — | **100%** |
 *
 * 2026-09-18 에 맞췄다. 그전에는 무기가 공격 예산의 51% 였고 **치확·공속은 아예
 * 안 줬다** — 랜덤 옵션으로만 붙었다. 그래서 목걸이와 반지가 "공격 조금 주는
 * 물건" 으로 겹쳐 있었는데, 지금은 치명타는 목걸이, 공격 속도는 반지 전담이라
 * 갈아입을 자리가 목적에 따라 갈린다.
 *
 * 치확·공속 계수는 설계표의 등급별 수치를 **레벨 선형으로 정확히 재현한다** —
 * 착용 레벨 1·31·61·91·121·151·181 에서 치확 0·8·17·25·33·42·50%p,
 * 공속 0·3·7·10·13·17·20% 가 그대로 나온다.
 *
 * 이동속도(설계표에서 신발 100%)는 **아직 안 넣었다** — 지금 스탯 모델에 이동속도가
 * 없고, 넣으면 movement 와 예측 보정까지 같이 봐야 한다.
 */
/**
 * 그 등급 그 슬롯의 기본 수치. **설계 표가 내는 값을 그대로 담는다.**
 *
 * 2026-09-21 까지는 요구 레벨을 연속 등급으로 **보간**해서 단계 20개를 채웠다.
 * 등급이 곧 축이 된 지금은 보간할 것이 없다 — `slotStats(slot, grade)` 가
 * 설계표의 그 칸이다 (등급1 무기 공 21%, 등급7 무기 공 514% …).
 */
function bonusFor(slot: EquipSlot, grade: number): ItemBonus {
  const s = slotStats(slot, grade);
  return {
    attack: Math.round(s.atk * 10) / 10,
    defense: Math.round(s.df * 10) / 10,
    maxHp: Math.round(s.hp * 10) / 10,
    // 치확·공속은 퍼센트 포인트 정수로 담는다 (`stackStats` 가 /100 한다)
    crit: Math.round(s.crit * 100),
    attackSpeed: Math.round(s.aspd * 100),
  };
}

// SLOT_CODE 는 slots.ts 로 갔다 (위에서 다시 내보낸다)

/**
 * 직업을 타는 슬롯 — **이제 없다.**
 *
 * 2026-09-21 지시: "직업별 장비는 동일해". 무기까지 전 직업 공용이라 빈 표다.
 * 이름을 남겨 두는 이유는 `items.json` 으로 나가고 있어서다 — 고도가 읽기를
 * 그만둔 뒤에도 키가 사라지면 옛 빌드가 깨진다.
 */
export const JOB_SLOTS: EquipSlot[] = [];

/** 아이템 id — `g{등급}_{슬롯코드}`. 설계 표(`gear.ts`)와 같은 규칙이다 */
export function itemId(grade: number, slot: EquipSlot): string {
  return `g${grade}_${SLOT_CODE[slot]}`;
}

/**
 * 그 레벨에서 낄 수 있는 가장 높은 등급 (1~7).
 *
 * 단계 축이 있던 때의 `tierForLevel` 자리다 — 상점 진열과 저장 복원이 쓴다.
 */
export function gradeForLevel(level: number): number {
  return Math.max(GRADE_MIN, Math.min(GRADE_MAX, Math.floor(gearGradeOf(level))));
}

/**
 * 등급 7 × 슬롯 6 = **42종.**
 *
 * 이름은 `등급 이름 + 슬롯 이름` 이다 ("일반 무기" … "태초 반지"). 무기를
 * 너클·지팡이·활로 나누지 않는 것은 장비가 직업을 안 타기 때문이고, 손에
 * 들리는 **모델은 직업이 정한다** — 같은 "전설 무기" 가 법사에게는 지팡이다.
 */
function buildItems(): Record<string, ItemDef> {
  const out: Record<string, ItemDef> = {};

  for (let grade = 1; grade <= GEAR_GRADE_COUNT; grade++) {
    const level = gradeLevel(grade);
    // 값은 착용 레벨을 따라간다 — 등급이 오르면 성능은 등비(×1.7)로 뛰지만
    // 골드 수입은 레벨에 비례해서 는다. 값까지 등비로 두면 상점이 닫힌다
    const price = Math.round(20 + level * 12);

    for (const slot of EQUIP_SLOTS) {
      const id = itemId(grade, slot);
      out[id] = {
        id,
        name: gearName(grade, slot),
        slot,
        grade,
        level,
        bonus: bonusFor(slot, grade),
        price,
      };
    }
  }

  return out;
}

export const ITEMS: Record<string, ItemDef> = buildItems();

export function getItem(id: string): ItemDef | null {
  return ITEMS[id] ?? null;
}

/**
 * 옛 id 를 지금 id 로 — **한 번 쓰고 버릴 다리다.** ★
 *
 * 2026-09-21 에 단계 20개 축을 없애면서 `w_fighter_07`·`a_07` 같은 id 가 전부
 * 사라졌다. 그냥 두면 **가방이 통째로 빈다** — 저장에 남은 것이 표에 없으면
 * 버리는 게 원래 규칙이라서다. 단계는 요구 레벨을 거쳐 등급으로 옮길 수 있으므로
 * (단계 7 = Lv70 = 3등급) 자리만 맞춰 준다. 수치는 그 등급의 것으로 다시 계산된다.
 *
 * 옛 저장이 다 지나가면 지워도 된다.
 */
export function migrateItemId(id: string): string | null {
  if (ITEMS[id]) return id;
  const match = /^([a-z])(?:_(?:fighter|mage|archer))?_(\d{2})$/.exec(id);
  if (!match) return null;
  const slot = EQUIP_SLOTS.find((s) => SLOT_CODE[s] === match[1]);
  if (!slot) return null; // 제작 재료(`m_XX`)는 갈 자리가 없다 — 버린다
  const tier = Number(match[2]);
  return itemId(gradeForLevel(tier === 0 ? 1 : tier * 10), slot);
}

// materialIdFor 는 제작과 함께 없앴다

/** 이 캐릭터가 낄 수 있는 장비인지 — 서버가 반드시 다시 확인해야 한다 */
export function canEquip(item: ItemDef, job: JobId, level: number): boolean {
  if (!item.slot) return false; // 슬롯이 없는 것은 못 낀다
  if (item.job && item.job !== job) return false;
  return level >= item.level;
}

// ---------------------------------------------------------------- 등급

/**
 * 등급 — **축이 이것 하나다.** ★★
 *
 * 2026-09-21 까지는 단계(요구 레벨)와 등급(1~10) 두 축이 겹쳐 있었다. 지금은
 * 등급이 곧 아이템이다: "전설 무기" 는 5등급 무기 하나뿐이고, 등급이 성능
 * (등비 ×1.7037)·착용 레벨·나오는 사냥터를 전부 정한다.
 *
 * 가방에 든 물건의 `grade` 는 이제 **카탈로그에서 따라온 값**이라 id 와 어긋날
 * 수 없다 — 불러올 때 `getItem(id).grade` 로 다시 맞춘다.
 */
export const GRADE_MIN = 1;
export const GRADE_MAX = GEAR_GRADE_COUNT;
/**
 * 드롭으로 나올 수 있는 최고 등급 — **7등급, 즉 전부.**
 *
 * 등급이 유일한 축이 되면서 "드롭 상한" 이라는 개념 자체가 없어졌다. 어느
 * 등급을 언제 얻는지는 사냥터가 정한다(`dropGrades`) — 7등급은 마지막
 * 사냥터에서만 뚫린다. 부르는 쪽이 많아 이름은 남겨 둔다.
 */
export const MAX_DROP_GRADE = GRADE_MAX;

/**
 * 등급이 올릴 **값** 배율 — 1등급이 기준이다.
 *
 * 능력치에는 더 이상 곱하지 않는다. 기본 공격력·방어력은 고정이고, 등급이
 * 하는 일은 붙는 옵션의 범위를 넓히는 것이다(optionRange). 여기 남은 쓰임은
 * 판매가와 제작 수수료뿐이다.
 */
export function gradeMultiplier(grade: number): number {
  const g = Math.min(GRADE_MAX, Math.max(GRADE_MIN, Math.round(grade)));
  return 1 + (g - 1) * 0.3;
}

/** 가방에 든 물건 하나 */
export interface ItemStack {
  id: string;
  grade: number;
  /** 강화 수치 (+0 ~ +10). 없으면 0 */
  enhance?: number;
  /**
   * **1차 옵션** — 만들어질 때(드랍·상점) 굴린 1개.
   *
   * **물건마다 다르다.** 같은 이름·등급이라도 이게 다르면 다른 물건이라
   * 가방에서도 한 칸에 겹치지 않는다.
   */
  options?: ItemOption[];
  /** **2차 옵션** — 크리스탈로 붙인다. 쓸 때마다 통째로 다시 굴린다 (`OPTION_TIERS`) */
  options2?: ItemOption[];
  /** **3차 옵션** — 자리만 있다. 붙이는 방법이 아직 없다 */
  options3?: ItemOption[];
  /** 재료(크리스탈)만 겹쳐 쌓는다. 장비는 늘 1 */
  count?: number;
}

// ---------------------------------------------------------------- 옵션

/**
 * 랜덤 옵션.
 *
 * 기본 공격력·방어력은 아이템에 고정으로 박혀 있고(bonusFor), 그 위에 이게
 * 1~3개 붙는다. 어떤 게 붙을지도, 얼마나 붙을지도 만들어질 때 한 번 굴리고
 * 그대로 고정된다 — 낄 때마다 달라지면 비교를 할 수 없다.
 *
 * **등급은 이제 여기서만 일한다.** 예전처럼 기본 수치에 배율을 곱하지 않고,
 * 굴릴 수 있는 범위(min~max)를 넓힌다. 그래서 높은 등급은 "무조건 세다"가
 * 아니라 "잘 뽑으면 훨씬 세다"가 된다.
 */
// 옵션 종류와 수치는 `gear.ts` 가 정한다 — 값어치를 하나로 묶고(옵션 하나 = DPS +1%)
// 종류별 최대치를 거기서 역산한 표다. 여기서는 굴리고 저장하는 것만 한다
export { OPTION_KINDS, type OptionKind } from './gear.ts';

export interface ItemOption {
  kind: OptionKind;
  /** 퍼센트 옵션은 퍼센트 포인트, 나머지는 그대로 더할 값 */
  value: number;
}

/**
 * 한 물건에 붙는 옵션 수 — **전 등급 1개 고정** (2026-09-24 지시. 그 전엔 2개).
 * 표는 `gear.ts` 의 `OPTION_COUNT` 이고, 여기 둘은 그 표를 통틀어 본 최소·최대라
 * 창의 안내 문구와 저장값 자르기(`sanitizeOptions`)에 쓴다
 */
export const OPTION_MIN = 1;
export const OPTION_MAX = 1;

/**
 * **여섯 종이 전부 퍼센트다.** 공격력·방어력을 빼면서 수치로 주는 옵션이 없어졌다 —
 * 표시에도 판정에도 100 으로 나눠 쓴다
 */
const PERCENT_OPTIONS = new Set<OptionKind>(OPTION_KINDS);

export function isPercentOption(kind: OptionKind): boolean {
  return PERCENT_OPTIONS.has(kind);
}

export const OPTION_LABEL: Record<OptionKind, string> = {
  crit: '치명타',
  critDamage: '치명타 데미지',
  attackSpeed: '공격 속도',
  maxHp: '체력',
  cooldown: '쿨타임 감소',
  penetration: '방어력 관통',
};

/**
 * **옛 옵션 이름.** 옵션을 여섯 종으로 다시 지으면서(`2deb916`) 공격력·방어력 옵션이
 * 빠졌는데, 그 전에 얻어 저장된 아이템에는 남아 있다. 이름표가 없으면 창에
 * `defense +12` 처럼 **영어 키가 그대로** 찍혔다 (2026-09-23 지적). 판정은 이 옵션을
 * 세지 않는다 — 이름만 한글로 찍는다. 값은 퍼센트가 아니라 고정 수치였다
 */
export const LEGACY_OPTION_LABEL: Record<string, string> = {
  attack: '공격력',
  defense: '방어력',
};

/**
 * 등급이 옵션 수치에 주는 배율 — `gear.ts` 의 `optionScale` 이다.
 * 1등급이 최대의 25%, 10등급이 100%.
 */
export function optionGradeScale(grade: number): number {
  return gearOptionScale(Math.min(GRADE_MAX, Math.max(GRADE_MIN, Math.round(grade))));
}

/**
 * 이 등급에서 이 옵션이 나올 수 있는 범위 — `gear.ts` 의 표다.
 *
 * 창에 그대로 보여준다 — "몇 등급이면 얼마까지 뜨나"를 알 수 없으면
 * 등급을 올릴 이유를 설명할 수 없다.
 *
 * **레벨은 안 본다.** 여섯 종이 전부 퍼센트라 어디서나 같은 뜻이라야 한다.
 * 인자는 부르는 쪽을 다 고치지 않으려고 남겨 두고 무시한다
 */
export function optionRange(
  kind: OptionKind,
  grade: number,
  _level?: number
): { min: number; max: number } {
  return gearOptionRange(kind, Math.min(GRADE_MAX, Math.max(GRADE_MIN, Math.round(grade))));
}

/** 옵션 한 줄을 사람이 읽는 글로 */
export function describeOption(option: ItemOption): string {
  const suffix = isPercentOption(option.kind) ? '%' : '';
  return `${OPTION_LABEL[option.kind]} +${option.value}${suffix}`;
}

/**
 * 옵션을 굴린다.
 *
 * 종류는 겹치지 않게 고른다 — 치명타가 셋 붙으면 그건 옵션이 하나 붙은 것과
 * 다르지 않으면서 설명만 길어진다.
 *
 * rng 를 받는 이유는 테스트에서 결과를 고정하기 위해서다.
 */
export function rollOptions(
  item: ItemDef,
  grade: number,
  rng: () => number = Math.random
): ItemOption[] {
  // **개수는 품질 등급이 정한다** — 등급이 오르면 개수와 수치가 같이 커진다
  const [lo, hi] = gearOptionCount(Math.min(GRADE_MAX, Math.max(GRADE_MIN, Math.round(grade))));
  const count = lo + Math.floor(rng() * (hi - lo + 1));
  const pool = [...OPTION_KINDS];

  const out: ItemOption[] = [];
  for (let i = 0; i < Math.min(count, pool.length); i++) {
    const kind = pool.splice(Math.floor(rng() * pool.length), 1)[0]!;
    const { min, max } = optionRange(kind, grade);
    // 소수 한 자리로 저장한다 — 정수로 자르면 낮은 등급에서 0 이 되어 버린다
    out.push({ kind, value: Math.round((min + rng() * (max - min)) * 10) / 10 });
  }
  return out;
}

// ---------------------------------------------------------------- 옵션 차수

/**
 * **옵션을 1차·2차·3차로 나눈다** (2026-09-23 지시: "1차만 드랍으로 나오게 하고
 * 2차는 크리스탈이라는 아이템 만들어서 해당 아이템으로 붙이는 시스템. 3차는 비어둬").
 *
 * - 1차 — 드랍·상점에서 물건이 생길 때 굴린다 (지금까지의 `options`, 1줄)
 * - 2차 — 크리스탈을 쓰면 **2차 칸을 통째로 다시 굴린다** (1줄). 처음 쓰면 붙고,
 *   다시 쓰면 바뀐다
 * - 3차 — 자리만 있다 (`count: 0`, 붙이는 곳 없음)
 *
 * 차수마다 저장 칸을 따로 둔다(`options` · `options2` · `options3`). 1차가 옛 `options`
 * 그대로라 **옛 저장은 손대지 않아도 1차로 읽힌다.** 수치 범위는 셋 다 장비 등급의
 * `optionRange` 다 — 차수는 "어디서 붙나" 만 가른다.
 *
 * 종류는 **같은 차수 안에서만** 안 겹친다. 2차가 1차와 같은 종류여도 된다 — 막으면
 * 크리스탈 결과가 1차에 따라 달라져 "무엇이 나올 수 있나" 를 설명하기 어렵다.
 */
export type OptionTierKey = 'options' | 'options2' | 'options3';

export interface OptionTier {
  tier: number;
  key: OptionTierKey;
  /** 붙는 줄 수. 0 이면 빈 차수 */
  count: number;
  /** 어디서 붙나 — `drop`(드랍·상점) · `crystal` · 없음 */
  source: 'drop' | 'crystal' | null;
}

export const OPTION_TIERS: OptionTier[] = [
  { tier: 1, key: 'options', count: OPTION_MAX, source: 'drop' },
  { tier: 2, key: 'options2', count: 1, source: 'crystal' },
  { tier: 3, key: 'options3', count: 0, source: null },
];

export function optionTier(tier: number): OptionTier | undefined {
  return OPTION_TIERS.find((t) => t.tier === tier);
}

/** 그 차수의 옵션을 굴린다 — 수치는 장비 등급, 줄 수는 차수 표가 정한다 */
export function rollTierOptions(
  tier: number,
  grade: number,
  rng: () => number = Math.random
): ItemOption[] {
  const count = optionTier(tier)?.count ?? 0;
  const pool = [...OPTION_KINDS];
  const out: ItemOption[] = [];
  for (let i = 0; i < Math.min(count, pool.length); i++) {
    const kind = pool.splice(Math.floor(rng() * pool.length), 1)[0]!;
    const { min, max } = optionRange(kind, grade);
    out.push({ kind, value: Math.round((min + rng() * (max - min)) * 10) / 10 });
  }
  return out;
}

// ---------------------------------------------------------------- 재료 (크리스탈)

/**
 * **재료** — 장비가 아닌 가방 물건. 지금은 크리스탈 하나다.
 *
 * `ITEMS`(장비 42종) 에 넣지 않는다 — 넣으면 슬롯·등급·능력치를 묻는 자리마다
 * "장비가 아니면" 을 걸어야 한다. 가방에는 `{ id, count }` 로 겹쳐 쌓인다.
 *
 * 크리스탈은 **한 종류**다 (2026-09-23 사용자 선택). 붙는 수치는 크리스탈이 아니라
 * **장비 등급**이 정한다.
 */
export interface MaterialDef {
  id: string;
  name: string;
  /** 상세 창에 적는 한 줄 */
  desc: string;
  /** 스킬 경험치북이면 넣는 경험치 (`SKILL_EXP_BOOKS`). 스킬창에서 쓴다 */
  skillExp?: number;
}

export const CRYSTAL_ID = 'crystal';

export const MATERIALS: Record<string, MaterialDef> = {
  [CRYSTAL_ID]: {
    id: CRYSTAL_ID,
    name: '크리스탈',
    desc: '장비의 2차 옵션을 다시 굴린다',
  },
  // 스킬 경험치북 — 경험치북 표에서 만든다. 모든 스킬 강화에 공용 (2026-09-23)
  ...Object.fromEntries(
    SKILL_EXP_BOOKS.map((book) => [
      book.id,
      { id: book.id, name: book.name, desc: `스킬 강화 경험치 +${book.exp}`, skillExp: book.exp },
    ])
  ),
};

export function getMaterial(id: string): MaterialDef | null {
  return MATERIALS[id] ?? null;
}

/**
 * 몬스터 한 마리가 크리스탈을 떨굴 확률 — **0.01%** (1만 마리에 하나, 2026-09-23 지시:
 * "크리스탈 드랍률은 일단 0.01%로 설정해"). 처음엔 1% 였다. 장비와 **따로** 굴린다.
 * 설계([stat-balance.md](../../../docs/features/stat-balance.md))에는 아직 없는 값이라
 * 손볼 자리는 여기 한 곳이다. **비율이다** — `GEAR_DROP_RATE` 처럼 퍼센트 단위가 아니다
 */
export const CRYSTAL_DROP_CHANCE = 0.0001;

/** 저장된 값이 지금 규칙에 맞는지 — 서버가 불러올 때 반드시 거친다 */
export function sanitizeOptions(
  raw: unknown,
  item: ItemDef,
  grade: number,
  limit: number = OPTION_MAX
): ItemOption[] {
  if (!Array.isArray(raw)) return [];

  const seen = new Set<OptionKind>();
  const out: ItemOption[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== 'object') continue;
    const kind = (entry as ItemOption).kind;
    const value = (entry as ItemOption).value;
    if (!OPTION_KINDS.includes(kind) || seen.has(kind)) continue;
    if (typeof value !== 'number' || !Number.isFinite(value)) continue;

    const { min, max } = optionRange(kind, grade);
    seen.add(kind);
    const clamped = Math.min(max, Math.max(min, value));
    out.push({ kind, value: Math.round(clamped * 10) / 10 });
    if (out.length >= limit) break;
  }
  return out;
}

// ---------------------------------------------------------------- 강화

/**
 * 강화.
 *
 * 등급과는 다른 축이다. 등급은 보스 재료로 확실하게 올리고, 강화는
 * **골드를 걸고 운을 본다.** 실패해도 유지되는 구간이 있고, 높은 수치에서는
 * 아예 부서진다 — 그래서 어디서 멈출지가 선택이 된다.
 */
/**
 * 강화 상한. 설계는 **10단계**이고 1단이 무강이므로, `+0 ~ +9` 로 아홉 번 두드린다
 * (2026-09-20 에 10 → 9 로 줄였다 — 그 전에는 +10 까지 열한 칸이었다).
 */
export const MAX_ENHANCE = GEAR_ENH_MAX - 1;

/**
 * 강화 배율 — **설계표를 그대로 쓴다** (`gear.ts`). `+0` 이 1단, `+9` 가 10단이다.
 *
 * 총 배수가 ×6 이고 증가율이 고강화일수록 크다(첫 구간 : 마지막 = 1 : 7).
 * 그 전에는 `1 + n×0.08` 이라 +10 이 ×1.8 이었다 — 9→10단이 +50% 여야 **파괴 위험을
 * 감수할 이유**가 생긴다는 것이 설계의 결론이다.
 */
export function enhanceMultiplier(level: number): number {
  const n = Math.min(MAX_ENHANCE, Math.max(0, Math.round(level || 0)));
  return gearEnhanceMultiplier(n + 1);
}

export interface EnhanceOdds {
  success: number;
  keep: number;
  destroy: number;
}

/**
 * +level 에서 한 번 더 두드릴 때의 확률 — **설계표 그대로**(90/80/…/10%).
 *
 * **"유지" 가 없다. 실패하면 무조건 파괴된다.** 재료도 값도 없으니(아래 `enhanceCost`)
 * 실패의 대가는 아이템 하나뿐이고, 무한히 재시도할 수 있다. 그래서 도달 단계는
 * **아이템이 몇 개 들어오느냐**로만 결정되고, 드랍률이 경험치와 같은 급의 손잡이가 된다.
 *
 * 그 전에는 유지 구간이 있어 +6 까지는 절대 안 부서졌다.
 */
export function enhanceOdds(level: number): EnhanceOdds {
  const n = Math.max(0, Math.round(level || 0));
  const success = GEAR_ENH_ODDS[Math.min(n, GEAR_ENH_ODDS.length - 1)]!;
  return { success, keep: 0, destroy: 1 - success };
}

/**
 * 한 번 두드리는 값 — **공짜다.** 설계에 강화 재료도 비용도 없다.
 *
 * 값을 매기면 강화가 "골드를 모으는 일" 이 되는데, 설계는 그 자리에 **드랍**을
 * 놓았다 — 실패하면 아이템이 사라지므로 아이템 자체가 연료다.
 */
export function enhanceCost(_item: ItemDef, _level: number): number {
  return 0;
}

export function canEnhance(level: number): boolean {
  return (level || 0) < MAX_ENHANCE;
}

export type EnhanceResult = 'success' | 'keep' | 'destroy';

/** 굴림값(0~1)에서 결과 하나 */
export function rollEnhance(level: number, roll: number): EnhanceResult {
  const odds = enhanceOdds(level);
  const r = Math.max(0, Math.min(0.999999, roll));
  if (r < odds.success) return 'success';
  if (r < odds.success + odds.keep) return 'keep';
  return 'destroy';
}

/**
 * 아이템에 고정으로 박힌 기본 능력치.
 *
 * **등급을 타지 않는다.** 같은 이름이면 기본 수치는 언제나 같고, 물건마다
 * 달라지는 부분은 전부 옵션이 맡는다. 강화만 이 위에 곱한다 — 강화는
 * "이 물건 자체를 두드려 키우는" 축이라 기본 수치에 붙는 게 맞다.
 */
export function baseBonus(item: ItemDef, enhance = 0): Required<ItemBonus> {
  const m = enhanceMultiplier(enhance);
  // **소수 한 자리를 남긴다.** 이 값들은 이제 절대 수치가 아니라 **%** 라서
  // 정수로 자르면 낮은 단계에서 오차가 커진다 (등급1 갑옷 방어 8.4% → 8%)
  const pct = (v: number) => Math.round(v * m * 10) / 10;
  return {
    attack: pct(item.bonus.attack ?? 0),
    defense: pct(item.bonus.defense ?? 0),
    maxHp: pct(item.bonus.maxHp ?? 0),
    // **강화는 공격·방어·HP 에만 곱한다.** 치확·공속까지 곱하면 목걸이·반지 두 자리가
    // 강화 한 번에 다른 슬롯 넷을 합친 값을 넘어선다 (설계 문서와 시뮬레이터가 같다)
    crit: item.bonus.crit ?? 0,
    attackSpeed: item.bonus.attackSpeed ?? 0,
  };
}

/**
 * 장비가 주는 능력치 전부 — 기본 + 옵션.
 *
 * 퍼센트 옵션은 여기서 이미 비율(0.07 = 7%)로 바꿔 담는다. 화면과 판정이
 * 서로 다른 단위를 쓰면 언젠가 100 을 한 번 더 곱하거나 빼먹는다.
 */
export interface ItemStats {
  attack: number;
  defense: number;
  maxHp: number;
  /** 치명타 확률 가산 (0.07 = +7%p) */
  crit: number;
  /** 치명타 데미지 가산 (0.2 = +20%) */
  critDamage: number;
  /** 공격 속도 가산 (0.2 = +20%) */
  attackSpeed: number;
  /** 스킬 쿨타임 감소 (0.05 = 5% 짧아짐). **옵션으로만 붙는다** */
  cooldown: number;
  /** 방어력 관통 (0.1 = 상대 방어력 10% 무시). **옵션으로만 붙는다** */
  penetration: number;
}

export function emptyStats(): ItemStats {
  return {
    attack: 0,
    defense: 0,
    maxHp: 0,
    crit: 0,
    critDamage: 0,
    attackSpeed: 0,
    cooldown: 0,
    penetration: 0,
  };
}

/** 물건 하나가 주는 것 전부 */
export function stackStats(stack: ItemStack): ItemStats {
  const total = emptyStats();
  const item = getItem(stack.id);
  if (!item) return total;

  const base = baseBonus(item, stack.enhance);
  total.attack = base.attack;
  total.defense = base.defense;
  total.maxHp = base.maxHp;
  total.crit = base.crit / 100;
  total.attackSpeed = base.attackSpeed / 100;

  // 옵션 여섯 종은 전부 퍼센트다. HP 만 **기본 스탯에 곱할 %** 라 같은 자리에 더하고,
  // 나머지 넷은 비율(0.07 = 7%)로 바꿔 담는다. **1·2·3차를 다 더한다**
  const options = OPTION_TIERS.flatMap((t) => stack[t.key] ?? []);
  for (const option of options) {
    switch (option.kind) {
      case 'maxHp': total.maxHp += option.value; break;
      case 'crit': total.crit += option.value / 100; break;
      case 'critDamage': total.critDamage += option.value / 100; break;
      case 'attackSpeed': total.attackSpeed += option.value / 100; break;
      case 'cooldown': total.cooldown += option.value / 100; break;
      case 'penetration': total.penetration += option.value / 100; break;
    }
  }
  return total;
}

/** 장착 중인 것들이 더해주는 능력치 합 */
export function equipmentStats(
  equipped: Partial<Record<EquipSlot, ItemStack | null>>
): ItemStats {
  const total = emptyStats();
  for (const slot of EQUIP_SLOTS) {
    const stack = equipped[slot];
    if (!stack || !getItem(stack.id)) continue;
    const one = stackStats(stack);
    total.attack += one.attack;
    total.defense += one.defense;
    total.maxHp += one.maxHp;
    total.crit += one.crit;
    total.critDamage += one.critDamage;
    total.attackSpeed += one.attackSpeed;
  }
  return total;
}

// ---------------------------------------------------------------- 제작

/**
 * **제작은 없앴다** (2026-09-20 요청: "제작은 일단 제거해").
 *
 * 등급 올리기·새로 만들기·재료(`m_XX`)가 전부 여기 있었다. 설계
 * ([stat-balance.md](../../../docs/features/stat-balance.md))에는 강화만 있고
 * 제작이 없으므로, 두 체계를 나란히 두면 "상위 등급으로 가는 길" 이 둘이 된다.
 *
 * 걷어내면서 따라온 것: **드롭이 유일한 길**이 되어 `MAX_DROP_GRADE` 가 7 → 10 이
 * 됐고, 보스가 떨구던 재료가 사라졌다(보스 전용 아이템은 나중에 정한다).
 * 되살리려면 이 커밋을 뒤집는 게 빠르다.
 */

// ---------------------------------------------------------------- 드롭

/**
 * 그 몬스터가 장비를 떨굴 확률 — **설계값이다.** ★★
 *
 * 2026-09-21 까지는 `DROP_CHANCE = 0.14` 평면값이었다. 그 숫자는 설계 문서보다
 * **먼저** 있던 것(고도 이관 2단계)이고, 설계의 `GEAR_DROP_RATE` 는 `balance.json`
 * 으로 내보내지기만 할 뿐 **판정에서 아무도 안 읽고 있었다** — 설계 9장의 "코드에
 * 넣을 때 순서" 여섯 단계에 드랍률이 없어서 그 사이로 빠졌다.
 *
 * 창에 든 등급들의 확률을 **더한 값**이다. 각 등급은 자기 `GEAR_DROP_RATE` 로
 * 떨어진다 — 아래 등급이 자기 기준 사냥터를 지나서도 계속 나오는 것은 의도다.
 * 강화 여벌이 필요하기 때문이다(실패하면 파괴).
 *
 * `GEAR_DROP_RATE` 는 **퍼센트 단위**라 100 으로 나눈다. 0.2963 = 0.2963% 다.
 */
export function dropChanceFor(monsterLevel: number): number {
  return dropGradesFor(monsterLevel).reduce((sum, g) => sum + gearDropRate(g), 0);
}

/** 등급 하나의 킬당 확률(0~1). 표는 퍼센트라 100 으로 나눈다 */
function gearDropRate(grade: number): number {
  return (GEAR_DROP_RATE[Math.min(GEAR_DROP_RATE.length, Math.max(1, grade)) - 1] ?? 0) / 100;
}

/**
 * 그 몬스터가 떨굴 수 있는 등급들 — **사냥터가 정한다.** ★
 *
 * 2026-09-21 요청: "사냥터에 따라 나오는 등급 아이템 확률을 다르게 할거야.
 * 지금 상태면 1레벨짜리 잡고 최종템을 먹을수도 있는거자나."
 *
 * 설계에 이미 답이 있었고 판정이 안 보고 있었다 — `dropField(g)` 가 "등급 g 는
 * 어느 사냥터에서 뚫나" 를 정해 둔다(2·5·8·11·14·17·20). **착용 레벨보다 한
 * 구간 위**라, 착용 레벨이 돼도 바로는 못 얻고 한 사냥터 더 올라가 이전
 * 등급으로 뚫어야 한다. 그게 상향 압력의 정체다.
 */
export function dropGradesFor(monsterLevel: number): number[] {
  return gearDropGrades(fieldOf(monsterLevel));
}

/**
 * 굴림값(0~1)에서 드롭 등급 하나 — **그 몬스터가 선 사냥터 안에서만.**
 *
 * 비율은 **설계의 등급별 드랍률 그대로**다 (`GEAR_DROP_RATE`). 예전에는
 * `2^(n-g)` 로 임의로 반씩 깎았는데, 설계가 등급마다 절대 확률을 정해 두었으므로
 * 그 비로 나누면 두 값이 어긋날 일이 없다. 창이 [1, 2] 면 0.2963 : 0.08 이다.
 */
export function rollGrade(roll: number, monsterLevel: number): number {
  const grades = dropGradesFor(monsterLevel);
  const weights = grades.map((g) => gearDropRate(g));
  const total = weights.reduce((a, b) => a + b, 0);
  let cursor = Math.max(0, Math.min(0.999999, roll)) * total;
  for (let i = 0; i < weights.length; i++) {
    cursor -= weights[i]!;
    if (cursor < 0) return grades[i]!;
  }
  return grades[grades.length - 1]!;
}

export interface Drop {
  gold: number;
  /** 없으면 골드만 나온 것 */
  item?: ItemStack;
  /** 크리스탈 개수. 없으면 안 나온 것 (`CRYSTAL_DROP_CHANCE`, 장비와 따로 굴린다) */
  crystal?: number;
}

/**
 * 처치 보상을 굴린다.
 *
 * **떨어지는 장비는 잡은 사람이 쓸 수 있는 것만 고른다.** 못 쓰는 무기가
 * 가방을 채우면 정리하는 게 일이 되고, 거래나 상점이 없는 지금은 그냥 쓰레기다.
 *
 * rng 를 받는 이유는 테스트에서 결과를 고정하기 위해서다.
 */
export function rollDrop(monsterLevel: number, job: JobId, rng: () => number = Math.random): Drop {
  const base = 2 + monsterLevel * 1.5;
  // ±30% 흔들어 매번 같은 숫자가 나오지 않게 한다
  const gold = Math.max(1, Math.round(base * (0.7 + rng() * 0.6)));

  // 크리스탈은 장비와 **따로** 굴린다. 순서는 골드 → 장비 → (슬롯 → 등급 → 옵션) → 크리스탈
  // — 고도 `items.gd` 도 같은 순서라야 같은 씨앗에서 같은 것이 나온다
  const drop: Drop = { gold };
  if (rng() < dropChanceFor(monsterLevel)) drop.item = rollGearDrop(monsterLevel, rng);
  if (rng() < CRYSTAL_DROP_CHANCE) drop.crystal = 1;
  return drop;
}

function rollGearDrop(monsterLevel: number, rng: () => number): ItemStack {
  // 슬롯은 고루 나와야 한다 — 한쪽만 나오면 나머지 자리는 영영 빈다.
  // 직업은 더 이상 후보를 가르지 않는다. 등급은 사냥터가 정한다
  // (굴리는 순서는 슬롯 → 등급. 고도 `items.gd` 도 같은 순서라야 같은 씨앗에서 같은 것이 나온다)
  const pick = Math.min(EQUIP_SLOTS.length - 1, Math.floor(rng() * EQUIP_SLOTS.length));
  const grade = rollGrade(rng(), monsterLevel);
  const id = itemId(grade, EQUIP_SLOTS[pick]!);

  const def = getItem(id);
  return { id, grade, options: def ? rollOptions(def, grade, rng) : [] };
}

export interface BossDrop {
  gold: number;
}

/**
 * 보스 보상 — **지금은 금화뿐이다.**
 *
 * 2026-09-20 에 제작을 걷으면서 보스 재료도 같이 없앴다. 보스는 **보스 전용
 * 아이템**을 떨굴 예정이고 그건 나중에 설계한다. 그때까지 잡은 값은 금화로만
 * 돌려준다 — 일반 처치의 12배다.
 */
export function rollBossDrop(monsterLevel: number, rng: () => number = Math.random): BossDrop {
  const base = (2 + monsterLevel * 1.5) * 12;
  return { gold: Math.max(1, Math.round(base * (0.8 + rng() * 0.4))) };
}
