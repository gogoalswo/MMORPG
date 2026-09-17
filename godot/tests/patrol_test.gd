extends SceneTree

## 쫓을 사람이 없는 몬스터가 집 주변을 서성이는지 본다 (World._patrol).
##
## **시각은 진짜 시계(Time.get_ticks_msec)에서 온다.** 헤드리스로 프레임만 돌려도
## 쉬는 시간(2~6초)은 지나가지 않는다 — 그래서 쉬는 시각을 직접 0 으로 밀어
## "쉬는 것이 끝났다"를 만든다 (어그로 테스트가 자리를 직접 옮기는 것과 같은 방식).
##
##   godot --headless --path godot --script tests/patrol_test.gd

var _failed := 0


func _init() -> void:
	_case_pick_and_rest()
	_case_walk()
	_case_inside_radius()
	_case_aggro_wins()
	_case_far_from_home()
	_case_dead()
	_case_stagger()

	if _failed == 0:
		print("순찰: 전부 통과")
		quit(0)
	else:
		print("순찰: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 마을에 시험용 한 마리. 사람은 어그로(9.1m) 밖에 세워 둔다 —
## 순찰로 4m 까지 다가와도 아직 밖이다
func _setup(mob_x: float, mob_z: float, player_z: float = 15.0) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = -20.0
	me.z = player_z
	var mobs: Array = w.snapshot().monsters
	mobs.append(World.make_monster(
		"dummy", GameData.monster_kind("mob003"), mob_x, mob_z, 10000.0, 0.0
	))
	return [w, me, mobs[0]]


func _home_gap(mob: Dictionary) -> float:
	return Vector2(mob.x - mob.home_x, mob.z - mob.home_z).length()


## 쉬는 시간을 끝내 준다. 안 그러면 진짜 시계가 흐를 때까지 한 발도 안 뗀다
func _wake(mob: Dictionary) -> void:
	mob.patrol_rest_until = 0


func _case_pick_and_rest() -> void:
	# 첫 판정에서 목적지를 뽑고 잠시 쉰다 (선 채로 굳어 있지 않다)
	var s := _setup(-20.0, 0.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	w.step(1.0 / 60.0)

	if int(mob.patrol_rest_until) <= 0:
		_fail("쉬는 시각을 안 잡았다")
	if mob.state != "idle":
		_fail("쉬는 동안은 idle 이어야 하는데 %s" % mob.state)

	var reach := Vector2(float(mob.patrol_x) - mob.home_x, float(mob.patrol_z) - mob.home_z).length()
	if reach < World.PATROL_RADIUS * 0.4 - 1e-3 or reach > World.PATROL_RADIUS + 1e-3:
		_fail("목적지가 집에서 %.2f m — 1.6~4.0 m 이어야 한다" % reach)
	else:
		print("  목적지를 집에서 %.2f m 에 뽑고 쉰다" % reach)

	# 쉬는 동안은 제자리다
	var before := Vector2(mob.x, mob.z)
	for i in 30:
		w.step(1.0 / 60.0)
	if Vector2(mob.x, mob.z).distance_to(before) > 1e-6:
		_fail("쉬는 동안 움직였다")


func _case_walk() -> void:
	# 쉬는 것이 끝나면 목적지까지 걸어가고, 닿으면 다음 자리를 뽑는다
	var s := _setup(-20.0, 0.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	w.step(1.0 / 60.0)
	var goal := Vector2(float(mob.patrol_x), float(mob.patrol_z))
	_wake(mob)

	w.step(1.0 / 60.0)
	if mob.state != "patrol":
		_fail("걷는 동안 상태가 %s" % mob.state)

	# 들늑대 3.6 m/s 의 0.35 배 -> 1.26 m/s. 4m 를 걷는 데 넉넉한 프레임을 준다
	var walked := 0
	for i in 400:
		if int(mob.patrol_rest_until) > 0:
			break
		w.step(1.0 / 60.0)
		walked += 1

	if int(mob.patrol_rest_until) <= 0:
		_fail("목적지에 못 닿았다 (남은 거리 %.2f m)" % Vector2(mob.x, mob.z).distance_to(goal))
	elif Vector2(mob.x, mob.z).distance_to(goal) > World.PATROL_ARRIVE:
		_fail("닿지도 않고 다음 자리를 뽑았다")
	else:
		print("  %.2f m 를 %d 프레임에 걸어가 닿고 다시 쉰다" % [
			goal.distance_to(Vector2(-20.0, 0.0)), walked
		])


func _case_inside_radius() -> void:
	# 여러 다리를 걸어도 집 반경(4m) 안이다. 순찰이 어그로 범위를 넘어가면
	# "가만히 있었는데 몬스터가 찾아왔다" 가 된다
	var s := _setup(-20.0, 0.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	var worst := 0.0
	for i in 2000:
		_wake(mob)
		w.step(1.0 / 60.0)
		worst = maxf(worst, _home_gap(mob))
	if worst > World.PATROL_RADIUS + 0.1:
		_fail("집에서 %.2f m 까지 벗어났다" % worst)
	else:
		print("  10여 다리를 걸어도 집에서 최대 %.2f m" % worst)


func _case_aggro_wins() -> void:
	# 순찰 중에 사람이 어그로 안으로 들어오면 곧바로 쫓는다 (순찰이 막지 않는다)
	var s := _setup(-20.0, 0.0, 8.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	_wake(mob)
	w.step(1.0 / 60.0)
	if mob.state != "chase":
		_fail("어그로 안인데 상태가 %s" % mob.state)
	if mob.target != "me":
		_fail("어그로 안인데 대상을 안 잡았다")


func _case_far_from_home() -> void:
	# 쫓다가 대상을 잃고 멀리 나와 있으면 집 쪽으로 걸어 돌아온다
	var s := _setup(-20.0, 0.0, 40.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	# 집에서 8m — leash(22m) 안이고 순찰 반경(4m) 밖이다.
	# 사람은 _setup 에서 40m 로 밀어 뒀다 (어그로 안이면 돌아오지 않고 쫓는 게 맞다)
	mob.z = 8.0
	var before := _home_gap(mob)
	for i in 30:
		w.step(1.0 / 60.0)
	if _home_gap(mob) >= before:
		_fail("집 쪽으로 안 돌아왔다 (%.2f -> %.2f)" % [before, _home_gap(mob)])
	elif mob.state != "patrol":
		_fail("돌아오는 중인데 상태가 %s" % mob.state)


func _case_dead() -> void:
	# 죽은 놈은 서성이지 않는다
	var s := _setup(-20.0, 0.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	mob.hp = 0
	mob.respawn_at = 0
	var before := Vector2(mob.x, mob.z)
	for i in 60:
		_wake(mob)
		w.step(1.0 / 60.0)
	if Vector2(mob.x, mob.z).distance_to(before) > 1e-6:
		_fail("죽었는데 움직였다")


func _case_stagger() -> void:
	# 무리가 한 몸처럼 움직이지 않는다 — 쉬는 시각을 놈마다 다르게 뽑는다
	var w := World.new()
	w.open("meadow")
	w.join("me")
	w.step(1.0 / 60.0)
	var rests := {}
	var counted := 0
	for mob in w.snapshot().monsters:
		if int(mob.hp) <= 0 or mob.state != "idle":
			continue
		rests[int(mob.patrol_rest_until)] = true
		counted += 1
	if counted < 5:
		_fail("사냥터에 쉬는 몬스터가 %d 마리뿐이다" % counted)
	elif rests.size() < counted / 2:
		_fail("%d 마리가 쉬는 시각을 %d 가지로만 뽑았다" % [counted, rests.size()])
	else:
		print("  사냥터 %d 마리가 %d 가지 시각으로 흩어져 쉰다" % [counted, rests.size()])
