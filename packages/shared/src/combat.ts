import type { JobId } from './character.ts';

/**
 * 스탯과 전투 계산.
 *
 * 클라이언트는 화면 표시(내 공격력, 예상 피해)에, 서버는 실제 판정에 쓴다.
 * **판정은 오직 서버에서만 한다** — 클라이언트가 "내가 3000 때렸다"고 보내는 걸
 * 믿으면 게임이 성립하지 않는다. 여기 있는 건 양쪽이 같은 수치를 말하기 위한 것이다.
 */

export interface Stats {
  maxHp: number;
  maxMp: number;
  /** 공격력 */
  attack: number;
  /** 방어력 */
  defense: number;
  /** 공격이 닿는 거리 (m) */
  attackRange: number;
  /** 공격 간격 (ms) */
  attackCooldown: number;
  /** 치명타 확률 (0~1) */
  crit: number;
  /** 치명타로 터졌을 때의 배율 */
  critDamage: number;
  /** 공격 속도 가산 (0.2 = 간격이 1.2 로 나뉜다) */
  attackSpeed: number;
}

/**
 * 치명타·공격 속도의 바탕값.
 *
 * 직업으로 가르지 않는다 — 이 셋은 장비 옵션으로 벌리는 축이라, 바탕까지
 * 직업마다 다르면 어느 쪽이 원인인지 알 수 없게 된다.
 */
export const BASE_CRIT = 0.05;
export const BASE_CRIT_DAMAGE = 1.5;

/**
 * 상한.
 *
 * 옵션이 여덟 자리에 3개씩 붙으므로 그냥 두면 치명타 100%, 공격 속도 몇 배가
 * 나온다. 그러면 다른 옵션은 고를 이유가 없어지고 전투는 숫자가 아니라
 * 장비 뽑기가 된다.
 */
export const CRIT_CAP = 0.75;
export const ATTACK_SPEED_CAP = 1;

/** 공격 속도를 반영한 실제 공격 간격 (ms) */
export function effectiveCooldown(cooldown: number, attackSpeed: number): number {
  const speed = Math.max(0, Math.min(ATTACK_SPEED_CAP, attackSpeed || 0));
  return Math.max(1, Math.round(cooldown / (1 + speed)));
}

/** 굴림값(0~1)이 치명타인지 */
export function rollCrit(chance: number, roll: number): boolean {
  return roll < Math.max(0, Math.min(CRIT_CAP, chance || 0));
}

interface JobGrowth {
  /** 치명타·공격 속도는 직업으로 가르지 않으므로 여기 적지 않는다 */
  base: Omit<Stats, 'crit' | 'critDamage' | 'attackSpeed'>;
  /** 레벨당 증가분 */
  perLevel: Partial<Stats>;
}

/**
 * 직업 성격을 수치로 정한다.
 *  기사   — 단단하고 오래 버틴다. 사거리는 짧다.
 *  마법사 — 종잇장이지만 한 대가 아프고 멀리 닿는다.
 *  궁수   — 중간. 사거리를 유지하며 꾸준히 넣는다.
 */
const JOB_GROWTH: Record<JobId, JobGrowth> = {
  knight: {
    base: { maxHp: 140, maxMp: 30, attack: 12, defense: 8, attackRange: 2.4, attackCooldown: 900 },
    perLevel: { maxHp: 14, maxMp: 2, attack: 2.2, defense: 1.4 },
  },
  mage: {
    base: { maxHp: 80, maxMp: 90, attack: 20, defense: 3, attackRange: 9, attackCooldown: 1300 },
    perLevel: { maxHp: 6, maxMp: 9, attack: 3.6, defense: 0.5 },
  },
  archer: {
    base: { maxHp: 100, maxMp: 50, attack: 15, defense: 5, attackRange: 12, attackCooldown: 800 },
    perLevel: { maxHp: 9, maxMp: 5, attack: 2.8, defense: 0.9 },
  },
};

export function statsFor(job: JobId, level: number): Stats {
  const growth = JOB_GROWTH[job];
  const steps = Math.max(0, level - 1);
  const add = growth.perLevel;
  return {
    maxHp: Math.round(growth.base.maxHp + (add.maxHp ?? 0) * steps),
    maxMp: Math.round(growth.base.maxMp + (add.maxMp ?? 0) * steps),
    attack: Math.round(growth.base.attack + (add.attack ?? 0) * steps),
    defense: Math.round(growth.base.defense + (add.defense ?? 0) * steps),
    attackRange: growth.base.attackRange,
    attackCooldown: growth.base.attackCooldown,
    crit: BASE_CRIT,
    critDamage: BASE_CRIT_DAMAGE,
    attackSpeed: 0,
  };
}

/** 공격이 닿는 정면 각도(라디안). 등 뒤의 적은 맞지 않는다 */
export const ATTACK_ARC = Math.PI * 0.6;

/**
 * 피해량.
 *
 * 방어력을 빼기만 하면 방어가 공격을 넘는 순간 0 이 되어 전투가 멈춘다.
 * 비율로 감쇠시켜 항상 조금은 들어가게 한다.
 */
export function computeDamage(attack: number, defense: number): number {
  const reduction = defense / (defense + 45);
  return Math.max(1, Math.round(attack * (1 - reduction)));
}

/** 다음 레벨까지 필요한 누적 경험치 */
/**
 * 다음 레벨까지 필요한 경험치.
 *
 * 지수를 1.45 에서 1.2 로 낮췄다. 1.45 는 필요량이 몬스터 보상보다 훨씬 빨리
 * 늘어서, 구간 후반이면 한 레벨에 40~50마리씩 잡아야 했다.
 *
 * 몬스터를 5레벨 간격으로 배치한 것과 맞물려(`monsters.ts`) 레벨당 대체로
 * 4~15마리, 1 → 40 이 약 390마리가 된다. `combat.test.ts` 가 이 범위를 지킨다.
 */
export function expToNext(level: number): number {
  return Math.round(55 * Math.pow(level, 1.2));
}

/**
 * 만렙.
 *
 * 사냥터 20곳이 10레벨씩 덮어 Lv 200 까지 간다 (초원 1-10 … 종말의 대지 190-200).
 * 콘텐츠 없는 구간을 열어두면 만렙 근처에서 잡을 게 없어 멈추므로 맵과 같이 움직인다.
 */
export const MAX_LEVEL = 200;

/** 레벨과 남은 경험치를 다시 계산한다 (한 번에 여러 레벨이 오를 수 있다) */
export function applyExp(level: number, exp: number, gained: number): { level: number; exp: number } {
  let nextLevel = level;
  let pool = exp + Math.max(0, Math.round(gained));

  while (nextLevel < MAX_LEVEL) {
    const need = expToNext(nextLevel);
    if (pool < need) break;
    pool -= need;
    nextLevel++;
  }

  if (nextLevel >= MAX_LEVEL) pool = 0;
  return { level: nextLevel, exp: pool };
}

/** 레벨 차이에 따른 경험치 보정 — 약한 몬스터만 잡는 걸 막는다 */
export function expReward(monsterLevel: number, playerLevel: number, base: number): number {
  const gap = monsterLevel - playerLevel;
  if (gap <= -8) return 0;
  const scale = gap >= 0 ? 1 + gap * 0.12 : 1 + gap * 0.11;
  return Math.max(1, Math.round(base * Math.max(0.1, scale)));
}
