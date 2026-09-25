class_name PlayMode

## 시작 화면에서 고른 모드. 장면을 갈아 끼워도 남도록 static 에 둔다 (`start_screen.gd` → `main.tscn`).
##
## - `TEST`   무적 켬 · 스킬 쿨타임 0 으로 시작한다. 치트 목록은 **접힌 채** 뜬다
## - `NORMAL` 치트 없이 캐릭터만 만든다. 치트 목록과 그 여닫는 단추가 아예 안 보인다
## - `""`     시작 화면을 안 거쳤다 — 테스트·도구가 `main.tscn` 을 바로 띄운 경우다.
##            아무것도 켜지 않고 치트 목록은 **펼친 채** 둔다 (테스트가 단추 자리를 본다)
##
## → docs/features/play-mode.md

const TEST := "test"
const NORMAL := "normal"

static var current := ""
