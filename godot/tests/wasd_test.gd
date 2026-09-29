extends SceneTree

## WASD 로 걷는지 본다. W 는 화면 위쪽(카메라가 보는 쪽)이고, 떼면 멈추며,
## 채팅 칸에 글을 쓰는 중에는 움직이지 않는다.
##
##   godot --headless --path godot --script tests/wasd_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# W — 카메라가 보는 쪽으로 간다
	var before := _me(game)
	_key(KEY_W, true)
	for i in 60:
		await process_frame
	_key(KEY_W, false)
	var after := _me(game)
	var moved := Vector2(after.x - before.x, after.z - before.z)
	var basis: Basis = game._camera.global_transform.basis
	var fwd := Vector2(-basis.z.x, -basis.z.z).normalized()
	if moved.length() < 0.5:
		print("  실패: W 를 눌렀는데 안 움직였다 (%.3f m)" % moved.length())
		_failed += 1
	elif moved.normalized().dot(fwd) < 0.9:
		print("  실패: W 가 화면 위쪽이 아니다 (간 쪽 %s, 카메라 앞 %s)" % [moved.normalized(), fwd])
		_failed += 1
	else:
		print("  W 1초 동안 %.2f m, 카메라 앞과 %.2f" % [moved.length(), moved.normalized().dot(fwd)])

	# 떼면 멈춘다
	for i in 10:
		await process_frame
	var still := _me(game)
	for i in 30:
		await process_frame
	if Vector2(_me(game).x - still.x, _me(game).z - still.z).length() > 0.05:
		print("  실패: W 를 뗐는데 계속 걷는다")
		_failed += 1

	# D — 화면 오른쪽
	before = _me(game)
	_key(KEY_D, true)
	for i in 60:
		await process_frame
	_key(KEY_D, false)
	moved = Vector2(_me(game).x - before.x, _me(game).z - before.z)
	var side := Vector2(basis.x.x, basis.x.z).normalized()
	if moved.length() < 0.5 or moved.normalized().dot(side) < 0.9:
		print("  실패: D 가 화면 오른쪽이 아니다 (%.2f m, %s)" % [moved.length(), moved.normalized()])
		_failed += 1

	# 땅을 눌러 걷던 중에 키를 잡으면 목표를 내려놓는다
	game._set_target(_me(game) + Vector3(5, 0, 0))
	_key(KEY_S, true)
	await process_frame
	await process_frame
	_key(KEY_S, false)
	if game._target != Vector3.INF:
		print("  실패: 키로 걸었는데 눌러 둔 목표가 남았다")
		_failed += 1

	# 채팅 칸에 쓰는 중이면 안 움직인다
	for i in 10:
		await process_frame
	var typing := LineEdit.new()
	game.add_child(typing)
	typing.grab_focus()
	before = _me(game)
	_key(KEY_W, true)
	for i in 30:
		await process_frame
	_key(KEY_W, false)
	if Vector2(_me(game).x - before.x, _me(game).z - before.z).length() > 0.05:
		print("  실패: 채팅 칸에 쓰는 중인데 걸었다")
		_failed += 1

	if _failed == 0:
		print("WASD 이동: 통과")
		quit(0)
	else:
		print("WASD 이동: 실패 %d" % _failed)
		quit(1)


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _me(game: Node3D) -> Vector3:
	var players: Dictionary = game._transport.snapshot().get("players", {})
	var me: Dictionary = players.get(game._transport.my_id(), {})
	return Vector3(me.get("x", 0.0), 0, me.get("z", 0.0)) if not me.is_empty() else Vector3.ZERO
