class_name DropPanel
extends PanelContainer

## 사냥터 드랍 창 — 차원문 창에서 사냥터 줄의 **느낌표**를 누르면 그 사냥터에서 떨어지는 것을
## 보인다 (2026-09-30 요청: "포탈UI에서 각 사냥터별로 느낌표 눌러서, 드랍되는 아이템 표시하는 UI").
## 내용은 판정이 굴리는 것 그대로다 (`Items.zone_drops`) — 표를 따로 두지 않는다.
## **확률은 적지 않는다** (같은 날 요청: "확률은 넣지마. 그리고 등장 몬스터 능력치도 표시해").
##
##   돌판 틀(ui_dungeon_card) ─┬─ [문장][존 이름][X]
##                             ├─ 금
##                             └─ 스크롤 ─┬─ "등장 몬스터" — 종류마다 [이름 · 치명타 저항] / 체력 · 공격 · 방어
##                                        ├─ 등급 머리 [등급 이름 (등급 색)]
##                                        │  격자 3칸 × 2줄 — 슬롯 6종 [등급 테 아이콘][이름]
##                                        ├─ (다음 등급)
##                                        └─ "그 밖에" — 골드 폭 · 크리스탈
##
## 차원문 창(`GatePanel`)의 아이 노드지만 **`top_level`** 이라 목록 칸을 따르지 않고 화면 가운데에
## 앵커로 선다. 차원문 창이 닫히면 같이 사라진다 (보이기는 부모를 따른다)

## 창 폭(기준 해상도 1280×720 의 px). 높이는 화면 위아래 ANCHOR_Y 만큼 비운 나머지 —
## 차원문 창과 같은 6% 라 그 창을 위아래로 다 덮는다. 두 등급 사냥터가 한 화면에 들어간다
## (0.08 이면 내용 476 / 칸 470px 로 넘쳤다). 더 작은 화면은 끌어서 내린다
const WIDTH := 640.0
const ANCHOR_Y := 0.06
## 한 줄에 놓는 장비 칸 수 — 슬롯 6종이 두 줄로 떨어진다
const COLUMNS := 3
## 장비 칸 아이콘 한 변
const ICON := 48
const NAME_FONT := 20
const HEAD_FONT := 24
const GAP := 8

## 판정에서 그대로 빼 온 내용 (테스트용) · 지금 보이는 존
var drops: Dictionary = {}
var zone_id := ""

var _title: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _drag: DragScroll
## 조각을 여는 손 — 차원문 창의 `_box(이름, 9조각 여백, 안쪽 여백)` · `_piece(이름)`
var _box := Callable()
var _piece := Callable()


static func make(box: Callable, piece: Callable) -> DropPanel:
	var panel := DropPanel.new()
	panel._box = box
	panel._piece = piece
	panel._build()
	return panel


func _build() -> void:
	name = "DropPanel"
	visible = false
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = ANCHOR_Y
	anchor_bottom = 1.0 - ANCHOR_Y
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 0.0
	offset_bottom = 0.0
	add_theme_stylebox_override("panel", _box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, GatePanel.PAD + 4))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var emblem := TextureRect.new()
	emblem.texture = _piece.call("ui_gate_go")
	emblem.custom_minimum_size = Vector2(GatePanel.EMBLEM, GatePanel.EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.visible = emblem.texture != null
	head.add_child(emblem)
	_title = _label("", GatePanel.PAGE_TITLE_SIZE, GatePanel.PAGE_TITLE_COLOR)
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	# 닫기 X — 차원문 창과 같은 조각. 닫으면 차원문 목록으로 돌아간다
	var close := Button.new()
	close.name = "Close"
	close.custom_minimum_size = Vector2(GatePanel.CLOSE_BTN, GatePanel.CLOSE_BTN)
	close.expand_icon = true
	close.icon = _piece.call("ui_close")
	if close.icon == null:
		close.text = "X"
	for key in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	close.pressed.connect(close_panel)
	head.add_child(close)

	var line := ColorRect.new()
	line.color = GatePanel.HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.get_v_scroll_bar().custom_minimum_size.x = GatePanel.BAR_WIDTH
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", GAP)
	_scroll.add_child(_list)
	# 끌어서 내린다 — 가방·강화 목록과 같은 길 (`DragScroll`). 칸에 누르는 것은 없다
	_drag = DragScroll.attach(_scroll, _list, GAP)


## 그 사냥터의 드랍을 채워 연다. 떨어지는 것이 없으면(마을) 열지 않는다
func show_zone(id: String) -> void:
	drops = Items.zone_drops(id)
	if drops.is_empty():
		return
	zone_id = id
	_title.text = str(GameData.zone(id).get("name", id))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_add_head("등장 몬스터", GatePanel.CARD_SUB_COLOR)
	var mobs := VBoxContainer.new()
	mobs.name = "Monsters"
	mobs.add_theme_constant_override("separation", GAP)
	for kind in drops.kinds:
		mobs.add_child(_monster_cell(GameData.monster_kind(str(kind))))
	_list.add_child(mobs)
	for grade in drops.grades:
		_add_grade(int(grade))
	_add_head("그 밖에", GatePanel.CARD_SUB_COLOR)
	var misc := _grid()
	var gold: Vector2i = drops.gold
	misc.add_child(_cell("gold", "골드 %d~%d" % [gold.x, gold.y], GatePanel.CELL_LINE, GatePanel.TEXT_COLOR))
	if bool(drops.crystal):
		var crystal := Items.crystal_id()
		misc.add_child(_cell(crystal, Items.stack_name({"id": crystal}), GatePanel.CELL_LINE, GatePanel.TEXT_COLOR))
	_list.add_child(misc)
	_scroll.scroll_vertical = 0
	_drag.forget()
	visible = true


func close_panel() -> void:
	_drag.forget()
	visible = false


## 몬스터 한 칸 — 윗줄 이름(보스면 표시) · 치명타 저항, 아랫줄 능력치. 값은 몬스터 표(`monsters.json`) 그대로다
func _monster_cell(kind: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.name = "Monster"
	cell.add_theme_stylebox_override("panel", _cell_box())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	cell.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	top.add_child(_label(str(kind.get("name", "")), HEAD_FONT, GatePanel.PAGE_TITLE_COLOR))
	# **레벨은 적지 않는다** (2026-09-30 요청: "몬스터 레벨은 표기하지 마"). 보스만 옅은 글자로 표시한다.
	# 이 칸이 늘어나 치명타 저항을 오른쪽 끝으로 민다
	var tag := _label("보스" if bool(kind.get("boss", false)) else "", NAME_FONT, GatePanel.CARD_SUB_COLOR)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tag)
	# 치명타 저항 — 때리는 쪽 치확에서 빼는 %p (`critResist`, 100레벨 사냥터부터). 능력치 줄에 넣으면
	# 뒤 사냥터(체력 백만 단위)에서 창 폭을 넘어 윗줄 오른쪽에 둔다 (2026-09-30 요청)
	var resist := _label("치명타 저항 %s%%" % String.num(float(kind.get("critResist", 0.0)) * 100.0, 1),
		NAME_FONT, GatePanel.TEXT_COLOR)
	resist.name = "CritResist"
	top.add_child(resist)
	var stats := _label("체력 %s     공격 %s     방어 %s" % [
		number(int(kind.get("maxHp", 0))), number(int(kind.get("attack", 0))), number(int(kind.get("defense", 0))),
	], NAME_FONT, GatePanel.TEXT_COLOR)
	stats.name = "Stats"
	column.add_child(stats)
	return cell


## 등급 하나 — 머리 줄(등급 이름, 등급 색) + 슬롯 6종 칸
func _add_grade(grade: int) -> void:
	var tint := ChatLog.grade_text_color(grade)
	_add_head(Items.grade_name(grade), tint)
	var grid := _grid()
	for slot in Items.slots():
		var item := Items.get_item(Items.item_id(grade, str(slot)))
		# 그림은 가방과 같은 이름 — 등급별 그림(`<슬롯>_g<등급>`)이 있으면 그것, 없으면 슬롯 그림
		var graded := "%s_g%d" % [slot, grade]
		var icon_name := graded if _piece.call(graded) != null else str(slot)
		grid.add_child(_cell(icon_name, str(item.get("name", slot)), Items.grade_color(grade), tint))
	_list.add_child(grid)


## 머리 줄 — 칸 무리의 이름
func _add_head(text: String, color: Color) -> void:
	var head := _label(text, HEAD_FONT, color)
	head.name = "Head"
	_list.add_child(head)


## 칸 격자. **칸을 다 채운 뒤에 목록에 넣는다** — `DragScroll` 은 목록에 들어오는 순간의
## 자식만 입력을 비키게 하므로, 넣고 나서 단 칸(`PanelContainer`, 기본 STOP)은 끌기를 먹는다
func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	return grid


## 칸 하나 — 던전 보상 칸과 같은 결: 어두운 평판에 가는 선, 아이콘 칸 테는 등급 색
func _cell(icon_name: String, text: String, edge: Color, text_color: Color) -> Control:
	var cell := PanelContainer.new()
	cell.name = "Cell"
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", _cell_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cell.add_child(row)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(ICON, ICON)
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	slot_box.border_color = edge
	slot_box.set_border_width_all(2)
	slot.add_theme_stylebox_override("panel", slot_box)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _piece.call(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(icon)
	row.add_child(slot)
	var label := _label(text, NAME_FONT, text_color)
	label.name = "Name"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return cell


func _cell_box() -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GatePanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## 세 자리마다 쉼표 (1137758 → 1,137,758) — 뒤 사냥터 몬스터 체력이 백만 단위다
static func number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
