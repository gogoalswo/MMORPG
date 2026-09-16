/**
 * ZoneConnection 이 서버와 말하는 통로.
 *
 * 구현이 둘이다.
 * - 네트워크: `@colyseus/sdk` 의 Client — 실제 게임 서버(wss://)에 붙는다.
 * - 로컬: `local/localServer.ts` — **같은 ZoneRoom 코드를 브라우저 안에서** 돌린다.
 *   서버 없이 GitHub Pages 에서 혼자 돌려 보는 용도다.
 *
 * ZoneConnection 은 어느 쪽인지 모른다. 판정 코드는 서버(ZoneRoom) 하나뿐이다.
 */
import { Client } from '@colyseus/sdk';

export interface RoomLike {
  readonly sessionId: string;
  send(type: string, message?: unknown): void;
  onMessage(type: string, callback: (message: any) => void): unknown;
  onStateChange(callback: (state: any) => void): unknown;
  onError(callback: (code: number, message?: string) => void): unknown;
  onLeave(callback: (code: number) => void): unknown;
  leave(): Promise<unknown>;
}

export interface TransportClient {
  joinOrCreate(roomName: string, options: Record<string, unknown>): Promise<RoomLike>;
}

/** `?server=local` 이나 빌드 기본값 `VITE_SERVER_URL=local` 이면 이 값이 된다 */
export const LOCAL_SERVER = 'local';

export function createTransport(serverUrl: string): TransportClient {
  if (serverUrl !== LOCAL_SERVER) {
    const client = new Client(serverUrl);
    return { joinOrCreate: (name, options) => client.joinOrCreate(name, options) as Promise<RoomLike> };
  }
  return {
    // 서버 코드와 sql.js 는 로컬 모드일 때만 받는다 (별도 청크)
    async joinOrCreate(name, options) {
      const { localServer } = await import('./local/localServer');
      return localServer.joinOrCreate(name, options);
    },
  };
}
