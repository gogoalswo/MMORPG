extends SceneTree

## 무적파쇄권(`crush_fist`) 이펙트 — **기를 모으다가 주먹이 닿는 판정 시각에 터지는지** 본다.
##
## 여기서는 **판정 표·동작과 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — 찍어서 눈으로 본다 → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/crush_fx_test.gd

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

	_case_table(game)
	_case_reach()
	await _case_fist()
	await _case_cast(game)
	await _case_once(game)
	await _case_gone(game)
	_done()


## 터지는 시각 = 판정 시각(`delayMs`), 동작 길이 = `castMs`, 판정은 앞 반원
func _case_table(game: Node3D) -> void:
	var skill := Skills.get_skill("fighter", "crush_fist")
	if skill.is_empty():
		_fail("판정 표에 무적파쇄권이 없다")
		return
	var delay := float(skill.get("delayMs", 0)) / 1000.0
	if absf(delay - CrushFx.PUNCH) > 0.02:
		_fail("판정은 %.2f초에 떨어지는데 이펙트는 %.2f초에 터진다" % [delay, CrushFx.PUNCH])
	# "1초간 기를 모은 다음" — 모으는 시간이 1초 가까이는 돼야 한다
	if CrushFx.PUNCH - CrushFx.GATHER < 0.9:
		_fail("기를 %.2f초만 모은다" % (CrushFx.PUNCH - CrushFx.GATHER))
	var clip: float = game._player.clip_length("CrushFist") if game._player != null else 0.0
	if absf(clip - float(skill.get("castMs", 0)) / 1000.0) > 0.05:
		_fail("동작 CrushFist 가 %.2f초인데 castMs 는 %d 다" % [clip, int(skill.get("castMs", 0))])
	if float(skill.get("arc", 0.0)) >= TAU - 1e-3:
		_fail("주먹 앞에서 터지는데 판정이 사방이다")


## 가시 빛살·불티가 **사거리 안에서 멎는다** — 끝이 사거리 밖까지 가면 "저기까지 맞는다" 로 읽힌다
func _case_reach() -> void:
	var reach := float(Skills.get_skill("fighter", "crush_fist").get("range", 0.0))
	var far := 0.0
	for strand in CrushFx.rays():
		for p: Vector3 in strand[0]:
			var at := p + CrushFx.CENTER
			far = maxf(far, Vector2(at.x, at.z).length())
			if at.y < -0.3:
				_fail("빛살이 땅속(%.2fm)으로 파고든다" % at.y)
				return
		if float(strand[1]) < CrushFx.PUNCH - 1e-4:
			_fail("주먹이 닿기 전에 빛살이 뻗는다")
			return
	if far > reach:
		_fail("빛살 끝이 %.2fm 까지 닿는다 — 사거리 %.1fm 밖" % [far, reach])
	var sparks := Vector2(CrushFx.CENTER.x, CrushFx.CENTER.z).length() + CrushFx.spark_reach()
	if sparks > reach:
		_fail("불티가 %.2fm 까지 간다 — 사거리 %.1fm 밖" % [sparks, reach])
	for strand in CrushFx.crackles():
		if float(strand[1]) < CrushFx.GATHER or float(strand[1]) + float(strand[2]) > CrushFx.PUNCH:
			_fail("모으는 전기가 모으는 동안 밖에서 튄다")
			return


## **터지는 자리 = 모델의 오른주먹** — 동작 `CrushFist` 의 내지르는 키에서 `RightHand` 뼈를 잰다.
## 보는 쪽 둘에서 재야 이펙트가 캐릭터 기준으로 도는지까지 본다
func _case_fist() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	root.add_child(rig)
	var skeleton: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	for facing in [0.0, 2.1]:
		rig.rotation.y = facing
		rig.play("CrushFist", 0.0, CrushFx.PUNCH, true, 0.0)
		for i in 4:
			await process_frame
		var bone := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))).origin
		var want := rig.global_position + CrushFx.FIST.rotated(Vector3.UP, facing)
		print("  내지른 주먹: 모델 (%.2f, %.2f, %.2f) · 이펙트 (%.2f, %.2f, %.2f)" % [
			bone.x, bone.y, bone.z, want.x, want.y, want.z])
		if bone.distance_to(want) > 0.15:
			_fail("보는 쪽 %.1f: 주먹과 이펙트의 주먹 자리가 %.2fm 어긋난다" % [facing, bone.distance_to(want)])
	rig.queue_free()
	await process_frame


## 누르자마자 이펙트가 서고(기를 모으기 시작), 흔들림은 **터질 때** 온다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["job_tier"] = 4
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "crush_fist"})
	game._transport.send(&"setSkillBar", {"bar": ["crush_fist"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("crush_fist" in me.get("skill_bar", [])):
		_fail("액션바에 무적파쇄권이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "crush_fist"})
	for i in 4:
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("무적파쇄권을 썼는데 이펙트가 바로 안 섰다 — 판정 시각까지 기다렸다 띄운다")
		return
	if game._player != null and game._player._playing != "CrushFist":
		_fail("동작이 CrushFist 가 아니라 %s 다" % game._player._playing)
	if game._camera._shake_left > 0.0:
		_fail("터지기도 전에 화면이 흔들린다")
	for e: CPUParticles3D in fx._emitters():
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
		if e.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("방출기가 그림자를 드리운다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")
	var waited := 0
	while fx._t < CrushFx.GATHER + 0.3 and waited < 300:
		await process_frame
		waited += 1
	if not fx._gather.emitting or not fx._fist_r.visible:
		_fail("기를 모으는 동안 빛알·주먹 빛이 안 보인다")
	if fx._halo.visible:
		_fail("주먹을 내지르기 전에 가시 빛살이 보인다")
	while fx._t < CrushFx.PUNCH + 0.05 and waited < 600:
		await process_frame
		waited += 1
	if game._camera._shake_left <= 0.0:
		_fail("터졌는데 화면이 안 흔들린다")
	if not fx._sparks.emitting or not fx._halo.visible or not fx._star_big.visible:
		_fail("터졌는데 불티·빛살·가시 별이 안 나온다")
	if fx._fist_r.visible:
		_fail("내지른 뒤에도 허리 주먹 빛이 남았다")


## 메시는 한 번만 깔고, 캐릭터가 보는 쪽으로 돈다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := CrushFx.burst(game._zone_node, Vector3.ZERO, 1.0)
	if fx._halo.mesh != first._halo.mesh or fx._crackle.mesh != first._crackle.mesh:
		_fail("빛살·전기 메시를 쓸 때마다 새로 깎는다")
	if absf(fx.rotation.y - 1.0) > 1e-4:
		_fail("캐릭터가 보는 쪽으로 안 돌았다")
	var ahead := fx._star_big.global_position - fx.global_position
	if ahead.dot(Vector3(sin(1.0), 0.0, cos(1.0))) < CrushFx.CENTER.z * 0.9:
		_fail("보는 쪽 앞이 아닌 곳에서 터진다")
	fx.queue_free()
	await process_frame


func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 900:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


func _newest(game: Node3D) -> CrushFx:
	if game._fx == null:
		return null
	var found: CrushFx = null
	for child in game._fx.get_children():
		if child is CrushFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("무적파쇄권 이펙트: 통과")
		quit(0)
	else:
		print("무적파쇄권 이펙트: %d개 실패" % _failed)
		quit(1)
