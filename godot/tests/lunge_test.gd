extends SceneTree

## 날라차기를 본다 (World._lunge / _run_lunges — 2026-09-29 요청).
## 평타 대상이 `LUNGE_MIN` 보다 멀고 `LUNGE_MAX` 안이면 달려가지 않고 날아 차며 붙는다.
##
## 나는 시간은 벽시계가 아니라 `step` 의 시간으로 끝난다 — 여기서 프레임만 돌려도 끝까지 간다.
##
##   godot --headless --path godot --script tests/lunge_test.gd

var _failed := 0


func _init() -> void:
	_case_flies_and_kicks()
	_case_follows_target()
	_case_near_walks()
	_case_too_far()
	_case_ranged_stays()
	_case_auto_lunges()
	_case_skill_out_of_reach()
	_case_skill_in_reach()

	if _failed == 0:
		print("날라차기: 전부 통과")
		quit(0)
	else:
		print("날라차기: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 마을에 시험용 한 마리 — auto_hunt_test 와 같다. 스킬은 빼 둔다(평타만 본다)
func _setup(mob_x: float, mob_z: float) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = 0.0
	me.z = 0.0
	me.skills = []
	me.skill_bar = []
	var mobs: Array = w.snapshot().monsters
	mobs.append(World.make_monster(
		"dummy", GameData.monster_kind("mob003"), mob_x, mob_z, 10000.0, 0.0
	))
	# 몬스터가 움직이지 않게 — 도착점을 재는 데 방해된다 (따라가는 건 따로 본다)
	mobs[0].speed = 0.0
	return [w, me, mobs[0]]


func _gap(me: Dictionary, mob: Dictionary) -> float:
	return Vector2(float(mob.x) - me.x, float(mob.z) - me.z).length()


## 7m 밖을 눌러 치면(끈 사람) 날아서 붙고, 닿는 순간 한 대 맞는다. 나는 동안 발이 묶여 있고
## 앞으로만 간다. 달리기(4.6m/s)보다 한참 빠르다
func _case_flies_and_kicks() -> void:
	var s := _setup(7.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	var full := int(mob.hp)
	w.drain_events()
	w.strike("me", "dummy")
	var events := w.drain_events()
	var lunge := {}
	for e in events:
		if e.type == "lunge":
			lunge = e
	if lunge.is_empty():
		_fail("7m 밖을 쳤는데 날라차기가 안 나갔다 %s" % [events])
		return
	if float(lunge.speed) <= 0.0 or int(lunge.ms) <= World.LUNGE_LAND_MS:
		_fail("날라차기 통보가 이상하다 %s" % lunge)

	var frames := 0
	var last_x := float(me.x)
	var went_back := false
	var hit_during := false
	var seq := 0
	while me.has("lunge") and frames < 120:
		# 나는 동안 반대로 몰아도 안 움직인다
		seq += 1
		w.input_move("me", seq, -1.0, 0.0, 1.0 / 60.0)
		w.step(1.0 / 60.0)
		frames += 1
		if float(me.x) < last_x - 1e-4:
			went_back = true
		last_x = float(me.x)
		for e in w.drain_events():
			if e.type == "hit" and str(e.target_kind) == "monster" and me.has("lunge"):
				hit_during = true

	var secs := frames / 60.0
	var speed := (7.0 - _gap(me, mob)) / maxf(secs, 1e-3)
	if me.has("lunge"):
		_fail("120 프레임이 지나도 안 내려앉았다")
	elif went_back:
		_fail("나는 동안 조작에 밀려 뒤로 갔다")
	elif hit_during:
		_fail("닿기 전에 맞았다")
	elif _gap(me, mob) > float(me.stats.attackRange):
		_fail("내려앉은 자리가 사거리 밖이다 (%.2f m)" % _gap(me, mob))
	elif int(mob.hp) >= full:
		_fail("닿았는데 한 대도 안 맞았다")
	elif speed < 10.0:
		_fail("너무 느리다 %.1f m/s" % speed)
	else:
		print("  7m → %.2f초(%d 프레임)에 날아 붙어(%.2f m) 찼다 — %.1f m/s, 클립 배속 %.2f" % [
			secs, frames, _gap(me, mob), speed, float(lunge.speed)
		])
	# 내려앉은 뒤에는 발이 잠깐 묶이고, 다음 평타는 공격 간격 뒤다
	var now := Time.get_ticks_msec()
	if int(me.rooted_until) <= now or int(me.rooted_until) > now + World.LUNGE_LAND_MS + 50:
		_fail("착지 경직이 %d ms" % (int(me.rooted_until) - now))


## 나는 동안 대상이 움직이면 도착점이 따라간다
func _case_follows_target() -> void:
	var s := _setup(7.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	w.strike("me", "dummy")
	for i in 5:
		w.step(1.0 / 60.0)
	mob.z = 2.0
	for i in 60:
		if not me.has("lunge"):
			break
		w.step(1.0 / 60.0)
	if _gap(me, mob) > float(me.stats.attackRange):
		_fail("대상이 옆으로 비켰는데 못 따라갔다 (%.2f m)" % _gap(me, mob))
	else:
		print("  나는 중에 대상이 2m 비켜도 따라가 %.2f m 에 내려앉았다" % _gap(me, mob))


## 가까우면(사거리 ~ LUNGE_MIN) 날지 않고, 헛휘두르지도 않는다 — 화면이 걸어서 붙인다
func _case_near_walks() -> void:
	var s := _setup(World.LUNGE_MIN - 0.5, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.drain_events()
	w.strike("me", "dummy")
	for e in w.drain_events():
		if e.type == "lunge" or e.type == "swing":
			_fail("%.1fm 에서 %s 가 나갔다 — 걸어서 붙어야 한다" % [World.LUNGE_MIN - 0.5, e.type])
	if me.has("lunge"):
		_fail("가까운데 날았다")


## 너무 멀면 날지 않는다 — 여기까지 걸어와서 난다
func _case_too_far() -> void:
	var s := _setup(World.LUNGE_MAX + 2.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.strike("me", "dummy")
	if me.has("lunge"):
		_fail("%.0fm 밖에서 날았다" % (World.LUNGE_MAX + 2.0))


## 원거리(사거리가 LUNGE_REACH 보다 긴) 직업은 날지 않는다
func _case_ranged_stays() -> void:
	var s := _setup(12.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.stats.attackRange = 9.0
	w.strike("me", "dummy")
	if me.has("lunge"):
		_fail("사거리 9m 인데 날았다")


## 자동 사냥도 스킬이 없으면 날아 붙는다
func _case_auto_lunges() -> void:
	var s := _setup(9.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)
	w.drain_events()
	var flew := false
	for i in 10:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if e.type == "lunge":
				flew = true
	if not flew:
		_fail("자동 사냥이 9m 밖 대상에게 날지 않았다")
	else:
		print("  자동 사냥도 스킬이 없으면 날아 붙는다")


## 자동 사냥 — 돌아온 스킬이 있어도 **거리가 안 닿으면 날라차기 먼저** (2026-09-29 요청),
## 내려앉으면 그 스킬이 나간다. 할퀴기 사거리 3, 대상 9m
func _case_skill_out_of_reach() -> void:
	var s := _setup(9.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.skills = ["rising_kick"]
	me.skill_bar = ["rising_kick"]
	w.set_auto("me", true)
	w.drain_events()
	var order: Array = []
	for i in 60:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if e.type == "lunge" or e.type == "skill" or e.type == "swing":
				order.append(str(e.type))
		if not me.has("lunge") and not order.is_empty():
			break
	# 착지 경직(300ms)은 벽시계다 — 기다렸다가 다음 수를 본다
	OS.delay_msec(World.LUNGE_LAND_MS + 50)
	for i in 10:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if e.type == "lunge" or e.type == "skill" or e.type == "swing":
				order.append(str(e.type))
	if order.size() < 2 or order[0] != "lunge" or order[1] != "skill":
		_fail("스킬이 안 닿는 9m 에서 날라차기 → 스킬 순이어야 하는데 %s" % [order])
	else:
		print("  스킬(사거리 3)이 안 닿는 9m: 날라차기 → 착지 뒤 스킬")


## 자동 사냥 — 스킬 사거리가 닿으면 날지 않고 그 자리에서 스킬을 쓴다. 빙주각 사거리 5, 대상 4.5m
func _case_skill_in_reach() -> void:
	var s := _setup(4.5, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.skills = ["frost_pillar"]
	me.skill_bar = ["frost_pillar"]
	w.set_auto("me", true)
	w.drain_events()
	var first := ""
	for i in 10:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if first == "" and (e.type == "lunge" or e.type == "skill" or e.type == "swing"):
				first = str(e.type)
	if first != "skill":
		_fail("스킬(사거리 5)이 닿는 4.5m 에서 첫 수가 %s" % (first if first != "" else "없음"))
	else:
		print("  스킬(사거리 5)이 닿는 4.5m: 날지 않고 스킬")
