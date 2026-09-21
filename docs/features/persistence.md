# 저장과 계정

## 무엇

`node:sqlite` (내장). 파일 하나: `packages/server/data/game.db`.

> **이 폴더는 gitignore 되어 있다. 절대 커밋하지 않는다.**

## 어디

| 파일 | 역할 |
|---|---|
| `packages/server/src/db.ts` | 스키마, 마이그레이션, 읽기/쓰기 전부 |
| `packages/server/src/auth.ts` | 토큰 검증, 게스트 계정 발급, Google 연동 |
| `packages/server/src/ZoneRoom.ts` | `persist(sessionId)` — 위치·상태를 남긴다 |
| `packages/client/src/net/local/shims/sqlite.ts` | **로컬 모드** — 같은 db.ts 를 sql.js 로 돌리고 IndexedDB 에 저장 (옛 local-mode.md(지워짐)) |

## 규칙

### 표
- `account` — 계정
- `auth_token` — **SHA-256 해시만** 저장한다. 원문 토큰은 남기지 않는다
- `character` — 캐릭터

`character` 컬럼: `id, account_id, name, job, zone_id, x, z, hp, max_hp, level, exp,
created_at, updated_at, gold, inventory, equipment, skills, skill_bar, skill_points`

### 마이그레이션
`CREATE TABLE IF NOT EXISTS` 는 표가 있으면 통째로 건너뛴다. 그래서 나중에 붙인
컬럼은 전부 `addColumnIfMissing(table, column, definition)` 으로 추가한다
(`PRAGMA table_info` 로 확인 후 `ALTER TABLE`).

지금까지 이렇게 붙은 것: `gold`, `inventory`, `equipment`, `skills`, `skill_bar`, `skill_points`.

### 값 복원 (`toStack`)
가방·장비는 JSON 문자열이다. 읽는 자리에서 **지금 규칙으로 다시 만든다.**
- 예전엔 아이템 id 문자열만 저장했다 → `{ id, grade: 1, enhance: 0 }` 으로 올린다.
- `grade` / `enhance` 는 범위로 자른다.
- `options` 가 **없으면(undefined) 한 번 굴려 붙인다.** 옵션이 생기기 전에 주운
  장비를 옵션 0개로 두면 영영 못 고치는 쓰레기가 된다. 한 번 굴리면 저장되므로
  다음 접속부터 그대로다. 빈 배열 `[]` 은 "굴려 봤는데 없다"는 뜻이라 다시 안 굴린다.
- 있으면 `sanitizeOptions` 로 지금 규칙에 맞게 자른다.

**깨진 값 하나 때문에 접속이 막히면 안 된다.** 못 읽으면 조용히 빈 값으로 떨어뜨린다.
가방을 잃는 건 아프지만 못 들어오는 것보단 낫다.

### 인증
- 토큰이 없거나 만료면 **게스트 계정을 새로 만든다.** 접속 자체는 절대 막지 않는다.
- Google 연동: `auth.ts` 가 `info.aud === GOOGLE_CLIENT_ID` 를 반드시 확인한다.
  클라이언트 ID 는 환경변수 `GOOGLE_CLIENT_ID` 로 넣는다.
  **클라이언트 시크릿은 이 설계에서 쓰지 않는다. 어디에도 넣지 말 것.**

## 손댈 때

- 저장 형식을 바꾸면 `toStack` 을 반드시 같이 고친다. 기존 캐릭터를 깨뜨리면 안 된다.
- 개발 중 DB 를 열어볼 때 주의: WAL 이 열려 있으면 다른 프로세스가 쓰는 중이다.
  복사할 거면 서버를 먼저 멈출 것.

## 관련

[items.md](items.md) · [networking-state.md](networking-state.md)
