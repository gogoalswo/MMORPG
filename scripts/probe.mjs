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
 *   node scripts/probe.mjs watch --seconds 20
 *
 * 옵션:
 *   --zone <id>        기본 village
 *   --token <t>        없으면 게스트로 접속한다 (새 계정이 만들어진다)
 *   --character <id>   기존 캐릭터로 들어간다
 *   --name <이름> --job <knight|mage|archer>
 *   --server <url>     기본 ws://localhost:2567
 *   --seconds <n> / --rounds <n>
 *   --log <path>       기본 logs/probe-<시각>.log
 *   --quiet            콘솔에는 안 찍고 파일에만 남긴다
 */
import { Client } from '@colyseus/sdk';
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
  const name = opt('name', m.suggestedName ?? '검증');
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
room.onMessage('target', (m) => say(`[대상] ${m.id ?? '해제'}`));
room.onMessage('aoe', (m) =>
  say(`[범위예고] ${m.name} 반경 ${m.radius}m @ (${m.x.toFixed(1)}, ${m.z.toFixed(1)}) ${m.delayMs}ms 뒤`));
room.onMessage('enhanceResult', (m) => say(`[강화] ${m.result} → +${m.level}`));
room.onMessage('npc', (m) => say(`[NPC] ${m.role} 재고=${JSON.stringify(m.stock)}`));
room.onMessage('hit', (m) => {
  if (m.targetKind !== 'monster') return;
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
      ` (${p.x.toFixed(1)}, ${p.z.toFixed(1)}) auto=${p.auto ?? false} chasing=${p.chasing ?? false}`);
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

function nearestAlive() {
  const p = me();
  let best = null;
  room.state.monsters.forEach((m) => {
    if (m.hp <= 0) return;
    if (!best || dist(p, m) < dist(p, best)) best = m;
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
} else if (command === 'watch') {
  const seconds = Number(opt('seconds', 15));
  for (let t = 0; t < seconds; t += 2) {
    dumpSelf();
    await sleep(2000);
  }
} else if (command === 'fight') {
  const rounds = Number(opt('rounds', 3));
  dumpSelf();
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
  const rate = hits ? ((crits / hits) * 100).toFixed(1) : '0.0';
  say(`타격 ${hits}회 · 치명타 ${crits}회 (${rate}%) · 누적 피해 ${damage}`);
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
  say(`보냄: ${type} ${JSON.stringify(payload ?? null)}`);
  room.send(type, payload);
  await sleep(Number(opt('seconds', 2)) * 1000);
  dumpSelf();
  dumpInventory();
} else {
  say(`모르는 명령: ${command} (state | fight | send | watch)`);
  await finish(1);
}

await finish(0);
