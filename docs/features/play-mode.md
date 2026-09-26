# 시작 모드 · 치트 목록 여닫기

## 무엇

게임을 켜면 **테스트 모드 / 일반 모드** 를 고르는 화면이 먼저 뜬다 (2026-09-25 요청).

| 모드 | 켜지는 것 | 왼쪽 치트 목록 |
|---|---|---|
| 테스트 모드 | **무적 · 스킬 쿨타임 0 · 장비 42개(+0)와 크리스탈 300개** | 접힌 채 시작 — 채팅창 위 **"치트 목록 열기"** 단추로 편다 |
| 일반 모드 | 없음 (캐릭터만 만들어 시작) | 목록도 여닫기 단추도 안 보인다 |

같은 날 요청으로 **치트 목록을 단추 하나로 접고 편다** — 단추 열 개가 왼쪽을 다 덮었다.

모드를 고르면 **로딩 막**이 덮였다가, 게임이 다 지어지면 **페이드 아웃**으로 걷힌다
(2026-09-26 요청: "로딩 끝나면 페이드 아웃으로 게임 스르륵 보이게").

## 어디

| 파일 | 역할 |
|---|---|
| `godot/start.tscn` · `godot/game/start_screen.gd` | 시작 화면. 단추 둘, 누르면 `PlayMode.current` 에 적고 `main.tscn` 으로 넘어간다 |
| `godot/game/loading_screen.gd` | `LoadingScreen` — 로딩 막. 루트에 달린 `CanvasLayer`(층 100)라 장면을 바꿔도 남는다 |
| `godot/game/play_mode.gd` | `PlayMode` — 고른 모드(`static var current`). 장면을 바꿔도 남는다 |
| `godot/game/game.gd` `_apply_play_mode` | 모드를 건다 — 테스트면 `invincible` · `testSwitch cooldownOff` 를 보낸다 |
| `godot/game/game.gd` `_cheat_toggle` · `_set_cheats_open` | 치트 목록(`_cheat_column`) 여닫기 |
| `godot/project.godot` | `run/main_scene = res://start.tscn` |
| `godot/world/world.gd` `grant_test_kit` | 테스트 모드 꾸러미 — 장비 42개(+0) · 크리스탈 300개, 한 번만 |
| `godot/tests/play_mode_test.gd` | 두 모드에서 무적·쿨타임·목록 상태, 테스트 모드 꾸러미를 본다 |
| `godot/tests/loading_screen_test.gd` | 누르면 막이 덮이고, 게임이 뜰 때까지 남았다가, 서서히 걷혀 지워지는지 본다 |

## 규칙

- **모드를 거는 건 게임 쪽이다.** 시작 화면은 고르기만 한다. 무적·쿨타임은 버튼으로
  켜던 것과 **같은 요청**(`invincible`, `testSwitch`)을 보낸다 — 판정 경로가 하나다.
- **모드 없음(`""`)은 테스트·도구용이다.** 테스트 스무 편과 `shot.gd` 가 `main.tscn` 을
  바로 띄우므로, 시작 화면을 안 거치면 **아무것도 켜지 않고 목록은 펼친 채** 둔다.
  그래서 기존 테스트는 손대지 않고 돈다 (`ui_test` 는 단추 자리를 본다).
- **테스트 모드의 목록은 접혀서 시작한다.** 펼치면 왼쪽이 다시 덮이기 때문이다.
- **테스트 모드 꾸러미** (2026-09-26 요청: "모든 장비 등급별로 하나씩 넣어. 0강으로.
  크리스탈로 300개 넣고") — 등급 7 × 부위 6 = **42개, 전부 +0**, 옵션은 드랍처럼 그
  등급대로 굴린다. 크리스탈 300개는 한 칸에 겹친다. `testKit` 요청 → `World.grant_test_kit`.
  **한 번만 준다** — 받으면 저장의 `granted` 에 `testKit` 이 남는다. 매번 주면 테스트
  모드로 들어올 때마다 가방이 42칸씩 불어난다. 다시 받으려면 저장을 지운다.
  가방(200칸)에 다 안 들어가면 **아무것도 안 넣고** 다음에 다시 준다.
  모두에게 주는 크리스탈 30개(`crystal30`)와는 따로라 처음 들어오면 330개가 된다.
- **일반 모드는 무적·쿨타임을 끄는 요청을 보내지 않는다.** 둘 다 저장되지 않아
  (`invincible` 은 존 이동에만 이어진다, `cooldownOff` 는 `skills.json` 기본값 `false`)
  새로 켜면 이미 꺼져 있다. 끄는 요청을 보내면 "무적 끔" 알림만 괜히 뜬다.
- **여닫기 단추 자리** — 채팅창 바로 위, 묶음은 그 위 (`lift += CHEAT_TOGGLE.y + 6`).
- 글자에 `▲▼` 를 쓰지 않는다 — 한글 부분집합 글꼴(`NotoSansKR-subset.ttf`)에 없다.

### 로딩 막 ★

순서: 누름 → 단추 잠금·막 덮기 → **두 프레임 기다림** → `change_scene_to_file` →
새 장면 `_ready` 끝 → **프레임이 가라앉을 때까지** 더 덮음 → 0.8초 페이드 아웃 → 막 지움.

- **왜 오래 걸리나** — `game.gd` 의 `_ready` 가 존·캐릭터·이펙트 풀(`FxPool.fill`)을
  **한 프레임 안에서** 다 짓는다. 그동안 화면이 굳는다.
- **진행률이 없다** — 웹 빌드는 스레드를 껐다(`export_presets.cfg` 의 `thread_support=false`).
  백그라운드 로딩(`load_threaded_request`)을 못 쓰니 몇 % 인지 알 수 없다. 그래서 막대 대신
  금줄 위로 밝은 조각이 흐른다("멈추지 않았다" 는 표시). 짓는 동안은 이것도 멈춘다.
- **두 프레임 기다리는 이유** — 막이 한 번 그려진 다음에 무거운 일을 시작해야 한다. 바로
  넘기면 누른 시작 화면이 굳은 채 보인다. `RenderingServer.frame_post_draw` 는 헤드리스에서
  오지 않아 테스트가 멈추므로 `process_frame` 두 번으로 한다.
- **`_ready` 뒤에도 더 덮는 이유** — 첫 몇 프레임은 셰이더를 굽느라 끊긴다. 프레임 간격이
  `SETTLE_DELTA`(1/20초) 이하로 `SETTLE_FRAMES`(4) 번 연속 돌면 걷는다. 느린 기기에서
  안 가라앉아도 `SETTLE_MAX_MS`(4초) 뒤에는 걷는다.
- **걷히기 시작하면 바로 누를 수 있다** — 페이드가 시작될 때 막의 `mouse_filter` 를 푼다.
- 테스트·`shot.gd` 는 `main.tscn` 을 바로 띄우므로 막을 안 거친다.

## 손댈 때

- 테스트 단추를 더하면 `_build_test_switches` 의 `column` 에 넣는다 — 그래야 같이 접힌다.
- 테스트 모드에서 켤 것·줄 것을 늘리면 `_apply_play_mode` 와 `play_mode_test` 를 같이 고친다.

## 관련

[hud.md](hud.md) (왼쪽 아래 채팅창 · 테스트 단추 자리) · [skills.md](skills.md) (테스트 스위치
`cooldownOff`) · [combat.md](combat.md) (무적)
