extends SceneTree

## 몬스터가 다가와 때리는지, 사람이 죽고 되살아나는지 본다.
##
## 사냥터를 쓰지 않는다 — 무리가 빽빽해 어느 놈이 관여했는지 가리기 어렵다.
## 몬스터가 없는 마을에 시험용 한 마리만 놓고 본다 (전투 테스트와 같은 방식).
##
##   godot --headless --path godot --script tests/aggro_test.gd

var _failed := 0


func _init() -> void:
	_case_idle()
	_case_chase()
	_case_attack()
	_case_leash()
	_case_death_and_revive()

	if _failed == 0:
		print("어그로: 전부 통과")
		quit(0)
	else:
		print("어그로: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 마을에 시험용 한 마리. 차원문(9,0)에서 멀리 떨어진 자리를 쓴다
func _setup(mob_x: float, mob_z: float, player_x: float, player_z: float) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = player_x
	me.z = player_z
	var mobs: Array = w.snapshot().monsters
	# 들늑대(mob003) 실제 값으로. World 스폰과 같은 함수를 쓴다
	mobs.append(World.make_monster(
		"dummy", GameData.monster_kind("mob003"), mob_x, mob_z, 10000.0, 0.0
	))
	return [w, me, mobs[0]]


func _case_idle() -> void:
	# 어그로(9.1m) 밖이면 쫓지 않는다. **가만히 서 있는 것은 아니다** —
	# 집 주변을 서성인다 (순찰은 tests/patrol_test.gd 가 따로 본다)
	var s := _setup(-20.0, 0.0, -20.0, 15.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	for i in 30:
		w.step(1.0 / 60.0)
	if mob.target != "":
		_fail("어그로 밖인데 대상을 잡았다")
	elif mob.state != "idle" and mob.state != "patrol":
		_fail("어그로 밖인데 상태가 %s" % mob.state)
	elif Vector2(mob.x - mob.home_x, mob.z - mob.home_z).length() > World.PATROL_RADIUS + 0.1:
		_fail("어그로 밖인데 집에서 멀어졌다")


func _case_chase() -> void:
	# 어그로 안이면 다가온다
	var s := _setup(-20.0, 0.0, -20.0, 8.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	var before: float = absf(mob.z - 8.0)
	for i in 60:
		w.step(1.0 / 60.0)
	var after: float = absf(mob.z - 8.0)
	if after >= before:
		_fail("어그로 안인데 안 다가왔다 (%.2f -> %.2f)" % [before, after])
	else:
		print("  1초 쫓아와서 %.2f m -> %.2f m (속도 3.6)" % [before, after])


func _case_attack() -> void:
	# 사거리(1.9m) 안이면 때린다. **한 대가 아주 작은 것이 설계다** — 몬스터
	# 공격력은 "여섯 마리가 동시에 때려 15초에 HP 절반" 에서 역산한 값이라,
	# 1:1 로는 120~150대를 맞아야 죽는다. 무리가 위협이지 한 마리는 아니다
	var s := _setup(-20.0, 0.0, -20.0, 1.5)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var full: int = me.hp
	w.step(1.0 / 60.0)
	var taken := full - int(me.hp)
	if taken <= 0:
		_fail("사거리 안인데 안 때렸다")
	elif taken > full / 10:
		_fail("한 대에 최대 체력의 1/10 이 넘게 날아간다 (%d/%d)" % [taken, full])
	else:
		print("  들늑대에게 %d 맞음 (%d -> %d)" % [taken, full, me.hp])

	# 공격 간격 안에는 한 번만. 휘두르는 동안 묶여 있기도 하다
	var once: int = me.hp
	for i in 30:
		w.step(1.0 / 60.0)
	if me.hp != once:
		_fail("공격 간격 안인데 또 맞았다")


func _case_leash() -> void:
	# 집에서 leash(22.2m) 넘게 벗어나면 쫓기를 포기하고 돌아간다
	var s := _setup(-20.0, 0.0, -20.0, 8.0)
	var w: World = s[0]
	var mob: Dictionary = s[2]
	mob.x = -20.0
	mob.z = 30.0  # 집에서 30m
	w.step(1.0 / 60.0)
	if mob.target != "":
		_fail("줄이 끊겼는데 아직 쫓고 있다")
	if mob.z >= 30.0:
		_fail("집 쪽으로 안 돌아갔다 (z %.2f)" % mob.z)


func _case_death_and_revive() -> void:
	var s := _setup(-20.0, 0.0, -20.0, 1.5)
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.hp = 1
	w.step(1.0 / 60.0)
	if not bool(me.dead):
		_fail("체력 1에서 맞았는데 안 죽었다 (hp %d)" % me.hp)
		return

	# **저절로 살아나지 않는다.** 죽은 걸 읽기도 전에 화면이 사라지면 안 된다
	for i in 120:
		w.step(1.0 / 60.0)
	if not bool(w.snapshot().players["me"].dead):
		_fail("저절로 살아났다")

	# 죽어 있으면 움직이지도 때리지도 못한다
	var held: float = me.x
	w.input_move("me", 99, 1.0, 0.0, 0.1)
	if absf(me.x - held) > 1e-9:
		_fail("죽었는데 움직였다")

	w.revive("me")
	var after: Dictionary = w.snapshot().players["me"]
	if bool(after.dead):
		_fail("되살아나지 않았다")
	elif after.hp != after.stats.maxHp:
		_fail("체력이 안 찼다 (%d/%d)" % [after.hp, after.stats.maxHp])
	elif w.zone_id != GameData.start_zone():
		_fail("마을이 아니라 %s 에서 살아났다" % w.zone_id)
	else:
		print("  죽음 -> 부활: 마을에서 hp %d/%d" % [after.hp, after.stats.maxHp])
