class_name DiscardPopup
extends Control

## 버리기 창 — 인벤토리 아래 줄 **"버리기"** 로 연다 (2026-10-02 요청: "가방에서 버리기 버튼 만들어.
## 버리기 UI가 뜨고 거기서 전체 선택 및 개별 선택, 등급별 선택 할 수 있게 만들어").
## 화면 가운데에 뜨고 뒤를 어둡게 덮는다 — 떠 있는 동안 가방 번호가 바뀔 일이 없다 (드롭은 끝에 붙는다).
##
##   ┌ ▣ 버리기 ──────────────────────── X ┐
##   │ [전체 선택]            고른 것 3/41 │
##   │ [일반][고급][희귀][영웅][전설][신화][태초] │  ← 그 등급 전부 담기 / 다 담겼으면 빼기
##   │ ▢ ▢ ▢ ▢ ▢ ▢ ▢                     │  ← 칸을 누르면 하나씩 담기 / 빼기 (금테)
##   │ …  (끌어서 내린다)                  │
##   │ ◆ 착용 중 · 잠근 장비는 없습니다  [버리기] │
##   └─────────────────────────────────────┘
##          [버리기] → 확인 창 "장비 N개를 버립니다" [취소] [버리기]
##
## 목록은 **가방의 장비만** — 재료(크리스탈)·잠근 장비는 안 나온다. 판정(`Ledger.discard`)도 같은 것을
## 다시 거른다. 요청은 `discard {indices}` 한 번. 틀·칸·단추는 game.gd 와 강화 팝업 것을 빌린다 (같은 결)
## → docs/features/inventory-equipment.md "버리기"

## 고른 가방 번호 — game 이 `discard` 로 보낸다
signal discarded(indices: Array)
signal closed

const COLS := 7
const CELL := 62
const GAP := 6
const LIST_HEIGHT := 340
const GRADE_BUTTON := 64
const HINT := "착용 중 · 잠근 장비는 목록에 없습니다"

var panel: PanelContainer
var list_grid: GridContainer
var list_drag: DragScroll
var all_button: Button
var count_label: Label
var go: Button
## 등급 → 단추. 단추 위의 금테(`pick`)가 "그 등급이 다 담겼다" 를 말한다
var grade_buttons := {}
var confirm: Control
var confirm_text: Label
## 창 뒤를 덮는 막 — 상세 창에서 하나만 버릴 때는 확인 창 막 한 겹만 쓰려고 감춘다
var _dim: ColorRect
## 상세 창 "버리기" 로 열었다 — 목록 창 없이 확인 창만 띄우고, 취소·확인하면 통째로 닫는다
var _single := false

## 담은 가방 번호
var picked: Array = []
## 칸 k 가 가리키는 가방 번호
var _view: Array = []
var _cells: Array = []
var _game  # game.gd — class_name 이 없어서 이름 없이 든다


static func make(game: Node) -> DiscardPopup:
	var popup := DiscardPopup.new()
	popup.name = "DiscardPopup"
	popup._game = game
	popup._build()
	return popup


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = _game._window_panel()
	panel.visible = true
	center.add_child(panel)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)
	_game._stone_title(side, "버리기", 22, "bag")

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	side.add_child(head)
	all_button = _button("전체 선택", toggle_all)
	all_button.name = "All"
	all_button.custom_minimum_size.x = 120
	head.add_child(all_button)
	count_label = _game._inv_label("", 18, _game.INV_TEXT)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count_label)

	# 등급별 — 누르면 그 등급 전부 담고, 이미 다 담겼으면 뺀다. 글자는 등급 색
	var grades := HBoxContainer.new()
	grades.add_theme_constant_override("separation", GAP)
	side.add_child(grades)
	for grade in range(1, int(Items._t().get("gradeMax", 7)) + 1):
		var button: Button = _button(Items.grade_name(grade), toggle_grade.bind(grade))
		button.name = "Grade%d" % grade
		button.custom_minimum_size.x = GRADE_BUTTON
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tint: Color = _game._grade_tint(grade)
		button.add_theme_color_override("font_color", tint)
		button.add_theme_color_override("font_hover_color", tint.lightened(0.2))
		button.add_theme_color_override("font_pressed_color", tint)
		var frame := Panel.new()
		frame.name = "pick"
		frame.visible = false
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", _game._inv_pick_box())
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(frame)
		grades.add_child(button)
		grade_buttons[grade] = button

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS * CELL + (COLS - 1) * GAP + 14, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	list_grid = GridContainer.new()
	list_grid.columns = COLS
	list_grid.add_theme_constant_override("h_separation", GAP)
	list_grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(list_grid)
	# **끌어서 내린다** — 칸 단추가 끌기를 먹었다 (`DragScroll`, 가방과 같다)
	list_drag = DragScroll.attach(scroll, list_grid, GAP)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	side.add_child(foot)
	var hint: Label = _game._inv_label(HINT, 15, _game.INV_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	go = _button("버리기", ask)
	go.name = "Go"
	go.custom_minimum_size.x = 110
	foot.add_child(go)

	_game._close_button(panel, close, 0)
	_build_confirm()


## 확인 창 — 버린 장비는 되돌릴 수 없다. 창 위에 한 겹 더 어둡게 덮고 가운데에 띄운다
func _build_confirm() -> void:
	confirm = Control.new()
	confirm.name = "Confirm"
	confirm.visible = false
	confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(confirm)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm.add_child(center)
	var sheet: PanelContainer = _game._window_panel()
	sheet.visible = true
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	column.add_theme_constant_override("separation", 14)
	sheet.add_child(column)
	confirm_text = _game._inv_label("", 20, _game.INV_TEXT)
	confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(confirm_text)
	var warn: Label = _game._inv_label("버린 장비는 되돌릴 수 없습니다", 16, _game.INV_WARN)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(warn)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var cancel: Button = _button("취소", _cancel)
	cancel.name = "Cancel"
	cancel.custom_minimum_size.x = 110
	row.add_child(cancel)
	var yes: Button = _button("버리기", commit)
	yes.name = "Yes"
	yes.custom_minimum_size.x = 110
	row.add_child(yes)


## 단추 — 강화 팝업의 것(잠기면 회색)을 그대로 쓴다
func _button(text: String, on_press: Callable) -> Button:
	return _game._enhance._button(text, on_press)


func open() -> void:
	picked = []
	confirm.visible = false
	visible = true
	redraw()


func close() -> void:
	hide_now()
	closed.emit()


## 상세 창 "버리기" (2026-10-02 요청) — 가방 번호 `index` 하나를 목록 창 없이 **확인 창만** 띄워 묻는다.
## 판정은 같은 `discard {indices}` 다
func ask_one(index: int, title: String) -> void:
	if index < 0 or index >= _bag().size() or not can_discard(_bag()[index]):
		return
	_single = true
	picked = [index]
	panel.visible = false
	_dim.visible = false
	visible = true
	confirm_text.text = "%s\n이 장비를 버립니다" % title
	confirm.visible = true


## 확인 창의 [취소] — 목록 창에서 왔으면 확인 창만, 상세 창에서 왔으면 통째로 닫는다
func _cancel() -> void:
	if _single:
		close()
		return
	confirm.visible = false


func hide_now() -> void:
	visible = false
	confirm.visible = false
	picked = []
	list_drag.forget()
	_single = false
	panel.visible = true
	_dim.visible = true


func _bag() -> Array:
	return _game._transport.snapshot().get("players", {}).get(_game._transport.my_id(), {}).get("bag", [])


## 버릴 수 있는 칸인가 — 장비이고 잠그지 않은 것 (판정 `Ledger.discard` 와 같은 거르기)
static func can_discard(stack: Dictionary) -> bool:
	var id := str(stack.get("id", ""))
	return not Items.get_item(id).is_empty() and not Items.is_material(id) and not Items.is_locked(stack)


func toggle_cell(k: int) -> void:
	if k < 0 or k >= _view.size():
		return
	var at: int = _view[k]
	if picked.has(at):
		picked.erase(at)
	else:
		picked.append(at)
	redraw()


## 전체 — 다 담겼으면 비우고, 아니면 다 담는다
func toggle_all() -> void:
	if not _view.is_empty() and picked.size() == _view.size():
		picked = []
	else:
		picked = _view.duplicate()
	redraw()


## 등급 — 그 등급이 다 담겼으면 그 등급만 빼고, 아니면 그 등급을 다 담는다
func toggle_grade(grade: int) -> void:
	var of_grade := _of_grade(grade)
	if of_grade.is_empty():
		return
	if of_grade.all(func(at: int) -> bool: return picked.has(at)):
		picked = picked.filter(func(at: int) -> bool: return not of_grade.has(at))
	else:
		for at in of_grade:
			if not picked.has(at):
				picked.append(at)
	redraw()


func _of_grade(grade: int) -> Array:
	var bag := _bag()
	return _view.filter(func(at: int) -> bool: return int(bag[at].get("grade", 1)) == grade)


## 담은 개수 — 겹친 칸은 개수만큼
func _pieces() -> int:
	var bag := _bag()
	var total := 0
	for at in picked:
		total += int(bag[at].get("count", 1))
	return total


## [버리기] — 바로 버리지 않고 확인 창을 띄운다
func ask() -> void:
	if picked.is_empty():
		return
	confirm_text.text = "장비 %d개를 버립니다" % _pieces()
	confirm.visible = true


## 확인 창의 [버리기] — 요청을 내고 담은 것을 비운다 (가방 번호가 바뀐다)
func commit() -> void:
	confirm.visible = false
	if picked.is_empty():
		return
	var indices := picked.duplicate()
	picked = []
	discarded.emit(indices)
	if _single:
		close()
		return
	redraw()


## 목록을 채운다. 칸은 모자라면 더 짓고 남으면 감춘다 (가방 200칸을 매번 새로 짓지 않는다)
func redraw() -> void:
	if not visible:
		return
	var bag := _bag()
	_view = []
	for at in bag.size():
		if can_discard(bag[at]):
			_view.append(at)
	# 장부가 바뀌어 사라진 번호는 뺀다
	picked = picked.filter(func(at: int) -> bool: return _view.has(at))
	while _cells.size() < _view.size():
		var cell: PanelContainer = _game._make_cell(toggle_cell.bind(_cells.size()), CELL)
		list_grid.add_child(cell)
		_cells.append(cell)
	for k in _cells.size():
		var cell: PanelContainer = _cells[k]
		cell.visible = k < _view.size()
		if not cell.visible:
			continue
		var stack: Dictionary = bag[_view[k]]
		_game._fill_cell(cell, stack, "", _game._item_icon(stack))
		cell.get_node("pick").visible = picked.has(_view[k])
	var everything := not _view.is_empty() and picked.size() == _view.size()
	all_button.text = "전체 해제" if everything else "전체 선택"
	all_button.disabled = _view.is_empty()
	for grade in grade_buttons:
		var button: Button = grade_buttons[grade]
		var of_grade := _of_grade(int(grade))
		button.disabled = of_grade.is_empty()
		button.get_node("pick").visible = not of_grade.is_empty() \
				and of_grade.all(func(at: int) -> bool: return picked.has(at))
	count_label.text = "고른 것 %d/%d" % [picked.size(), _view.size()]
	go.disabled = picked.is_empty()
