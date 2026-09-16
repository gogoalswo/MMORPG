# 로컬 모드 (서버 없이 브라우저 안에서)

## 무엇

게임 서버 없이 **같은 `ZoneRoom` 코드를 브라우저 안에서** 돌린다. GitHub Pages 에
올려 폰으로 화면·플레이를 확인하는 용도다. 서버를 붙이면 연결만 바뀌고 판정 코드는
그대로다.

- Pages 주소: `https://gogoalswo.github.io/MMORPG/` — 기본이 로컬 모드
- 같은 주소에서 실제 서버로: `...?server=wss://서버주소` (기억된다)
- 다시 로컬로: `...?server=local` (기억한 주소를 지운다)
- dev(`npm run dev`)에서 로컬 모드 보기: `http://localhost:5173/?server=local`

## 어디

| 파일 | 역할 |
|---|---|
| `packages/client/src/net/transport.ts` | `RoomLike`·`TransportClient` 인터페이스, `createTransport(url)` — `local` 이면 로컬, 아니면 `@colyseus/sdk` |
| `packages/client/src/net/connection.ts` | `resolveServerUrl` 이 `local` 을 고른다. `storageKey` 가 로컬용 토큰·캐릭터 키를 가른다 |
| `packages/client/src/net/local/localServer.ts` | 룸 호스트. 존별 룸, 메시지 배달, 상태 패치, 관심영역 |
| `packages/client/src/net/local/shims/colyseus.ts` | `Room` 기반 클래스 흉내 (`onMessage` `broadcast` `clients` `setSimulationInterval` `setPatchRate`) |
| `packages/client/src/net/local/shims/sqlite.ts` | `node:sqlite` 의 `DatabaseSync` → sql.js + IndexedDB |
| `packages/client/src/net/local/shims/crypto.ts` | `randomUUID` `randomBytes` `createHash('sha256')` |
| `packages/client/src/net/local/shims/node.ts` | `node:fs` `mkdirSync`, `node:path` `dirname` |
| `packages/client/vite.config.ts` | `resolve.alias` 로 위 대체물을 끼움, `base`, `process.env.DB_PATH` define |
| `packages/client/tsconfig.json` | `paths` — alias 와 **같은 표**. 클라이언트 tsc 가 서버 코드를 대체물 기준으로 검사한다 |
| `.github/workflows/pages.yml` | main push → typecheck·test·build(`VITE_SERVER_URL=local`, `VITE_BASE=/저장소/`) → Pages |

## 규칙

- **서버 코드는 고치지 않는다.** Node 전용 모듈(`colyseus` `node:sqlite` `node:crypto`
  `node:fs` `node:path`)만 alias 로 바꿔 끼운다. 로직을 클라이언트에 따로 짜면 서버를
  붙일 때 판정이 둘로 갈라진다.
- **서버·sql.js 는 별도 청크다** (`import('./local/localServer')`). 네트워크 모드는 받지 않는다.
  빌드 기준 localServer 85KB + sql-wasm 658KB.
- **DB 는 sql.js 로 같은 SQL 을 돌린다.** db.ts 를 키-값으로 새로 짜지 않으려고.
  DB 바이트 전체를 IndexedDB(`mmo-local` / `files` / `data/game.db`)에 넣는다.
  쓰기가 멎고 0.5초 뒤, 그리고 `pagehide` 때 저장한다.
- **토큰·캐릭터 키가 따로다** (`mmo:token:local`, `mmo:character:local`). 같은 키를 쓰면
  로컬 DB 가 모르는 서버 토큰을 보내 게스트가 새로 생기고, 그 토큰이 서버 토큰을 덮어쓴다.
- **메시지는 JSON 으로 복사하고 다음 태스크(setTimeout)에 배달한다.** 선로처럼
  `undefined` 가 빠지고, onJoin 중에 보낸 메시지가 클라이언트 핸들러보다 먼저 도착해
  버려지지 않는다.
- **상태는 직렬화하지 않고 서버 스키마 객체를 그대로 넘긴다.** 대신 관심영역에 든 것만
  골라 `{ zoneId, players, monsters }` 로 싼다. `ingest` 는 읽기만 한다.
- **관심영역은 `StateView.prototype.add/remove` 를 가로채 적는다.** 인스턴스에서 가로채면
  ZoneRoom 이 `view.add(player)` 를 `client.view = view` 보다 먼저 불러 **자기 캐릭터를
  놓친다** — HP·레벨이 영영 빈 채가 된다 (2026-09-16 밟음). 진짜 StateView 는 인코더가
  없어서 못 쓴다.
- **아무도 없는 룸은 버린다** (Colyseus autoDispose 와 같다). 존을 옮기면 이전 존의
  시뮬레이션이 멈춘다.

## 한계

- 혼자다. 다른 플레이어가 없고, 저장은 그 브라우저(IndexedDB)에만 남는다.
- 탭이 가려지면 `setInterval` 이 1Hz 로 느려져 세계 전체가 느려진다. 실제 서버와 다른 점이다.
- Google 계정 연결은 로컬 DB 에만 붙는다.

## 손댈 때

- **ZoneRoom 이 Colyseus·Node API 를 새로 쓰면** `shims/` 에도 채운다. 안 채우면
  `npm run typecheck` 의 클라이언트 쪽이 잡는다 (paths 가 서버 코드를 대체물로 검사하므로).
- alias(vite.config.ts)와 paths(tsconfig.json)는 **둘 다** 고친다.
- `process.env` 를 서버 코드에서 새로 읽으면 vite.config.ts `define` 에 넣는다.
- 에셋 경로는 `import.meta.env.BASE_URL` 을 앞에 붙인다. `/assets/...` 로 쓰면 Pages
  (`/MMORPG/` 아래)에서 404 다.
- Windows Git Bash 에서 `VITE_BASE=/MMORPG/` 로 빌드하면 경로가
  `C:/Program Files/Git/MMORPG/` 로 바뀐다. `MSYS_NO_PATHCONV=1` 을 붙인다.

## 확인

```js
// 콘솔 — 서버 상태를 글로
const s = __localServer; const [zone, host] = [...s.hosts][0];
const st = host.room.state; const out = [];
st.players.forEach(p => out.push([p.name, p.hp, p.maxHp, p.dead, p.exp]));
st.monsters.forEach(m => m.hp < m.maxHp && out.push([m.kind, m.hp, m.maxHp]));
JSON.stringify({ zone, out })
```

빌드 결과물을 Pages 경로 그대로: `.claude/launch.json` 의 `pages-preview`
(먼저 `MSYS_NO_PATHCONV=1 VITE_SERVER_URL=local VITE_BASE=/MMORPG/ npm run build`)
→ `http://localhost:4173/MMORPG/`.

## 관련

- [godot-migration.md](godot-migration.md) — 고도 이관. **이 로컬 모드 방식(브라우저가
  TS `ZoneRoom` 을 그대로 돌림)은 고도에서 쓸 수 없다.** 고도는 TS 를 실행할 수단이
  없어서 판정을 GDScript 로 한 벌 다시 쓴다. 같은 사이트의 `/game/` 에 나란히 올라간다

[networking-state.md](networking-state.md) · [persistence.md](persistence.md) · [verification.md](verification.md)
