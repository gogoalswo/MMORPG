# 네트워크와 상태 동기화

## 무엇

Colyseus 0.18. 존 하나 = 룸 하나. 서버 권위 + 클라이언트 예측/보정.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/server/src/state.ts` | 동기화 스키마 (`Player`, `Monster`, `ZoneState`) |
| `packages/server/src/ZoneRoom.ts` | 룸 본체. 메시지 핸들러 전부 |
| `packages/server/src/index.ts` | 서버 부팅, 존별 룸 등록 |
| `packages/client/src/net/connection.ts` | 접속·메시지·보간 샘플링 |
| `packages/client/src/game/player.ts` | 예측(`applyMove`)과 보정(`reconcile`) |
| `packages/shared/src/constants.ts` | `TICK_RATE`, `INTERP_DELAY_MS`, `RUN_SPEED` 등 |
| `packages/shared/src/movement.ts` | `applyMove` — **서버와 클라가 같은 함수를 쓴다** |

## 규칙

### 기본 수치
- `TICK_RATE = 15` (틱 66.7ms), 패치도 같은 주기.
- `INTERP_DELAY_MS = 120` — 남을 그릴 때 120ms 과거를 재생하며 보간한다.
- `RUN_SPEED = 4.6`, `AOI_CELL_SIZE = 32`.

### 스키마
- `Player`: id, name, job, x, z, rotY, hp/maxHp, level, exp, dead,
  **auto**(자동 사냥), **chasing**(클릭 추격), lastSeq.
- `Monster`: id, kind, x, z, rotY, hp/maxHp, state(idle|chase|attack|dead).
- 좌표는 `float32` — 월드가 ±110이라 정밀도는 충분하고 대역폭은 절반.
- **데코레이터를 쓰지 않는다.** `schema()` / `t.*` 함수형 정의라야 Node 가
  타입만 벗겨 그대로 실행할 수 있다(빌드 단계 없음).
- **불리언은 만들 때 반드시 대입한다.** 스키마 불리언은 한 번도 대입하지 않으면
  `false` 가 아니라 `undefined` 로 남아 그대로 내려간다. 클라이언트에서
  `classList.toggle(cls, undefined)` 는 강제 지정이 아니라 **뒤집기**라서,
  상태 패치마다(≈20Hz) 클래스가 뒤집혀 버튼이 깜빡인다 — 2026-09-06 자동 사냥
  버튼이 이걸로 깜빡였다. `ZoneRoom` 의 플레이어 생성부에서 `auto`/`chasing`/`dead`
  를 전부 대입하고, 받는 쪽 `ingest` 에서도 `?? false` 로 한 번 더 메운다.

### 관심영역 (StateView)
- `players` / `monsters` 맵에 `.view()` 를 걸어, 클라이언트별 `StateView` 에
  등록된 것만 내려간다. 자기 자신은 거리와 무관하게 항상 보인다.
- `SpatialGrid` 로 주변 셀만 조회한다.

### 이동 예측/보정
1. 클라이언트가 매 프레임 `applyMove` 로 자기 위치를 먼저 옮기고 `input` 을 보낸다.
2. 서버가 같은 `applyMove` 로 검증·적용하고 `lastSeq` 를 돌려준다.
3. `reconcile` 이 서버 위치에서 시작해 **아직 확인 안 된 입력만** 다시 적용하고,
   차이만큼 `CORRECTION_RATE = 0.25` 로 당긴다. 2.5유닛 넘게 어긋나면 스냅.
- **정지 중에도 입력을 보낸다.** 안 보내면 서버가 마지막 순번을 확인해 주지 않아
  보정 기준점이 멈춘다.
- **`seq` 는 접속 하나에서 단조 증가만 한다. 절대 0 으로 되돌리지 않는다.** ★
  서버는 `seq <= player.lastSeq` 를 지연 도착한 중복 패킷으로 보고 버린다.
  클라이언트가 번호를 되돌리면 서버가 그 번호를 따라잡을 때까지 이동이 전부
  버려지고, 클라이언트만 혼자 걸어가다 보정에 끌려 스폰 지점으로 순간이동한다.
  로그인·캐릭터 선택 화면에 머무는 동안에도 매 프레임 번호를 하나씩 쓰므로
  (60fps 면 초당 60), 화면에 오래 머물수록 먹통 구간이 그만큼 길어진다.
  2026-09-06 `Player.teleport()` 가 `seq = 0` 을 해서 이 증상이 났다.
  존을 옮기면 서버가 새 `Player` 를 만들며 `lastSeq` 를 0 으로 두므로,
  클라이언트 번호가 계속 커져도 문제가 없다.
- 서버가 이동을 모는 동안(`auto` 또는 `chasing`)에는 클라이언트가 예측을 멈춘다.

### 메시지 목록 (클라 → 서버)
`input` `chat` `attack` `target` `autohunt` `autoSkills` `autoRange` `skill`
`learnSkill` `setSkillBar` `equip` `unequip` `craft`
`npcOpen` `npcBuy` `npcSell` `npcForge` `npcEnhance` `npcJob`
`createCharacter` `selectCharacter` `deleteCharacter` `setJob` `linkGoogle`

### 메시지 목록 (서버 → 클라)
`hit` `aoe` `swing` `skill` `notice` `reward` `levelUp` `inventory` `skills` `npc`
`loot` `respawn` `target` `enhanceResult` `jobChanged` `chat` `session`
`needsCharacter` `createResult` `characterList` `switchZone` `linkResult`

- `aoe` — 보스 범위 공격 예고 `{ id, name, x, z, radius, delayMs }`. **보여주기 전용**이다.
  누가 맞았는지는 터질 때 `hit` 이 따로 알려준다 → [combat.md](combat.md).

## 손댈 때

- 스키마에 필드를 더하면 클라이언트 `ingest`(connection.ts)와 `SelfStatus` 도 같이 고친다.
- 새 메시지를 추가하면 **서버 `onMessage` 등록 / 클라 `send` 래퍼 / `main.ts` 배선**
  세 군데다. 한 군데를 빼먹으면 조용히 아무 일도 안 일어난다.

## 관련

[auto-hunt-and-targeting.md](auto-hunt-and-targeting.md) · [combat.md](combat.md) · [persistence.md](persistence.md)
