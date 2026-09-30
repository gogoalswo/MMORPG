/**
 * 헬스 — 던전에서 받은 **프로틴**으로 세 운동의 단계를 올려 캐릭터 능력치를 키운다
 * (2026-09-30 요청: "헬스라는 컨텐츠 만들어. 프로틴 먹고 능력치 업그레이드").
 *
 *   벤치프레스 ── 파워 프로틴   ── 공격력 +%
 *   데드리프트 ── 디펜스 프로틴 ── 방어력 +%
 *   스쿼트     ── 헬스 프로틴   ── 체력  +%
 *
 * - **확률 강화다.** 한 번 두드릴 때마다 그 단계의 프로틴이 들고, 성공하면 단계가 오른다.
 *   실패해도 **단계는 안 내려간다** — 프로틴만 없어진다.
 * - 보너스는 **장비 % 와 곱한다** (`기본 × (1 + 장비%) × (1 + 헬스%)`). 장비 % 에 더하면
 *   태초 풀셋(공격력 +856%) 앞에서 +50% 가 +5% 로 줄어든다 — 언제 올려도 같은 비율로 세지게 곱한다.
 * - 판정은 장부(`Ledger.fitness_up`)가 한다. 이 표는 수치만 갖는다 → docs/features/fitness.md
 */

export type FitnessStat = 'attack' | 'defense' | 'maxHp';

export interface FitnessKind {
  id: string;
  /** 탭 이름 */
  name: string;
  /** 올리는 능력치 — `Stats` 의 키 */
  stat: FitnessStat;
  statName: string;
  /** 드는 프로틴 id — 장부의 `proteins` 사전 키 */
  protein: string;
  proteinName: string;
}

export const FITNESS_KINDS: FitnessKind[] = [
  { id: 'bench', name: '벤치프레스', stat: 'attack', statName: '공격력', protein: 'power', proteinName: '파워 프로틴' },
  { id: 'deadlift', name: '데드리프트', stat: 'defense', statName: '방어력', protein: 'defense', proteinName: '디펜스 프로틴' },
  { id: 'squat', name: '스쿼트', stat: 'maxHp', statName: '체력', protein: 'health', proteinName: '헬스 프로틴' },
];

/** 운동마다 오를 수 있는 끝 단계 */
export const FITNESS_MAX_STAGE = 20;

/**
 * 단계 k 로 오르는 **성공 확률(%)** — 앞에서부터 1단계, 2단계 … 20단계.
 * 다섯 단계씩 네 구간이다: 초반은 거의 붙고(90~70), 중반 반반(60~40), 후반 한 자릿수까지.
 */
export const FITNESS_CHANCE = [
  90, 85, 80, 75, 70,
  60, 55, 50, 45, 40,
  30, 27, 24, 21, 18,
  12, 10, 8, 6, 5,
];

/**
 * 단계 k 가 올려 주는 몫(%) — 구간마다 1 · 2 · 3 · 4 %. 끝(20단계)까지 합이 **+50%**.
 * 뒤 단계일수록 확률이 낮은 만큼 한 단계의 몫도 크게 준다.
 */
export const FITNESS_GAIN_BY_BAND = [1, 2, 3, 4];
const BAND = 5;

/** 단계 k 로 한 번 두드리는 프로틴 — 10 × 1.25^(k-1) (1단계 10개 → 20단계 694개) */
export const FITNESS_COST_BASE = 10;
export const FITNESS_COST_GROWTH = 1.25;

/**
 * 던전 N단계를 깨면 **프로틴 세 종을 각각** N × 이만큼 (토벌 · 시련의 탑 둘 다).
 * 세 운동이 한 번에 같이 자란다 — 한 종만 주면 셋을 고루 올리는 데 세 배가 든다.
 */
export const DUNGEON_PROTEIN_PER_STAGE = 5;

export interface FitnessStep {
  /** 이 단계로 오른다 (1부터) */
  stage: number;
  /** 성공 확률 % */
  chance: number;
  /** 한 번 두드리는 프로틴 */
  cost: number;
  /** 이 단계가 더하는 % */
  gain: number;
  /** 이 단계까지 모은 % */
  total: number;
}

export const FITNESS_STEPS: FitnessStep[] = (() => {
  let total = 0;
  return FITNESS_CHANCE.map((chance, i) => {
    const gain = FITNESS_GAIN_BY_BAND[Math.floor(i / BAND)];
    total += gain;
    return {
      stage: i + 1,
      chance,
      cost: Math.round(FITNESS_COST_BASE * FITNESS_COST_GROWTH ** i),
      gain,
      total,
    };
  });
})();

/** 단계 `stage` 까지 모은 보너스(%) — 0 단계는 0 */
export function fitnessBonus(stage: number): number {
  if (stage <= 0) return 0;
  return FITNESS_STEPS[Math.min(stage, FITNESS_MAX_STAGE) - 1].total;
}

/** 끝 단계까지 드는 프로틴 기댓값 (한 운동) — 문서의 "얼마나 걸리나" 가 이 값이다 */
export function fitnessExpectedCost(): number {
  return FITNESS_STEPS.reduce((sum, s) => sum + s.cost / (s.chance / 100), 0);
}
