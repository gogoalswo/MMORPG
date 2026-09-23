class_name LootLog
extends VBoxContainer

## 화면 왼쪽에 쌓이는 획득 알림 — **경험치**와 **장비 획득**을 한 줄씩 띄운다.
##
## 처음에는 `+n EXP` 를 쓰러진 자리에서 3D 글자로 띄웠는데, 피해 숫자와 같은
## 자리에서 터져서 **"데미지랑 같이 뜨니까 안 보여"** 라는 말을 들었다 (2026-09-23).
## 그래서 전투가 벌어지는 가운데를 비우고 왼쪽에 모았다.
##
## 결은 `ui-art-style.md` 대로 **어두운 판 + 얇은 금테**다. 조각 그림 없이
## `StyleBoxFlat` 으로 그린다 — 한 줄짜리 띠라 9조각을 받을 이유가 없다.
## 글자는 `Label` 로 얹는다. 누르는 것이 아니므로 입력을 전부 흘린다.
##
## 줄은 아래로 쌓이고(새 것이 맨 아래), `MAX_LINES` 를 넘으면 가장 오래된 것부터
## 지운다. 한 줄은 `LIFE` 초 뒤에 흐려지며 스스로 사라진다.
##
## **줄 노드는 지우지 않고 숨겨 두었다 다시 쓴다** ★ — 한 줄이 컨테이너 둘 ·
## 글자 둘 · 테마 덮어쓰기라 만드는 데 1.6~1.9ms 였고, 범위 스킬로 무리를 잡으면
## 한 프레임에 여러 줄이 몰려 히치가 됐다 (2026-09-23 "스킬 사용할 때 자꾸 히치").
## 넘치면 가장 오래된 줄을 맨 아래로 옮겨 글자만 바꾼다. 이펙트 풀(`FxPool`)과 같은 생각이다.

## 한 번에 보이는 줄 수. 무리를 잡으면 한꺼번에 들어오므로 넘치면 오래된 것을 민다
const MAX_LINES := 6
## 한 줄이 떠 있는 시간(초). 끝 `FADE` 초 동안 흐려진다
const LIFE := 4.0
const FADE := 0.6
## 들어올 때 왼쪽에서 밀려 들어오는 거리(px)와 시간
const SLIDE := 40.0
const SLIDE_TIME := 0.18
const FONT_SIZE := 18
const LINE_H := 34

## 판 안쪽 — `ui-art-style.md` 의 판 색. 게임 화면을 다 가리지 않게 조금 비친다
const BG := Color(0.098, 0.102, 0.098, 0.78)
## 얇은 금테
const BORDER := Color("#b9a46c", 0.55)
## 머리말(무엇을 얻었나) — 상아빛을 조금 눌러서 뒤에 오는 값이 먼저 읽히게
const HEAD := Color("#eeead7", 0.75)
## 경험치 값 — HUD 의 경험치 글자와 같은 금빛
const EXP := Color("#e8c14a")

## [{row, t}, ...] — 떠 있는 줄과 산 시간
var _rows: Array = []
## 숨겨 둔 줄 — 다음 줄이 꺼내 쓴다
var _spare: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	# 줄은 **미리 다 지어 둔다** — 처음 잡을 때 한 줄에 1ms 씩 드는 것을 게임을 열 때 치른다
	for i in MAX_LINES:
		var row := _make_row()
		row.visible = false
		add_child(row)
		_spare.append(row)


## 경험치 한 줄
func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	add_line("경험치", "+%d" % amount, EXP)


## 장비 획득 한 줄. 이름에 등급이 이미 들어 있다 ("희귀 투구") — 색도 등급을 따른다
func add_item(name: String, tint: Color) -> void:
	add_line("장비 획득", name, tint)


## 머리말 + 값 한 줄을 맨 아래에 넣는다. 가득 찼으면 가장 오래된 줄을, 아니면
## 숨겨 둔 줄을 꺼내 쓴다 — 새로 만드는 것은 처음 `MAX_LINES` 줄뿐이다
func add_line(head: String, value: String, tint: Color) -> void:
	var row: PanelContainer
	if _rows.size() >= MAX_LINES:
		row = _rows.pop_front().row
	elif not _spare.is_empty():
		row = _spare.pop_back()
	else:
		row = _make_row()
		add_child(row)
	move_child(row, -1)
	row.visible = true
	var labels: Array = row.get_child(0).get_children()
	labels[0].text = head
	labels[1].text = value
	labels[1].add_theme_color_override("font_color", tint)
	# 첫 프레임부터 들어오는 자리에 — `_process` 가 돌기 전에 그려져도 튀지 않게
	row.modulate.a = 0.3
	row.get_child(0).position.x = -SLIDE + _box().content_margin_left
	_rows.append({"row": row, "t": 0.0})


## 줄 하나를 짓는다 — 판 · 머리말 · 값
func _make_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, LINE_H)
	row.add_theme_stylebox_override("panel", _box())
	# 판 폭은 글자에 맞춘다 — 부모(VBox)가 늘이지 않도록 왼쪽에 붙인다
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	line.add_child(_label("", HEAD))
	line.add_child(_label("", HEAD))
	return row


## 지금 떠 있는 줄의 글자들 (테스트가 읽는다). [[머리말, 값], ...]
func lines() -> Array:
	var out: Array = []
	for entry in _rows:
		var labels: Array = entry.row.get_child(0).get_children()
		out.append([labels[0].text, labels[1].text])
	return out


func _process(delta: float) -> void:
	for i in range(_rows.size() - 1, -1, -1):
		var entry: Dictionary = _rows[i]
		entry.t += delta
		var row: PanelContainer = entry.row
		# 왼쪽에서 밀려 들어온다. 컨테이너가 자리를 잡으므로 그림만 옮긴다
		var slide := clampf(entry.t / SLIDE_TIME, 0.0, 1.0)
		var content: Control = row.get_child(0)
		content.position.x = -SLIDE * (1.0 - slide) + _box().content_margin_left
		row.modulate.a = clampf((LIFE - entry.t) / FADE, 0.0, 1.0) * lerpf(0.3, 1.0, slide)
		if entry.t >= LIFE:
			_drop(i)


## 줄을 내린다 — 지우지 않고 숨겨 둔다
func _drop(index: int) -> void:
	var row: Control = _rows[index].row
	_rows.remove_at(index)
	row.visible = false
	_spare.append(row)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 4)
	return label


var _style: StyleBoxFlat


func _box() -> StyleBoxFlat:
	if _style != null:
		return _style
	_style = StyleBoxFlat.new()
	_style.bg_color = BG
	_style.border_color = BORDER
	_style.set_border_width_all(1)
	_style.content_margin_left = 12
	_style.content_margin_right = 14
	_style.content_margin_top = 4
	_style.content_margin_bottom = 4
	return _style
