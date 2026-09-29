extends SceneTree

## 폭렬 찍기(`blast_heel`) — **발로 찍은 자리에서 연기와 기 줄기가 터지는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 발 자리와 맞는지 · 규칙을 지키는지 · 치워지는지** 를
## 본다. 생김새는 노드로 못 본다 — `npm run shot:godot -- blast_heel` 로 찍어서 눈으로 본다
## → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/blast_fx_test.gd

var _failed := 0


func _init() -> void:
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

	await _case_cast(game)
	await _case_foot()
	_case_judge()
	await _case_shape(game)
	await _case_gone(game)
	_done()


## 액션바의 폭렬 찍기를 누르면 **발이 닿은 뒤에**, **찍는 발 자리에** 이펙트가 선다 — 실제 경로로 쏜다.
## 4차 전직(Lv.180) 스킬이라 레벨·포인트·전직 단계를 직접 올린다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["job_tier"] = 4
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "blast_heel"})
	game._transport.send(&"setSkillBar", {"bar": ["blast_heel"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("blast_heel" in me.get("skill_bar", [])):
		_fail("액션바에 폭렬 찍기가 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "blast_heel"})
	for i in 4:
		await process_frame
	var delay := float(Skills.get_skill("fighter", "blast_heel").get("delayMs", 0)) / 1000.0
	if delay <= 0.0:
		_fail("폭렬 찍기에 발이 닿는 지연(delayMs)이 없다 — 발을 들기도 전에 터진다")
	elif _newest(game) != null:
		_fail("폭렬 찍기 이펙트가 발이 닿기(%.2f초) 전에 섰다" % delay)
	await create_timer(delay + 0.1).timeout
	var fx := _newest(game)
	if fx == null:
		_fail("폭렬 찍기를 썼는데 발이 닿은 뒤에도 이펙트가 안 섰다")
		return
	if game._camera._shake_left <= 0.0:
		_fail("폭렬 찍기를 썼는데 화면이 안 흔들린다")
	var foot := BlastFx.foot_point(Vector3(me.x, 0.0, me.z), float(me.rot))
	var gap := Vector2(fx.position.x - foot.x, fx.position.z - foot.z).length()
	if gap > 0.05:
		_fail("이펙트가 찍는 발 자리에서 %.2fm 어긋났다" % gap)


## `BlastFx.FOOT` 가 **동작이 실제로 발을 내려놓는 자리**인가 — 모델의 오른발 뼈를 발이 닿는
## 순간(`delayMs`)에 재어 본다. 보는 쪽을 돌려도 같이 돌아야 한다
func _case_foot() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	root.add_child(rig)
	var skeleton: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	# 키는 30fps 로 박혀 0.42 는 13번째 키(0.433초)다 — 그 뒤를 잰다
	var landed := float(Skills.get_skill("fighter", "blast_heel").get("delayMs", 0)) / 1000.0 + 0.02
	for facing in [0.0, 2.1]:
		rig.rotation.y = facing
		rig.play("BlastHeel", 0.0, landed, true, 0.0)
		for i in 4:
			await process_frame
		var bone := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot"))).origin
		var want := BlastFx.foot_point(rig.global_position, facing)
		var gap := Vector2(bone.x - want.x, bone.z - want.z).length()
		print("  찍는 발: 모델 (%.2f, %.2f) · 이펙트 자리 (%.2f, %.2f) · 발목 높이 %.2fm" % [
			bone.x, bone.z, want.x, want.z, bone.y])
		if gap > 0.12:
			_fail("보는 쪽 %.1f: 발(%.2f, %.2f)과 폭발 자리(%.2f, %.2f)가 %.2fm 어긋난다" % [
				facing, bone.x, bone.z, want.x, want.z, gap])
		if bone.y > 0.2:
			_fail("발이 닿는 때(%.2f초)인데 발목이 %.2fm 떠 있다 — delayMs 와 클립의 찍는 키가 어긋났다" % [landed, bone.y])
	rig.queue_free()


## 판정 — **내 둘레**(사거리 5m)다. 폭발이 발 자리로 왔으니 타겟 자리가 아니다 (2026-09-29)
func _case_judge() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me["job_tier"] = 4
	me.skills = ["blast_heel"]
	me.skill_bar = ["blast_heel"]
	var mobs: Array = w.snapshot().monsters
	var near := World.make_monster("near", GameData.monster_kind("mob003"),
		float(me.x) + 1.2, float(me.z), 100000.0, 0.0)
	var far := World.make_monster("far", GameData.monster_kind("mob003"),
		float(me.x) + 7.0, float(me.z), 100000.0, 0.0)
	mobs.append(near)
	mobs.append(far)
	var near_hp := int(near.hp)
	var far_hp := int(far.hp)
	w.cast("me", "blast_heel", "far")
	w._run_landings(Time.get_ticks_msec() + 5000)
	var ring := _event(w.drain_events(), "skillRange")
	if ring.is_empty():
		_fail("떨어졌는데 판정 범위가 안 왔다")
		return
	if Vector2(float(ring.x) - float(me.x), float(ring.z) - float(me.z)).length() > 0.01:
		_fail("판정 중심이 내 자리가 아니다 (%.1f, %.1f)" % [ring.x, ring.z])
	if int(near.hp) >= near_hp:
		_fail("내 옆(1.2m) 놈이 안 맞았다")
	if int(far.hp) < far_hp:
		_fail("사거리 밖(7m) 놈을 겨눴더니 맞았다 — 타겟 자리에서 터지면 안 된다")
	print("  판정: 내 둘레 %.1fm · 옆 놈 맞음 · 7m 밖 겨눈 놈 안 맞음" % float(ring.reach))


## 모양 — 기 줄기가 **위로 솟다가 바깥으로 휘고**, 끝이 사거리 안이다. 불·기둥·잔해가 없다.
## 줄기 메시는 한 번만 깐다
func _case_shape(game: Node3D) -> void:
	var reach := float(Skills.get_skill("fighter", "blast_heel").get("range", 0.0))
	var foot := Vector2(BlastFx.FOOT.x, BlastFx.FOOT.z).length()
	var widest := 0.0
	for strand in BlastFx.streaks():
		var path: PackedVector3Array = strand[0]
		var mid := path[path.size() / 2]
		var end := path[path.size() - 1]
		widest = maxf(widest, Vector2(end.x, end.z).length())
		# 솟다가 휜다 — 가운데까지는 오른 높이가 벌어진 거리보다 크다
		if mid.y <= Vector2(mid.x, mid.z).length() * 0.8 or end.y <= path[0].y:
			_fail("기 줄기가 위로 솟다가 휘지 않는다 (가운데 %s · 끝 %s)" % [mid, end])
			break
	print("  기 줄기 끝 %.1fm (+ 발 자리 %.2fm) · 사거리 %.1fm" % [widest, foot, reach])
	if widest + foot > reach:
		_fail("기 줄기 끝이 사거리(%.1fm)를 넘어 %.1fm 까지 간다" % [reach, widest + foot])
	if BlastFx.streak_end() > BlastFx.STREAK_END:
		_fail("줄기가 %.2f초까지 가는데 %.2f초에 숨긴다" % [BlastFx.streak_end(), BlastFx.STREAK_END])
	var puff := BlastFx.PUFF_SPEED * BlastFx.PUFF_SPEED / (2.0 * BlastFx.PUFF_DAMP)
	if puff > 1.5:
		_fail("발밑 흙먼지가 %.1fm 까지 번진다 — 내 주변으로 퍼지면 안 된다" % puff)
	if BlastFx.span() > 2.0:
		_fail("이펙트가 %.1f초나 간다 — 잔해를 남기지 않는다" % BlastFx.span())

	var fx := BlastFx.blast(game._zone_node, Vector3.ZERO, 1.0)
	await process_frame
	await process_frame
	var first := _newest(game)
	if first != null and fx._core.mesh != first._core.mesh:
		_fail("기 줄기 메시를 쓸 때마다 새로 깎는다")
	for e in fx._bursts:
		if not e.one_shot:
			_fail("계속 나는 방출기가 있다 — 불꽃 잔해는 없앴다")
			break
		if e.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("그림자를 드리우는 방출기가 있다 — 밑동에 어두운 호가 생긴다")
			break
	if not fx._bursts[0].emitting:
		_fail("연기가 안 솟았다")
	fx.queue_free()
	await process_frame


func _case_gone(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		return
	fx._t = BlastFx.span() - 0.01
	for i in 3:
		await process_frame
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")


func _event(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


func _newest(game: Node3D) -> BlastFx:
	if game._fx == null:
		return null
	var found: BlastFx = null
	for child in game._fx.get_children():
		if child is BlastFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("폭렬 찍기 이펙트: 통과")
		quit(0)
	else:
		print("폭렬 찍기 이펙트: %d개 실패" % _failed)
		quit(1)
