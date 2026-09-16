/**
 * 브라우저에서 `colyseus`(서버 패키지) 대신 쓰는 것.
 *
 * `ZoneRoom` 이 쓰는 만큼만 흉내 낸다: `onMessage` `broadcast` `clients`
 * `setSimulationInterval` `setPatchRate` `roomId`. 실제로 룸을 굴리는 건
 * `localServer.ts` 의 `LocalRoomHost` 다 — 여기는 서버 코드가 기대는 모양만 있다.
 *
 * 새 API 를 ZoneRoom 에서 쓰기 시작하면 여기도 같이 채워야 한다.
 * 안 채우면 `npm run typecheck` 가 클라이언트 쪽에서 잡는다.
 */
import type { StateView } from '@colyseus/schema';

export interface Client {
  readonly sessionId: string;
  view?: StateView;
  send(type: string, message?: unknown): void;
}

export type MessageHandler = (client: Client, message: any) => void;

export interface ClientArray extends Array<Client> {
  getById(sessionId: string): Client | undefined;
}

let roomSeq = 0;

export abstract class Room {
  declare state: any;
  readonly roomId = `local-${++roomSeq}`;
  readonly clients: ClientArray = Object.assign([] as Client[], {
    getById(this: Client[], sessionId: string) {
      return this.find((c) => c.sessionId === sessionId);
    },
  });

  /** @internal 호스트가 읽는다 */
  readonly messageHandlers = new Map<string, MessageHandler>();
  /** @internal 호스트가 읽는다 */
  patchRateMs = 50;
  /** @internal */
  simulationTimer: ReturnType<typeof setInterval> | undefined;

  onCreate?(options: any): void;
  onAuth?(client: Client, options: any): unknown;
  onJoin?(client: Client, options: any, auth?: any): void;
  onLeave?(client: Client): void;
  onDispose?(): void;

  onMessage(type: string, handler: MessageHandler): void {
    this.messageHandlers.set(type, handler);
  }

  broadcast(type: string, message?: unknown): void {
    for (const client of this.clients) client.send(type, message);
  }

  setPatchRate(ms: number): void {
    this.patchRateMs = ms;
  }

  setSimulationInterval(callback: (deltaMs: number) => void, ms = 16): void {
    if (this.simulationTimer !== undefined) clearInterval(this.simulationTimer);
    let last = performance.now();
    this.simulationTimer = setInterval(() => {
      const now = performance.now();
      callback(now - last);
      last = now;
    }, ms);
  }
}
