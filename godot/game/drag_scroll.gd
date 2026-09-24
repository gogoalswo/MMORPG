class_name DragScroll
extends RefCounted

## 칸 격자를 담은 `ScrollContainer` 를 **끌어서 내린다**. 가방·스킬 목록·강화 목록이 같이 쓴다.
##
## 칸마다 칸 전체를 덮는 `hit` 단추가 있어서 **끌기를 단추가 다 먹었다** — 휠로만
## 내려가고 끌어서는(폰은 손가락으로) 안 내려갔다 (2026-09-24 지적: "인벤토리 ui
## 스크롤이 안돼"). 그래서 격자에 들어오는 칸의 `hit` 는 입력을 흘려보내고
## 목록이 직접 받는다: **데드존을 넘겨 끌면 스크롤, 그 자리에서 떼면 그 칸의
## `hit.pressed`** 를 낸다 — 누른 칸과 뗀 칸이 다르면 취소다.
##
## 방식은 차원문 목록(`GatePanel._on_list_input`)과 같다: 휠은 `ScrollContainer` 에
## 넘기고, 손가락 이벤트는 삼킨다 — 고도가 같은 손짓을 마우스로 흉내 내 한 번 더
## 보내므로(`emulate_mouse_from_touch`) 둘 다 받으면 두 배로 내려간다.
## 엔진의 끌기는 터치 화면일 때만 켜져서 PC 브라우저에서는 안 된다.

var _scroll: ScrollContainer
var _grid: Container
## 칸 사이 틈 — 틈을 눌러도 가까운 칸으로 친다
var _gap := 0.0
## 누른 자리(목록 기준 세로), 누를 때의 스크롤, 데드존을 넘겼나, 누른 칸
var _hold := false
var _hold_y := 0.0
var _hold_scroll := 0
var _dragging := false
var _held := -1


## 붙인다. 돌려받은 것을 버려도 된다 — 목록이 메타로 쥐고 있다
static func attach(scroll: ScrollContainer, grid: Container, gap: float) -> DragScroll:
	var drag := DragScroll.new()
	drag._scroll = scroll
	drag._grid = grid
	drag._gap = gap
	scroll.set_meta("drag_scroll", drag)
	scroll.gui_input.connect(drag.on_input)
	# 칸은 나중에 채워진다 — 들어오는 칸마다 입력을 흘려보내게 한다
	grid.child_entered_tree.connect(_let_through)
	for cell in grid.get_children():
		_let_through(cell)
	return drag


## 칸은 **흘려보내고**(PASS — 목록까지 올라간다) 칸 안의 것은 **비킨다**(IGNORE).
## 단추만 비켰더니 칸(`PanelContainer`, 기본이 STOP)이 입력을 멈춰서 목록에 안 닿았다 —
## 누르기까지 죽었다 (2026-09-24 지적: "아이템 선택도 안 되고 스크롤도 안돼").
## `on_input` 을 직접 부르는 테스트는 이 길을 안 거쳐서 통과했다
static func _let_through(cell: Node) -> void:
	var box := cell as Control
	if box != null:
		box.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in cell.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## 창을 여닫을 때 — 누르던 것을 잊는다 (그 사이 손을 뗐을 수 있다)
func forget() -> void:
	_hold = false
	_dragging = false
	_held = -1


func on_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_scroll.accept_event()
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_hold = true
			_dragging = false
			_hold_y = click.position.y
			_hold_scroll = _scroll.scroll_vertical
			_held = cell_at(click.position)
		elif _hold:
			var held := _held
			var tapped := not _dragging
			forget()
			if tapped and held >= 0 and held == cell_at(click.position):
				var hit := _grid.get_child(held).get_node_or_null("hit") as Button
				if hit != null:
					hit.pressed.emit()
		_scroll.accept_event()
		return
	var move := event as InputEventMouseMotion
	if move != null and _hold:
		var moved := move.position.y - _hold_y
		if not _dragging and absf(moved) > GatePanel.DEADZONE:
			_dragging = true
		if _dragging:
			# 손을 따라간다 — 위로 끌면 목록이 올라온다. 범위는 고도가 죈다
			_scroll.scroll_vertical = _hold_scroll - int(moved)
			_scroll.accept_event()


## 그 자리의 칸 번호 (없으면 -1). `at` 은 목록 기준이라 화면 기준으로 옮겨서
## 견준다 (칸은 스크롤만큼 밀려 있다). 감춘 칸은 건너뛴다 (강화 목록은 남는 칸을 감춘다)
func cell_at(at: Vector2) -> int:
	var point := _scroll.global_position + at
	for index in _grid.get_child_count():
		var cell := _grid.get_child(index) as Control
		if cell == null or not cell.visible:
			continue
		if cell.get_global_rect().grow(_gap * 0.5).has_point(point):
			return index
	return -1
