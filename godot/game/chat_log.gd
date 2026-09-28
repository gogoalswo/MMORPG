class_name ChatLog
extends PanelContainer

## 화면 왼쪽 아래 채팅창 — 지금은 **경험치**와 **장비 획득**을 한 줄씩 적는다.
##
## 오기까지 두 번 옮겼다 (2026-09-23):
## 1. 쓰러진 자리에서 3D 글자(`+n EXP`) → **"데미지랑 같이 뜨니까 안 보여"**
## 2. 왼쪽 위에 잠깐 떴다 사라지는 띠 → **"왼쪽 아래 채팅창 만들어서 거기에 넣어"**
##
## 그래서 줄은 **사라지지 않고 쌓인다** — 채팅창이라 지나간 것도 남아 있어야 한다.
## 새 줄이 맨 아래에 붙고 창은 늘 맨 아래를 따라간다. `MAX_LINES` 를 넘으면 가장
## 오래된 줄부터 지운다.
##
## 결은 `ui-art-style.md` 대로 **어두운 판 + 얇은 금테**다. 조각 그림 없이
## `StyleBoxFlat` 으로 그린다. 글자는 `RichTextLabel` 로 얹는다 — 한 줄 안에서
## 머리말과 값의 색이 달라서다.
##
## **창은 입력을 받지 않는다** — 창을 눌러도 밑의 땅이 눌린다(이동). 창 뒤로 걸어가지 못하면 안 된다.
## **서버에 붙었을 때만** 맨 아래에 입력칸이 선다(`set_online`) — 혼자 노는 판에는 말 걸 사람이 없다.
## 입력칸만 터치를 받는다. 남의 말(`add_chat`)과 알림도 같은 창에 적힌다 (docs/features/server.md 5단계).

## 말 한 줄을 보냈다 (Enter · 폰 키보드의 완료)
signal submitted(text: String)

## 창이 들고 있는 줄 수. 넘으면 오래된 것부터 지운다
const MAX_LINES := 50
## 창 크기(px). 18px 글자 여섯 줄이 보인다
const SIZE := Vector2(380, 170)
const FONT_SIZE := 17

## 판 안쪽 — `ui-art-style.md` 의 판 색. 게임 화면이 조금 비친다
const BG := Color(0.098, 0.102, 0.098, 0.72)
## 얇은 금테
const BORDER := Color("#b9a46c", 0.55)
## 머리말(무엇을 얻었나) — 상아빛을 조금 눌러서 뒤에 오는 값이 먼저 읽히게
const HEAD := Color("#eeead7", 0.7)
## 경험치 값 — **청록.** 처음엔 경험치 띠와 같은 금빛(`#e8c14a`)이었는데 영웅 등급
## 금색과 나란히 서면 구분이 안 됐다 (2026-09-23). 흰빛은 고급(옅은 회청)과 가까웠다.
## 청록은 등급 일곱 색(흙·회청·초록·금·보라·파랑·빨강) 어디에도 없다
const EXP := Color("#62e0cc")
## 남이 한 말 — 상아빛 그대로 (머리말 자리에 이름)
const SAY := Color("#eeead7")
## 알림(강화 성공 같은 것) — 고른 탭·밝은 강조의 금빛
const NOTICE := Color("#e3d092")
## 입력칸 높이와 한 줄 최대 글자 (서버도 100자에서 자른다 — `LedgerServer.CHAT_MAX_LEN`)
const INPUT_HEIGHT := 30
const INPUT_MAX := 100

## [[머리말, 값], ...] — 창에 적힌 줄 (테스트가 읽는다)
var _lines: Array = []
var _text: RichTextLabel
var _input: LineEdit


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	var box := StyleBoxFlat.new()
	box.bg_color = BG
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	add_theme_stylebox_override("panel", box)

	_text = RichTextLabel.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.bbcode_enabled = true
	_text.scroll_active = false
	# 새 줄이 들어오면 맨 아래를 보여 준다 — 채팅창이 늘 그렇듯
	_text.scroll_following = true
	_text.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_text.add_theme_constant_override("outline_size", 4)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(_text)

	# 입력칸 — 같은 결(어두운 판 + 얇은 금테 + 상아빛 글자). 서버에 붙기 전에는 숨긴다
	_input = LineEdit.new()
	_input.visible = false
	_input.max_length = INPUT_MAX
	_input.placeholder_text = "말하기"
	_input.custom_minimum_size = Vector2(0, INPUT_HEIGHT)
	_input.add_theme_font_size_override("font_size", FONT_SIZE)
	_input.add_theme_color_override("font_color", SAY)
	_input.add_theme_color_override("font_placeholder_color", Color(SAY, 0.4))
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.098, 0.102, 0.098, 0.9)
	field.border_color = BORDER
	field.set_border_width_all(1)
	field.set_content_margin_all(4)
	field.content_margin_left = 8
	_input.add_theme_stylebox_override("normal", field)
	var focus := field.duplicate()
	focus.border_color = Color("#dfc97a")
	_input.add_theme_stylebox_override("focus", focus)
	_input.text_submitted.connect(_on_submit)
	column.add_child(_input)


## 서버에 붙었나 — 붙었을 때만 입력칸을 보인다
func set_online(on: bool) -> void:
	_input.visible = on


func is_online() -> bool:
	return _input.visible


## 남이 한 말 · 알림 한 줄. 말은 **글자 그대로** 적는다(`add_text` — BBCode 로 읽지 않는다)
func add_chat(from: String, text: String, system := false) -> void:
	if system:
		add_line("알림", text, NOTICE)
	else:
		add_line(from, text, SAY)


func _on_submit(text: String) -> void:
	var said := text.strip_edges()
	_input.clear()
	# 보내면 입력칸에서 손을 뗀다 — 폰 키보드가 내려가고 단축키(1~4)가 다시 먹는다
	_input.release_focus()
	if not said.is_empty():
		submitted.emit(said)


## 경험치 한 줄
func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	add_line("경험치", "+%d" % amount, EXP)


## 장비 획득 한 줄 — "흑철 건틀릿". **이름에는 등급 글자가 없고 색이 등급을 알린다**
## (2026-09-23, 이름을 재질로 바꾸면서)
func add_item(name: String, grade: int) -> void:
	add_line("장비 획득", name, grade_text_color(grade))


## 등급 색(`Items.grade_color`)을 어두운 판 위에서 읽히게 밝힌 것.
## **색상(hue)은 그대로 두고 밝기만 올린다** — 흰색을 섞으면(가방 칸의 `_grade_tint`)
## 등급끼리 색이 다 옅어져 비슷해 보인다. 표의 색은 어두운 흙빛에서 시작해서
## 그대로 쓰면 판에 묻힌다
static func grade_text_color(grade: int) -> Color:
	var base := Items.grade_color(grade)
	return Color.from_hsv(base.h, clampf(base.s * 1.15, 0.0, 0.85), maxf(base.v, 0.92))


## 머리말 + 값 한 줄을 맨 아래에 붙인다
func add_line(head: String, value: String, tint: Color) -> void:
	if not _lines.is_empty():
		_text.newline()
	_text.push_color(HEAD)
	_text.add_text(head + "  ")
	_text.pop()
	_text.push_color(tint)
	_text.add_text(value)
	_text.pop()
	_lines.append([head, value])
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
		_text.remove_paragraph(0)


## 적힌 줄들. [[머리말, 값], ...]
func lines() -> Array:
	return _lines.duplicate()
