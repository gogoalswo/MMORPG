class_name CodexPicker
extends Control

## 도감 — **등록할 장비 선택** 창 (2026-10-01 요청: "도감 등록할 때 가방에서 선택하는 UI를 따로 만들어.
## 지금 보면 2,3차 옵션은 안 보이자나"). 도감 창의 [등록] 을 누르면 그 위에 뜬다.
## 그 칸(등급·부위·강화)에 맞는 가방 장비를 칸으로 늘어놓고, 칸마다 **1차 · 2차 · 3차 옵션을 차수별로** 적는다.
## 칸을 골라 [등록] → `picked(가방 번호)`. 판정은 장부(`Ledger.codex_register`)가 다시 본다 → docs/features/codex.md
##
##   ┌──────────── 등록할 장비 선택 — 흑철 건틀릿 +3 ─────────────┐
##   │ ┌────────────────────────┐ ┌────────────────────────┐ │
##   │ │[그림] 흑철 건틀릿 +3     │ │[그림] 흑철 건틀릿 +3 ×2 │ │  ← 고른 칸은 금빛 테
##   │ │ 1차  치명타 +6%          │ │ 1차  치명타 +2%          │ │
##   │ │ 2차  방어력 관통 +3%     │ │ 2차  비어 있음           │ │
##   │ │ 3차  비어 있음           │ │ 3차  비어 있음           │ │
##   │ └────────────────────────┘ └────────────────────────┘ │
##   │  넣은 장비는 사라집니다            [ 취소 ]  [ 등록 ]  │
##   └─────────────────────────────────────────────────────┘

signal picked(index: int)
## **자동 등록** 확인 — `open_all` 로 연 창의 [등록] (2026-10-02 요청 "도감에 자동 등록 버튼 만들어")
signal picked_all

const WIDTH := 820.0
const HEIGHT := 540.0
const COLUMNS := 2
const GAP := 10
const ICON := 56.0
const BUTTON_MARGIN := 28
const SINK := 3

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const NEXT := Color("#6fc9d6")

var _frame_box := Callable()
var _icon := Callable()

var _bag: Array = []
var _item_id := ""
var _enhance := 0
## 고른 가방 번호 · 늘어놓은 가방 번호들
var _choice := -1
var _choices: Array = []
## 자동 등록 확인으로 열었나 — 늘어놓은 것이 **전부** 들어간다 (하나를 고르지 않는다)
var _all := false

var _title: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _drag: DragScroll
var _confirm: Button


static func make(frame_box: Callable, icon: Callable) -> CodexPicker:
	var picker := CodexPicker.new()
	picker._frame_box = frame_box
	picker._icon = icon
	picker._build()
	return picker


func _build() -> void:
	name = "CodexPicker"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 뒤를 어둡게 덮고 누름을 막는다 — 도감 창의 칸이 뒤에서 눌리지 않게
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# 어두운 판 + 얇은 금테 (ui-art-style.md) — 메뉴 판과 같은 결
	var sheet := PanelContainer.new()
	sheet.name = "sheet"
	sheet.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.055, 0.045, 0.97)
	box.border_color = Color(GOLD, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(18)
	sheet.add_theme_stylebox_override("panel", box)
	center.add_child(sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	sheet.add_child(column)
	_title = _label("", 24, TITLE)
	_title.name = "title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.name = "choices"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.get_v_scroll_bar().custom_minimum_size.x = GatePanel.BAR_WIDTH
	column.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)
	# 끌어서 내린다 — 가방·강화 목록과 같은 길
	_drag = DragScroll.attach(_scroll, _grid, GAP)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	column.add_child(foot)
	var note := _label("넣은 장비는 가방에서 사라집니다", 18, DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(note)
	var cancel := _button("취소")
	cancel.name = "cancel"
	cancel.pressed.connect(close)
	foot.add_child(cancel)
	_confirm = _button("등록")
	_confirm.name = "confirm"
	_confirm.pressed.connect(_on_confirm)
	foot.add_child(_confirm)


## 그 칸(아이템 id · 강화)에 맞는 가방 장비를 늘어놓고 연다. 처음엔 **옵션 줄이 가장 적은 것**을 고른다 —
## 장부의 기본(`index` -1)과 같다. 맞는 것이 없으면 안 연다
func open(item_id: String, enhance: int, bag: Array) -> void:
	_item_id = item_id
	_enhance = enhance
	_bag = bag
	_choices = []
	for index in bag.size():
		# 잠근 것은 고를 수 없다 — 판정(`Ledger.codex_register`)도 거절한다
		if str(bag[index].get("id", "")) == item_id and int(bag[index].get("enhance", 0)) == enhance \
				and not Items.is_locked(bag[index]):
			_choices.append(index)
	if _choices.is_empty():
		return
	_all = false
	_choice = -1
	for index in _choices:
		if _choice < 0 or Items.option_lines(bag[index]) < Items.option_lines(bag[_choice]):
			_choice = index
	var item := Items.get_item(item_id)
	_title.text = "등록할 장비 선택 — %s +%d" % [str(item.get("name", "")), enhance]
	_scroll.scroll_vertical = 0
	visible = true
	_redraw()


## **자동 등록** 확인 — 들어갈 장비(`Codex.auto_picks`, 칸마다 하나)를 **전부** 늘어놓는다.
## 고르지 않고 [등록] 한 번이면 다 들어간다 — 무엇이 사라지는지 1·2·3차까지 보고 누른다. 없으면 안 연다
func open_all(bag: Array, picks: Array) -> void:
	if picks.is_empty():
		return
	_bag = bag
	_choices = picks.duplicate()
	_all = true
	_choice = -1
	_title.text = "자동 등록 — %d칸에 넣습니다" % _choices.size()
	_scroll.scroll_vertical = 0
	visible = true
	_redraw()


## 자동 등록 확인으로 열렸나 — 테스트가 본다
func is_all() -> bool:
	return _all


func close() -> void:
	visible = false
	_drag.forget()


## 고른 가방 번호 · 늘어놓은 가방 번호들 — 테스트가 본다
func choice() -> int:
	return _choice


func choices() -> Array:
	return _choices


func confirm_button() -> Button:
	return _confirm


func _on_confirm() -> void:
	if _all:
		close()
		picked_all.emit()
		return
	if _choice < 0:
		return
	var index := _choice
	close()
	picked.emit(index)


func _select(index: int) -> void:
	if _all:
		return
	_choice = index
	_redraw()


func _redraw() -> void:
	_drag.forget()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for index in _choices:
		_grid.add_child(_card(_bag[index], index, _all or index == _choice))
	_confirm.disabled = not _all and _choice < 0


## 칸 하나 — 그림 · 이름(+강화 · 겹친 개수) · 차수마다 한 줄. 누르는 것은 덮개 `hit`
## (`DragScroll` 이 끌기와 누르기를 가른다)
func _card(stack: Dictionary, index: int, chosen: bool) -> Control:
	var card := PanelContainer.new()
	card.name = "choice_%d" % index
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.78, 0.5, 0.1) if chosen else Color(0.03, 0.03, 0.03, 0.75)
	box.border_color = GOLD if chosen else GatePanel.CELL_LINE
	box.set_border_width_all(2 if chosen else 1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)

	var item := Items.get_item(str(stack.get("id", "")))
	var grade := int(item.get("grade", 1))
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(ICON, ICON)
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = _icon.call("%s_g%d" % [item.get("slot", ""), grade]) if _icon.is_valid() else null
	line.add_child(art)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 2)
	line.add_child(words)
	var title := "%s +%d" % [str(item.get("name", "")), int(stack.get("enhance", 0))]
	if int(stack.get("count", 1)) > 1:
		title += "  ×%d" % int(stack.count)
	var name_label := _label(title, 20, Items.grade_color(grade) if chosen else Items.grade_color(grade).darkened(0.25))
	words.add_child(name_label)
	# 차수마다 한 줄 — 상세 창 · 크리스탈 창과 같은 말("N차" · "비어 있음"), 크리스탈로 붙는 차수는 금빛
	for tier in Items.option_tiers():
		var lines: Array = Items.shown_options(stack.get(str(tier.key), []))
		var crystal := str(tier.get("source", "")) == "crystal"
		var head := "%d차" % int(tier.tier)
		if lines.is_empty():
			words.add_child(_tier_line(head, "비어 있음", FAINT, "tier_%d" % int(tier.tier)))
			continue
		for at in lines.size():
			var color := (GOLD if crystal else NEXT) if chosen else DIM
			words.add_child(_tier_line(head, Items.describe_option(lines[at]), color, "tier_%d_%d" % [int(tier.tier), at]))

	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(_select.bind(index))
	card.add_child(hit)
	return card


func _tier_line(head: String, text: String, color: Color, node_name: String) -> Control:
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var key := _label(head, 16, DIM)
	key.custom_minimum_size = Vector2(34, 0)
	row.add_child(key)
	var value := _label(text, 17, color)
	value.name = "value"
	row.add_child(value)
	return row


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 56)
	button.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_button_text(button, 22)
	button.add_theme_stylebox_override("normal", _button_box(false))
	button.add_theme_stylebox_override("hover", _button_box(false))
	button.add_theme_stylebox_override("disabled", _button_box(false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", _button_box(true))
	return button


func _button_box(pressed: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 12)
	var sink: int = SINK if pressed else 0
	box.content_margin_top = 10 + sink
	box.content_margin_bottom = 10 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
