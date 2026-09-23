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
## **입력을 받지 않는다.** 혼자 하는 판이라 말 걸 사람이 없어서 입력칸이 없고,
## 창을 눌러도 밑의 땅이 눌린다(이동) — 창 뒤로 걸어가지 못하면 안 된다.
## 서버가 붙어 말을 주고받게 되면 입력칸과 스크롤을 단다.

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
## 경험치 값 — HUD 의 경험치 글자와 같은 금빛
const EXP := Color("#e8c14a")

## [[머리말, 값], ...] — 창에 적힌 줄 (테스트가 읽는다)
var _lines: Array = []
var _text: RichTextLabel


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
	add_child(_text)


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
