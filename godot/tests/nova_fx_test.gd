extends SceneTree

## 폭렬권(`nova_fist`) 이펙트 — **주먹이 닿으면 기운이 끓다가 판정 시각에 대폭발하는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — 찍어서 눈으로 본다 → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/nova_fx_test.gd

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

	_case_table()
	_case_reach()
	await _case_cast(game)
	await _case_once(game)
	await _case_upgrades(game)
	await _case_gone(game)
	_done()


## 폭발 시각 = 판정 시각(`delayMs`). 어긋나면 터지기 전에 숫자가 뜨거나 터지고 한참 뒤에 뜬다
func _case_table() -> void:
	var skill := Skills.get_skill("fighter", "nova_fist")
	if skill.is_empty():
		_fail("판정 표에 폭렬권이 없다")
		return
	var delay := float(skill.get("delayMs", 0)) / 1000.0
	if absf(delay - NovaFx.EXPLODE) > 0.02:
		_fail("판정은 %.2f초에 떨어지는데 폭발은 %.2f초다" % [delay, NovaFx.EXPLODE])
	if NovaFx.IMPACT >= NovaFx.EXPLODE:
		_fail("주먹이 닿기 전에 터진다")
	# 동작(`NovaFist`, 블렌더) 길이 = 스킬 표의 `castMs` — 그동안 다른 스킬이 막힌다
	var game: Node3D = root.get_node("Game")
	var clip: float = game._player.clip_length("NovaFist") if game._player != null else 0.0
	if absf(clip - float(skill.get("castMs", 0)) / 1000.0) > 0.05:
		_fail("동작 NovaFist 가 %.2f초인데 castMs 는 %d 다" % [clip, int(skill.get("castMs", 0))])
	if absf(float(skill.get("arc", 0.0)) - TAU) > 1e-3:
		_fail("폭발은 사방인데 판정이 부채꼴이다")


## 폭발이 **사거리 안에서 멎는다** — 불덩이·흙먼지·호·빛살 끝이 사거리 밖까지 가면
## "저기까지 맞는다" 로 읽힌다. 가운데가 앞으로 `AHEAD` 만큼 나가 있으니 그만큼 더한다
func _case_reach() -> void:
	var reach := float(Skills.get_skill("fighter", "nova_fist").get("range", 0.0))
	var fire := NovaFx.AHEAD + NovaFx.fire_reach()
	if fire > reach:
		_fail("불덩이가 %.2fm 까지 간다 — 사거리 %.1fm 밖" % [fire, reach])
	var dust := NovaFx.AHEAD + NovaFx.dust_reach()
	if dust > reach:
		_fail("흙먼지가 %.2fm 까지 간다 — 사거리 %.1fm 밖" % [dust, reach])
	var far := 0.0
	var starts := {}
	for strand in NovaFx.strands():
		starts[snappedf(float(strand[1]), 0.01)] = true
		for p: Vector3 in strand[0]:
			var at := p * NovaFx.SIZE + Vector3(0.0, 0.0, NovaFx.AHEAD)
			far = maxf(far, Vector2(at.x, at.z).length())
			if p.y * NovaFx.SIZE + NovaFx.CORE_Y < -0.3:
				_fail("가닥이 땅속(%.2fm)으로 파고든다" % (p.y * NovaFx.SIZE + NovaFx.CORE_Y))
				return
	if far > reach:
		_fail("호·빛살 끝이 %.2fm 까지 닿는다 — 사거리 %.1fm 밖" % [far, reach])
	if starts.size() < 8:
		_fail("가닥이 %d번에 나온다 — 한꺼번에 켜지면 소용돌이가 아니라 그림 한 장이다" % starts.size())
	for strand in NovaFx.strands():
		if float(strand[1]) < NovaFx.IMPACT - 1e-4:
			_fail("주먹이 닿기 전에 기운이 돈다")
			return


## 누르자마자 이펙트가 서고(끓기 시작), 흔들림은 **터질 때** 온다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "nova_fist"})
	game._transport.send(&"setSkillBar", {"bar": ["nova_fist"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("nova_fist" in me.get("skill_bar", [])):
		_fail("액션바에 폭렬권이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "nova_fist"})
	for i in 4:
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("폭렬권을 썼는데 이펙트가 바로 안 섰다 — 판정 시각까지 기다렸다 띄운다")
		return
	if game._camera._shake_left > 0.0:
		_fail("터지기도 전에 화면이 흔들린다")
	for e: CPUParticles3D in fx._emitters():
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")
	var waited := 0
	while fx._t < NovaFx.EXPLODE + 0.05 and waited < 300:
		await process_frame
		waited += 1
	if game._camera._shake_left <= 0.0:
		_fail("터졌는데 화면이 안 흔들린다")
	if not fx._fire.emitting or not fx._sparks.emitting:
		_fail("터졌는데 불덩이·불티가 안 나온다")


## 메시는 한 번만 깔고, 캐릭터가 보는 쪽으로 돈다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := NovaFx.burst(game._zone_node, Vector3.ZERO, 1.0)
	if fx._halo.mesh != first._halo.mesh:
		_fail("소용돌이 메시를 쓸 때마다 새로 깎는다")
	if absf(fx.rotation.y - 1.0) > 1e-4:
		_fail("캐릭터가 보는 쪽으로 안 돌았다")
	var ahead := fx._orb.global_position - fx.global_position
	if ahead.dot(Vector3(sin(1.0), 0.0, cos(1.0))) < NovaFx.AHEAD * 0.9:
		_fail("기운이 보는 쪽 앞이 아닌 곳에 모인다")
	fx.queue_free()
	await process_frame


## 강화 (2026-09-29) — 표의 값이 요청대로인가, 2차 폭발이 판정의 `followMs` 에 나오나,
## 풀에서 되감아 쓸 때 과부하 모양이 강화 없는 폭렬권에 남지 않나
func _case_upgrades(game: Node3D) -> void:
	var power := float(Skills.get_skill("fighter", "nova_fist").get("power", 0.0))
	var over := Skills.upgrade("nova_fist", "overload")
	var chain := Skills.upgrade("nova_fist", "chain")
	if over.is_empty() or chain.is_empty():
		_fail("폭렬권 강화(과부하·연쇄 폭발)가 표에 없다")
		return
	if absf(power - 15.0) > 1e-4:
		_fail("폭렬권 기본이 %d%% 다 — 1500%% 여야 한다" % int(power * 100.0))
	if absf(power * float(over.get("powerMul", 1.0)) - power - 5.0) > 1e-4:
		_fail("과부하가 500%% 추가가 아니다 (× %.2f)" % float(over.get("powerMul", 1.0)))
	if absf(float(chain.get("followPower", 0.0)) - 0.5) > 1e-4:
		_fail("연쇄 폭발이 50%% 가 아니다")
	if absf(float(chain.get("followMs", 0)) / 1000.0 - NovaFx.CHAIN) > 0.02:
		_fail("연쇄 폭발 판정은 폭발 %.2f초 뒤인데 2차 폭발은 %.2f초 뒤다"
			% [float(chain.get("followMs", 0)) / 1000.0, NovaFx.CHAIN])

	var fx := NovaFx.burst(game._zone_node, Vector3.ZERO, 0.0, true, true)
	fx.set_process(false)
	var wide := float((fx._halo.material_override as ShaderMaterial).get_shader_parameter(&"width"))
	if wide <= NovaFx.HALO_WIDTH * NovaFx.SIZE * 1.01:
		_fail("과부하인데 소용돌이가 안 굵다")
	while fx._t < NovaFx.EXPLODE + NovaFx.CHAIN - 0.05:
		fx._process(0.05)
	if fx._sparks2.emitting or fx._flash2.visible:
		_fail("2차 폭발이 제 시각보다 먼저 나온다")
	fx._process(0.08)
	if not fx._sparks2.emitting or not fx._fire2.emitting or not fx._flash2.visible:
		_fail("연쇄 폭발인데 2차 폭발(불티·불덩이·섬광)이 안 나온다")
	# 같은 노드를 강화 없이 되감는다 — 풀이 한 벌이라 모양이 남으면 안 된다
	fx._start(Vector3.ZERO, 0.0)
	wide = float((fx._halo.material_override as ShaderMaterial).get_shader_parameter(&"width"))
	if absf(wide - NovaFx.HALO_WIDTH * NovaFx.SIZE) > 1e-4:
		_fail("강화 없는 폭렬권에 과부하 굵기가 남았다")
	while fx._t < NovaFx.EXPLODE + NovaFx.CHAIN + 0.1:
		fx._process(0.05)
	if fx._flash2.visible:
		_fail("연쇄 폭발이 없는데 2차 섬광이 나온다")
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


func _newest(game: Node3D) -> NovaFx:
	if game._fx == null:
		return null
	var found: NovaFx = null
	for child in game._fx.get_children():
		if child is NovaFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("폭렬권 이펙트: 통과")
		quit(0)
	else:
		print("폭렬권 이펙트: %d개 실패" % _failed)
		quit(1)
