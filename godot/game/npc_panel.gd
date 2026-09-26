class_name NpcPanel
extends PanelContainer

## 상점·대장간 창 (docs/features/npc-town.md). **조각을 조립한다** — 전직 창(`JobPanel`)과
## 같은 얇은 금테 결이다 (docs/features/ui-art-style.md):
##
##   창 바탕(ui_panel) ─ 여백 ─┬─ 제목 "상점" · NPC 이름                      [X]
##                            ├─ 가르는 금선
##                            ├─ [사기][팔기]                   골드 1,234 · 가방 12/200
##                            ├─ 목록(ui_slot, 끌어서 내림) ─ 줄: [아이콘] 이름 / 부위·Lv  [ 120 G ]
##                            └─ 한 줄 안내 ("줄을 누르면 삽니다")
##
## 처음 판은 고도 기본 패널에 글자·단추만 쌓았다 → 2026-09-26 "같은 결로 다시 만들어".
## **줄 전체가 단추다** — 끌기와 누르기를 가르는 것은 가방·스킬 목록과 같은 `DragScroll` 이
## 한다(줄마다 `hit`). 판정은 World 다: 줄을 누르면 `buy`·`sell`·`enhance` 신호만 낸다.

signal buy(item_id: String)
signal sell(index: int)
signal enhance(index: int)

const WIDTH := 660.0
## 목록 높이 — 줄 넷이 조금 넘게 보인다 (나머지는 끌어서). 창이 720 화면에 여유 있게 들어가야 한다
const LIST_H := 330.0
const PANEL_MARGIN := 26
const BUTTON_MARGIN := 28
const SLOT_MARGIN := 26
const PAD := 30
const ROW_H := 72
const ROW_GAP := 6
const ICON := 54
const TAG := Vector2(132, 48)
const TAB := Vector2(116, 48)
const PRESS_TINT := Color(1.45, 1.3, 1.0)

## 색 — ui-art-style.md 의 표 (전직 창과 같다)
const TITLE := Color("#e8c14a")
const GOLD := Color("#dfc97a")
const GOLD_HI := Color("#f1dc9c")
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const DARK := Color("#191a19")
const WARN := Color("#d9644f")

var _frame_box := Callable()
var _icon := Callable()
## `game.gd` 의 `_item_icon(stack) -> 그림 이름` · `_grade_tint(grade) -> Color`
var _item_icon := Callable()
var _grade_tint := Callable()
## 지금 내 캐릭터(스냅샷)를 주는 손 — 탭을 눌러 다시 그릴 때도 새 값을 읽는다
var _me := Callable()

## 테스트가 읽는다 — 제목 · 목록(줄들) · 상점이 파는 id
var title_label: Label
var list: VBoxContainer
var items: Array = []

var _npc: Label
var _tabs: HBoxContainer
var _wallet: Label
var _hint: Label
var _scroll: ScrollContainer
var _drag: DragScroll
var _role := ""
var _tab := ""


static func make(frame_box: Callable, icon: Callable, item_icon: Callable, grade_tint: Callable,
		me: Callable) -> NpcPanel:
	var panel := NpcPanel.new()
	panel._me = me
	panel._frame_box = frame_box
	panel._icon = icon
	panel._item_icon = item_icon
	panel._grade_tint = grade_tint
	panel._build()
	return panel


func _build() -> void:
	name = "NpcPanel"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", _frame_box.call("ui_panel", PANEL_MARGIN, 0))
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD)
	add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	pad.add_child(column)

	# 제목 — 닫기 X 는 game.gd 의 `_close_button` 이 단다
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	column.add_child(head)
	title_label = _label("", 32, TITLE)
	head.add_child(title_label)
	_npc = _label("", 18, DIM)
	head.add_child(_npc)
	var rule := ColorRect.new()
	rule.color = FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	# 탭 · 지갑
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	column.add_child(bar)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_tabs)
	_wallet = _label("", 18, IVORY)
	_wallet.name = "wallet"
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_wallet)

	# 목록 — 어두운 칸 안에서 끌어 내린다
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _frame_box.call("ui_slot", SLOT_MARGIN, 10))
	column.add_child(box)
	_scroll = ScrollContainer.new()
	_scroll.name = "scroll"
	_scroll.custom_minimum_size = Vector2(0, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_bar(_scroll.get_v_scroll_bar())
	box.add_child(_scroll)
	list = VBoxContainer.new()
	list.name = "rows"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ROW_GAP)
	_scroll.add_child(list)
	_drag = DragScroll.attach(_scroll, list, ROW_GAP)

	_hint = _label("", 16, DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


## 연다. `role` 은 `shop`(사기·팔기) · `smith`(강화)
func open(npc_name: String, role: String, title: String, stock: Array) -> void:
	_role = role
	items = stock
	_tab = "buy" if role == "shop" else "enhance"
	title_label.text = title if title != "" else npc_name
	_npc.text = npc_name
	_drag.forget()
	_scroll.scroll_vertical = 0
	redraw()
	visible = true


## 사고팔고 두드리는 동안 계속 바뀐다 — 그때마다 통째로 다시 그린다
func redraw() -> void:
	var me: Dictionary = _me.call()
	if me.is_empty():
		return
	_draw_tabs()
	_wallet.text = "골드 %s   가방 %d/%d" % [
		_comma(int(me.get("gold", 0))), me.get("bag", []).size(), Items.bag_size()
	]
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	match _tab:
		"buy":
			_list_buy(me)
			_hint.text = "줄을 누르면 삽니다  ·  살 때 옵션이 붙습니다"
		"sell":
			_list_bag(me, "sell")
			_hint.text = "줄을 누르면 팝니다"
		"enhance":
			_list_bag(me, "enhance")
			_hint.text = "줄을 누르면 한 단계 두드립니다  ·  실패하면 부서집니다"


func _draw_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var names := {"buy": "사기", "sell": "팔기"} if _role == "shop" else {"enhance": "강화"}
	for key in names:
		var on: bool = _tab == key
		var tab := Button.new()
		tab.name = "tab_" + str(key)
		tab.text = names[key]
		tab.custom_minimum_size = TAB
		tab.add_theme_font_size_override("font_size", 22)
		tab.add_theme_color_override("font_color", GOLD_HI if on else DIM)
		tab.add_theme_color_override("font_hover_color", GOLD_HI if on else IVORY)
		tab.add_theme_color_override("font_pressed_color", GOLD_HI)
		tab.add_theme_color_override("font_focus_color", GOLD_HI if on else DIM)
		var box := _tag_box(PRESS_TINT if on else Color(0.55, 0.55, 0.55))
		for state in ["normal", "hover", "pressed", "focus"]:
			tab.add_theme_stylebox_override(state, box)
		tab.pressed.connect(func() -> void:
			_tab = str(key)
			_scroll.scroll_vertical = 0
			redraw()
		)
		_tabs.add_child(tab)


func _list_buy(me: Dictionary) -> void:
	var gold := int(me.get("gold", 0))
	if items.is_empty():
		_empty("지금 레벨에 파는 것이 없습니다")
	for id in items:
		var item := Items.get_item(str(id))
		var price := int(item.get("price", 0))
		var grade := int(item.get("grade", 1))
		var poor := gold < price
		_add_row(
			{"id": str(id), "grade": grade},
			str(item.get("name", id)),
			"%s  ·  Lv.%d" % [Items.slot_label(str(item.get("slot", ""))), int(item.get("level", 1))],
			"%s G" % _comma(price), WARN if poor else GOLD, poor,
			func() -> void: buy.emit(str(id)),
		)


## 팔기·강화 — 가방의 장비. 재료(크리스탈·물약)는 팔지도 강화하지도 않는다
func _list_bag(me: Dictionary, mode: String) -> void:
	var bag: Array = me.get("bag", [])
	var shown := 0
	for index in bag.size():
		var stack: Dictionary = bag[index]
		if Items.is_material(str(stack.get("id", ""))):
			continue
		var item := Items.get_item(str(stack.get("id", "")))
		if item.is_empty():
			continue
		shown += 1
		var grade := int(stack.get("grade", 1))
		var level := int(stack.get("enhance", 0))
		var name_text := Items.stack_name(stack) + (" +%d" % level if level > 0 else "")
		var sub := "%s  ·  %s" % [Items.slot_label(str(item.get("slot", ""))), Items.grade_name(grade)]
		var tag := ""
		var tag_color := GOLD
		var blocked := false
		if mode == "sell":
			tag = "%s G" % _comma(Items.sell_price(item, grade))
		elif not Items.can_enhance(level):
			tag = "최대"
			tag_color = DIM
			blocked = true
		else:
			tag = "+%d → +%d" % [level, level + 1]
			var odds := Items.enhance_odds(level)
			sub = "성공 %d%%" % roundi(float(odds.success) * 100.0)
			# 값표는 금색 그대로 — 모든 단계에 파괴 확률이 있어 값표까지 붉히면 전부 붉다.
			# 경고는 설명 줄("실패 시 파괴")만 붉힌다
			if float(odds.destroy) > 0.0:
				sub += "  ·  실패 시 파괴"
		var at: int = index
		_add_row(stack, name_text, sub, tag, tag_color, blocked, func() -> void:
			if mode == "sell":
				sell.emit(at)
			else:
				enhance.emit(at)
		)
	if shown == 0:
		_empty("가방에 장비가 없습니다")


## 줄 하나 — [아이콘] 이름 / 한 줄 설명  [값표]. **줄 전체가 누르는 자리**(`hit`)다
func _add_row(stack: Dictionary, title: String, sub: String, tag: String, tag_color: Color,
		blocked: bool, action: Callable) -> void:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.add_theme_stylebox_override("panel", _row_box())
	list.add_child(row)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)

	var grade := int(stack.get("grade", 1))
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(ICON, ICON)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_theme_stylebox_override("panel", _icon_box(grade))
	line.add_child(cell)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = _icon.call(str(_item_icon.call(stack)))
	cell.add_child(picture)

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(words)
	var name_label := _label(title, 21, _grade_tint.call(grade))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	words.add_child(name_label)
	var sub_label := _label(sub, 15, WARN if sub.contains("파괴") else DIM)
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label.clip_text = true
	words.add_child(sub_label)

	var price := PanelContainer.new()
	price.name = "tag"
	price.custom_minimum_size = TAG
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_theme_stylebox_override("panel", _tag_box(Color(0.55, 0.55, 0.55) if blocked else Color.WHITE))
	line.add_child(price)
	var price_label := _label(tag, 19, tag_color)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.add_child(price_label)

	if blocked:
		row.modulate = Color(1, 1, 1, 0.6)
	# 줄 전체를 덮는 누름 자리. DragScroll 이 떼는 자리에서 `pressed` 를 낸다
	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.disabled = blocked
	hit.pressed.connect(func() -> void:
		# DragScroll 은 `disabled` 를 안 보고 `pressed` 를 낸다 — 막힌 줄은 여기서 거른다
		if not hit.disabled:
			action.call()
	)
	row.add_child(hit)


func _empty(text: String) -> void:
	var label := _label(text, 20, DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, ROW_H)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	list.add_child(label)


## 줄 바탕 — 어두운 판에 가는 테. 조각(ui_slot)을 줄마다 깔면 테가 두꺼워 보여 코드로 그린다
func _row_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#202321")
	box.border_color = FAINT
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


## 아이콘 칸 — 가방 칸처럼 **등급은 테 색이 말한다**
func _icon_box(grade: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = DARK
	box.border_color = _grade_tint.call(grade)
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(4)
	return box


## 값표·탭 — 단추 조각(ui_button). `tint` 로 달아오르게(고른 탭) 하거나 흐리게(막힘) 한다
func _tag_box(tint: Color) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 6)
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = tint
	return box


## 스크롤 막대 — 기본(회색)은 이 창에서만 튄다. 어두운 홈에 짙은 금 손잡이
func _style_bar(bar: VScrollBar) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(DARK, 0.8)
	groove.set_corner_radius_all(4)
	groove.content_margin_left = 6
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color("#86714d")
	grab.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", groove)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab)
	bar.add_theme_stylebox_override("grabber_pressed", grab)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func _comma(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + out
