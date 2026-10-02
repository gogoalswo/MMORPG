class_name SettingsPanel
extends PanelContainer

## 설정 창 — 메뉴 판의 "설정" 으로 뜬다. 전체 화면, 헬스·도감 창과 같은 층이다
## (2026-10-02 요청: "설정 UI를 전체화면으로 만들어. 설정 중에 습득할 아이템도 설정할 수 있는 옵션").
## 같은 날 사용자가 준 다른 게임의 설정 화면 그림을 따라 **배치와 결을 갈았다** ("옵션창을 이런 느낌으로 바꿔.
## 배치도 말이야") → docs/features/hud.md "설정 창"
##
##   ┌─────────────────────────────────────────────────── 설정  X ┐
##   │  환경  │  아이템                          [O 검색어를 입력해주세요.] │ ← 위 탭 (고른 것 금빛 글자 + 금 밑줄)
##   ├──────────┬───────────────────────────────────────────────────┤
##   │ ◆ 소리    │ 소리                                               │ ← 띠 머리
##   │           │   전체 볼륨                70%  -  ━━━━━■────  +   │ ← 줄: 이름 왼쪽, 조작 오른쪽
##   │           │     ◆ 0 이면 소리를 끕니다                          │ ← 풀이 줄
##   │ (왼쪽 세부 목록)│   일반                          [ ON ][ OFF ]  │ ← 두 칸 스위치 (아이템 탭)
##
## 판은 돌판 틀이 아니라 **어두운 갈색 결**이다 — 그림이 그렇다. 소리는 **기기 설정**(`SoundSettings`)이라
## 이 창이 바로 건다. 습득은 **장부**(`Ledger.set_loot_skip`) — 이 창은 요청만 내고 장부 값을 그린다.

## 안 주울 목록 하나 전체 — `field` 는 `grades`(등급) · `slots`(부위) · `options`(1차 옵션 종류).
## `game.gd` 가 `lootSkip` 으로 `{field: list}` 를 보낸다
signal loot_skip_changed(field: String, list: Array)

const HEAD_HEIGHT := 50.0
const TAB_WIDTH := 132.0
const TAB_HEIGHT := 50.0
const SIDE_WIDTH := 190.0
const ROW_HEIGHT := 62.0
const SWITCH_CELL := Vector2(118, 40)
const SLIDER_WIDTH := 300.0
## X(44) 와 그 왼쪽 틈 — 머리 줄의 "설정" 글자가 X 에 안 걸친다
const CLOSE_ROOM := 60

const BG_TOP := Color("#2b2722")
const BG_BOTTOM := Color("#181613")
const BAR_BG := Color("#1b1916", 0.9)
const LINE := Color("#3a342a")
const BAND_BG := Color("#14120f", 0.8)
const BAND_TEXT := Color("#dcc9a0")
const GOLD := Color("#f0d49a")
const GOLD_LINE := Color("#cfa860")
const TEXT := Color("#d6d0c4")
const SUB_TEXT := Color("#a39d90")
const DIM := Color("#8a8376")
const FAINT := Color("#5d574d")

## 위 탭 → 왼쪽 세부 목록. 탭 하나에 세부 하나씩이지만 그림의 자리(위 탭 · 왼쪽 목록)를 그대로 둔다 —
## 설정이 늘면 줄만 더한다
const TABS := [
	{"id": "env", "name": "환경", "subs": [["sound", "소리"]]},
	{"id": "item", "name": "아이템", "subs": [["loot", "습득 등급"], ["loot_slot", "습득 부위"], ["loot_option", "습득 옵션"]]},
]

## 고른 탭 (0 부터) · 그 탭 안에서 고른 세부 (0 부터)
var _tab := 0
var _sub := 0
var _me: Dictionary = {}
var _seen := ""

var _tabs: Array = []
## 탭마다 세부 목록 단추 묶음 · 세부마다 쪽(page) — 둘 다 `[탭][세부]`
var _sides: Array = []
var _pages: Array = []
var _sound_label: Label
var _sound_slider: HSlider
## 등급 → 그 줄의 ON/OFF 스위치 · 부위(슬롯) → 스위치 · 옵션 종류 → 스위치
var _loot_rows := {}
var _slot_rows := {}
var _option_rows := {}
var _search: LineEdit
var _empty: Label
## 검색이 거르는 줄 `{node, band, words}`
var _rows: Array = []


static func make() -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel._build()
	return panel


func _build() -> void:
	name = "SettingsPanel"
	visible = false
	var back := StyleBoxTexture.new()
	back.texture = _gradient([BG_TOP, BG_BOTTOM], Vector2(0, 0), Vector2(0, 1))
	back.content_margin_left = 0
	back.content_margin_right = 12
	back.content_margin_top = 8
	back.content_margin_bottom = 0
	add_theme_stylebox_override("panel", back)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# 머리 줄 — 오른쪽 위에 "설정", 그 옆이 X 자리
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, HEAD_HEIGHT)
	column.add_child(head)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var title := _label("설정", 26, TEXT)
	title.name = "title"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var room := Control.new()
	room.custom_minimum_size = Vector2(CLOSE_ROOM, 0)
	head.add_child(room)

	column.add_child(_build_tab_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)
	var side := VBoxContainer.new()
	side.name = "side"
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_theme_constant_override("separation", 4)
	body.add_child(side)
	var side_top := Control.new()
	side_top.custom_minimum_size = Vector2(0, 14)
	side.add_child(side_top)
	for index in TABS.size():
		var group: Array = []
		for sub_index in TABS[index].subs.size():
			var sub: Array = TABS[index].subs[sub_index]
			var button := _side_button(str(sub[0]), str(sub[1]))
			button.pressed.connect(pick_sub.bind(index, sub_index))
			side.add_child(button)
			group.append(button)
		_sides.append(group)
	var rule := ColorRect.new()
	rule.color = LINE
	rule.custom_minimum_size = Vector2(1, 0)
	body.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_name in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side_name, 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(pad)
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 10)
	pad.add_child(pages)
	_pages = [[_build_sound()], [_build_loot(), _build_loot_slots(), _build_loot_options()]]
	for group in _pages:
		for page in group:
			pages.add_child(page)
	_empty = _label("검색 결과가 없습니다", 19, DIM)
	_empty.name = "search_empty"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	pages.add_child(_empty)


## 위 탭 줄 — 글자 탭 사이에 가는 세로선, 오른쪽 끝에 검색 칸
func _build_tab_bar() -> Control:
	var bar := PanelContainer.new()
	bar.name = "tab_bar"
	var box := StyleBoxFlat.new()
	box.bg_color = BAR_BG
	box.border_color = LINE
	box.border_width_top = 1
	box.border_width_bottom = 1
	box.content_margin_left = 24
	box.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.name = "tabs"
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)
	for index in TABS.size():
		if index > 0:
			var split := ColorRect.new()
			split.color = LINE
			split.custom_minimum_size = Vector2(1, 18)
			split.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(split)
		var tab := Button.new()
		tab.name = "tab_%s" % str(TABS[index].id)
		tab.text = str(TABS[index].name)
		tab.custom_minimum_size = Vector2(TAB_WIDTH, TAB_HEIGHT)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 21)
		tab.pressed.connect(pick_tab.bind(index))
		row.add_child(tab)
		_tabs.append(tab)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	row.add_child(_build_search())
	return bar


## 검색 칸 — 줄 이름으로 거른다. 치는 동안에는 모든 탭의 줄 중 맞는 것만 늘어놓는다
func _build_search() -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(260, 38)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#0f0e0c", 0.9)
	box.border_color = LINE
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 8
	holder.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	holder.add_child(row)
	var glass := SearchGlyph.new()
	glass.custom_minimum_size = Vector2(18, 18)
	glass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glass)
	_search = HangulLineEdit.new()  # 윈도우에서 한글 앞 글자가 지워지는 고도 버그를 메운다
	_search.name = "search"
	_search.placeholder_text = "검색어를 입력해주세요."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 16)
	_search.add_theme_color_override("font_color", TEXT)
	_search.add_theme_color_override("font_placeholder_color", FAINT)
	for state in ["normal", "focus", "read_only"]:
		_search.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# 글자가 바뀌면 `refresh` 가 알아챈다 — 본 값(`_seen`)에 검색어가 든다
	_search.text_changed.connect(func(_text: String) -> void: refresh(_me))
	row.add_child(_search)
	return holder


## 소리 — 전체 볼륨 -/+ (10 씩)와 슬라이더. 0 이 "소리 끔" (docs/features/hud.md "소리 설정")
func _build_sound() -> Control:
	var page := _page("sound_page")
	var band := _band("소리")
	page.add_child(band)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_sound_label = _label("", 20, TEXT)
	_sound_label.name = "sound_value"
	_sound_label.custom_minimum_size = Vector2(96, 0)
	_sound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sound_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_child(_sound_label)
	# ASCII "-" — 빼기 기호(U+2212)는 한글 폰트 부분집합에 없다
	controls.add_child(_step_button("sound_down", "-", _sound_step.bind(-1)))
	_sound_slider = HSlider.new()
	_sound_slider.name = "sound_slider"
	_sound_slider.min_value = 0
	_sound_slider.max_value = SoundSettings.MAX
	_sound_slider.step = SoundSettings.STEP
	_sound_slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 36)
	_sound_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sound_slider.focus_mode = Control.FOCUS_NONE
	_paint_slider(_sound_slider)
	_sound_slider.value_changed.connect(func(value: float) -> void: set_sound(roundi(value)))
	controls.add_child(_sound_slider)
	controls.add_child(_step_button("sound_up", "+", _sound_step.bind(1)))
	page.add_child(_row("전체 볼륨", TEXT, controls, band, "소리 볼륨"))
	page.add_child(_hint("0 이면 소리를 끕니다", band))
	return page


## 아이템 — 장비 등급 일곱 줄 · 부위 여섯 줄 · 1차 옵션 종류 다섯 줄, 줄마다 ON(줍기)/OFF(안 줍기).
## 셋 다 켜진 장비만 줍는다 (`Ledger.loot_wanted`).
## 골드·크리스탈은 거르지 않는다 — 크리스탈은 한 칸에 겹쳐 가방을 채우지 않는다
func _build_loot() -> Control:
	var page := _page("loot_page")
	var band := _band("주울 장비 등급")
	page.add_child(band)
	page.add_child(_hint("끈 등급의 장비는 떨어져도 가방에 넣지 않습니다 · 골드와 크리스탈은 늘 줍습니다", band))
	for grade in range(1, _grade_count() + 1):
		var on_off := make_switch("loot_%d" % grade, func(on: bool) -> void: _set_grade(grade, on))
		_loot_rows[grade] = on_off
		var row := _row(Items.grade_name(grade), Items.grade_color(grade), on_off, band, "습득 줍기 장비 등급")
		row.name = "loot_row_%d" % grade
		page.add_child(row)
	return page


## 부위 — 무기 ~ 반지 여섯 줄 (2026-10-02 요청: "등급만 있는데, 부위와 옵션도 설정할 수 있게끔").
## 한 쪽에 등급과 같이 두면 기준 화면(720)을 넘어서 세부를 나눴다
func _build_loot_slots() -> Control:
	var page := _page("loot_slot_page")
	var slot_band := _band("주울 장비 부위")
	page.add_child(slot_band)
	page.add_child(_hint("끈 부위의 장비는 떨어져도 가방에 넣지 않습니다", slot_band))
	for slot in Items.slots():
		var slot_id := str(slot)
		var on_off := make_switch("loot_slot_%s" % slot_id,
			func(on: bool) -> void: _set_name(&"slots", slot_id, on))
		_slot_rows[slot_id] = on_off
		var row := _row(Items.slot_label(slot_id), TEXT, on_off, slot_band, "습득 줍기 장비 부위")
		row.name = "loot_slot_row_%s" % slot_id
		page.add_child(row)
	return page


## 옵션 — 드랍에 붙는 1차 옵션 종류(`optionKinds`). 붙은 종류를 끄면 그 장비는 안 줍는다
func _build_loot_options() -> Control:
	var page := _page("loot_option_page")
	var option_band := _band("주울 장비 옵션")
	page.add_child(option_band)
	page.add_child(_hint("떨어질 때 붙은 1차 옵션의 종류로 거릅니다 · 끈 옵션이 붙은 장비는 넣지 않습니다", option_band))
	var labels: Dictionary = Items._t().get("optionLabel", {})
	for kind in _option_kinds():
		var on_off := make_switch("loot_option_%s" % kind,
			func(on: bool) -> void: _set_name(&"options", kind, on))
		_option_rows[kind] = on_off
		var row := _row(str(labels.get(kind, kind)), TEXT, on_off, option_band, "습득 줍기 장비 옵션")
		row.name = "loot_option_row_%s" % kind
		page.add_child(row)
	return page


static func _option_kinds() -> Array:
	var out: Array = []
	for kind in Items._t().get("optionKinds", []):
		out.append(str(kind))
	return out


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
	var seen := "%d|%d|%s|%s|%s|%s" % [_tab, _sub, Ledger.loot_skip(me), Ledger.loot_skip_slots(me),
		Ledger.loot_skip_options(me), _search.text]
	if seen == _seen:
		return
	_seen = seen
	_redraw()


## 위 탭을 고른다 — 검색 중이었으면 검색을 비운다
func pick_tab(index: int) -> void:
	pick_sub(index, 0)


## 왼쪽 세부를 고른다 — 그 탭으로 가서 그 세부의 쪽을 띄운다
func pick_sub(index: int, sub: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	_sub = clampi(sub, 0, TABS[_tab].subs.size() - 1)
	if _search.text != "":
		_search.text = ""
	_seen = ""
	refresh(_me)


## 고른 탭 (0 환경 · 1 아이템) · 세부 · 볼륨 글자 · 검색 칸 — 테스트가 본다
func tab_index() -> int:
	return _tab


func sub_index() -> int:
	return _sub


func sound_label() -> Label:
	return _sound_label


func search_box() -> LineEdit:
	return _search


## 그 등급 줄의 스위치 상태("ON" · "OFF") — 테스트가 본다
func loot_state(grade: int) -> String:
	return "ON" if switch_on(_loot_rows[grade]) else "OFF"


## 그 부위·옵션 줄의 스위치 상태 — 테스트가 본다
func slot_state(slot: String) -> String:
	return "ON" if switch_on(_slot_rows[slot]) else "OFF"


func option_state(kind: String) -> String:
	return "ON" if switch_on(_option_rows[kind]) else "OFF"


## 줄 하나를 뒤집어 **목록 전체**를 요청한다. 화면은 장부 답(`refresh`)이 오면 바뀐다
func toggle_grade(grade: int) -> void:
	_set_grade(grade, grade in Ledger.loot_skip(_me))


func _set_grade(grade: int, pick_up: bool) -> void:
	var skip := Ledger.loot_skip(_me).duplicate()
	var picking := not (grade in skip)
	if pick_up == picking:
		return
	if pick_up:
		skip.erase(grade)
	else:
		skip.append(grade)
	skip.sort()
	loot_skip_changed.emit("grades", skip)


## 부위·옵션 줄 하나를 바꿔 그 **목록 전체**를 요청한다. 순서는 장부가 표 순서로 다듬는다
func _set_name(field: StringName, id: String, pick_up: bool) -> void:
	var skip: Array = (Ledger.loot_skip_slots(_me) if field == &"slots" else Ledger.loot_skip_options(_me)).duplicate()
	if pick_up == not (id in skip):
		return
	if pick_up:
		skip.erase(id)
	else:
		skip.append(id)
	loot_skip_changed.emit(str(field), skip)


func _sound_step(dir: int) -> void:
	set_sound(SoundSettings.volume() + dir * SoundSettings.STEP)


func set_sound(value: int) -> void:
	_show_sound(SoundSettings.set_volume(value))


## 글자와 손잡이를 건 값에 맞춘다 — 손잡이는 신호 없이 (신호를 내면 다시 거는 되먹임이 된다)
func _show_sound(value: int) -> void:
	_sound_label.text = "%d%%" % value if value > 0 else "소리 끔"
	_sound_slider.set_value_no_signal(value)


func _redraw() -> void:
	var searching := _search.text.strip_edges() != ""
	for index in _tabs.size():
		var on := index == _tab and not searching
		_paint_tab(_tabs[index], on)
		for sub in _sides[index].size():
			var picked: bool = on and sub == _sub
			_paint_side(_sides[index][sub], picked)
			(_pages[index][sub] as Control).visible = picked or searching
	_apply_search()
	_show_sound(SoundSettings.volume())
	var skip := Ledger.loot_skip(_me)
	for grade in _loot_rows:
		paint_switch(_loot_rows[grade], not (int(grade) in skip))
	var skip_slots := Ledger.loot_skip_slots(_me)
	for slot in _slot_rows:
		paint_switch(_slot_rows[slot], not (slot in skip_slots))
	var skip_options := Ledger.loot_skip_options(_me)
	for kind in _option_rows:
		paint_switch(_option_rows[kind], not (kind in skip_options))


## 검색 — 치는 동안은 모든 탭의 줄을 펼쳐 이름이 맞는 줄만 남긴다. 띠는 아래 줄이 하나라도 남으면 선다
func _apply_search() -> void:
	var query := _search.text.strip_edges()
	var bands := {}
	var shown := 0
	for entry in _rows:
		var hit := query == "" or str(entry.words).contains(query)
		(entry.node as Control).visible = hit
		if hit:
			bands[entry.band] = true
			shown += 1
	for entry in _rows:
		(entry.band as Control).visible = bands.has(entry.band)
	_empty.visible = query != "" and shown == 0


## --- 조각 ---

func _page(node_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = node_name
	page.add_theme_constant_override("separation", 0)
	return page


## 띠 머리 — 줄 묶음의 이름 (그림의 "체력 부족 알림")
func _band(text: String) -> Control:
	var band := PanelContainer.new()
	band.name = "band"
	var box := StyleBoxFlat.new()
	box.bg_color = BAND_BG
	box.content_margin_left = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	band.add_theme_stylebox_override("panel", box)
	band.add_child(_label(text, 20, BAND_TEXT))
	return band


## 줄 — 이름 왼쪽, 조작 오른쪽. `words` 는 검색이 보는 낱말(이름은 늘 든다)
func _row(text: String, color: Color, controls: Control, band: Control, words: String) -> Control:
	var row := MarginContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("margin_left", 28)
	row.add_theme_constant_override("margin_right", 6)
	var line := HBoxContainer.new()
	row.add_child(line)
	var title := _label(text, 20, color)
	title.name = "name"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(title)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(controls)
	_rows.append({"node": row, "band": band, "words": "%s %s" % [text, words]})
	return row


## 풀이 줄 — 작은 마름모 + 흐린 글자 (그림의 "◆ 세부 설정")
func _hint(text: String, band: Control) -> Control:
	var row := MarginContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.add_theme_constant_override("margin_left", 40)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	line.add_child(_diamond(Color("#a08a5c")))
	var label := _label(text, 16, DIM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	_rows.append({"node": row, "band": band, "words": text})
	return row


## 두 칸 스위치 [ON][OFF] — 고른 칸만 밝은 갈색 판 + 금빛 글자. 도감 자동 등록 설정 창도 같이 쓴다.
## 칸을 누르면 `on_pick(켬?)` — 그림은 부르는 쪽이 `paint_switch` 로 맞춘다 (판정 값을 받아 그린다)
static func make_switch(node_name: String, on_pick: Callable) -> HBoxContainer:
	var switch := HBoxContainer.new()
	switch.name = node_name
	switch.add_theme_constant_override("separation", 0)
	for each in [["on", "ON", true], ["off", "OFF", false]]:
		var cell := Button.new()
		cell.name = str(each[0])
		cell.text = str(each[1])
		cell.custom_minimum_size = SWITCH_CELL
		cell.focus_mode = Control.FOCUS_NONE
		cell.add_theme_font_size_override("font_size", 17)
		cell.pressed.connect(on_pick.bind(bool(each[2])))
		switch.add_child(cell)
	paint_switch(switch, true)
	return switch


static func paint_switch(switch: Control, on: bool) -> void:
	switch.set_meta("on", on)
	for cell: Button in [switch.get_node("on"), switch.get_node("off")]:
		var chosen := (cell.name == "on") == on
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#3b3226") if chosen else Color("#121110")
		box.border_color = Color("#6e5c3d") if chosen else Color("#29261f")
		box.set_border_width_all(1)
		if chosen:
			box.shadow_color = Color(0.9, 0.7, 0.35, 0.16)
			box.shadow_size = 5
		for state in ["normal", "hover", "pressed", "disabled"]:
			cell.add_theme_stylebox_override(state, box)
		cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		cell.add_theme_color_override("font_color", GOLD if chosen else FAINT)
		cell.add_theme_color_override("font_hover_color", GOLD if chosen else SUB_TEXT)
		cell.add_theme_color_override("font_pressed_color", GOLD)


static func switch_on(switch: Control) -> bool:
	return bool(switch.get_meta("on", false))


## -/+ — 판 없는 글자 단추
func _step_button(node_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.flat = true
	button.custom_minimum_size = Vector2(40, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", DIM)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.pressed.connect(on_press)
	return button


## 슬라이더 — 검은 홈 · 손잡이까지 금빛 채움(왼쪽이 어둡다) · 회색 네모 손잡이
func _paint_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#0b0a09")
	track.border_color = Color("#2a2620")
	track.set_border_width_all(1)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxTexture.new()
	fill.texture = _gradient([Color("#6a5a3c"), Color("#e8d29c")], Vector2(0, 0), Vector2(1, 0))
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(Color("#4d4943"), Color("#7a736a"))
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", _knob(Color("#5e5952"), GOLD_LINE))
	slider.add_theme_icon_override("grabber_disabled", knob)
	slider.add_theme_icon_override("tick", ImageTexture.new())


static func _knob(face: Color, rim: Color) -> Texture2D:
	var image := Image.create(14, 28, false, Image.FORMAT_RGBA8)
	image.fill(face)
	for x in 14:
		image.set_pixel(x, 0, rim)
		image.set_pixel(x, 27, rim)
	for y in 28:
		image.set_pixel(0, y, rim)
		image.set_pixel(13, y, rim)
	return ImageTexture.create_from_image(image)


static func _gradient(colors: Array, from: Vector2, to: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = from
	texture.fill_to = to
	texture.width = 64
	texture.height = 64
	return texture


## 위 탭 — 판 없이 글자만. 고른 것은 금빛 글자 + 금 밑줄 + 옅은 금빛 바탕
func _paint_tab(tab: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.68, 0.38, 0.08) if on else Color(0, 0, 0, 0)
	box.border_color = GOLD_LINE if on else Color(0, 0, 0, 0)
	box.border_width_bottom = 2
	box.set_content_margin_all(6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		tab.add_theme_stylebox_override(state, box)
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tab.add_theme_color_override("font_color", GOLD if on else SUB_TEXT)
	tab.add_theme_color_override("font_hover_color", GOLD if on else TEXT)
	tab.add_theme_color_override("font_pressed_color", GOLD)


## 왼쪽 세부 목록 단추 — 고른 것은 왼쪽에서 번지는 금빛 + 마름모
func _side_button(id: String, text: String) -> Button:
	var button := Button.new()
	button.name = "sub_%s" % id
	button.text = text
	button.custom_minimum_size = Vector2(SIDE_WIDTH - 16, 46)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 19)
	var mark := _diamond(GOLD_LINE)
	mark.name = "mark"
	mark.position = Vector2(16, 19)
	button.add_child(mark)
	return button


func _paint_side(button: Button, on: bool) -> void:
	var box: StyleBox
	if on:
		var glow := StyleBoxTexture.new()
		glow.texture = _gradient([Color(0.85, 0.62, 0.3, 0.24), Color(0.85, 0.62, 0.3, 0.0)], Vector2(0, 0), Vector2(1, 0))
		box = glow
	else:
		box = StyleBoxEmpty.new()
	box.content_margin_left = 38
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", GOLD if on else SUB_TEXT)
	button.add_theme_color_override("font_hover_color", GOLD if on else TEXT)
	button.add_theme_color_override("font_pressed_color", GOLD)
	(button.get_node("mark") as Control).visible = on


## 작은 마름모 — 글꼴에 ◆ 가 없을 수 있어 네모를 45도 돌려 그린다
func _diamond(color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(10, 10)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var square := ColorRect.new()
	square.color = color
	square.size = Vector2(7, 7)
	square.position = Vector2(1.5, 1.5)
	square.pivot_offset = Vector2(3.5, 3.5)
	square.rotation = PI / 4
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(square)
	return holder


func _grade_count() -> int:
	return int(Items._t().get("gradeMax", 7))


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## 검색 칸 앞의 돋보기 — 글꼴에 없는 기호라 선으로 그린다
class SearchGlyph:
	extends Control

	func _draw() -> void:
		var color := Color("#8a8376")
		draw_arc(Vector2(7.5, 7.5), 5.5, 0, TAU, 20, color, 1.6, true)
		draw_line(Vector2(11.5, 11.5), Vector2(16.5, 16.5), color, 1.8, true)
