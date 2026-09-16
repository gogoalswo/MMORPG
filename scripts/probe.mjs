/**
 * 헤드리스 검증 클라이언트.
 *
 * 화면을 띄우지 않고 서버에 그냥 접속해서, 상태와 결과를 **글로** 찍는다.
 * 스크린샷으로 확인하면 한 장에 토큰이 천 단위로 나가고, 브라우저가 가려지면
 * requestAnimationFrame 이 멈춰서 화면이 낡은 채로 굳는다 — 그 상태로 클릭하면
 * 엉뚱한 자리를 누른다. 실제로 그것 때문에 같은 검증을 여섯 번 반복한 적이 있다.
 *
 * 찍은 내용은 항상 logs/ 아래 파일로도 남는다. 나중에 "그때 뭐가 나왔더라"를
 * 다시 굴려보지 않아도 되게.
 *
 *   node scripts/probe.mjs state
 *   node scripts/probe.mjs fight --rounds 4 --zone meadow
 *   node scripts/probe.mjs send npcBuy w_archer_06
 *   node scripts/probe.mjs send skill rising_kick --times 3 --gap 300 --job fighter  # 쿨타임 확인
 *   node scripts/probe.mjs watch --seconds 20
 *
 * 옵션:
 *   --zone <id>        기본 village
 *   --token <t>        없으면 게스트로 접속한다 (새 계정이 만들어진다)
 *   --character <id>   기존 캐릭터로 들어간다
 *   --name <이름> --job <knight|mage|archer|fighter>
 *   --server <url>     기본 ws://localhost:2567
 *   --seconds <n> / --rounds <n>
 *   --log <path>       기본 logs/probe-<시각>.log
 *   --quiet            콘솔에는 안 찍고 파일에만 남긴다
 */
import { Client } from '@colyseus/sdk';
import { MONSTER_KINDS, monsterRadius } from '../packages/shared/src/index.ts';
import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

// ---------------------------------------------------------------- 인자

const argv = process.argv.slice(2);
const command = argv[0] && !argv[0].startsWith('--') ? argv[0] : 'state';
const positional = argv.slice(1).filter((a) => !a.startsWith('--'));

function opt(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
}
const flag = (name) => argv.includes(`--${name}`);

const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const logPath = opt('log', join('logs', `probe-${command}-${stamp}.log`));
mkdirSync(dirname(logPath), { recursive: true });

const lines = [];
function say(...parts) {
  const text = parts.join(' ');
  lines.push(text);
  if (!flag('quiet')) console.log(text);
  appendFileSync(logPath, text + '\n');
}

// ---------------------------------------------------------------- 접속

const serverUrl = opt('server', 'ws://localhost:2567');
const zoneId = opt('zone', 'village');

say(`# probe ${command} — ${new Date().toISOString()}`);
say(`# ${serverUrl} zone=${zoneId} log=${logPath}`);

let room;
try {
  room = await new Client(serverUrl).joinOrCreate('zone', {
    zoneId,
    name: opt('name', '검증'),
    job: opt('job', 'archer'),
    ...(opt('token') ? { token: opt('token') } : {}),
    ...(opt('character') ? { characterId: opt('character') } : {}),
  });
} catch (err) {
  say(`접속 실패: ${err?.message ?? err}`);
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
const me = () => room.state?.players?.get(room.sessionId);

let inventory = null;
let hits = 0;
let crits = 0;
let damage = 0;

/**
 * 캐릭터가 없는 계정(게스트 첫 접속)은 월드에 바로 안 들어간다.
 * 사람이 하는 것과 같은 순서로 만들고 고른다 — 서버에 예외 경로를 뚫지 않는다.
 */
room.onMessage('needsCharacter', (m) => {
  // `??` 가 아니라 `||` 다 — 서버가 빈 이름을 제안하면 그대로 보내서 생성이 거절된다.
  // 기본 이름에 꼬리를 붙이는 이유: 매번 게스트 계정이 새로 생기는데 이름은 서버
  // 전체에서 하나뿐이라, 고정 이름이면 두 번째 실행부터 "이미 사용 중"으로 막힌다.
  const name = opt('name', '') || m.suggestedName || `검증${Math.random().toString(36).slice(2, 6)}`;
  say(`[생성] ${name} (${opt('job', 'archer')})`);
  room.send('createCharacter', { name, job: opt('job', 'archer') });
});
room.onMessage('createResult', (r) => {
  if (!r.ok) say(`[생성 실패] ${r.reason ?? ''}`);
});
room.onMessage('characterList', (list) => {
  const first = list.characters?.[0];
  if (first && !opt('character')) {
    say(`[선택] ${first.name}`);
    room.send('selectCharacter', { id: first.id });
  }
});

room.onMessage('inventory', (m) => { inventory = m; });
room.onMessage('notice', (m) => say(`[알림] ${m.text}`));
room.onMessage('reward', (m) => say(`[보상] ${m.name} +${m.exp} exp`));
room.onMessage('loot', (m) => say(`[전리품] ${m.gold}G ${(m.items ?? []).join(', ')}`));
room.onMessage('levelUp', (m) => say(`[레벨업] ${m.level}`));
let skillBar = [];
room.onMessage('skills', (m) => {
  skillBar = m.bar ?? [];
  say(`[스킬] 배운 것 ${m.learned?.length ?? 0}개 · 액션바 [${skillBar.join(', ')}] · 포인트 ${m.points ?? 0}`);
});
room.onMessage('target', (m) => say(`[대상] ${m.id ?? '해제'}`));
room.onMessage('aoe', (m) =>
  say(`[범위예고] ${m.name} 반경 ${m.radius}m @ (${m.x.toFixed(1)}, ${m.z.toFixed(1)}) ${m.delayMs}ms 뒤`));
room.onMessage('enhanceResult', (m) => say(`[강화] ${m.result} → +${m.level}`));
room.onMessage('npc', (m) => say(`[NPC] ${m.role} 재고=${JSON.stringify(m.stock)}`));
// 스킬 사용과 스킬 명중 — 스킬 이펙트는 명중(hit)에 skillId 가 실려 와야 뜬다
const skillHits = {};
room.onMessage('skill', (m) => { if (m.id === room.sessionId) say(`[스킬 사용] ${m.skillId}`); });
/** 몬스터가 나를 때린 시각과 그놈 (몬스터 경직 확인에 쓴다) */
let lastHitAt = 0;
let lastHitBy = null;
/** 내가 맞은 횟수와, 그중 피해 0(무적)으로 온 횟수 */
let hitsOnMe = 0;
let zeroHits = 0;
/** 서버가 알려준 무적 상태 (null = 아직 안 받았다) */
let godmodeOn = null;
room.onMessage('godmode', (m) => { godmodeOn = !!m.on; });
room.onMessage('hit', (m) => {
  if (m.targetKind === 'player' && m.targetId === room.sessionId && !m.heal) {
    lastHitAt = Date.now();
    lastHitBy = m.sourceId;
    hitsOnMe++;
    if (m.amount === 0) zeroHits++;
  }
  if (m.targetKind !== 'monster') return;
  if (m.skillId) skillHits[m.skillId] = (skillHits[m.skillId] ?? 0) + 1;
  hits++;
  damage += m.amount;
  if (m.crit) crits++;
  if (m.killed) say(`[처치] ${m.targetId.slice(0, 8)} 마지막 ${m.amount}${m.crit ? ' (치명타)' : ''}`);
});

// 정지 중에도 보내야 서버가 마지막 순번을 확인해 준다
let seq = 0;
const beat = setInterval(() => room.send('input', { seq: ++seq, dx: 0, dz: 0, dt: 0.066 }), 66);

// 생성·선택을 거치면 몇 초 걸린다. 고정 대기 대신 들어올 때까지 본다.
for (let i = 0; i < 40 && !me(); i++) await sleep(250);
if (!me()) {
  say('내 캐릭터가 상태에 안 들어왔다 — 생성/선택 단계에서 멈춘 듯하다');
  await finish(1);
}
await sleep(600); // 인벤토리·스킬 메시지가 뒤따라온다

// ---------------------------------------------------------------- 출력 도우미

const stackLine = (s) => {
  const opts = (s.options ?? []).map((o) => `${o.kind}+${o.value}`).join(', ');
  return `${s.id} ${s.grade}등급 +${s.enhance ?? 0}${opts ? ` [${opts}]` : ''}`;
};

function dumpSelf() {
  const p = me();
  say(`나: ${p.name} ${p.job} Lv.${p.level} hp ${p.hp}/${p.maxHp}` +
      ` (${p.x.toFixed(1)}, ${p.z.toFixed(1)}) auto=${p.auto ?? false}`);
  // 남에게 보이는 장비 — 이게 비어 있으면 다른 사람 화면에서 빈손으로 보인다
  say(`  겉모습: 무기=${p.weapon || '-'} 보조=${p.offhand || '-'} 투구=${p.helmet || '-'}` +
      ` 갑옷=${p.armor || '-'} 신발=${p.boots || '-'}`);
}

function dumpInventory() {
  if (!inventory) return say('가방 정보가 아직 안 왔다');
  say(`골드 ${inventory.gold}`);
  say(`가방 ${inventory.items.length}칸`);
  for (const s of inventory.items) say(`  ${stackLine(s)}`);
  say('장비');
  for (const [slot, s] of Object.entries(inventory.equipment ?? {})) say(`  ${slot.padEnd(9)} ${stackLine(s)}`);
}

/** 눈에 보이는 다른 플레이어들 — 남의 장비가 실제로 내려오는지 본다 */
function dumpOthers() {
  const me2 = me();
  const list = [];
  room.state.players?.forEach((p, id) => {
    if (id === room.sessionId) return;
    list.push(
      `  ${p.name} ${p.job} ${dist(me2, p).toFixed(1)}m 무기=${p.weapon || '-'} 보조=${p.offhand || '-'}` +
        ` 투구=${p.helmet || '-'} 갑옷=${p.armor || '-'} 신발=${p.boots || '-'}`
    );
  });
  say(`다른 플레이어 ${list.length}명`);
  for (const line of list) say(line);
}

function dumpMonsters(limit = 8) {
  const p = me();
  const list = [];
  // 마을처럼 몬스터가 하나도 없는 존에서는 맵 자체가 안 내려온다
  room.state.monsters?.forEach((m) => list.push(m));
  list.sort((a, b) => dist(p, a) - dist(p, b));
  say(`주변 몬스터 ${list.length}마리`);
  for (const m of list.slice(0, limit)) {
    say(`  ${m.kind.padEnd(8)} hp ${m.hp}/${m.maxHp} ${dist(p, m).toFixed(1)}m ${m.state}`);
  }
}

/**
 * 몬스터끼리 겹쳐 있는지 — **눈으로 보지 않고 재는 방법**이다.
 * 두 마리 사이 거리에서 두 몸 반지름을 빼서, 음수면 그만큼 파고든 것이다.
 * (관심영역 밖은 안 내려오므로 보이는 것들만 본다)
 */
function dumpCrowding() {
  const list = [];
  room.state.monsters?.forEach((m) => { if (m.hp > 0) list.push(m); });
  let worst = null;
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      const a = list[i], b = list[j];
      const ra = monsterRadius(MONSTER_KINDS[a.kind].scale);
      const rb = monsterRadius(MONSTER_KINDS[b.kind].scale);
      const gap = dist(a, b) - (ra + rb);
      if (!worst || gap < worst.gap) worst = { a, b, gap };
    }
  }
  if (!worst) { say('겹침 검사: 볼 몬스터가 둘 미만이다'); return; }
  const verdict = worst.gap < -0.01 ? `${(-worst.gap).toFixed(2)}m 겹쳤다` : '겹친 것 없음';
  say(`겹침 검사: 가장 가까운 두 마리 ${worst.a.kind}↔${worst.b.kind} 여유 ${worst.gap.toFixed(2)}m — ${verdict}`);
}

function nearestAlive() {
  const p = me();
  let best = null;
  room.state.monsters.forEach((m) => {
    if (m.hp <= 0) return;
    if (!best || dist(p, m) < dist(p, best)) best = m;
  });
  return best;
}

/** 나 말고 가장 가까운, 살아 있는 캐릭터 — 캐릭터끼리 충돌을 볼 때 쓴다 */
function nearestPlayer() {
  const p = me();
  let best = null;
  room.state.players.forEach((other, id) => {
    if (id === room.sessionId || other.dead) return;
    if (!best || dist(p, other) < dist(p, best)) best = other;
  });
  return best;
}

async function finish(code = 0) {
  clearInterval(beat);
  say(`# 끝 — ${lines.length}줄, ${logPath}`);
  try { await room.leave(); } catch { /* 이미 끊겼으면 그만 */ }
  process.exit(code);
}

// ---------------------------------------------------------------- 명령

if (command === 'state') {
  dumpSelf();
  dumpInventory();
  dumpOthers();
  dumpMonsters();
  dumpCrowding();
} else if (command === 'watch') {
  const seconds = Number(opt('seconds', 15));
  for (let t = 0; t < seconds; t += 2) {
    dumpSelf();
    await sleep(2000);
  }
} else if (command === 'fight') {
  const rounds = Number(opt('rounds', 3));
  dumpSelf();
  // 지목(target)은 **겨누기만 한다** — 붙어서 때리는 건 자동 사냥의 일이다.
  // 자동 사냥은 지목한 놈을 먼저 잡으므로(driveAutoHunt), 둘을 같이 켠다.
  room.send('autohunt', true);
  for (let round = 0; round < rounds; round++) {
    const target = nearestAlive();
    if (!target) { say('살아 있는 몬스터가 없다'); break; }
    say(`--- ${round + 1}회차: ${target.kind} hp ${target.maxHp}, ${dist(me(), target).toFixed(1)}m ---`);
    room.send('target', target.id);
    for (let i = 0; i < 40; i++) {
      await sleep(300);
      const t = room.state.monsters.get(target.id);
      if (!t || t.hp <= 0) break;
      if (i % 8 === 0) say(`  거리 ${dist(me(), t).toFixed(1)}m 대상 hp ${t.hp} 내 hp ${me().hp}`);
      if (me().dead) { say('  내가 죽었다'); break; }
    }
    if (me().dead) break;
  }
  room.send('autohunt', false);
  const rate = hits ? ((crits / hits) * 100).toFixed(1) : '0.0';
  say(`타격 ${hits}회 · 치명타 ${crits}회 (${rate}%) · 누적 피해 ${damage}`);
  say(`스킬 명중 ${JSON.stringify(skillHits)}`);
  dumpSelf();
} else if (command === 'aim') {
  /**
   * 클릭 타겟팅 확인 — **지목하면 겨누기만 하고, 쏘면 그쪽으로 나간다.**
   *
   * 보는 것은 셋이다.
   * 1. 지목한 뒤에도 **내가 그 자리에 있는지** (예전 클릭 추격은 여기서 달려갔다)
   * 2. 쏠 때 서버가 **대상 쪽으로 rotY 를 돌리는지** (판정 부채꼴이 이걸 본다)
   * 3. 사거리 밖을 겨누고 쏘면 **안 맞는지**
   */
  const target = nearestAlive();
  if (!target) { say('살아 있는 몬스터가 없다'); await finish(1); }

  const spot = { x: me().x, z: me().z };
  say(`지목: ${target.kind} hp ${target.hp}/${target.maxHp} · 거리 ${dist(me(), target).toFixed(1)}m`);
  room.send('target', target.id);
  await sleep(1500);
  say(`  지목 1.5초 뒤 내가 움직인 거리 ${dist(me(), spot).toFixed(2)}m (제자리여야 한다)`);

  // 사거리 안까지는 **내가 걸어간다** — 지목은 이동을 시키지 않는다.
  // 8m 를 고른 이유: 원거리 스킬(사거리 11~14)에는 들어오고 근접 판정에는
  // 절대 안 닿는 거리라, 타겟 자리에서 터진 것인지 구분이 된다.
  clearInterval(beat); // 정지 입력이 섞이면 반만 걷는다
  for (let i = 0; i < 200 && dist(me(), target) > 8; i++) {
    const p = me();
    const dx = target.x - p.x;
    const dz = target.z - p.z;
    const len = Math.hypot(dx, dz) || 1;
    room.send('input', { seq: ++seq, dx: dx / len, dz: dz / len, dt: 0.1 });
    await sleep(100);
  }
  const start = { x: me().x, z: me().z };
  say(`  걸어서 ${dist(me(), target).toFixed(1)}m 까지 붙었다 — 여기서부터는 안 움직여야 한다`);

  const wantRot = () => Math.atan2(target.x - me().x, target.z - me().z);
  say(`  쏘기 전 내 rotY ${me().rotY.toFixed(2)} / 대상 방향 ${wantRot().toFixed(2)}`);

  const hpBefore = target.hp;
  room.send('attack');
  await sleep(700);
  say(`  기본 공격 뒤 rotY ${me().rotY.toFixed(2)} (대상 방향 ${wantRot().toFixed(2)}) · 대상 hp ${hpBefore} → ${target.hp}`);

  for (const id of skillBar) {
    if (!target || target.hp <= 0) { say('  대상이 죽어서 남은 스킬은 건너뛴다'); break; }
    const before = target.hp;
    room.send('skill', id);
    await sleep(900);
    say(`  ${id}: 대상 hp ${before} → ${target.hp} · 거리 ${dist(me(), target).toFixed(1)}m`);
  }
  say(`스킬 명중 ${JSON.stringify(skillHits)} · 타격 ${hits}회 · 누적 피해 ${damage}`);

  // --- 사거리 밖 ---
  let far = null;
  room.state.monsters.forEach((m) => {
    if (m.hp <= 0) return;
    if (!far || dist(me(), m) > dist(me(), far)) far = m;
  });
  if (far && dist(me(), far) > 20) {
    const before = hits;
    say(`먼 놈 지목: ${far.kind} ${dist(me(), far).toFixed(1)}m — 사거리 밖이라 안 맞아야 한다`);
    room.send('target', far.id);
    await sleep(400);
    room.send('attack');
    for (const id of skillBar) { room.send('skill', id); await sleep(300); }
    await sleep(700);
    say(`  타격 ${hits - before}회 (0 이어야 한다) · 내가 움직인 거리 ${dist(me(), start).toFixed(2)}m`);
  }

  // --- 지목 없이 쏘기 ---
  //
  // **조준을 풀고 스킬만 누른다.** 서버가 사거리 안에서 가장 가까운 놈을 잡아
  // `target` 메시지로 알려주고(위의 `[대상]` 줄), 그놈이 맞아야 한다.
  room.send('target', null);
  await sleep(300);
  const near = nearestAlive();
  if (near) {
    say(`지목 없이 스킬 — 가장 가까운 ${near.kind} (${dist(me(), near).toFixed(1)}m) 가 맞아야 한다`);
    const before = near.hp;
    for (const id of skillBar) {
      if (near.hp <= 0) break;
      room.send('skill', id);
      await sleep(900);
    }
    say(`  ${near.kind} hp ${before} → ${near.hp} (줄어야 한다)`);
  }
  dumpSelf();
} else if (command === 'walk') {
  /**
   * 가장 가까운 몬스터를 향해 계속 걸어간다 — **충돌이 되는지 보는 명령.**
   *
   * 뚫고 지나가면 거리가 0 을 지나 다시 벌어지고, 막히면 몸 두께에서 멈춘다.
   * 화면 없이 확인할 방법이 이것뿐이라 만들었다 (docs/features/collision.md).
   */
  clearInterval(beat); // 정지 입력이 섞이면 반만 걷는다
  const seconds = Number(opt('seconds', 6));
  // --player 를 주면 몬스터 대신 다른 캐릭터에게 걸어간다 (probe 를 두 개 띄워서 본다)
  const toPlayer = flag('player');
  const target = toPlayer ? nearestPlayer() : nearestAlive();
  if (!target) {
    say(toPlayer ? '다른 캐릭터가 없다 — probe 를 하나 더 띄워야 한다' : '살아 있는 몬스터가 없다 — --zone 으로 사냥터를 골라야 한다');
    await finish(1);
  }
  say(`--- ${toPlayer ? target.name : target.kind} 에게 걸어간다 (지금 ${dist(me(), target).toFixed(2)}m) ---`);

  // 붙어서 시작하면 걸어갈 거리가 없어 아무것도 못 잰다. 먼저 2초 물러난다.
  if (dist(me(), target) < 3) {
    for (let i = 0; i < 20; i++) {
      const p = me();
      const dx = p.x - target.x;
      const dz = p.z - target.z;
      const len = Math.hypot(dx, dz) || 1;
      room.send('input', { seq: ++seq, dx: dx / len, dz: dz / len, dt: 0.1 });
      await sleep(100);
    }
    say(`  (${dist(me(), target).toFixed(2)}m 까지 물러났다가 다시 간다)`);
  }
  const until = Date.now() + seconds * 1000;
  let closest = Infinity;
  let last = -1;
  let ticks = 0;
  while (Date.now() < until) {
    const p = me();
    const dx = target.x - p.x;
    const dz = target.z - p.z;
    const len = Math.hypot(dx, dz) || 1;
    room.send('input', { seq: ++seq, dx: dx / len, dz: dz / len, dt: 0.1 });
    await sleep(100);
    const d = dist(me(), target);
    closest = Math.min(closest, d);
    if (Math.abs(d - last) > 0.03) say(`  거리 ${d.toFixed(2)}m`);
    last = d;
    // 몰려든 몬스터끼리 겹치는지도 걸어가는 내내 본다 (2초마다)
    if (++ticks % 20 === 0) dumpCrowding();
  }
  say(`멈춘 거리 ${dist(me(), target).toFixed(2)}m · 가장 가까웠던 거리 ${closest.toFixed(2)}m`);
  say(
    toPlayer
      ? '막혔으면 0.80m(캐릭터 0.4 + 0.4)에서 더 안 줄어든다. 0 에 가까우면 뚫은 것이다'
      : '막혔으면 몸 두께(캐릭터 0.4 + 몬스터 반지름)에서 더 안 줄어든다. 0 에 가까우면 뚫은 것이다'
  );
  // 여럿이 나를 쫓아왔을 것이다 — 그 몰린 상태에서 서로 겹쳤는지 같이 본다
  dumpCrowding();
} else if (command === 'root') {
  /**
   * **공격 경직** — 휘두르는 동안 이동이 막히는지 본다 (`ATTACK_ROOT_MS`).
   *
   * 같은 이동 입력을 내내 보내면서 중간에 `attack` 을 한 번 끼운다. 경직이
   * 걸리면 그 0.4초 동안 이동 거리가 0 에 가깝고, 풀리면 다시 걷는다.
   * 화면으로는 "공격하면서 미끄러진다"가 애매하게 보여서 글로 잰다.
   */
  clearInterval(beat); // 정지 입력이 섞이면 반만 걷는다
  const target = nearestAlive();
  if (!target) { say('살아 있는 몬스터가 없다 — --zone 으로 사냥터를 골라야 한다'); await finish(1); }

  // 대상 옆을 스쳐 가는 방향으로 걷는다 — 대상에게 박혀 서면 충돌 때문에
  // 안 움직인 것인지 경직 때문인지 구분이 안 된다.
  const dir = { dx: -(target.z - me().z), dz: target.x - me().x };
  const len = Math.hypot(dir.dx, dir.dz) || 1;
  dir.dx /= len;
  dir.dz /= len;

  /** 0.4초 동안 같은 방향으로 걸으면서 움직인 거리 */
  async function walk400() {
    const from = { x: me().x, z: me().z };
    for (let i = 0; i < 4; i++) {
      room.send('input', { seq: ++seq, dx: dir.dx, dz: dir.dz, dt: 0.1 });
      await sleep(100);
    }
    return dist(me(), from);
  }

  /**
   * **경직이 몇 초인지 직접 잰다.** 같은 방향으로 계속 걸으면서 50ms 마다 보고,
   * 처음으로 5cm 넘게 움직인 순간을 돌려준다. 구간 거리만 재면 "0 이 아니다"
   * 까지만 알 수 있고 길이가 맞는지는 모른다.
   */
  async function movesAgainAfter(who, step = { dx: 0, dz: 0 }) {
    const from = { x: who().x, z: who().z };
    const t0 = Date.now();
    for (let i = 0; i < 40; i++) {
      room.send('input', { seq: ++seq, dx: step.dx, dz: step.dz, dt: 0.05 });
      await sleep(50);
      if (dist(who(), from) > 0.05) return (Date.now() - t0) / 1000;
    }
    return null; // 2초가 지나도 안 움직였다
  }

  room.send('target', target.id);
  await sleep(300);
  say(`대상 ${target.kind} ${dist(me(), target).toFixed(1)}m · 옆으로 걷는다`);
  say(`  공격 전 0.4초: ${(await walk400()).toFixed(2)}m (RUN_SPEED 4.6 이면 1.8m 쯤)`);

  room.send('attack');
  say(`  공격 직후 0.4초: ${(await walk400()).toFixed(2)}m (경직 중이라 0 에 가까워야 한다)`);
  say(`  그 다음 0.4초: ${(await walk400()).toFixed(2)}m (경직이 풀려 다시 걸어야 한다)`);
  await sleep(1000); // 쿨타임을 넘겨 다시 칠 수 있게 한다
  room.send('attack');
  const mine = await movesAgainAfter(me, dir);
  say(
    `  경직 길이: ${mine === null ? '2초가 지나도 안 움직였다' : mine.toFixed(2) + '초'}` +
      ` (ATTACK_ROOT_MS 0.40초 + 틱·전송 지연)`
  );

  /**
   * --- 몬스터 쪽 ---
   *
   * 붙어 서서 **한 대 맞은 직후에 도망친다.** 경직이 걸려 있으면 그 0.4초 동안
   * 몬스터가 제자리에 있고, 풀리면 쫓아온다. 가만히 서서 재면 몬스터도 때리느라
   * 서 있어서 경직이 있으나 없으나 0 이 나온다 — 그래서 도망치면서 잰다.
   */
  say(`--- 몬스터 경직: ${target.kind} 에게 붙어서 한 대 맞아 본다 ---`);
  for (let i = 0; i < 200 && dist(me(), target) > 2; i++) {
    const p = me();
    const dx = target.x - p.x;
    const dz = target.z - p.z;
    const len = Math.hypot(dx, dz) || 1;
    room.send('input', { seq: ++seq, dx: dx / len, dz: dz / len, dt: 0.1 });
    await sleep(100);
  }
  lastHitAt = 0;
  for (let i = 0; i < 60 && !(lastHitBy === target.id && lastHitAt); i++) await sleep(100);
  if (!lastHitAt) {
    say('  안 때린다 — 어그로가 안 붙었다');
  } else {
    // 맞자마자 반대쪽으로 달린다. 몬스터가 이 0.4초 동안 움직였는지만 본다.
    const away = { dx: me().x - target.x, dz: me().z - target.z };
    const len = Math.hypot(away.dx, away.dz) || 1;
    away.dx /= len;
    away.dz /= len;
    const chased = async () => {
      const from = { x: target.x, z: target.z };
      for (let i = 0; i < 4; i++) {
        room.send('input', { seq: ++seq, dx: away.dx, dz: away.dz, dt: 0.1 });
        await sleep(100);
      }
      return dist(target, from);
    };
    say(`  맞은 직후 0.4초 몬스터 이동: ${(await chased()).toFixed(2)}m (경직 중이라 0 에 가까워야 한다)`);
    say(`  그 다음 0.4초 몬스터 이동: ${(await chased()).toFixed(2)}m (쫓아와야 한다)`);

    // 경직 길이도 잰다 — 다음 한 대를 맞고, 그놈이 언제 다시 움직이는지 본다.
    // 나는 계속 도망치므로 경직이 풀리는 순간이 곧 쫓아오기 시작하는 순간이다.
    lastHitAt = 0;
    for (let i = 0; i < 60 && !(lastHitBy === target.id && lastHitAt); i++) {
      room.send('input', { seq: ++seq, dx: 0, dz: 0, dt: 0.05 });
      await sleep(50);
    }
    if (lastHitAt) {
      const chaseAt = await movesAgainAfter(() => target, away);
      // 잰 값은 서버 틱과 상태 전송 간격만큼(0.1~0.2초) 길게 나온다 — 그만큼 늦게 보인다
      say(
        `  몬스터 경직 길이: ${chaseAt === null ? '2초가 지나도 안 움직였다' : chaseAt.toFixed(2) + '초'}` +
          ` (MONSTER_SWING_MS 0.65초 + 틱·전송 지연)`
      );
    }
  }
  dumpSelf();
} else if (command === 'god') {
  /**
   * **무적 모드** (테스트 도구) — 켜면 정말 안 깎이는지, 그런데도 맞은 것은
   * 그대로 방송되는지 본다. 뒤쪽이 중요하다: 몬스터 공격 동작은 `hit` 으로 도는데
   * 무적이 그 메시지를 막아 버리면, 동작을 보려고 켠 무적이 동작을 못 보게 만든다.
   */
  clearInterval(beat);
  const target = nearestAlive();
  if (!target) { say('살아 있는 몬스터가 없다 — --zone 으로 사냥터를 골라야 한다'); await finish(1); }

  // 맞을 수 있는 자리까지 붙는다
  for (let i = 0; i < 200 && dist(me(), target) > 2; i++) {
    const p = me();
    const dx = target.x - p.x;
    const dz = target.z - p.z;
    const len = Math.hypot(dx, dz) || 1;
    room.send('input', { seq: ++seq, dx: dx / len, dz: dz / len, dt: 0.1 });
    await sleep(100);
  }

  /** 4초 동안 가만히 맞으면서 체력 변화와 맞은 횟수를 센다 */
  async function stand(seconds = 4) {
    const before = me().hp;
    hitsOnMe = 0;
    zeroHits = 0;
    for (let i = 0; i < seconds * 20; i++) {
      room.send('input', { seq: ++seq, dx: 0, dz: 0, dt: 0.05 });
      await sleep(50);
    }
    return { lost: before - me().hp, hits: hitsOnMe, zero: zeroHits };
  }

  /**
   * **무적 켠 구간을 먼저 잰다.** ★
   * 끄고 먼저 재면 1레벨이 4초를 못 버티고 쓰러지는데, 죽은 뒤에는
   * `damagePlayer` 가 `dead` 로 바로 빠져나가 체력 -0 · 맞은 횟수 0 이 나온다 —
   * 무적이 된 건지 죽어서 안 맞는 건지 구분이 안 되는 거짓 결과다.
   */
  room.send('godmode', true);
  await sleep(300);
  say(`무적 상태: ${godmodeOn === null ? '서버가 대답을 안 했다' : godmodeOn ? '켜짐' : '꺼짐'}`);
  const on = await stand();
  say(`무적 켜고 4초: 체력 -${on.lost} (0 이어야 한다) · 맞은 횟수 ${on.hits} (0 이면 공격 동작이 안 돈다)`);
  say(`  그중 피해 0 으로 온 것 ${on.zero}회 (맞은 횟수와 같아야 한다)`);
  room.send('godmode', false);
  await sleep(300);
  say(`끈 뒤 상태: ${godmodeOn ? '켜짐' : '꺼짐'}`);
  const off = await stand();
  say(`무적 끄고 4초: 체력 -${off.lost} (0 이면 안 된다) · 맞은 횟수 ${off.hits}` +
    `${me().dead ? ' — 쓰러졌다' : ''}`);
  dumpSelf();
} else if (command === 'send') {
  const type = positional[0];
  if (!type) { say('보낼 메시지 종류를 적어야 한다: probe.mjs send <type> [payload]'); await finish(1); }
  let payload = positional[1];
  if (payload !== undefined) {
    try { payload = JSON.parse(payload); } catch { /* 문자열 그대로 보낸다 */ }
  }
  // 보내기 전후를 같이 찍는다 — 마나가 줄었는지 같은 건 이걸로만 보인다
  dumpSelf();
  // --times/--gap: 같은 메시지를 연달아 보낸다 — 쿨타임이 막는지 여기서 본다
  const times = Math.max(1, Number(opt('times', 1)));
  const gap = Number(opt('gap', 300));
  for (let i = 0; i < times; i++) {
    if (i > 0) await sleep(gap);
    say(`보냄${times > 1 ? ` ${i + 1}/${times}` : ''}: ${type} ${JSON.stringify(payload ?? null)}`);
    room.send(type, payload);
  }
  await sleep(Number(opt('seconds', 2)) * 1000);
  dumpSelf();
  dumpInventory();
} else {
  say(`모르는 명령: ${command} (state | fight | aim | walk | root | god | send | watch)`);
  await finish(1);
}

await finish(0);
