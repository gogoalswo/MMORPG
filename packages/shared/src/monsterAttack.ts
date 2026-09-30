/**
 * 몬스터 공격력 역산 — **"한 마리 잡는 동안 HP 10% 를 잃는다"** ★★ (2026-09-30)
 *
 * 지시: "전체적으로 몬스터 공격력이 너무 낮은 것 같아" → "한 마리 잡는동안 체력을 10% 정도
 * 잃게 만들면 좋겠는데?" 그 전 공격력은 설계(`monsterByDesign`)의 "3~6마리가 **동시에** 때려
 * 한 무리 정리에 HP 50%" 에서 나왔는데, 사냥터는 이제 한 마리씩 떨어져 서 있고(간격 8m ·
 * 어그로 3m) 격투가는 질풍각으로 초당 1~10타를 때려 한 마리를 2~4초에 잡는다. 그래서 실제로는
 * 한 마리에 **0.4~1.8%** 밖에 안 잃었다.
 *
 * 기준은 **그 레벨 격투가** — 기준 장비(`refWorn`) + 그 레벨까지 열린 패시브 전부
 * (`World.stats_of` 와 같은 식). 같은 레벨 몬스터를 평타로 잡는 시간 동안 1.5초마다 맞아서
 * 잃는 HP 가 `HP_LOSS_PER_KILL` 이 되게 공격력을 거꾸로 푼다.
 *
 * **표는 여전히 고정이다** — 이 파일은 `scripts/fit-monster-attack.mjs` 가 **사람이 부를 때만**
 * 쓴다 (`monsterTable.ts` 의 공격력 열을 덮어쓴다). 테스트는 표가 여기서 얼마나 벗어났는지 본다.
 */
import { MON_ATTACK_INTERVAL, damage, damageTaken, defK, gearTotals, monster, refWorn } from './balance.ts';
import { effectiveCooldown, statsFor } from './combat.ts';
import { monsterCritResist } from './monsters.ts';
import { PASSIVES, passiveRankOpen } from './skills.ts';

/** 같은 레벨 몬스터 한 마리를 잡는 동안 잃는 HP 비율 */
export const HP_LOSS_PER_KILL = 0.1;

/** 그 레벨 격투가 — 기준 장비 + 그 레벨까지 열린 패시브 전부 (`World.stats_of` 와 같은 식) */
export function refFighter(level: number) {
  const s = statsFor('fighter', level);
  const g = gearTotals(refWorn(level));
  const p = { attack: 0, attackSpeed: 0, crit: 0, critDamage: 0, penetration: 0, moveSpeed: 0 };
  for (const def of PASSIVES) {
    if (def.job === 'fighter') p[def.stat] += def.perRank * passiveRankOpen(def, level);
  }
  return {
    hp: Math.round(s.maxHp * (1 + g.hp / 100)),
    atk: Math.round(s.attack * (1 + g.atk / 100 + p.attack)),
    df: Math.round(s.defense * (1 + g.df / 100)),
    crit: s.crit + g.crit + p.crit,
    critDamage: s.critDamage + g.critDamage + p.critDamage,
    penetration: p.penetration,
    interval: effectiveCooldown(s.attackCooldown, s.attackSpeed + p.attackSpeed) / 1000,
  };
}

/** 그 레벨 격투가가 같은 레벨 몬스터 한 마리를 평타로 잡는 초 (치명타는 평균으로) */
export function fighterKillSeconds(level: number): number {
  const f = refFighter(level);
  const m = monster(level);
  const crit = Math.max(0, f.crit - monsterCritResist(level));
  const hit = damage(f.atk, level, m.df * (1 - f.penetration)) * (1 + crit * f.critDamage);
  return (m.hp / hit) * f.interval;
}

/** 한 마리 잡는 동안 잃는 HP 비율 — `atk` 를 안 주면 지금 표의 공격력 */
export function hpLossPerKill(level: number, atk = monster(level).atk): number {
  const f = refFighter(level);
  const hits = fighterKillSeconds(level) / MON_ATTACK_INTERVAL;
  return (hits * damageTaken(atk, level, f.df)) / f.hp;
}

/** `HP_LOSS_PER_KILL` 이 되는 공격력 — `damageTaken` 을 거꾸로 푼다 */
export function monsterAtkForLoss(level: number, loss = HP_LOSS_PER_KILL): number {
  const f = refFighter(level);
  const hit = (loss * f.hp * MON_ATTACK_INTERVAL) / fighterKillSeconds(level);
  const k = defK(level);
  return (hit * (k + f.df)) / k;
}
