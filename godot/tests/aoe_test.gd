extends SceneTree

## 보스 범위 공격 — 예고하고, 그 자리에 서고, 시간이 되면 터진다.
## 예고를 보고 원 밖으로 나가면 안 맞아야 한다.
##
## 실제 시간을 1.8초쯤 기다린다 (windup 1600ms 를 진짜로 재기 위해서다 —
## 값을 손으로 밀어 넣으면 정작 타이밍을 검사하지 못한다).
##
##   godot --headless --path godot --script tests/aoe_test.gd

var _failed := 0


func _init() -> void:
	_case_cast_and_burst()
	_case_dodge()
	_case_cooldown()

	if _failed == 0:
		print("범위 공격: 전부 통과")
		quit(0)
	else:
		print("범위 공격: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 마을에 시험용 보스 하나. 초원 보스(boss00)의 실제 값이다
func _setup(player_x: float) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = player_x
	me.z = 0.0
	var mobs: Array = w.snapshot().monsters
	# 초원 보스(boss00) 실제 값으로
	mobs.append(World.make_monster(
		"boss", GameData.monster_kind("boss00"), -20.0, 0.0, 900000.0, 0.0
	))
	return [w, me, mobs[0]]


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


func _case_cast_and_burst() -> void:
	# 원 안(7m)에 들어가면 건다. 보스는 -20, 사람은 -15 -> 5m
	var s := _setup(-15.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var boss: Dictionary = s[2]

	w.step(0.016)
	var cast := _first(w.drain_events(), "aoe")
	if cast.is_empty():
		_fail("7m 안인데 예고하지 않았다")
		return
	if absf(float(cast.radius) - 7.0) > 1e-9 or int(cast.delay_ms) != 1600:
		_fail("예고 값이 다르다 (반지름 %.1f, %dms)" % [cast.radius, cast.delay_ms])
	print("  예고: (%.1f, %.1f) 반지름 %.0f, %dms 뒤" % [cast.x, cast.z, cast.radius, cast.delay_ms])

	# 예고하는 동안 보스는 그 자리에 선다 — 원과 터지는 자리가 어긋나면 못 피한다
	var held := Vector2(boss.x, boss.z)
	OS.delay_msec(200)
	w.step(0.2)
	if Vector2(boss.x, boss.z).distance_to(held) > 1e-6:
		_fail("예고 중에 움직였다")
	if boss.state != "cast":
		_fail("예고 중인데 상태가 %s" % boss.state)
	if me.hp != me.stats.maxHp:
		_fail("아직 안 터져야 하는데 맞았다")

	# 1600ms 가 지나면 터진다. 보스 25 x 2.2 = 55, 기사 Lv1 방어 8 -> 47
	OS.delay_msec(1500)
	w.step(0.016)
	var hit := _first(w.drain_events(), "hit")
	if hit.is_empty():
		_fail("시간이 지났는데 안 터졌다")
	elif int(hit.amount) != 47:
		_fail("범위 피해가 47 이어야 하는데 %d" % hit.amount)
	else:
		print("  터짐: 체력 %d -> %d (피해 %d)" % [me.stats.maxHp, me.hp, hit.amount])


func _case_dodge() -> void:
	# 예고를 보고 원 밖으로 나가면 안 맞는다
	var s := _setup(-15.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.step(0.016)
	if _first(w.drain_events(), "aoe").is_empty():
		_fail("예고가 안 걸려 회피를 못 본다")
		return

	me.x = -11.0  # 보스(-20)에서 9m — 원(7m) 밖
	OS.delay_msec(1700)
	w.step(0.016)
	if not _first(w.drain_events(), "hit").is_empty():
		_fail("원 밖으로 나갔는데 맞았다 (거리 9m, 반지름 7m)")
	elif me.hp != me.stats.maxHp:
		_fail("체력이 줄었다 (%d)" % me.hp)
	else:
		print("  9m 로 피하니 안 맞음 (원 7m)")


func _case_cooldown() -> void:
	# 9초 안에는 다시 안 건다
	var s := _setup(-15.0)
	var w: World = s[0]
	w.step(0.016)
	w.drain_events()
	OS.delay_msec(1700)
	w.step(0.016)
	w.drain_events()  # 터진 것

	for i in 30:
		w.step(0.016)
	if not _first(w.drain_events(), "aoe").is_empty():
		_fail("쿨타임 9초 안인데 또 걸었다")
