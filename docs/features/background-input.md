# 백그라운드 키 입력 시험 도구

게임 창을 **포커스하지 않은 채** 키(기본 `1` = 퀵슬롯 1)를 눌러 주는 Windows 도구다.
매크로 막기 기능을 만들고 **막혔는지 확인하는 데** 쓴다 (2026-10-15 요청).

## 어디에 있나

| 파일 | 역할 |
|---|---|
| `scripts/bg-key.ps1` | 게임 창을 찾아 `WM_KEYDOWN`/`WM_KEYUP` 을 `PostMessage` 로 넣는다. 앞뒤로 포커스 창을 찍어 안 바뀐 것을 보여 준다 |
| `godot/game/game.gd` `_unhandled_input` | 받는 쪽. `event.keycode - KEY_1` 로 퀵슬롯 1~4 를 누른다 |

## 쓰는 법

`scripts\play.bat` 로 게임을 띄우고 **다른 창을 클릭해 포커스를 뺀 뒤**:

```bat
powershell -ExecutionPolicy Bypass -File scripts\bg-key.ps1
powershell -ExecutionPolicy Bypass -File scripts\bg-key.ps1 -Key 2 -Count 10 -IntervalMs 500
powershell -ExecutionPolicy Bypass -File scripts\bg-key.ps1 -Title "MMORPG (DEBUG)"
```

| 인자 | 기본 | 뜻 |
|---|---|---|
| `-Key` | `1` | 누를 키 한 글자 (`0-9`, `A-Z`) |
| `-Count` / `-IntervalMs` | `1` / `1000` | 몇 번, 몇 ms 간격 |
| `-HoldMs` | `50` | 누르고 떼기까지 |
| `-Title` | `MMORPG` | 창 제목에 들어 있는 글자. `Godot Engine` 이 든 창(에디터)은 건너뛴다 |
| `-Hwnd` | | 창 핸들을 16진수로 직접 준다 |

출력 끝줄이 `foreground : ... (unchanged)` 면 포커스는 그대로였다. 게임에서 퀵슬롯 1이
발동했으면 **아직 안 막힌 것**이다.

## 왜 이렇게 했나

- **`PostMessage` 를 쓴다.** `SendInput`·`keybd_event` 는 포커스 창에만 들어가서
  "포커스 없이" 가 안 된다. 백그라운드 매크로가 실제로 쓰는 방식이 창 메시지 큐에 직접
  넣는 이것이라, 막기 기능도 이것으로 시험해야 한다.
- **lParam 에 스캔 코드를 채운다** (`MapVirtualKey`). 고도는 `wParam`(가상 키)으로
  `keycode` 를, 스캔 코드로 `physical_keycode` 를 만든다. 비워 두면 물리 키로 막거나
  판별하는 쪽 시험이 틀어진다.
- **본문은 ASCII 만 쓴다.** PowerShell 5.1 은 BOM 없는 `.ps1` 을 ANSI 코드 페이지로 읽어
  UTF-8 한글이 깨진다 (`play.bat` 이 같은 이유로 영어다). 한국어 설명은 이 문서에 둔다.

## 손댈 때

- 퀵슬롯 키 처리(`game.gd` `_unhandled_input`)를 옮기거나 키를 바꾸면 `-Key` 기본값과 이 문서를 같이 고친다.
- 막기 기능을 넣으면 그 자리와 규칙을 이 문서(또는 그 기능 문서)에 적고, 이 도구로 막히는 것을 확인한다.

## 관련

- [godot-migration.md](godot-migration.md) — PC 에서 띄우기 (`play.bat`)
- [verification.md](verification.md) — 확인 방법
