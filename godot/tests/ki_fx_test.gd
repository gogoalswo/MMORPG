extends SceneTree

## 파천장(`ki_burst`) 이펙트 — **손바닥에서 기가 앞으로 휘몰아치는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — `npm run shot:godot -- ki_burst` 로 찍어서 눈으로 본다
## → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/ki_fx_test.gd

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
	await _case_hold(game)
	_case_reach()
	await _case_once(game)
	await _case_gone(game)
	_case_upgrade_table()
	await _case_upgraded(game)
	await _case_gone(game)
	_done()


## 액션바의 파천장을 누르면 **멈춤 뒤에** 이펙트가 서고 화면이 흔들린다 — **실제 경로로 쏜다.**
## 4차 전직(Lv.180) 스킬이라 레벨·포인트를 직접 올린다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "ki_burst"})
	game._transport.send(&"setSkillBar", {"bar": ["ki_burst"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("ki_burst" in me.get("skill_bar", [])):
		_fail("액션바에 파천장이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "ki_burst"})
	for i in 4:
		await process_frame
	# 주먹을 내질러 0.2초 멈췄다가 나간다 — 이펙트는 판정 시각(`delayMs`)에 선다. 그 전에는 없다
	var delay := float(Skills.get_skill("fighter", "ki_burst").get("delayMs", 0)) / 1000.0
	if delay <= 0.0:
		_fail("판정 지연(delayMs)이 없다 — 주먹을 내지르는 것과 같은 순간에 나간다")
	if _newest(game) != null:
		_fail("파천장 이펙트가 멈춤(%.2f초)이 끝나기 전에 섰다" % delay)
	await create_timer(delay + 0.05).timeout
	var fx := _newest(game)
	if fx == null:
		_fail("파천장을 썼는데 이펙트가 안 섰다")
		return
	if game._camera._shake_left <= 0.0:
		_fail("파천장을 썼는데 화면이 안 흔들린다")
	if absf(wrapf(fx.rotation.y - float(me.rot), -PI, PI)) > 1e-3:
		_fail("이펙트가 캐릭터가 보는 쪽(%.2f)이 아니라 %.2f 로 섰다" % [float(me.rot), fx.rotation.y])
	for e: CPUParticles3D in [fx._dust, fx._motes, fx._aura]:
		if not e.emitting:
			_fail("내지를 때 켜질 방출기가 안 켜졌다")
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다. 띠는 파티클이 아니라 메시다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")


## **절도** — 주먹을 내질러 멈춘 채로 이펙트가 나간다. 제 속도(벽시계)로 돌려서, 이펙트가 서는
## 순간 캐릭터가 여전히 `KiBurst` 를 틀고 있고 멈춤 끝(판정 시각) 근처에 있는지 잰다.
## 동작 상한(`_move_until`)이 벽시계라 `shot.gd` 처럼 시간을 늦추면 동작이 일찍 잘려 보인다 —
## 그래서 장면이 아니라 여기서 본다
func _case_hold(game: Node3D) -> void:
	if not game._player is Rig:
		print("  내 캐릭터가 모델이 아니다 (에셋 미동기화) — 멈춤 확인 건너뜀")
		return
	var rig: Rig = game._player
	var clip := str(game.SKILL_CLIPS["ki_burst"])
	var me: Dictionary = game._transport._world._players[game._transport.my_id()]
	while Time.get_ticks_msec() < int(me.rooted_until) or _newest(game) != null:
		OS.delay_msec(16)
		await process_frame
	me.skill_ready_at = {}
	me.cast_until = 0
	game._transport.send(&"skill", {"skill": "ki_burst"})
	var delay := float(Skills.get_skill("fighter", "ki_burst").get("delayMs", 0)) / 1000.0
	for i in 120:
		OS.delay_msec(16)
		await process_frame
		if _newest(game) != null:
			var at := rig._anim.current_animation_position
			if rig._anim.current_animation != clip or absf(at - delay) > 0.08:
				_fail("이펙트가 설 때 동작이 %s %.2f초다 — %s %.2f초(멈춤 끝)여야 한다" % [
					rig._anim.current_animation, at, clip, delay])
			else:
				print("  이펙트가 설 때 %s %.2f초 (멈춤 0.22~%.2f초)" % [clip, at, delay])
			return
	_fail("제 속도로 쐈는데 이펙트가 안 섰다")


## 가장 먼 것(소용돌이 · 빛살)이 **판정 사거리 안**이고 **앞쪽**이다
func _case_reach() -> void:
	var reach := float(Skills.get_skill("fighter", "ki_burst").get("range", 0.0))
	var far := 0.0
	for i in KiFx.SWIRLS:
		far = maxf(far, KiFx.SWIRL_Z[i] + KiFx.SWIRL_DEPTH * KiFx.radius_at(KiFx.SWIRL_Z[i]))
	var box := KiFx.streak_mesh().get_aabb()
	var streak_far := KiFx.PALM + box.end.z
	if far > reach or streak_far > reach:
		_fail("사거리 %.1fm 를 넘는다 — 소용돌이 %.2fm · 빛살 %.2fm" % [reach, far, streak_far])
	if box.position.z < 0.0:
		_fail("빛살이 손바닥 뒤로 뻗는다 (%.2f)" % box.position.z)
	print("  소용돌이 %.2fm · 빛살 %.2fm 까지 (사거리 %.1fm)" % [far, streak_far, reach])


## 메시는 게임 전체에서 한 번만 깐다 — 두 번째 것도 같은 메시를 쓴다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := KiFx.new()
	game._zone_node.add_child(fx)
	fx._build()
	var a: MeshInstance3D = (first._swirls[0].node as Node3D).get_child(0)
	var b: MeshInstance3D = (fx._swirls[0].node as Node3D).get_child(0)
	if a.mesh != b.mesh or first._streaks[0].node.mesh != fx._streaks[0].node.mesh:
		_fail("소용돌이·빛살 메시를 쓸 때마다 새로 깎는다")
	fx.queue_free()
	await process_frame


func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 600:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


## 강화 이펙트의 시각·자리가 **판정 표와 같다** — 연파 파도가 나가는 때, 기폭이 터지는 때·자리,
## 터지는 빛살이 판정 반경 안
func _case_upgrade_table() -> void:
	var twin := Skills.upgrade("ki_burst", "twin")
	var boom := Skills.upgrade("ki_burst", "detonate")
	if twin.is_empty() or boom.is_empty():
		_fail("강화 표에 파천장 연파·기폭이 없다")
		return
	if roundi(KiFx.TWIN_DELAY * 1000.0) != int(twin.followMs):
		_fail("연파 파도 %.2f초 ≠ 판정 %dms" % [KiFx.TWIN_DELAY, int(twin.followMs)])
	if roundi(KiFx.DETONATE_AT * 1000.0) != int(boom.followMs):
		_fail("기폭 이펙트 %.2f초 ≠ 판정 %dms" % [KiFx.DETONATE_AT, int(boom.followMs)])
	if absf(KiFx.DETONATE_Z - float(boom.followAhead)) > 1e-3:
		_fail("기폭 자리 %.2fm ≠ 판정 %.2fm" % [KiFx.DETONATE_Z, float(boom.followAhead)])
	var box := KiFx.blast_mesh().get_aabb()
	var edge := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	if edge > float(boom.followRadius):
		_fail("기폭 빛살이 판정 반경 %.1fm 를 넘는다 (%.2fm)" % [float(boom.followRadius), edge])
	print("  연파 %.2f초 · 기폭 %.2f초 앞 %.1fm, 빛살 옆으로 %.2fm" % [
		KiFx.TWIN_DELAY, KiFx.DETONATE_AT, KiFx.DETONATE_Z, edge])


## 연파·기폭을 붙이고 **실제 경로로** 쏜다 — 첫 파도(기폭)와 0.3초 뒤 푸른 파도가 둘 다 서고,
## 첫 파도가 `DETONATE_AT` 에 터진다(방출기가 켜진다). 푸른 파도는 터지지 않는다
func _case_upgraded(game: Node3D) -> void:
	var me: Dictionary = game._transport._world._players[game._transport.my_id()]
	while Time.get_ticks_msec() < int(me.rooted_until):
		await process_frame
	me.skill_upgrades = {"ki_burst": ["twin", "detonate"]}
	me.skill_ready_at = {}
	me.cast_until = 0
	game._transport.send(&"skill", {"skill": "ki_burst"})
	var delay := float(Skills.get_skill("fighter", "ki_burst").get("delayMs", 0)) / 1000.0
	await create_timer(delay + 0.05).timeout
	var list := _busy(game)
	if list.size() != 1 or not list[0]._detonate or list[0]._twin:
		_fail("기폭을 붙이고 쐈는데 첫 파도가 %d개 (기폭 붙은 금빛 하나여야 한다)" % list.size())
		me.skill_upgrades = {}
		return
	var first: KiFx = list[0]
	await create_timer(KiFx.TWIN_DELAY + 0.05).timeout
	list = _busy(game)
	var twin: KiFx = null
	for fx: KiFx in list:
		if fx._twin:
			twin = fx
	if list.size() != 2 or twin == null or twin._detonate:
		_fail("연파를 붙였는데 %.1f초 뒤 파도가 %d개 (푸른 것 하나 더, 기폭 없이)" % [KiFx.TWIN_DELAY, list.size()])
	elif absf(wrapf(twin.rotation.y - first.rotation.y, -PI, PI)) > 1e-3 or twin.position.distance_to(first.position) > 1e-3:
		_fail("푸른 파도가 첫 파도와 다른 자리·쪽에서 나갔다")
	await create_timer(KiFx.DETONATE_AT - KiFx.TWIN_DELAY).timeout
	if not first._blasted:
		_fail("기폭이 %.1f초가 지나도 안 터졌다" % KiFx.DETONATE_AT)
	for e: CPUParticles3D in [first._blast_aura, first._blast_motes, first._blast_dust]:
		if not e.emitting:
			_fail("기폭 방출기가 터질 때 안 켜졌다")
		if e.explosiveness < 1.0 or e.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("기폭 방출기 — 되감아 쓰는 1회용은 한꺼번에 내보내고 그림자를 끈다 (규칙 3절)")
	if twin != null and twin._blasted:
		_fail("푸른 파도까지 터졌다 — 기폭은 첫 파도만이다")
	print("  강화: 금빛 파도(기폭) + %.1f초 뒤 푸른 파도, %.1f초에 터졌다" % [KiFx.TWIN_DELAY, KiFx.DETONATE_AT])
	me.skill_upgrades = {}


func _busy(game: Node3D) -> Array:
	var out: Array = []
	if game._fx == null:
		return out
	for child in game._fx.get_children():
		if child is KiFx and FxPool.busy(child):
			out.append(child)
	return out


func _newest(game: Node3D) -> KiFx:
	if game._fx == null:
		return null
	var found: KiFx = null
	for child in game._fx.get_children():
		if child is KiFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("파천장 이펙트: 통과")
		quit(0)
	else:
		print("파천장 이펙트: %d개 실패" % _failed)
		quit(1)
