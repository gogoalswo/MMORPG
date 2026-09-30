/**
 * `balance.ts` 가 설계 문서와 같은 값을 내는지 본다.
 *
 * `gear.test.ts` 와 같은 규칙이다 — **기대값은 문서의 표를 손으로 박아 둔 것**이고,
 * 식에서 다시 계산해 비교하지 않는다. 그래야 문서와 코드가 어긋나는 순간 걸린다.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JOB_IDS } from './character.ts';
import { MONSTER_STATS } from './monsterTable.ts';
import { GEAR_DROP_MIN_GAP, GEAR_DROP_RATE, GEAR_DROP_TARGET, dropField } from './gear.ts';
import { KILL_SECONDS } from './balance.ts';
import { HP_LOSS_PER_KILL, hpLossPerKill } from './monsterAttack.ts';
import {
  CLEAR_TIME,
  DEF_BASE,
  EXP_COEF,
  EARLY_EXP_MULT,
  LATE_EXP_MULT,
  LATE_EXP_ANCHOR,
  LATE_EXP_ANCHOR_LEVEL,
  expBoost,
  expMult,
  HP_LOSS_PER_CLEAR,
  JOB_MULT,
  K,
  MAX_LEVEL,
  MON_DEF_RATIO,
  ROLE_MULT,
  TARGET_REDUCE,
  TTK_HITS,
  aoeTargets,
  balanceTable,
  base,
  buildPlayer,
  damage,
  damageTaken,
  defReduce,
  defK,
  dropLevels,
  enhRefStep,
  fieldOf,
  killsPerLevel,
  levelSeconds,
  expToNext,
  meleeAttackers,
  monster,
  refGrade,
  refPlayer,
  refWorn,
  spawnCount,
} from './balance.ts';

test('기본 스탯은 레벨당 복리 ×1.02 다', () => {
  // Lv1 HP300/공20/방20 → Lv200 맨몸 HP 5,146 / 공 1,029 / 방 1,029
  // (문서 2장은 공10/방10 — 2026-09-26 에 공 20 · 방 20 으로 올렸다)
  // 2026-09-27: Lv1 HP 100 → 300, HP 만 성장률을 따로 둬서 Lv200 은 그대로 5,146 (후반 2만 유지)
  const one = base(1);
  assert.equal(one.hp, 300);
  assert.equal(one.atk, 20);
  assert.equal(one.df, 20);

  const top = base(MAX_LEVEL);
  assert.equal(Math.round(top.hp), 5146);
  assert.equal(Math.round(top.atk), 1029);
  assert.equal(Math.round(top.df), 1029);

  // 레벨 1개는 언제나 +2% — 구간마다 다르면 "장비 비중" 의 기준이 사라진다
  for (const level of [2, 50, 120, 199]) {
    const step = base(level + 1).atk / base(level).atk;
    assert.ok(Math.abs(step - 1.02) < 1e-12, `Lv${level} 성장률 ${step}`);
  }
});

test('피해 감소율은 전 구간에서 정확히 30% 다', () => {
  // K 를 상수로 두면 후반에 68% 까지 치솟는다. 기준 플레이어에서 역산하므로 고정된다
  for (const level of [1, 10, 50, 100, 150, 200]) {
    const ref = refPlayer(level);
    const reduce = ref.df / (K(level) + ref.df);
    assert.ok(Math.abs(reduce - TARGET_REDUCE) < 1e-12, `Lv${level} 감소율 ${reduce}`);
  }
});

test('피해는 뺄셈이 아니라 나눗셈이다 — 방어력이 커져도 0 이 되지 않는다', () => {
  const huge = damage(1000, 100, 1e9);
  assert.ok(huge >= 1, '최소 피해는 1');
  // 방어력이 두 배면 피해가 절반보다는 많이 남는다 (포화하지 않는다)
  const a = damage(1000, 100, K(100));
  const b = damage(1000, 100, K(100) * 2);
  assert.ok(b > a / 2, '나눗셈식이면 절반 아래로 떨어지지 않는다');
});

test('몬스터 표가 설계 문서 6장과 같다 (사냥터 끝 레벨)', () => {
  // | 사냥터 | 잰 레벨 | 기준 등급 | 몬스터 HP | 몬스터 ATK |
  // **2026-09-23 에 HP 를 되돌렸다** (지시: "몬스터 HP 30%를 다시 올려").
  // 2026-09-21 에 장신구 배분을 고치면서 몬스터 HP 가 소리 없이 따라 내려갔던
  // 것을 장신구 변경 직전 값으로 복원했다 — 공격력·방어력은 그때도 안 바뀌었다.
  // 되돌린 폭은 레벨마다 다르다 (Lv10 +3% · Lv100 +7% · Lv200 +44%)
  // **2026-09-24 에 HP 를 공격력 축 배수만큼 올렸다** (지시: "등급간 배수를 키워" ·
  // "몬스터 HP도 같이 올린다") — 기준 플레이어 공격력(새/옛)을 곱했다. 같은 날 방어·HP 축도
  // 같은 배수가 되어("방어력이 올라감에 따라 몬스터 공격력도 올려") 공격력·방어력 열을 설계 비율만큼 올렸다
  const rows = [
    // 2026-09-25 에 HP 를 초반부터 서서히 올려 Lv200 에서 3배 (`3^((L−1)/199)`)
    // 2026-09-30 에 공격력을 "한 마리 잡는 동안 HP 10%" 로 다시 구웠다 (`monsterAttack.ts`)
    { level: 10, grade: 1.0, hp: 75, atk: 29 },
    { level: 50, grade: 1.63, hp: 308, atk: 118 },
    { level: 100, grade: 3.3, hp: 3272, atk: 419 },
    { level: 150, grade: 4.97, hp: 57924, atk: 2247 },
    { level: 200, grade: 6.63, hp: 1278546, atk: 14955 },
  ];
  for (const row of rows) {
    assert.equal(Math.round(refGrade(row.level) * 100) / 100, row.grade, `Lv${row.level} 기준 등급`);
    const m = monster(row.level);
    assert.equal(Math.round(m.hp), row.hp, `Lv${row.level} 몬스터 HP`);
    assert.equal(Math.round(m.atk), row.atk, `Lv${row.level} 몬스터 공격력`);
  }
});

test('동레벨 타수 — 6타는 목표이지 불변식이 아니다', () => {
  // 2026-09-23 지시: "동레벨 6타, 만렙 2880 시간을 무조건 적으로 지키려고 하지마.
  // 후반부에 가면 동레벨 몬스터가 6타가 넘을 수 있어."
  //
  // 그래서 `assert.equal(hits, TTK_HITS)` 를 걷었다. 6타에 **딱** 맞추라고 걸어
  // 두면 다른 것(장비 배분·옵션·스킬 계수)을 고칠 때마다 몬스터 표를 되맞추게
  // 되는데, 그게 바로 하지 말라고 한 일이다. 여기서는 **말이 되는 범위인지**만
  // 본다 — 뒤로 갈수록 늘어나는 것은 정상이고, 그게 장비를 갖추라는 압력이다.
  let previous = 0;
  const seen: number[] = [];
  for (let level = 1; level <= MAX_LEVEL; level += 7) {
    const ref = refPlayer(level);
    const m = monster(level);
    const hits = Math.ceil(m.hp / (damage(ref.atk, level, m.df) * ref.crit));
    seen.push(hits);
    // 바닥은 6 → 5 로 내렸다 (2026-09-26) — 맨몸 공격·방어를 10 → 20 으로 올렸는데 몬스터는
    // 고정 표라 따라 오르지 않아 초반(Lv1~22)이 5타가 됐다. 사용자가 "검사 기준을 새 값에 맞춤" 으로 정했다
    assert.ok(hits >= TTK_HITS - 1, `Lv${level}: ${hits}타 — 기준 장비로 설계보다 쉬우면 곡선이 무너진다`);
    // 한도는 2026-09-25 에 ×3 → ×9 로 풀었다 — 몬스터 HP 를 서서히 3배로 올려(지시: "후반부
    // 몬스터 hp를 세 배로 올려") 기준 장비 평타가 Lv197 에서 50타다. 스킬로 줄이는 것이 전제다
    // 같은 날 ×9 → ×15 로 한 번 더 풀었다 — 몬스터 방어를 피해 50% 감소로 올려(지시: "HP 그대로,
    // 더 단단하게") Lv197 평타가 82타다. 관통·스킬로 줄이는 것이 전제다
    assert.ok(hits <= TTK_HITS * 15, `Lv${level}: ${hits}타 — 기준 장비로도 너무 오래 걸린다`);
    previous = hits;
  }
  // 후반이 초반보다 적으면 성장 압력이 거꾸로 붙은 것이다
  assert.ok(previous >= seen[0]!, `초반 ${seen[0]}타 → 후반 ${previous}타 로 되레 쉬워졌다`);
});

// 아래 둘은 **고정 표가 설계에서 얼마나 벗어났는지 보는 감시**다 (2026-09-21).
// 몬스터 수치가 더는 역산이 아니라 `monsterTable.ts` 의 고정 표라, 예전처럼
// 1e-9 로 딱 맞을 수 없다(표가 소수 둘째 자리에서 끊긴다). **표를 손으로 고치면
// 그만큼 더 벌어진다** — 그건 의도된 일이므로 폭을 넉넉히 둔다. 크게 바꿀 거면
// 여기 허용 폭도 같이 고치고, 무엇을 왜 바꿨는지 표 주석에 적는다.
const DESIGN_DRIFT = 0.05; // 5%

test('몬스터 방어력이 기준 플레이어의 절반쯤이다 — 체력형이어야 타격감이 산다', () => {
  for (const level of [1, 77, 200]) {
    // 몬스터 표는 맨몸 방어 10 일 때 뽑았다. 2026-09-26 에 맨몸 방어를 20 으로 올렸는데
    // 표는 그대로 두기로 했으므로(검사 기준을 새 값에 맞춤) **표를 뽑을 때의 방어**로 환산해 본다
    const want = refPlayer(level).df * MON_DEF_RATIO * (10 / DEF_BASE);
    assert.ok(
      Math.abs(monster(level).df - want) <= want * DESIGN_DRIFT,
      `Lv${level}: ${monster(level).df} vs 설계 ${want}`
    );
  }
});

test('한 마리 잡는 동안 HP 를 10% 쯤 잃는다 ★★', () => {
  // 2026-09-30 지시: "한 마리 잡는동안 체력을 10% 정도 잃게 만들면 좋겠는데?" 그 전에는
  // "한 무리(3~6마리 동시) 정리에 HP 50%" 로 역산해서, 한 마리씩 서 있는 사냥터에서는
  // 0.4~1.8% 밖에 안 잃었다. 기준은 그 레벨 격투가(기준 장비 + 열린 패시브 전부).
  // 표는 앞 레벨보다 안 낮아지게 구웠으므로(누적 최대) 위로만 조금 넘친다
  for (let level = 1; level <= MAX_LEVEL; level++) {
    const loss = hpLossPerKill(level);
    assert.ok(
      loss >= HP_LOSS_PER_KILL * (1 - DESIGN_DRIFT) && loss <= HP_LOSS_PER_KILL * (1 + DESIGN_DRIFT),
      `Lv${level}: 한 마리에 HP ${(loss * 100).toFixed(1)}%`
    );
  }
});

test('후반 HP 는 2만 근처이고, 생존은 방어의 감소율이 맡는다 ★★', () => {
  // 2026-09-27 지시: "체력은 후반에도 2만 정도만 되고 방어력 올려서 피해감소를 해서 안 죽으면 좋겠어"
  const hp200 = refPlayer(MAX_LEVEL).hp;
  assert.ok(hp200 > 15000 && hp200 < 25000, `Lv200 기준 HP ${Math.round(hp200)}`);
  // 등급7 풀세트는 풀강(10단)이어도 무강과 HP 가 같다 — HP 는 강화를 안 탄다
  const worn = (step: number) =>
    refWorn(MAX_LEVEL).map(([slot]) => [slot, 7, step] as [typeof slot, number, number]);
  const plain = buildPlayer(MAX_LEVEL, worn(1));
  const maxed = buildPlayer(MAX_LEVEL, worn(10));
  assert.equal(maxed.hp, plain.hp, 'HP 가 강화를 탔다');
  assert.ok(maxed.df > plain.df * 3, '방어는 강화를 탄다');
  assert.ok(plain.hp < 21000, `등급7 풀세트 HP ${Math.round(plain.hp)}`);
  // 맞는 쪽 감소율: 초반 30% → 후반 90% 대, 줄지 않는다
  assert.equal(defReduce(1), TARGET_REDUCE);
  assert.ok(defReduce(MAX_LEVEL) > 0.9, `Lv200 감소율 ${defReduce(MAX_LEVEL)}`);
  for (let l = 2; l <= MAX_LEVEL; l++) {
    assert.ok(defReduce(l) >= defReduce(l - 1), `Lv${l} 감소율이 줄었다`);
  }
  // 기준 플레이어는 그 레벨 몬스터에게 정확히 defReduce 만큼 덜 맞는다
  for (const level of [50, 150, 200]) {
    const ref = refPlayer(level);
    const got = 1 - damageTaken(1e6, level, ref.df) / 1e6;
    assert.ok(Math.abs(got - defReduce(level)) < 1e-9, `Lv${level} ${got}`);
  }
  // 때리는 쪽 K 는 그대로다 — 후반 감소율을 올려도 내 공격이 깎이지 않는다
  assert.ok(defK(MAX_LEVEL) < K(MAX_LEVEL), '맞는 쪽 K 가 더 작아야 한다 (감소율이 높다)');
});

test('몬스터 표는 고정 표에서 나온다 — 장비를 고쳐도 안 움직인다 ★', () => {
  // 2026-09-21 지시: "몬스터 능력치가 자동으로 역산 되면 안돼."
  // 표에 박힌 값이 그대로 나와야 한다 (역할 배수만 얹는다)
  const [hp, atk, df] = MONSTER_STATS[99]!;
  const m = monster(100);
  assert.equal(m.hp, hp, 'Lv100 HP 가 표와 다르다');
  assert.equal(m.atk, atk);
  assert.equal(m.df, df);
  assert.equal(monster(100, 'elite').hp, hp * 3, '정예 배수만 얹는다');
  // 표 밖 레벨은 양 끝으로 자른다 — 없는 칸을 읽어 0 이 나오면 안 된다
  assert.equal(monster(0).hp, MONSTER_STATS[0]![0]);
  assert.equal(monster(999).hp, MONSTER_STATS[MONSTER_STATS.length - 1]![0]);
  assert.equal(MONSTER_STATS.length, MAX_LEVEL, '레벨마다 한 줄이어야 한다');
});

test('역할 배수 — 보스는 설계 보류라 임시값이다', () => {
  assert.deepEqual(ROLE_MULT.normal, { hp: 1, atk: 1 });
  assert.deepEqual(ROLE_MULT.elite, { hp: 3, atk: 2 });
  // 보스 공격 ×5 → ×1 (2026-09-30) — 일반 몬스터를 "한 마리당 HP 10%" 로 올리면서
  assert.deepEqual(ROLE_MULT.boss, { hp: 7, atk: 1 });
  const normal = monster(100);
  assert.equal(monster(100, 'elite').hp, normal.hp * 3);
  assert.equal(monster(100, 'boss').atk, normal.atk);
  // 역할이 달라도 방어력은 그대로다 (배수는 HP·공격력에만)
  assert.equal(monster(100, 'boss').df, normal.df);
});

test('경험치는 몬스터 HP 에 정비례한다', () => {
  // 지수 1.0 — 아래 사냥터를 손해로 만들고, 위쪽 한계는 경험치가 아니라 사망이 정한다
  // 초반(Lv1~30)은 `expMult` 배(2026-09-26 지시로 3배), 그 뒤는 기준을 `expBoost` 배로 올리고
  // `expMult` 배(2026-09-29 지시로 2배)를 얹는다
  for (const level of [1, 30, 31, 60, 200]) {
    const m = monster(level);
    assert.ok(Math.abs(m.exp - m.hp * EXP_COEF * expBoost(level) * expMult(level)) < 1e-9, `Lv${level}`);
  }
  assert.equal(expMult(30), EARLY_EXP_MULT);
  assert.equal(expBoost(30), 1);
  assert.equal(expMult(31), LATE_EXP_MULT);
  // 잿빛 황야 첫 몬스터(Lv33)의 기준 경험치가 50 — 배수까지 얹으면 100
  assert.ok(Math.abs(monster(LATE_EXP_ANCHOR_LEVEL).exp / LATE_EXP_MULT - LATE_EXP_ANCHOR) < 1e-9);
});

test('스킬 해금 단계에 그룹 크기가 묶인다', () => {
  // 문서 5장: 1 / 10 / 30 레벨에 15·8·3 → 30·14·4 → 50·20·6
  const want = [
    { level: 1, spawn: 15, aoe: 8, melee: 3 },
    { level: 9, spawn: 15, aoe: 8, melee: 3 },
    { level: 10, spawn: 30, aoe: 14, melee: 4 },
    { level: 29, spawn: 30, aoe: 14, melee: 4 },
    { level: 30, spawn: 50, aoe: 20, melee: 6 },
    { level: 200, spawn: 50, aoe: 20, melee: 6 },
  ];
  for (const row of want) {
    assert.equal(spawnCount(row.level), row.spawn, `Lv${row.level} 스폰`);
    assert.equal(aoeTargets(row.level), row.aoe, `Lv${row.level} 범위`);
    assert.equal(meleeAttackers(row.level), row.melee, `Lv${row.level} 동시 피격`);
  }
  // 50마리 × 6타 ÷ 범위 20 = 15회 시전 = 15초. 이 관계가 설계의 전제다
  assert.equal((50 * TTK_HITS) / 20, CLEAR_TIME);
});

test('기준 강화 단계는 사냥터 구간별로 4 → 7 단이다', () => {
  const want: Array<[number, number]> = [
    [1, 4],
    [6, 4],
    [7, 5],
    [12, 5],
    [13, 6],
    [17, 6],
    [18, 7],
    [20, 7],
  ];
  for (const [field, step] of want) {
    const level = field * 10; // 그 사냥터의 끝 레벨
    assert.equal(fieldOf(level), field, `Lv${level} 사냥터`);
    assert.equal(enhRefStep(level), step, `사냥터 ${field} 기준 강화`);
  }
});

test('시작 장비는 무기 한 자루뿐이고 Lv11 부터 풀세트 기준이 된다', () => {
  // 등급1 은 사냥터 2 에서야 나온다 — 그 전 구간의 몬스터를 이 상태로 낮춘다
  assert.deepEqual(dropLevels(1), [11, 20]);
  for (const level of [1, 5, 10]) {
    assert.deepEqual(refWorn(level), [['weapon', 1, 1]], `Lv${level}`);
  }
  assert.equal(refWorn(11).length, 6, 'Lv11 부터는 여섯 칸');
});

test('기준 등급 보간 — 해금 레벨에서 절벽이 생기지 않는다', () => {
  // 계단식이면 Lv120 → 121 에서 몬스터가 한 번에 1.9배 세진다
  const jump = monster(121).hp / monster(120).hp;
  assert.ok(jump < 1.25, `해금 지점에서 ×${jump.toFixed(2)} 나 뛴다`);
  // 갈아입은 직후엔 이전 등급 수준, 구간 끝에 현재 등급에 도달한다
  assert.equal(Math.round(refGrade(121) * 100) / 100, 4);
  assert.equal(Math.round(refGrade(150) * 100) / 100, 4.97);
});

test('몬스터 HP 는 레벨이 오를수록 커진다', () => {
  // 보간·강화 기준이 구간마다 바뀌므로 어딘가 뒤집히지 않는지 전수로 본다
  for (let level = 2; level <= MAX_LEVEL; level++) {
    assert.ok(monster(level).hp > monster(level - 1).hp, `Lv${level} HP 가 안 올랐다`);
  }
});

test('몬스터 공격력은 레벨을 따라 오른다', () => {
  // 예전엔 스킬이 열리는 Lv10·30 에서 **떨어졌다** — "동시에 때리는 마릿수" 로 나눠 역산해서다.
  // 2026-09-30 에 "한 마리당 HP 10%" 로 바꾸면서 그 전제가 없어져 전 구간이 오른다
  for (let level = 2; level <= MAX_LEVEL; level++) {
    assert.ok(monster(level).atk >= monster(level - 1).atk, `Lv${level} 공격력이 줄었다`);
  }
});

test('성장 곡선 — 만렙까지 2,880시간(120일)이 목표다', () => {
  // 총 시간은 **역산의 입력**이라 늘 맞는다 (레벨당 킬 수를 여기서 뽑는다).
  // 2026-09-23 지시대로 2,880 을 불변식으로 지키려 들지는 않는다 — 목표를
  // 바꾸기로 하면 `TARGET_HOURS` 한 줄을 고치면 되고, 여기가 그걸 막지 않는다
  let seconds = 0;
  for (let level = 1; level < MAX_LEVEL; level++) seconds += levelSeconds(level);
  assert.equal(Math.round((seconds / 3600) * 10) / 10, 2880);

  // 문서 7장 표의 "레벨당 킬 수" 열 (초반 경험치 3배를 곱하기 전).
  // **2026-09-28 에 한 마리씩 잡는 기준으로 바꿨다** — 무리 50마리를 15초에 정리하는 속도로
  // 세던 것을 "같은 레벨 한 마리 4초"(`KILL_SECONDS`)로. 레벨당 시간은 그대로라 킬 수만
  // 줄었다 (Lv91 19,745 → 1,551마리)
  const want: Array<[number, number]> = [
    [1, 30],
    [11, 45],
    [21, 68],
    [31, 136],
    [91, 1551],
    [141, 11776],
    [191, 89424],
  ];
  for (const [level, kills] of want) {
    assert.equal(Math.round(killsPerLevel(level)), kills, `Lv${level} 킬 수`);
  }

  // 초반 세 구간은 레벨당 2 / 3 / 4.5분 — 경험치 3배를 곱하기 전 시간이다 (실제로는 1/3)
  for (const [level, minutes] of [[1, 2], [11, 3], [21, 4.5]] as Array<[number, number]>) {
    assert.equal(Math.round((levelSeconds(level) / 60) * 10) / 10, minutes, `Lv${level} 분`);
  }
});

test('드랍률이 한 마리 4초 기준 공식과 맞는다', () => {
  // 2026-09-28 지시: "드랍 확률도 한 마리 4초 기준으로 맞춰". `gear.ts` 는 이 파일을
  // 못 불러서 값을 박아 뒀다 — 성장 곡선·`KILL_SECONDS` 를 바꾸면 여기서 걸린다
  for (let g = 1; g <= GEAR_DROP_RATE.length; g++) {
    const f = dropField(g);
    let kills = 0;
    for (let level = (f - 1) * 10 + 1; level <= Math.min(f * 10, MAX_LEVEL - 1); level++) {
      kills += killsPerLevel(level);
    }
    const want = Math.min(GEAR_DROP_TARGET[g - 1]! / kills, KILL_SECONDS / GEAR_DROP_MIN_GAP) * 100;
    const got = GEAR_DROP_RATE[g - 1]!;
    assert.ok(Math.abs(got / want - 1) < 0.001, `등급 ${g}: ${got}% 인데 공식은 ${want.toPrecision(4)}%`);
  }
});

test('경험치 표는 레벨이 오를수록 커지고 만렙에서 끝난다', () => {
  const table = balanceTable().expTable;
  assert.equal(table.length, MAX_LEVEL);
  assert.equal(table[MAX_LEVEL - 1], 0, '만렙 다음은 없다');
  for (let i = 1; i < MAX_LEVEL - 1; i++) {
    assert.ok(table[i]! > table[i - 1]!, `Lv${i + 1} 요구량이 안 올랐다`);
  }
  // 표는 공식과 같아야 한다 (반올림만 다르다)
  assert.equal(table[99], Math.round(expToNext(100)));
});

test('직업 배수가 설계 문서 2장 표와 같다', () => {
  // 기사(knight)는 설계 문서에 있지만 게임에서는 2026-09-17 에 지웠다
  assert.deepEqual(Object.keys(JOB_MULT).sort(), [...JOB_IDS].sort());
  assert.deepEqual(JOB_MULT.fighter, { atk: 1.0, hp: 1.0, df: 1.0, interval: 0.9 });
  assert.deepEqual(JOB_MULT.mage, { atk: 1.35, hp: 0.8, df: 0.75, interval: 1.0 });
  assert.deepEqual(JOB_MULT.archer, { atk: 1.35, hp: 0.9, df: 0.85, interval: 1.2 });
});

test('직업 전투력(DPS × 버티는 시간)이 서로 ±15% 안이다', () => {
  // 어느 직업을 골라도 손해가 아니어야 한다
  const level = 100;
  const m = monster(level);
  const powers = JOB_IDS.map((job) => {
    const mult = JOB_MULT[job];
    const ref = refPlayer(level);
    const atk = (ref.atk / 1) * mult.atk;
    const hp = ref.hp * mult.hp;
    const df = ref.df * mult.df;
    const dps = (damage(atk, level, m.df) * ref.crit) / (mult.interval / 1);
    const taken = (damage(m.atk, level, df) * meleeAttackers(level)) / m.interval;
    return dps * (hp / taken);
  });
  const lo = Math.min(...powers);
  const hi = Math.max(...powers);
  assert.ok(hi / lo <= 1.15, `전투력 격차 ${(hi / lo).toFixed(2)} 배`);
});
