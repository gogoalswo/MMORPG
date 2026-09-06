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

export type EquipSlot =
  | 'weapon'
  | 'offhand'
  | 'armor'
  | 'helmet'
  | 'boots'
  | 'ring'
  | 'necklace'
  | 'earring';

/** 창에 놓이는 순서 */
export const EQUIP_SLOTS: EquipSlot[] = [
  'weapon',
  'offhand',
  'helmet',
  'armor',
  'boots',
  'ring',
  'necklace',
  'earring',
];

/**
 * 보조 슬롯은 직업마다 다른 물건이 들어간다.
 * 기사는 방패로 버티고, 궁수는 화살통, 마법사는 마법서를 든다.
 */
export const OFFHAND_NAME: Record<JobId, string> = {
  knight: '방패',
  mage: '마법서',
  archer: '화살통',
};

const FIXED_SLOT_LABEL: Record<Exclude<EquipSlot, 'offhand'>, string> = {
  weapon: '무기',
  armor: '갑옷',
  helmet: '투구',
  boots: '신발',
  ring: '반지',
  necklace: '목걸이',
  earring: '귀걸이',
};

/** 슬롯 이름. 보조는 직업을 알아야 제대로 부를 수 있다 */
export function slotLabel(slot: EquipSlot, job?: JobId): string {
  if (slot !== 'offhand') return FIXED_SLOT_LABEL[slot];
  return job ? OFFHAND_NAME[job] : '보조';
}

/** 장비가 더해주는 능력치 */
export interface ItemBonus {
  attack?: number;
  defense?: number;
  maxHp?: number;
}

export interface ItemDef {
  id: string;
  name: string;
  /** 재료는 착용할 수 없으므로 슬롯이 없다 */
  slot: EquipSlot | null;
  /** 착용 가능한 최소 레벨 */
  level: number;
  /** 무기와 보조는 직업을 탄다. 없으면 아무나 낀다 */
  job?: JobId;
  bonus: ItemBonus;
  /** 상점에 팔 때 받는 금액 */
  price: number;
  /** 제작 재료인지 — 보스만 떨군다 */
  material?: boolean;
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
  knight: '장검',
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
 * 슬롯마다 성격이 다르다.
 *
 * 무기는 공격, 갑옷 계열은 체력·방어, 장신구는 공격 위주다. 보조는 직업이
 * 갈리는 자리라 기사는 버티고, 마법사와 궁수는 공격을 얻는다.
 * 같은 단계 안에서 갑옷 > 투구 > 신발 순으로 무게를 준다.
 *
 * 장신구가 원래 마나를 주던 자리였다. 마나를 걷어내면서 그 몫을 공격과
 * 체력으로 옮겼다 — 안 그러면 반지·목걸이·귀걸이 세 자리가 빈 물건이 된다.
 */
function bonusFor(slot: EquipSlot, level: number, job?: JobId): ItemBonus {
  const hp = (k: number) => Math.round((10 + level * 4) * k);
  const def = (k: number) => Math.round((1 + level * 0.4) * k);
  const atk = (k: number) => Math.round((2 + level * 0.6) * k);

  switch (slot) {
    case 'weapon':
      return { attack: atk(1) };
    case 'offhand':
      if (job === 'knight') return { defense: def(0.9), maxHp: hp(0.5) };
      if (job === 'mage') return { attack: atk(0.55), maxHp: hp(0.2) }; // 마법서
      return { attack: atk(0.5), defense: def(0.3) }; // 궁수 화살통
    case 'armor':
      return { maxHp: hp(1), defense: def(1) };
    case 'helmet':
      return { maxHp: hp(0.6), defense: def(0.6) };
    case 'boots':
      return { maxHp: hp(0.4), defense: def(0.45) };
    case 'ring':
      return { attack: atk(0.45), maxHp: hp(0.15) };
    case 'necklace':
      return { attack: atk(0.5), maxHp: hp(0.2) };
    case 'earring':
      return { defense: def(0.6), maxHp: hp(0.25) };
  }
}

/** 슬롯별 id 앞글자 */
const SLOT_CODE: Record<EquipSlot, string> = {
  weapon: 'w',
  offhand: 'o',
  armor: 'a',
  helmet: 'h',
  boots: 'b',
  ring: 'r',
  necklace: 'n',
  earring: 'e',
};

/** 직업을 타는 슬롯 */
const JOB_SLOTS: EquipSlot[] = ['weapon', 'offhand'];

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
          const base = slot === 'weapon' ? WEAPON_NAME[job] : OFFHAND_NAME[job];
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

    // 그 사냥터 보스가 떨구는 제작 재료
    const materialId = materialIdFor(index);
    out[materialId] = {
      id: materialId,
      name: `${prefix} 정수`,
      slot: null,
      level,
      bonus: {},
      price: Math.round(price * 0.4),
      material: true,
    };
  });

  return out;
}

export const ITEMS: Record<string, ItemDef> = buildItems();

export function getItem(id: string): ItemDef | null {
  return ITEMS[id] ?? null;
}

/** 단계 번호에서 재료 id */
export function materialIdFor(tier: number): string {
  return 'm_' + String(tier).padStart(2, '0');
}

/** 이 캐릭터가 낄 수 있는 장비인지 — 서버가 반드시 다시 확인해야 한다 */
export function canEquip(item: ItemDef, job: JobId, level: number): boolean {
  if (!item.slot) return false; // 재료는 못 낀다
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
export const MAX_DROP_GRADE = 7;

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
export type OptionKind =
  | 'crit'
  | 'attackSpeed'
  | 'critDamage'
  | 'maxHp'
  | 'attack'
  | 'defense';

export const OPTION_KINDS: OptionKind[] = [
  'crit',
  'attackSpeed',
  'critDamage',
  'maxHp',
  'attack',
  'defense',
];

export interface ItemOption {
  kind: OptionKind;
  /** 퍼센트 옵션은 퍼센트 포인트, 나머지는 그대로 더할 값 */
  value: number;
}

/** 한 물건에 붙을 수 있는 옵션 수 */
export const OPTION_MIN = 1;
export const OPTION_MAX = 3;

/** 퍼센트로 읽는 옵션 — 표시에도 판정에도 100 으로 나눠 쓴다 */
const PERCENT_OPTIONS = new Set<OptionKind>(['crit', 'attackSpeed', 'critDamage']);

export function isPercentOption(kind: OptionKind): boolean {
  return PERCENT_OPTIONS.has(kind);
}

export const OPTION_LABEL: Record<OptionKind, string> = {
  crit: '치명타',
  attackSpeed: '공격 속도',
  critDamage: '치명타 데미지',
  maxHp: '체력',
  attack: '공격력',
  defense: '방어력',
};

/**
 * 등급이 옵션 범위를 넓히는 배율.
 *
 * 1등급 1.0 → 10등급 4.15. 최상위 등급이 하위 등급 셋을 합친 것보다 나아야
 * 재료를 쌓아 올릴 이유가 생긴다.
 */
export function optionGradeScale(grade: number): number {
  const g = Math.min(GRADE_MAX, Math.max(GRADE_MIN, Math.round(grade)));
  return 1 + (g - 1) * 0.35;
}

/**
 * 1등급 기준 범위.
 *
 * 퍼센트 옵션은 레벨을 타지 않는다 — 10% 는 어디서나 10% 다.
 * 수치 옵션은 요구 레벨을 타야 한다. 안 그러면 200레벨 장비에 붙은 공격력
 * +3 은 붙으나 마나다.
 */
function baseOptionRange(kind: OptionKind, level: number): { min: number; max: number } {
  switch (kind) {
    case 'crit':
      return { min: 1, max: 3 };
    case 'attackSpeed':
      return { min: 1, max: 3 };
    case 'critDamage':
      return { min: 4, max: 10 };
    // 옵션 하나가 그 자리의 기본 수치를 넘어서면 기본이 장식이 된다.
    // 1등급 최대가 기본의 3할쯤, 10등급 최대가 기본을 조금 넘는 선으로 잡았다.
    case 'attack':
      return { min: Math.round(1 + level * 0.06), max: Math.round(1 + level * 0.12) };
    case 'defense':
      return { min: Math.round(1 + level * 0.04), max: Math.round(1 + level * 0.08) };
    case 'maxHp':
      return { min: Math.round(3 + level * 0.6), max: Math.round(5 + level * 1.2) };
  }
}

/**
 * 이 등급에서 이 옵션이 나올 수 있는 범위.
 *
 * 창에 그대로 보여준다 — "몇 등급이면 얼마까지 뜨나"를 알 수 없으면
 * 등급을 올릴 이유를 설명할 수 없다.
 */
export function optionRange(
  kind: OptionKind,
  grade: number,
  level: number
): { min: number; max: number } {
  const base = baseOptionRange(kind, level);
  const scale = optionGradeScale(grade);
  const min = Math.max(1, Math.round(base.min * scale));
  const max = Math.max(min, Math.round(base.max * scale));
  return { min, max };
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
  if (item.material) return []; // 재료는 끼는 물건이 아니다

  const count = OPTION_MIN + Math.floor(rng() * (OPTION_MAX - OPTION_MIN + 1));
  const pool = [...OPTION_KINDS];

  const out: ItemOption[] = [];
  for (let i = 0; i < Math.min(count, pool.length); i++) {
    const kind = pool.splice(Math.floor(rng() * pool.length), 1)[0]!;
    const { min, max } = optionRange(kind, grade, item.level);
    out.push({ kind, value: min + Math.round(rng() * (max - min)) });
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

    const { min, max } = optionRange(kind, grade, item.level);
    seen.add(kind);
    out.push({ kind, value: Math.min(max, Math.max(min, Math.round(value))) });
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
export const MAX_ENHANCE = 10;

/** 강화 수치가 올리는 배율 */
export function enhanceMultiplier(level: number): number {
  const n = Math.min(MAX_ENHANCE, Math.max(0, Math.round(level || 0)));
  return 1 + n * 0.08;
}

export interface EnhanceOdds {
  success: number;
  keep: number;
  destroy: number;
}

/**
 * +level 에서 한 번 더 두드릴 때의 확률.
 *
 * 낮은 구간은 거의 성공하고, 중반부터 유지가 늘고, 높은 구간에서만 부서진다.
 * 처음부터 부서지면 강화를 아예 안 하게 되고, 끝까지 안 부서지면 골드만 있으면
 * 되는 일이 된다.
 */
export function enhanceOdds(level: number): EnhanceOdds {
  const n = Math.max(0, Math.round(level || 0));
  if (n <= 3) return { success: 0.95, keep: 0.05, destroy: 0 };
  if (n <= 6) return { success: 0.7, keep: 0.3, destroy: 0 };
  if (n <= 8) return { success: 0.45, keep: 0.45, destroy: 0.1 };
  return { success: 0.3, keep: 0.5, destroy: 0.2 };
}

/** 한 번 두드리는 값 — 골드만 쓴다 */
export function enhanceCost(item: ItemDef, level: number): number {
  const n = Math.max(0, Math.round(level || 0));
  return Math.round(item.price * 2 * (n + 1) * gradeMultiplier(1));
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
  return {
    attack: Math.round((item.bonus.attack ?? 0) * m),
    defense: Math.round((item.bonus.defense ?? 0) * m),
    maxHp: Math.round((item.bonus.maxHp ?? 0) * m),
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
}

export function emptyStats(): ItemStats {
  return { attack: 0, defense: 0, maxHp: 0, crit: 0, critDamage: 0, attackSpeed: 0 };
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

  for (const option of stack.options ?? []) {
    switch (option.kind) {
      case 'attack': total.attack += option.value; break;
      case 'defense': total.defense += option.value; break;
      case 'maxHp': total.maxHp += option.value; break;
      case 'crit': total.crit += option.value / 100; break;
      case 'critDamage': total.critDamage += option.value / 100; break;
      case 'attackSpeed': total.attackSpeed += option.value / 100; break;
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
 * 제작.
 *
 * 예전에는 같은 물건 3개를 합쳤는데, 이제 **보스가 떨구는 재료**로 올린다.
 * 쓰던 장비를 그대로 올리므로 똑같은 걸 여러 개 모을 필요가 없고,
 * 대신 상위 등급은 보스를 몇 번 잡았느냐에 걸린다.
 */

/** 목표 등급 하나를 만드는 데 드는 재료 수 */
export function materialsNeeded(targetGrade: number): number {
  return Math.max(1, targetGrade - 1);
}

/** 제작 수수료 */
export function craftCost(item: ItemDef, currentGrade: number): number {
  return Math.round(item.price * 0.5 * gradeMultiplier(currentGrade));
}

/** 이 등급에서 위로 올릴 수 있는지 */
export function canCraftUp(grade: number): boolean {
  return grade >= GRADE_MIN && grade < GRADE_MAX;
}

export interface CraftRequirement {
  targetGrade: number;
  materialId: string;
  materialName: string;
  materialCount: number;
  gold: number;
}

/**
 * 이 장비를 한 등급 올리는 데 필요한 것.
 *
 * 재료는 **그 장비와 같은 단계**의 것을 쓴다. 낮은 단계 재료로 최상위 장비를
 * 올릴 수 있으면 초반 보스만 반복해서 끝나버린다.
 */
export function craftRequirement(item: ItemDef, currentGrade: number): CraftRequirement | null {
  if (!canCraftUp(currentGrade) || item.material) return null;

  const tier = tierIndexOf(item);
  const materialId = materialIdFor(tier);
  const target = currentGrade + 1;

  return {
    targetGrade: target,
    materialId,
    materialName: ITEMS[materialId]?.name ?? materialId,
    materialCount: materialsNeeded(target),
    gold: craftCost(item, currentGrade),
  };
}

/** 아이템 id 끝에 붙은 단계 번호 */
export function tierIndexOf(item: ItemDef): number {
  const tag = item.id.slice(-2);
  const parsed = Number.parseInt(tag, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * 새로 만들기.
 *
 * 등급 올리기가 "가진 걸 더 좋게"라면 이건 "없는 걸 마련한다"이다.
 * 드롭은 슬롯 8종에 고루 퍼지지만 운이라, 투구만 끝내 안 나오는 일이 생긴다.
 * 그때 보스 재료로 원하는 자리를 직접 채운다.
 *
 * 등급 올리기보다 재료를 더 쓴다 — 없던 걸 만드는 쪽이 싸면 아무도 줍지 않는다.
 */
export const FORGE_MATERIALS = 5;

export interface ForgeRecipe {
  itemId: string;
  materialId: string;
  materialName: string;
  materialCount: number;
  gold: number;
}

/** 이 장비를 1등급으로 만들 때 드는 것 */
export function forgeRecipe(item: ItemDef): ForgeRecipe | null {
  if (item.material) return null;

  const materialId = materialIdFor(tierIndexOf(item));
  return {
    itemId: item.id,
    materialId,
    materialName: ITEMS[materialId]?.name ?? materialId,
    materialCount: FORGE_MATERIALS,
    gold: Math.round(item.price * 1.5),
  };
}

/**
 * 그 캐릭터가 만들 수 있는 것 — 자기 레벨까지의 장비 전부.
 *
 * 상점이 무기만 파는 것과 짝이 된다. 방어구·장신구는 사냥으로 줍거나
 * 여기서 만든다.
 */
export function forgeableFor(job: JobId, level: number): string[] {
  return Object.values(ITEMS)
    .filter((item) => {
      if (item.material) return false;
      if (item.job && item.job !== job) return false;
      return item.level <= level;
    })
    .sort((a, b) => a.level - b.level || a.slot!.localeCompare(b.slot!))
    .map((item) => item.id);
}

// ---------------------------------------------------------------- 드롭

/** 몬스터 레벨에 맞는 단계 번호 */
export function tierForLevel(monsterLevel: number): number {
  const index = Math.floor(monsterLevel / 10);
  return Math.min(TIER_PREFIX.length - 1, Math.max(0, index));
}

/** 아이템이 떨어질 확률 */
export const DROP_CHANCE = 0.14;

/**
 * 등급별 상대 빈도.
 *
 * 한 등급 오를 때마다 절반으로 준다. 7등급은 전체 드롭의 1% 이하라
 * 나오면 기억에 남는다.
 */
function gradeWeights(): number[] {
  const out: number[] = [];
  for (let g = GRADE_MIN; g <= MAX_DROP_GRADE; g++) out.push(2 ** (MAX_DROP_GRADE - g));
  return out;
}

/** 굴림값(0~1)에서 드롭 등급 하나 */
export function rollGrade(roll: number): number {
  const weights = gradeWeights();
  const total = weights.reduce((a, b) => a + b, 0);
  let cursor = Math.max(0, Math.min(0.999999, roll)) * total;
  for (let i = 0; i < weights.length; i++) {
    cursor -= weights[i]!;
    if (cursor < 0) return GRADE_MIN + i;
  }
  return MAX_DROP_GRADE;
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

  const grade = rollGrade(rng());
  const def = getItem(id);
  return { gold, item: { id, grade, options: def ? rollOptions(def, grade, rng) : [] } };
}

/** 보스가 한 번에 떨구는 재료 수 */
export const BOSS_MATERIALS = 3;

export interface BossDrop {
  gold: number;
  materialId: string;
  count: number;
}

/**
 * 보스 보상.
 *
 * 재료는 **반드시** 나온다. 최상위 등급으로 가는 유일한 길이라 운에 맡기면
 * 보스를 잡고도 아무것도 못 얻는 일이 생기고, 그건 3분을 기다린 값이 아니다.
 */
export function rollBossDrop(monsterLevel: number, rng: () => number = Math.random): BossDrop {
  const base = (2 + monsterLevel * 1.5) * 12;
  return {
    gold: Math.max(1, Math.round(base * (0.8 + rng() * 0.4))),
    materialId: materialIdFor(tierForLevel(monsterLevel)),
    count: BOSS_MATERIALS,
  };
}
