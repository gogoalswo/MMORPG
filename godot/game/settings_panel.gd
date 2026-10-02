class_name SettingsPanel
extends PanelContainer

## 설정 창 — 메뉴 판의 "설정" 으로 뜬다. 헬스·도감 창과 같은 층·같은 결(전체 화면 · 돌판 틀)이다
## (2026-10-02 요청: "설정 UI를 전체화면으로 만들어. 설정 중에 습득할 아이템도 설정할 수 있는 옵션").
## → docs/features/hud.md "설정 창"
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ──────────────────────── X
##   │ 소리 │ 아이템 습득 │                    ← 탭 (판 없이 글자만, 고른 것은 금빛 + 밑줄)
##   ├───────────────────────────────────────────┤
##   │               전체 볼륨                     │
##   │          [-]    70%    [+]                  │
##   │          ━━━━━━━━●━━━━━                      │
##
##   │ 아이템 습득 탭 — 등급 일곱 줄. 누르면 줍기 ↔ 안 줍기   │
##   │  일반 ............................ 줍기   │
##   │  고급 ............................ 안 줍기 │
##
## 소리는 **기기 설정**(`SoundSettings`)이라 이 창이 바로 건다. 습득은 **장부**(`Ledger.set_loot_skip`) —
## 가방에 무엇이 들어오는지가 바뀌므로 판정하는 쪽이 정한다. 이 창은 요청만 내고 장부 값을 그린다.

## 안 주울 등급 목록 전체 — `game.gd` 가 `lootSkip` 으로 보낸다
signal loot_skip_changed(grades: Array)

const STONE_IN := 30
const BODY_WIDTH := 560.0
const ROW_HEIGHT := 60.0

const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const OK := Color("#a9c77a")

const TABS := [["sound", "소리"], ["loot", "아이템 습득"]]

var _frame_box := Callable()
var _inv_button := Callable()

## 고른 탭 (0 부터)
var _tab := 0
var _me: Dictionary = {}
var _seen := ""

var _tabs: Array = []
var _pages: Array = []
var _sound_label: Label
var _sound_slider: HSlider
## 등급 → 그 줄 단추
var _loot_rows := {}


## `frame_box` · `inv_button` 은 `game.gd` 것을 받는다 (-/+ 단추가 물약 창과 같은 모양이다)
static func make(frame_box: Callable, inv_button: Callable) -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel._frame_box = frame_box
	panel._inv_button = inv_button
	panel._build()
	return panel


func _build() -> void:
	name = "SettingsPanel"
	visible = false
	add_theme_stylebox_override("panel", _frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var tabs := HBoxContainer.new()
	tabs.name = "tabs"
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for index in TABS.size():
		var tab := Button.new()
		tab.name = "tab_%s" % str(TABS[index][0])
		tab.text = str(TABS[index][1])
		tab.custom_minimum_size = Vector2(180, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(pick_tab.bind(index))
		tabs.add_child(tab)
		_tabs.append(tab)
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	var body := CenterContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_pages = [_build_sound(), _build_loot()]
	for page in _pages:
		body.add_child(page)


## 소리 탭 — 전체 볼륨 -/+ (10 씩)와 슬라이더. 0 이 "소리 끔" (docs/features/hud.md "소리 설정")
func _build_sound() -> Control:
	var page := VBoxContainer.new()
	page.name = "sound_page"
	page.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	page.add_theme_constant_override("separation", 18)
	page.add_child(_head("전체 볼륨"))
	var hint := _label("0 이면 소리를 끈다", 18, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	# ASCII "-" — 빼기 기호(U+2212)는 한글 폰트 부분집합에 없다 (물약 창과 같다)
	var down: Button = _inv_button.call("-", _sound_step.bind(-1))
	down.name = "sound_down"
	row.add_child(down)
	_sound_label = _label("", 26, GOLD)
	_sound_label.custom_minimum_size = Vector2(140, 0)
	_sound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_sound_label)
	var up: Button = _inv_button.call("+", _sound_step.bind(1))
	up.name = "sound_up"
	row.add_child(up)

	_sound_slider = HSlider.new()
	_sound_slider.name = "sound_slider"
	_sound_slider.min_value = 0
	_sound_slider.max_value = SoundSettings.MAX
	_sound_slider.step = SoundSettings.STEP
	_sound_slider.tick_count = SoundSettings.MAX / SoundSettings.STEP + 1
	_sound_slider.ticks_on_borders = true
	_sound_slider.custom_minimum_size = Vector2(0, 36)
	_sound_slider.value_changed.connect(func(value: float) -> void: set_sound(roundi(value)))
	page.add_child(_sound_slider)
	return page


## 아이템 습득 탭 — 장비 등급 일곱 줄. 줄을 누르면 줍기 ↔ 안 줍기.
## 골드·크리스탈은 거르지 않는다 — 크리스탈은 한 칸에 겹쳐 가방을 채우지 않는다
func _build_loot() -> Control:
	var page := VBoxContainer.new()
	page.name = "loot_page"
	page.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	page.add_theme_constant_override("separation", 8)
	page.add_child(_head("주울 장비 등급"))
	var hint := _label("끈 등급의 장비는 떨어져도 가방에 넣지 않는다 · 골드와 크리스탈은 늘 줍는다", 16, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	for grade in range(1, _grade_count() + 1):
		var row := Button.new()
		row.name = "loot_%d" % grade
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.focus_mode = Control.FOCUS_NONE
		row.pressed.connect(toggle_grade.bind(grade))
		var line := HBoxContainer.new()
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 24
		line.offset_right = -24
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
		var title := _label(Items.grade_name(grade), 22, Items.grade_color(grade))
		title.name = "grade"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(title)
		var state := _label("", 22, OK)
		state.name = "state"
		state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(state)
		page.add_child(row)
		_loot_rows[grade] = row
	return page


func open() -> void:
	visible = true
	_seen = ""
	_redraw()


func close_panel() -> void:
	visible = false


## 장부가 바뀌면 다시 그린다 — `game.gd` 가 매 프레임 부른다. 같으면 안 짓는다
func refresh(me: Dictionary) -> void:
	_me = me
	if not visible:
		return
	var seen := "%d|%s" % [_tab, Ledger.loot_skip(me)]
	if seen == _seen:
		return
	_seen = seen
	_redraw()


func pick_tab(index: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	_seen = ""
	refresh(_me)


## 고른 탭 (0 소리 · 1 아이템 습득) · 볼륨 글자 — 테스트가 본다
func tab_index() -> int:
	return _tab


func sound_label() -> Label:
	return _sound_label


## 그 등급 줄에 적힌 상태 글자("줍기" · "안 줍기") — 테스트가 본다
func loot_state(grade: int) -> String:
	return (_loot_rows[grade].find_child("state", true, false) as Label).text


## 줄 하나를 뒤집어 **목록 전체**를 요청한다. 화면은 장부 답(`refresh`)이 오면 바뀐다
func toggle_grade(grade: int) -> void:
	var skip := Ledger.loot_skip(_me).duplicate()
	if grade in skip:
		skip.erase(grade)
	else:
		skip.append(grade)
	skip.sort()
	loot_skip_changed.emit(skip)


func _sound_step(dir: int) -> void:
	set_sound(SoundSettings.volume() + dir * SoundSettings.STEP)


func set_sound(value: int) -> void:
	_show_sound(SoundSettings.set_volume(value))


## 글자와 손잡이를 건 값에 맞춘다 — 손잡이는 신호 없이 (신호를 내면 다시 거는 되먹임이 된다)
func _show_sound(value: int) -> void:
	_sound_label.text = "%d%%" % value if value > 0 else "소리 끔"
	_sound_slider.set_value_no_signal(value)


func _redraw() -> void:
	for index in _tabs.size():
		_paint_tab(_tabs[index], index == _tab)
		(_pages[index] as Control).visible = index == _tab
	_show_sound(SoundSettings.volume())
	var skip := Ledger.loot_skip(_me)
	for grade in _loot_rows:
		var on := not (int(grade) in skip)
		var row: Button = _loot_rows[grade]
		_paint_row(row, on)
		var state: Label = row.find_child("state", true, false)
		state.text = "줍기" if on else "안 줍기"
		state.add_theme_color_override("font_color", OK if on else DIM)
		var title: Label = row.find_child("grade", true, false)
		var color := Items.grade_color(int(grade))
		title.add_theme_color_override("font_color", color if on else color.darkened(0.55))


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


## 등급 줄 — 어두운 판 + 얇은 테. 줍는 줄은 금테, 안 줍는 줄은 흐린 테
func _paint_row(row: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.05, 0.92) if on else Color(0.03, 0.03, 0.03, 0.8)
	box.border_color = Color(GOLD, 0.6) if on else FAINT
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed", "disabled"]:
		row.add_theme_stylebox_override(state, box)
	row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _head(text: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var label := _label(text, 22, DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var line := ColorRect.new()
	line.color = FAINT
	line.custom_minimum_size = Vector2(0, 1)
	column.add_child(line)
	return column


func _grade_count() -> int:
	return int(Items._t().get("gradeMax", 7))


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
