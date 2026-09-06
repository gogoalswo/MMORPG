import { Server } from 'colyseus';
import { ZONES } from '@mmo/shared';
import { ZoneRoom } from './ZoneRoom.ts';
import { countAccounts, pruneEmptyGuests, pruneTokens } from './db.ts';

const PORT = Number(process.env.PORT ?? 2567);

const gameServer = new Server();

/**
 * 존 하나당 룸 하나.
 * filterBy(['zoneId']) 덕분에 같은 zoneId 로 들어온 클라이언트는 같은 룸에 모인다.
 */
gameServer.define('zone', ZoneRoom).filterBy(['zoneId']);

const pruned = pruneTokens();
if (pruned > 0) console.log(`[db] 만료 토큰 ${pruned}개 정리`);

// 캐릭터를 안 만들고 떠난 빈 계정 정리 (하루 지난 것만)
const emptied = pruneEmptyGuests(1000 * 60 * 60 * 24);
if (emptied > 0) console.log(`[db] 빈 게스트 계정 ${emptied}개 정리`);

await gameServer.listen(PORT);
console.log(`[server] :${PORT} 대기 중 — 존 ${Object.keys(ZONES).join(', ')}`);
console.log(`[db] 계정 ${countAccounts()}개`);
