import type { JobId } from './character.ts';

/**
 * 아이템과 드롭.
 *
 * 몬스터와 같은 방식으로 **표에서 만든다.** 사냥터 20곳에 맞춰 20단계가 있고,
 * 단계마다 슬롯 8종을 채운다. 직업을 타는 무기·보조는 3벌씩이라 단계당 13개,
 * 전부 260개다. 손으로 적으면 반드시 어긋나므로 이름은 접두어 표에서,
 * 수치는 요구 레벨에서 뽑는다.
 *
 * 수치는 아직 정밀하게 맞추지 않았다 — 곡선을 먼저 잡고 장비를 얹으면 두 번
 * 조정해야 해서, 지금은 "레벨에 비례해 눈에 띄게 오르는" 정도로만 두었다.
 */

// 슬롯 정의는 `slots.ts` 로 옮겼다 — 여기서 `gear.ts` 를 임포트하게 되면서
// 서로를 부르는 순환이 되기 때문이다. 그대로 다시 내보내니 부르는 쪽은 그대로다
export { EQUIP_SLOTS, SLOT_CODE, slotLabel, type EquipSlot } from './slots.ts';
import { EQUIP_SLOTS, SLOT_CODE, slotLabel, type EquipSlot } from './slots.ts';
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
  GRADE_LV_SPAN as GEAR_GRADE_LV_SPAN,
  enhanceMultiplier as gearEnhanceMultiplier,
  slotStats,
  dropGrades as gearDropGrades,
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
  /** 착용 가능한 최소 레벨 */
  level: number;
  /** 무기와 보조는 직업을 탄다. 없으면 아무나 낀다 */
  job?: JobId;
  bonus: ItemBonus;
  /** 상점에 팔 때 받는 금액 */
  price: number;
}

/** 가방 칸 수 */
export const INVENTORY_SIZE = 200;

/** 단계별 접두어 — 사냥터 순서와 같다 */
const TIER_PREFIX = [
  '낡은', '단단한', '강철', '은빛', '늪지',
  '서리', '흑단', '고대', '사막', '백금',
  '유황', '용암', '빙하', '뒤틀린', '그림자',
  '폐허', '창백한', '균열', '심연', '종말',
];

/**
 * 단계별 색.
 *
 * 갑옷·신발은 모델에 갈아입힐 메시가 없다. 그래서 **몸통과 다리 색을 바꾼다** —
 * 20단계를 지나며 색이 변하면 "다른 걸 입었다"로는 읽힌다. 사냥터 분위기와
 * 같은 순서라 어디서 얻은 장비인지도 짐작이 간다.
 */
export const TIER_COLOR = [
  '#8a7a5e', '#7f8a92', '#9aa3ad', '#c3cbd6', '#6f8a5a',
  '#9fc4de', '#4a4a52', '#c9a94a', '#d0a86a', '#dfe3e8',
  '#c2a63a', '#c46a3a', '#7fb8d8', '#6b5a86', '#5a4f7a',
  '#8a8479', '#cfc9bb', '#b054b0', '#3f6e8c', '#a83a44',
];

/** 직업별 무기 이름 */
const WEAPON_NAME: Record<JobId, string> = {
  fighter: '너클',
  mage: '지팡이',
  archer: '활',
};

/** 단계 번호(0부터)에서 요구 레벨 — 사냥터 레벨대의 시작점과 같다 */
export function tierLevel(index: number): number {
  return index === 0 ? 1 : index * 10;
}

/** 단계 개수 */
export const TIER_COUNT = TIER_PREFIX.length;

/**
 * 단계 이름(접두어). 제작창에서 단계를 골라 거르려면 이름이 있어야 한다 —
 * "8단계" 로만 적으면 어느 사냥터 물건인지 알 수 없다.
 */
export function tierName(index: number): string {
  return TIER_PREFIX[Math.max(0, Math.min(TIER_PREFIX.length - 1, index))]!;
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
 * 요구 레벨을 설계의 **연속 등급**으로 옮긴다.
 *
 * 설계는 등급 7개(착용 Lv 1/31/61/91/121/151/181)를 쓰는데, 이 표는 단계 20개라
 * 축이 다르다. 30레벨마다 등급 하나가 오르도록 **보간**하면 양 끝이 설계와 정확히
 * 맞고(Lv1 = 등급1 = 35%, Lv181+ = 등급7 = 856%) 단계마다 값도 다르게 나온다.
 * 계단으로 끊으면 한 등급 안의 단계 셋이 전부 같은 값이 되어 갈아입을 이유가 없어진다.
 */
function gearGrade(level: number): number {
  return Math.max(1, Math.min(GEAR_GRADE_COUNT, 1 + (level - 1) / GEAR_GRADE_LV_SPAN));
}

function bonusFor(slot: EquipSlot, level: number, _job?: JobId): ItemBonus {
  const s = slotStats(slot, gearGrade(level));
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

/** 직업을 타는 슬롯. 보조를 없애 무기 하나만 남았다 */
export const JOB_SLOTS: EquipSlot[] = ['weapon'];

function buildItems(): Record<string, ItemDef> {
  const out: Record<string, ItemDef> = {};
  const jobs = Object.keys(WEAPON_NAME) as JobId[];

  TIER_PREFIX.forEach((prefix, index) => {
    const level = tierLevel(index);
    const price = Math.round(20 + level * 12);
    const tag = String(index).padStart(2, '0');

    for (const slot of EQUIP_SLOTS) {
      const code = SLOT_CODE[slot];

      if (JOB_SLOTS.includes(slot)) {
        for (const job of jobs) {
          const id = `${code}_${job}_${tag}`;
          const base = WEAPON_NAME[job];
          out[id] = {
            id,
            name: `${prefix} ${base}`,
            slot,
            level,
            job,
            bonus: bonusFor(slot, level, job),
            price,
          };
        }
        continue;
      }

      const id = `${code}_${tag}`;
      out[id] = {
        id,
        name: `${prefix} ${slotLabel(slot)}`,
        slot,
        level,
        bonus: bonusFor(slot, level),
        price,
      };
    }

    // 제작 재료(`m_XX`)는 2026-09-20 에 없앴다 — 제작 자체를 걷었기 때문이다
  });

  return out;
}

export const ITEMS: Record<string, ItemDef> = buildItems();

export function getItem(id: string): ItemDef | null {
  return ITEMS[id] ?? null;
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
 * 등급.
 *
 * 단계(요구 레벨)와는 다른 축이다. 같은 "낡은 활"이라도 등급이 다르면 성능이
 * 다르다. 단계는 어느 사냥터에서 나오는지를, 등급은 그 중 얼마나 좋은 물건인지를
 * 정한다.
 *
 * **7등급까지만 떨어지고 8~10 은 제작으로만 나온다.** 그래야 최상위 장비가
 * 운이 아니라 쌓아온 결과가 된다.
 */
export const GRADE_MIN = 1;
export const GRADE_MAX = 10;
/**
 * 드롭으로 나올 수 있는 최고 등급 — **7등급.**
 *
 * 2026-09-20 에 제작을 걷으면서 "드롭이 유일한 길" 이라는 이유로 7 → 10 으로
 * 올렸다가, **2026-09-21 에 다시 7로 내렸다.** 사냥터별 상한(`dropGrades`)을
 * 걸면서 그 이유가 사라졌기 때문이다 — 어차피 사냥터 20 이 끝이고, 8~10 은
 * 설계([stat-balance.md](../../../docs/features/stat-balance.md) 3장)에 **근거가
 * 없는 숫자**였다. 설계 등급은 7개이고, 카탈로그를 56종으로 갈 때 두 축이
 * 7에서 하나로 합쳐진다.
 */
export const MAX_DROP_GRADE = GEAR_GRADE_COUNT;

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
   * 만들어질 때 굴린 옵션 1~3개.
   *
   * **물건마다 다르다.** 같은 이름·등급이라도 이게 다르면 다른 물건이라
   * 가방에서도 한 칸에 겹치지 않는다.
   */
  options?: ItemOption[];
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
 * 한 물건에 붙을 수 있는 옵션 수 — **품질 등급이 정한다**(`gear.ts` 의 `OPTION_COUNT`).
 * 아래 둘은 전 등급을 통틀어 본 최소·최대라 창의 안내 문구에만 쓴다
 */
export const OPTION_MIN = 1;
export const OPTION_MAX = 4;

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

/** 저장된 값이 지금 규칙에 맞는지 — 서버가 불러올 때 반드시 거친다 */
export function sanitizeOptions(raw: unknown, item: ItemDef, grade: number): ItemOption[] {
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
    if (out.length >= OPTION_MAX) break;
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
  // 나머지 넷은 비율(0.07 = 7%)로 바꿔 담는다
  for (const option of stack.options ?? []) {
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

/** 몬스터 레벨에 맞는 단계 번호 */
export function tierForLevel(monsterLevel: number): number {
  const index = Math.floor(monsterLevel / 10);
  return Math.min(TIER_PREFIX.length - 1, Math.max(0, index));
}

/** 아이템이 떨어질 확률 */
export const DROP_CHANCE = 0.14;

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
 * 후보는 둘(사냥터 1 은 하나)이고 **아래 등급이 두 배 흔하다.** 한 등급 오를
 * 때마다 절반이라는 예전 가중치를, 이제 전 구간이 아니라 창 안에서만 쓴다.
 */
export function rollGrade(roll: number, monsterLevel: number): number {
  const grades = dropGradesFor(monsterLevel);
  const weights = grades.map((_, i) => 2 ** (grades.length - 1 - i));
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

  if (rng() >= DROP_CHANCE) return { gold };

  const tier = tierForLevel(monsterLevel);
  const tag = String(tier).padStart(2, '0');

  // 슬롯 8종이 고루 나와야 한다. 한쪽만 나오면 나머지 자리는 영영 빈다.
  const candidates = EQUIP_SLOTS.map((slot) =>
    JOB_SLOTS.includes(slot) ? `${SLOT_CODE[slot]}_${job}_${tag}` : `${SLOT_CODE[slot]}_${tag}`
  );
  const id = candidates[Math.min(candidates.length - 1, Math.floor(rng() * candidates.length))]!;

  const grade = rollGrade(rng(), monsterLevel);
  const def = getItem(id);
  return { gold, item: { id, grade, options: def ? rollOptions(def, grade, rng) : [] } };
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
