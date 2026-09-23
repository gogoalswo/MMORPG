extends SceneTree

## 할퀴기 스킬 이펙트 — **초승달 다섯 번**이 앞 120° 를 번갈아 쓸고, 제 시간에
## 사라지는지 본다.
##
## 모양의 **수치**(몇 번 · 몇 가닥 · 앞쪽인가 · 번갈아 도나 · 몇 px 인가 · 판정과
## 박자가 같은가 · 치웠나)는 노드로 읽는다. **생김새는 찍어서 본다** —
## `npm run shot:godot -- rising_kick@225` (effect-rules.md 4절)
##
##   godot --headless --path godot --script tests/skill_fx_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
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
	_case_warm(game)
	await _case_cast(game)
	await _case_shape(game)
	await _case_visible(game)
	await _case_other_skill(game)
	await _case_gone(game)
	_done()


## **판정과 박자가 같아야 한다** — 한 줄기가 지나갈 때 숫자 하나가 떠야 긁은 것이
## 곧 맞은 것으로 읽힌다. 표(`skills.json`)가 바뀌면 여기서 걸린다
func _case_table() -> void:
	var kick := Skills.get_skill("fighter", "rising_kick")
	if int(kick.get("hits", 1)) != SkillFx.SLASHES:
		_fail("판정은 %d타인데 이펙트는 %d번 긁는다" % [int(kick.get("hits", 1)), SkillFx.SLASHES])
	if roundi(SkillFx.GAP * 1000.0) != int(kick.get("hitGap", 0)):
		_fail("판정 간격 %dms 와 이펙트 간격 %.0fms 가 다르다" % [
			int(kick.get("hitGap", 0)), SkillFx.GAP * 1000.0
		])
	# 쓸고 가는 각은 판정 부채꼴보다 넓어야 끝에 선 놈도 긁힌 것으로 보인다
	if SkillFx.SWEEP_ARC < float(kick.arc):
		_fail("이펙트가 %.0f° 만 쓴다 — 판정 부채꼴 %.0f° 보다 좁다" % [
			rad_to_deg(SkillFx.SWEEP_ARC), rad_to_deg(float(kick.arc))
		])


## **셰이더 미리 굽기** — 게임에 들어가면 한 번 돌고, 본 화면에는 안 보인다
## (본 카메라가 굽는 레이어를 안 본다). 안 돌면 스킬을 처음 쓸 때 멈칫한다
func _case_warm(game: Node3D) -> void:
	if not FxWarm._done:
		_fail("이펙트 셰이더 미리 굽기가 안 돌았다")
	if game._camera.cull_mask & FxWarm.LAYER != 0:
		_fail("본 화면 카메라가 굽는 레이어를 본다 — 굽는 이펙트가 화면에 보인다")
	var warm := game.get_node_or_null("FxWarm")
	if warm != null:
		for node in warm._stage.find_children("*", "", true, false):
			if node is VisualInstance3D and node.layers != FxWarm.LAYER:
				_fail("굽는 이펙트 %s 가 다른 레이어에 있다" % node.name)
				break


## 액션바의 할퀴기를 누르면(= 서버가 `skill` 이벤트를 낸다) 이펙트가 선다.
## **실제 경로로 쏜다** — 이벤트만 흉내 내면 액션바·전송이 끊겨도 통과한다
func _case_cast(game: Node3D) -> void:
	# 새 캐릭터는 아직 아무것도 안 배웠다 — 배우고 액션바에 올려야 쏠 수 있다
	# (서버가 액션바에 올라간 스킬만 받아 준다)
	game._transport.send(&"learnSkill", {"skill": "rising_kick"})
	game._transport.send(&"setSkillBar", {"bar": ["rising_kick"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var bar: Array = me.get("skill_bar", [])
	if not ("rising_kick" in bar):
		_fail("액션바에 할퀴기가 없다 (%s) — 기본 직업이 격투가가 아니다" % str(bar))
		return
	game._transport.send(&"skill", {"skill": "rising_kick"})
	for i in 3:
		await process_frame
	if _newest(game) == null:
		_fail("할퀴기를 썼는데 이펙트가 안 섰다")


## 다섯 번 · 세 겹 · 번갈아 · **캐릭터가 보는 쪽 앞** · 기울기가 엇갈리나
func _case_shape(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("모양을 볼 이펙트가 없다")
		return
	if fx._slashes.size() != SkillFx.SLASHES:
		_fail("긁기가 %d번이다" % fx._slashes.size())
		return

	# 줄기는 **직접 메시**다 (effect-rules.md 3절) — 한 번에 세 겹(빛·테·심)
	for slash in fx._slashes:
		if slash.layers.size() != 3:
			_fail("겹이 %d개다 (빛·테·심 셋이어야 한다)" % slash.layers.size())
			return

	# 번갈아 쓸고, 기울기는 이웃끼리 반대다 — 같으면 한 줄로 겹친다
	for i in range(1, SkillFx.SLASHES):
		var a: Dictionary = fx._slashes[i - 1]
		var b: Dictionary = fx._slashes[i]
		if float(a.side) * float(b.side) > 0.0:
			_fail("%d·%d번째가 같은 쪽으로 쓴다" % [i, i + 1])
		if float(a.tilt) * float(b.tilt) >= 0.0:
			_fail("%d·%d번째 기울기가 같은 쪽이다" % [i, i + 1])

	# **호의 가운데는 캐릭터가 보는 쪽이다** — 화면이 아니라 몸 기준
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var facing := Vector3(sin(float(me.rot)), 0.0, cos(float(me.rot)))
	var mid: Vector3 = fx.arc_point(0.0, SkillFx.RADIUS, fx._slashes[0])
	mid.y = 0.0
	if mid.normalized().dot(facing) < 0.95:
		_fail("호 가운데가 앞쪽이 아니다 (보는 쪽과 %.2f)" % mid.normalized().dot(facing))
	# 양 끝은 보는 쪽에서 반각만큼 벌어진다 — 뒤로 넘어가면 등을 긁는다
	var edge: Vector3 = fx.arc_point(SkillFx.SWEEP_ARC * 0.5, SkillFx.RADIUS, fx._slashes[0])
	edge.y = 0.0
	if edge.normalized().dot(facing) < 0.0:
		_fail("호 끝이 등 뒤로 넘어갔다")
	if absf(fx.global_position.y - SkillFx.HEIGHT) > 1e-3:
		_fail("이펙트 높이가 %.2f 다 — 가슴 높이여야 한다" % fx.global_position.y)

	# 몇 프레임 지나면 첫 긁기의 메시가 서 있어야 한다
	for i in 4:
		await process_frame
	var core: MeshInstance3D = fx._slashes[0].layers[2].node
	if not core.visible or core.mesh == null or core.mesh.get_surface_count() == 0:
		_fail("첫 긁기의 심이 안 그려졌다")
	# **메시를 다시 깎지 않는다** — 매 프레임 깎았더니 웹·폰에서 히치가 났다
	# (2026-09-23). 할퀴기마다 새로 만들어도 한 번 튄다. 모두가 같은 것을 쓴다
	elif core.mesh != SkillFx.arc_mesh(0) or fx._slashes[0].layers[0].node.mesh != core.mesh:
		_fail("호 메시를 새로 만들었다 — 한 번 깔아 둔 것(arc_mesh)을 같이 써야 한다")
	else:
		print("  모양: %d번 × 발톱 %d가닥 × 3겹, 간격 %.0fms, %.0f° 를 쓴다" % [
			SkillFx.SLASHES, SkillFx.CLAWS, SkillFx.GAP * 1000.0, rad_to_deg(SkillFx.SWEEP_ARC)
		])


## **화면에서 몇 px 로 보이나.** 미터로 정하면 서기만 하고 안 보인다 —
## 피격 이펙트에서 숫자 16px 로 잡았다가 "이펙트가 안 나온다" 는 말을 들었다
## (2026-09-17, `hit_fx_test.gd` 의 같은 검사)
func _case_visible(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("크기를 잴 이펙트가 없다")
		return

	var cam: Camera3D = game._camera
	var at: Vector3 = game._player.global_position + Vector3.UP
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	# 호 양 끝 사이(현) — 화면에서 긁고 간 길이
	var chord := 2.0 * SkillFx.RADIUS * sin(SkillFx.SWEEP_ARC * 0.5) * per_m
	var halo := SkillFx.HALO_WIDTH * per_m
	var core := SkillFx.CORE_WIDTH * per_m
	print("  1m=%.0fpx — 쓸고 간 길이 %.0fpx · 빛 폭 %.0fpx · 심 폭 %.0fpx" % [
		per_m, chord, halo, core
	])
	if chord < 100.0:
		_fail("쓸고 간 길이가 %.0fpx 다 — 캐릭터(68px)보다 넉넉히 커야 부채꼴로 읽힌다" % chord)
	if core < 3.0:
		_fail("심이 %.0fpx 다 — 흰 줄이 안 보인다" % core)
	if halo < 20.0:
		_fail("빛 폭이 %.0fpx 다 — 배경에 묻힌다" % halo)


## 다른 스킬은 이 이펙트를 그리지 않는다. 스킬마다 그림이 달라야 한다
func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "tiger_roar", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("호포각에 할퀴기 이펙트가 떴다")


## 스스로 사라진다. 부르는 쪽이 목록을 들고 있지 않으므로 여기서 안 지우면 쌓인다
func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 300:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다 (%.2f초짜리)" % [waited, SkillFx.span()])


func _newest(game: Node3D) -> SkillFx:
	if game._zone_node == null:
		return null
	var found: SkillFx = null
	for child in game._zone_node.get_children():
		if child is SkillFx:
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._zone_node == null:
		return 0
	var n := 0
	for child in game._zone_node.get_children():
		if child is SkillFx:
			n += 1
	return n


func _done() -> void:
	if _failed == 0:
		print("스킬 이펙트: 통과")
		quit(0)
	else:
		print("스킬 이펙트: %d개 실패" % _failed)
		quit(1)
