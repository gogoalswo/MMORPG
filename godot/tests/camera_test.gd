extends SceneTree

## 쿼터뷰 카메라 — 웹 클라(game/cameraRig.ts)와 같은 값인지 본다.
##
## 각도는 눈으로 보면 "좀 더 위에서" 같은 말밖에 안 나온다. 숫자로 잡아 둔다.
##
##   godot --headless --path godot --script tests/camera_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_values()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _eq(label: String, got: float, want: float, slack: float = 1e-4) -> void:
	if absf(got - want) > slack:
		print("  실패 %s: %.3f 이어야 하는데 %.3f" % [label, want, got])
		_failed += 1


func _case_values() -> void:
	# 각도는 웹 클라와 같아야 한다
	_eq("피치", CameraRig.PITCH, 42.0)
	_eq("요", CameraRig.YAW, PI / 4)
	# 거리만 웹(40)에서 1.5배 당겼다
	_eq("거리", CameraRig.DISTANCE, 40.0 / 1.5, 1e-3)


func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	for i in 30:
		await process_frame

	var cam: CameraRig = game._camera
	_eq("FOV", cam.fov, 30.0)
	_eq("near", cam.near, 1.0)
	_eq("far", cam.far, 400.0)

	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var focus := Vector3(me.x, CameraRig.FOCUS_HEIGHT, me.z)
	var offset := cam.position - focus

	_eq("초점까지 거리", offset.length(), CameraRig.DISTANCE, 0.05)

	# 내려다보는 각 — 수평에서 얼마나 올라가 있나
	var down := rad_to_deg(asin(offset.y / offset.length()))
	_eq("내려다보는 각", down, CameraRig.PITCH, 0.05)

	# 45도에서 본다 = 가로·세로 치우침이 같다
	_eq("요 45도", offset.x, offset.z, 0.05)

	# 좁은 FOV 가 쿼터뷰의 핵심이다. 고도 기본 FOV(75)로 두면 원근이 살아나
	# 지평선까지 보인다 — "멀리까지 보인다" 의 원인이었다
	var visible_h := 2.0 * CameraRig.DISTANCE * tan(deg_to_rad(cam.fov) / 2.0)
	if absf(visible_h - 14.3) > 0.3:
		_fail("화면 세로가 14.3m 여야 하는데 %.1fm" % visible_h)
	else:
		print("  카메라: 내려보기 %.0f도 · 거리 %.0fm · FOV %.0f -> 화면 세로 %.1fm" % [
			down, offset.length(), cam.fov, visible_h
		])

	# 각도가 바뀌어도 눌러서 걸어가는 것은 그대로여야 한다
	var before := Vector2(me.x, me.z)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 260)
	game._unhandled_input(press)
	for i in 60:
		await process_frame
	var moved := Vector2(me.x, me.z).distance_to(before)
	if moved < 0.3:
		_fail("새 각도에서 눌렀는데 안 움직였다 (%.2f m)" % moved)
	else:
		print("  눌러서 %.2f m 이동 — 각도가 바뀌어도 그대로다" % moved)

	Save.clear()
	if _failed == 0:
		print("카메라: 전부 통과")
		quit(0)
	else:
		print("카메라: %d개 실패" % _failed)
		quit(1)
