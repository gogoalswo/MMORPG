# 자동 사냥과 클릭 추격

## 무엇

두 가지 "알아서 싸운다"가 있고, **같은 경로**를 탄다.
1. **자동 사냥** — 버튼으로 켠다. 켠 자리 주변을 돌며 알아서 고르고 싸운다.
2. **클릭 추격** — 몬스터를 클릭하면 그놈에게 붙어 죽을 때까지 때린다.

## 왜 서버가 하나 ★

`requestAnimationFrame` 은 탭을 옮기거나 폰에서 화면이 꺼지면 **0~1Hz 로 떨어진다.**
클라이언트가 몰면 그 순간 캐릭터가 그 자리에 선다. 그래서 판단·이동·공격을
전부 서버 틱에 얹었다. 이건 실제로 측정하고 내린 결정이다.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/autoHunt.ts` | 순수 계산 — `pickHuntTarget`, `standoffPoint`, 반경/리쉬 상수 |
| `packages/shared/src/autoHunt.test.ts` | 대상 선택·거리 계산 검사 |
| `packages/server/src/ZoneRoom.ts` | `driveAutoHunt` / `driveChase` / `engageTarget` / `stepAutoPlayer` / `handleTarget` |
| `packages/client/src/ui/autoHuntToggle.ts` | 토글 버튼 + 반경 슬라이더 |
| `packages/client/src/game/input.ts` | `pickTarget` — 지면보다 **먼저** 몬스터를 레이캐스트 |
| `packages/client/src/game/remoteMonsters.ts` | `idAt(object)` 맞은 메시 → 몬스터 id, `setHighlight` |

## 규칙

### 공유 경로 `engageTarget(client, player, target, dt)`
붙는다 → 바라본다 → 때린다. 자동 사냥과 클릭 추격이 **둘 다 이걸 부른다.**
```
stand = standoffPoint(..., attackRange * HUNT_STANDOFF)   // 0.7 — 꽉 채우면 조금만 움직여도 빠진다
stepAutoPlayer(player, stand, dt, target)                  // 걷고, 대상을 정확히 바라본다
tryAutoSkill(...) || (거리 <= attackRange && handleAttack(...))
```
- 때리는 건 사람이 눌렀을 때와 **똑같은** `handleAttack` / `handleSkill` 이다.
  쿨타임·정면각 검증을 두 벌 만들면 반드시 어긋난다.
- 서버가 `player.rotY` 를 직접 정한다. 클라이언트 이동으로는 "움직인 방향"밖에
  못 정해서 옆구리로 굳는다.

### 자동 사냥
- `player.auto` (스키마 필드). 켠 자리를 `autoAnchor` 로 잡는다.
  앵커가 없으면 몬스터를 따라 맵 끝까지 끌려간다.
- 반경은 사람이 조절: `HUNT_RADIUS = 22`, 범위 `6~40`. 슬라이더 값은
  `localStorage['mmo.autoRange']`, 서버가 `clampHuntRadius` 로 다시 자른다.
- `huntLeash(r) = r + 8` — 잡고 있던 대상은 리쉬 안에서 계속 잡는다.
  같으면 경계에 걸친 몬스터를 잡았다 놓았다 반복한다.
- 대상이 없으면 앵커로 돌아가 기다린다.
- **자동 시전 전용 모드**: 자동 사냥이 꺼져 있어도 `A` 켠 스킬이 있으면
  `casting` 모드로 같은 경로를 탄다. 앵커가 "지금 서 있는 자리"라 돌아가지 않는다.

### 클릭 추격
- 메시지 `target` (id 또는 null) → `handleTarget`. 스키마 필드 `player.chasing`.
- 앵커는 **지목한 순간 그놈이 서 있던 자리**. 플레이어 자리로 재면 멀리 보이는
  놈을 눌렀을 때 누르자마자 풀린다. 여기서 재는 건 "대상이 얼마나 도망쳤나"다.
- `CHASE_LEASH = 45` 를 벗어나거나, 대상이 죽거나, 내가 죽으면 놓는다.
- 푸는 방법: 땅 클릭 / WASD 이동 / 자동 사냥 켜기.
- 서버가 `target` 메시지로 지정·해제를 **다시 알려준다.** 클라이언트가
  `chasing` 상태만 보고 표시를 지우면 보낸 직후 한 틱 깜빡인다.
- 자동 사냥과 겹치면 자동 사냥이 주인이다. `driveAutoHunt` 는 추격 중인
  세션을 건너뛴다(`this.chase.has(id)`).

### 토글 버튼 표시
- `AutoHuntToggle.setOn` 은 받은 값을 `!!` 로 굳혀서 쓴다. `classList.toggle` 의
  두 번째 인자가 `undefined` 면 강제 지정이 아니라 뒤집기가 되어, 상태 패치마다
  버튼이 깜빡인다. 서버가 `player.auto` 를 생성 시점에 `false` 로 대입하지 않으면
  실제로 그 값이 내려온다 — [networking-state.md](networking-state.md) 참고.
- 클래스(`is-on`)와 글자(켜짐/꺼짐)를 **같은 값**으로 쓴다. 둘이 어긋나 보이면
  (초록인데 "꺼짐") 누군가 클래스만 따로 건드린 것이다.

### 클라이언트가 하는 일
- `myState.auto || myState.chasing` 이면 **예측을 멈추고** 서버 위치를 따라간다.
  양쪽이 동시에 움직이면 보정이 계속 싸워서 캐릭터가 떨린다.
- 그래서 **자동 사냥 버튼은 이동 동기화가 깨졌는지 알려주는 계기판이기도 하다.**
  켜자마자 엉뚱한 자리로 튀면 자동 사냥이 아니라 그 전부터 서버와 내 위치가
  달랐던 것이다 — 예측을 멈추는 순간 그 차이가 한 번에 드러날 뿐이다.
  이동 입력이 서버에서 버려지고 있는지부터 본다
  ([networking-state.md](networking-state.md) 의 `seq` 규칙).
- 클릭 레이캐스트는 몬스터 그룹을 지면보다 먼저 본다. 죽은 몬스터는 안 잡힌다.
- 물고 있는 대상은 이름표를 금색으로 밝힌다(`.nameplate.is-target`).

## 손댈 때

- 새 "알아서 싸운다"를 만들면 `engageTarget` 을 재사용할 것. 붙는 거리·바라보는
  각·쿨타임을 다시 쓰면 한쪽만 고치는 실수가 난다.
- 서버가 이동을 모는 모드를 추가하면 `handleInput` 의 무시 조건과 클라이언트의
  예측 정지 조건을 **둘 다** 고쳐야 한다.

## 관련

[combat.md](combat.md) · [skills.md](skills.md) · [networking-state.md](networking-state.md)
