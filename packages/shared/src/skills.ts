import type { JobId } from './character.ts';

/**
 * 직업별 스킬.
 *
 * 세 직업이 같은 뼈대를 공유한다 — 짧은 쿨타임의 단일기, 여러 마리를 치는 범위기,
 * 긴 쿨타임의 한 방. 그래야 직업 차이가 "숫자"가 아니라 "쓰는 방법"으로 드러난다.
 * 기사만 세 번째가 자기 회복이다 (버티는 직업이라는 정체성).
 *
 * 클라이언트는 액션바 표시와 쿨타임 그리기에, 서버는 검증에 쓴다.
 * **소모·쿨타임·대상 판정은 전부 서버가 다시 한다.**
 */

/**
 * 투사체 종류.
 *
 * 서버는 발사 시점에 명중을 확정하고, 클라이언트는 날아가는 모습을 보여준 뒤
 * **도착할 때 피해 숫자를 띄운다.** 진짜로 날아가는 투사체를 서버가 굴리면
 * 15Hz 틱에서 빗나감 판정이 지저분해지고, 맞았는데 안 맞은 것처럼 보인다.
 */
export type ProjectileKind = 'arrow' | 'fireball' | 'spark';

export const PROJECTILE_SPEED: Record<ProjectileKind, number> = {
  arrow: 34,
  fireball: 20,
  spark: 55,
};

export interface SkillDef {
  id: string;
  name: string;
  job: JobId;
  /** 재사용 대기시간 (ms) */
  cooldown: number;
  /** 닿는 거리 (m) */
  range: number;
  /**
   * 전방 부채꼴 각도(라디안). Math.PI * 2 면 자기 주위 전방향.
   */
  arc: number;
  /** 공격력 배율 */
  power: number;
  /** 최대 대상 수 */
  maxTargets: number;
  /** 자기 회복량 (최대 체력 대비 비율). 있으면 공격 대신 회복만 한다 */
  selfHeal?: number;
  /** 날아가는 무언가가 보여야 하는 스킬 */
  projectile?: ProjectileKind;
  /** 배우려면 필요한 레벨 */
  reqLevel: number;
  description: string;
}

/** 액션바에 올릴 수 있는 개수 */
export const SKILL_BAR_SIZE = 4;

/** 레벨업 한 번에 주는 스킬 포인트 */
export const SKILL_POINT_PER_LEVEL = 1;

/** 기본 공격의 투사체 (직업별) */
export const BASIC_PROJECTILE: Record<JobId, ProjectileKind | undefined> = {
  knight: undefined, // 근접
  mage: 'fireball',
  archer: 'arrow',
};

const SKILL_LIST: SkillDef[] = [
  // ---------------------------------------------------------------- 기사
  {
    id: 'heavy_strike',
    name: '강타',
    job: 'knight',
    cooldown: 6000,
    range: 2.8,
    arc: Math.PI * 0.6,
    power: 2.2,
    maxTargets: 1,
    reqLevel: 1,
    description: '한 대상을 강하게 내리친다.',
  },
  {
    id: 'whirlwind',
    name: '회전베기',
    job: 'knight',
    cooldown: 10000,
    range: 3.2,
    arc: Math.PI * 2,
    power: 1.4,
    maxTargets: 5,
    reqLevel: 6,
    description: '주위를 한 바퀴 베어 여럿을 친다.',
  },
  {
    id: 'regroup',
    name: '재정비',
    job: 'knight',
    cooldown: 25000,
    range: 0,
    arc: 0,
    power: 0,
    maxTargets: 0,
    selfHeal: 0.3,
    reqLevel: 12,
    description: '숨을 고르며 체력을 회복한다.',
  },

  // ---------------------------------------------------------------- 마법사
  {
    id: 'fireball',
    name: '화염구',
    job: 'mage',
    cooldown: 5000,
    range: 10,
    arc: Math.PI * 0.5,
    power: 2.6,
    maxTargets: 1,
    projectile: 'fireball',
    reqLevel: 1,
    description: '불덩이를 던져 큰 피해를 준다.',
  },
  {
    id: 'frost_nova',
    name: '서리 폭발',
    job: 'mage',
    cooldown: 12000,
    range: 6,
    arc: Math.PI * 2,
    power: 1.6,
    maxTargets: 6,
    reqLevel: 6,
    description: '주위를 얼려 여럿에게 피해를 준다.',
  },
  {
    id: 'arc_surge',
    name: '감전',
    job: 'mage',
    cooldown: 20000,
    range: 11,
    arc: Math.PI * 0.4,
    power: 4.2,
    maxTargets: 1,
    projectile: 'spark',
    reqLevel: 12,
    description: '한 대상에게 모든 마력을 쏟는다.',
  },

  // ---------------------------------------------------------------- 궁수
  {
    id: 'piercing_shot',
    name: '관통사격',
    job: 'archer',
    cooldown: 4000,
    range: 13,
    arc: Math.PI * 0.35,
    power: 2.0,
    maxTargets: 1,
    projectile: 'arrow',
    reqLevel: 1,
    description: '한 대상을 꿰뚫는다.',
  },
  {
    id: 'arrow_rain',
    name: '화살비',
    job: 'archer',
    cooldown: 11000,
    range: 11,
    arc: Math.PI * 0.7,
    power: 1.3,
    maxTargets: 5,
    projectile: 'arrow',
    reqLevel: 6,
    description: '넓게 화살을 퍼부어 여럿을 맞힌다.',
  },
  {
    id: 'aimed_shot',
    name: '급소 노리기',
    job: 'archer',
    cooldown: 16000,
    range: 14,
    arc: Math.PI * 0.25,
    power: 3.2,
    maxTargets: 1,
    projectile: 'arrow',
    reqLevel: 12,
    description: '숨을 멈추고 급소를 노린다.',
  },

  // ---------------------------------------------------------------- 기사 (상위)
  {
    id: 'shield_bash',
    name: '방패 밀치기',
    job: 'knight',
    cooldown: 7000,
    range: 3.0,
    arc: Math.PI * 0.5,
    power: 2.6,
    maxTargets: 1,
    reqLevel: 20,
    description: '방패로 밀어 크게 친다.',
  },
  {
    id: 'earth_shatter',
    name: '대지 가르기',
    job: 'knight',
    cooldown: 14000,
    range: 4.2,
    arc: Math.PI * 2,
    power: 2.2,
    maxTargets: 6,
    reqLevel: 35,
    description: '땅을 갈라 주위를 모두 친다.',
  },
  {
    id: 'iron_will',
    name: '강철 의지',
    job: 'knight',
    cooldown: 40000,
    range: 0,
    arc: 0,
    power: 0,
    maxTargets: 0,
    selfHeal: 0.5,
    reqLevel: 55,
    description: '숨을 고르며 크게 회복한다.',
  },
  {
    id: 'execution',
    name: '처형',
    job: 'knight',
    cooldown: 26000,
    range: 3.2,
    arc: Math.PI * 0.4,
    power: 6.5,
    maxTargets: 1,
    reqLevel: 80,
    description: '한 대상에게 모든 힘을 쏟는다.',
  },
  {
    id: 'last_stand',
    name: '최후의 방벽',
    job: 'knight',
    cooldown: 45000,
    range: 5.0,
    arc: Math.PI * 2,
    power: 4.0,
    maxTargets: 8,
    reqLevel: 120,
    description: '주위를 쓸어버린다.',
  },

  // ---------------------------------------------------------------- 마법사 (상위)
  {
    id: 'ice_lance',
    name: '얼음창',
    job: 'mage',
    cooldown: 6500,
    range: 12,
    arc: Math.PI * 0.4,
    power: 3.0,
    maxTargets: 1,
    projectile: 'spark',
    reqLevel: 20,
    description: '얼음창을 꿰뚫듯 날린다.',
  },
  {
    id: 'meteor',
    name: '유성',
    job: 'mage',
    cooldown: 16000,
    range: 13,
    arc: Math.PI * 2,
    power: 2.8,
    maxTargets: 6,
    projectile: 'fireball',
    reqLevel: 35,
    description: '불덩이를 떨어뜨려 넓게 태운다.',
  },
  {
    id: 'chain_lightning',
    name: '연쇄 번개',
    job: 'mage',
    cooldown: 13000,
    range: 12,
    arc: Math.PI * 0.8,
    power: 2.4,
    maxTargets: 4,
    projectile: 'spark',
    reqLevel: 55,
    description: '번개가 여럿을 타고 흐른다.',
  },
  {
    id: 'inferno',
    name: '지옥불',
    job: 'mage',
    cooldown: 24000,
    range: 14,
    arc: Math.PI * 2,
    power: 4.4,
    maxTargets: 8,
    projectile: 'fireball',
    reqLevel: 80,
    description: '일대를 불바다로 만든다.',
  },
  {
    id: 'void_collapse',
    name: '공허 붕괴',
    job: 'mage',
    cooldown: 38000,
    range: 15,
    arc: Math.PI * 0.3,
    power: 9.0,
    maxTargets: 1,
    projectile: 'spark',
    reqLevel: 120,
    description: '한 점을 무너뜨린다.',
  },

  // ---------------------------------------------------------------- 궁수 (상위)
  {
    id: 'twin_shot',
    name: '쌍발 사격',
    job: 'archer',
    cooldown: 5000,
    range: 13,
    arc: Math.PI * 0.35,
    power: 2.6,
    maxTargets: 2,
    projectile: 'arrow',
    reqLevel: 20,
    description: '두 발을 연달아 쏜다.',
  },
  {
    id: 'explosive_arrow',
    name: '폭발 화살',
    job: 'archer',
    cooldown: 13000,
    range: 12,
    arc: Math.PI * 2,
    power: 2.5,
    maxTargets: 6,
    projectile: 'arrow',
    reqLevel: 35,
    description: '터지는 화살로 주위를 친다.',
  },
  {
    id: 'hawk_eye',
    name: '매의 눈',
    job: 'archer',
    cooldown: 15000,
    range: 18,
    arc: Math.PI * 0.2,
    power: 4.6,
    maxTargets: 1,
    projectile: 'arrow',
    reqLevel: 55,
    description: '아주 멀리서 한 발을 꽂는다.',
  },
  {
    id: 'storm_volley',
    name: '폭풍 연사',
    job: 'archer',
    cooldown: 22000,
    range: 14,
    arc: Math.PI * 0.9,
    power: 3.0,
    maxTargets: 8,
    projectile: 'arrow',
    reqLevel: 80,
    description: '화살을 퍼부어 전방을 덮는다.',
  },
  {
    id: 'heart_seeker',
    name: '심장 사냥',
    job: 'archer',
    cooldown: 34000,
    range: 16,
    arc: Math.PI * 0.25,
    power: 8.0,
    maxTargets: 1,
    projectile: 'arrow',
    reqLevel: 120,
    description: '심장만 노려 쏜다.',
  },

  // ---------------------------------------------------------------- 최상위 (150 / 200)
  {
    id: 'cataclysm',
    name: '대지진',
    job: 'knight',
    cooldown: 55000,
    range: 6.0,
    arc: Math.PI * 2,
    power: 5.5,
    maxTargets: 10,
    reqLevel: 150,
    description: '땅을 뒤흔들어 주위를 무너뜨린다.',
  },
  {
    id: 'kings_verdict',
    name: '왕의 심판',
    job: 'knight',
    cooldown: 70000,
    range: 3.6,
    arc: Math.PI * 0.35,
    power: 12.0,
    maxTargets: 1,
    reqLevel: 200,
    description: '한 번의 심판으로 끝낸다.',
  },
  {
    id: 'starfall',
    name: '별똥별',
    job: 'mage',
    cooldown: 50000,
    range: 15,
    arc: Math.PI * 2,
    power: 6.0,
    maxTargets: 10,
    projectile: 'fireball',
    reqLevel: 150,
    description: '하늘에서 별을 떨어뜨린다.',
  },
  {
    id: 'final_flame',
    name: '종말의 불꽃',
    job: 'mage',
    cooldown: 72000,
    range: 16,
    arc: Math.PI * 2,
    power: 9.5,
    maxTargets: 12,
    projectile: 'fireball',
    reqLevel: 200,
    description: '모든 것을 태워 없앤다.',
  },
  {
    id: 'sky_volley',
    name: '천공 사격',
    job: 'archer',
    cooldown: 48000,
    range: 16,
    arc: Math.PI * 1.2,
    power: 5.2,
    maxTargets: 10,
    projectile: 'arrow',
    reqLevel: 150,
    description: '하늘을 덮도록 쏘아 올린다.',
  },
  {
    id: 'true_shot',
    name: '절대 사격',
    job: 'archer',
    cooldown: 68000,
    range: 20,
    arc: Math.PI * 0.2,
    power: 13.0,
    maxTargets: 1,
    projectile: 'arrow',
    reqLevel: 200,
    description: '빗나가지 않는 한 발.',
  },
];

export const SKILLS: Record<string, SkillDef> = Object.fromEntries(
  SKILL_LIST.map((s) => [s.id, s])
);

/**
 * 직업별 배울 수 있는 스킬 — 요구 레벨 순.
 *
 * 예전에는 이 목록이 곧 액션바였다. 이제는 **배울 수 있는 전체 목록**이고,
 * 그중 넷만 골라 액션바에 올린다. 목록에서 직접 뽑으므로 스킬을 추가하면
 * 스킬창에 자동으로 나타난다.
 */
export const JOB_SKILLS: Record<JobId, string[]> = {
  knight: skillsOf('knight'),
  mage: skillsOf('mage'),
  archer: skillsOf('archer'),
};

function skillsOf(job: JobId): string[] {
  return SKILL_LIST.filter((s) => s.job === job)
    .sort((a, b) => a.reqLevel - b.reqLevel)
    .map((s) => s.id);
}

/** 그 레벨에 배울 수 있는지 */
export function canLearn(skill: SkillDef, job: JobId, level: number): boolean {
  return skill.job === job && level >= skill.reqLevel;
}

/** 이 직업이 실제로 가진 스킬인지 — 서버가 반드시 확인해야 한다 */
export function skillForJob(job: JobId, skillId: string): SkillDef | null {
  const skill = SKILLS[skillId];
  if (!skill || skill.job !== job) return null;
  return skill;
}
