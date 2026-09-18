extends SceneTree

## 낙뢰(`thunder_fall`) 이펙트가 **세 번 겹쳐 치고**, 줄기가 **뒤에서 앞으로**
## 내리꽂히고, 닿은 자리에서 **땅이 갈라지며 파편이 튀는지** 본다.
##
## 스크린샷을 찍지 않는다 — "몇 번 치나 · 언제 치나 · 줄기가 어디서 어디로 가나 ·
## 금이 지면에 눕나 · 파편이 떨어지나 · 화면에서 몇 px 인가 · 치우고 갔나" 는
## 전부 노드로 읽을 수 있다. 눈으로 볼 것은 색과 속도감뿐이다.
##
##   godot --headless --path godot --script tests/lightning_fx_test.gd

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
	await _case_strikes(game)
	await _case_particles(game)
	await _case_direction(game)
	await _case_ground(game)
	await _case_visible(game)
	await _case_other_skill(game)
	await _case_gone(game)
	_done()


## 액션바의 낙뢰를 누르면(= `World` 가 `skill` 이벤트를 낸다) 이펙트가 선다.
## **실제 경로로 쏜다** — 이벤트만 흉내 내면 액션바·전송이 끊겨도 통과한다.
##
## 낙뢰는 Lv.30 스킬이라 **레벨과 포인트를 직접 올려 둔다.** 테스트 스위치
## (`SKILL_UNLOCK_ALL`)에 기대면 스위치를 끄는 날 이 테스트가 같이 깨진다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 30
	player["skill_points"] = 5

	game._transport.send(&"learnSkill", {"skill": "thunder_fall"})
	game._transport.send(&"setSkillBar", {"bar": ["thunder_fall"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var bar: Array = me.get("skill_bar", [])
	if not ("thunder_fall" in bar):
		_fail("액션바에 낙뢰가 없다 (%s) — 기본 직업이 격투가가 아니다" % str(bar))
		return
	game._transport.send(&"skill", {"skill": "thunder_fall"})
	for i in 3:
		await process_frame
	if _newest(game) == null:
		_fail("낙뢰를 썼는데 이펙트가 안 섰다")


## **한 지점에 세 번, 순차적으로 겹쳐서** 친다. 간격이 수명보다 길면 세 번
## 따로 치는 것이고, 0 이면 한 번 크게 치는 것이다
func _case_strikes(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("몇 번 치는지 볼 이펙트가 없다")
		return

	var strikes := _strikes(fx)
	if strikes.size() != LightningFx.STRIKES:
		_fail("낙뢰가 %d번이다 (%d번이어야 한다)" % [strikes.size(), LightningFx.STRIKES])
		return

	# 늦게 켜질 방출기가 있어야 순차다. 첫 줄기만 지금 터지고 나머지는 대기다
	if fx._delayed.is_empty():
		_fail("전부 한꺼번에 터졌다 — 세 번이 아니라 한 번이 된다")
	var gap := LightningFx.STRIKE_GAP
	if gap <= 0.0:
		_fail("치는 간격이 0 이다")
	elif gap >= LightningFx.CRACK_LIFE:
		_fail("간격 %.2fs 이 금 수명 %.2fs 보다 길다 — 겹치지 않는다" % [gap, LightningFx.CRACK_LIFE])

	# 겹치되 자리가 조금씩 어긋나야 두 번째·세 번째가 보인다
	if strikes[1].position.distance_to(strikes[0].position) < 1e-3:
		_fail("두 번째가 첫 번째와 똑같은 자리다")
	var spread: float = strikes[1].position.distance_to(strikes[0].position)
	if spread > 1.0:
		_fail("두 번째가 %.2fm 떨어졌다 — 한 지점이 아니다" % spread)
	else:
		print("  낙뢰 %d번, %.0fms 간격, 자리 어긋남 %.2fm" % [strikes.size(), gap * 1000.0, spread])


## **파티클이어야 한다.** 판 모양 메시를 세워 두면 "이미지 붙여 놓은 것 같다" 가
## 된다 (2026-09-17, 할퀴기에서 지적받았다). 방출기가 있고 뿌리는 알갱이가 있나
func _case_particles(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("파티클을 볼 이펙트가 없다")
		return

	var jets := _jets(fx)
	# 한 번에 일곱 — 줄기 묶음 셋 · 잔가지 · 섬광 · 금 · 파편
	var want := LightningFx.STRIKES * (LightningFx.BOLT_FLICKERS + 4)
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
	if total < 80:
		_fail("알갱이가 %d개뿐이다 — 파티클로 안 보인다" % total)
	else:
		print("  파티클: 방출기 %d개, 알갱이 %d개" % [jets.size(), total])

	# **치는 순간 주위가 번쩍여야 한다.** 줄기 모양보다 이쪽이 번개로 읽게 한다
	var lights := 0
	for strike in _strikes(fx):
		for child in strike.get_children():
			if child is OmniLight3D:
				lights += 1
	if lights != LightningFx.STRIKES:
		_fail("번쩍임이 %d개다 (%d개여야 한다)" % [lights, LightningFx.STRIKES])


## **번개는 캐릭터 뒤 위쪽에서 앞 아래로 내리꽂힌다** (2026-09-18 지시).
## 시작점이 캐릭터보다 앞에 있거나 수직으로 떨어지면 그림이 어긋난다
func _case_direction(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("방향을 볼 이펙트가 없다")
		return

	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var here := Vector3(me.x, 0.0, me.z)
	var facing := Vector3(sin(float(me.rot)), 0.0, cos(float(me.rot)))

	# 떨어지는 자리는 **보는 쪽 앞**이다
	var fell := fx.global_position - here
	fell.y = 0.0
	if fell.normalized().dot(facing) < 0.9:
		_fail("번개가 앞쪽에 안 떨어진다 (보는 쪽과 %.2f)" % fell.normalized().dot(facing))

	var bolt := _bolt_of(fx, 0)
	if bolt == null:
		_fail("줄기 방출기가 없다")
		return

	# 시작점은 **캐릭터보다 뒤**여야 한다 — 뒤에서 앞으로 지나가는 그림이다
	var start := bolt.global_position - here
	start.y = 0.0
	var behind := -start.dot(facing)
	if behind <= 0.0:
		_fail("줄기가 캐릭터 앞(%.1fm)에서 시작한다 — 뒤에서 와야 한다" % -behind)
	if bolt.global_position.y < 3.0:
		_fail("줄기가 %.1fm 에서 시작한다 — 하늘에서 와야 한다" % bolt.global_position.y)

	# **줄기 한 가닥이 시작점에서 땅까지 이어져야 한다.** 짧은 바늘을 초속 62m 로
	# 날렸더니 프레임 사이로 지나가 화면에 아무것도 안 남았다 (2026-09-18 캡처)
	var span := sqrt(LightningFx.SKY * LightningFx.SKY + LightningFx.BEHIND * LightningFx.BEHIND)
	if LightningFx.BOLT_LENGTH < span:
		_fail("줄기가 %.1fm 인데 하늘까지 %.1fm 다 — 중간에 끊긴다" % [
			LightningFx.BOLT_LENGTH, span
		])

	# 진행 방향은 **아래 + 앞**이다. 수직으로만 떨어지면 캐릭터와 겹쳐 기둥이 된다
	var way := (fx.global_transform.basis * bolt.direction).normalized()
	if way.y >= -0.3:
		_fail("줄기가 아래로 안 온다 (y=%.2f)" % way.y)
	var ahead := Vector3(way.x, 0.0, way.z)
	if ahead.length() < 0.2:
		_fail("줄기가 수직으로 떨어진다 — 뒤에서 앞으로 기울어야 한다")
	elif ahead.normalized().dot(facing) < 0.9:
		_fail("줄기가 앞쪽으로 안 간다 (보는 쪽과 %.2f)" % ahead.normalized().dot(facing))
	else:
		print("  줄기: 캐릭터 뒤 %.1fm · 높이 %.1fm 에서 앞 %.1fm 지점으로 (기울기 %.0f°)" % [
			behind, bolt.global_position.y, fell.length(),
			rad_to_deg(atan2(ahead.length(), -way.y)),
		])


## **닿은 자리에서 땅이 갈라지고 파편이 튄다.** 금은 지면을 따라 눕고,
## 파편은 솟았다 떨어진다. 그리고 둘 다 **줄기가 닿은 뒤**에 터진다
func _case_ground(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("땅을 볼 이펙트가 없다")
		return

	var cracks := _nth_of(fx, 0, LightningFx.BOLT_FLICKERS + 2)
	var debris := _nth_of(fx, 0, LightningFx.BOLT_FLICKERS + 3)
	if cracks == null or debris == null:
		_fail("금·파편 방출기가 없다")
		return

	# **금과 파편은 흙이라 빛나지 않는다.** 가산 혼합으로 뿌렸다가 흰 꽃과
	# 노란 알갱이 무리가 됐다 (2026-09-18 캡처)
	for dirt in [cracks, debris]:
		var mat: StandardMaterial3D = dirt.material_override
		if mat == null or mat.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			_fail("흙이 가산 혼합이다 — 밝은 알갱이가 된다")
		elif mat.no_depth_test:
			_fail("흙이 깊이 검사를 껐다 — 몸 앞으로 튀어나온다")

	# 금은 **XZ 평면**으로만 뻗어야 한다. flatness 를 안 올리면 위로도 뻗어 별표가 된다
	if cracks.flatness < 0.99:
		_fail("금이 평면에 안 갇혔다 (flatness %.2f) — 위로도 뻗어 별표가 된다" % cracks.flatness)
	if absf(cracks.direction.y) > 1e-3:
		_fail("금이 기운 방향으로 뻗는다 (y=%.2f)" % cracks.direction.y)
	if cracks.spread < 90.0:
		_fail("금이 사방으로 안 갈라진다 (spread %.0f°)" % cracks.spread)
	if cracks.gravity.length() > 1e-3:
		_fail("금이 중력을 받는다 — 지면에 남아야 한다")
	if not cracks.particle_flag_align_y:
		_fail("금이 뻗는 쪽으로 서지 않는다 — 뿌려진 부스러기가 된다")
	if cracks.global_position.y > 0.4:
		_fail("금이 %.2fm 에 떠 있다" % cracks.global_position.y)

	# 파편은 **솟았다 떨어진다.** 안 떨어지면 불똥이지 파편이 아니다
	if debris.direction.y <= 0.0:
		_fail("파편이 위로 안 튄다 (y=%.2f)" % debris.direction.y)
	if debris.gravity.y >= 0.0:
		_fail("파편이 안 떨어진다 (중력 %.1f)" % debris.gravity.y)

	# 줄기가 땅에 닿기 전에 갈라지면 번개가 원인으로 안 읽힌다
	var late := 0.0
	for waiting in fx._delayed:
		if waiting.node == cracks:
			late = float(waiting.delay)
	if late < LightningFx.IMPACT_DELAY - 1e-3:
		_fail("금이 %.2fs 에 터진다 — 줄기가 닿는 %.2fs 뒤여야 한다" % [late, LightningFx.IMPACT_DELAY])
	else:
		print("  땅: 금 %d갈래가 %.0fms 뒤에 눕고, 파편 %d개가 중력 %.0f 로 떨어진다" % [
			cracks.amount, late * 1000.0, debris.amount, debris.gravity.y
		])


## **화면에서 몇 px 로 보이나.** 미터로 정하면 서기만 하고 안 보인다 —
## 피격 이펙트에서 숫자 16px 로 잡았다가 "이펙트가 안 나온다" 는 말을 들었다
## (2026-09-17, `hit_fx_test.gd` · `skill_fx_test.gd` 의 같은 검사)
func _case_visible(game: Node3D) -> void:
	var cam: Camera3D = game._camera
	var at: Vector3 = game._player.global_position + Vector3.UP
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	var bolt := LightningFx.BOLT_LENGTH * per_m
	var width := LightningFx.BOLT_WIDTH * per_m
	var crack := LightningFx.CRACK_LENGTH * per_m
	var chunk := LightningFx.DEBRIS_SIZE * per_m
	var sky := LightningFx.SKY * per_m
	print("  1m=%.0fpx — 줄기 %.0fpx(폭 %.0fpx, 높이 %.0fpx) · 금 %.0fpx · 파편 %.0fpx" % [
		per_m, bolt, width, sky, crack, chunk
	])

	# 기준은 할퀴기에서 눈으로 정한 선을 따른다 (발톱 50px · 폭 4px · 파편 5px)
	if bolt < 200.0:
		_fail("줄기가 %.0fpx 다 — 하늘에서 땅까지 이어져 보여야 한다" % bolt)
	# **폭은 얇을수록 낫다.** 10px 로 잡았다가 가닥이 뭉쳐 흰 띠가 됐다
	# (2026-09-18 캡처). 길이 338px 이 번개를 만들고, 굵기는 3px 이면 족하다
	if width < 2.5:
		_fail("줄기 폭이 %.1fpx 다 — 한 픽셀 밑이면 렌더에서 끊긴다" % width)
	if crack < 40.0:
		_fail("금이 %.0fpx 다 — 갈라진 것으로 안 보인다" % crack)
	if chunk < 5.0:
		_fail("파편이 %.0fpx 다 — 안 보인다" % chunk)
	if sky < 150.0:
		_fail("시작 높이가 %.0fpx 다 — 하늘에서 오는 것으로 안 보인다" % sky)


## 다른 스킬은 이 이펙트를 그리지 않는다. 스킬마다 그림이 달라야 한다
func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "tiger_roar", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("호포각에 낙뢰 이펙트가 떴다")


## 스스로 사라진다. 부르는 쪽이 목록을 들고 있지 않으므로 여기서 안 지우면 쌓인다
func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 400:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


## 낙뢰 한 번씩 (붙인 순서대로)
func _strikes(fx: LightningFx) -> Array:
	var found: Array = []
	for child in fx.get_children():
		if child is Node3D and not (child is CPUParticles3D):
			found.append(child)
	return found


## 이펙트 안의 방출기 전부 (낙뢰마다 줄기 · 잔가지 · 섬광 · 금 · 파편)
func _jets(fx: LightningFx) -> Array:
	var found: Array = []
	for strike in _strikes(fx):
		for child in strike.get_children():
			if child is CPUParticles3D:
				found.append(child)
	return found


## `which` 번째 낙뢰의 `nth` 번째 방출기 (0 줄기 · 1 잔가지 · 2 섬광 · 3 금 · 4 파편)
func _nth_of(fx: LightningFx, which: int, nth: int) -> CPUParticles3D:
	var strikes := _strikes(fx)
	if which >= strikes.size():
		return null
	var jets: Array = []
	for child in strikes[which].get_children():
		if child is CPUParticles3D:
			jets.append(child)
	if nth >= jets.size():
		return null
	return jets[nth]


func _bolt_of(fx: LightningFx, which: int) -> CPUParticles3D:
	return _nth_of(fx, which, 0)


func _newest(game: Node3D) -> LightningFx:
	if game._zone_node == null:
		return null
	var found: LightningFx = null
	for child in game._zone_node.get_children():
		if child is LightningFx:
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._zone_node == null:
		return 0
	var n := 0
	for child in game._zone_node.get_children():
		if child is LightningFx:
			n += 1
	return n


func _done() -> void:
	if _failed == 0:
		print("낙뢰 이펙트: 통과")
		quit(0)
	else:
		print("낙뢰 이펙트: %d개 실패" % _failed)
		quit(1)
