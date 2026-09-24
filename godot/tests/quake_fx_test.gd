extends SceneTree

## 천붕각(`sky_breaker`) 이펙트 — **땅이 갈라지고 모래 먼지가 충격파로 터지는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — `npm run shot:godot -- sky_breaker 8,27,54,108,243,432`
## 로 찍어서 눈으로 본다 → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/quake_fx_test.gd

## 캐릭터 키(m). 금 길이는 이것의 1.5~4배다 (effect-rules.md 3절)
const HEIGHT := 1.7

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
	await _case_shake(game)
	await _case_cracks(game)
	await _case_dust(game)
	await _case_once(game)
	await _case_other_skill(game)
	await _case_gone(game)
	await _case_upgrades(game)
	_done()


## 액션바의 천붕각을 누르면 이펙트가 선다 — **실제 경로로 쏜다.**
## Lv.20 스킬이라 레벨과 포인트를 직접 올린다 (테스트 스위치에 기대지 않는다)
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 20
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "sky_breaker"})
	game._transport.send(&"setSkillBar", {"bar": ["sky_breaker"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("sky_breaker" in me.get("skill_bar", [])):
		_fail("액션바에 천붕각이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "sky_breaker"})
	for i in 4:
		await process_frame
	# 뛰어올랐다 내려찍는다 — 이펙트는 착지(`delayMs`)에 선다. 그 전에는 없어야 한다
	var delay := float(Skills.get_skill("fighter", "sky_breaker").get("delayMs", 0)) / 1000.0
	if delay > 0.0 and _newest(game) != null:
		_fail("천붕각 이펙트가 착지(%.2f초) 전에 섰다" % delay)
	await create_timer(delay + 0.1).timeout
	if _newest(game) == null:
		_fail("천붕각을 썼는데 착지 뒤에도 이펙트가 안 섰다")


## 화면이 **살짝** 흔들린다 — 몇 px 인지 재고, 끝나면 멈추고, 다른 스킬은 안 흔든다.
## 떨림 자체는 정지 화면으로 못 본다 (한 장에는 어긋난 자리 하나만 찍힌다)
func _case_shake(game: Node3D) -> void:
	var cam: CameraRig = game._camera
	if cam._shake_left <= 0.0:
		_fail("천붕각을 썼는데 화면이 안 흔들린다")
		return
	var at: Vector3 = game._player.global_position + Vector3.UP
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	var px := QuakeFx.SHAKE * per_m
	print("  흔들림 %.2fm = %.1fpx, %.2f초" % [QuakeFx.SHAKE, px, QuakeFx.SHAKE_TIME])
	if px < 2.0:
		_fail("흔들림이 %.1fpx 다 — 안 느껴진다" % px)
	if px > 10.0:
		_fail("흔들림이 %.1fpx 다 — '살짝' 이 아니다" % px)
	var waited := 0
	while cam._shake_left > 0.0 and waited < 600:
		await process_frame
		waited += 1
	if cam._shake_left > 0.0:
		_fail("흔들림이 안 멈춘다")
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "fireball", "root_ms": 400,
	})
	await process_frame
	if cam._shake_left > 0.0:
		_fail("화염구에도 화면이 흔들린다")


## 금 — 길이가 규칙(키의 1.5~4배) 안이고 **판정 사거리를 넘지 않는다.**
## 한꺼번에가 아니라 **어긋나게** 갈라지고, 흙이라 **가산이 아니다**
func _case_cracks(game: Node3D) -> void:
	# 흔들림을 기다리는 동안 첫 이펙트가 끝났을 수 있다 — 하나 새로 띄운다
	if _newest(game) == null:
		QuakeFx.slam(game._fx, game._player.position, 0.0)
		await process_frame
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("금을 볼 이펙트가 없다")
		return
	var reach := float(Skills.get_skill("fighter", "sky_breaker").get("range", 0.0))
	var paths := QuakeFx.crack_paths()
	var longest := 0.0
	var shortest := INF
	var delays := {}
	for entry in paths:
		# 본줄기만 (굵기 배율 1)
		if entry[1] < 1.0:
			continue
		var path: PackedVector3Array = entry[0]
		var tip := Vector2(path[path.size() - 1].x, path[path.size() - 1].z).length()
		longest = maxf(longest, tip)
		shortest = minf(shortest, tip)
		delays[entry[3]] = true
		for p in path:
			if absf(p.y) > 1e-4:
				_fail("금이 지면을 벗어났다 (y=%.2f) — 솟은 뿌리가 된다" % p.y)
				break
	if shortest < HEIGHT * 1.5 or longest > HEIGHT * 4.0:
		_fail("금 길이 %.1f~%.1fm — 키의 1.5~4배(%.1f~%.1fm)가 아니다" % [
			shortest, longest, HEIGHT * 1.5, HEIGHT * 4.0])
	if longest > float(reach):
		_fail("금이 %.1fm 까지 뻗는다 — 사거리 %.1fm 밖까지 맞는 것으로 읽힌다" % [longest, reach])
	if delays.size() < QuakeFx.CRACKS:
		_fail("금 %d갈래가 %d번에 갈라진다 — 한꺼번에 켜지면 무늬 한 장이다" % [
			QuakeFx.CRACKS, delays.size()])
	if paths.size() <= QuakeFx.CRACKS:
		_fail("곁가지가 없다 — 곁가지가 금다움이다")

	for pair in [["틈", fx._crack], ["심", fx._glow]]:
		var node: MeshInstance3D = pair[1]
		if node.mesh == null or node.mesh.get_surface_count() == 0:
			_fail("%s 메시에 면이 없다" % pair[0])
			continue
		var code: String = (node.material_override as ShaderMaterial).shader.code
		if code.contains("blend_add"):
			_fail("%s 이 가산 혼합이다 — 흙은 빛나지 않고, 밝은 바닥에서 안 보인다" % pair[0])
	print("  금 %d갈래(곁가지 %d) %.1f~%.1fm · 사거리 %.0fm" % [
		QuakeFx.CRACKS, paths.size() - QuakeFx.CRACKS, shortest, longest, reach])


## 먼지 — 켜졌고, **밀려나다 멈추는 거리가 사거리 안**이고, 가운데 기둥이 있다
func _case_dust(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("먼지를 볼 이펙트가 없다")
		return
	var reach := float(Skills.get_skill("fighter", "sky_breaker").get("range", 0.0))
	var up := 0
	for e: CPUParticles3D in fx._emitters:
		if not e.emitting:
			_fail("방출기가 안 켜졌다")
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
		if e.direction == Vector3.UP:
			up += 1
			continue
		# 수평으로 밀려나는 것 — 감속으로 멈추는 거리 v²/(2d)
		var stop := pow(e.initial_velocity_max, 2.0) / (2.0 * e.damping_min)
		if stop > reach + 0.5:
			_fail("먼지가 %.1fm 까지 나간다 — 사거리 %.0fm 를 넘는다" % [stop, reach])
		if stop < reach * 0.5:
			_fail("먼지가 %.1fm 에서 멈춘다 — 퍼지는 것으로 안 보인다" % stop)
	if up < 1:
		_fail("가운데서 솟는 먼지가 없다 — 가운데가 비어 먼지 고리가 된다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")


## 금 메시는 **한 번만** 깐다 — 쓸 때마다 깎으면 웹·폰에서 멈칫한다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := QuakeFx.slam(game._zone_node, Vector3.ZERO, 1.0)
	if fx._crack.mesh != first._crack.mesh:
		_fail("금 메시를 쓸 때마다 새로 깎는다")
	if absf(fx._crack.rotation.y - 1.0) > 1e-4:
		_fail("금이 캐릭터가 보는 쪽으로 안 돌았다")
	fx.queue_free()
	await process_frame


func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "fireball", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("화염구에 천붕각 이펙트가 떴다")


func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 600:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


## **강화** — "진폭" 이면 먼지 충격파·금 대신 **모래 토네이도**가 휘감아 판정 반경(9m)
## 까지 퍼진다. "균열 지대" 면 금이 3초 동안 붉게 남고 틱마다 맥동하며 **틈에서 용암이
## 여섯 번 솟는다.** 없으면 0.8초에 식는다. 시계를 직접 넣어 본다 — 3초를 기다리지 않는다
func _case_upgrades(game: Node3D) -> void:
	var wide := QuakeFx.slam(game._zone_node, Vector3.ZERO, 0.0, true, false)
	var reach := float(Skills.get_skill("fighter", "sky_breaker").get("range", 0.0)) \
		* float(Skills.upgrade("sky_breaker", "wide").get("rangeMul", 1.0))
	await process_frame
	var tornado: QuakeParts.Tornado = wide._tornado
	for i in 60:
		tornado.tick(1.0 / 60.0)
	wide._show_cracks()
	var front: CPUParticles3D = wide._emitters[0]
	if not tornado.active or not tornado.visible:
		_fail("진폭인데 토네이도가 안 섰다")
	elif absf(tornado.radius() - reach) > 0.3:
		_fail("토네이도가 %.1fm 까지 퍼진다 (판정 반경 %.0fm)" % [tornado.radius(), reach])
	elif front.emitting or wide._crack.visible:
		_fail("진폭만 붙었는데 먼지 충격파나 금이 나왔다 — 토네이도가 대신해야 한다")
	else:
		print("  진폭: 모래 토네이도 띠 %d줄이 %.1fm 까지 휘감는다 (먼지 충격파·금 없음)" % [
			QuakeParts.Tornado.BANDS, tornado.radius()])
	var plain_wide := QuakeFx.slam(game._zone_node, Vector3.ZERO, 0.0, false, false)
	if plain_wide._tornado.active:
		_fail("진폭이 없는데 토네이도가 섰다")
	wide.queue_free()
	plain_wide.queue_free()

	var zone_ms := float(Skills.upgrade("sky_breaker", "zone").get("zoneMs", 0)) / 1000.0
	var tick_ms := float(Skills.upgrade("sky_breaker", "zone").get("zoneTickMs", 0)) / 1000.0
	if absf(zone_ms - QuakeFx.ZONE_TIME) > 1e-3 or absf(tick_ms - QuakeFx.ZONE_TICK) > 1e-3:
		_fail("균열 지대: 판정은 %.1f초·%.1f초 간격인데 이펙트는 %.1f·%.1f" % [
			zone_ms, tick_ms, QuakeFx.ZONE_TIME, QuakeFx.ZONE_TICK])
	var zone := QuakeFx.slam(game._zone_node, Vector3.ZERO, 0.0, false, true)
	var plain := QuakeFx.slam(game._zone_node, Vector3.ZERO, 0.0, false, false)
	var alphas: Array = []
	for t in [1.0, 2.5, 2.55, 2.75]:
		for fx in [zone, plain]:
			fx._t = t
			fx._show_cracks()
		var lava: Color = zone._glow.material_override.get_shader_parameter(&"tint")
		alphas.append(lava.a)
		if not zone._glow.visible or lava.r < lava.g * 2.0:
			_fail("균열 지대 %.2f초에 금이 붉게 달아올라 있지 않다 (%s)" % [t, lava])
		if plain._glow.visible:
			_fail("강화 없는 천붕각인데 %.2f초에 금이 아직 달아올라 있다" % t)
	# 2.5초(틱) 직후가 가장 밝고, 틱 사이(2.75초)는 잦아든다
	if not (float(alphas[1]) > float(alphas[3]) + 0.2):
		_fail("틱마다 맥동하지 않는다 (%s)" % str(alphas))
	# 틈에서 솟는 용암 — 0.5 · 1.0 · … · 3.0초에 여섯 번, 틈 사이 방울은 지대 동안만
	var lava: QuakeParts.Lava = zone._lava
	lava.start(true, 0.0, 1.0)
	var bubbling := false
	for step in range(1, 81):
		lava.tick(step * 0.05)
		bubbling = bubbling or lava._bubbles.emitting
	if lava.bursts != 6 or not bubbling or lava._bubbles.emitting:
		_fail("용암: 분수 %d번 · 방울 %s → %s (여섯 번 · 지대 동안만 방울이어야 한다)" % [
			lava.bursts, bubbling, lava._bubbles.emitting])
	else:
		print("  균열 지대: 틈 %d곳에서 용암이 여섯 번 솟고, 틱 사이 방울이 튄다" % lava._vents.size())
	if plain._lava.active:
		_fail("균열 지대가 없는데 용암이 솟는다")
	zone._t = QuakeFx.ZONE_TIME + QuakeFx.ZONE_FADE
	zone._show_cracks()
	if zone._glow.visible:
		_fail("지대가 끝났는데 금이 식지 않았다")
	else:
		print("  균열 지대: %.1f초 붉게 남고 틱마다 맥동 (%.2f → %.2f), 끝나면 식는다" % [
			QuakeFx.ZONE_TIME, alphas[1], alphas[3]])
	zone.queue_free()
	plain.queue_free()


func _newest(game: Node3D) -> QuakeFx:
	if game._fx == null:
		return null
	var found: QuakeFx = null
	for child in game._fx.get_children():
		if child is QuakeFx and FxPool.busy(child):
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._fx == null:
		return 0
	var n := 0
	for child in game._fx.get_children():
		if child is QuakeFx and FxPool.busy(child):
			n += 1
	return n


func _done() -> void:
	if _failed == 0:
		print("천붕각 이펙트: 통과")
		quit(0)
	else:
		print("천붕각 이펙트: %d개 실패" % _failed)
		quit(1)
