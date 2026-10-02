class_name FitnessPanel
extends PanelContainer

## 헬스 창 — 프로틴을 넣어 운동 단계를 올린다 (2026-09-30 요청: "헬스라는 컨텐츠 만들어 … 스크린샷
## 느낌으로 … 탭 이름은 벤치프레스, 데드리프트, 스쿼트"). 받은 그림은 다른 게임의 탈리스만 강화 창이다.
## 판정은 장부(`Ledger.fitness_up`)가 하고, 이 창은 장부 값(`proteins` · `fitness`)을 그리기만 한다
## → docs/features/fitness.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ────────────────────────────────── X
##   │ 벤치프레스 │ 데드리프트 │ 스쿼트 │           ← 탭 (고른 것 금빛 + 밑줄, 두드릴 수 있으면 빨간 점)
##   ├──────────────────────────────────────┬────────────────────┤
##   │          벤치프레스 8단계              │     획득 효과       │
##   │      <     [문장 그림]     >           │ ◆ 공격력 +12% → +14%│
##   │   ───────────────────────────         │ ◆ 방어력 +5%        │
##   │ 강화 성공 시   공격력 +2% 상승          │ ◆ 체력 +3%          │
##   │            ●  ○  ○                    │        재료         │
##   │                                       │ [통] 파워 프로틴     │
##   │                                       │      120 / 75       │
##   │                                       │ 강화 성공 확률  45% │
##   │                                       │ [ 자동 ]  [ 강화 ]  │
##
## 뒤의 옅은 원·눈금은 코드로 그린다 (받은 그림의 룬 원판 자리). 그림은 문장·프로틴 통만 바르코다.

signal up_requested(kind: String, auto: bool)

const SIDE_WIDTH := 400.0
const STONE_IN := 30
const EMBLEM := 300.0
const PROTEIN_ICON := 64.0
const BUTTON_MARGIN := 28
const SINK := 3

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const NEXT := Color("#6fc9d6")
const OK := Color("#a9c77a")
const WARN := Color("#d9644f")
const RING := Color(0.86, 0.78, 0.55, 0.07)

var _frame_box := Callable()
var _icon := Callable()

var _kind := 0
var _me: Dictionary = {}
var _seen := ""

var _tabs: Array = []
var _tab_dots: Array = []
var _title: Label
var _emblem: TextureRect
var _next_label: Label
var _next_value: Label
var _page_dots: Array = []
var _flash: Label
var _effects: VBoxContainer
var _protein_icon: TextureRect
var _protein_name: Label
var _protein_count: Label
var _chance: Label
var _auto_button: Button
var _up_button: Button


## `frame_box` · `icon` 은 `game.gd` 것을 받는다 (던전 결과창과 같다)
static func make(frame_box: Callable, icon: Callable) -> FitnessPanel:
	var panel := FitnessPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	return panel


func _build() -> void:
	name = "FitnessPanel"
	visible = false
	add_theme_stylebox_override("panel", _frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# 탭 — 받은 그림처럼 판 없이 글자만, 고른 것은 금빛 글자 + 밑줄
	var tabs := HBoxContainer.new()
	tabs.name = "tabs"
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	var kinds := Fitness.kinds()
	for index in kinds.size():
		var tab := Button.new()
		tab.name = "tab_%s" % str(kinds[index].id)
		tab.text = str(kinds[index].name)
		tab.custom_minimum_size = Vector2(180, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_pick.bind(index))
		tabs.add_child(tab)
		_tabs.append(tab)
		_tab_dots.append(_red_dot(tab))
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(_build_stage())
	body.add_child(_build_side())


## 왼쪽 큰 칸 — 제목 · 문장 · 다음 단계 한 줄 · 쪽 점
func _build_stage() -> Control:
	var stage := Control.new()
	stage.name = "stage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true

	# 받은 그림의 룬 원판 자리 — 옅은 원 셋과 눈금. 문장 가운데에 맞춘다
	var ring := Control.new()
	ring.name = "ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.draw.connect(_draw_ring.bind(ring))
	ring.resized.connect(ring.queue_redraw)
	stage.add_child(ring)

	var center := VBoxContainer.new()
	center.name = "center"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(center)

	_title = _label("", 34, TITLE)
	_title.name = "title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	center.add_child(row)
	row.add_child(_chevron(-1))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(EMBLEM, EMBLEM)
	row.add_child(holder)
	_emblem = TextureRect.new()
	_emblem.name = "emblem"
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emblem.pivot_offset = Vector2(EMBLEM, EMBLEM) * 0.5
	holder.add_child(_emblem)
	# 성공 · 실패를 문장 위에 잠깐 띄운다 (`show_result`)
	_flash = _label("", 52, OK)
	_flash.name = "flash"
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_flash.add_theme_constant_override("outline_size", 10)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.modulate.a = 0.0
	holder.add_child(_flash)
	row.add_child(_chevron(1))

	# 받은 그림의 "상시 발동 / 마법 방어력 +1" 자리 — 다음 단계가 더해 주는 몫
	var line := ColorRect.new()
	line.color = FAINT
	line.custom_minimum_size = Vector2(380, 1)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(line)
	var next := HBoxContainer.new()
	next.alignment = BoxContainer.ALIGNMENT_CENTER
	next.add_theme_constant_override("separation", 48)
	center.add_child(next)
	_next_label = _label("다음 단계", 20, GOLD)
	next.add_child(_next_label)
	_next_value = _label("", 20, DIM)
	_next_value.name = "next"
	next.add_child(_next_value)

	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 22)
	center.add_child(dots)
	for index in Fitness.kinds().size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
		_page_dots.append(dot)
	return stage


## 오른쪽 칸 — 획득 효과 · 재료 · 확률 · 단추
func _build_side() -> Control:
	var side := PanelContainer.new()
	side.name = "side"
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GatePanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(16)
	side.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	side.add_child(column)

	column.add_child(_head("획득 효과"))
	_effects = VBoxContainer.new()
	_effects.name = "effects"
	_effects.add_theme_constant_override("separation", 8)
	column.add_child(_effects)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(gap)

	column.add_child(_head("재료"))
	var cell := PanelContainer.new()
	var cell_box := StyleBoxFlat.new()
	cell_box.bg_color = Color(0.05, 0.05, 0.05, 0.6)
	cell_box.border_color = GatePanel.CELL_LINE
	cell_box.set_border_width_all(1)
	cell_box.set_content_margin_all(8)
	cell.add_theme_stylebox_override("panel", cell_box)
	column.add_child(cell)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	cell.add_child(row)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(PROTEIN_ICON, PROTEIN_ICON)
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.03, 0.03, 0.03, 0.9)
	slot_box.border_color = GatePanel.CELL_LINE
	slot_box.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", slot_box)
	row.add_child(slot)
	_protein_icon = TextureRect.new()
	_protein_icon.name = "protein_icon"
	_protein_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_protein_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(_protein_icon)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	_protein_name = _label("", 20, IVORY)
	_protein_name.name = "protein_name"
	names.add_child(_protein_name)
	_protein_count = _label("", 22, OK)
	_protein_count.name = "protein_count"
	names.add_child(_protein_count)

	var chance_row := HBoxContainer.new()
	column.add_child(chance_row)
	var chance_key := _label("강화 성공 확률", 20, DIM)
	chance_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chance_row.add_child(chance_key)
	_chance = _label("", 26, GOLD)
	_chance.name = "chance"
	chance_row.add_child(_chance)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_auto_button = _button("자동", true)
	_auto_button.name = "auto"
	buttons.add_child(_auto_button)
	_up_button = _button("강화", false)
	_up_button.name = "up"
	buttons.add_child(_up_button)
	return side


## --- 여닫기 · 그리기 ---

func open() -> void:
	visible = true
	_seen = ""
	_redraw()


func close_panel() -> void:
	visible = false


## 장부가 바뀌면 다시 그린다 — `game.gd` 가 창이 떠 있는 동안 매 프레임 부른다. 같으면 안 짓는다
func refresh(me: Dictionary) -> void:
	_me = me
	if not visible:
		return
	var seen := str(_kind) + str(me.get("proteins", {})) + str(me.get("fitness", {}))
	if seen == _seen:
		return
	_seen = seen
	_redraw()


## 고른 운동 (0 부터) — 테스트가 본다
func kind_index() -> int:
	return _kind


func kind_id() -> String:
	return str(Fitness.kinds()[_kind].id)


func up_button() -> Button:
	return _up_button


func auto_button() -> Button:
	return _auto_button


func title_text() -> String:
	return _title.text


## 획득 효과 줄들의 글자 (줄마다 조각을 띄어 이음) — 테스트가 본다
func effect_texts() -> Array:
	var out: Array = []
	for line in _effects.get_children():
		var parts: Array = []
		for part in line.get_children():
			if part is Label:
				parts.append((part as Label).text)
		out.append(" ".join(parts))
	return out


## 빨간 점이 켜진 탭 (운동 id) — 테스트가 본다
func dotted_tabs() -> Array:
	var out: Array = []
	for index in _tab_dots.size():
		if (_tab_dots[index] as Control).visible:
			out.append(str(Fitness.kinds()[index].id))
	return out


## `fitnessResult` 이벤트 — 성공이면 초록 "성공!", 실패면 붉은 "실패" 를 문장 위에 띄웠다가 지운다.
## 문장에서 이펙트도 난다 — 성공은 금빛 빛줄기 · 반짝이, 실패는 금 · 잿빛 연기 (`FitnessFx`)
func show_result(event: Dictionary) -> void:
	if not visible:
		return
	var success := str(event.get("result", "")) == "success"
	_flash.text = "성공!" if success else "실패"
	_flash.add_theme_color_override("font_color", OK if success else WARN)
	_flash.modulate.a = 1.0
	_emblem.scale = Vector2.ONE * (1.12 if success else 0.94)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_emblem, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_flash, "modulate:a", 0.0, 0.5).set_delay(0.7)
	if success:
		FitnessFx.burst(_emblem.get_parent(), _emblem)
	else:
		FitnessFx.smoke(_emblem.get_parent(), _emblem)


func _pick(index: int) -> void:
	_kind = posmod(index, Fitness.kinds().size())
	_seen = ""
	refresh(_me)


func _redraw() -> void:
	var kinds := Fitness.kinds()
	var kind: Dictionary = kinds[_kind]
	var stages: Dictionary = _me.get("fitness", {})
	var have: Dictionary = _me.get("proteins", {})
	var stage := int(stages.get(str(kind.id), 0))
	var top := stage >= Fitness.max_stage()
	var step := Fitness.step(stage + 1)
	var owned := int(have.get(str(kind.protein), 0))
	var cost := int(step.get("cost", 0))

	for index in _tabs.size():
		_paint_tab(_tabs[index], index == _kind)
		(_tab_dots[index] as Control).visible = Fitness.can_up(_me, str(kinds[index].id))
	for index in _page_dots.size():
		var dot_box := StyleBoxFlat.new()
		dot_box.bg_color = GOLD if index == _kind else FAINT
		dot_box.set_corner_radius_all(5)
		(_page_dots[index] as Panel).add_theme_stylebox_override("panel", dot_box)

	_title.text = "%s %d단계" % [str(kind.name), stage]
	_emblem.texture = _icon.call("ui_fitness_" + str(kind.id)) if _icon.is_valid() else null
	if top:
		_next_label.text = "최대 단계"
		_next_value.text = "%s +%d%%" % [str(kind.statName), int(Fitness.bonus(stage))]
	else:
		_next_label.text = "강화 성공 시"
		_next_value.text = "%s +%d%% 상승" % [str(kind.statName), int(step.get("gain", 0))]

	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()
	for index in kinds.size():
		var each: Dictionary = kinds[index]
		var each_stage := int(stages.get(str(each.id), 0))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(_diamond(GOLD if index == _kind else FAINT))
		line.add_child(_label(
			"%s +%d%%" % [str(each.statName), int(Fitness.bonus(each_stage))], 21, IVORY if index == _kind else DIM
		))
		# 받은 그림의 "+1" 자리 — 몫(+2%)만 붙이면 누계에 더하는 건지 헷갈려서(2026-10-02 지적)
		# 강화하면 **얼마가 되는지**를 화살표로 보인다: "체력 +5% → +7%"
		if index == _kind and not top:
			line.add_child(_label("→", 21, DIM))
			line.add_child(_label("+%d%%" % int(Fitness.bonus(each_stage + 1)), 21, NEXT))
		_effects.add_child(line)

	_protein_icon.texture = _icon.call("ui_protein_" + str(kind.protein)) if _icon.is_valid() else null
	_protein_name.text = str(kind.proteinName)
	if top:
		_protein_count.text = "보유 %d" % owned
		_protein_count.add_theme_color_override("font_color", DIM)
		_chance.text = "-"
	else:
		_protein_count.text = "%d / %d" % [owned, cost]
		_protein_count.add_theme_color_override("font_color", OK if owned >= cost else WARN)
		_chance.text = "%d%%" % int(step.get("chance", 0))
	var can := not top and owned >= cost
	for button in [_auto_button, _up_button]:
		(button as Button).disabled = not can
		(button as Button).modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)


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


## 받은 그림의 룬 원판 자리 — 문장 가운데에 옅은 원 셋 + 바깥 원의 눈금 36개
func _draw_ring(ring: Control) -> void:
	var middle := ring.size * 0.5 + Vector2(0, -10)
	for radius in [175.0, 235.0, 300.0]:
		ring.draw_arc(middle, radius, 0.0, TAU, 96, RING, 2.0, true)
	for index in 36:
		var angle := TAU * index / 36.0
		var direction := Vector2(cos(angle), sin(angle))
		var inner := 250.0 if index % 3 == 0 else 262.0
		ring.draw_line(middle + direction * inner, middle + direction * 285.0, RING, 2.0, true)


## 문장 좌우의 꺾쇠 — 누르면 옆 운동으로 (탭과 같은 일). 폰트에 꺾쇠 글자가 없어 선으로 그린다
func _chevron(step: int) -> Button:
	var button := Button.new()
	button.name = "prev" if step < 0 else "next"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(56, 96)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: _pick(_kind + step))
	button.draw.connect(func() -> void:
		var c := button.size * 0.5
		var w := 12.0 * float(step)
		var points := PackedVector2Array([c + Vector2(-w, -26), c + Vector2(w, 0), c + Vector2(-w, 26)])
		button.draw_polyline(points, GOLD, 4.0, true)
	)
	return button


## 마름모 점 — 폰트에 ◆ 가 없다 (완성형 부분 집합)
func _diamond(color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(14, 28)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.draw.connect(func() -> void:
		var c := holder.size * 0.5
		holder.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0),
		]), color)
	)
	return holder


func _head(text: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var label := _label(text, 20, DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var line := ColorRect.new()
	line.color = FAINT
	line.custom_minimum_size = Vector2(0, 1)
	column.add_child(line)
	return column


func _button(text: String, auto: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_button_text(button, 24)
	button.add_theme_stylebox_override("normal", _button_box(false))
	button.add_theme_stylebox_override("hover", _button_box(false))
	button.add_theme_stylebox_override("disabled", _button_box(false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", _button_box(true))
	button.pressed.connect(func() -> void: up_requested.emit(kind_id(), auto))
	return button


func _button_box(pressed: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 12)
	var sink: int = SINK if pressed else 0
	box.content_margin_top = 12 + sink
	box.content_margin_bottom = 12 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
	return box


## 탭 오른쪽 위 빨간 점 — 그 운동을 지금 두드릴 수 있으면 켠다 (HUD 가방 점과 같은 색)
func _red_dot(tab: Button) -> Control:
	var dot := Panel.new()
	dot.name = "red_dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e3342b")
	style.border_color = Color("#3a0b08")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	dot.add_theme_stylebox_override("panel", style)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -18
	dot.offset_right = -6
	dot.offset_top = 6
	dot.offset_bottom = 18
	dot.visible = false
	tab.add_child(dot)
	return dot


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
