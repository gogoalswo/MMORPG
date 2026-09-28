class_name ExpToast
extends VBoxContainer

## 화면 오른쪽 아래, 경험치 띠 바로 위 — **잠깐 떴다 사라지는 경험치 알림**.
## "경험치를 얻었습니다 (+12)" 한 줄이 떠서 `SHOW_SEC` 머문 뒤 `FADE_SEC` 동안 옅어지고 지워진다.
##
## 2026-09-28 요청: "경험치를 채팅창에 띄우지 말고 … 파란 박스와 같은 위치에 … 잠깐 텍스트가
## 나왔다 사라지는 형식으로" — 받은 스크린샷(메이플의 "메소를 얻었습니다 (+1955)")대로
## **판 없이 글자만**, 오른쪽 끝에 맞춰, 새 줄이 맨 아래에 붙고 앞 줄은 위로 밀린다.
## 채팅창에는 이제 장비 획득·강화·말만 적힌다 (`ChatLog`).
##
## 입력을 받지 않는다 — 글자 뒤의 땅이 눌려야 한다.

## 한 줄이 또렷이 머무는 시간(초)
const SHOW_SEC := 2.5
## 옅어지는 시간(초)
const FADE_SEC := 0.6
## 한꺼번에 여럿 잡아도 이만큼만 쌓는다 — 넘으면 가장 오래된 것부터 지운다
const MAX_LINES := 6
## 줄 너비(px). 오른쪽 끝에 맞추므로 글자가 짧으면 오른쪽에 붙는다
const WIDTH := 320
const FONT_SIZE := 16
## 스크린샷의 옅은 금빛. 판이 없어서 검은 테로 땅 위에서 읽히게 한다
const TEXT := Color("#f3dc7a")
const OUTLINE := Color(0, 0, 0, 0.85)
const OUTLINE_SIZE := 4


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 0)


## 경험치 한 줄을 띄운다
func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	var line := Label.new()
	line.text = "경험치를 얻었습니다 (+%d)" % amount
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("font_size", FONT_SIZE)
	line.add_theme_color_override("font_color", TEXT)
	line.add_theme_color_override("font_outline_color", OUTLINE)
	line.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(line)
	var tween := line.create_tween()
	tween.tween_interval(SHOW_SEC)
	tween.tween_property(line, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(line.queue_free)
	while _live().size() > MAX_LINES:
		var old: Node = _live()[0]
		remove_child(old)
		old.queue_free()


## 지금 떠 있는 글자들 (위에서부터)
func lines() -> Array:
	var out := []
	for line in _live():
		out.append(line.text)
	return out


func _live() -> Array:
	return get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
