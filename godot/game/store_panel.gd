class_name StorePanel
extends PanelContainer

## 상점 창 — 메인 카테고리 탭(위) · 서브 카테고리 목록(왼쪽) · 상품 카드 격자(오른쪽)
## (2026-10-02 요청: 다른 게임의 상점 스크린샷 + "이런식으로 상점 만들거야 … 상품 패스 교환소 이쪽이 메인
## 카테고리고, 프로모션 클래스체인지 이쪽이 서브 카테고리야"). **상품은 아직 없다** — 카테고리만 선다
## → docs/features/store.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ─────────────────────────────────── X
##   │ 상품 │ 월정액 │                                          상점   │  ← 메인 탭 (고른 것 금빛 + 밑줄)
##   ├──────────────┬──────────────────────────────────────────────────┤
##   │▌초보자 패키지 │ ┌ 이름 ──────┐ ┌──────────┐ ┌──────────┐       │
##   │  재화         │ │ 설명        │ │          │ │          │       │  ← 상품 카드 3열 (스크롤)
##   │               │ │  [그림]     │ │          │ │          │       │
##   │               │ │ KRW 55,000  │ │          │ │          │       │
##
## 판정(결제·지급)은 아직 없다 — 붙일 때 서버가 본다 (server.md "다이아").

## 메인 → 서브. 상품은 `set_products("<메인 id>/<서브 id>", [...])` 로 넣는다
const CATEGORIES := [
	{"id": "goods", "name": "상품", "subs": [
		{"id": "starter", "name": "초보자 패키지"},
		{"id": "currency", "name": "재화"},
	]},
	{"id": "monthly", "name": "월정액", "subs": [
		{"id": "goods", "name": "상품"},
	]},
]

const STONE_IN := 30
const SIDE_WIDTH := 240.0
const COLUMNS := 3
const CARD_SIZE := Vector2(270, 236)
const CARD_ART := 116.0
## 제목이 오른쪽 위 X 에 안 걸리게 비워 두는 몫
const TITLE_ROOM := 72

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")

var _icon := Callable()

var _main := 0
var _sub := 0
var _products: Dictionary = {}

var _tabs: Array = []
var _side: VBoxContainer
var _rows: Array = []
var _grid: GridContainer
var _empty: Label


## `frame_box` · `icon` 은 `game.gd` 것을 받는다 (헬스·도감 창과 같다)
static func make(frame_box: Callable, icon: Callable) -> StorePanel:
	var panel := StorePanel.new()
	panel._icon = icon
	panel._build(frame_box)
	return panel


func _build(frame_box: Callable) -> void:
	name = "StorePanel"
	visible = false
	add_theme_stylebox_override("panel", frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# 메인 탭 — 받은 그림처럼 판 없이 글자만, 고른 것은 금빛 글자 + 밑줄. 오른쪽 끝에 창 이름
	var head := HBoxContainer.new()
	head.name = "head"
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	for index in CATEGORIES.size():
		var tab := Button.new()
		tab.name = "tab_%s" % CATEGORIES[index].id
		tab.text = str(CATEGORIES[index].name)
		tab.custom_minimum_size = Vector2(160, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_pick_main.bind(index))
		head.add_child(tab)
		_tabs.append(tab)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var title := _label("상점", 30, TITLE)
	title.name = "title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var room := Control.new()
	room.custom_minimum_size = Vector2(TITLE_ROOM, 0)
	head.add_child(room)
	column.add_child(_rule(Vector2(0, 1)))

	var body := HBoxContainer.new()
	body.name = "body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)

	# 서브 카테고리 — 던전 단계 창처럼 평평한 줄, 고른 줄만 옅은 금빛 바탕 + 왼쪽 금 막대
	_side = VBoxContainer.new()
	_side.name = "subs"
	_side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	_side.add_theme_constant_override("separation", 0)
	body.add_child(_side)
	body.add_child(_rule(Vector2(1, 0)))

	var shelf := MarginContainer.new()
	shelf.name = "shelf"
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		shelf.add_theme_constant_override("margin_" + side, 16)
	body.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	# 상품이 없는 서브 — 격자 자리 가운데에 한 줄
	_empty = _label("판매 중인 상품이 없습니다.", 20, DIM)
	_empty.name = "empty"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shelf.add_child(_empty)

	_pick_main(0)


func open() -> void:
	visible = true


func close_panel() -> void:
	visible = false


## 서브 하나의 상품 `[{name, note?, icon?, price}]` — price 는 원(KRW) 정수
func set_products(key: String, list: Array) -> void:
	_products[key] = list
	if key == current_key():
		_fill()


## 지금 고른 "<메인 id>/<서브 id>" — 테스트가 본다
func current_key() -> String:
	var main: Dictionary = CATEGORIES[_main]
	return "%s/%s" % [main.id, main.subs[_sub].id]


func tab_buttons() -> Array:
	return _tabs


func sub_buttons() -> Array:
	return _rows


func cards() -> Array:
	return _grid.get_children()


func empty_shown() -> bool:
	return _empty.visible


func _pick_main(index: int) -> void:
	_main = index
	for i in _tabs.size():
		_paint_tab(_tabs[i], i == index)
	for row in _rows:
		_side.remove_child(row)
		row.queue_free()
	_rows.clear()
	var subs: Array = CATEGORIES[index].subs
	for i in subs.size():
		var row := Button.new()
		row.name = "sub_%s" % subs[i].id
		row.text = str(subs[i].name)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override("font_size", 20)
		row.pressed.connect(_pick_sub.bind(i))
		_side.add_child(row)
		_rows.append(row)
	_pick_sub(0)


func _pick_sub(index: int) -> void:
	_sub = index
	for i in _rows.size():
		_paint_row(_rows[i], i == index)
	_fill()


func _fill() -> void:
	for card in _grid.get_children():
		_grid.remove_child(card)
		card.queue_free()
	var list: Array = _products.get(current_key(), [])
	for product in list:
		_grid.add_child(_card(product))
	_empty.visible = list.is_empty()


## 상품 카드 — 받은 그림의 칸: 이름 · 설명 · 가는 선 · 그림 · 값
func _card(product: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "card"
	card.custom_minimum_size = CARD_SIZE
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GatePanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", box)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)

	var title := _label(str(product.get("name", "")), 21, IVORY)
	title.name = "name"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var note := _label(str(product.get("note", "")), 15, DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(note)
	var line := _rule(Vector2(180, 1))
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(line)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0, CARD_ART)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _icon.call(str(product.get("icon", ""))) if product.has("icon") else null
	stack.add_child(art)
	var price := _label("KRW %s" % _commas(int(product.get("price", 0))), 20, IVORY)
	price.name = "price"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(price)
	return card


## 55000 → "55,000"
static func _commas(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## 헬스 창 탭과 같은 결 (`FitnessPanel._paint_tab`)
func _paint_tab(tab: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.78, 0.5, 0.08) if on else Color(0, 0, 0, 0)
	box.border_color = GOLD if on else Color(0, 0, 0, 0)
	box.border_width_bottom = 3
	box.set_content_margin_all(6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		tab.add_theme_stylebox_override(state, box)
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tab.add_theme_color_override("font_color", GOLD if on else DIM)
	tab.add_theme_color_override("font_hover_color", GOLD if on else IVORY)
	tab.add_theme_color_override("font_pressed_color", GOLD)


## 던전 단계 창의 목록 줄과 같은 결 (`GatePanel._row_box`)
func _paint_row(row: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.75, 0.45, 0.14) if on else Color(0, 0, 0, 0)
	box.border_color = GOLD if on else GatePanel.CELL_LINE
	box.border_width_left = 3 if on else 0
	box.border_width_bottom = 1
	box.content_margin_left = GatePanel.ROW_PAD_X
	box.content_margin_right = GatePanel.ROW_PAD_X
	box.content_margin_top = GatePanel.ROW_PAD + 4
	box.content_margin_bottom = GatePanel.ROW_PAD + 4
	for state in ["normal", "hover", "pressed", "disabled"]:
		row.add_theme_stylebox_override(state, box)
	row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_theme_color_override("font_color", GOLD if on else IVORY)
	row.add_theme_color_override("font_hover_color", GOLD)
	row.add_theme_color_override("font_pressed_color", GOLD)


func _rule(size: Vector2) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = size
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
