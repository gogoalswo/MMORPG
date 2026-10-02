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

	# 클릭 이펙트는 한 번 퍼지고 사라진다. 누르고 있으면 `CLICK_FX_EVERY` 마다 다시 뜬다
	# (2026-10-02 요청: "안 없어지고 계속 보여"). 프레임 시간이 고르지 않아 delta 를 직접 넣는다
	if not game._marker.visible:
		print("  실패: 땅을 눌렀는데 클릭 이펙트가 안 떴다")
		_failed += 1
	game._tick_marker(game.CLICK_FX_LIFE + 0.01)
	if game._marker.visible:
		print("  실패: 클릭 이펙트가 %.1f초가 지나도 안 사라진다" % game.CLICK_FX_LIFE)
		_failed += 1
	# 이펙트 시계와 다음 이펙트까지의 시계는 따로 간다 — 움직임이 크지 않게 delta 는 짧게 주고 남은 시간을 당긴다
	game._send_input(0.1)
	if game._marker.visible:
		print("  실패: 누르고 있는데 %.1f초가 되기 전에 클릭 이펙트가 또 떴다" % game.CLICK_FX_EVERY)
		_failed += 1
	game._marker_next = 0.05
	game._send_input(0.1)
	if not game._marker.visible:
		print("  실패: 누르고 있는데 %.1f초마다 클릭 이펙트가 다시 안 뜬다" % game.CLICK_FX_EVERY)
		_failed += 1

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

	await _edge_tap(game)
	await _surrounded_tap(game)

	if _failed == 0:
		print("터치 이동: 통과")
		quit(0)
	else:
		print("터치 이동: %d개 실패" % _failed)
		quit(1)


## 몬스터에 둘러싸여 못 나가는 데를 누르면 **이동 명령을 버려야 한다** (2026-09-27 — 막힌
## 채 입력을 계속 보내서 자동 사냥이 "사람이 몰고 있다" 로 영영 쉬었고, 캐릭터가 서 있기만 했다)
func _surrounded_tap(game: Node3D) -> void:
	var world = game._transport._world
	var me: Dictionary = world._players[game._transport.my_id()]
	me.x = 0.0
	me.z = 0.0
	var kind: Dictionary = GameData.monster_kind("mob003")
	for i in 12:
		var mob: Dictionary = World.make_monster("ring_%d" % i, kind, 0.0, 0.0, 10000.0, 0.0)
		var at := Vector2.from_angle(TAU * i / 12.0) * (float(mob.r) + Movement.PLAYER_RADIUS + 0.05)
		mob.x = at.x
		mob.z = at.y
		world._monsters.append(mob)
	world.set_auto(game._transport.my_id(), true)
	game._camera.follow(Vector3(me.x, 0, me.z), 0.0, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	game._unhandled_input(press)
	if game._target == Vector3.INF:
		print("  실패: 둘러싸인 채 누른 자리를 바닥 좌표로 못 바꿨다")
		_failed += 1
		return
	# 누른 채로 둬도 버려야 한다 — 누르고 있다고 막힌 발이 풀리지는 않는다
	var start := Time.get_ticks_msec()
	while game._target != Vector3.INF and Time.get_ticks_msec() - start < 3000:
		await process_frame
	if game._target != Vector3.INF:
		print("  실패: 둘러싸여 못 가는데 이동 명령이 안 지워졌다")
		_failed += 1
		return
	var waited := Time.get_ticks_msec() - start
	# 명령을 버렸으면 입력이 끊겨 자동 사냥이 이어받는다
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1000:
		await process_frame
	if Time.get_ticks_msec() < int(me.manual_until) or str(me.auto_target) == "":
		print("  실패: 이동 명령을 버렸는데 자동 사냥이 안 이어받았다")
		_failed += 1
		return
	print("  둘러싸인 채 누름 -> %dms 만에 명령 취소, 자동 사냥이 %s 를 잡음" % [waited, me.auto_target])


func _me(game: Node3D) -> Vector3:
	var players: Dictionary = game._transport.snapshot().get("players", {})
	var me: Dictionary = players.get(game._transport.my_id(), {})
	return Vector3(me.get("x", 0.0), 0, me.get("z", 0.0)) if not me.is_empty() else Vector3.ZERO


## 이동 끝 너머(마을 언덕)를 누르면 끝에 닿아 **멈춰야 한다** (2026-09-26 — 끝에 막힌 채
## 목표가 안 지워져 제자리 뛰기를 했다). 누른 자리가 끝 안으로 당겨지는지와 멈추는지를 본다
func _edge_tap(game: Node3D) -> void:
	var world = game._transport._world
	var me: Dictionary = world._players[game._transport.my_id()]
	me.x = world.half_size - 0.3
	# 카메라가 따라와야 화면 오른쪽 끝이 이동 끝 너머가 된다
	game._camera.follow(Vector3(me.x, 0, me.z), 0.0, true)
	await process_frame
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(root.get_visible_rect().size.x - 40, root.get_visible_rect().size.y * 0.5)
	game._unhandled_input(press)
	# 톡 누르고 뗀다 — 누르고 있으면 목표가 손가락을 따라 계속 옮겨 간다
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = press.position
	game._input(release)
	var raw: Vector3 = game._ground_point(press.position)
	if raw.x <= world.half_size:
		print("  실패: 끝 너머를 못 눌렀다 (%.1f) — 테스트가 엉뚱한 데를 눌렀다" % raw.x)
		_failed += 1
		return
	var target: Vector3 = game._target
	if target == Vector3.INF:
		print("  실패: 끝 너머를 눌렀는데 목표가 없다")
		_failed += 1
		return
	if absf(target.x) > world.half_size or absf(target.z) > world.half_size:
		print("  실패: 목표 (%.1f, %.1f) 가 이동 끝 ±%.0f 밖이다" % [target.x, target.z, world.half_size])
		_failed += 1
	for i in 600:
		if game._target == Vector3.INF:
			break
		await process_frame
	if game._target != Vector3.INF:
		print("  실패: 끝에 막혀 제자리에서 뛴다 — 지금 (%.1f, %.1f)" % [me.x, me.z])
		_failed += 1
