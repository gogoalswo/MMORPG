extends SceneTree

## 몬스터를 눌러 고르면 발밑에 고리가 서는지, 따라다니는지, 놓을 자리에서
## 놓는지 본다.
##
## 스크린샷을 찍지 않는다 — "고리가 섰나 · 발밑에 있나 · 도는가 · 치웠나" 는
## 전부 노드로 읽는다. 눈으로 볼 것은 색과 두께뿐이다.
##
##   godot --headless --path godot --script tests/select_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# 마을에는 몬스터가 없다. 사냥터로 옮겨야 고를 것이 생긴다
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 3:
		await process_frame
	# 고르기만 본다. 맵을 2/3 로 줄인 뒤로(2026-09-23) 도착 지점이 무리의 인식 범위
	# 안이라, 몬스터가 쫓아오며 매 프레임 움직이면 고리 자리 비교가 한 프레임씩 어긋난다
	for m in game._transport.snapshot().get("monsters", []):
		m.aggro = 0.0
		m.target = ""

	var mob := _nearest(game)
	if mob.is_empty():
		_fail("존에 몬스터가 없다 — 고를 자리가 없다")
		_done()
		return

	await _case_pick(game, mob)
	await _case_spin(game)
	await _case_ground(game, mob)
	await _case_death(game, mob)
	await _case_zone(game)
	_done()


## 몬스터를 누르면 그놈이 골라지고, 발밑에 고리가 선다
func _case_pick(game: Node3D, mob: Dictionary) -> void:
	_click(game, Vector3(mob.x, 0.0, mob.z))
	await process_frame

	if game._selected_mob != str(mob.id):
		_fail("몬스터를 눌렀는데 안 골라졌다 (%s)" % game._selected_mob)
		return
	if game._ring == null or not is_instance_valid(game._ring):
		_fail("골랐는데 고리가 안 섰다")
		return

	var gap := Vector2(game._ring.position.x - mob.x, game._ring.position.z - mob.z).length()
	if gap > 0.05:
		_fail("고리가 발밑이 아니다 (%.2f m 떨어져 있다)" % gap)
	if not is_equal_approx(game._ring.position.y, SelectRing.HEIGHT):
		_fail("고리 높이가 %.3f 다 (바닥에 묻히거나 떠 있다)" % game._ring.position.y)

	var torus: TorusMesh = game._ring._ring.mesh
	if torus.outer_radius <= float(mob.r):
		_fail("고리가 몸(%.2f)보다 작다 — 모델에 가려진다" % float(mob.r))
	if torus.outer_radius - torus.inner_radius < 0.1:
		_fail("고리가 너무 얇다 (%.2f m)" % (torus.outer_radius - torus.inner_radius))
	else:
		print("  고리 반지름 %.2f m, 두께 %.2f m (몸 %.2f m)" % [
			torus.outer_radius, torus.outer_radius - torus.inner_radius, float(mob.r)])


## 돈다. 안 돌면 바닥 무늬처럼 보인다
func _case_spin(game: Node3D) -> void:
	if game._ring == null:
		return
	var before: float = game._ring._ring.rotation.y
	for i in 10:
		await process_frame
	if is_equal_approx(game._ring._ring.rotation.y, before):
		_fail("고리가 안 돈다")


## 땅을 눌러도 안 풀린다 — 걸어갈 뿐이고, 고른 놈은 그대로 있다
func _case_ground(game: Node3D, mob: Dictionary) -> void:
	var spot := _empty_spot(game)
	if spot == Vector3.INF:
		_fail("몬스터가 없는 빈 바닥을 못 찾았다")
		return
	_click(game, spot)
	await process_frame

	if game._selected_mob != str(mob.id):
		_fail("땅을 눌렀더니 고른 놈이 풀렸다")
	if game._ring == null or not is_instance_valid(game._ring):
		_fail("땅을 눌렀더니 고리가 사라졌다")
	if game._target_mob != "":
		_fail("땅을 눌렀는데 아직 쫓아간다")
	if game._target == Vector3.INF:
		_fail("땅을 눌렀는데 그쪽으로 안 걸어간다")


## 죽으면 고리를 놓는다. 시체에 남으면 다음에 누를 놈을 가린다
func _case_death(game: Node3D, mob: Dictionary) -> void:
	mob.hp = 0
	await process_frame
	if game._selected_mob != "":
		_fail("죽었는데 아직 골라 둔 채다")
	if game._ring != null:
		_fail("죽었는데 고리가 남았다")


## 존을 옮기면 놓는다. 몬스터 id 는 존마다 다시 매겨진다
func _case_zone(game: Node3D) -> void:
	var mob := _nearest(game)
	if mob.is_empty():
		return
	_click(game, Vector3(mob.x, 0.0, mob.z))
	await process_frame
	if game._selected_mob == "":
		_fail("두 번째 몬스터를 못 골랐다")
		return

	game._transport.send(&"travel", {"zone": "village"})
	for i in 3:
		await process_frame
	if game._selected_mob != "" or game._ring != null:
		_fail("존을 옮겼는데 고른 것이 남았다")


## 그 자리를 누른 것으로 친다. 화면 좌표로 되돌려서 진짜 입력과 같은 길로 넣는다
func _click(game: Node3D, at: Vector3) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = game._camera.unproject_position(at)
	game._unhandled_input(press)


## 나에게 제일 가까운 산 몬스터
func _nearest(game: Node3D) -> Dictionary:
	var snap: Dictionary = game._transport.snapshot()
	var me: Dictionary = snap.get("players", {}).get(game._transport.my_id(), {})
	var best: Dictionary = {}
	var best_gap := INF
	for monster in snap.get("monsters", []):
		if int(monster.hp) <= 0:
			continue
		var gap: float = Vector2(monster.x - me.x, monster.z - me.z).length()
		if gap < best_gap:
			best_gap = gap
			best = monster
	return best


## 몬스터가 없는 바닥 한 자리. 화면 가운데에서 조금씩 옮겨 가며 찾는다
func _empty_spot(game: Node3D) -> Vector3:
	var size: Vector2 = game._camera.get_viewport().get_visible_rect().size
	for step in 12:
		var screen := Vector2(size.x * 0.5, size.y * 0.5) + Vector2(step * 30, step * 20)
		var point: Vector3 = game._ground_point(screen)
		if point != Vector3.INF and game._mob_at(point) == "":
			return point
	return Vector3.INF


func _done() -> void:
	if _failed == 0:
		print("몬스터 선택: 통과")
		quit(0)
	else:
		print("몬스터 선택: %d개 실패" % _failed)
		quit(1)
