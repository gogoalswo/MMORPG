/**
 * 브라우저 안의 게임 서버.
 *
 * `packages/server` 의 ZoneRoom 을 **고치지 않고 그대로** 돌린다. Node 전용 모듈은
 * vite.config.ts 의 alias(타입은 tsconfig 의 paths)로 `shims/` 가 대신 받는다.
 *
 * 실제 서버와 맞춘 것:
 * - 존 하나 = 룸 하나 (`filterBy(['zoneId'])`), 아무도 없으면 룸을 버린다 (autoDispose)
 * - 메시지는 JSON 으로 한 번 복사한다. 선로를 타는 것처럼 undefined 가 빠지고,
 *   서버가 보낸 배열을 나중에 고쳐도 클라이언트 쪽 값이 따라 바뀌지 않는다
 * - 메시지·상태는 다음 태스크에 배달한다. 동기로 부르면 클라이언트가 핸들러를
 *   달기 전에 onJoin 의 메시지가 먼저 도착해 버려진다
 * - 상태는 `setPatchRate` 주기로, 그 클라이언트의 StateView 에 든 것만 보낸다
 *
 * 다른 점: 스키마를 직렬화하지 않고 서버 객체를 그대로 넘긴다 (같은 메모리라서).
 * 클라이언트 `ingest` 는 읽기만 하므로 문제없다.
 */
import { StateView } from '@colyseus/schema';
import { ZoneRoom } from '../../../../server/src/ZoneRoom.ts';
import type { Client } from './shims/colyseus';
import type { RoomLike } from '../transport';

/**
 * 뷰마다 무엇이 보이는지 (관심영역).
 *
 * 진짜 StateView 는 인코더에 붙은 객체만 다루는데 여기엔 인코더가 없다. 그래서
 * add/remove 를 **프로토타입에서** 가로채 적어 두기만 한다. 인스턴스에서 가로채면
 * 안 된다 — ZoneRoom 은 `view.add(player)` 를 `client.view = view` 보다 먼저 불러서
 * 자기 캐릭터를 놓친다 (그러면 HP·위치가 영영 안 온다).
 * 이 청크는 로컬 모드에서만 받으므로 네트워크 모드에는 영향이 없다.
 */
const visibleByView = new WeakMap<object, Set<object>>();
function visibleOf(view: object): Set<object> {
  let set = visibleByView.get(view);
  if (!set) visibleByView.set(view, (set = new Set()));
  return set;
}
StateView.prototype.add = function (this: StateView, obj: object) {
  visibleOf(this).add(obj);
  return true;
} as typeof StateView.prototype.add;
StateView.prototype.remove = function (this: StateView, obj: object) {
  visibleOf(this).delete(obj);
  return this;
} as typeof StateView.prototype.remove;

function wire<T>(message: T): T {
  return message === undefined ? message : JSON.parse(JSON.stringify(message));
}

function sessionId(): string {
  return Math.random().toString(36).slice(2, 11);
}

/** 클라이언트가 쥐는 쪽 — @colyseus/sdk 의 Room 과 같은 모양 */
class LocalRoom implements RoomLike {
  constructor(id: string, host: LocalRoomHost) {
    this.sessionId = id;
    this.host = host;
  }
  readonly sessionId: string;
  private readonly host: LocalRoomHost;
  private readonly messageHandlers = new Map<string, (message: any) => void>();
  private stateHandler: ((state: any) => void) | undefined;
  private leaveHandler: ((code: number) => void) | undefined;
  left = false;

  send(type: string, message?: unknown): void {
    if (this.left) return;
    const copy = wire(message);
    setTimeout(() => this.host.receive(this.sessionId, type, copy));
  }

  onMessage(type: string, callback: (message: any) => void): void {
    this.messageHandlers.set(type, callback);
  }

  onStateChange(callback: (state: any) => void): void {
    this.stateHandler = callback;
  }

  onError(_callback: (code: number, message?: string) => void): void {
    // 로컬에서는 선로 오류가 없다. 핸들러 예외는 콘솔에 남는다
  }

  onLeave(callback: (code: number) => void): void {
    this.leaveHandler = callback;
  }

  async leave(): Promise<void> {
    if (this.left) return;
    this.left = true;
    this.host.leave(this.sessionId);
    this.leaveHandler?.(1000);
  }

  deliver(type: string, message: unknown): void {
    const copy = wire(message);
    setTimeout(() => {
      if (this.left) return;
      const handler = this.messageHandlers.get(type);
      if (handler) handler(copy);
      else console.warn(`[local] 받는 쪽이 없는 메시지: ${type}`);
    });
  }

  deliverState(state: unknown): void {
    if (!this.left) this.stateHandler?.(state);
  }
}

interface Seat {
  client: Client;
  room: LocalRoom;
}

/** 서버 쪽 — ZoneRoom 인스턴스 하나를 굴린다 */
class LocalRoomHost {
  constructor(zoneKey: string, options: Record<string, unknown>, onEmpty: () => void) {
    this.zoneKey = zoneKey;
    this.onEmpty = onEmpty;
    this.room = new ZoneRoom();
    this.room.onCreate(options);
    this.patchTimer = setInterval(() => this.patch(), this.room.patchRateMs);
  }
  readonly zoneKey: string;
  private readonly onEmpty: () => void;
  private readonly room: ZoneRoom;
  private readonly seats = new Map<string, Seat>();
  private readonly patchTimer: ReturnType<typeof setInterval>;

  async join(options: Record<string, unknown>): Promise<LocalRoom> {
    const id = sessionId();
    const room = new LocalRoom(id, this);
    const client: Client = {
      sessionId: id,
      send: (type, message) => room.deliver(type, message),
    };

    const auth = await this.room.onAuth(client, options);
    this.room.clients.push(client);
    this.seats.set(id, { client, room });
    try {
      this.room.onJoin(client, options, auth);
    } catch (err) {
      this.leave(id);
      throw err;
    }
    // 접속 직후 한 번 — 네트워크에서도 첫 상태는 join 직후에 온다
    setTimeout(() => this.patchOne(this.seats.get(id)));
    return room;
  }

  receive(id: string, type: string, message: unknown): void {
    const seat = this.seats.get(id);
    if (!seat) return;
    const handler = this.room.messageHandlers.get(type);
    if (!handler) {
      console.warn(`[local] 서버에 등록되지 않은 메시지: ${type}`);
      return;
    }
    try {
      handler(seat.client, message);
    } catch (err) {
      console.error(`[local] '${type}' 처리 중 오류`, err);
    }
  }

  leave(id: string): void {
    const seat = this.seats.get(id);
    if (!seat) return;
    this.seats.delete(id);
    const index = this.room.clients.indexOf(seat.client);
    if (index >= 0) this.room.clients.splice(index, 1);
    this.room.onLeave(seat.client);
    if (this.seats.size === 0) this.dispose();
  }

  private dispose(): void {
    clearInterval(this.patchTimer);
    if (this.room.simulationTimer !== undefined) clearInterval(this.room.simulationTimer);
    this.room.onDispose?.();
    this.onEmpty();
  }

  private patch(): void {
    for (const seat of this.seats.values()) this.patchOne(seat);
  }

  private patchOne(seat: Seat | undefined): void {
    if (!seat) return;
    const state = this.room.state;
    const visible = seat.client.view ? visibleOf(seat.client.view) : new Set<object>();
    const players = new Map<string, unknown>();
    state.players.forEach((p: object, key: string) => {
      if (visible.has(p)) players.set(key, p);
    });
    const monsters = new Map<string, unknown>();
    state.monsters.forEach((m: object, key: string) => {
      if (visible.has(m)) monsters.set(key, m);
    });
    seat.room.deliverState({ zoneId: state.zoneId, players, monsters });
  }
}

class LocalServer {
  private readonly hosts = new Map<string, LocalRoomHost>();

  async joinOrCreate(roomName: string, options: Record<string, unknown>): Promise<LocalRoom> {
    if (roomName !== 'zone') throw new Error(`없는 룸: ${roomName}`);
    const key = String(options.zoneId ?? '');
    let host = this.hosts.get(key);
    if (!host) {
      const created: LocalRoomHost = new LocalRoomHost(key, options, () => {
        if (this.hosts.get(key) === created) this.hosts.delete(key);
      });
      host = created;
      this.hosts.set(key, host);
    }
    return host.join(options);
  }
}

export const localServer = new LocalServer();

/**
 * 검증용 — 콘솔에서 서버 상태를 글로 읽는다 (docs/features/local-mode.md).
 * dev 에서 모듈을 다시 import 하면 HMR 주소(?t=)가 달라 **빈 새 인스턴스**를 받는다.
 */
(globalThis as { __localServer?: LocalServer }).__localServer = localServer;
