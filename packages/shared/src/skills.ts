import type { JobId } from './character.ts';

/**
 * 직업별 스킬.
 *
 * 세 직업이 같은 뼈대를 공유한다 — 짧은 쿨타임의 단일기, 여러 마리를 치는 범위기,
 * 긴 쿨타임의 한 방. 그래야 직업 차이가 "숫자"가 아니라 "쓰는 방법"으로 드러난다.
 *
 * **자기 회복 스킬은 지금 하나도 없다.** 가진 직업이 기사뿐이었는데 기사를
 * 지웠다 (2026-09-17). `selfHeal` 필드와 판정은 그대로 남아 있으니, 회복기를
 * 다시 만들면 값만 넣으면 된다.
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
  /**
   * 때리느냐와 단일기냐만 가른다 — **명수 상한이 아니다.** 범위에 들어온 놈은
   * 전부 맞는다 (2026-09-24 지시: "스킬 범위에 들어오면 모두 피격되게. 명수 제한 없애").
   * `0` 은 회복기(안 때림), `1` 은 단일기(착탄 반경 `SKILL_BLAST_MIN`),
   * `2` 이상은 범위기다. 2 이상의 숫자 크기는 판정에 쓰이지 않는다
   */
  maxTargets: number;
  /**
   * 한 번 쓰면 몇 번 때리나 (없으면 1). `power` 는 **한 대의** 배율이다.
   * 대상은 첫 대에서 한 번만 고르고, 나머지는 `hitGap` 간격으로 같은 대상에 들어간다
   */
  hits?: number;
  /** 연타 간격 (ms). `hits` 가 2 이상일 때만 쓴다 */
  hitGap?: number;
  /**
   * 누른 뒤 **이만큼 지나서** 대상을 고르고 때린다 (ms, 없으면 0 = 누르는 순간).
   * 뛰어올랐다 내려찍는 동작처럼 부딪히는 순간이 늦은 스킬에 쓴다 — 이펙트도 같은
   * 시각에 선다. 그동안 발이 묶인다(경직이 이 값보다 짧으면 이 값까지 늘린다)
   */
  delayMs?: number;
  /**
   * 시전 시간 (ms, 없으면 경직과 같다) — 스킬 동작이 끝날 때까지. **그동안 다른 스킬을
   * 못 쓴다** (2026-09-24 요청: "스킬을 시전중에 다른 스킬 사용 못 하도록 막아").
   * 동작 클립 길이(`scripts/blender/fighter_moves.py` 의 `CLIPS` 마지막 키)와 같게 둔다 —
   * 짧으면 다음 스킬이 동작을 끊고, 길면 서 있는데도 안 나간다. 둘은 같이 고친다
   */
  castMs?: number;
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

/**
 * **테스트용 스위치 — 스킬 쿨타임을 끈다.** (2026-09-12, 스킬 이펙트 테스트 중)
 *
 * 서버 판정(`handleSkill`)과 액션바가 둘 다 `skillCooldown` 을 보므로 여기 하나만 바꾸면
 * 된다. 각 스킬의 `cooldown` 데이터는 건드리지 않는다 — 테스트가 끝나면 false 로 되돌린다.
 * 켜져 있어도 서버 자동 시전은 `AUTO_SKILL_TEST_GAP` 마다 한 번만 쏜다 (ZoneRoom 참고).
 */
export const SKILL_COOLDOWN_OFF = true;

/** 쿨타임을 끈 동안에도 자동 시전이 쏘는 간격(ms) — 0 이면 매 틱(15Hz) 쏜다 */
export const AUTO_SKILL_TEST_GAP = 1000;

/** 실제로 적용할 쿨타임(ms) — 테스트 스위치가 켜져 있으면 0 */
export function skillCooldown(skill: SkillDef): number {
  return SKILL_COOLDOWN_OFF ? 0 : skill.cooldown;
}

/** 레벨업 한 번에 주는 스킬 포인트 */
export const SKILL_POINT_PER_LEVEL = 1;

/**
 * **테스트용 스위치 — 배우는 데 걸리는 제한(요구 레벨·스킬 포인트)을 끈다.** (2026-09-12)
 *
 * 레벨에 따라 열리는 건 나중에 다시 설계한다. 지금 보려는 건 이펙트와 판정인데,
 * 천붕각은 Lv.150 이라 그때까지 올리지 않으면 **한 번도 못 본다.** 포인트도 같이 끈다 —
 * 레벨당 1개라 액션바 4칸을 채우는 데만 4레벨이 필요해서, 레벨만 풀면 반만 풀린 것이다.
 *
 * 서버(`handleLearnSkill`)와 스킬창이 둘 다 `canLearn` · `skillPointCost` 를 보므로
 * 여기 하나만 바꾸면 양쪽이 같은 답을 낸다. 스킬 데이터의 `reqLevel` 은 건드리지 않는다 —
 * 스킬창에는 그대로 "Lv.150" 이라고 적혀 있고, false 로 되돌리면 곧바로 다시 잠긴다.
 *
 * **직업은 이 스위치와 무관하게 본다.** 남의 직업 스킬은 배워 봐야 쓸 수가 없다
 * (`handleSkill` 이 `skillForJob` 으로 다시 거른다).
 */
export const SKILL_UNLOCK_ALL = true;

/** 하나 배우는 데 드는 스킬 포인트 — 테스트 스위치가 켜져 있으면 0 */
export function skillPointCost(): number {
  return SKILL_UNLOCK_ALL ? 0 : 1;
}

/** 기본 공격의 투사체 (직업별) */
export const BASIC_PROJECTILE: Record<JobId, ProjectileKind | undefined> = {
  fighter: undefined, // 근접 — 맨주먹
  mage: 'fireball',
  archer: 'arrow',
};

const SKILL_LIST: SkillDef[] = [
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

  {
    // 이름은 '올려차기' 에서 바꿨지만 id 는 그대로 둔다 — 저장된 캐릭터가 이 id 로 남아 있다
    id: 'rising_kick',
    name: '할퀴기',
    job: 'fighter',
    cooldown: 6500,
    range: 3.0,
    // 앞 120° 를 **세 번** 긁는다. 처음엔 다섯 번이었다가 강화(연타 +2)가 생기며
    // 기본을 셋으로 줄였다 (2026-09-23 요청). 한 대는 0.56 그대로다 (사용자 선택) —
    // 합계 1.68, 연타 강화를 붙이면 예전 다섯 번(2.8)과 같다
    arc: (Math.PI * 2) / 3,
    power: 0.56,
    hits: 3,
    hitGap: 80,
    castMs: 1000,
    maxTargets: 4,
    reqLevel: 1,
    description: '손톱을 세워 앞 부채꼴을 세 번 긁어낸다.',
  },
  {
    id: 'sky_breaker',
    name: '천붕각',
    job: 'fighter',
    cooldown: 55000,
    range: 6.0,
    // 뛰어올랐다 내려찍는 동작의 착지 시각 (2026-09-24 요청: "점프해서 땅을 강하게 내려 찍는").
    // 동작(`fighter_moves.py` 의 SkyBreaker)이 0.72초에 땅을 찍는다 — 둘은 같이 고친다.
    // 5.4m 까지 뛰어오르므로 체공이 길다 (처음 0.42 → "지금의 5배" 로 늘렸다)
    delayMs: 720,
    castMs: 1450,
    arc: Math.PI * 2,
    power: 5.5,
    maxTargets: 10,
    reqLevel: 20,
    description: '뛰어올라 내리찍어 일대를 무너뜨린다.',
  },
  {
    /**
     * 앞쪽 한 지점에 번개가 **세 번 겹쳐** 떨어지고, 떨어진 자리에서 땅이 갈라지며
     * 파편이 튄다 (`LightningFx.bolt`). 줄기는 **시전자 뒤 위쪽에서 앞으로** 내리꽂힌다 —
     * 화면에서 캐릭터를 지나 앞쪽 땅으로 꽂히는 대각선이라 "내가 불렀다" 가 읽힌다.
     *
     * 투사체를 두지 않았다 — 번개는 날아가는 것이 보이는 게 아니라 이미 꽂혀 있다.
     * 그래서 **손이 닿는 사거리(4m)** 로 둔다: 그보다 길면 `skills.test.ts` 의
     * "한 방향으로 쏘는 스킬에는 투사체가 붙어 있다" 에 걸리고, 실제로도 아무것도
     * 안 날아가는데 멀리서 맞는 것이 된다. 번개는 **시전자가 선 자리**에 떨어지므로
     * (`LightningFx.AHEAD` 0) 판정 원의 한가운데다 — 2026-09-18 에 앞 2.8m 에서
     * 옮겼다.
     */
    id: 'thunder_fall',
    name: '낙뢰',
    job: 'fighter',
    cooldown: 12000,
    castMs: 1100,
    range: 4.0,
    // **내 주위 원**이다 (2026-09-24 요청: "낙뢰 범위가 부채꼴인데 원 범위로 바꿔").
    // 처음엔 108° 부채꼴이었다 — 번개가 발밑에 떨어지는데 뒤에 선 놈이 안 맞았다
    arc: Math.PI * 2,
    power: 4.2,
    maxTargets: 4,
    reqLevel: 30,
    description: '번개를 세 번 내리꽂아 땅을 가른다.',
  },
  {
    /**
     * 땅을 짓밟으면 발 주위 사방에서 **얼음 기둥이 고리를 그리며 솟는다**
     * (`IceFx.burst`, 2026-09-23 요청). 안쪽 고리부터 바깥으로 차례로 솟으므로
     * 전방위(`arc` 2π)이고, 기둥이 서는 가장 바깥 고리(4.3m) + 기울기만큼이
     * 사거리(5m)다 — 기둥 끝이 사거리를 넘으면 "저기까지 맞는다" 로 읽힌다.
     *
     * 낙뢰(Lv.30 · 12초 · 4.2 · 넷)와 천붕각(Lv.20 · 55초 · 5.5 · 열) 사이 —
     * 여럿을 한꺼번에 치는 광역인데 천붕각보다 자주 쓰고 약하다.
     */
    id: 'frost_pillar',
    name: '빙주각',
    job: 'fighter',
    cooldown: 20000,
    castMs: 1000,
    range: 5.0,
    arc: Math.PI * 2,
    power: 4.6,
    maxTargets: 8,
    reqLevel: 40,
    description: '땅을 짓밟아 사방에서 얼음 기둥을 솟구치게 한다.',
  },
];

export const SKILLS: Record<string, SkillDef> = Object.fromEntries(
  SKILL_LIST.map((s) => [s.id, s])
);

/**
 * **스킬 강화** (2026-09-23 요청) — 스킬마다 **둘까지** 붙는다. 스킬창에서 강화
 * 하나를 골라 **스킬 경험치북**(`SKILL_EXP_BOOKS`)으로 경험치를 넣고, `exp` 에
 * 닿으면 붙는다. 경험치북은 모든 스킬·강화에 공용이고 나중에 던전에서 떨어진다.
 * (같은 날 앞 판은 강화마다 강화서 한 장이었다 — "개별로 하지 말고 경험치북으로" 요청.)
 *
 * 둘은 **따로 붙고 같이 붙을 수도 있다.** 그래서 이펙트도 강화마다 따로 바뀐다 —
 * 기절은 번개 색만, 범위는 크기·줄기 수만 건드려서 둘이 섞여도 서로를 안 덮는다.
 *
 * `id` 는 **스킬 안에서만** 겹치지 않으면 된다. 저장에는
 * `{ 스킬 id: [강화 id, …] }` 로 남는다.
 */
export interface SkillUpgradeDef {
  id: string;
  skill: string;
  /** 창에 적는 강화 이름 */
  name: string;
  desc: string;
  /** 이만큼 경험치를 넣으면 붙는다 */
  exp: number;
  /** 맞은 몬스터를 이만큼(ms) 세운다 — 못 움직이고 못 때린다 */
  stunMs?: number;
  /** 판정 사거리 배율 (1.5 = 50% 증가). 여럿이면 곱한다 */
  rangeMul?: number;
  /** 판정 부채꼴 각을 이만큼(rad) 넓힌다. 여럿이면 더한다 */
  arcAdd?: number;
  /** 다단 히트를 이만큼 늘린다 (`hits` 에 더한다). 여럿이면 더한다 */
  extraHits?: number;
  /**
   * **남는 피해 지대** — 시전한 자리에 `zoneMs` 동안 남아 `zoneTickMs` 마다 범위 안
   * 몬스터에게 `공격력 × zonePower` 를 준다. 첫 틱은 시전 뒤 `zoneTickMs` 에 온다
   */
  zoneMs?: number;
  zoneTickMs?: number;
  zonePower?: number;
}

/** 스킬 하나에 붙는 강화 수 */
export const SKILL_UPGRADE_MAX = 2;

export const SKILL_UPGRADES: SkillUpgradeDef[] = [
  {
    id: 'stun',
    skill: 'thunder_fall',
    name: '기절',
    // 상세 창(300px)의 한 줄에 들어가야 한다 — 색이 바뀌는 것은 적지 않는다
    desc: '맞은 적 3초 기절',
    exp: 1000,
    stunMs: 3000,
  },
  {
    // 이펙트는 좌우로 두 번 더 치고 땅의 흔적이 1.5배다 (LightningFx.SIDE_STRIKES · WIDE)
    id: 'wide',
    skill: 'thunder_fall',
    name: '범위',
    desc: '범위 50% 증가',
    exp: 1000,
    rangeMul: 1.5,
  },
  {
    // 이펙트는 쓸고 가는 호가 같은 각만큼 길어진다 (SkillFx.SWEEP_ARC 140 → 180°)
    id: 'wide',
    skill: 'rising_kick',
    name: '부채꼴',
    desc: '부채꼴 각도 40° 증가',
    exp: 1000,
    arcAdd: (Math.PI * 40) / 180,
  },
  {
    // 이펙트는 긁기가 두 번 늘고 빛이 보라로 바뀐다 (SkillFx.PALETTE_PURPLE)
    id: 'combo',
    skill: 'rising_kick',
    name: '연타',
    desc: '다단 히트 2회 증가',
    exp: 1000,
    extraHits: 2,
  },
  {
    // 이펙트는 금·그을림·먼지 충격파가 1.5배 (QuakeFx.WIDE)
    id: 'wide',
    skill: 'sky_breaker',
    name: '진폭',
    // "대상 +5" 도 있었는데 명수 상한을 없애면서 뺐다 (2026-09-24)
    desc: '범위 50% 증가',
    exp: 1000,
    rangeMul: 1.5,
  },
  {
    // 이펙트는 금이 붉은 용암빛으로 3초 남고 틱마다 맥동한다 (QuakeFx.ZONE_*)
    id: 'zone',
    skill: 'sky_breaker',
    name: '균열 지대',
    // 처음엔 40% 였다 — "너무 약해" 로 100% 로 올렸다 (2026-09-24)
    desc: '3초간 0.5초마다 100% 피해',
    exp: 1000,
    zoneMs: 3000,
    zoneTickMs: 500,
    zonePower: 1.0,
  },
];

/**
 * **스킬 경험치북** — 쓰면 스킬창에서 고른 강화에 `exp` 만큼 들어간다. 세 종류
 * (사용자 선택: 하급 100 · 중급 500 · 상급 2000, 강화 하나에 1000). 가방에는 재료로
 * 들어간다 (`items.ts` 의 `MATERIALS` 가 이 표에서 만든다). **넘친 경험치는 버린다** —
 * 강화가 붙으면 그 강화에는 더 못 넣는다.
 */
export interface SkillExpBookDef {
  id: string;
  name: string;
  /** 창의 단추에 적는 짧은 이름 */
  short: string;
  exp: number;
}

export const SKILL_EXP_BOOKS: SkillExpBookDef[] = [
  { id: 'skill_book_1', name: '하급 스킬 경험치북', short: '하급', exp: 100 },
  { id: 'skill_book_2', name: '중급 스킬 경험치북', short: '중급', exp: 500 },
  { id: 'skill_book_3', name: '상급 스킬 경험치북', short: '상급', exp: 2000 },
];

/**
 * 직업별 배울 수 있는 스킬 — 요구 레벨 순.
 *
 * 예전에는 이 목록이 곧 액션바였다. 이제는 **배울 수 있는 전체 목록**이고,
 * 그중 넷만 골라 액션바에 올린다. 목록에서 직접 뽑으므로 스킬을 추가하면
 * 스킬창에 자동으로 나타난다.
 */
export const JOB_SKILLS: Record<JobId, string[]> = {
  fighter: skillsOf('fighter'),
  mage: skillsOf('mage'),
  archer: skillsOf('archer'),
};

function skillsOf(job: JobId): string[] {
  return SKILL_LIST.filter((s) => s.job === job)
    .sort((a, b) => a.reqLevel - b.reqLevel)
    .map((s) => s.id);
}

/** 그 레벨에 배울 수 있는지 — 테스트 스위치(`SKILL_UNLOCK_ALL`)가 켜져 있으면 레벨을 안 본다 */
export function canLearn(skill: SkillDef, job: JobId, level: number): boolean {
  if (skill.job !== job) return false;
  return SKILL_UNLOCK_ALL || level >= skill.reqLevel;
}

/** 이 직업이 실제로 가진 스킬인지 — 서버가 반드시 확인해야 한다 */
export function skillForJob(job: JobId, skillId: string): SkillDef | null {
  const skill = SKILLS[skillId];
  if (!skill || skill.job !== job) return null;
  return skill;
}

/**
 * 타겟을 지정하고 쓴 스킬이 **어디서 터지는지** — 원거리면 타겟 자리, 근접이면 내 몸.
 *
 * 따로 필드를 두지 않고 `projectile` 로 가른다. 이미 그게 원거리 여부를 뜻하기
 * 때문이다 (투사체 규칙: 한 방향으로 사거리 4 넘게 쏘는 스킬에는 투사체가 반드시
 * 있고, 투사체 없는 전방위기는 사거리 8 이하다). 필드를 하나 더 만들면 두 값이
 * 어긋난 스킬이 반드시 생긴다.
 */
export function isRangedSkill(skill: SkillDef): boolean {
  return !!skill.projectile;
}

/**
 * 원거리 스킬이 **타겟 자리에서** 터질 때의 판정 반경.
 *
 * 사거리를 그대로 쓰면 안 된다 — 원거리기는 사거리가 10~14 라, 타겟을 중심으로
 * 그만큼 잡으면 지름 20m 가 넘어 화면(세로 21유닛) 전체가 범위가 된다.
 * 그래서 사거리에 비례하되 상한을 둔다. 단일기(`maxTargets <= 1`)는 타겟 하나만
 * 맞아야 하므로 몸 하나 크기(`SKILL_BLAST_MIN`)만 본다.
 */
export const SKILL_BLAST_RATIO = 0.35;
export const SKILL_BLAST_MAX = 6;
export const SKILL_BLAST_MIN = 0.6;

export function blastRadius(skill: SkillDef): number {
  if (skill.maxTargets <= 1) return SKILL_BLAST_MIN;
  return Math.min(SKILL_BLAST_MAX, Math.max(SKILL_BLAST_MIN, skill.range * SKILL_BLAST_RATIO));
}
