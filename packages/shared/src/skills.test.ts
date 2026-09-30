import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  JOB_SKILLS,
  PASSIVES,
  type PassiveDef,
  passiveRankOpen,
  PROJECTILE_SPEED,
  SKILLS,
  SKILL_BAR_SIZE,
  SKILL_UNLOCK_ALL,
  SKILL_UPGRADES,
  SKILL_UPGRADE_MAX,
  SKILL_UPGRADE_EXP_BY_TIER,
  canLearn,
  skillForJob,
} from './skills.ts';
import { JOB_IDS } from './character.ts';
import { MAX_LEVEL, effectiveCooldown, statsFor } from './combat.ts';

/**
 * 스킬 데이터 검사.
 *
 * 스킬은 이제 요구 레벨·포인트·장착 제한이 얽혀 있어서, 하나를 잘못 적으면
 * "그 구간만 배울 게 없다"거나 "만렙인데 못 쓰는 스킬이 있다"로만 나타난다.
 * 눈으로 30개를 훑는 대신 규칙으로 잡는다.
 */

const all = Object.values(SKILLS);
/** 보이는 스킬이 있는 직업 — 격투가는 2026-09-29 부터 평타만 쓴다 */
const SKILLED_JOBS = JOB_IDS.filter((job) => JOB_SKILLS[job].length > 0);

test('id 와 키가 일치한다', () => {
  for (const [key, skill] of Object.entries(SKILLS)) {
    assert.equal(key, skill.id, `${key}: id 가 ${skill.id} 이다`);
  }
});

test('모든 스킬이 실재하는 직업에 속한다', () => {
  for (const skill of all) {
    assert.ok(JOB_IDS.includes(skill.job), `${skill.id}: 직업이 ${skill.job}`);
  }
});

/**
 * **직업끼리 개수·요구 레벨을 맞추던 검사는 뺐다** (2026-09-12).
 *
 * 원래는 "한 직업만 적으면 그 직업이 손해다", "배우는 시점이 다르면 그 자체로 강약이
 * 갈린다" 는 이유로 넷을 똑같이 맞췄다. 그런데 그 규칙 때문에 **격투가에 스킬 하나를
 * 더하려면 나머지 세 직업 몫까지 같이 설계해야 했다.** 지금은 직업마다 콘텐츠가
 * 따로 붙는 단계라, 균형을 맞추느라 만들고 싶은 걸 못 만드는 쪽이 더 손해다.
 *
 * 남아 있는 것: 직업마다 Lv.1 스킬이 하나씩 있고(첫 스킬), 요구 레벨이 오름차순이며,
 * Lv.20 까지 액션바 칸 수(4개)만큼은 열린다. **직업별 개수만 자유다.**
 */
test('직업마다 액션바를 채울 만큼은 갖는다', () => {
  /**
   * 원래는 "칸 수보다 **많아야** 고르는 의미가 있다" 였다. 2026-09-12 격투가를
   * 이펙트가 붙은 넷만 남기고 정리하면서 딱 4개가 됐다 — 고를 여지는 없지만 빈 칸도
   * 없다. 스킬을 더 만들면 자연스럽게 다시 고르게 된다.
   * 격투가는 2026-09-29 부터 보이는 스킬이 없다 (아래 "격투가는 평타로만 싸운다") — 뺀다.
   */
  for (const job of SKILLED_JOBS) {
    assert.ok(
      JOB_SKILLS[job].length >= SKILL_BAR_SIZE,
      `${job}: ${JOB_SKILLS[job].length}개라 액션바(${SKILL_BAR_SIZE}칸)에 빈 칸이 남는다`
    );
  }
});

test('요구 레벨이 오름차순이고 만렙 안에 있다', () => {
  for (const job of JOB_IDS) {
    let previous = 0;
    for (const id of JOB_SKILLS[job]) {
      const skill = SKILLS[id]!;
      assert.ok(skill.reqLevel >= previous, `${id}: 순서가 뒤집혔다`);
      assert.ok(skill.reqLevel >= 1, `${id}: 요구 레벨이 ${skill.reqLevel}`);
      assert.ok(skill.reqLevel <= MAX_LEVEL, `${id}: 만렙(${MAX_LEVEL})을 넘는다`);
      previous = skill.reqLevel;
    }
  }
});

test('시작하자마자 배울 수 있는 스킬이 직업마다 하나씩 있다', () => {
  // 없으면 1레벨이 기본 공격만 갖고 시작한다
  for (const job of SKILLED_JOBS) {
    const first = SKILLS[JOB_SKILLS[job][0]!]!;
    assert.equal(first.reqLevel, 1, `${job}: 첫 스킬이 Lv.${first.reqLevel}`);
  }
});

test('수치가 말이 되는 범위에 있다', () => {
  for (const skill of all) {
    assert.ok(skill.cooldown >= 1000, `${skill.id}: 쿨타임이 ${skill.cooldown}ms`);
    assert.ok(skill.arc >= 0 && skill.arc <= Math.PI * 2, `${skill.id}: 각이 ${skill.arc}`);
    assert.ok(skill.name.length > 0 && skill.description.length > 0, `${skill.id}: 이름·설명이 비었다`);

    if (skill.selfHeal) {
      // 회복기는 때리지 않는다 — 둘 다 하면 판정 경로가 갈린다
      assert.equal(skill.power, 0, `${skill.id}: 회복기인데 공격 배율이 있다`);
      assert.equal(skill.maxTargets, 0, `${skill.id}: 회복기인데 대상이 있다`);
      assert.ok(skill.selfHeal > 0 && skill.selfHeal <= 1, `${skill.id}: 회복량이 ${skill.selfHeal}`);
      continue;
    }

    assert.ok(skill.power > 0, `${skill.id}: 배율이 ${skill.power}`);
    assert.ok(skill.maxTargets >= 1, `${skill.id}: 대상이 ${skill.maxTargets}`);
    assert.ok(skill.range > 0, `${skill.id}: 사거리가 ${skill.range}`);
  }
});

test('레벨이 오를수록 세진다', () => {
  // 공격기끼리만 비교한다 — 회복기는 배율이 0 이라 줄에 끼면 안 된다
  for (const job of SKILLED_JOBS) {
    const attacks = JOB_SKILLS[job]
      .map((id) => SKILLS[id]!)
      .filter((s) => !s.selfHeal);
    const best = attacks[attacks.length - 1]!;
    const first = attacks[0]!;
    assert.ok(best.power > first.power, `${job}: 마지막 스킬이 첫 스킬보다 약하다`);
    assert.ok(best.cooldown >= first.cooldown, `${job}: 마지막 스킬이 더 자주 나간다`);
  }
});

test('투사체는 속도가 정의된 종류만 쓴다', () => {
  for (const skill of all) {
    if (!skill.projectile) continue;
    assert.ok(
      PROJECTILE_SPEED[skill.projectile] > 0,
      `${skill.id}: '${skill.projectile}' 속도가 없다`
    );
  }
});

// 투사체는 없지만 **이펙트가 사거리 끝까지 눈에 보이게 날아가는** 스킬 — 규칙의 뜻(멀리서
// 아무것도 안 날아가는데 맞는 것)에 안 걸린다. 파천장은 2026-09-29 요청으로 6m 가 됐다.
// 무적파쇄권은 주먹 앞에서 터지는 가시가 5.2m 까지 눈에 보이게 뻗는다 (같은 날 "이펙트 크기를 1.5배")
const FLYING_FX = ['ki_burst', 'crush_fist'];

test('한 방향으로 쏘는 스킬에는 투사체가 붙어 있다', () => {
  // 안 붙으면 멀리서 쏘는데 아무것도 안 날아가 즉시 맞는 것처럼 보인다.
  // 자기 주위로 터지는 기술(전방위)은 날아갈 게 없으므로 예외다 — 서리 폭발 같은 것.
  for (const skill of all) {
    if (skill.selfHeal) continue;
    if (FLYING_FX.includes(skill.id)) continue;
    if (skill.arc >= Math.PI * 2) continue;
    if (skill.range <= 4) continue; // 근접은 손이 닿는다
    assert.ok(skill.projectile, `${skill.id}: 멀리 쏘는데 투사체가 없다`);
  }
});

test('자기 주위로 터지는 기술은 사거리가 짧다', () => {
  // 전방위인데 사거리가 길면 화면 밖의 것까지 맞아 무슨 일인지 알 수 없다
  for (const skill of all) {
    if (skill.arc < Math.PI * 2 || skill.selfHeal) continue;
    if (skill.projectile) continue; // 날려서 터뜨리는 건 멀어도 된다
    assert.ok(skill.range <= 8, `${skill.id}: 전방위인데 사거리가 ${skill.range}`);
  }
});

test('격투가는 평타로만 싸운다 — 보이는 스킬이 없다', () => {
  // 2026-09-29 요청: "스킬을 다 숨김처리 하고, 공속을 성장시켜서 빠르게 때리는 스타일로".
  // 판정·이펙트 데이터는 남아 있어서 `hidden` 만 지우면 돌아온다
  assert.deepEqual(JOB_SKILLS.fighter, []);
  assert.ok(Object.values(SKILLS).some((s) => s.job === 'fighter' && s.hidden));
});

test('다른 직업 스킬은 걸러진다', () => {
  // 숨긴 스킬도 판정 표에는 있다 — 걸러지는지는 그대로 본다
  const fighterSkill = 'rising_kick';
  assert.ok(skillForJob('fighter', fighterSkill));
  assert.equal(skillForJob('mage', fighterSkill), null);
  assert.equal(skillForJob('fighter', '없는스킬'), null);
});

test('배우기 판정이 직업과 레벨을 함께 본다', () => {
  const late = SKILLS[JOB_SKILLS.archer[JOB_SKILLS.archer.length - 1]!]!;
  assert.equal(canLearn(late, 'archer', late.reqLevel), true);
  // 테스트 스위치가 켜져 있는 동안은 레벨을 안 본다 — 그게 스위치의 목적이다 (skills.ts)
  if (!SKILL_UNLOCK_ALL) {
    assert.equal(canLearn(late, 'archer', late.reqLevel - 1), false, '레벨이 모자라면 못 배운다');
  }
  assert.equal(canLearn(late, 'fighter', MAX_LEVEL), false, '다른 직업은 못 배운다');
});

test('만렙까지 올리면 모든 스킬을 배울 수 있다', () => {
  // 만렙에도 못 배우는 스킬이 남으면 그건 만들어놓고 못 쓰는 콘텐츠다
  for (const job of JOB_IDS) {
    for (const id of JOB_SKILLS[job]) {
      assert.ok(canLearn(SKILLS[id]!, job, MAX_LEVEL), `${id}: 만렙에도 못 배운다`);
    }
  }
});

test('스킬 강화는 있는 스킬에 붙고, 스킬마다 둘까지이며, 필요 경험치가 전직 단계 표를 따른다', () => {
  const perSkill: Record<string, string[]> = {};
  for (const upgrade of SKILL_UPGRADES) {
    assert.ok(SKILLS[upgrade.skill], `${upgrade.skill} 이 없다`);
    assert.ok(upgrade.exp > 0, `${upgrade.skill} ${upgrade.id} 의 필요 경험치가 없다`);
    assert.equal(
      upgrade.exp,
      SKILL_UPGRADE_EXP_BY_TIER[SKILLS[upgrade.skill].tier ?? 0],
      `${upgrade.skill} ${upgrade.id} 의 필요 경험치가 전직 단계 표와 다르다`
    );
    const ids = (perSkill[upgrade.skill] ??= []);
    assert.ok(!ids.includes(upgrade.id), `${upgrade.skill} 의 ${upgrade.id} 가 겹친다`);
    ids.push(upgrade.id);
  }
  for (const [skill, ids] of Object.entries(perSkill)) {
    assert.ok(ids.length <= SKILL_UPGRADE_MAX, `${skill} 강화가 ${ids.length}개`);
  }
});

test('질풍각 — Lv.200 에 격투가가 초당 10번 때린다', () => {
  // 2026-09-30 요청: "200레벨 기준 초당 10타 때릴 수 있게" (처음 09-29 엔 초당 8번). 공속은 이 패시브에서만 온다
  const gale = PASSIVES.find((p) => p.id === 'gale_kicks')!;
  assert.ok(gale, '질풍각이 없다');
  assert.equal(passiveRankOpen(gale, 9), 0, 'Lv.9 는 아직 0단계');
  assert.equal(passiveRankOpen(gale, 10), 1, 'Lv.10 에 1단계');
  assert.equal(passiveRankOpen(gale, MAX_LEVEL), gale.maxRank, '만렙에 끝 단계');
  const base = statsFor('fighter', MAX_LEVEL).attackCooldown;
  const interval = effectiveCooldown(base, gale.perRank * gale.maxRank);
  assert.equal(interval, 100, `만렙 간격 ${interval}ms`);
});

test('레벨 도달 패시브 — 그 레벨에 한 번만 열린다', () => {
  // 2026-09-30 요청: 10 공격력 30% · 30 이속 20% · 50 치확 10% · 70 치피 20% · 100 관통 10% ·
  // 150 치피 30% · 200 치피 50% → 같은 날 150 을 치확 20% 로 바꿨다 ("치명타 확률 20% 증가로 변경해")
  // 같은 날 철각 30% → 10% 로 내리고 40 · 80 · 120 에 공격력 20 · 40 · 80% 를 이었다
  const want: [number, PassiveDef['stat'], number][] = [
    [10, 'attack', 0.1], [40, 'attack', 0.2], [80, 'attack', 0.4], [120, 'attack', 0.8],
    [30, 'moveSpeed', 0.2], [50, 'crit', 0.1], [70, 'critDamage', 0.2],
    [100, 'penetration', 0.1], [150, 'crit', 0.2], [200, 'critDamage', 0.5],
  ];
  const got = PASSIVES.filter((p) => p.maxRank === 1);
  assert.deepEqual(got.map((p) => [p.everyLevels, p.stat, p.perRank]), want);
  for (const p of got) {
    assert.equal(p.job, 'fighter');
    assert.equal(passiveRankOpen(p, p.everyLevels - 1), 0, `${p.name} 이 Lv.${p.everyLevels - 1} 에 열렸다`);
    assert.equal(passiveRankOpen(p, p.everyLevels), 1, `${p.name} 이 Lv.${p.everyLevels} 에 안 열렸다`);
    assert.equal(passiveRankOpen(p, MAX_LEVEL), 1);
  }
  assert.equal(new Set(PASSIVES.map((p) => p.id)).size, PASSIVES.length, '패시브 id 가 겹친다');
});

test('레벨 패시브 이름은 계열 첫 칸 이름 + "N단" — "철각 1단" → "철각 4단"', () => {
  const byId = new Map(PASSIVES.map((p) => [p.id, p]));
  for (const p of PASSIVES.filter((each) => each.maxRank === 1)) {
    let root = p;
    let step = 1;
    while (root.requires) {
      root = byId.get(root.requires)!;
      step += 1;
    }
    const base = root.name.replace(/ 1단$/, '');
    assert.equal(p.name, `${base} ${step}단`, `${p.id} 이름`);
  }
});

test('뒷 패시브는 같은 스탯의 앞 패시브에 잇는다 — 공격력 10 → 40 → 80 → 120 · 치확 50 → 150 · 치피 70 → 200', () => {
  const byId = new Map(PASSIVES.map((p) => [p.id, p]));
  const chains = PASSIVES.filter((p) => p.requires).map((p) => [byId.get(p.requires!)?.everyLevels, p.everyLevels, p.stat]);
  assert.deepEqual(chains, [
    [10, 40, 'attack'], [40, 80, 'attack'], [80, 120, 'attack'], [50, 150, 'crit'], [70, 200, 'critDamage'],
  ]);
  for (const p of PASSIVES.filter((each) => each.requires)) {
    const need = byId.get(p.requires!)!;
    assert.equal(need.stat, p.stat, `${p.name} 이 다른 스탯(${need.name})에 이어졌다`);
    assert.ok(need.everyLevels < p.everyLevels, `${p.name} 의 앞 단계가 더 늦게 열린다`);
  }
});
