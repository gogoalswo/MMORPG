class_name CodexAutoSheet
extends Control

## 도감 **자동 등록 설정** 창 — 도감 창 오른쪽 칸 맨 아래 [자동 등록 설정] 으로 뜬다 (2026-10-02 요청: "도감창에 아이템
## 자동 등록 활성화 기능 만들어. 등급별로 설정할 수 있도록" → "1차 옵션도 선택해서 … 치명타 옵션이 있을 경우 등록 안 되게"
## → "등급마다 아이템 종류도 선택할 수 있게" → "등급마다 옵션 설정할 수 있게"). 켠 등급의 고른 부위 장비를 **주우면**
## 장부가 바로 도감에 넣고, 그 단계 칸이 차 있으면 다음 빈 단계까지 +1 씩 두드려 올려 넣는다 (`Ledger._codex_auto`)
## → codex.md "주울 때 자동 등록"
##
##   ┌──────────────────── 자동 등록 설정 ────────────────────┐
##   │  일반•  고급  희귀•  영웅  전설  초월  태초               │ ← 등급 탭 (켠 등급은 금빛 점)
##   │  자동 등록                               [ ON ][ OFF ]  │
##   │  아이템 종류 — 활성화 된 종류만 자동으로 등록합니다          │
##   │  [무기][갑옷][투구][신발][목걸이][반지]                    │ ← 켜면(밝음) 넣는다
##   │  1차 옵션 — 활성화 된 옵션만 자동으로 등록합니다            │
##   │  [치명타][치명타 데미지][체력][방어력 관통][아이템 드랍률]    │ ← 켜면(밝음) 넣는다
##   │                     (오른쪽 위 X 로 닫는다 — [닫기] 단추는 뺐다)│
##
## 일곱 등급을 한 화면에 줄로 늘어놓으면 옵션 칩까지 720 높이에 안 들어가 **등급 탭**으로 나눴다.
## 값은 **장부**(`codex_auto` · `codex_auto_options`)다 — 이 창은 요청만 내고 장부 값을 그린다.

## 등급 하나의 넣을 부위 목록(비면 그 등급을 끈다) — `game.gd` 가 `codexAutoGrade` 로 보낸다
signal changed(grade: int, slots: Array)
## 등급 하나의 넣을 1차 옵션 목록 — `game.gd` 가 `codexAutoOptions` 로 보낸다
signal options_changed(grade: int, kinds: Array)

const WIDTH := 860.0

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const DIM := Color("#948c7a")

var _me: Dictionary = {}
var _seen := ""
## 고른 등급 탭
var _grade := 1
var _tabs := {}
var _pages := {}
## 등급 → ON/OFF 스위치 · `{부위: 칩}` · `{옵션 종류: 칩}`
var _switches := {}
var _chips := {}
var _option_chips := {}


static func make(close_button: Button) -> CodexAutoSheet:
	var sheet := CodexAutoSheet.new()
	sheet._build(close_button)
	return sheet


func _build(close_button: Button) -> void:
	name = "CodexAuto"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 뒤를 어둡게 덮고 누름을 막는다 — 고르기 창과 같다
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.name = "sheet"
	sheet.custom_minimum_size = Vector2(WIDTH, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.055, 0.045, 0.97)
	box.border_color = Color(GOLD, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(18)
	sheet.add_theme_stylebox_override("panel", box)
	center.add_child(sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	sheet.add_child(column)
	var title := _label("자동 등록 설정", 24, TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0, close_button.custom_minimum_size.y)  # 오른쪽 위 X 가 아래 줄에 안 걸친다
	column.add_child(title)
	column.add_child(_hint("주운 장비를 바로 도감에 넣습니다 — 칸이 차 있으면 다음 빈 단계까지 +1 부터 강화해 넣고, 실패하면 부서집니다"))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	column.add_child(tabs)
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	var labels: Dictionary = Items._t().get("optionLabel", {})
	for grade in range(1, int(Items._t().get("gradeMax", 7)) + 1):
		# 등급 탭 · 칩은 설정 창 "아이템 → 습득" 과 같이 쓴다 (`SettingsPanel.make_grade_tab` · `make_chip`)
		var tab := SettingsPanel.make_grade_tab("tab_%d" % grade, grade, pick_grade.bind(grade))
		tabs.add_child(tab)
		_tabs[grade] = tab

		var page := VBoxContainer.new()
		page.name = "page_%d" % grade
		page.add_theme_constant_override("separation", 8)
		column.add_child(page)
		_pages[grade] = page
		var row := HBoxContainer.new()
		var head := _label("자동 등록", 20, Color("#d6d0c4"))
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(head)
		var switch := SettingsPanel.make_switch("auto_%d" % grade, func(on: bool) -> void: _set_grade(grade, on))
		row.add_child(switch)
		page.add_child(row)
		_switches[grade] = switch

		page.add_child(SettingsPanel.chip_head("아이템 종류 — 활성화 된 종류만 자동으로 등록합니다"))
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 8)
		page.add_child(slots)
		var chips := {}
		for slot in Items.slots():
			var chip := SettingsPanel.make_chip("slot_%d_%s" % [grade, slot], Items.slot_label(str(slot)), SettingsPanel.CHIP)
			chip.pressed.connect(_toggle_slot.bind(grade, str(slot)))
			slots.add_child(chip)
			chips[str(slot)] = chip
		_chips[grade] = chips

		page.add_child(SettingsPanel.chip_head("1차 옵션 — 활성화 된 옵션만 자동으로 등록합니다"))
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		page.add_child(options)
		var option_chips := {}
		for kind in Items._t().get("optionKinds", []):
			var chip := SettingsPanel.make_chip("option_%d_%s" % [grade, kind], str(labels.get(kind, kind)),
				SettingsPanel.OPTION_CHIP)
			chip.pressed.connect(_toggle_option.bind(grade, str(kind)))
			options.add_child(chip)
			option_chips[str(kind)] = chip
		_option_chips[grade] = option_chips

	# 오른쪽 위 X — 판 안쪽 모서리에 앵커로 얹는다 (창 X 와 같은 자리 규칙, ui-art-style.md "창은 오른쪽 위 X 로 닫는다").
	# 판 위에 겹쳐 놓는 층이라 누름은 X 만 받는다
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(layer)
	close_button.name = "close"
	close_button.pressed.connect(close)
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -close_button.custom_minimum_size.x
	close_button.offset_right = 0
	close_button.offset_top = 0
	close_button.offset_bottom = close_button.custom_minimum_size.y
	layer.add_child(close_button)
	pick_grade(1)


func open(me: Dictionary) -> void:
	visible = true
	# 도감 창 X 는 `game.gd` 가 나중에 붙여 맨 뒤 자식이다 — 그보다 앞으로 올려야 X 가 이 창 위에서 안 눌린다
	# (2026-10-02 지적 "자동 등록 설정 창 누른 상태에서도 뒤에 도감창 X버튼이 눌리는 문제")
	move_to_front()
	_seen = ""
	refresh(me)


func close() -> void:
	visible = false


## 등급 탭을 고른다
func pick_grade(grade: int) -> void:
	_grade = clampi(grade, 1, _tabs.size())
	for each in _pages:
		(_pages[each] as Control).visible = each == _grade
	_seen = ""
	refresh(_me)


## 장부가 바뀌면 탭·스위치·칩을 맞춘다 — 도감 창이 `refresh` 마다 부른다
func refresh(me: Dictionary) -> void:
	_me = me
	if not visible:
		return
	var table := Ledger.codex_auto(me)
	var options := Ledger.codex_auto_options(me)
	var seen := "%d|%s|%s" % [_grade, table, options]
	if seen == _seen:
		return
	_seen = seen
	for grade in _tabs:
		var slots: Array = table.get(str(grade), [])
		var allowed := Ledger.codex_auto_option_kinds(me, grade)
		SettingsPanel.paint_grade_tab(_tabs[grade], grade == _grade, grade, not slots.is_empty())
		SettingsPanel.paint_switch(_switches[grade], not slots.is_empty())
		for slot in _chips[grade]:
			SettingsPanel.paint_chip(_chips[grade][slot], slot in slots, not slots.is_empty())
		for kind in _option_chips[grade]:
			SettingsPanel.paint_chip(_option_chips[grade][kind], kind in allowed, not slots.is_empty())


## 고른 탭 · 그 등급이 켜졌나 · 그 부위를 넣나 · 그 옵션을 막나 — 테스트가 본다
func grade() -> int:
	return _grade


func is_on(grade: int) -> bool:
	return SettingsPanel.switch_on(_switches[grade])


func slot_on(grade: int, slot: String) -> bool:
	return bool(_chips[grade][slot].get_meta("on", false))


func option_on(grade: int, kind: String) -> bool:
	return bool(_option_chips[grade][kind].get_meta("on", false))


## 등급 스위치 — 켜면 그 등급의 전 부위 · 전 옵션, 끄면 부위를 비운다(옵션은 그대로 둔다)
func _set_grade(grade: int, on: bool) -> void:
	var lit := not Ledger.codex_auto_slots(_me, grade).is_empty()
	if on == lit:
		return
	changed.emit(grade, Items.slots().duplicate() if on else [])
	if on:
		options_changed.emit(grade, Ledger.clean_option_kinds(Items._t().get("optionKinds", [])))


## 부위 칩 — 그 등급의 목록에서 넣고 뺀다. 마지막 하나를 빼면 그 등급이 꺼진다
func _toggle_slot(grade: int, slot: String) -> void:
	var slots: Array = Ledger.codex_auto_slots(_me, grade).duplicate()
	if slot in slots:
		slots.erase(slot)
	else:
		slots.append(slot)
	changed.emit(grade, Ledger.clean_slots(slots))


## 옵션 칩 — 켜면(활성화) 그 옵션이 붙은 장비를 넣는다
func _toggle_option(grade: int, kind: String) -> void:
	var kinds: Array = Ledger.codex_auto_option_kinds(_me, grade).duplicate()
	if kind in kinds:
		kinds.erase(kind)
	else:
		kinds.append(kind)
	options_changed.emit(grade, Ledger.clean_option_kinds(kinds))


func _hint(text: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var mark := ColorRect.new()
	mark.color = Color("#a08a5c")
	mark.custom_minimum_size = Vector2(6, 6)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var label := _label(text, 16, DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 줄바꿈 글자는 폭을 안 주면 최소 폭 0 으로 읽혀 한 글자씩 세로로 늘어난다
	label.custom_minimum_size = Vector2(WIDTH - 36 - 14, 0)
	line.add_child(label)
	return line


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
