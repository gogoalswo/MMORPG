import { createTransport, LOCAL_SERVER, type RoomLike } from './transport';
import type { ItemStack, MoveInput, NpcRole } from '@mmo/shared';
import type { ChatMessage } from '../ui/chat';
import type { CharacterSummary } from '../ui/characterSelect';

/**
 * 존 룸 접속.
 *
 * 서버 상태를 그대로 그리지 않는다. 다른 플레이어는 스냅샷을 버퍼에 쌓아두고
 * 일정 시간 뒤의 과거를 재생한다 (보간) — 그래야 15Hz 로 띄엄띄엄 오는 위치가
 * 60fps 화면에서 끊기지 않는다.
 */

export interface RemoteSnapshot {
  /** performance.now() 기준 수신 시각 */
  t: number;
  x: number;
  z: number;
  rotY: number;
}

/** 화면에 그려지는 장비. 빈 문자열이면 그 자리가 비어 있다 */
export interface GearLook {
  weapon: string;
  offhand: string;
  helmet: string;
  armor: string;
  boots: string;
}

export const EMPTY_GEAR: GearLook = {
  weapon: '',
  offhand: '',
  helmet: '',
  armor: '',
  boots: '',
};

export function sameGear(a: GearLook, b: GearLook): boolean {
  return (
    a.weapon === b.weapon &&
    a.offhand === b.offhand &&
    a.helmet === b.helmet &&
    a.armor === b.armor &&
    a.boots === b.boots
  );
}

export interface RemoteEntity {
  id: string;
  name: string;
  /** 플레이어는 직업 id, 몬스터는 종류 id */
  job: string;
  hp: number;
  maxHp: number;
  /** 플레이어 전용 — 남의 손에 뭐가 들렸는지 */
  gear?: GearLook;
  /** 몬스터 전용 — idle | chase | attack | dead */
  state?: string;
  buffer: RemoteSnapshot[];
}

/** 버퍼 길이. 보간 지연 + 패킷 지터를 덮을 만큼만 */
const MAX_SNAPSHOTS = 24;

const SERVER_KEY = 'mmo:server';
const TOKEN_KEY = 'mmo:token';
const CHARACTER_KEY = 'mmo:character';

/**
 * http(s) 주소를 ws(s) 로 바꾼다.
 *
 * HTTPS 페이지에서 ws:// 로 접속하면 브라우저가 혼합 콘텐츠로 차단한다.
 * 터널은 https 주소를 주므로 반드시 wss 로 바꿔야 한다.
 */
function toWebSocketUrl(url: string): string {
  return url.trim().replace(/^http/, 'ws').replace(/\/+$/, '');
}

/**
 * 접속할 서버 주소를 정한다.
 *
 * 빌드에 박지 않고 **실행 시점에** 정하는 게 핵심이다.
 * 무료 터널은 켤 때마다 주소가 바뀌는데, 빌드에 박아두면 그때마다
 * 다시 빌드해서 다시 배포해야 한다.
 *
 * 우선순위: ?server= 쿼리 > 지난번에 쓴 주소 > 빌드 기본값 > 로컬
 *
 * `local` 은 서버 없이 브라우저 안에서 돈다 (transport.ts). GitHub Pages 빌드의
 * 기본값이다. `?server=local` 은 기억해 둔 주소를 지운다 — 한 번 붙어 본 원격
 * 주소가 남아 있으면 다시는 로컬로 못 돌아온다.
 */
export function resolveServerUrl(): string {
  const fromQuery = new URLSearchParams(location.search).get('server');
  if (fromQuery === LOCAL_SERVER) {
    try {
      localStorage.removeItem(SERVER_KEY);
    } catch {
      /* 무시 */
    }
    return LOCAL_SERVER;
  }
  if (fromQuery) {
    // 한 번 받은 주소는 기억해둔다. 다음부터는 링크 없이 들어와도 붙는다.
    try {
      localStorage.setItem(SERVER_KEY, fromQuery);
    } catch {
      /* 시크릿 모드 등에서 저장이 막혀도 이번 접속은 된다 */
    }
    return toWebSocketUrl(fromQuery);
  }

  try {
    const saved = localStorage.getItem(SERVER_KEY);
    if (saved) return toWebSocketUrl(saved);
  } catch {
    /* 무시 */
  }

  const fromEnv = import.meta.env.VITE_SERVER_URL;
  if (fromEnv === LOCAL_SERVER) return LOCAL_SERVER;
  if (fromEnv) return toWebSocketUrl(fromEnv);

  return 'ws://localhost:2567';
}

const SERVER_URL = resolveServerUrl();

/** 서버가 접속 직후 알려주는 내 계정 정보 */
export interface SessionInfo {
  token: string;
  accountId: string;
  characterId: string;
  characterName: string;
  job: string;
  /** 서버가 확정한 존과 위치 */
  zoneId: string;
  x: number;
  z: number;
  /** 구글 연동이 돼 있으면 그 이메일 */
  linkedGoogle: string | null;
  isNewAccount: boolean;
}

export interface SelfStatus {
  level: number;
  hp: number;
  maxHp: number;
  exp: number;
  dead: boolean;
  /** 자동 사냥 중인지 — 판단과 이동은 서버가 한다 */
  auto: boolean;
  /** 클릭으로 지정한 대상을 쫓는 중인지. 이동은 서버가 한다 */
  /** 지금 걸치고 있는 것 — 내 캐릭터도 남과 같은 경로로 그린다 */
  gear: GearLook;
  /**
   * 서버가 정한 바라보는 각.
   *
   * 자동 사냥·추격 중에는 **서버가 각을 정한다.** 클라이언트는 "움직인 방향"밖에
   * 알 수 없어서, 이걸 안 받으면 대상을 옆구리로 보고 걷는다.
   */
  rotY: number;
}

export interface HitEvent {
  targetId: string;
  targetKind: 'monster' | 'player';
  amount: number;
  killed: boolean;
  sourceId: string;
  /**
   * 맞은 지점. 대상이 이미 시야에서 빠졌어도(막타) 숫자를 띄울 수 있게
   * 서버가 좌표를 같이 보내준다.
   */
  x: number;
  z: number;
  /** 회복이면 초록으로 표시한다 */
  heal?: boolean;
  /** 치명타로 터진 피해 — 숫자를 다르게 띄운다 */
  crit?: boolean;
  /** 있으면 날아가는 모습을 보여주고, 도착할 때 피해를 표시한다 */
  projectile?: string;
  /** 이 타격을 낸 스킬. 기본 공격이면 없다 — 맞은 자리에 그 이펙트를 터뜨린다 */
  skillId?: string;
}

/**
 * 보스의 범위 공격 예고.
 *
 * 원을 그릴 정보만 온다. 맞았는지는 별개로 `hit` 이 알려준다 — 판정은 서버가
 * 하고, 이 메시지는 순전히 보여주기용이다.
 */
export interface AoeEvent {
  /** 건 몬스터 */
  id: string;
  name: string;
  /** 원 중심. 시전을 시작한 자리에 고정된다 */
  x: number;
  z: number;
  radius: number;
  /** 터지기까지 남은 시간 (ms) */
  delayMs: number;
}

export interface LinkResult {
  ok: boolean;
  reason?: string;
  email?: string | null;
  token?: string;
  /** 다른 계정으로 갈아탔다 — 그 계정 캐릭터를 쓰려면 새로고침해야 한다 */
  switched?: boolean;
}

/**
 * 로컬 모드는 토큰·캐릭터를 따로 적는다. 같은 키를 쓰면 로컬 DB 가 모르는
 * 서버 토큰을 보내 게스트가 새로 생기고, 그 토큰이 서버 토큰을 덮어써서
 * 서버 계정으로 다시 못 들어간다.
 */
function storageKey(key: string): string {
  return SERVER_URL === LOCAL_SERVER ? `${key}:local` : key;
}

function readToken(): string | undefined {
  try {
    return localStorage.getItem(storageKey(TOKEN_KEY)) ?? undefined;
  } catch {
    return undefined;
  }
}

/** 선택한 캐릭터. 포탈로 존을 옮길 때도 같은 캐릭터로 들어가야 한다 */
export function readCharacterId(): string | undefined {
  try {
    return localStorage.getItem(storageKey(CHARACTER_KEY)) ?? undefined;
  } catch {
    return undefined;
  }
}

export function writeCharacterId(id: string): void {
  try {
    localStorage.setItem(storageKey(CHARACTER_KEY), id);
  } catch {
    /* 무시 */
  }
}

function writeToken(token: string): void {
  try {
    localStorage.setItem(storageKey(TOKEN_KEY), token);
  } catch {
    /* 저장이 막혀도 이번 세션은 유지된다 */
  }
}

export interface InventoryState {
  gold: number;
  items: ItemStack[];
  equipment: Record<string, ItemStack>;
}

export interface ConnectionHandlers {
  /** 서버가 확정한 내 위치(예측 보정용)와 전투 상태 */
  onSelf(x: number, z: number, lastSeq: number, status: SelfStatus): void;
  onRemoteAdd(entity: RemoteEntity): void;
  onRemoteRemove(id: string): void;
  onMonsterAdd(entity: RemoteEntity): void;
  onMonsterRemove(id: string): void;
  /** 피해가 들어갔다 (내가 때렸든 맞았든) */
  onHit(event: HitEvent): void;
  /** 보스가 범위 공격을 걸었다 — 바닥에 원을 그린다 */
  onAoe(event: AoeEvent): void;
  /**
   * 공격 모션. `rootMs` 는 **이 동안 못 움직인다**는 서버의 통보다
   * (`ATTACK_ROOT_MS`). 내 것이면 예측도 그만큼 멈춰야 보정이 안 튄다.
   */
  onSwing(id: string, rootMs: number): void;
  onSkill(id: string, skillId: string, rootMs: number): void;
  /** 무적 모드가 켜졌는지 — 서버가 정한 값 (테스트 도구) */
  onGodMode(on: boolean): void;
  onNotice(text: string): void;
  onReward(exp: number, name: string): void;
  /** 가방·골드·장비. 바뀔 때마다 서버가 통째로 다시 보낸다 */
  onInventory(state: InventoryState): void;
  /** NPC 창을 열어도 된다 — 서버가 거리를 확인해준 뒤에만 온다 */
  onNpc(info: { role: NpcRole; stock: string[]; forge: string[]; jobs: string[] }): void;
  onJobChanged(job: string): void;
  /** 배운 스킬·액션바·남은 포인트 */
  onSkills(state: { learned: string[]; bar: string[]; points: number }): void;
  /** 방금 주운 것 */
  onLoot(gold: number, items: string[]): void;
  onLevelUp(level: number): void;
  /** 서버가 물고 있는 대상이 바뀌었다 (지정·해제·대상 사망) */
  onTarget(monsterId: string | null): void;
  onChat(message: ChatMessage): void;
  onSession(info: SessionInfo): void;
  /** 아직 캐릭터가 없다 — 생성 화면을 띄워야 한다 */
  onNeedsCharacter(suggestedName: string): void;
  onCharacterList(list: { max: number; characters: CharacterSummary[] }): void;
  /** 고른 캐릭터가 다른 존에 있다 — 그 존으로 옮겨서 다시 들어가야 한다 */
  onSwitchZone(zoneId: string, characterId: string): void;
  onCreateResult(result: { ok: boolean; reason?: string }): void;
  onLinkResult(result: LinkResult): void;
  onError(message: string): void;
}

export class ZoneConnection {
  readonly remotes = new Map<string, RemoteEntity>();
  readonly monsters = new Map<string, RemoteEntity>();

  private readonly client = createTransport(SERVER_URL);
  private room: RoomLike | null = null;
  /** 접속 요청 세대. 늦게 도착한 이전 존의 응답을 버리는 데 쓴다 */
  private generation = 0;
  /**
   * 사람이 마지막으로 누른 무적 값 (테스트 도구).
   *
   * 존을 옮기면 룸이 새로 생겨 **서버 쪽 무적은 꺼진 채로 시작한다.** 다시
   * 요청하지 않으면 단추만 노랗게 켜져 있고 실제로는 안 무적이 된다.
   */
  private godmodeWanted = false;

  constructor(private readonly handlers: ConnectionHandlers) {
    // https 페이지에서 ws:// 는 브라우저가 조용히 막는다. 원인을 못 찾으면 한참 헤맨다.
    if (location.protocol === 'https:' && SERVER_URL.startsWith('ws://') && SERVER_URL !== LOCAL_SERVER) {
      handlers.onError('HTTPS 페이지에서는 wss:// 서버만 접속됩니다 (현재 ' + SERVER_URL + ')');
    }
  }

  /** 디버깅용 — 지금 어디에 붙고 있는지 */
  get serverUrl(): string {
    return SERVER_URL;
  }

  get sessionId(): string | null {
    return this.room?.sessionId ?? null;
  }

  get connected(): boolean {
    return this.room !== null;
  }

  async join(
    zoneId: string,
    spawn: string | undefined,
    name: string,
    job: string,
    characterId?: string
  ): Promise<void> {
    const gen = ++this.generation;
    await this.leave();

    let room: RoomLike;
    try {
      // 토큰을 같이 보낸다. 서버가 계정을 알아보거나, 없으면 게스트로 만들어준다.
      room = await this.client.joinOrCreate('zone', {
        zoneId,
        // 스폰을 지정하지 않으면 서버가 저장된 위치로 복원한다
        ...(spawn ? { spawn } : {}),
        name,
        job,
        token: readToken(),
        ...(characterId ? { characterId } : {}),
      });
    } catch (err) {
      if (gen === this.generation) {
        this.handlers.onError(err instanceof Error ? err.message : String(err));
      }
      return;
    }

    // 접속하는 사이에 다른 존으로 또 이동했다면 이 룸은 버린다
    if (gen !== this.generation) {
      void room.leave();
      return;
    }

    this.room = room;
    room.onMessage('chat', (msg: ChatMessage) => this.handlers.onChat(msg));
    room.onMessage('needsCharacter', (msg: { suggestedName: string }) => {
      this.handlers.onNeedsCharacter(msg?.suggestedName ?? '');
    });
    room.onMessage('createResult', (result: { ok: boolean; reason?: string }) => {
      this.handlers.onCreateResult(result);
    });
    room.onMessage('characterList', (list: { max: number; characters: CharacterSummary[] }) => {
      this.handlers.onCharacterList(list);
    });
    room.onMessage('switchZone', (msg: { zoneId: string; characterId: string }) => {
      this.handlers.onSwitchZone(msg.zoneId, msg.characterId);
    });
    room.onMessage('session', (info: SessionInfo) => {
      writeToken(info.token);
      writeCharacterId(info.characterId);
      this.handlers.onSession(info);
    });
    room.onMessage('linkResult', (result: LinkResult) => {
      if (result.ok && result.token) writeToken(result.token);
      this.handlers.onLinkResult(result);
    });
    room.onError((_code, message) => this.handlers.onError(message ?? '알 수 없는 오류'));
    room.onLeave(() => {
      if (this.room === room) this.room = null;
    });

    room.onMessage('hit', (e: HitEvent) => this.handlers.onHit(e));
    room.onMessage('aoe', (e: AoeEvent) => this.handlers.onAoe(e));
    room.onMessage('swing', (m: { id: string; rootMs?: number }) =>
      this.handlers.onSwing(m.id, m.rootMs ?? 0)
    );
    room.onMessage('skill', (m: { id: string; skillId: string; rootMs?: number }) =>
      this.handlers.onSkill(m.id, m.skillId, m.rootMs ?? 0)
    );
    room.onMessage('godmode', (m: { on: boolean }) => this.handlers.onGodMode(!!m.on));
    room.onMessage('notice', (m: { text: string }) => this.handlers.onNotice(m.text));
    room.onMessage('reward', (m: { exp: number; name: string }) =>
      this.handlers.onReward(m.exp, m.name)
    );
    room.onMessage('levelUp', (m: { level: number }) => this.handlers.onLevelUp(m.level));
    room.onMessage('inventory', (m: InventoryState) => this.handlers.onInventory(m));
    room.onMessage('npc', (m: { role: NpcRole; stock: string[]; forge: string[]; jobs: string[] }) =>
      this.handlers.onNpc(m)
    );
    room.onMessage('jobChanged', (m: { job: string }) => this.handlers.onJobChanged(m.job));
    room.onMessage('skills', (m: { learned: string[]; bar: string[]; points: number }) =>
      this.handlers.onSkills(m)
    );
    room.onMessage('loot', (m: { gold: number; items: string[] }) =>
      this.handlers.onLoot(m.gold, m.items)
    );
    room.onMessage('target', (m: { id: string | null }) => this.handlers.onTarget(m.id ?? null));

    /**
     * 무적은 룸에 붙어 있다 — 존을 옮기면 새 룸이라 꺼진 채로 시작한다. ★
     *
     * 그래서 단추를 **먼저 꺼짐으로 되돌린 다음** 원했으면 다시 요청한다.
     * 되돌리지 않으면 차원문을 지난 뒤 단추만 노랗게 남아 "눌렀는데 무적이
     * 안 된다"가 된다 — 켜졌는지는 서버가 돌려주는 'godmode' 로만 그린다.
     */
    this.handlers.onGodMode(false);
    if (this.godmodeWanted) room.send('godmode', true);

    room.onStateChange((state) => this.ingest(state));
  }

  private ingest(state: any): void {
    const now = performance.now();
    const self = this.room?.sessionId;
    const seen = new Set<string>();

    // 접속 직후 첫 패치는 StateView 가 아직 비어 있어 players 맵 자체가 내려오지 않는다.
    // 여기서 던지면 SDK 의 디코드 루프가 끊겨 뒤따르는 패치가 아예 오지 않는다 —
    // 화면은 뜨는데 HP·레벨이 영원히 빈 채로 굳는다. monsters 쪽과 같은 이유로 건너뛴다.
    if (!state.players) return;

    state.players.forEach((p: any, id: string) => {
      seen.add(id);

      if (id === self) {
        this.handlers.onSelf(p.x, p.z, p.lastSeq, {
          level: p.level,
          hp: p.hp,
          maxHp: p.maxHp,
          exp: p.exp,
          dead: p.dead,
          auto: p.auto ?? false,
          rotY: p.rotY ?? 0,
          gear: {
            weapon: p.weapon ?? '',
            offhand: p.offhand ?? '',
            helmet: p.helmet ?? '',
            armor: p.armor ?? '',
            boots: p.boots ?? '',
          },
        });
        return;
      }

      let entity = this.remotes.get(id);
      if (!entity) {
        entity = { id, name: p.name, job: p.job, hp: p.hp, maxHp: p.maxHp, buffer: [] };
        this.remotes.set(id, entity);
        this.handlers.onRemoteAdd(entity);
      }
      entity.hp = p.hp;
      entity.gear = {
        weapon: p.weapon ?? '',
        offhand: p.offhand ?? '',
        helmet: p.helmet ?? '',
        armor: p.armor ?? '',
        boots: p.boots ?? '',
      };
      entity.buffer.push({ t: now, x: p.x, z: p.z, rotY: p.rotY });
      if (entity.buffer.length > MAX_SNAPSHOTS) entity.buffer.shift();
    });

    // 관심영역 밖으로 나갔거나 접속을 끊은 플레이어
    for (const id of [...this.remotes.keys()]) {
      if (seen.has(id)) continue;
      this.remotes.delete(id);
      this.handlers.onRemoteRemove(id);
    }

    this.ingestMonsters(state, now);
  }

  private ingestMonsters(state: any, now: number): void {
    const seen = new Set<string>();

    state.monsters?.forEach((m: any, id: string) => {
      seen.add(id);
      let entity = this.monsters.get(id);
      if (!entity) {
        entity = { id, name: m.kind, job: m.kind, hp: m.hp, maxHp: m.maxHp, state: m.state, buffer: [] };
        this.monsters.set(id, entity);
        this.handlers.onMonsterAdd(entity);
      }
      entity.hp = m.hp;
      entity.state = m.state;
      entity.buffer.push({ t: now, x: m.x, z: m.z, rotY: m.rotY });
      if (entity.buffer.length > MAX_SNAPSHOTS) entity.buffer.shift();
    });

    for (const id of [...this.monsters.keys()]) {
      if (seen.has(id)) continue;
      this.monsters.delete(id);
      this.handlers.onMonsterRemove(id);
    }
  }

  sendInput(input: MoveInput): void {
    this.room?.send('input', input);
  }

  sendChat(text: string): void {
    this.room?.send('chat', text);
  }

  selectCharacter(id: string): void {
    this.room?.send('selectCharacter', { id });
  }

  deleteCharacter(id: string): void {
    this.room?.send('deleteCharacter', { id });
  }

  createCharacter(name: string, job: string): void {
    this.room?.send('createCharacter', { name, job });
  }

  attack(): void {
    this.room?.send('attack');
  }

  /**
   * 무적 모드 켜기/끄기 (테스트 도구). **켜졌는지는 서버가 `godmode` 로 돌려준다** —
   * 여기서 미리 켠 것으로 치면 서버가 거절해도(스위치가 꺼져 있으면) 켜 보인다.
   */
  setGodMode(on: boolean): void {
    this.godmodeWanted = on;
    this.room?.send('godmode', on);
  }

  /** 가방 칸 번호로 낀다 — 같은 아이템의 등급 다른 것이 섞이므로 id 로는 못 고른다 */
  equip(index: number): void {
    this.room?.send('equip', index);
  }

  craft(index: number): void {
    this.room?.send('craft', index);
  }

  unequip(slot: string): void {
    this.room?.send('unequip', slot);
  }

  /** 자동 사냥 켜기/끄기. 실제 상태는 서버가 정하고 state 로 돌아온다 */
  setAutoHunt(on: boolean): void {
    this.room?.send('autohunt', on);
  }

  /**
   * 자동 사냥 중에 "저기로 먼저 가라".
   *
   * 자동 사냥이 켜져 있으면 이동은 서버가 몬다. 클라이언트가 목표를 들고 있어 봐야
   * 매 프레임 지워지므로(driven 모드), 자리를 서버에 알려주는 수밖에 없다.
   * 꺼져 있을 때는 보내지 않는다 — 그때는 클라이언트 예측이 더 부드럽다.
   */
  moveTo(x: number, z: number): void {
    this.room?.send('moveTo', { x, z });
  }

  /**
   * 클릭으로 때릴 대상을 지정한다. null 이면 그만둔다.
   *
   * 붙고 때리는 건 전부 서버가 한다 — 폰에서 화면이 꺼져도 싸움이 이어지려면
   * 클라이언트 루프에 기대면 안 된다.
   */
  setTarget(monsterId: string | null): void {
    this.room?.send('target', monsterId);
  }

  learnSkill(skillId: string): void {
    this.room?.send('learnSkill', skillId);
  }

  /** 액션바 구성. 배운 것 중에서만 올라간다 (서버가 다시 본다) */
  setSkillBar(skillIds: string[]): void {
    this.room?.send('setSkillBar', skillIds);
  }

  /** NPC 에게 말을 건다. 서버가 거리를 다시 확인한다 */
  openNpc(role: string): void {
    this.room?.send('npcOpen', role);
  }

  buyItem(itemId: string): void {
    this.room?.send('npcBuy', itemId);
  }

  sellItem(index: number): void {
    this.room?.send('npcSell', index);
  }

  enhanceItem(index: number): void {
    this.room?.send('npcEnhance', index);
  }

  forgeItem(itemId: string): void {
    this.room?.send('npcForge', itemId);
  }

  changeJob(job: string): void {
    this.room?.send('npcJob', job);
  }

  /** 자동으로 쓸 스킬. 서버가 직업을 다시 확인한다 */
  setAutoSkills(skillIds: string[]): void {
    this.room?.send('autoSkills', skillIds);
  }

  /** 사냥 반경. 서버가 다시 자르므로 여기서는 보낼 뿐이다 */
  setAutoRange(radius: number): void {
    this.room?.send('autoRange', radius);
  }

  useSkill(skillId: string): void {
    this.room?.send('skill', skillId);
  }

  sendJob(job: string): void {
    this.room?.send('setJob', job);
  }

  linkGoogle(idToken: string): void {
    this.room?.send('linkGoogle', idToken);
  }

  async leave(): Promise<void> {
    const room = this.room;
    this.room = null;
    for (const id of this.remotes.keys()) this.handlers.onRemoteRemove(id);
    this.remotes.clear();
    for (const id of this.monsters.keys()) this.handlers.onMonsterRemove(id);
    this.monsters.clear();
    if (room) {
      try {
        await room.leave();
      } catch {
        /* 이미 끊겼으면 무시 */
      }
    }
  }
}

/**
 * 버퍼에서 renderTime 시점의 위치를 뽑는다.
 *
 * renderTime 은 "지금"이 아니라 INTERP_DELAY_MS 만큼 과거다. 그 지연 덕분에
 * 항상 앞뒤 스냅샷 두 개 사이를 보간할 수 있어 외삽(추측)을 하지 않아도 된다.
 */
export function sampleRemote(
  entity: RemoteEntity,
  renderTime: number,
  out: { x: number; z: number; rotY: number }
): boolean {
  const buf = entity.buffer;
  if (buf.length === 0) return false;

  if (buf.length === 1 || renderTime <= buf[0]!.t) {
    const s = buf[0]!;
    out.x = s.x;
    out.z = s.z;
    out.rotY = s.rotY;
    return true;
  }

  const last = buf[buf.length - 1]!;
  if (renderTime >= last.t) {
    // 버퍼가 말랐다 — 마지막 위치에 붙인다 (외삽하면 튄다)
    out.x = last.x;
    out.z = last.z;
    out.rotY = last.rotY;
    return true;
  }

  for (let i = buf.length - 1; i > 0; i--) {
    const b = buf[i]!;
    const a = buf[i - 1]!;
    if (renderTime >= a.t && renderTime <= b.t) {
      const span = b.t - a.t;
      const k = span > 0 ? (renderTime - a.t) / span : 0;
      out.x = a.x + (b.x - a.x) * k;
      out.z = a.z + (b.z - a.z) * k;
      out.rotY = lerpAngle(a.rotY, b.rotY, k);
      return true;
    }
  }

  return false;
}

/** 각도 보간. -pi/pi 경계를 넘을 때 반대로 도는 걸 막는다 */
export function lerpAngle(a: number, b: number, k: number): number {
  let delta = b - a;
  while (delta > Math.PI) delta -= Math.PI * 2;
  while (delta < -Math.PI) delta += Math.PI * 2;
  return a + delta * k;
}
