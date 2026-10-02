class_name CodexPanel
extends PanelContainer

## 장비 도감 창 — 등급 탭 일곱(일반 ~ 태초) × 부위 여섯 줄 × 강화 +0 ~ +9 열 칸
## (2026-10-01 요청: "각 등급 0강부터 9강까지 등록할 수 있는 도감 … 파츠별로 … 탭 만들어서
## 일반부터 태초등급까지"). 판정은 장부(`Ledger.codex_register`)가 하고, 이 창은 장부 값
## (`codex` · `bag`)을 그리기만 한다 → docs/features/codex.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ─────────────────────────────────────── X
##   │ 일반 │ 고급 │ 희귀 • │ 영웅 │ 전설 │ 초월 │ 태초 │  ← 탭 (넣을 수 있는 칸이 있으면 빨간 점)
##   ├──────────────────────────────────────────────┬───────────────────┤
##   │          +0  +1  +2  +3  +4  +5  +6  +7  +8  +9 │     획득 효과      │
##   │ 무기    [■] [■] [□•][ ] [ ] [ ] [ ] [ ] [ ] [ ] │ ◆ 공격력 +0.42%   │
##   │ 갑옷    [■] [ ] …                              │ ◆ 방어력 +0.10%   │
##   │ 투구 …  (■ 찬 칸 · □• 가방에 있어 넣을 수 있는 칸) │ ◆ 체력  +0.03%   │
##   │ 신발                                           │   희귀 12 / 60    │
##   │ 목걸이                                          │      선택한 칸      │
##   │ 반지                                           │ [그림] 희귀 무기 +2 │
##   │                                               │ 공격력 +0.09%      │
##   │                                               │ 보유 1개  [ 등록 ]  │
##
## 칸 그림은 장비 아이콘(`{부위}_g{등급}`)을 그대로 쓴다 — 새로 그리지 않는다.

## `index` 는 넣을 장비 목록에서 고른 가방 번호 (장부가 다시 본다)
signal register_requested(item_id: String, enhance: int, index: int)
## [자동 등록] → 확인 창의 [등록] — 넣을 수 있는 칸 전부 (고르는 것은 장부가 다시 한다)
signal register_all_requested
## [강화] — 고른 칸을 채우려고 가방 번호 `index` 의 장비를 `goal` 까지 올리는 강화 창을 띄운다 (game.gd 가 연다)
signal enhance_requested(index: int, goal: int)
## 자동 등록 설정 창 — 등급 하나의 넣을 부위 목록(비면 그 등급을 끈다) → `codexAutoGrade` (주울 때 장부가 넣는다)
signal auto_changed(grade: int, slots: Array)
## 자동 등록 설정 창에서 막을 1차 옵션 종류 목록 전체 → `codexAutoBlock`
signal auto_block_changed(grade: int, kinds: Array)
## 그 등급 탭을 보고 나왔다 → `codexSeen` (자동 등록으로 새로 찬 칸의 빨간 점을 지운다)
signal seen(grade: int)

const SIDE_WIDTH := 340.0
const STONE_IN := 30
const CELL := 62.0
const CELL_GAP := 6
const NAME_WIDTH := 92.0
const PICK_ICON := 52.0
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

var _frame_box := Callable()
var _icon := Callable()

## 고른 등급 (1 ~ 7)
var _grade := 1
## 고른 칸 — `[부위, 강화]`
var _pick: Array = []
## 칸을 직접 누르기 전에는 그릴 때마다 **넣을 수 있는 첫 칸**을 다시 고른다 — 하나 넣으면 다음 칸으로 넘어간다
var _auto_pick := true
var _me: Dictionary = {}
var _seen := ""

var _tabs: Array = []
var _tab_dots: Array = []
## 칸 단추 — `"부위:강화"` → Button
var _cells := {}
var _effects: VBoxContainer
var _progress: Label
var _pick_icon: TextureRect
var _pick_name: Label
var _pick_gain: Label
var _pick_have: Label
var _register_button: Button
## 넣을 수 있는 칸을 **전부** 채우는 단추 (2026-10-02 요청 "도감에 자동 등록 버튼 만들어") — 등급을 가리지 않는다
var _auto_button: Button
## 고른 칸을 채울 장비를 강화 창에 넘기는 단추 (2026-10-02 요청 "도감에서 강화 버튼 만들어. 도감 목록 누르면 강화
## 버튼 활성화 … 해당 장비를 선택하고 목표 등급 자동 선택 된 상태로 창을 띄워") — 칸을 **직접 눌러야** 켜진다
var _enhance_button: Button
## 등록할 장비 선택 창 — [등록] 을 누르면 이 창 위에 뜬다 (codex_picker.gd, 2026-10-01 요청
## "가방에서 선택하는 UI를 따로 만들어 … 2,3차 옵션은 안 보이자나")
var _picker: CodexPicker
## 자동 등록 설정 창과 그 창을 여는 탭 줄 오른쪽 단추 (codex.md "주울 때 자동 등록")
var _auto_sheet: CodexAutoSheet
var _auto_setting: Button


## `frame_box` · `icon` 은 `game.gd` 것을 받는다 (헬스 창과 같다)
static func make(frame_box: Callable, icon: Callable) -> CodexPanel:
	var panel := CodexPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	return panel


func _build() -> void:
	name = "CodexPanel"
	visible = false
	add_theme_stylebox_override("panel", _frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# 탭 — 헬스 창처럼 판 없이 글자만, 고른 것은 금빛 글자 + 밑줄. 등급 이름은 등급 색으로 적는다
	var tabs := HBoxContainer.new()
	tabs.name = "tabs"
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for grade in range(1, _grade_count() + 1):
		var tab := Button.new()
		tab.name = "tab_%d" % grade
		tab.text = Items.grade_name(grade)
		tab.custom_minimum_size = Vector2(112, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_pick_grade.bind(grade))
		tabs.add_child(tab)
		_tabs.append(tab)
		_tab_dots.append(_red_dot(tab, 6))
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(_build_grid())
	body.add_child(_build_side())
	# 등록할 장비 선택 창 — 맨 뒤에 달아 모든 것 위에 뜬다
	_picker = CodexPicker.make(_frame_box, _icon)
	_picker.picked.connect(func(index: int) -> void:
		if not _pick.is_empty():
			register_requested.emit(Items.item_id(_grade, str(_pick[0])), int(_pick[1]), index)
	)
	_picker.picked_all.connect(func() -> void: register_all_requested.emit())
	add_child(_picker)
	var done := _side_button("done", "닫기", func() -> void: pass)
	done.custom_minimum_size = Vector2(160, 56)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	_auto_sheet = CodexAutoSheet.make(done)
	_auto_sheet.changed.connect(func(grade: int, slots: Array) -> void: auto_changed.emit(grade, slots))
	_auto_sheet.blocked_changed.connect(func(grade: int, kinds: Array) -> void: auto_block_changed.emit(grade, kinds))
	add_child(_auto_sheet)
	# 숨으면(X · 다른 창 · 강화 창으로 넘어감) 보던 탭의 새 칸 표시를 지운다 — 본 것이다
	visibility_changed.connect(func() -> void:
		if not visible:
			_leave_tab()
	)


## 왼쪽 — 강화 머리줄 + 부위 여섯 줄 × 칸 열
func _build_grid() -> Control:
	var holder := CenterContainer.new()
	holder.name = "grid"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = Codex.max_enhance() + 2
	grid.add_theme_constant_override("h_separation", CELL_GAP)
	grid.add_theme_constant_override("v_separation", CELL_GAP)
	holder.add_child(grid)

	grid.add_child(Control.new())
	for enhance in Codex.max_enhance() + 1:
		var head := _label("+%d" % enhance, 18, DIM)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(CELL, 0)
		grid.add_child(head)
	for slot in Items.slots():
		var names := VBoxContainer.new()
		names.custom_minimum_size = Vector2(NAME_WIDTH, CELL)
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.add_theme_constant_override("separation", 0)
		names.add_child(_label(Items.slot_label(str(slot)), 21, IVORY))
		names.add_child(_label(Codex.stat_name(Codex.slot_stat(str(slot))), 15, DIM))
		grid.add_child(names)
		for enhance in Codex.max_enhance() + 1:
			var cell := _cell(str(slot), enhance)
			grid.add_child(cell)
			_cells["%s:%d" % [slot, enhance]] = cell
	return holder


## 칸 하나 — 장비 그림 · 오른쪽 아래 +N · 넣을 수 있으면 빨간 점
func _cell(slot: String, enhance: int) -> Button:
	var cell := Button.new()
	cell.name = "cell_%s_%d" % [slot, enhance]
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.focus_mode = Control.FOCUS_NONE
	cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cell.pressed.connect(_pick_cell.bind(slot, enhance))
	var art := TextureRect.new()
	art.name = "art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 6
	art.offset_top = 6
	art.offset_right = -6
	art.offset_bottom = -6
	cell.add_child(art)
	var badge := _label("+%d" % enhance, 15, IVORY)
	badge.name = "badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 5)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.offset_right = -4
	badge.offset_bottom = -1
	cell.add_child(badge)
	_red_dot(cell, 3)
	return cell


## 오른쪽 칸 — 획득 효과 · 모은 칸 · 고른 칸 · 등록 단추
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
	column.add_theme_constant_override("separation", 8)
	side.add_child(column)

	column.add_child(_head("획득 효과"))
	_effects = VBoxContainer.new()
	_effects.name = "effects"
	_effects.add_theme_constant_override("separation", 0)
	column.add_child(_effects)
	_progress = _label("", 19, DIM)
	_progress.name = "progress"
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_progress)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(gap)

	column.add_child(_head("선택한 칸"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(PICK_ICON, PICK_ICON)
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.03, 0.03, 0.03, 0.9)
	slot_box.border_color = GatePanel.CELL_LINE
	slot_box.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", slot_box)
	row.add_child(slot)
	_pick_icon = TextureRect.new()
	_pick_icon.name = "pick_icon"
	_pick_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pick_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(_pick_icon)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	_pick_name = _label("", 20, IVORY)
	_pick_name.name = "pick_name"
	names.add_child(_pick_name)
	_pick_gain = _label("", 19, NEXT)
	_pick_gain.name = "pick_gain"
	names.add_child(_pick_gain)
	_pick_have = _label("", 20, DIM)
	_pick_have.name = "pick_have"
	_pick_have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_pick_have)

	# [강화] 는 한 줄을 따로 — 셋을 한 줄에 두면 340 칸에 안 들어간다. 높이는 위의 빈 칸(gap)이 내준다
	_enhance_button = _side_button("enhance", "강화", _on_enhance)
	column.add_child(_enhance_button)
	# [자동 등록 설정] · [등록] 한 줄 — 창 높이를 늘리지 않는다 (1280x720 틀 안).
	# [자동 등록 설정] 은 처음엔 탭 줄 오른쪽이었고, [자동 등록](가방 것을 한 번에)이 이 자리였다 —
	# 2026-10-02 요청 "자동 등록 설정 버튼을 자동 등록 버튼 위치로 옮기고, 기존 자동 등록 버튼은 숨김 처리 해".
	# [자동 등록] 은 지우지 않고 숨긴다 (판정 `codex_register_all` · 확인 창은 그대로 남는다)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_auto_button = _side_button("auto_register", "자동 등록", _on_register_all)
	_auto_button.visible = false
	buttons.add_child(_auto_button)
	_auto_setting = _side_button("auto_setting", "자동 등록 설정", _open_auto)
	_auto_setting.size_flags_stretch_ratio = 1.7
	GatePanel.paint_button_text(_auto_setting, 19)
	buttons.add_child(_auto_setting)
	_register_button = _side_button("register", "등록", _on_register)
	buttons.add_child(_register_button)
	return side


func _side_button(node_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_button_text(button, 22)
	button.add_theme_stylebox_override("normal", _button_box(false))
	button.add_theme_stylebox_override("hover", _button_box(false))
	button.add_theme_stylebox_override("disabled", _button_box(false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", _button_box(true))
	button.pressed.connect(on_press)
	return button


## --- 여닫기 · 그리기 ---

func open() -> void:
	# 자동 등록으로 새로 찬 칸이 있으면 그 등급 탭으로 연다 — 보던 탭에도 있으면 그대로
	if not _grade_has_new(_grade):
		for grade in range(1, _grade_count() + 1):
			if _grade_has_new(grade):
				_grade = grade
				_auto_pick = true
				break
	visible = true
	_seen = ""
	_redraw()


func close_panel() -> void:
	visible = false
	_picker.close()
	_auto_sheet.close()


## 장부가 바뀌면 다시 그린다 — `game.gd` 가 매 프레임 부른다. 같으면 안 짓는다
func refresh(me: Dictionary) -> void:
	_me = me
	if not visible:
		return
	_auto_sheet.refresh(me)
	var seen := "%d|%s|%s|%s|%s|%s" % [
		_grade, _auto_pick, _pick, me.get("codex", {}), Ledger.codex_new(me), _bag_key(me.get("bag", []))]
	if seen == _seen:
		return
	_seen = seen
	_redraw()


## 고른 등급 (1 ~ 7) · 고른 칸 `[부위, 강화]` — 테스트가 본다
func grade() -> int:
	return _grade


func picked() -> Array:
	return _pick


func register_button() -> Button:
	return _register_button


func auto_button() -> Button:
	return _auto_button


func enhance_button() -> Button:
	return _enhance_button


## 빨간 점이 켜진 탭 (등급 번호) — 테스트가 본다
func dotted_tabs() -> Array:
	var out: Array = []
	for index in _tab_dots.size():
		if (_tab_dots[index] as Control).visible:
			out.append(index + 1)
	return out


## 자동 등록 설정 창 · 탭 줄의 그 단추 — 테스트가 본다
func auto_sheet() -> CodexAutoSheet:
	return _auto_sheet


func auto_setting_button() -> Button:
	return _auto_setting


## 그 칸에 빨간 점이 켜졌나 — 넣을 수 있는 칸, 또는 자동 등록으로 새로 찬 칸. 테스트가 본다
func cell_dot(slot: String, enhance: int) -> bool:
	return (_cells["%s:%d" % [slot, enhance]].get_node("red_dot") as Control).visible


## 칸 상태 — "filled" · "owned"(가방에 있어 넣을 수 있다) · "empty". 테스트가 본다
func cell_state(slot: String, enhance: int) -> String:
	var item_id := Items.item_id(_grade, slot)
	if Codex.has(_me.get("codex", {}), item_id, enhance):
		return "filled"
	return "owned" if int(_owned(_me.get("bag", [])).get("%s:%d" % [item_id, enhance], 0)) > 0 else "empty"


## `codexResult` 이벤트 — 방금 찬 칸을 살짝 튕긴다
func show_result(event: Dictionary) -> void:
	if not visible:
		return
	var item := Items.get_item(str(event.get("id", "")))
	var cell: Button = _cells.get("%s:%d" % [str(item.get("slot", "")), int(event.get("enhance", -1))])
	if cell == null or int(item.get("grade", 0)) != _grade:
		return
	cell.pivot_offset = cell.size * 0.5
	cell.scale = Vector2.ONE * 1.18
	create_tween().tween_property(cell, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pick_grade(grade: int) -> void:
	if grade != _grade:
		_leave_tab()
	_grade = clampi(grade, 1, _grade_count())
	_auto_pick = true
	_seen = ""
	refresh(_me)


func _pick_cell(slot: String, enhance: int) -> void:
	_pick = [slot, enhance]
	_auto_pick = false
	_seen = ""
	refresh(_me)


func _on_register() -> void:
	if _pick.is_empty():
		return
	# 넣을 장비는 따로 뜨는 창에서 고른다 — 1·2·3차 옵션을 다 보고 고른다 (codex_picker.gd)
	_picker.open(Items.item_id(_grade, str(_pick[0])), int(_pick[1]), _me.get("bag", []))


## [강화] — 고른 칸의 장비 중 목표에 가장 가까운 것을 그 칸의 강화 단계까지 올리는 강화 창을 띄운다
func _on_enhance() -> void:
	var at := _enhance_source()
	if at >= 0:
		enhance_requested.emit(at, int(_pick[1]))


## 고른 칸을 채울 가방 번호 — 직접 누른 칸이고, 아직 비었고, 같은 장비가 목표 아래에 있어야 한다. 아니면 -1
func _enhance_source() -> int:
	if _auto_pick or _pick.is_empty():
		return -1
	var item_id := Items.item_id(_grade, str(_pick[0]))
	if Codex.has(_me.get("codex", {}), item_id, int(_pick[1])):
		return -1
	return Codex.enhance_source(_me.get("bag", []), item_id, int(_pick[1]))


## [자동 등록 설정] — 등급마다 ON/OFF 를 고르는 창
func _open_auto() -> void:
	# 도감에서 보던 등급 탭으로 연다
	_auto_sheet.pick_grade(_grade)
	_auto_sheet.open(_me)


## 보던 탭을 떠난다 — 그 등급에 자동 등록으로 새로 찬 칸이 있었으면 본 것으로 친다(`seen`)
func _leave_tab() -> void:
	if _grade_has_new(_grade):
		seen.emit(_grade)


## 그 등급에 자동 등록으로 새로 찬 칸이 있나 (`codex_new`)
func _grade_has_new(grade: int) -> bool:
	var marks := Ledger.codex_new(_me)
	for slot in Items.slots():
		if int(marks.get(Items.item_id(grade, str(slot)), 0)) != 0:
			return true
	return false


## [자동 등록] — 바로 넣지 않고 들어갈 장비 전부를 확인 창에 늘어놓는다 (넣으면 가방에서 사라진다)
func _on_register_all() -> void:
	var bag: Array = _me.get("bag", [])
	_picker.open_all(bag, Codex.auto_picks(_me.get("codex", {}), bag))


## 등록할 장비 선택 창 — 테스트가 본다
func picker() -> CodexPicker:
	return _picker


func _redraw() -> void:
	var codex: Dictionary = _me.get("codex", {})
	var owned := _owned(_me.get("bag", []))
	var marks := Ledger.codex_new(_me)

	# 빨간 점 — 넣을 수 있는 칸이 있거나, 자동 등록으로 새로 찬 칸이 있는 탭
	for index in _tabs.size():
		var grade := index + 1
		_paint_tab(_tabs[index], grade == _grade, grade)
		(_tab_dots[index] as Control).visible = _grade_has_owned(grade, codex, owned) or _grade_has_new(grade)

	# 직접 고르기 전에는 넣을 수 있는 첫 칸 → 없으면 빈 첫 칸 → 다 찼으면 첫 칸
	if _auto_pick or _pick.is_empty():
		_pick = _first_cell(codex, owned)

	for slot in Items.slots():
		var item_id := Items.item_id(_grade, str(slot))
		var texture: Texture2D = _icon.call("%s_g%d" % [slot, _grade]) if _icon.is_valid() else null
		for enhance in Codex.max_enhance() + 1:
			var cell: Button = _cells["%s:%d" % [slot, enhance]]
			var filled := Codex.has(codex, item_id, enhance)
			var have := int(owned.get("%s:%d" % [item_id, enhance], 0)) > 0
			var chosen: bool = not _pick.is_empty() and str(_pick[0]) == str(slot) and int(_pick[1]) == enhance
			_paint_cell(cell, filled, have, chosen)
			var art: TextureRect = cell.get_node("art")
			art.texture = texture
			art.modulate = Color.WHITE if filled else (Color(1, 1, 1, 0.5) if have else Color(0.5, 0.5, 0.5, 0.18))
			var badge: Label = cell.get_node("badge")
			badge.add_theme_color_override("font_color", GOLD if filled else (IVORY if have else FAINT))
			var fresh := filled and Codex.has(marks, item_id, enhance)
			(cell.get_node("red_dot") as Control).visible = (have and not filled) or fresh

	_redraw_effects(codex)
	_redraw_pick(codex, owned)
	# 자동 등록은 등급을 가리지 않는다 — 넣을 것(잠근 것 빼고)이 어느 탭에든 하나라도 있으면 켠다
	var any := not Codex.auto_picks(codex, _me.get("bag", [])).is_empty()
	_auto_button.disabled = not any
	_auto_button.modulate = Color.WHITE if any else Color(1, 1, 1, 0.45)


## 획득 효과 — 도감 전체의 능력치 셋, 줄 끝에 이 등급 몫(하늘색)
func _redraw_effects(codex: Dictionary) -> void:
	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()
	var total := Codex.stat_bonus(codex)
	var here := Codex.stat_bonus(codex, _grade)
	for stat in ["attack", "defense", "maxHp"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var lit := float(total[stat]) > 0.0
		line.add_child(_diamond(GOLD if lit else FAINT))
		line.add_child(_label("%s +%s%%" % [Codex.stat_name(stat), _pct(float(total[stat]))], 21, IVORY if lit else DIM))
		if float(here[stat]) > 0.0:
			line.add_child(_label("(%s +%s%%)" % [Items.grade_name(_grade), _pct(float(here[stat]))], 17, NEXT))
		_effects.add_child(line)
	var per_grade := Items.slots().size() * (Codex.max_enhance() + 1)
	_progress.text = "%s %d / %d   ·   전체 %d / %d" % [
		Items.grade_name(_grade), Codex.filled(codex, _grade), per_grade,
		Codex.filled(codex), per_grade * _grade_count(),
	]


## 고른 칸 — 그림 · 이름 · 몫 · 보유 · 등록 단추
func _redraw_pick(codex: Dictionary, owned: Dictionary) -> void:
	if _pick.is_empty():
		return
	var slot := str(_pick[0])
	var enhance := int(_pick[1])
	var item_id := Items.item_id(_grade, slot)
	var item := Items.get_item(item_id)
	_pick_icon.texture = _icon.call("%s_g%d" % [slot, _grade]) if _icon.is_valid() else null
	_pick_name.text = "%s +%d" % [str(item.get("name", Items.slot_label(slot))), enhance]
	_pick_name.add_theme_color_override("font_color", Items.grade_color(_grade))
	_pick_gain.text = "%s +%s%%" % [Codex.stat_name(Codex.slot_stat(slot)), _pct(Codex.cell_value(_grade, enhance))]
	var count := int(owned.get("%s:%d" % [item_id, enhance], 0))
	var filled := Codex.has(codex, item_id, enhance)
	if filled:
		_pick_have.text = "등록 완료"
		_pick_have.add_theme_color_override("font_color", GOLD)
	elif count > 0:
		_pick_have.text = "가방에 %d개 보유" % count
		_pick_have.add_theme_color_override("font_color", OK)
	else:
		_pick_have.text = "가방에 없습니다"
		_pick_have.add_theme_color_override("font_color", WARN)
	var can := not filled and count > 0
	_register_button.disabled = not can
	_register_button.modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)
	var lift := _enhance_source() >= 0
	_enhance_button.disabled = not lift
	_enhance_button.modulate = Color.WHITE if lift else Color(1, 1, 1, 0.45)


## 가방 → `{ "아이템 id:강화": 개수 }` — 장비만 센다 (재료는 칸이 없다). **잠근 것은 안 센다** —
## 등록할 수 없으니 "가방에 있음" 으로 띄우면 눌러도 거절만 당한다
func _owned(bag: Array) -> Dictionary:
	var out := {}
	for stack in bag:
		var id := str(stack.get("id", ""))
		if Items.get_item(id).is_empty() or Items.is_locked(stack):
			continue
		var key := "%s:%d" % [id, int(stack.get("enhance", 0))]
		out[key] = int(out.get(key, 0)) + int(stack.get("count", 1))
	return out


## 가방이 바뀌었나만 알면 된다 — 장비의 id · 강화 · 개수 · 잠금만 이어 붙인다 (옵션까지 문자열로 만들지 않는다)
func _bag_key(bag: Array) -> String:
	var parts := PackedStringArray()
	for stack in bag:
		parts.append("%s+%d*%d%s" % [
			stack.get("id", ""), int(stack.get("enhance", 0)), int(stack.get("count", 1)),
			"L" if Items.is_locked(stack) else "",
		])
	return ",".join(parts)


func _grade_has_owned(grade: int, codex: Dictionary, owned: Dictionary) -> bool:
	for slot in Items.slots():
		var item_id := Items.item_id(grade, str(slot))
		for enhance in Codex.max_enhance() + 1:
			if int(owned.get("%s:%d" % [item_id, enhance], 0)) > 0 and not Codex.has(codex, item_id, enhance):
				return true
	return false


func _first_cell(codex: Dictionary, owned: Dictionary) -> Array:
	var empty: Array = []
	for slot in Items.slots():
		var item_id := Items.item_id(_grade, str(slot))
		for enhance in Codex.max_enhance() + 1:
			if Codex.has(codex, item_id, enhance):
				continue
			if int(owned.get("%s:%d" % [item_id, enhance], 0)) > 0:
				return [str(slot), enhance]
			if empty.is_empty():
				empty = [str(slot), enhance]
	return empty if not empty.is_empty() else [str(Items.slots()[0]), 0]


## 등급 수 (탭 수) — 아이템 표의 끝 등급
func _grade_count() -> int:
	return int(Items._t().get("gradeMax", 7))


## 0.01% 단위 — `String.num` 이 끝자리 0 을 뗀다 (0.10 → 0.1, 2.00 → 2)
func _pct(value: float) -> String:
	# 0 은 "0.0" 으로 찍혔다 (2026-10-01 스크린샷 "방어력 +0.0%") — 0 만 따로 적는다
	return "0" if is_zero_approx(value) else String.num(value, 2)


func _paint_cell(cell: Button, filled: bool, have: bool, chosen: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.05, 0.95) if filled else Color(0.03, 0.03, 0.03, 0.85)
	box.border_color = Items.grade_color(_grade) if filled else (NEXT if have else GatePanel.CELL_LINE)
	if chosen:
		box.border_color = GOLD
	box.set_border_width_all(3 if chosen else (2 if filled or have else 1))
	box.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed", "disabled"]:
		cell.add_theme_stylebox_override(state, box)


func _paint_tab(tab: Button, on: bool, grade: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.78, 0.5, 0.08) if on else Color(0, 0, 0, 0)
	box.border_color = GOLD if on else Color(0, 0, 0, 0)
	box.border_width_bottom = 3
	box.set_content_margin_all(6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		tab.add_theme_stylebox_override(state, box)
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 등급 이름은 등급 색 — 안 고른 탭은 흐리게
	var color := Items.grade_color(grade)
	tab.add_theme_color_override("font_color", color if on else color.darkened(0.45))
	tab.add_theme_color_override("font_hover_color", color)
	tab.add_theme_color_override("font_pressed_color", color)


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


func _button_box(pressed: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 12)
	var sink: int = SINK if pressed else 0
	box.content_margin_top = 12 + sink
	box.content_margin_bottom = 12 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
	return box


## 오른쪽 위 빨간 점 — 탭은 그 등급에, 칸은 그 칸에 넣을 수 있는 장비가 가방에 있으면 켠다
func _red_dot(owner: Control, inset: int) -> Control:
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
	dot.offset_left = -12 - inset
	dot.offset_right = -inset
	dot.offset_top = inset
	dot.offset_bottom = 12 + inset
	dot.visible = false
	owner.add_child(dot)
	return dot


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
