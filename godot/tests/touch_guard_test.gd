extends SceneTree

## 폰에서 손가락 떼기를 한 번 놓치면 그 뒤 누름이 전부 죽던 것 (2026-09-27 — 몬스터가
## 몰린 채 "어떤것도 클릭이 안돼"). 고도의 터치→마우스 흉내는 **떼기를 받은 손가락만**
## 놓아 주는데 웹판은 놓친 걸 풀지 않는다. `TouchGuard` 가 풀어 주는지 **진짜 입력 길**
## (`Input.parse_input_event` → 흉내 → GUI)로 본다. `push_input` 은 흉내를 안 거쳐서 못 잡는다.
##
##   godot --headless --path godot --script tests/touch_guard_test.gd

var _failed := 0
var _presses := 0


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame
	# 자동사냥 칸 — 누르면 켜고 끄기만 해서 창이 떠 단추를 가리는 일이 없다
	var button: Button = game._auto_cell.get_node("hit")
	button.pressed.connect(func() -> void: _presses += 1)
	# 폰의 손가락은 **창 좌표**로 온다 — 늘이기 배율을 걸어 화면(캔버스) 자리를 창 자리로 바꾼다
	var to_window := root.get_final_transform()
	var on_button := to_window * button.get_global_rect().get_center()
	# 땅 — 화면 위쪽 가운데 (단추가 없는 자리)
	var ground := to_window * Vector2(root.get_visible_rect().size.x * 0.5, root.get_visible_rect().size.y * 0.3)
	var far_ground := to_window * Vector2(root.get_visible_rect().size.x * 0.3, root.get_visible_rect().size.y * 0.4)

	# 평소 — 한 손가락으로 누르고 떼면 단추가 눌린다
	await _touch(0, on_button, true)
	await _touch(0, on_button, false)
	if _presses != 1:
		print("  실패: 평소에 단추를 눌렀는데 안 눌렸다 (%d번)" % _presses)
		_failed += 1

	# 걸으며(땅을 누른 채) 다른 손가락으로 단추를 누른다 — 단추는 눌리고 **걷기는 계속**이다.
	# 이때 풀면 안 된다 (두 손가락 조작)
	await _touch(1, ground, true)
	if not game._holding:
		print("  실패: 땅을 누르고 있는데 누르는 중으로 안 잡혔다")
		_failed += 1
	await _touch(2, on_button, true)
	await _touch(2, on_button, false)
	if _presses != 2:
		print("  실패: 걸으며 누른 단추가 안 눌렸다 (%d번)" % _presses)
		_failed += 1
	if not game._holding or game._touch_guard.rescued != 0:
		print("  실패: 단추를 눌렀더니 걷던 손가락이 풀렸다 (풂 %d)" % game._touch_guard.rescued)
		_failed += 1

	# 이제 땅을 누르던 손가락의 **떼기를 놓쳤다** 치고(1번은 안 뗀다) 다른 손가락으로 땅을
	# 누른다. 고치기 전에는 여기서 땅·몬스터 누르기가 새로고침 전까지 전부 죽었다
	game._target = Vector3.INF
	await _touch(3, far_ground, true)
	if game._touch_guard.rescued != 1:
		print("  실패: 떼기를 놓친 뒤 땅을 눌렀는데 안 풀었다 (풂 %d)" % game._touch_guard.rescued)
		_failed += 1
	if game._target == Vector3.INF:
		print("  실패: 떼기를 놓친 뒤 땅을 누르니 안 간다 — 폰에서 전부 죽는 그 상태")
		_failed += 1
	await _touch(3, far_ground, false)
	if game._holding:
		print("  실패: 손을 다 뗐는데 계속 걷는다")
		_failed += 1

	# 풀린 뒤로는 평소대로 — 다시 막히지 않는다
	await _touch(4, on_button, true)
	await _touch(4, on_button, false)
	game._target = Vector3.INF
	await _touch(5, ground, true)
	await _touch(5, ground, false)
	if _presses != 3 or game._target == Vector3.INF or game._touch_guard.rescued != 1:
		print("  실패: 풀린 뒤 누름이 이상하다 (눌림 %d · 풂 %d)" % [_presses, game._touch_guard.rescued])
		_failed += 1

	if _failed == 0:
		print("떼기 놓친 손가락 풀기: 통과")
		quit(0)
	else:
		print("떼기 놓친 손가락 풀기: %d개 실패" % _failed)
		quit(1)


## 폰이 보내는 것과 같은 손가락 이벤트를 넣고, 고도가 흘려보낼 때까지 두 프레임 기다린다
## (지킴이가 다시 넣은 것은 다음 프레임에 흐른다)
func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	Input.flush_buffered_events()
	await process_frame
