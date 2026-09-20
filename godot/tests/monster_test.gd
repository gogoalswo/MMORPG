extends SceneTree

## 몬스터 스폰·충돌·차원문을 글로 확인한다.
##
##   godot --headless --path godot --script tests/monster_test.gd

var _failed := 0


func _init() -> void:
	_case_village_empty()
	_case_meadow_count()
	_case_no_overlap()
	_case_same_seed()
	_case_block()
	_case_corpse_passable()
	_case_gate()

	if _failed == 0:
		print("몬스터: 전부 통과")
		quit(0)
	else:
		print("몬스터: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _world(zone_id: String) -> World:
	var w := World.new()
	w.open(zone_id)
	w.join("me")
	return w


func _mobs(w: World) -> Array:
	return w.snapshot().get("monsters", [])


func _case_village_empty() -> void:
	# 마을에는 무리 정의가 없다
	var count := _mobs(_world("village")).size()
	if count != 0:
		_fail("마을에 몬스터가 %d마리 있다" % count)


func _case_meadow_count() -> void:
	# 보스 1 + 무리 4개 x 50 (밸런스 설계의 "한 그룹 50마리")
	var count := _mobs(_world("meadow")).size()
	if count != 201:
		_fail("초원 몬스터가 201이어야 하는데 %d" % count)


func _case_no_overlap() -> void:
	# 겹친 채로 서 있으면 그게 그대로 화면에 남는다
	var mobs := _mobs(_world("meadow"))
	var worst := INF
	for i in mobs.size():
		for j in range(i + 1, mobs.size()):
			var a: Dictionary = mobs[i]
			var b: Dictionary = mobs[j]
			var gap: float = Vector2(a.x - b.x, a.z - b.z).length() - (a.r + b.r)
			worst = minf(worst, gap)
	if worst < -0.001:
		_fail("가장 심하게 겹친 둘이 %.3f m 파고들었다" % worst)
	else:
		print("  가장 가까운 둘 사이 여유 %.3f m" % worst)


func _case_same_seed() -> void:
	# 자리를 정하는 건 언제나 판정하는 쪽이다 — 같은 존이면 같은 자리
	var a := _mobs(_world("meadow"))
	var b := _mobs(_world("meadow"))
	for i in a.size():
		if absf(a[i].x - b[i].x) > 1e-9 or absf(a[i].z - b[i].z) > 1e-9:
			_fail("두 번 열었더니 %d번째 자리가 다르다" % i)
			return


func _case_block() -> void:
	# 몬스터를 뚫고 지나갈 수 없다
	var w := _world("meadow")
	var mob: Dictionary = _mobs(w)[0]
	var players: Dictionary = w.snapshot().players
	var me: Dictionary = players["me"]
	# 몬스터 바로 옆에 세우고 몬스터 쪽으로 계속 민다
	me.x = mob.x - 2.0
	me.z = mob.z
	for i in 200:
		w.input_move("me", i + 1, 1.0, 0.0, 0.05)
	var gap: float = Vector2(me.x - mob.x, me.z - mob.z).length()
	var minimum: float = mob.r + Movement.PLAYER_RADIUS
	if gap < minimum - 0.001:
		_fail("몬스터 안으로 %.3f m 들어갔다" % (minimum - gap))
	else:
		print("  몬스터 앞에서 %.3f m 남기고 막혔다 (최소 %.3f)" % [gap, minimum])


func _case_corpse_passable() -> void:
	# **죽은 놈은 지나간다.** 화면에서 사라진 시체가 벽으로 남으면
	# "몬스터한테 막힌 것도 아닌데 안 가진다" 가 된다
	# (docs/features/collision.md 의 "죽은 것은 지나간다")
	var w := _world("meadow")
	var mob: Dictionary = _mobs(w)[0]
	mob.hp = 0
	var me: Dictionary = w.snapshot().players["me"]
	me.x = mob.x - 2.0
	me.z = mob.z
	for i in 200:
		w.input_move("me", i + 1, 1.0, 0.0, 0.05)
	if me.x <= mob.x + 0.5:
		_fail("시체에 막혔다 — 시체 x=%.2f 인데 나는 x=%.2f 에 섰다" % [mob.x, me.x])
	else:
		print("  시체를 %.2f m 지나쳤다" % (me.x - mob.x))


func _case_gate() -> void:
	# 차원문은 **고르라고 알리기만 한다.** 어디로 갈지는 사람이 고른다
	var w := _world("village")
	var gate_pos: Array = w.zone.gate.position
	var me: Dictionary = w.snapshot().players["me"]
	me.x = float(gate_pos[0])
	me.z = float(gate_pos[1])
	w.step(0.016)
	if w.zone_id != "village":
		_fail("고르기도 전에 존이 %s 로 바뀌었다" % w.zone_id)
	var told := false
	for e in w.drain_events():
		if e.get("type", "") == "gate":
			told = true
	if not told:
		_fail("차원문에 섰는데 알려 주지 않았다")

	# 문을 벗어나지 않으면 다시 알리지 않는다 (매 프레임 뜨면 깜빡인다)
	w.step(0.016)
	for e in w.drain_events():
		if e.get("type", "") == "gate":
			_fail("문 안에 서 있는데 또 알렸다")

	# 고른 곳으로 옮긴다
	w.travel("me", "meadow")
	if w.zone_id != "meadow":
		_fail("고른 곳으로 안 갔다 (%s)" % w.zone_id)
	elif _mobs(w).size() != 201:
		_fail("옮긴 존에 몬스터가 안 났다")
	else:
		print("  차원문 알림 -> 골라서 %s, 몬스터 %d마리" % [w.zone_id, _mobs(w).size()])

	# 없는 존은 거절한다 — 화면이 보내는 건 요청이다
	w.travel("me", "없는곳")
	if w.zone_id != "meadow":
		_fail("없는 존으로 옮겨졌다")
