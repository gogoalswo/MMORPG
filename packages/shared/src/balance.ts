/**
 * 밸런스 기본기 — 레벨 곡선 · 피해 공식 · 몬스터 역산.
 *
 * 원본은 [stat-balance.md](../../../docs/features/stat-balance.md) 1·2·5·6장이고,
 * 검증기는 `tools/balance_sim.py` 다. **식과 상수 이름을 그 스크립트와 맞춰 뒀다** —
 * 숫자를 두 곳에 두지 않는 것이 이 설계의 핵심이라, 어긋나면 `balance.test.ts` 가 잡는다.
 * 장비 쪽(등급·슬롯·강화)은 [gear.ts](gear.ts) 에 있다.
 *
 * **2026-09-20 에 판정에 붙였다.** `combat.ts` 의 `statsFor`·`expToNext` 와
 * `monsters.ts` 의 능력치가 전부 여기서 나오고, 고도는 `world/stats.gd` 로 같은 식을
 * 돌린다. 옛 공식(`JOB_STATS` 선형 · `55×레벨^1.2` · `20L+40`)은 전부 걷었다.
 */
import { JOB_IDS, type JobId } from './character.ts';
import { EQUIP_SLOTS, type EquipSlot } from './slots.ts';
import {
  ASPD_MAX,
  CRIT_DMG_MAX,
  CRIT_RATE_MAX,
  ENH_ACCEL,
  ENH_MAX,
  ENH_ODDS,
  ENH_TOTAL,
  GEAR_ATK_FACTOR,
  GEAR_DEF_FACTOR,
  GEAR_DROP_RATE,
  GEAR_HP_FACTOR,
  GRADE_COUNT,
  GRADE_LV_SPAN,
  GRADE_SUM_END,
  GRADE_SUM_START,
  MOVE_SPD_MAX,
  SLOT_SHARE,
  dropField,
  equipLevel,
  gradeOf,
  slotStats,
  type GearStat,
} from './gear.ts';

export const MAX_LEVEL = 200;
/** 사냥터 하나가 담당하는 레벨 폭 → 사냥터 20개 */
export const FIELD_SPAN = 10;

/** Lv1 맨몸 기본 스탯 */
export const HP_BASE = 100;
export const ATK_BASE = 10;
export const DEF_BASE = 10;

/**
 * 레벨당 성장률 — **복리다.**
 *
 * 선형(레벨당 +2 같은 고정값)으로 두면 레벨당 상대 성장이 Lv2→3 은 +18%,
 * Lv199→200 은 +0.5% 로 40배 차이가 난다. 그러면 "장비 비중" 이라는 개념 자체가
 * 레벨대마다 다른 뜻이 되어 밸런스를 잡을 기준이 사라진다. 복리면 **레벨 1개는
 * 언제나 총 피해 +2%** 로 일정하다.
 *
 * 2.0% 를 고른 이유는 Lv200 에서 51배로 숫자가 읽을 수 있는 크기에 머물고
 * (HP 5,146 / 공격력 515), 10레벨 사냥터 하나당 ×1.22 라는 눈금이 생기기 때문이다.
 */
export const GROWTH = 0.02;

/** 기준 플레이어의 피해 감소율. `K` 를 여기서 역산한다 */
export const TARGET_REDUCE = 0.3;
/** 몬스터 방어력 = 기준 플레이어 총방어력 × 이것 (몬스터는 방어보다 체력형이어야 타격감이 산다) */
export const MON_DEF_RATIO = 0.5;
export const MON_ATTACK_INTERVAL = 1.5;
export const PLAYER_ATTACK_INTERVAL = 1.0;

/** 범위 스킬이 몬스터 한 마리에 넣는 타격 횟수 */
export const TTK_HITS = 6;
/**
 * 몬스터 HP 를 정확히 `TTK_HITS` 타분으로 잡으면 **기준과 같은 장비가 늘 올림 경계에
 * 얹힌다** — 0.4% 만 모자라도 한 타가 더 든다(풀세트에서 슬롯 하나가 덜 찬 상태가
 * 바로 그것이다). HP 를 이만큼 깎아 경계에서 떨어뜨린다. 0.5% 면 그 한 슬롯을
 * 흡수하고, 그 이상(2%)은 다른 구간의 천장을 대신 무너뜨린다.
 */
export const TTK_MARGIN = 0.005;
/** 한 그룹을 정리하는 목표 시간(초) */
export const CLEAR_TIME = 15;
/** 그동안 잃는 HP 비율 */
export const HP_LOSS_PER_CLEAR = 0.5;
/** 경험치 = 몬스터 HP × 이것 (정비례) */
export const EXP_COEF = 0.2;

/** 그룹 간 대기(리스폰·이동) 초. **설계 파라미터다** — 이게 없으면 한 방에 죽는 */
/** 저레벨 그룹이 시간당 효율이 더 좋아진다 */
export const GROUP_GAP = 3;
/** Lv1 → 만렙 총 사냥 시간. 24시간 × 120일 = 4개월 */
export const TARGET_HOURS = 2880;
/** 사냥터가 하나 올라갈 때마다 "레벨당 필요 킬 수" × 이 값 */
export const KILLS_FIELD_MULT = 1.5;
/** 이 사냥터까지가 초반 (Lv1~30). 스킬이 모자라 사냥 속도가 후반의 1/3 이다 */
export const EARLY_FIELDS = 3;
/** 사냥터 1 의 레벨당 목표 시간(분) */
export const EARLY_LEVEL_MIN = 2;
/** 초반 사냥터마다 레벨당 시간 × 이 값 */
export const EARLY_TIME_MULT = 1.5;

/**
 * 직업 배수 — 기본 스탯에 곱한다. **DPS × 버티는 시간이 서로 ±10% 안**이라야
 * "어느 직업을 골라도 손해가 아니다" 가 된다 (`balance_sim.py --class`).
 *
 * 궁수는 사거리(카이팅) 이점이 있어 조금 낮게, 격투가는 이점이 없어 조금 높게 둔 것이
 * 의도다. 설계 문서에는 **기사(knight, 공 0.85 / HP 1.20 / 방 1.15 / 1.0초)** 도 있는데
 * 게임에서는 2026-09-17 에 지웠다 — 되살리면 여기 한 줄을 더한다.
 */
export const JOB_MULT: Record<JobId, { atk: number; hp: number; df: number; interval: number }> = {
  fighter: { atk: 1.0, hp: 1.0, df: 1.0, interval: 0.9 },
  mage: { atk: 1.35, hp: 0.8, df: 0.75, interval: 1.0 },
  archer: { atk: 1.35, hp: 0.9, df: 0.85, interval: 1.2 },
};

/** 역할 배수. 보스는 **설계 보류**라 자리만 잡아 둔 임시값이다 */
export const ROLE_MULT = {
  normal: { hp: 1, atk: 1 },
  elite: { hp: 3, atk: 2 },
  boss: { hp: 7, atk: 5 },
} as const;
export type MonsterRole = keyof typeof ROLE_MULT;

/**
 * 스킬 해금 단계 — **그룹 크기가 여기 묶인다.**
 *
 * 초반에는 스킬이 없어서 50마리를 15초에 정리할 수 없다. 그래서 스폰 수·범위 타격
 * 수·동시 피격 수를 스킬 해금에 맞춰 같이 키운다. 초반 사냥터는 몬스터가 드문드문,
 * 후반은 빽빽하다는 뜻이고, 정리 시간이 10초 → 15초로 서서히 목표에 수렴한다.
 */
export const SKILL_STAGES = [
  { level: 1, skills: 1, spawn: 15, aoe: 8, melee: 3 },
  { level: 10, skills: 2, spawn: 30, aoe: 14, melee: 4 },
  { level: 30, skills: 3, spawn: 50, aoe: 20, melee: 6 },
];

/** 전직 — 40레벨마다, 사냥터 경계에 맞춘다. 스킬 계수는 아직 스탯에 미반영 */
export const JOB_ADVANCES = [
  { level: 1, name: '1차' },
  { level: 41, name: '2차' },
  { level: 81, name: '3차' },
  { level: 121, name: '4차' },
  { level: 161, name: '5차' },
];

/**
 * 몬스터 역산에 쓰는 기준 강화 단계 — 사냥터 구간별로 올라간다.
 * 후반 사냥터는 체류가 수백 시간이라 드랍이 훨씬 많이 쌓인다. 4단 고정으로 두면
 * 드랍 간격이 37시간까지 벌어진다(설계 문서 7장).
 */
export const ENH_REF_BY_FIELD = [
  { field: 1, step: 4 },
  { field: 7, step: 5 },
  { field: 13, step: 6 },
  { field: 18, step: 7 },
];

export interface Stats {
  hp: number;
  atk: number;
  df: number;
}

/** 레벨 L 의 성장 배수 (Lv1 = 1.0) */
export function growth(level: number): number {
  return (1 + GROWTH) ** (level - 1);
}

/** 맨몸 기본 스탯 */
export function base(level: number): Stats {
  const g = growth(level);
  return { hp: HP_BASE * g, atk: ATK_BASE * g, df: DEF_BASE * g };
}

export function fieldCount(): number {
  return Math.ceil(MAX_LEVEL / FIELD_SPAN);
}

/** 레벨 L 이 속한 사냥터 번호 (1~20) */
export function fieldOf(level: number): number {
  return Math.max(1, Math.min(fieldCount(), Math.ceil(level / FIELD_SPAN)));
}

export function skillStage(level: number): (typeof SKILL_STAGES)[number] {
  let cur = SKILL_STAGES[0]!;
  for (const stage of SKILL_STAGES) if (level >= stage.level) cur = stage;
  return cur;
}

/** 한 그룹의 스폰 수 */
export function spawnCount(level: number): number {
  return skillStage(level).spawn;
}
/** 범위 스킬 한 번이 때리는 마릿수 */
export function aoeTargets(level: number): number {
  return skillStage(level).aoe;
}
/** 동시에 나를 때리는 마릿수 */
export function meleeAttackers(level: number): number {
  return skillStage(level).melee;
}

/** 그 레벨에서 몬스터 역산에 쓰는 기준 강화 단계 */
export function enhRefStep(level: number): number {
  const f = fieldOf(level);
  let cur = ENH_REF_BY_FIELD[0]!.step;
  for (const row of ENH_REF_BY_FIELD) if (f >= row.field) cur = row.step;
  return cur;
}

/**
 * 몬스터 역산에 쓰는 **기준 장비 등급 — 30레벨에 걸쳐 보간한다.**
 *
 * 계단식으로 올리면 등급 해금 레벨에서 몬스터가 한 번에 1.7배 이상 세진다. 그러면
 * 장비를 아직 못 구한 플레이어는 레벨이 1 올랐다는 이유만으로 사냥이 막힌다 —
 * **레벨업이 벌이 되는 셈**이고, 몬스터 레벨을 안 보여주니 이유도 알 수 없다.
 * 보간하면 갈아입고 → 서서히 빡세지고 → 다음 등급에서 리셋되는 사이클이 된다.
 */
export function refGrade(level: number): number {
  const g = gradeOf(level);
  if (g <= 1) return g;
  const t = Math.min(1, (level - equipLevel(g)) / GRADE_LV_SPAN);
  return g - 1 + t;
}

/** 등급 g 아이템이 나오는 사냥터의 레벨 범위 */
export function dropLevels(grade: number): [number, number] {
  const f = dropField(grade);
  return [FIELD_SPAN * (f - 1) + 1, Math.min(FIELD_SPAN * f, MAX_LEVEL)];
}

/**
 * 그 레벨에서 현실적으로 갖고 있는 착용 상태.
 *
 * 등급1 드랍 사냥터(Lv11)에 들어가기 전에는 **시작 장비인 무기 한 자루뿐**이다.
 * 여기서 중요한 것은 무기의 세기가 아니라 **Lv1~10 구간의 몬스터 기준을 이 상태로
 * 낮춘다**는 점이다 — 등급1 풀셋을 기준으로 잡으면 게임의 첫 10레벨이 전 구간에서
 * 가장 힘들어진다.
 */
export function refWorn(level: number): Array<[EquipSlot, number, number]> {
  if (level < dropLevels(1)[0]) return [['weapon', 1, 1]];
  const grade = refGrade(level);
  const step = enhRefStep(level);
  return EQUIP_SLOTS.map((slot) => [slot, grade, step]);
}

export interface Player extends Stats {
  level: number;
  /** 평균 피해 배수 (치명타 반영) */
  crit: number;
  /** 한 번 때리는 데 걸리는 초 */
  interval: number;
}

/** 착용 상태에서 스탯 합계를 낸다 */
export function gearTotals(
  worn: Array<[EquipSlot, number, number]>
): Record<GearStat, number> {
  const total = {
    atk: 0,
    df: 0,
    hp: 0,
    crit: 0,
    critDamage: 0,
    aspd: 0,
    move: 0,
  } as Record<GearStat, number>;
  for (const [slot, grade, step] of worn) {
    const s = slotStats(slot, grade, step);
    for (const stat of Object.keys(total) as GearStat[]) total[stat] += s[stat];
  }
  return total;
}

/** 치명타까지 반영한 평균 피해 배수 */
export function critMultiplier(totals: Record<GearStat, number>): number {
  return 1 + totals.crit * totals.critDamage;
}

/** 레벨·장비·직업으로 플레이어를 짓는다. `job` 을 안 주면 배수 1.0 인 기준 직업이다 */
export function buildPlayer(
  level: number,
  worn: Array<[EquipSlot, number, number]>,
  job?: JobId
): Player {
  const b = base(level);
  const t = gearTotals(worn);
  const m = job ? JOB_MULT[job] : { atk: 1, hp: 1, df: 1, interval: PLAYER_ATTACK_INTERVAL };
  return {
    level,
    hp: b.hp * (1 + t.hp / 100) * m.hp,
    atk: b.atk * (1 + t.atk / 100) * m.atk,
    df: b.df * (1 + t.df / 100) * m.df,
    crit: critMultiplier(t),
    interval: m.interval / (1 + t.aspd),
  };
}

/** 몬스터 역산의 기준이 되는 플레이어 */
export function refPlayer(level: number): Player {
  return buildPlayer(level, refWorn(level));
}

/**
 * 피해 공식의 K — **상수로 두면 안 된다.**
 *
 * 기본 스탯은 복리로, 장비는 등급으로 커지기 때문에 K 를 선형으로 두면 후반에
 * 감소율이 68% 까지 치솟는다. "그 레벨 기준 플레이어의 감소율이 정확히 30% 가 되는
 * 값" 으로 역산하면 전 구간 30% 가 유지된다.
 *
 * K 가 **공격자 레벨**에 의존하므로 레벨 차이 페널티가 공식에 내장된다 — 높은 사냥터
 * 몬스터가 때릴 때 내 방어력 효율이 자동으로 떨어진다. 별도 보정 시스템이 필요 없다.
 */
export function K(attackerLevel: number): number {
  return (refPlayer(attackerLevel).df * (1 - TARGET_REDUCE)) / TARGET_REDUCE;
}

/**
 * 피해 = 공격력 × K / (K + 방어력). **뺄셈이 아니라 나눗셈이다.**
 *
 * `공격력 - 방어력` 식은 구간이 바뀌면 "안 박히는 벽" 이나 "종이 방어" 중 하나가
 * 되기 쉽다. 나눗셈식은 방어력이 아무리 커도 100% 에 도달하지 않고, 방어 1당
 * 효율이 부드럽게 줄어든다.
 */
export function damage(atk: number, attackerLevel: number, df: number): number {
  const k = K(attackerLevel);
  return Math.max(1, (atk * k) / (k + df));
}

export interface Monster extends Stats {
  level: number;
  role: MonsterRole;
  interval: number;
  exp: number;
}

/**
 * 몬스터를 **(레벨, 그 레벨의 기준 장비)** 에서 역산한다.
 *
 * 레벨만으로 역산하면 후반에 의미가 없다 — 같은 레벨이라도 등급 4 유저와 등급 6
 * 유저는 3배 차이다. **몬스터에게 치명타는 주지 않는다**: 몬스터 레벨을 안 보여주는
 * 설계에서 유일한 경고 신호가 "몇 대 맞았나" 인데, 치명타는 예고 없는 죽음을 만든다.
 *
 * 1마리 공격력이 아주 작아진다 — `meleeAttackers` 마리가 동시에 때린다고 보고
 * 역산하기 때문이다. 잡몹 한 마리는 위협이 아니고 **무리가 위협**인 구조다.
 */
export function monster(level: number, role: MonsterRole = 'normal'): Monster {
  const ref = refPlayer(level);
  const df = ref.df * MON_DEF_RATIO;
  const hp = TTK_HITS * (1 - TTK_MARGIN) * damage(ref.atk, level, df) * ref.crit;
  // 한 그룹을 정리하는 동안 HP 를 HP_LOSS_PER_CLEAR 만큼 잃도록
  const dpsIn = (ref.hp * HP_LOSS_PER_CLEAR) / CLEAR_TIME;
  const want = (dpsIn * MON_ATTACK_INTERVAL) / meleeAttackers(level);
  const k = K(level);
  const atk = (want * (k + ref.df)) / k;
  const r = ROLE_MULT[role];
  return {
    level,
    role,
    hp: hp * r.hp,
    atk: atk * r.atk,
    df,
    interval: MON_ATTACK_INTERVAL,
    exp: hp * r.hp * EXP_COEF,
  };
}

/** 그 레벨에서 **풀세트를 갖춘** 플레이어. 사냥 속도(킬/초)를 잴 때 쓴다 */
export function fullPlayer(level: number): Player {
  const grade = gradeOf(level);
  const step = enhRefStep(level);
  return buildPlayer(
    level,
    EQUIP_SLOTS.map((slot) => [slot, grade, step]),
  );
}

/**
 * 한 그룹을 정리하는 데 드는 시전 횟수·시간·몬스터 1마리 타수.
 *
 * **타수가 정수라는 것이 설계의 핵심**이다 — 타수가 작으면 장비 갱신이 그 정수를
 * 넘기지 못해 체감이 아예 0 이 된다. 6타로 잡아 계단을 33% → 17% 로 촘촘하게 했다.
 */
export function groupClear(pl: Player, mo: Monster): { casts: number; seconds: number; hits: number } {
  const per = damage(pl.atk, pl.level, mo.df) * pl.crit;
  const hits = Math.ceil(mo.hp / per);
  const casts = Math.ceil((spawnCount(pl.level) * hits) / aoeTargets(pl.level));
  return { casts, seconds: casts * pl.interval, hits };
}

/** 그 레벨 기준 플레이어의 사냥 속도 (마리/초). 그룹 간 대기를 포함한다 */
export function killRate(level: number): number {
  const pl = fullPlayer(level);
  const mo = monster(level);
  return spawnCount(level) / (groupClear(pl, mo).seconds + GROUP_GAP);
}

let killsBaseCache: number | null = null;

/**
 * 사냥터 1 의 레벨당 킬 수 — **목표 총 시간에서 역산한다.**
 *
 * 만렙까지 걸리는 시간을 먼저 정하고(2,880시간) 필요 킬 수를 거기서 뽑는다.
 * 어느 배수를 써도 총 시간은 맞춰지므로, 배수(`KILLS_FIELD_MULT`)는 "Lv31 시점의
 * 속도" 를 고르는 손잡이일 뿐이다.
 */
function killsBase(): number {
  if (killsBaseCache !== null) return killsBaseCache;
  let early = 0;
  const earlyTop = Math.min(EARLY_FIELDS * FIELD_SPAN, MAX_LEVEL - 1);
  for (let level = 1; level <= earlyTop; level++) {
    early += EARLY_LEVEL_MIN * 60 * EARLY_TIME_MULT ** (fieldOf(level) - 1);
  }
  let acc = 0;
  for (let level = EARLY_FIELDS * FIELD_SPAN + 1; level < MAX_LEVEL; level++) {
    acc += KILLS_FIELD_MULT ** (fieldOf(level) - EARLY_FIELDS - 1) / killRate(level);
  }
  killsBaseCache = (TARGET_HOURS * 3600 - early) / acc;
  return killsBaseCache;
}

/**
 * L → L+1 에 필요한 킬 수.
 *
 * **초반(Lv1~30)은 배수로 잡지 않고 레벨당 목표 시간을 직접 정한다** — 스킬이 모자라
 * 사냥 속도가 후반의 1/3 이라 같은 배수를 쓰면 곡선이 망가진다. Lv31 에서 10.4분으로
 * ×2.3 뛰는 단차는 **의도적으로 그 자리에 둔 것**이다: Lv30 에 3번째 스킬이 열리고
 * Lv31 에 등급2 장비가 착용 가능해지므로, 벽이 아니라 "본 게임 시작" 으로 읽힌다.
 */
export function killsPerLevel(level: number): number {
  const f = fieldOf(level);
  if (f <= EARLY_FIELDS) {
    const targetSec = EARLY_LEVEL_MIN * 60 * EARLY_TIME_MULT ** (f - 1);
    return targetSec * killRate(level);
  }
  return killsBase() * KILLS_FIELD_MULT ** (f - EARLY_FIELDS - 1);
}

/** L → L+1 에 걸리는 시간(초) */
export function levelSeconds(level: number): number {
  return killsPerLevel(level) / killRate(level);
}

/** L → L+1 에 필요한 경험치 */
export function expToNext(level: number): number {
  return killsPerLevel(level) * monster(level).exp;
}

/** 내보내기용 — 고도가 읽는 `data/balance.json` 의 알맹이 */
export function balanceTable() {
  return {
    maxLevel: MAX_LEVEL,
    fieldSpan: FIELD_SPAN,
    hpBase: HP_BASE,
    atkBase: ATK_BASE,
    defBase: DEF_BASE,
    growth: GROWTH,
    targetReduce: TARGET_REDUCE,
    monDefRatio: MON_DEF_RATIO,
    monAttackInterval: MON_ATTACK_INTERVAL,
    playerAttackInterval: PLAYER_ATTACK_INTERVAL,
    ttkHits: TTK_HITS,
    ttkMargin: TTK_MARGIN,
    clearTime: CLEAR_TIME,
    hpLossPerClear: HP_LOSS_PER_CLEAR,
    expCoef: EXP_COEF,
    jobs: JOB_IDS,
    jobMult: JOB_MULT,
    roleMult: ROLE_MULT,
    skillStages: SKILL_STAGES,
    jobAdvances: JOB_ADVANCES,
    enhRefByField: ENH_REF_BY_FIELD,
    /**
     * 레벨당 필요 경험치 표 (`expTable[L-1]` = L → L+1). 만렙 자리는 0 이다.
     *
     * **공식이 아니라 표로 내보내는 이유**는 설계 문서 2장이 적어 둔 것과 같다 —
     * 역산에 170레벨어치 사냥 속도를 다 돌려야 해서 런타임에 굴릴 값이 아니고,
     * 반올림된 표라야 "이 구간만 좀 세게" 같은 손질이 가능하다.
     */
    expTable: Array.from({ length: MAX_LEVEL }, (_, i) =>
      i + 1 >= MAX_LEVEL ? 0 : Math.round(expToNext(i + 1))
    ),
    growthTargetHours: TARGET_HOURS,
    groupGap: GROUP_GAP,
    // 장비 쪽 상수도 같이 내보낸다 — `stats.gd` 가 여기 하나만 읽으면 되게
    gear: {
      slots: EQUIP_SLOTS,
      gradeCount: GRADE_COUNT,
      gradeLvSpan: GRADE_LV_SPAN,
      sumStart: GRADE_SUM_START,
      sumEnd: GRADE_SUM_END,
      atkFactor: GEAR_ATK_FACTOR,
      defFactor: GEAR_DEF_FACTOR,
      hpFactor: GEAR_HP_FACTOR,
      critRateMax: CRIT_RATE_MAX,
      critDmgMax: CRIT_DMG_MAX,
      aspdMax: ASPD_MAX,
      moveSpdMax: MOVE_SPD_MAX,
      slotShare: SLOT_SHARE,
      enhMax: ENH_MAX,
      enhTotal: ENH_TOTAL,
      enhAccel: ENH_ACCEL,
      enhOdds: ENH_ODDS,
      dropRate: GEAR_DROP_RATE,
    },
  };
}
