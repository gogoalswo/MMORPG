class_name GatePanel
extends NinePatchRect

## 차원문 창 — 어디로 갈지 고르는 목록. **그림 한 장이 아니라 조각을 조립한다** (CLAUDE.md):
##
##   창 바탕(panel.png, 9분할) ─ 여백 ─┬─ 제목 · 닫기
##                                     └─ 스크롤 ─ 줄마다 [칸 아이콘][존 이름]
##
## 칸 아이콘은 둘이다 — 지금 서 있는 곳은 소용돌이(gate_here), 갈 수 있는 곳은 별(gate_go).
## 자리는 **앵커로만** 잡는다: 가로는 가운데 고정 폭, 세로는 화면 높이의 비율이라
## 해상도가 바뀌어도 줄 수만 달라지고 모양은 그대로다 (docs/features/portal-ui.md)

signal picked(zone_id: String)

const UI_DIR := "res://assets/ui/"

## 창 폭(기준 해상도 1280×720 의 px). 높이는 화면 위아래 ANCHOR_Y 만큼 비운 나머지
const WIDTH := 520.0
const ANCHOR_Y := 0.06
## 바탕 그림의 9분할 여백 — 256px 그림의 테두리가 약 7px 이다 (scripts/build-ui.mjs)
const PATCH := 12
## 테두리 안쪽 여백
const PAD := 26
## 칸 아이콘 한 변과 줄 사이
const ICON := 60
const ROW_GAP := 6
const FONT_SIZE := 30
const TEXT_COLOR := Color("#f2f2f2")
## 지금 서 있는 곳은 누를 수 없고 흐리게 (참고 그림의 맨 윗줄)
const HERE_COLOR := Color("#8c8c8c")

## 줄 한 칸의 **틀 색.** 기본 단추(회색 네모)를 그대로 쓰면 게임 화면에서 혼자
## 사무용 UI 로 보인다 (2026-09-20 지적: "스타일도 다른 UI와 아트풍 비슷하게").
## 차원문·아이콘 조각과 같은 **검푸른 바탕 + 푸른 테**로 맞춘다.
## 그림을 새로 받지 않고 `StyleBoxFlat` 으로 짓는 이유는 이펙트 텍스처와 같다 —
## 에셋을 안 받은 사람도 보이고, 색·두께가 상수라 고쳐서 바로 확인할 수 있다
const ROW_FILL := Color("#141d2e")
const ROW_RIM := Color("#31507e")
## 누른 동안. 테가 밝아지고 바탕이 푸르게 달아오른다
const ROW_PRESS_FILL := Color("#1f3f6b")
const ROW_PRESS_RIM := Color("#79bdff")
## 지금 서 있는 곳 — 누를 수 없으니 테도 죽인다
const ROW_HERE_FILL := Color("#0e1420")
const ROW_HERE_RIM := Color("#22314a")
const ROW_RADIUS := 8
const ROW_RIM_WIDTH := 2
## 줄 안쪽 여백(가로, 세로)
const ROW_PAD := Vector2(12, 6)
## **누르면 내용이 이만큼 내려앉는다.** 색만 바뀌면 눌렸는지 눈에 안 들어온다
const ROW_SINK := 3
## 제목·테두리 금색. 차원문의 푸른색과 대비를 준다
const TITLE_COLOR := Color("#ffd98a")
const HEAD_LINE := Color("#31507e")
## 끌기로 치는 최소 거리(px). 이만큼 움직이면 고르기가 아니라 스크롤이다
const DEADZONE := 14
## 스크롤 막대 굵기 — 손가락으로 집을 수 있어야 한다 (기본은 폰에서 너무 가늘다)
const BAR_WIDTH := 18

var _rows: VBoxContainer
var _scroll: ScrollContainer
var _here_icon: Texture2D
var _go_icon: Texture2D
## 끌기 — 누른 자리(창 기준 세로), 누를 때의 스크롤, 데드존을 넘겼나
var _hold := false
var _hold_y := 0.0
var _hold_scroll := 0
var _dragging := false
## 지금 눌려 있는 줄 (뗄 때까지 밝은 틀로 둔다)
var _held: Button = null


static func create() -> GatePanel:
	var panel := GatePanel.new()
	panel._build()
	return panel


func _build() -> void:
	name = "GatePanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = ANCHOR_Y
	anchor_bottom = 1.0 - ANCHOR_Y
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 0.0
	offset_bottom = 0.0

	texture = _tex("panel.png")
	patch_margin_left = PATCH
	patch_margin_right = PATCH
	patch_margin_top = PATCH
	patch_margin_bottom = PATCH
	if texture == null:
		# 조각이 없어도(sync 를 안 돌렸어도) 창은 보여야 한다
		var fallback := ColorRect.new()
		fallback.color = Color(0.08, 0.08, 0.09, 0.95)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)
	_here_icon = _tex("gate_here.png")
	_go_icon = _tex("gate_go.png")

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "차원문"
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", FONT_SIZE + 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "닫기"
	# 닫기도 줄과 같은 틀이다 — 창 안에 기본 회색 단추 하나만 남으면 그게 튄다
	close.add_theme_stylebox_override("normal", _row_box(ROW_FILL, ROW_RIM, 0))
	close.add_theme_stylebox_override("hover", _row_box(ROW_FILL, ROW_PRESS_RIM, 0))
	close.add_theme_stylebox_override("pressed", _row_box(ROW_PRESS_FILL, ROW_PRESS_RIM, ROW_SINK))
	close.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close.add_theme_color_override("font_color", TEXT_COLOR)
	close.pressed.connect(close_panel)
	head.add_child(close)

	# 제목과 목록을 가르는 금
	var line := ColorRect.new()
	line.color = HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# **끌어서 내린다** (2026-09-18 요청: "UI 스크롤이 마우스 휠로만 되는데,
	# 클릭해서 내릴 수 있게"). 엔진에도 끌기가 있지만 **터치 화면일 때만** 켜지고,
	# 그러면 폰에서는 손가락 이벤트와 흉내 낸 마우스 이벤트가 겹쳐 두 배로 내려간다.
	# 그래서 목록에 오는 입력을 여기서 직접 받는다 (`_on_list_input`)
	_scroll.gui_input.connect(_on_list_input)
	_scroll.get_v_scroll_bar().custom_minimum_size.x = BAR_WIDTH
	column.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_scroll.add_child(_rows)


## 연다. 지금 서 있는 존을 알아야 그 줄을 흐리게 막는다
func open(current_zone: String) -> void:
	_fill(current_zone)
	_scroll.scroll_vertical = 0
	_forget_hold()
	visible = true


func close_panel() -> void:
	_forget_hold()
	visible = false


## 누르던 것을 잊는다 — 창을 여닫는 사이에 손을 뗐을 수 있다
func _forget_hold() -> void:
	_hold = false
	_dragging = false
	_press(null)


## 줄 수 (테스트용)
func row_count() -> int:
	return _rows.get_child_count()


func row(i: int) -> Button:
	return _rows.get_child(i) as Button


## 마을 + 사냥터 20곳. 순서는 데이터가 정한다 (zones.json 의 fieldOrder).
## **목록 맨 위가 마을이다** — 돌아가는 길을 매번 훑지 않게 (world-zones.md)
func _fill(current_zone: String) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ids: Array = [GameData.start_zone()]
	ids.append_array(GameData.field_order())
	for id in ids:
		var here := str(id) == current_zone
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = str(GameData.zone(str(id)).get("name", id))
		button.icon = _here_icon if here else _go_icon
		button.add_theme_constant_override("icon_max_width", ICON)
		button.add_theme_constant_override("h_separation", 22)
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_disabled_color", HERE_COLOR)
		# **줄 하나가 칸 하나다.** 검푸른 바탕에 푸른 테 — 누르면 `_press` 가
		# 밝은 틀로 바꿔 끼운다 (`normal` 을 갈아 끼운다: 이 단추는 입력을 안 받아
		# 고도의 pressed 상태가 오지 않는다)
		if here:
			button.add_theme_stylebox_override("disabled", _row_box(ROW_HERE_FILL, ROW_HERE_RIM, 0))
		else:
			button.add_theme_stylebox_override("normal", _row_box(ROW_FILL, ROW_RIM, 0))
		button.custom_minimum_size = Vector2(0, ICON + 4)
		button.disabled = here
		# **줄은 입력을 받지 않는다.** 누른 것이 고르기인지 끌기인지는 목록 쪽에서
		# 판정한다 — 줄이 먼저 받으면 끌다가 손을 뗀 자리의 줄로 떠나 버린다
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.set_meta("zone", str(id))
		_rows.add_child(button)


## 목록에 온 입력. **누르고 끌면 스크롤, 누르고 그 자리에서 떼면 고르기**다.
##
## 휠은 건드리지 않고 `ScrollContainer` 에 그대로 넘긴다 (`accept_event` 를 안 부른다).
## 손가락 이벤트도 넘기지 않고 **삼킨다** — 고도는 기본으로 같은 손짓을 마우스로도
## 흉내 내 보내므로(`emulate_mouse_from_touch`), 둘 다 받으면 두 배로 내려간다
func _on_list_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		accept_event()
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_hold = true
			_dragging = false
			_hold_y = click.position.y
			_hold_scroll = _scroll.scroll_vertical
			# 누른 줄을 **눌린 틀**로 바꾼다
			_press(_row_at(click.position))
		elif _hold:
			_hold = false
			var row_under := _row_at(click.position)
			var held := _held
			_press(null)
			# 누른 줄에서 뗐을 때만 고른다 — 다른 줄로 미끄러졌으면 취소다
			if not _dragging and held != null and held == row_under:
				_on_pick(str(held.get_meta("zone", "")))
		accept_event()
		return
	var move := event as InputEventMouseMotion
	if move != null and _hold:
		var moved := move.position.y - _hold_y
		if not _dragging and absf(moved) > DEADZONE:
			_dragging = true
			# 끌기 시작 = 고르기 취소. 눌린 자국을 지운다
			_press(null)
		if _dragging:
			# 손을 따라간다 — 위로 끌면 목록이 올라온다. 범위는 고도가 죈다
			_scroll.scroll_vertical = _hold_scroll - int(moved)
			accept_event()


## 그 자리의 줄. **줄 전체가 누르는 자리다** (2026-09-20 요청: "해당 라인을 전체
## 클릭 영역으로") — 가로는 따지지 않고(목록 안이면 다 그 줄이다) 세로만 본다.
## 줄 사이 틈(ROW_GAP)도 가까운 줄에 붙여 준다. `at` 은 목록 기준이라 화면
## 기준으로 옮겨서 견준다 (줄은 스크롤만큼 밀려 있다)
func _row_at(at: Vector2) -> Button:
	var y: float = _scroll.global_position.y + at.y
	for child in _rows.get_children():
		var button := child as Button
		if button == null or button.disabled:
			continue
		var box := button.get_global_rect()
		if y >= box.position.y - ROW_GAP * 0.5 and y <= box.end.y + ROW_GAP * 0.5:
			return button
	return null


## 눌린 틀로 바꿔 끼운다. `row` 가 null 이면 눌린 자국을 지운다.
## 누름을 **보이게** 하는 자리다 (2026-09-20 요청: 누를 때와 뗄 때가 달라야 한다)
func _press(row: Button) -> void:
	if _held == row:
		return
	if _held != null and is_instance_valid(_held):
		_held.add_theme_stylebox_override("normal", _row_box(ROW_FILL, ROW_RIM, 0))
	_held = row
	if _held != null:
		_held.add_theme_stylebox_override("normal", _row_box(ROW_PRESS_FILL, ROW_PRESS_RIM, ROW_SINK))


## 줄 한 칸의 틀. `sink` 만큼 내용이 내려앉는다 — 누른 줄에 준다
func _row_box(fill: Color, rim: Color, sink: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(ROW_RIM_WIDTH)
	box.set_corner_radius_all(ROW_RADIUS)
	box.content_margin_left = ROW_PAD.x
	box.content_margin_right = ROW_PAD.x
	box.content_margin_top = ROW_PAD.y + sink
	box.content_margin_bottom = maxf(ROW_PAD.y - sink, 0.0)
	return box


func _on_pick(zone_id: String) -> void:
	visible = false
	picked.emit(zone_id)


static func _tex(file: String) -> Texture2D:
	var path := UI_DIR + file
	return load(path) if ResourceLoader.exists(path) else null
