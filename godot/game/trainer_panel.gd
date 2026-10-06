class_name TrainerPanel
extends PanelContainer

## PT 트레이너 창 — 메뉴 판의 **트레이너** 로 연다 (2026-10-06 요청). 모은 트레이너를 등급 탭으로 보고,
## 하나를 골라 **동행**(같이 싸운다) · **돌려보내기**. 갖고만 있어도 붙는 **보유 효과** 합계를 아래에 적는다.
## 뽑기는 상점(뽑기 → 트레이너)에서 한다 → docs/features/trainers.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ─────────────────────────────────── X
##   │ 전체 │ 일반 │ 고급 │ 희귀 │ 영웅 │ 전설 │                      트레이너 │ ← 등급 탭
##   ├────────────────────────────────────────────┬────────────────────────┤
##   │ ┌────┐┌────┐┌────┐┌────┐┌────┐             │   [큰 원화]            │
##   │ │원화││    ││    ││    ││    │  ← 카드      │   이름 (등급 색)        │
##   │ │이름││    ││    ││    ││    │    (스크롤)  │   계승 · 보유 효과      │
##   │ └────┘└────┘└────┘└────┘└────┘             │   [ 동행 ]             │
##   ├────────────────────────────────────────────┴────────────────────────┤
##   │ 모은 트레이너 12 / 53   보유 효과  공격력 +5% · 방어력 +3% …            │

signal pick_requested(id: String)

const STONE_IN := 30
const COLUMNS := 5
const CARD_SIZE := Vector2(150, 232)
const ART_SIZE := Vector2(126, 168)
const DETAIL_WIDTH := 380.0
const DETAIL_ART := Vector2(240, 320)
const TITLE_ROOM := 72

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")

## 탭 — 0 은 전체, 1 ~ 5 는 등급
var _tab := 0
var _selected := ""
var _me: Dictionary = {}
var _seen := ""
var _portrait := Callable()

var _tabs: Array = []
var _grid: GridContainer
var _detail_art: TextureRect
var _detail_name: Label
var _detail_grade: Label
var _detail_lines: Label
var _pick: Button
var _summary: Label


## `portrait` 는 트레이너 id → 원화 Texture2D (없으면 null) — `game.gd` 의 `_trainer_art`
static func make(frame_box: Callable, portrait: Callable) -> TrainerPanel:
	var panel := TrainerPanel.new()
	panel._portrait = portrait
	panel._build(frame_box)
	return panel


func _build(frame_box: Callable) -> void:
	name = "TrainerPanel"
	visible = false
	add_theme_stylebox_override("panel", frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var head := HBoxContainer.new()
	head.name = "head"
	head.add_theme_constant_override("separation", 4)
	column.add_child(head)
	var names := ["전체"]
	for g in Trainers.grades():
		names.append(str(g.name))
	for index in names.size():
		var tab := Button.new()
		tab.name = "tab_%d" % index
		tab.text = names[index]
		tab.custom_minimum_size = Vector2(104, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 22)
		tab.pressed.connect(_pick_tab.bind(index))
		head.add_child(tab)
		_tabs.append(tab)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var title := _label("트레이너", 30, TITLE)
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

	var shelf := MarginContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		shelf.add_theme_constant_override("margin_" + side, 14)
	body.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	body.add_child(_rule(Vector2(1, 0)))

	# 오른쪽 — 고른 트레이너
	var detail := VBoxContainer.new()
	detail.name = "detail"
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail.alignment = BoxContainer.ALIGNMENT_CENTER
	detail.add_theme_constant_override("separation", 10)
	body.add_child(detail)
	_detail_art = TextureRect.new()
	_detail_art.name = "art"
	_detail_art.custom_minimum_size = DETAIL_ART
	_detail_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	detail.add_child(_detail_art)
	_detail_name = _label("", 26, IVORY)
	_detail_name.name = "name"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_name)
	_detail_grade = _label("", 18, DIM)
	_detail_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_grade)
	_detail_lines = _label("", 19, IVORY)
	_detail_lines.name = "lines"
	_detail_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_lines)
	_pick = Button.new()
	_pick.name = "pick"
	_pick.custom_minimum_size = Vector2(220, 58)
	_pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.add_theme_font_size_override("font_size", 24)
	_pick.pressed.connect(_on_pick)
	detail.add_child(_pick)

	column.add_child(_rule(Vector2(0, 1)))
	_summary = _label("", 18, IVORY)
	_summary.name = "summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 56)
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_summary)

	_pick_tab(0)


func open() -> void:
	visible = true
	_seen = ""
	if not _me.is_empty():
		refresh(_me)


func close_panel() -> void:
	visible = false


## 스냅샷(`trainers` · `trainer_active`)으로 다시 그린다. `_refresh_status` 가 매 프레임 부르므로
## 보이는 동안 **바뀐 것이 있을 때만** 다시 짓는다
func refresh(me: Dictionary) -> void:
	_me = me
	if _selected == "" and me.has("trainers"):
		var active := str(me.get("trainer_active", ""))
		_selected = active if active != "" else str(Trainers.all()[0].id)
	var seen := str(me.get("trainers", {})) + "|" + str(me.get("trainer_active", ""))
	if not visible or seen == _seen:
		return
	_seen = seen
	_fill()


func select(id: String) -> void:
	_selected = id
	_fill()


func cards() -> Array:
	return _grid.get_children()


func tab_buttons() -> Array:
	return _tabs


func detail_name() -> String:
	return _detail_name.text


func pick_button() -> Button:
	return _pick


func summary_text() -> String:
	return _summary.text


func _pick_tab(index: int) -> void:
	_tab = index
	for i in _tabs.size():
		_paint_tab(_tabs[i], i == index)
	_fill()


func _fill() -> void:
	for card in _grid.get_children():
		_grid.remove_child(card)
		card.queue_free()
	var owned: Dictionary = _me.get("trainers", {})
	var active := str(_me.get("trainer_active", ""))
	for info in Trainers.all():
		if _tab != 0 and int(info.grade) != _tab:
			continue
		var id := str(info.id)
		var card := TrainerPanel.make_card(info, _art(id), int(owned.get(id, 0)), id == active, id == _selected)
		var hit := Button.new()
		hit.name = "hit"
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(select.bind(id))
		card.add_child(hit)
		_grid.add_child(card)
	_fill_detail(owned, active)
	_fill_summary(owned)


func _fill_detail(owned: Dictionary, active: String) -> void:
	var info := Trainers.trainer(_selected)
	if info.is_empty():
		return
	var grade := Trainers.grade(int(info.grade))
	var have := int(owned.get(_selected, 0))
	_detail_art.texture = _art(_selected)
	_detail_art.modulate = Color.WHITE if have > 0 else Color(0.35, 0.35, 0.35)
	_detail_name.text = str(info.name)
	_detail_name.add_theme_color_override("font_color", TrainerPanel.grade_color(int(info.grade)))
	_detail_grade.text = "%s 등급" % str(grade.get("name", ""))
	var lines := [
		"동행 시 능력치 %d%% 계승" % int(info.inherit),
		"보유 효과  %s" % TrainerPanel.owned_text(info),
		"보유 %d" % have if have > 0 else "미보유",
	]
	_detail_lines.text = "\n".join(lines)
	if have <= 0:
		_pick.text = "미보유"
		_pick.disabled = true
	elif _selected == active:
		_pick.text = "돌려보내기"
		_pick.disabled = false
	else:
		_pick.text = "동행"
		_pick.disabled = false


func _fill_summary(owned: Dictionary) -> void:
	var count := 0
	for id in owned:
		if int(owned[id]) > 0 and not Trainers.trainer(str(id)).is_empty():
			count += 1
	var bonus := Trainers.owned_bonus(owned)
	var parts: Array = []
	for stat in ["attack", "defense", "maxHp", "crit", "critDamage"]:
		var value := float(bonus[stat])
		if value <= 0.0:
			continue
		var pct := value * 100.0 if stat in ["crit", "critDamage"] else value
		parts.append("%s +%d%%" % [Trainers.stat_name(stat), roundi(pct)])
	_summary.text = "  모은 트레이너 %d / %d     보유 효과  %s" % [
		count, Trainers.all().size(), " · ".join(parts) if not parts.is_empty() else "없음",
	]


func _on_pick() -> void:
	if _pick.disabled:
		return
	var active := str(_me.get("trainer_active", ""))
	pick_requested.emit("" if _selected == active else _selected)


func _art(id: String) -> Texture2D:
	return _portrait.call(id) if _portrait.is_valid() else null


## 카드 한 장 — 트레이너 창 · 뽑기 결과가 같이 쓴다. 원화 · 등급 색 테 · 이름 · 표시(동행 / ×개수 / 미보유)
static func make_card(info: Dictionary, art: Texture2D, have: int, active: bool, picked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "card_%s" % str(info.get("id", ""))
	card.custom_minimum_size = CARD_SIZE
	var color := TrainerPanel.grade_color(int(info.get("grade", 1)))
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GOLD if picked else color
	box.set_border_width_all(3 if picked else 2)
	box.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", box)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	var pic := TextureRect.new()
	pic.name = "art"
	pic.custom_minimum_size = ART_SIZE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = art
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if have <= 0:
		pic.modulate = Color(0.3, 0.3, 0.3)
	stack.add_child(pic)
	var label := Label.new()
	label.name = "name"
	label.text = str(info.get("name", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color.lightened(0.35) if have > 0 else DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	var tag := Label.new()
	tag.name = "tag"
	tag.text = "동행" if active else ("×%d" % have if have > 1 else ("" if have == 1 else "미보유"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", GOLD if active else DIM)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(tag)
	return card


## 등급 색 — 장비 등급과 같은 표 (`combat.json` 의 gradeColors)
static func grade_color(grade: int) -> Color:
	var colors: Array = GameData.load_table("combat").get("gradeColors", [])
	if grade < 1 or grade > colors.size():
		return IVORY
	return Color(str(colors[grade - 1]))


## "공격력 +8%" — 치명타 둘은 %p 지만 화면에는 % 로 적는다
static func owned_text(info: Dictionary) -> String:
	return "%s +%d%%" % [Trainers.stat_name(str(info.get("stat", ""))), int(info.get("owned", 0))]


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
