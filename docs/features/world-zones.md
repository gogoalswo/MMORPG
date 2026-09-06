# 존과 월드

## 무엇

마을 1개 + 사냥터 20개, 전부 같은 크기의 정사각 맵. 포탈로 이어진 사슬 구조.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/zones.ts` | 존 정의 21개 (**생성 코드**, 손으로 안 적는다) |
| `packages/shared/src/zone.ts` | `ZoneDef` 타입, 환경(하늘·안개·풀) 타입 |
| `packages/shared/src/zones.test.ts` | 포탈 짝, 도달 가능성, 레벨 순서 전수 검사 |
| `packages/client/src/scene/zoneScene.ts` | 존 하나를 3D로 세운다 |
| `packages/client/src/scene/{ground,grass,sky,portal,lighting}.ts` | 지면·풀·하늘·포탈·광원 |
| `packages/server/src/ZoneRoom.ts` | 존 하나 = Colyseus 룸 하나 |
| `scratchpad/gen_zones.py` | zones.ts 를 뽑아내는 생성기 (세션 스크래치패드) |

## 규칙

### 크기
- 모든 존 `size: 92`, 이동 가능 영역 ±42.
- 근거: FOV 30 / 거리 40 / 부각 42 에서 16:9 화면에 보이는 지면이 약 56.5유닛
  사각형이고, 그 **1.5배**가 되도록 맞췄다.
- 포탈은 `PORTAL = 34`, 도착 지점은 `ARRIVE = 26` (문 안쪽 8유닛).

### 사슬
```
마을 ─ 초원(1-10) ─ 덤불숲(10-20) ─ 협곡(20-30) ─ 잿빛황야(30-40) ─ … ─ 종말의 대지(190-200)
 │                                      │
 └────────────── 지름길 ────────────────┘
```
- 포탈은 북(0,-34) 남(0,34) 서(-34,0) 동(34,0) 네 자리에만 둔다.
- 사슬은 **서(뒤) ↔ 동(앞)** 으로만 잇는다.
- 도착 지점 이름은 들어온 방향을 쓴다 (`from_west`, `from_east`).
- 지름길 하나(`SHORTCUT_FROM=0` 초원 ↔ `SHORTCUT_TO=3` 잿빛 황야)는 처음 그린
  손그림 배치를 남긴 것이다. 저레벨이 30레벨대로 바로 넘어갈 수 있는 위험한 문.

### 보스 자리
- `BOSS_SPOT = [-12.0, 20.8]` — 중심에서 24유닛, **7시 방향**. 모든 사냥터 동일.
- `respawnMs: 900000` (15분), `count: 1`, `radius: 3`.

### 그 외
- **프랍(나무·바위)은 없다.** 전부 제거했다. 지형은 지면 + 풀 인스턴싱뿐이다.
- 마을은 안전지대(몬스터 스폰 없음). `zones.test.ts` 가 검사한다.
- `resolveZoneId(id)` — 없어진 존 id 가 저장돼 있으면 시작 존으로 떨어뜨린다.
  존을 지워도 캐릭터가 접속 불가가 되면 안 된다.

## 손댈 때

- 존을 추가/수정하려면 `zones.ts` 를 직접 고치기보다 생성 규칙을 고친다.
- 고친 뒤 `npm test` — 포탈 짝이 어긋나면 여기서 잡힌다. 눈으로는 못 잡는다.
- 존 개수를 바꾸면 [monsters-progression.md](monsters-progression.md) 의 티어 수,
  [items.md](items.md) 의 단계 접두어 20개가 같이 흔들린다.

## 관련

[monsters-progression.md](monsters-progression.md) · [networking-state.md](networking-state.md)
