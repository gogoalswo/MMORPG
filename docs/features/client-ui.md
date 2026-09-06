# 클라이언트 UI / HUD

## 무엇

3D 위에 얹히는 DOM 오버레이. 이름표, 피해 숫자, 액션바, 창들.

## 어디

| 파일 | 역할 |
|---|---|
| `packages/client/index.html` | `#game`(캔버스) / `#overlay` / `#stats` / `#help` |
| `packages/client/src/ui/style.css` | 전부. 레이아웃·테마·모바일 |
| `packages/client/src/ui/*.ts` | 창 하나당 클래스 하나 |
| `packages/client/src/main.ts` | 배선. 모든 콜백이 여기서 이어진다 |

## 규칙

### 오버레이 ★
`#overlay` 는 `pointer-events: none` 이다. 3D 클릭이 UI 를 통과해야 하기 때문이다.

**`pointer-events` 는 상속되는 속성이다.** 그래서 눌러야 하는 창은 CSS 에서
하나씩 `pointer-events: auto` 로 다시 켜야 한다. 목록에 없으면 화면에 멀쩡히
보이면서 눌리지 않는다 — PC 는 단축키로 가려지지만 폰에서는 그대로 조작 불가가 된다.

지금 켜 둔 것: `.actionbar .autohunt .autorange .npc-prompt .npc .bag .sb`

장식(이름표, 피해 숫자, 상태바, `#stats`)은 꺼진 채로 둔다.

### 이름표 / 피해 숫자
- 3D 텍스트가 아니라 HTML 오버레이다. 폰트가 또렷하고 드로우콜을 안 늘린다.
- 카메라 뒤 / 70유닛 초과는 숨긴다 (DOM 갱신 비용).
- 이름은 거의 안 바뀌므로 달라졌을 때만 DOM 을 건드린다. 강조(`is-target`)도 마찬가지.
- 피해 숫자 종류: `deal` / `take` / `kill` / `gain`, 치명타는 `is-crit`
  (색은 그대로 두고 키운다 — 색까지 바꾸면 처치와 헷갈린다).

### 모바일 (`@media (max-width: 760px)`)
- 액션바(4칸)와 자동 사냥 버튼을 한 줄에 두면 화면 밖으로 밀려난다.
  폰에서는 자동 사냥을 **오른쪽 위**로 세우고, 아래에서부터
  상태바 → 액션바 → 자동사냥 → 범위 → 채팅 순으로 쌓는다.
- 창(가방·NPC·스킬)은 좌우 8px 여백만 두고 화면 폭을 채운다.
- `#help` 는 숨긴다 (WASD·휠·Enter 가 없다).
- `@media (pointer: coarse)` 에서 작은 스위치를 키운다 (`A` 15px → 22px).
- `touch-action: manipulation` — 두 번 두드리면 확대되는 동작과 눌림 지연 제거.

### 렌더 루프 주의 ★
`requestAnimationFrame` 은 화면이 가려지면 0~1Hz 다. 그래서:
- rAF 안에서만 하는 일(이름표 위치, 쿨타임 표시, 프롬프트 갱신)은 창이
  가려지면 멈춘다. **버그가 아니다.** 이걸로 여러 번 오진했다.
- 오래 안 그린 뒤에는 쌓인 시각 효과를 버린다(`dropStaleVisuals`, `STALL_MS`).
- 계속 돌아야 하는 로직은 서버에 둔다.

### 조작
- 좌클릭: **몬스터면 지목**(추격), 아니면 그 지점으로 이동. 누르고 있으면 계속 따라간다.
- WASD 이동, Q/E 카메라 회전, 휠 줌, 1~4 스킬, F 말걸기, I 가방, K 스킬창, Enter 채팅.
- Space 기본 공격은 남아 있지만 안내문에서는 뺐다 (클릭이 주 조작).

## 손댈 때

- 새 창을 만들면 **CSS 의 `pointer-events: auto` 목록에 추가**하고,
  모바일 media query 에도 넣는다.
- `main.ts` 배선을 잊지 말 것. 창 클래스의 `onXxx` 콜백을 안 이으면 버튼이
  조용히 아무 일도 안 한다.

## 관련

[inventory-equipment.md](inventory-equipment.md) · [npc-town.md](npc-town.md) · [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md)
