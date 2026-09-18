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

var _rows: VBoxContainer
var _scroll: ScrollContainer
var _here_icon: Texture2D
var _go_icon: Texture2D


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
	title.add_theme_color_override("font_color", Color("#4aa8ff"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "닫기"
	close.pressed.connect(close_panel)
	head.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_scroll.add_child(_rows)


## 연다. 지금 서 있는 존을 알아야 그 줄을 흐리게 막는다
func open(current_zone: String) -> void:
	_fill(current_zone)
	_scroll.scroll_vertical = 0
	visible = true


func close_panel() -> void:
	visible = false


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
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = str(GameData.zone(str(id)).get("name", id))
		button.icon = _here_icon if here else _go_icon
		button.add_theme_constant_override("icon_max_width", ICON)
		button.add_theme_constant_override("h_separation", 22)
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_disabled_color", HERE_COLOR)
		button.custom_minimum_size = Vector2(0, ICON + 4)
		button.disabled = here
		# 손가락으로 목록을 끌어 올릴 수 있게 누름을 스크롤에도 넘긴다
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.pressed.connect(_on_pick.bind(str(id)))
		_rows.add_child(button)


func _on_pick(zone_id: String) -> void:
	visible = false
	picked.emit(zone_id)


static func _tex(file: String) -> Texture2D:
	var path := UI_DIR + file
	return load(path) if ResourceLoader.exists(path) else null
