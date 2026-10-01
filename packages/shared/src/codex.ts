/**
 * 장비 도감 — 등급마다 **부위 6개 × 강화 +0 ~ +9 = 60칸**, 등급 7개라 모두 420칸
 * (2026-10-01 요청: "각 등급 0강부터 9강까지 등록할 수 있는 도감 … 파츠별로 … 탭 만들어서
 * 일반부터 태초등급까지").
 *
 * - 칸 하나 = (등급, 부위, 강화). 가방에서 **그 등급·부위·강화의 장비 하나를 넣으면(소모)** 칸이 찬다.
 *   끼고 있는 장비는 넣지 않는다 — 몸에서 벗겨져 사라지면 되돌릴 수 없다.
 * - 칸이 찰 때마다 **그 부위의 능력치가 % 로** 붙는다 (아래 `CODEX_SLOT_STAT`).
 *   보너스는 헬스처럼 **장비 % 와 따로 곱한다** — 더하면 태초 풀셋 앞에서 안 보인다.
 * - 판정은 장부(`Ledger.codex_register`)가 한다. 이 표는 수치만 갖는다 → docs/features/codex.md
 */

import { GRADE_MAX, GRADE_MIN } from './items.ts';
import { EQUIP_SLOTS } from './slots.ts';

export type CodexStat = 'attack' | 'defense' | 'maxHp';

/**
 * 부위가 올리는 능력치 — **능력치 하나에 부위 둘씩** 묶어 셋이 같은 크기로 자란다.
 * 무기·목걸이 = 공격력(장비 기본에 공격력이 있는 둘), 갑옷·투구 = 방어력, 신발·반지 = 체력.
 */
export const CODEX_SLOT_STAT: Record<string, CodexStat> = {
  weapon: 'attack',
  necklace: 'attack',
  armor: 'defense',
  helmet: 'defense',
  boots: 'maxHp',
  ring: 'maxHp',
};

export const CODEX_STAT_NAMES: Record<CodexStat, string> = {
  attack: '공격력',
  defense: '방어력',
  maxHp: '체력',
};

/** 칸마다 강화 +0 ~ +이것까지 — 강화 끝(+9)과 같다 */
export const CODEX_MAX_ENHANCE = 9;

/**
 * 등급별 **+0 칸 하나의 몫(%)** — 일반 → 태초. 높은 등급일수록 구하기 어려워 크게 준다.
 */
export const CODEX_GRADE_VALUE = [0.01, 0.02, 0.03, 0.05, 0.08, 0.12, 0.2];

/**
 * (등급, 강화) 칸 하나의 몫(%) = 등급 몫 × (강화 + 1) — +0 은 ×1, +9 는 ×10.
 * 강화는 실패하면 부서지므로(+9 까지 닿을 확률이 매우 낮다) 높은 강화 칸을 크게 준다.
 * 곱이 늘 0.01 의 배수라 소수 둘째 자리에서 같은 값이 겹치지 않는다
 * (처음 안 `× (1 + 0.1 × 강화)` 는 반올림하면 0.06 · 0.06 처럼 겹쳤다).
 */
export function codexCellValue(grade: number, enhance: number): number {
  const base = CODEX_GRADE_VALUE[grade - GRADE_MIN] ?? 0;
  return Math.round(base * (enhance + 1) * 100) / 100;
}

/** 칸 몫 표 — `[등급-1][강화]` (고도는 이 표를 그대로 읽는다) */
export const CODEX_CELLS: number[][] = (() => {
  const out: number[][] = [];
  for (let grade = GRADE_MIN; grade <= GRADE_MAX; grade++) {
    const row: number[] = [];
    for (let enhance = 0; enhance <= CODEX_MAX_ENHANCE; enhance++) row.push(codexCellValue(grade, enhance));
    out.push(row);
  }
  return out;
})();

/** 도감을 다 채웠을 때 능력치 하나의 몫(%) — 문서의 "다 채우면" 이 이 값이다 */
export function codexFullBonus(stat: CodexStat): number {
  const slots = EQUIP_SLOTS.filter((slot) => CODEX_SLOT_STAT[slot] === stat).length;
  const sum = CODEX_CELLS.reduce((acc, row) => acc + row.reduce((a, b) => a + b, 0), 0);
  return Math.round(sum * slots * 100) / 100;
}
