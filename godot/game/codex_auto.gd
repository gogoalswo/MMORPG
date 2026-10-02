class_name CodexAutoSheet
extends Control

## 도감 **자동 등록 설정** 창 — 도감 창 탭 줄 오른쪽 [자동 등록 설정] 으로 뜬다 (2026-10-02 요청: "도감창에 아이템
## 자동 등록 활성화 기능 만들어. 등급별로 설정할 수 있도록"). 켠 등급의 장비를 **주우면** 장부가 바로 도감에 넣고,
## 그 단계 칸이 차 있으면 다음 빈 단계까지 +1 씩 두드려 올려 넣는다 (`Ledger._codex_auto`) → codex.md "주울 때 자동 등록"
##
##   ┌──────────── 자동 등록 설정 ────────────┐
##   │ ◆ 켠 등급의 장비를 주우면 바로 도감에 넣습니다 │
##   │ ◆ 칸이 차 있으면 다음 빈 단계까지 강화합니다 … │
##   │  일반                     [ ON ][ OFF ] │   ← 설정 창과 같은 두 칸 스위치 (`SettingsPanel.make_switch`)
##   │  … 태초                                 │
##   │                              [ 닫기 ]  │
##   └───────────────────────────────────────┘
##
## 값은 **장부**(`codex_auto`)다 — 가방에서 무엇이 사라지는지가 바뀐다. 이 창은 요청만 내고 장부 값을 그린다.

## 켤 등급 목록 전체 — `game.gd` 가 `codexAuto` 로 보낸다
signal changed(grades: Array)

const WIDTH := 600.0
const ROW_HEIGHT := 50.0

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const DIM := Color("#948c7a")

var _me: Dictionary = {}
var _seen := ""
## 등급 → 그 줄의 ON/OFF 스위치
var _switches := {}


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
	column.add_theme_constant_override("separation", 6)
	sheet.add_child(column)
	var title := _label("자동 등록 설정", 24, TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)
	for text in [
		"켠 등급의 장비를 주우면 바로 도감에 넣습니다",
		"칸이 차 있으면 다음 빈 단계까지 +1 부터 강화해 넣습니다 — 실패하면 부서집니다",
	]:
		column.add_child(_hint(text))
	for grade in range(1, int(Items._t().get("gradeMax", 7)) + 1):
		var switch := SettingsPanel.make_switch("auto_%d" % grade, func(on: bool) -> void: _set_grade(grade, on))
		_switches[grade] = switch
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		var name_label := _label(Items.grade_name(grade), 20, Items.grade_color(grade))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(switch)
		column.add_child(row)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(foot)
	close_button.name = "done"
	close_button.pressed.connect(close)
	foot.add_child(close_button)


func open(me: Dictionary) -> void:
	visible = true
	_seen = ""
	refresh(me)


func close() -> void:
	visible = false


## 장부가 바뀌면 스위치를 맞춘다 — 도감 창이 `refresh` 마다 부른다
func refresh(me: Dictionary) -> void:
	_me = me
	if not visible:
		return
	var seen := str(Ledger.codex_auto(me))
	if seen == _seen:
		return
	_seen = seen
	var on := Ledger.codex_auto(me)
	for grade in _switches:
		SettingsPanel.paint_switch(_switches[grade], int(grade) in on)


## 그 등급 스위치가 켜졌나 — 테스트가 본다
func is_on(grade: int) -> bool:
	return SettingsPanel.switch_on(_switches[grade])


func _set_grade(grade: int, on: bool) -> void:
	var grades := Ledger.codex_auto(_me).duplicate()
	if on == (grade in grades):
		return
	if on:
		grades.append(grade)
	else:
		grades.erase(grade)
	grades.sort()
	changed.emit(grades)


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
	line.add_child(label)
	return line


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
