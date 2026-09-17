/**
 * 몬스터 종류와 배치.
 *
 * 능력치는 서버가 판정에 쓰고, 클라이언트는 외형·이름·HP바를 그리는 데 쓴다.
 *
 * **표에서 만든다.** 존마다 두 종이고 레벨은 5 간격으로 자동 배정된다
 * (3, 8, 13, … 198). 사냥감보다 5레벨 이상 앞서면 경험치 감쇠가 급격히 붙어
 * 레벨당 필요 마릿수가 몇 배로 뛰는데, 5 간격이면 항상 4레벨 안쪽에 상대가 있다.
 *
 * 능력치는 전부 레벨에서 뽑는다. 40종을 손으로 적으면 반드시 어긋나고,
 * 어긋난 건 한참 뒤에 "이 구간만 유독 어렵다"로만 나타난다.
 */

export interface MonsterKind {
  id: string;
  name: string;
  level: number;
  maxHp: number;
  attack: number;
  defense: number;
  /** 공격이 닿는 거리 (m) */
  attackRange: number;
  attackCooldown: number;
  /** 이 거리 안에 들어오면 쫓아온다 */
  aggroRange: number;
  /** 스폰 지점에서 이만큼 멀어지면 포기하고 돌아간다 */
  leashRange: number;
  moveSpeed: number;
  expReward: number;
  /**
   * 쓸 3D 모델 이름 (public/assets/models/<이름>.glb).
   *
   * 종류마다 생김새가 달라야 사냥터를 옮긴 느낌이 난다. 색만 바꾸면
   * 20개 사냥터를 지나도 같은 짐승을 계속 잡는 기분이 든다.
   */
  look: string;
  /** 클라이언트 외형 */
  bodyColor: string;
  accentColor: string;
  scale: number;
  /** 보스는 사냥터마다 한 마리뿐이고 제작 재료를 떨군다 */
  boss?: boolean;
  /** 범위 공격. 지금은 보스만 가진다 */
  aoe?: MonsterAoe;
}

/**
 * 예고하고 터지는 범위 공격.
 *
 * **예고가 핵심이다.** 즉발이면 피할 수 없어서 그냥 "가끔 크게 아픈 평타"이고,
 * 그건 이미 있는 것과 다르지 않다. 원을 먼저 그려 주고 그 안에 있으면 맞는다.
 * 원은 시전을 시작한 자리에 고정된다 — 보스를 따라 움직이면 붙어서 때리는
 * 쪽은 피할 방법이 없다.
 */
export interface MonsterAoe {
  /** 원 반지름 (m) */
  radius: number;
  /** 표시가 뜨고 터질 때까지 (ms). 이 시간에 원 밖으로 나가면 안 맞는다 */
  windupMs: number;
  /** 다음 범위 공격까지 (ms) */
  cooldownMs: number;
  /** 보스 공격력 대비 배율 */
  power: number;
}

/**
 * 보스 공용 범위 공격 수치. 종마다 다르게 하지 않는다 —
 * 20마리가 제각각이면 어느 보스에서 몇 초 만에 피해야 하는지 외울 수가 없다.
 *
 * - `radius: 7` — 보스 사거리(2.2)보다 한참 넓어서 실제로 뛰어야 벗어난다.
 *   자기 중심 범위기는 8 이하로 둔다는 스킬 쪽 규칙과도 같은 눈금이다
 *   (더 넓으면 화면 밖까지 닿아 무슨 일인지 알 수 없다).
 * - `windupMs: 1600` — 붙어 있던 자리(2.2m)에서 원 밖(7m)까지 4.8m,
 *   `RUN_SPEED = 4.6` 으로 약 1.05초다. 1.6초면 반응할 틈이 있으면서
 *   가만히 서 있으면 반드시 맞는다.
 * - `power: 2.2` — 평타의 두 배가 조금 넘는다. 전 레벨 구간에서 격투가는
 *   최대 체력의 5~15%, 마법사는 25~35% 를 잃는다. 종잇장이 더 아픈 건 의도다.
 */
export const BOSS_AOE: MonsterAoe = {
  radius: 7,
  windupMs: 1600,
  cooldownMs: 9000,
  power: 2.2,
};

/** 존 하나에 들어가는 두 종. 배열 순서가 곧 존 순서이자 레벨대다 */
interface TierDef {
  /** [약한 쪽, 강한 쪽] */
  names: [string, string];
  bodyColor: string;
  accentColor: string;
  /** 이 사냥터 몬스터가 쓸 모델 */
  look: string;
}

/** 사냥터 순서대로 보스 이름 */
const BOSS_NAMES = [
  '들판의 우두머리', '가시왕', '협곡의 지배자', '잿빛 군주', '늪의 주인',
  '서리 여왕', '삼림의 폭군', '성터의 망령왕', '사막의 파라오', '소금 거상',
  '유황 폭군', '용암의 지배자', '빙하 군주', '뒤틀린 대목', '그림자 대공',
  '폐허의 왕', '창백한 군주', '균열의 주인', '심연의 파수왕', '종말의 군주',
];

/**
 * 보스 모델 — 덩치 큰 것들만 쓴다.
 *
 * 보스가 그 사냥터 잡몹과 같은 종이면 "커진 잡몹"으로만 보인다. 15분을
 * 기다린 값이 안 난다. 그래서 같은 모델이 걸리면 다음 것으로 넘긴다.
 */
const BOSS_LOOKS = [
  'trex',
  'triceratops',
  'stegosaurus',
  'apatosaurus',
  'parasaurolophus',
  'velociraptor',
];

function bossLookFor(index: number): string {
  const mob = TIERS[index]?.look;
  for (let i = 0; i < BOSS_LOOKS.length; i++) {
    const pick = BOSS_LOOKS[(index + i) % BOSS_LOOKS.length]!;
    if (pick !== mob) return pick;
  }
  return BOSS_LOOKS[0]!;
}

const TIERS: TierDef[] = [
  { names: ['들늑대', '숲그림자'], bodyColor: '#7b6a55', accentColor: '#4a3f33', look: 'varco_ogre1' }, // 초원 — VARCO 오우거. 나머지 존은 아직 뺀 짐승 이름이다
  { names: ['가시멧돼지', '그림자늑대'], bodyColor: '#6b5230', accentColor: '#3a2c19', look: 'bull' }, // 덤불숲
  { names: ['바위짐승', '협곡사냥꾼'], bodyColor: '#6d6a63', accentColor: '#3d3b37', look: 'stag' }, // 메마른 협곡
  { names: ['잿빛사냥개', '공포야수'], bodyColor: '#58545a', accentColor: '#2b2a2e', look: 'husky' }, // 잿빛 황야
  { names: ['늪지벌레', '수렁괴물'], bodyColor: '#4d5a3f', accentColor: '#26301f', look: 'frog' }, // 안개 늪
  { names: ['서리늑대', '얼음발톱'], bodyColor: '#9fb6c4', accentColor: '#5d707d', look: 'wolf' }, // 서리 고원
  { names: ['검은곰', '숲의 포식자'], bodyColor: '#2f2a24', accentColor: '#171310', look: 'shibainu' }, // 검은 삼림
  { names: ['폐허 수호병', '녹슨 기사'], bodyColor: '#7a6f5c', accentColor: '#413a2f', look: 'stegosaurus' }, // 무너진 성터
  { names: ['모래전갈', '사막 군주'], bodyColor: '#b58a4e', accentColor: '#6b4f28', look: 'snake' }, // 붉은 사막
  { names: ['소금거인', '백골짐승'], bodyColor: '#cfcabc', accentColor: '#8e8a7e', look: 'deer' }, // 소금 평원
  { names: ['유황도마뱀', '불꽃이빨'], bodyColor: '#c2a63a', accentColor: '#6e5c17', look: 'wasp' }, // 유황 분지
  { names: ['잿불사냥개', '용암거인'], bodyColor: '#6e3a2a', accentColor: '#391a12', look: 'rat' }, // 화산재 언덕
  { names: ['빙하 수호자', '혹한의 왕'], bodyColor: '#8fb9d4', accentColor: '#4a7188', look: 'triceratops' }, // 얼어붙은 심연
  { names: ['뒤틀린 가지', '고목괴물'], bodyColor: '#4a3b2c', accentColor: '#241c15', look: 'spider' }, // 뒤틀린 숲
  { names: ['그림자 망령', '어둠의 사냥꾼'], bodyColor: '#3a3350', accentColor: '#1c1828', look: 'horse' }, // 그림자 계곡
  { names: ['무너진 골렘', '폐허의 군주'], bodyColor: '#8a8479', accentColor: '#4b473f', look: 'parasaurolophus' }, // 폐허 도시
  { names: ['빛바랜 짐승', '창백한 거인'], bodyColor: '#c9c2b4', accentColor: '#8a8477', look: 'horse_white' }, // 빛바랜 고원
  { names: ['균열 포식자', '공간을 찢는 것'], bodyColor: '#5b3a6e', accentColor: '#2c1a37', look: 'velociraptor' }, // 균열 지대
  { names: ['심연의 감시자', '문지기'], bodyColor: '#2a3a4a', accentColor: '#131c24', look: 'apatosaurus' }, // 심연의 문턱
  { names: ['종말의 사자', '최후의 포식자'], bodyColor: '#5a1f28', accentColor: '#2c0d12', look: 'trex' }, // 종말의 대지
];

/** 티어 번호(0부터)에 들어가는 두 레벨 — 3·8 / 13·18 / 23·28 … */
export function tierLevels(index: number): [number, number] {
  const base = index * 10;
  return [base + 3, base + 8];
}

/** 보스 레벨 — 그 사냥터에서 가장 높다 */
export function bossLevel(index: number): number {
  return index * 10 + 9;
}

/** 티어 번호에서 보스 id */
export function bossIdFor(index: number): string {
  return 'boss' + String(index).padStart(2, '0');
}

/** 레벨에서 몬스터 id. 존 데이터는 이 함수로 종을 가리킨다 */
export function monsterIdFor(level: number): string {
  return 'mob' + String(level).padStart(3, '0');
}

/**
 * 레벨 하나에서 능력치를 뽑는다.
 *
 * 방어가 √L 인 게 핵심이다. 선형으로 키우면 `computeDamage` 의 감쇠식
 * `def/(def+45)` 가 100% 로 포화해서 고레벨 전투가 한없이 길어진다 —
 * 선형이었을 때 200레벨에서 근접 직업이 43대를 때려야 했다. √L 이면 200까지 10~15대다.
 */
function statsForLevel(level: number, strong: boolean) {
  return {
    maxHp: Math.round(20 * level + 40),
    attack: Math.round(1.8 * level + 4),
    defense: Math.round(2 * Math.sqrt(level)),
    expReward: Math.round(4 + 7 * level),
    attackRange: strong ? 2.2 : 1.9,
    attackCooldown: strong ? 1000 : 1200,
    aggroRange: Math.round(Math.min(16, 9 + level * 0.04) * 10) / 10,
    leashRange: Math.round(Math.min(34, 22 + level * 0.06) * 10) / 10,
    moveSpeed: strong ? 4.4 : 3.6,
    scale: Math.round(Math.min(1.7, 1 + level * 0.004) * (strong ? 1.12 : 1) * 100) / 100,
  };
}

function buildKinds(): Record<string, MonsterKind> {
  const out: Record<string, MonsterKind> = {};
  TIERS.forEach((tier, index) => {
    tierLevels(index).forEach((level, slot) => {
      const id = monsterIdFor(level);
      out[id] = {
        id,
        name: tier.names[slot]!,
        level,
        look: tier.look,
        bodyColor: tier.bodyColor,
        accentColor: tier.accentColor,
        ...statsForLevel(level, slot === 1),
      };
    });

    // 보스 — 사냥터마다 한 마리. 체력이 두껍고 크다.
    const bossId = bossIdFor(index);
    const level = bossLevel(index);
    const base = statsForLevel(level, true);
    out[bossId] = {
      id: bossId,
      name: BOSS_NAMES[index] ?? `${index}번 보스`,
      level,
      // 보스는 일반 몬스터와 다른 것이 나와야 한다. 같은 짐승이 커지기만 하면
      // 15분을 기다린 값이 안 난다.
      look: bossLookFor(index),
      bodyColor: tier.accentColor,
      accentColor: tier.bodyColor,
      boss: true,
      ...base,
      maxHp: base.maxHp * 8,
      attack: Math.round(base.attack * 1.25),
      // 도망칠 틈은 준다 — 사거리 밖으로 나가면 따라오지 않는다
      aggroRange: Math.min(18, base.aggroRange + 2),
      leashRange: Math.min(38, base.leashRange + 4),
      scale: Math.round(base.scale * 1.8 * 100) / 100,
      // 보스만 범위 공격을 한다. 일반 몬스터까지 하면 사냥터를 지나다니는 것
      // 자체가 피하기 놀이가 되어, 정작 보스를 만났을 때 특별하지 않다.
      aoe: BOSS_AOE,
    };
  });
  return out;
}

export const MONSTER_KINDS: Record<string, MonsterKind> = buildKinds();

export function getMonsterKind(id: string): MonsterKind {
  const kind = MONSTER_KINDS[id];
  if (!kind) throw new Error('알 수 없는 몬스터: ' + id);
  return kind;
}

/** 존에 몬스터를 뿌리는 규칙 */
export interface MonsterSpawnDef {
  kind: string;
  /** 무리 중심 */
  x: number;
  z: number;
  /** 이 반경 안에 흩어진다 */
  radius: number;
  count: number;
  /** 죽은 뒤 다시 나오기까지 (ms) */
  respawnMs: number;
}
