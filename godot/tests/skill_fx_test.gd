extends SceneTree

## 할퀴기 스킬 이펙트가 **파티클로** 서고, 양쪽에서 엇갈리고, 제 시간에 사라지는지 본다.
##
## 스크린샷을 찍지 않는다 — "방출기가 몇 개인가 · 파티클이 몇 개인가 · 진행 방향으로
## 서는가 · 두 세트가 반대로 뻗는가 · 화면에서 몇 px 인가 · 치우고 갔나" 는 전부
## 노드로 읽을 수 있다. 눈으로 볼 것은 색과 속도감뿐이다.
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

	await _case_cast(game)
	await _case_particles(game)
	await _case_shape(game)
	await _case_visible(game)
	await _case_other_skill(game)
	await _case_gone(game)
	_done()


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


## **파티클이어야 한다.** 판 모양 메시를 세워 두었더니 "이미지 붙여 놓은 것 같다"
## 는 지적을 받았다 (2026-09-17). 방출기가 있고, 뿌리는 알갱이가 있고,
## 진행 방향으로 서는지를 여기서 본다
func _case_particles(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("파티클을 볼 이펙트가 없다")
		return

	var jets := _jets(fx)
	# 코어 하나 + 발톱 넷(두 세트 × 좌우) + 불똥 하나
	var want := 1 + SkillFx.SETS * 2 + 1
	if jets.size() != want:
		_fail("방출기가 %d개다 (%d개여야 한다)" % [jets.size(), want])
		return

	var total := 0
	for jet in jets:
		total += jet.amount
		if not jet.one_shot:
			_fail("한 번 터지고 마는 것이 아니다 (one_shot 이 꺼져 있다)")
		if jet.mesh == null:
			_fail("알갱이에 메시가 없다 — 점으로도 안 보인다")
	if total < 40:
		_fail("알갱이가 %d개뿐이다 — 파티클로 안 보인다" % total)
	else:
		print("  파티클: 방출기 %d개, 알갱이 %d개" % [jets.size(), total])

	# 발톱과 불똥은 날아가는 쪽으로 서야 한다. 안 세우면 알갱이가 아무 데나 누워
	# 뿌려진 부스러기가 된다
	for jet in _claws(fx):
		if not jet.particle_flag_align_y:
			_fail("발톱이 진행 방향으로 서지 않는다")


## **양쪽에서 들어와 X 로 엇갈려야 한다.** 한 세트는 서로 반대쪽으로 뻗는 방출기
## 둘이고, 두 세트는 기울기 부호가 반대다. 나란하게만 두면 빗금이 된다
func _case_shape(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("모양을 볼 이펙트가 없다")
		return

	var claws := _claws(fx)
	if claws.size() != SkillFx.SETS * 2:
		_fail("발톱 방출기가 %d개다" % claws.size())
		return

	# 한 세트(앞의 둘)는 서로 정반대로 뻗는다
	if claws[0].direction.normalized().dot(claws[1].direction.normalized()) > -0.99:
		_fail("한 세트가 양쪽으로 안 갈렸다 — 한 손으로만 긁은 빗금이 된다")
	# 두 세트는 기울기가 반대다 (X 로 엇갈린다)
	if claws[0].direction.y * claws[2].direction.y >= 0.0:
		_fail("두 세트가 같은 쪽으로 기울었다 (%.2f, %.2f)" % [
			claws[0].direction.y, claws[2].direction.y
		])

	# 두 번째 세트는 **늦게 켜진다.** 동시에 그으면 X 가 한 번에 찍힌다
	var late := 0
	for waiting in fx._delayed:
		late += 1
	if late == 0 and claws[2].emitting and claws[0].emitting:
		_fail("두 세트가 한꺼번에 나갔다")

	# **캐릭터가 보는 쪽 앞에 선다.** 화면이 아니라 몸이 보는 쪽이어야 한다
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var here := Vector3(me.x, 0.0, me.z)
	var facing := Vector3(sin(float(me.rot)), 0.0, cos(float(me.rot)))
	var away := fx.global_position - here
	away.y = 0.0
	if away.normalized().dot(facing) < 0.9:
		_fail("이펙트가 앞쪽에 없다 (보는 쪽과 %.2f)" % away.normalized().dot(facing))
	elif absf(fx.global_position.y - SkillFx.HEIGHT) > 1e-3:
		_fail("이펙트 높이가 %.2f 다 — 가슴 높이여야 한다" % fx.global_position.y)
	else:
		print("  자리: 앞 %.1fm, 높이 %.2fm, 세트 간격 %.0fms" % [
			away.length(), fx.global_position.y, SkillFx.SET_DELAY * 1000.0
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
	var claw := SkillFx.CLAW_LENGTH * per_m
	var width := SkillFx.CLAW_WIDTH * per_m
	var core := SkillFx.CORE_SIZE * per_m
	# 광선은 뻗어 나가므로 실제로 덮는 자리는 길이 + 날아간 거리다
	var reach := (SkillFx.CLAW_LENGTH + SkillFx.CLAW_SPEED * SkillFx.CLAW_LIFE * 0.5) * per_m
	print("  1m=%.0fpx — 발톱 %.0fpx(폭 %.0fpx, 뻗어서 %.0fpx) · 코어 %.0fpx" % [
		per_m, claw, width, reach, core
	])

	# 기준은 피격 이펙트에서 눈으로 정한 선을 따른다 — 파편이 5px 하한이었다
	if claw < 50.0:
		_fail("발톱이 %.0fpx 다 — 캐릭터(68px)보다 한참 짧으면 안 읽힌다" % claw)
	if width < 4.0:
		_fail("발톱 폭이 %.0fpx 다 — 배경에 묻힌다" % width)
	if core < 12.0:
		_fail("코어가 %.0fpx 다 — 터진 자리가 안 보인다" % core)


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
		print("  %d프레임 뒤 치워졌다" % waited)


## 이펙트 안의 방출기 전부 (붙인 순서대로: 코어 · 발톱 넷 · 불똥)
func _jets(fx: SkillFx) -> Array:
	var found: Array = []
	for child in fx.get_children():
		if child is CPUParticles3D:
			found.append(child)
	return found


## 발톱만 — 코어(첫째)와 불똥(마지막)을 뺀 가운데 넷
func _claws(fx: SkillFx) -> Array:
	var jets := _jets(fx)
	if jets.size() < 3:
		return []
	return jets.slice(1, jets.size() - 1)


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
