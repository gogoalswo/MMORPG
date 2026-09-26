extends SceneTree

## 화면을 눌렀을 때 실제로 그쪽으로 걸어가는지 본다.
## 눌린 자리를 바닥 좌표로 바꾸는 계산(_ground_point)이 이 단계에서 제일
## 틀리기 쉬운 자리라, 폰에서 눈으로 보기 전에 글로 먼저 확인한다.
##
##   godot --headless --path godot --script tests/touch_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	var before := _me(game)

	# 화면 왼쪽 위를 누른다 — 카메라가 뒤 위에서 보므로 캐릭터보다 먼 쪽이다
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	game._unhandled_input(press)

	var target: Vector3 = game._target
	if target == Vector3.INF:
		print("  실패: 누른 자리를 바닥 좌표로 못 바꿨다")
		_failed += 1
	else:
		print("  누른 자리 -> 바닥 (%.1f, %.1f)" % [target.x, target.z])

	for i in 90:
		await process_frame

	var after := _me(game)
	var moved := Vector2(after.x - before.x, after.z - before.z).length()
	if moved < 0.5:
		print("  실패: 눌렀는데 안 움직였다 (%.3f m)" % moved)
		_failed += 1
	else:
		print("  1.5초 동안 %.2f m 이동, 지금 (%.1f, %.1f)" % [moved, after.x, after.z])

	# 누른 채로 끌면 목표가 손가락을 따라온다 (2026-09-26 요청: "누른 지점만 움직여")
	if not game._holding:
		print("  실패: 땅을 누르고 있는데 누르는 중으로 안 잡혔다")
		_failed += 1
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(600, 200)
	game._input(drag)
	await process_frame
	var dragged: Vector3 = game._target
	if dragged == Vector3.INF or Vector2(dragged.x - target.x, dragged.z - target.z).length() < 0.5:
		print("  실패: 끌었는데 목표가 안 따라왔다")
		_failed += 1

	# 떼면 더는 다시 잡지 않는다
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = drag.position
	game._input(release)
	var left_at: Vector3 = game._target
	drag.position = Vector2(200, 200)
	game._input(drag)
	await process_frame
	if game._holding or (left_at != Vector3.INF and game._target != Vector3.INF and game._target != left_at):
		print("  실패: 뗐는데 목표가 계속 따라온다")
		_failed += 1

	if _failed == 0:
		print("터치 이동: 통과")
		quit(0)
	else:
		print("터치 이동: %d개 실패" % _failed)
		quit(1)


func _me(game: Node3D) -> Vector3:
	var players: Dictionary = game._transport.snapshot().get("players", {})
	var me: Dictionary = players.get(game._transport.my_id(), {})
	return Vector3(me.get("x", 0.0), 0, me.get("z", 0.0)) if not me.is_empty() else Vector3.ZERO
