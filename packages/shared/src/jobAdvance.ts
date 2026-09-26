import type { GateDef, ZoneDef } from './zone.ts';
import { bossIdFor, bossLevel } from './monsters.ts';
import { DUNGEON_BOSS_SPOT, DUNGEON_ENV } from './dungeons.ts';

/**
 * **전직** (2026-09-26 요청) — 레벨 30 · 70 · 120 · 180 이 되면 마을의 전직 NPC 에게서
 * 다음 전직을 받을 수 있다. 버튼을 누르면 **전직 시험(존)** 으로 옮겨지고, 거기 선
 * **보스를 잡으면 전직이 되며** 그 단계의 스킬이 풀린다 (스킬 표의 `tier`).
 *
 *   전직 NPC ─ "N차 전직" 버튼 (레벨이 되면 눌린다)
 *        └─▶ N차 전직 시험 (보스 한 마리) ─ 잡으면 ─▶ N차 전직 · 스킬 해금
 *
 * **보스는 사냥터 보스를 그대로 쓴다** (던전과 같은 이유 — 새 종·새 모델을 짓지 않는다).
 * 전직 레벨 L 에는 **L-1 레벨 보스**(`bossIdFor(L/10 - 1)`)가 선다 — 30 이면 3번째
 * 사냥터 보스(Lv.29). 레벨이 되자마자 오는 곳이라 한 급 아래 보스가 맞다.
 */

export interface JobAdvanceDef {
  /** 몇 차 전직인가 — 1부터 */
  tier: number;
  /** 버튼이 눌리는 레벨 */
  level: number;
  /** 옮겨 갈 시험 존 id — `ZONES` 에 있다 */
  zone: string;
  boss: string;
  bossLevel: number;
}

/** 전직 레벨 — 차례대로 1차 · 2차 · 3차 · 4차 */
export const JOB_ADVANCE_LEVELS = [30, 70, 120, 180];

const jobZoneId = (tier: number) => `job_${tier}`;

export const JOB_ADVANCES: JobAdvanceDef[] = JOB_ADVANCE_LEVELS.map((level, i) => {
  const index = level / 10 - 1;
  return {
    tier: i + 1,
    level,
    zone: jobZoneId(i + 1),
    boss: bossIdFor(index),
    bossLevel: bossLevel(index),
  };
});

/** 가장 높은 전직 단계 */
export const JOB_TIER_MAX = JOB_ADVANCES.length;

/**
 * 전직 시험마다 존 하나. 던전 존과 같은 틀(보스 자리·어두운 돌길)이다.
 * **차원문 목록에도 던전 창에도 없다** — 전직 NPC 로만 간다 (`World.travel` 이 거른다).
 * 나오는 길은 다른 존과 같은 차원문이다.
 */
export function jobAdvanceZones(gate: () => GateDef): ZoneDef[] {
  return JOB_ADVANCES.map((a) => ({
    id: a.zone,
    name: `${a.tier}차 전직 시험`,
    size: 66,
    spawns: { default: [0, 0] },
    gate: gate(),
    monsters: [{ kind: a.boss, x: DUNGEON_BOSS_SPOT[0], z: DUNGEON_BOSS_SPOT[1], radius: 3, count: 1, respawnMs: 900000 }],
    env: DUNGEON_ENV,
  }));
}
