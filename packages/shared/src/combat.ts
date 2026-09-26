import type { JobId } from './character.ts';
import { JOB_MULT, base as balanceBase, expToNext as balanceExpToNext } from './balance.ts';

/**
 * 스탯과 전투 계산.
 *
 * 클라이언트는 화면 표시(내 공격력, 예상 피해)에, 서버는 실제 판정에 쓴다.
 * **판정은 오직 서버에서만 한다** — 클라이언트가 "내가 3000 때렸다"고 보내는 걸
 * 믿으면 게임이 성립하지 않는다. 여기 있는 건 양쪽이 같은 수치를 말하기 위한 것이다.
 */

export interface Stats {
  maxHp: number;
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
 * **치명타·공격 속도에 상한이 없다.** ★ (2026-09-23 지시: "상한 없애.")
 *
 * 2026-09-16 부터 `CRIT_CAP = 0.75` · `ATTACK_SPEED_CAP = 1` 이 있었는데
 * **지시받은 값이 아니었다.** 치확이 100% 면 항상 치명타고, 공격 속도는
 * `cooldown / (1 + 공속)` 이라 아무리 높아도 0 으로 나누지 않는다 — 둘 다
 * 없애도 판정이 깨지지 않는다. 음수만 막는다(0 미만은 값이 뒤집힌다).
 *
 * **쿨감·관통만 90% 에서 멈춘다** ★ (2026-09-23 지시: "관통이랑 쿨타임 감소만
 * 상한을 90%로 설정해"). 이 둘은 100% 에 뜻이 없거나 판정이 깨진다 —
 * 쿨감 100% 는 쿨타임 0 이라 프레임마다 시전이고, 관통 100% 를 넘기면 상대
 * 방어력이 음수가 되어 `ATK × K/(K+DEF)` 가 K 근처에서 발산한다(무한 피해).
 * 수치를 더 주고 싶으면 이 상한이 아니라 옵션 최대치(`OPTION_MAX_VALUE`)를 올린다.
 */
export const COOLDOWN_CAP = 0.9;
export const PENETRATION_CAP = 0.9;

/** 공격 속도를 반영한 실제 공격 간격 (ms) */
export function effectiveCooldown(cooldown: number, attackSpeed: number): number {
  const speed = Math.max(0, attackSpeed || 0);
  return Math.max(1, Math.round(cooldown / (1 + speed)));
}

/**
 * 공격 동작이 몸을 묶는 시간 (ms).
 *
 * **휘두르는 동안에는 못 움직인다.** 안 묶으면 공격 모션을 튼 채로 그대로 달려서
 * 발은 달리는데 팔만 휘두르는 그림이 된다. 기본 공격과 스킬이 같은 값을 쓴다.
 *
 * 400ms 인 이유: 가장 짧은 공격 간격(격투가 700ms)보다 짧아야 **때리는 사이에
 * 움직일 틈**이 남는다. 간격과 같거나 길면 한 번 치기 시작한 순간부터 영영 못 움직인다.
 * `attackRootMs` 가 간격으로 한 번 더 자르는 이유도 같다 — 공격 속도 옵션이 상한까지
 * 붙으면 간격이 절반(격투가 350ms)이 되어 400ms 아래로 내려간다.
 *
 * **판정은 서버가 한다** — `ZoneRoom.handleInput` 이 이 동안 이동 입력을 버리고,
 * 자동 사냥(`stepAutoPlayer`)도 같은 동안 발을 멈춘다. 클라이언트는 `swing`/`skill`
 * 메시지에 실려 오는 값으로 예측을 같이 멈춘다 — 안 멈추면 한 발 나갔다가 보정에
 * 끌려 돌아오기를 반복해 캐릭터가 떤다.
 */
export const ATTACK_ROOT_MS = 400;

/**
 * 물약 (2026-09-26 요청: "퀵슬롯 옆에 물약 슬롯 만들고, 설정한 HP 퍼센트가 되면 물약을
 * 마시도록… 물약 쿨타임은 10초로 하고 클릭하면 직접 사용도"). 개수는 세지 않는다 —
 * 쿨타임만 막는다. 자동으로 마시는 기준(HP %)은 캐릭터마다 저장한다.
 */
export const POTION_COOLDOWN_MS = 10_000;
/** 한 병이 채우는 몫 — 최대 HP 의 이 비율 (2026-09-26 요청 "물약 한번 마시면 10% 차도록") */
export const POTION_HEAL_RATIO = 0.1;
/** 자동으로 마시는 기준의 처음 값(HP %). 0 이면 자동으로 안 마신다 (2026-09-26 요청 "초기값 70%") */
export const POTION_AUTO_DEFAULT = 70;
/** 설정 창에서 한 번 누를 때 움직이는 폭(%p)과 상한 */
export const POTION_AUTO_STEP = 10;
export const POTION_AUTO_MAX = 90;

/** 이번 공격이 몸을 묶는 시간. 다음 공격까지의 간격을 넘지 않는다 */
export function attackRootMs(cooldownMs: number): number {
  return Math.max(0, Math.min(ATTACK_ROOT_MS, Math.round(cooldownMs)));
}

/**
 * **짐승이 한 번 휘두르는 데 걸리는 시간 (ms).**
 *
 * 사람과 달리 이 값이 곧 **공격 클립을 보여 주는 창의 길이**다. 서버는 이 동안
 * 몬스터를 세워 두고(`server/combat.ts` 의 `rootedUntil`), 클라이언트는 긴 공격
 * 클립에서 딱 이만큼을 잘라 튼다(`modelRig` 의 `BEAST_ATTACK_WINDOW`). 둘이 같은
 * 값을 봐야 **동작이 끝나는 순간에 발이 떨어진다** — 어느 한쪽이 길면 휘두르며
 * 달리거나(서버가 짧을 때) 다 휘두르고도 멈춰 있는다(클립이 짧을 때).
 *
 * 650ms 인 근거는 오우거 `Attack` 클립을 FK 로 재서 나왔다: 3.73초짜리 안에
 * 할퀴기가 네 번 들어 있고, 첫 번째가 0.80~1.45s(정점 1.00s, 손 앞으로 0.39m)다.
 * 오우거 5종이 같은 클립이라 하나로 맞는다. 몬스터 공격 간격(1000·1200ms)보다
 * 짧아야 때리는 사이에 쫓아올 틈이 남으므로 `monsterRootMs` 가 한 번 더 자른다.
 */
export const MONSTER_SWING_MS = 650;

/** 짐승이 한 번 휘두르는 동안 묶이는 시간. 공격 간격을 넘지 않는다 */
export function monsterRootMs(cooldownMs: number): number {
  return Math.max(0, Math.min(MONSTER_SWING_MS, Math.round(cooldownMs)));
}

/**
 * **테스트 스위치 — 무적 모드를 쓸 수 있는가.**
 *
 * 켜져 있으면 화면 왼쪽 테스트 칸에 "무적" 단추가 나오고, 서버가 `godmode`
 * 메시지를 받아 준다. 끄면 **단추도 안 보이고 메시지도 무시된다** — 테스트 도구가
 * 실제 플레이 화면에 남아 있으면 그때부터는 버그다 (스킬 디버그 목록과 같은 규칙).
 *
 * 무적이어도 **맞은 것 자체는 그대로 방송한다** (`amount: 0`). 안 그러면 때린
 * 몬스터의 공격 동작이 `hit` 으로 돌아가는 지금 구조에서 아예 안 보여서,
 * 정작 동작을 보려고 켠 무적이 동작을 못 보게 만든다 → [combat.md]
 */
export const GODMODE_ALLOWED = true;

/** 굴림값(0~1)이 치명타인지. **상한이 없다** — 100% 를 넘기면 늘 치명타다 */
export function rollCrit(chance: number, roll: number): boolean {
  return roll < Math.max(0, chance || 0);
}

/**
 * 직업 스탯 표 — **한 줄이 한 직업이다. 직업 스탯은 여기서만 고친다.**
 *
 * 열: 체력 · 공격 · 방어 · 사거리(m) · 공격 간격(ms) · 레벨당 체력 · 레벨당 공격 · 레벨당 방어.
 * `statsFor` 는 `바탕값 + 레벨당 × (레벨 - 1)` 이다. 치명타·공격 속도는 직업으로
 * 가르지 않으므로 표에 없다 (위 `BASE_CRIT`).
 *
 * `Record<JobId, …>` 라서 직업을 `JOB_IDS` 에 넣고 여기 줄을 빠뜨리면 타입 검사가 잡는다.
 *
 * 2026-09-11 에 CSV(엑셀) + 변환 스크립트로 옮겼다가 되돌렸다. 변환 단계가 하나 끼면
 * 잊기 쉽고, 파일이 생기는 순서에 따라 감시 중인 게임 서버와 Vite 가 깨졌다.
 * 코드 안 표면 이 파일 하나만 고치면 서버와 화면이 곧바로 따라온다.
 *
 * 직업 성격:
 *  격투가 — 붙어서 가장 자주 친다. 궁수보다 단단하고 사거리가 가장 짧다. **기본 직업**
 *  마법사 — 종잇장이지만 한 대가 아프고 멀리 닿는다.
 *  궁수   — 중간. 사거리를 유지하며 꾸준히 넣는다.
 *
 * 기사는 **2026-09-17 에 지웠다** (요청: 격투가를 기본 캐릭터로). 버티는 자리가
 * 비었지만 격투가 수치는 그대로 뒀다 — 균형을 다시 잡는 건 시킨 범위 밖이다.
 */
type StatRow = readonly [
  maxHp: number,
  attack: number,
  defense: number,
  attackRange: number,
  attackCooldown: number,
  maxHpPerLevel: number,
  attackPerLevel: number,
  defensePerLevel: number,
];

export const JOB_STATS: Record<JobId, StatRow> = {
  //          체력   공격   방어   사거리   공격간격   레벨당 체력   레벨당 공격   레벨당 방어
  fighter: [  120,    12,     6,     2.2,      700,         11,          2.4,          1.1 ],
  mage:    [   80,    20,     3,     9,       1300,          6,          3.6,          0.5 ],
  archer:  [  100,    15,     5,    12,        800,          9,          2.8,          0.9 ],
};

/**
 * 맨몸 능력치 — **밸런스 설계의 복리 곡선**이다 ([balance.ts](balance.ts)).
 *
 * 2026-09-20 에 갈아끼웠다. 그 전에는 `JOB_STATS` 의 선형 증가(레벨당 +11 HP 같은
 * 고정값)였는데, 그러면 레벨당 상대 성장이 초반 +18% / 후반 +0.5% 로 40배 차이가 나
 * "장비 비중" 이라는 개념 자체가 레벨대마다 다른 뜻이 된다. 복리면 레벨 1개가
 * 언제나 총 피해 +2% 다. `JOB_STATS` 는 **사거리와 공격 간격**만 남아서 쓰인다.
 *
 * **치명타는 기본이 0 이다** — 설계에서 치확·치피는 목걸이 전담이라 장비에서만 온다.
 * 등급 1~2 에서 치명타가 거의 없어야 몬스터 HP 가 작은 초반에 타수 편차가 안 커진다.
 */
export function statsFor(job: JobId, level: number): Stats {
  const [, , , attackRange] = JOB_STATS[job];
  const b = balanceBase(level);
  const m = JOB_MULT[job];
  return {
    maxHp: Math.round(b.hp * m.hp),
    attack: Math.round(b.atk * m.atk),
    defense: Math.round(b.df * m.df),
    attackRange,
    // 설계의 직업별 공격 간격(초) → ms
    attackCooldown: Math.round(m.interval * 1000),
    crit: 0,
    critDamage: 1,
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

/**
 * 다음 레벨까지 필요한 경험치 — **만렙까지 걸리는 시간에서 역산한 값**이다
 * ([balance.ts](balance.ts) 의 성장 곡선, 2,880시간 = 24시간 × 120일).
 *
 * 그 전에는 `55 × 레벨^1.2` 였다 (Lv100 에 13,815). 사냥 속도와 무관한 식이라
 * "만렙까지 얼마나 걸리는가" 를 정할 수 없었다.
 */
export function expToNext(level: number): number {
  return Math.round(balanceExpToNext(level));
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

/**
 * 몬스터가 주는 경험치. **레벨 차이 보정을 걷었다** (2026-09-20).
 *
 * 설계에서 경험치는 **몬스터 HP 에 정비례**하므로, 약한 몬스터는 HP 가 작아 이미
 * 보상이 작다 — 따로 깎을 이유가 없다. 위쪽 한계도 경험치가 아니라 **사망**이 정한다
 * (+20레벨이면 그룹을 정리하기 전에 죽는다). 경험치의 역할은 "위로 밀어주는 것" 이
 * 아니라 **"위로 갈 때 방해하지 않는 것"** 이다 — 상향 압력은 드랍이 담당한다.
 *
 * 그 전에는 레벨 차이로 ±12%/칸 씩 깎고, 8레벨 아래면 0 이었다.
 */
export function expReward(_monsterLevel: number, _playerLevel: number, base: number): number {
  return Math.max(1, Math.round(base));
}
