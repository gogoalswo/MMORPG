# 시작 모드 · 치트 목록 여닫기

## 무엇

게임을 켜면 **테스트 모드 / 일반 모드** 를 고르는 화면이 먼저 뜬다 (2026-09-25 요청).

| 모드 | 켜지는 것 | 왼쪽 치트 목록 |
|---|---|---|
| 테스트 모드 | **무적 · 스킬 쿨타임 0** | 접힌 채 시작 — 채팅창 위 **"치트 목록 열기"** 단추로 편다 |
| 일반 모드 | 없음 (캐릭터만 만들어 시작) | 목록도 여닫기 단추도 안 보인다 |

같은 날 요청으로 **치트 목록을 단추 하나로 접고 편다** — 단추 열 개가 왼쪽을 다 덮었다.

## 어디

| 파일 | 역할 |
|---|---|
| `godot/start.tscn` · `godot/game/start_screen.gd` | 시작 화면. 단추 둘, 누르면 `PlayMode.current` 에 적고 `main.tscn` 으로 넘어간다 |
| `godot/game/play_mode.gd` | `PlayMode` — 고른 모드(`static var current`). 장면을 바꿔도 남는다 |
| `godot/game/game.gd` `_apply_play_mode` | 모드를 건다 — 테스트면 `invincible` · `testSwitch cooldownOff` 를 보낸다 |
| `godot/game/game.gd` `_cheat_toggle` · `_set_cheats_open` | 치트 목록(`_cheat_column`) 여닫기 |
| `godot/project.godot` | `run/main_scene = res://start.tscn` |
| `godot/tests/play_mode_test.gd` | 두 모드에서 무적·쿨타임·목록 상태를 본다 |

## 규칙

- **모드를 거는 건 게임 쪽이다.** 시작 화면은 고르기만 한다. 무적·쿨타임은 버튼으로
  켜던 것과 **같은 요청**(`invincible`, `testSwitch`)을 보낸다 — 판정 경로가 하나다.
- **모드 없음(`""`)은 테스트·도구용이다.** 테스트 스무 편과 `shot.gd` 가 `main.tscn` 을
  바로 띄우므로, 시작 화면을 안 거치면 **아무것도 켜지 않고 목록은 펼친 채** 둔다.
  그래서 기존 테스트는 손대지 않고 돈다 (`ui_test` 는 단추 자리를 본다).
- **테스트 모드의 목록은 접혀서 시작한다.** 펼치면 왼쪽이 다시 덮이기 때문이다.
- **일반 모드는 무적·쿨타임을 끄는 요청을 보내지 않는다.** 둘 다 저장되지 않아
  (`invincible` 은 존 이동에만 이어진다, `cooldownOff` 는 `skills.json` 기본값 `false`)
  새로 켜면 이미 꺼져 있다. 끄는 요청을 보내면 "무적 끔" 알림만 괜히 뜬다.
- **여닫기 단추 자리** — 채팅창 바로 위, 묶음은 그 위 (`lift += CHEAT_TOGGLE.y + 6`).
- 글자에 `▲▼` 를 쓰지 않는다 — 한글 부분집합 글꼴(`NotoSansKR-subset.ttf`)에 없다.

## 손댈 때

- 테스트 단추를 더하면 `_build_test_switches` 의 `column` 에 넣는다 — 그래야 같이 접힌다.
- 테스트 모드에서 켤 것을 늘리면 `_apply_play_mode` 와 `play_mode_test` 를 같이 고친다.

## 관련

[hud.md](hud.md) (왼쪽 아래 채팅창 · 테스트 단추 자리) · [skills.md](skills.md) (테스트 스위치
`cooldownOff`) · [combat.md](combat.md) (무적)
