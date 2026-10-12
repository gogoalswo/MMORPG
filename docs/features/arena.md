# 결투장

## 무엇

남의 캐릭터 **복사본**과 AI 끼리 싸우는 콘텐츠. 내가 조종하지 않고, 실시간 PVP 도 아니다 — 상대 데이터는
서버가 주고 기기가 복사해 쓴다. **지금은 창과 더미 상대 50명까지만 있다. 결투(AI 대 AI)는 아직 없다.**

2026-10-12 요청: "결투장 컨텐츠 만들어. 샌드백 때리는 것 처럼 내가 조종하는게 아니라 AI로 만들어서 서로 싸우게
할거야. 상대방 데이터는 서버에서 받아서 복사해서 사용할거야. 실시간 PVP가 아니라는 말이야. 일단 HUD에 결투장 버튼을
만들고, 해당 버튼을 누르면 전체 페이지로 결투장 UI가 나오는거야. 랭킹도 있고, 스크롤로 내가 도전할 도전자 목록이 나오면
좋겠어. 일단 더미로 50개 만들어. 여기까지 우선 진행해".

```
 메뉴 판(≡) [결투장] ─▶ ┌ 결투장 ───────────────────────────────────────────── X ┐
                        │ 상대 캐릭터의 복사본과 자동으로 겨룹니다.                 │
                        │ ┌ 나  Lv.30 ─────────┐ │ 도전자 목록                 50명 │
                        │ │ 26위 / 51명 · 점수 1,000 │ ┌ 1 푸른늑대 Lv.35 전투력 … 점수 1,490 [도전] ┐ │
                        │ │ 전투력 67,393      │ │ │ 2 검은독수리 …                          │ │ ← 끌어 굴림
                        │ └────────────────────┘ │ └────────────────────────────────────────┘ │
                        │ 랭킹 (끌어 굴림)       │ 푸른늑대 님과의 결투는 준비 중입니다.       │
                        │ 1 푸른늑대   1,490     │                                            │
                        └───────────────────────────────────────────────────────────────────┘
```

## 어디

| 파일 | 역할 |
|---|---|
| `godot/world/arena.gd` | `Arena` — 더미 50명(`dummies`) · 이름(`dummy_name`) · **표 하나**(`board` — 랭킹 · 도전자 · 내 줄). 서버와 로컬이 같이 쓴다 |
| `godot/game/arena_panel.gd` | `ArenaPanel` — 전체 화면 창. 왼쪽 내 기록 칸 + 랭킹, 오른쪽 도전자 목록 + 안내 줄. `fill(답)` · `open` · `close_panel` · 신호 `challenge_requested(id)` |
| `godot/game/game.gd` | 메뉴 칸 "결투장"(샌드백 옆) · `_toggle_arena`(같은 층 창 닫고 열기 · 열 때마다 `arenaBoard` 요청) · 이벤트 `arenaBoard` → `fill` · 다른 전체 화면 창을 열면 닫힌다 |
| `godot/net/local_transport.gd` | `arenaBoard` — 서버가 있으면 `ask_arena_board`, 없으면 `_local_arena_board`(`Arena.board(나)`) |
| `godot/net/server_ledger.gd` | `ask_arena_board` · 신호 `arena_listed` |
| `godot/server/ledger_server.gd` | `"arenaBoard"` → `_arena_board` — 그 계정 장부 + `name_of` 로 `Arena.board`. 인사 전이면 `no_hello` |
| `scripts/check-godot-assets.mjs` | `NO_ASSET` 에 `icons/ui_icon_arena.png` — 그림이 아직 없다 (아래) |
| `godot/tests/arena_test.gd` | 표(50명 · 이름 안 겹침 · 점수 순 · 나 26위 · 레벨 ± 5 · 1 ~ 만렙) · 서버 답 · 창(메뉴 판 안 · 전체 화면 · 랭킹 51 · 도전자 50 · 둘 다 굴림 · 줄 누르면 안내 · 글자 · 샌드백 창과 서로 닫음) |
| `godot/tests/ui_test.gd` | 메뉴 칸 수 12 → **13** |

## 규칙

### 표 — 답 하나 `arenaBoard` ★

```
{t: "arenaBoard", ranking: [줄 + rank (내 줄은 me: true)], challengers: [더미 줄 + rank],
 me: {rank, score, power, level, name}, total, dummy: true}
줄 = 상대 복사본 {id, name, job, level, score, power}
```

- **서버든 로컬이든 `Arena.board` 하나가 짓는다.** 창은 둘을 가리지 않는다. 진짜 상대를 붙일 때는
  `LedgerServer._arena_board` 에서 다른 계정의 장부를 복사해 `challengers` 로 싣고, 창은 그대로 둔다.
- 창을 열 때마다 새로 묻는다 (샌드백 순위와 같다).

### 더미 50명 (`DUMMY_COUNT`)

- **점수** 1490 → 510, 한 줄에 20씩 (`DUMMY_TOP_SCORE` · `DUMMY_SCORE_STEP`). 나는 `START_SCORE` 1000 이라
  **26위 / 51명** — 위로도 아래로도 상대가 보이게 가운데에 놓았다. 같은 점수면 더미가 앞.
- **레벨은 내 레벨 ± 5** (`DUMMY_LEVEL_SPREAD`), 점수가 높을수록 높다. 1 ~ 만렙으로 자른다.
  고정 레벨로 두면 1레벨이 200레벨만 보게 된다.
- **이름**은 앞말 10 × 뒷말 10 표를 겹친다 (`dummy_name` — 앞말 i % 10, 뒷말 (⌊i/10⌋×3 + i%10) % 10,
  50명이 안 겹친다). 글자는 폰트(완성형 2350자) 안이다 — 테스트가 본다.
- **전투력**은 자동 장착이 견주는 값 `Ledger.gear_power`(공격 기대값 × 유효 체력) 그대로다. 더미는 맨몸이고
  나는 낀 장비까지 들어간다. 1레벨 3만 · 30레벨 7만 · 200레벨 1,900만쯤.
- 직업은 `fighter` (지금 고를 수 있는 직업이 하나다). 화면에는 안 적는다.

### 창 — 전체 화면 ★

- 메뉴 판(≡) 안, **샌드백 옆**. "HUD 에 결투장 버튼" 이지만 평소 줄(`MENU_QUICK`)은 마을가기와 겹쳐서
  넷으로 묶어 뒀다 ([hud.md](hud.md) "메뉴 판") — 샌드백처럼 판 안에 넣었다.
- 헬스 · 도감 · 샌드백 · 상점 창과 같은 층(`GateLayer`) · 같은 결(돌판 틀 `ui_dungeon_card` + 뒤에 불투명한 판),
  오른쪽 위 X. 같은 층 창을 열면 서로 닫는다.
- 왼쪽 칸(440) — 내 기록(이름 · 레벨 / 순위 · 점수 / 전투력) 위, 랭킹(순위 · 이름 · 점수) 아래.
  **1 ~ 3위 밝은 금빛, 내 줄 청록** — 레벨 · 샌드백 랭킹과 같다.
- 오른쪽 — 도전자 목록. 한 줄이 어두운 칸(64 높이)에 순위 · 이름 · 레벨 · 전투력 · 점수 · **[도전]**(청록 돌판).
- 두 목록 다 **끌어서 굴린다** (`DragScroll`). DragScroll 은 칸의 **바로 아래 자식 `hit`** 만 누르므로,
  줄 전체를 덮는 투명한 `hit` 을 칸 바로 아래에 두고 보이는 [도전](`challenge`)은 그림으로 둔다 —
  줄 어디를 눌러도 도전이다. 처음엔 [도전] 단추를 `hit` 으로 줄 안에 넣었다가 안 눌리는 것을 짜면서 알았다.
- **도전을 누르면 안내 줄만 바뀐다** — "<이름> 님과의 결투는 준비 중입니다." 신호 `challenge_requested(id)` 는
  결투를 붙일 때 `game.gd` 가 받는다.

### 메뉴 그림이 아직 없다

HUD 아이콘은 바르코로 뽑는다 ([ui-art-style.md](ui-art-style.md) "HUD 아이콘 기준") — 이 세션에 바르코가 인증되지 않아
못 뽑았다. 그래서 메뉴 칸은 **글자 "결투장" 만** 서고 창 제목 문장도 숨는다(그림이 없으면 `visible = false`).
그림을 받으면 `assets-src/icons/ui_icon_arena.png` → 굽기 → `public/assets/icons/` 커밋 → `sync-godot-assets.mjs`
목록에 넣고, `check-godot-assets.mjs` 의 `NO_ASSET` 에서 뺀다.

## 아직 없는 것 (다음 단계)

- **결투** — 상대 복사본(장부: 레벨 · 장비 · 패시브 · 헬스 · 도감 · 트레이너)으로 몬스터 대신 캐릭터를 세우고 AI 끼리
  싸우게 한다. 판정은 기기, 결과 보고는 서버가 다시 본다 (샌드백 기록 검증과 같은 길 — [sandbag.md](sandbag.md)).
- **점수 · 순위** — 장부 칸이 없다 (나는 늘 1000점). 붙일 때 `Ledger.KEYS` · `fresh` · `World.join` · `restore` · `Save`.
- **진짜 상대** — 서버가 다른 계정 장부를 복사해 `challengers` 로 준다. 그때 더미는 서버가 없는 판(로컬)에만 남길지 정한다.
- 입장 횟수 · 보상 — 정하지 않았다.

## 관련

- [sandbag.md](sandbag.md) — 같은 층 전체 화면 창 · 순위 답 · 서버 기록 검증
- [hud.md](hud.md) — 메뉴 판
- [server.md](server.md) — 장부 요청 · 랭킹
- [inventory-equipment.md](inventory-equipment.md) — 전투력(`gear_power`)
