extends SceneTree

## 자동 사냥을 본다 (World.set_auto / _drive_auto / _pick_hunt_target).
##
## **가장 중요한 것은 반경이다.** 사냥터의 한 무리가 통째로 들어오고 옆 무리는
## 안 끌려오는지를 진짜 존 데이터(meadow)로 잰다 — 무리 배치가 바뀌면 여기서 깨진다.
##
## 시각은 진짜 시계(Time.get_ticks_msec)에서 온다. 헤드리스로 프레임만 돌리면
## 공격 간격(700ms)은 지나가지 않으므로 **한 대 때리는 것까지만** 본다.
##
##   godot --headless --path godot --script tests/auto_hunt_test.gd

var _failed := 0


func _init() -> void:
	_case_radius_covers_one_pack()
	_case_anchor_on_toggle()
	_case_walks_in_and_hits()
	_case_back_to_anchor()
	_case_outside_radius()
	_case_off_stops()
	_case_dead()
	_case_anchor_move()

	if _failed == 0:
		print("자동 사냥: 전부 통과")
		quit(0)
	else:
		print("자동 사냥: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 마을(몬스터가 없는 곳)에 시험용 한 마리를 놓는다. 사냥터에서 하면 근처의
## 다른 놈이 먼저 걸려 무엇을 보고 있는지 알 수 없다
func _setup(mob_x: float, mob_z: float) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = 0.0
	me.z = 0.0
	var mobs: Array = w.snapshot().monsters
	mobs.append(World.make_monster(
		"dummy", GameData.monster_kind("mob003"), mob_x, mob_z, 10000.0, 0.0
	))
	return [w, me, mobs[0]]


func _gap(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 사냥터 무리는 반지름 8m 원에 흩어져 있고 무리끼리 40m 떨어져 있다.
## 무리 안 **어디에 서서 켜도** 그 무리가 다 들어오고, 옆 무리는 한 마리도
## 안 들어와야 한다
func _case_radius_covers_one_pack() -> void:
	var w := World.new()
	w.open("meadow")
	# 보스는 다른 무리 옆에 혼자 서 있어 무리로 치지 않는다 (id 로 가른다)
	var packs := {}
	for mob in w.snapshot().monsters:
		if str(mob.id).begins_with("boss"):
			continue
		var key := "%s%s" % ["n" if mob.home_x < 0 else "p", "n" if mob.home_z < 0 else "p"]
		if not packs.has(key):
			packs[key] = []
		packs[key].append(mob)

	if packs.size() != 4:
		_fail("초원 무리를 %d 개로 봤다 (4 이어야 한다)" % packs.size())
		return

	var widest := 0.0
	for key in packs:
		for a in packs[key]:
			for b in packs[key]:
				widest = maxf(widest, _gap(a, b))
	if widest > World.HUNT_RADIUS:
		_fail("한 무리의 양 끝이 %.1f m — 반경 %.1f 로는 다 못 덮는다" % [
			widest, World.HUNT_RADIUS
		])
	else:
		print("  한 무리 양 끝 %.1f m < 반경 %.1f m — 통째로 들어온다" % [
			widest, World.HUNT_RADIUS
		])

	# 무리 안 어느 자리에 앵커를 잡아도 옆 무리는 안 걸린다
	var nearest_other := INF
	for key in packs:
		for anchor in packs[key]:
			for other in packs:
				if other == key:
					continue
				for mob in packs[other]:
					nearest_other = minf(nearest_other, _gap(anchor, mob))
	if nearest_other <= World.HUNT_RADIUS:
		_fail("옆 무리가 %.1f m 까지 붙어 있다 — 반경 %.1f 안에 들어온다" % [
			nearest_other, World.HUNT_RADIUS
		])
	else:
		print("  옆 무리는 최소 %.1f m — 반경 밖이다" % nearest_other)


## 켜면 **그 자리**가 앵커다. 앵커가 없으면 몬스터를 따라 맵 끝까지 끌려간다
func _case_anchor_on_toggle() -> void:
	var s := _setup(30.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.x = 7.0
	me.z = -3.0
	w.set_auto("me", true)
	if absf(float(me.auto_x) - 7.0) > 1e-6 or absf(float(me.auto_z) + 3.0) > 1e-6:
		_fail("앵커를 켠 자리(7, -3)가 아니라 (%.1f, %.1f) 에 잡았다" % [me.auto_x, me.auto_z])


## 반경 안의 놈에게 걸어가 사거리 안에서 친다
func _case_walks_in_and_hits() -> void:
	var s := _setup(10.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	var full := int(mob.hp)
	w.set_auto("me", true)

	var frames := 0
	for i in 600:
		w.step(1.0 / 60.0)
		frames += 1
		if int(mob.hp) < full:
			break

	var gap := _gap(me, mob)
	if int(mob.hp) >= full:
		_fail("%d 프레임을 돌려도 한 대도 못 쳤다 (거리 %.2f m)" % [frames, gap])
	elif gap > float(me.stats.attackRange) + 1e-3:
		_fail("사거리(%.1f) 밖 %.2f m 에서 맞췄다" % [me.stats.attackRange, gap])
	else:
		print("  10m 밖에서 %d 프레임에 붙어(%.2f m) 첫 대를 넣었다" % [frames, gap])

	if str(me.auto_target) != "dummy":
		_fail("대상을 안 잡았다 (%s)" % me.auto_target)


## 대상이 없으면 앵커로 돌아가 기다린다. 안 돌아가면 마지막으로 쫓던 자리에
## 눌러앉아 무리 밖에 서 있게 된다
func _case_back_to_anchor() -> void:
	var s := _setup(60.0, 60.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)
	me.x = 12.0
	me.z = 0.0

	for i in 300:
		w.step(1.0 / 60.0)
	var gap := Vector2(me.x - float(me.auto_x), me.z - float(me.auto_z)).length()
	if gap > World.HUNT_ARRIVE + 1e-3:
		_fail("앵커로 안 돌아왔다 (남은 거리 %.2f m)" % gap)
	else:
		print("  대상이 없자 앵커로 돌아와 섰다 (%.2f m)" % gap)


## 반경 밖의 놈은 안 잡는다 — 잡으면 앵커를 둔 뜻이 없다
func _case_outside_radius() -> void:
	var s := _setup(World.HUNT_RADIUS + 3.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	w.set_auto("me", true)

	for i in 300:
		w.step(1.0 / 60.0)
	if str(me.auto_target) != "":
		_fail("반경 밖(%.1f m)의 놈을 잡았다" % _gap(me, mob))
	if Vector2(me.x, me.z).length() > World.HUNT_ARRIVE + 1e-3:
		_fail("반경 밖의 놈에게 걸어갔다 (%.2f, %.2f)" % [me.x, me.z])


## 끄면 그 자리에 선다
func _case_off_stops() -> void:
	var s := _setup(10.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)
	for i in 30:
		w.step(1.0 / 60.0)
	w.set_auto("me", false)

	var before := Vector2(me.x, me.z)
	for i in 120:
		w.step(1.0 / 60.0)
	if Vector2(me.x, me.z).distance_to(before) > 1e-6:
		_fail("껐는데 움직였다")
	if str(me.auto_target) != "":
		_fail("껐는데 대상이 남아 있다")


## 죽어 있으면 아무것도 안 한다. 시체가 걸어가면 안 된다
func _case_dead() -> void:
	var s := _setup(10.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)
	me.dead = true

	var before := Vector2(me.x, me.z)
	for i in 120:
		w.step(1.0 / 60.0)
	if Vector2(me.x, me.z).distance_to(before) > 1e-6:
		_fail("죽었는데 움직였다")


## 땅을 누르면 사냥할 자리가 옮겨진다. **꺼져 있으면 안 듣는다** —
## 남겨 두면 다음에 켤 때 엉뚱한 데로 걷는다
func _case_anchor_move() -> void:
	var s := _setup(60.0, 60.0)
	var w: World = s[0]
	var me: Dictionary = s[1]

	w.set_hunt_anchor("me", 9.0, 9.0)
	if absf(float(me.auto_x)) > 1e-6 or absf(float(me.auto_z)) > 1e-6:
		_fail("꺼져 있는데 앵커가 옮겨졌다")

	w.set_auto("me", true)
	w.set_hunt_anchor("me", 9.0, 9.0)
	if absf(float(me.auto_x) - 9.0) > 1e-6:
		_fail("앵커가 안 옮겨졌다 (%.1f, %.1f)" % [me.auto_x, me.auto_z])

	for i in 300:
		w.step(1.0 / 60.0)
	var gap := Vector2(me.x - 9.0, me.z - 9.0).length()
	if gap > World.HUNT_ARRIVE + 1e-3:
		_fail("옮긴 자리로 안 걸어갔다 (남은 거리 %.2f m)" % gap)
	else:
		print("  누른 자리로 걸어가 섰다 (%.2f m)" % gap)
