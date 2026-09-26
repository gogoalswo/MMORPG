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
	_case_casts_skills()
	_case_click_casts_skills()
	_case_patrol_when_empty()
	_case_outside_radius()
	_case_off_stops()
	_case_dead()
	_case_manual_wins()

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
## 무리 안 **어디에 서서 켜도** 그 무리가 다 들어와야 한다.
## 옆 무리는 이제 들어온다 — 맵을 2/3 로 줄이며(2026-09-23) 무리 간격이 28 이 돼
## 한 무리를 덮는 반경(≥26)으로는 옆 무리를 뺄 수 없고, 사용자가 그걸 받아들였다.
## 그래서 옆 무리 거리는 검사하지 않고 적어만 둔다
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

	# 옆 무리가 얼마나 붙어 있는지 적어만 둔다 (위 설명)
	var nearest_other := INF
	for key in packs:
		for anchor in packs[key]:
			for other in packs:
				if other == key:
					continue
				for mob in packs[other]:
					nearest_other = minf(nearest_other, _gap(anchor, mob))
	print("  옆 무리는 최소 %.1f m (반경 %.1f)" % [nearest_other, World.HUNT_RADIUS])


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


## 액션바에 올린 스킬을 쓴다 (2026-09-23 "자동사냥하면 스킬을 안 사용해").
## 붙기 전에는 안 쓰고(사거리 밖), 사거리에 들면 기본 공격보다 먼저 쓴다
func _case_casts_skills() -> void:
	var s := _setup(10.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	me.skills = ["rising_kick"]
	me.skill_bar = ["rising_kick"]
	var reach := float(Skills.get_skill(str(me.job), "rising_kick").range)
	w.set_auto("me", true)
	w.drain_events()

	var cast_at := -1.0
	var swung_first := false
	for i in 600:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if e.type == "swing" and cast_at < 0.0:
				swung_first = true
			if e.type == "skill" and str(e.skill) == "rising_kick" and cast_at < 0.0:
				cast_at = _gap(me, mob)
		if cast_at >= 0.0:
			break

	if cast_at < 0.0:
		_fail("600 프레임 동안 액션바의 스킬을 한 번도 안 썼다")
	elif cast_at > reach + 1e-3:
		_fail("스킬 사거리(%.1f) 밖 %.2f m 에서 썼다" % [reach, cast_at])
	elif swung_first:
		_fail("돌아온 스킬을 두고 기본 공격을 먼저 휘둘렀다")
	else:
		print("  사거리 안(%.2f m)에 들자 스킬부터 썼다" % cast_at)


## 켜 둔 채로 몬스터를 눌러 쫓아도 스킬부터 쓴다 (2026-09-26 "평타만 사용해").
## 쫓는 동안은 이동 입력 때문에 `_drive_auto` 가 쉬므로, 화면(`_chase_and_hit`)이 하듯
## 매 프레임 이동 + `strike` 를 넣는다. 끈 채로는 `strike` 가 기본 공격이다
func _case_click_casts_skills() -> void:
	for auto in [true, false]:
		var s := _setup(10.0, 0.0)
		var w: World = s[0]
		var me: Dictionary = s[1]
		var mob: Dictionary = s[2]
		me.skills = ["rising_kick"]
		me.skill_bar = ["rising_kick"]
		w.set_auto("me", auto)
		w.drain_events()

		var first := ""
		var seq := 0
		for i in 600:
			var to := Vector2(mob.x - me.x, mob.z - me.z)
			var dt := 1.0 / 60.0 if to.length() > float(me.stats.attackRange) else 0.0
			seq += 1
			w.input_move("me", seq, to.normalized().x, to.normalized().y, dt)
			w.strike("me", str(mob.id))
			w.step(1.0 / 60.0)
			for e in w.drain_events():
				if first == "" and (e.type == "swing" or e.type == "skill"):
					first = str(e.type)
			if first != "":
				break

		var want := "skill" if auto else "swing"
		if first != want:
			_fail("눌러 쫓기(자동 %s): 첫 수가 %s 여야 하는데 %s" % [auto, want, first if first != "" else "없음"])
		else:
			print("  눌러 쫓기(자동 %s): 첫 수가 %s" % ["켬" if auto else "끔", "스킬" if auto else "기본 공격"])


## 잡을 것이 없으면 앵커 주변을 서성인다 — 선 채로 굳어 있으면 멈춘 것처럼 보인다.
##
## 쉬는 시간(1.2초)은 진짜 시계라 헤드리스에서는 안 지나간다. 몬스터 순찰
## 테스트와 같은 방식으로 쉬는 시각을 직접 밀어 준다
func _case_patrol_when_empty() -> void:
	var s := _setup(60.0, 60.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)
	# 쫓다가 반경 밖까지 나와 있는 자리에서 시작한다
	me.x = 12.0
	me.z = 0.0

	var anchor := Vector2(float(me.auto_x), float(me.auto_z))
	var walked := 0.0
	var worst := 0.0
	var before := Vector2(me.x, me.z)
	for i in 1200:
		me.auto_rest_until = 0
		w.step(1.0 / 60.0)
		var here := Vector2(me.x, me.z)
		walked += here.distance_to(before)
		before = here
		# 앵커로 돌아오기 전(첫 몇 초)은 반경 밖이라 세지 않는다
		if i > 300:
			worst = maxf(worst, here.distance_to(anchor))

	if walked < 5.0:
		_fail("서성이지 않았다 (%.1f m 만 걸었다)" % walked)
	elif worst > World.HUNT_PATROL_RADIUS + 1e-3:
		_fail("앵커에서 %.1f m 까지 벗어났다 (순찰 반경 %.1f)" % [
			worst, World.HUNT_PATROL_RADIUS
		])
	else:
		print("  잡을 것이 없자 앵커 %.1f m 안에서 %.1f m 를 서성였다" % [worst, walked])


## 반경 밖의 놈은 안 잡는다 — 잡으면 앵커를 둔 뜻이 없다
func _case_outside_radius() -> void:
	var s := _setup(World.HUNT_RADIUS + 3.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2]
	w.set_auto("me", true)

	for i in 300:
		me.auto_rest_until = 0
		w.step(1.0 / 60.0)
	if str(me.auto_target) != "":
		_fail("반경 밖(%.1f m)의 놈을 잡았다" % _gap(me, mob))
	# 서성이기는 하지만 순찰 반경 밖으로는 안 나간다 (=그놈에게 걸어가지 않았다)
	if Vector2(me.x, me.z).length() > World.HUNT_PATROL_RADIUS + 1e-3:
		_fail("반경 밖의 놈 쪽으로 걸어갔다 (%.2f, %.2f)" % [me.x, me.z])


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


## **켜 둔 채로 조작하면 사람이 이긴다.** 몬스터를 두고 반대쪽으로 몰아 본다 —
## 자동 사냥이 이기면 몬스터 쪽(+x)으로 끌려간다.
##
## 손을 떼면 0.4초(MANUAL_HOLD_MS) 뒤에 자동 사냥이 이어받는다. 그 시간은 진짜
## 시계라 헤드리스에서도 실제로 기다려야 한다 (한 번, 0.45초)
func _case_manual_wins() -> void:
	var s := _setup(10.0, 0.0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.set_auto("me", true)

	# 몬스터 반대쪽(-x)으로 몬다
	var seq := 0
	for i in 60:
		seq += 1
		w.input_move("me", seq, -1.0, 0.0, 1.0 / 60.0)
		w.step(1.0 / 60.0)

	if me.x > -0.5:
		_fail("조작한 쪽으로 안 갔다 (x %.2f) — 자동 사냥이 이겼다" % me.x)
	else:
		print("  조작이 이긴다: 1초 몰아 x %.2f 로 (몬스터는 +10 쪽)" % me.x)
	# 걸어간 자리가 새 사냥터다. 안 옮기면 손을 떼는 순간 도로 끌려간다
	if absf(float(me.auto_x) - me.x) > 1e-3 or absf(float(me.auto_z) - me.z) > 1e-3:
		_fail("앵커가 안 따라왔다 (%.2f, %.2f)" % [me.auto_x, me.auto_z])

	# 손을 뗀다. 유예가 지나면 다시 자동 사냥이 몬다
	OS.delay_msec(World.MANUAL_HOLD_MS + 50)
	var before := float(me.x)
	for i in 60:
		w.step(1.0 / 60.0)
	if me.x <= before:
		_fail("손을 뗐는데 자동 사냥이 안 이어받았다 (x %.2f -> %.2f)" % [before, me.x])
	else:
		print("  손을 떼자 %.1f초 뒤 자동 사냥이 이어받았다 (x %.2f -> %.2f)" % [
			World.MANUAL_HOLD_MS / 1000.0, before, me.x
		])
