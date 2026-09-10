# 검증 방법

## 원칙

**글로 확인한다. 스크린샷은 정말 눈으로 봐야 할 때 한 장만.**

이유가 둘이다.

1. **비용** — 스크린샷 한 장이 토큰 천 단위다. 같은 확인을 텍스트로 하면 수십 단위다.
2. **정확도** — 브라우저 창이 가려지면 `requestAnimationFrame` 이 0~1Hz 로 떨어진다.
   화면은 낡은 채로 굳고, 그 좌표를 보고 클릭하면 엉뚱한 자리를 누른다.
   실제로 이것 때문에 같은 검증을 여섯 번 반복하고 "버그다"라고 오진한 적이 있다.
   서버 상태와 DOM 은 그런 것과 무관하게 항상 지금 값이다.

**남긴다.** 확인한 내용은 `logs/` 아래 파일로 남는다. 나중에 "그때 뭐가 나왔더라"를
다시 굴려보지 않아도 되게.

## 도구

| 도구 | 무엇을 보나 |
|---|---|
| `npm run probe -- <명령>` (`scripts/probe.mjs`) | **서버 로직** — 접속해서 상태·전투·아이템·메시지를 글로 찍는다 |
| `scripts/ui-probe.js` | **클라이언트 UI** — DOM 을 글로 뽑는 조각 모음 (콘솔에 붙여 넣는 용도) |
| `logs/server.log` | 서버 출력. `npm run server` 와 `npm run dev` 의 자동 실행이 남긴다 |
| `scripts/db-peek.mjs` | 저장된 캐릭터를 훑는다 |
| `npm test` | 데이터 규칙 전수 검사 |

## 헤드리스 클라이언트 (`probe.mjs`)

화면 없이 진짜로 접속한다. 캐릭터가 없으면 사람과 같은 순서로 만들고 고른다 —
서버에 검증용 예외 경로를 뚫지 않는다.

```bash
npm run probe -- state --zone meadow            # 내 상태 / 가방 / 장비 / 주변 몬스터
npm run probe -- fight --rounds 3 --zone meadow # 클릭 추격으로 싸우며 타격·치명타 집계
npm run probe -- send npcBuy w_archer_06        # 아무 메시지나 보내고 결과를 본다
npm run probe -- watch --seconds 20             # 상태 변화를 지켜본다
```

옵션: `--zone --token --character --name --job --server --rounds --seconds --log --quiet`

- 토큰 없이 돌리면 **게스트로 새 캐릭터**를 만든다. 깨끗한 상태에서 보고 싶을 때 좋다.
- 기존 캐릭터로 보려면 `--token`(브라우저 `localStorage['mmo:token']`)과 `--character` 를 준다.
  **토큰은 자격증명이다. 저장소에 커밋하지 않는다.**
- 결과는 `logs/probe-<명령>-<시각>.log` 로 남는다.

실제 출력 (클릭 추격 + 치명타 확인):
```
--- 1회차: mob003 hp 100, 21.8m ---
[대상] 3aa7b06d-...
  거리 20.7m 대상 hp 100 내 hp 100
  거리 8.4m  대상 hp 58  내 hp 100
[처치] 3aa7b06d 마지막 28
[보상] 들늑대 +31 exp
타격 24회 · 치명타 3회 (12.5%) · 누적 피해 437
```

## UI 확인 (`ui-probe.js`)

`javascript_tool` / 브라우저 콘솔에 **함수 본문을 골라 붙여 넣는다.** 들어 있는 것:

- `summary()` — 존, HP, 열린 창, 말걸기 프롬프트, 자동사냥 상태, 물고 있는 대상, 최근 채팅
- `bag()` — 골드, 칸 수, 장비 툴팁, 각 칸 이름, 상세, 옵션 칩과 범위
- `npc()` — NPC 창 섹션과 줄 전부
- `layout()` — 각 요소의 위치·`pointer-events`·화면 밖 여부 (모바일 확인용)
- `hitTest(sel)` — 그 자리를 누르면 정말 그게 눌리는지
- `tap(sel)` — 손가락 탭을 흉내내 실제 히트 테스트를 거쳐 누른다

주의: **rAF 로만 갱신되는 값**(이름표 화면 좌표, 쿨타임 표시, 말걸기 프롬프트)은
창이 가려져 있으면 낡은 값이다. 그것들을 봐야 하면 창을 앞으로 꺼낸 뒤
**같은 호출 안에서** 읽는다.

## 스크린샷을 찍어도 되는 때

- 새로 만든 화면의 **모양**을 사람이 봐야 할 때 (레이아웃, 색, 겹침)
- 텍스트로 설명이 안 되는 시각 효과
- 그때도 **한 장**. 여러 번 찍어 비교해야 하면 그건 대개 `layout()` 으로 풀린다.

## 저장된 데이터를 건드리는 검증

"죽은 채로 재접속" 처럼 **DB 상태를 만들어야 하는 검증**은 돌아가는 서버의 DB 를
건드리지 말고, 임시 DB 로 서버를 하나 더 띄워서 한다. 둘 다 환경변수로 갈린다:

```bash
PORT=2599 DB_PATH=<임시경로>/test.db node src/index.ts   # packages/server 에서
```

- **`DB_PATH` 는 cwd 상대경로(`data/game.db`)다.** 서버는 `packages/server` 에서
  도니까 실제 파일은 `packages/server/data/game.db` 인데, 저장소 루트에서 스크립트를
  돌리면 `DB_PATH` 를 안 주는 순간 **루트에 빈 DB 를 새로 만들고 거기에 쓴다.**
  에러가 안 나서 검증이 통과한 것처럼 보인다 — 2026-09-07 에 이걸로 한 번 속았다.
- 고치기 전/후를 비교하려면 임시 서버 쪽 코드만 잠깐 되돌려 두 번 돌린다.
  같은 스크립트가 양쪽에서 다른 결과를 내야 원인이 맞다고 할 수 있다.

## 손댈 때

- 새 UI 창을 만들면 `ui-probe.js` 에 그 창을 뽑는 함수를 추가한다.
- 새 서버 메시지를 만들면 `probe.mjs` 의 `onMessage` 목록에 한 줄 추가한다.
  안 그러면 SDK 가 "onMessage() not registered" 경고만 뱉고 내용을 못 본다.

## 관련

[client-ui.md](client-ui.md) · [networking-state.md](networking-state.md) · [persistence.md](persistence.md)
