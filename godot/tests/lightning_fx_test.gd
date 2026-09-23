extends SceneTree

## 낙뢰(`thunder_fall`) 이펙트가 **세 번 겹쳐 치고**, 줄기가 **뒤에서 앞으로**
## 내리꽂히고, 닿은 자리에서 **땅이 갈라지며 파편이 튀는지** 본다.
##
## **줄기는 리본 메시다** — 파티클에 메시를 붙여 날렸더니 모양을 통제할 수 없어
## 다발로 뭉친 실이 됐다 (2026-09-18). 그래서 여기서는 "방출기가 몇 개인가" 가
## 아니라 **메시가 섰나 · 두 겹인가 · 지글거리나 · 금이 자라나** 를 본다.
##
## 생김새는 노드로 못 본다 — `npm run shot:godot` 으로 찍어서 눈으로 본다
## → [verification.md](../../docs/features/verification.md)
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
	await _case_ribbon(game)
	await _case_direction(game)
	await _case_flicker(game)
	await _case_ground(game)
	await _case_visible(game)
	await _case_other_skill(game)
	await _case_gone(game)
	await _case_red(game)
	await _case_wide(game)
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
	for i in 4:
		await process_frame
	if _newest(game) == null:
		_fail("낙뢰를 썼는데 이펙트가 안 섰다")


## **한 지점에 세 번, 순차적으로 겹쳐서** 친다
func _case_strikes(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("몇 번 치는지 볼 이펙트가 없다")
		return

	var strikes := _strikes(fx)
	if strikes.size() != LightningFx.STRIKES:
		_fail("낙뢰가 %d번이다 (%d번이어야 한다)" % [strikes.size(), LightningFx.STRIKES])
		return

	# 순차 — 뒤의 것일수록 늦게 친다
	for i in range(1, strikes.size()):
		if strikes[i].at <= strikes[i - 1].at:
			_fail("%d번째가 앞의 것보다 늦지 않다" % (i + 1))
	# 겹침 — 간격이 줄기 수명보다 짧아야 앞의 것이 살아 있는 동안 다음이 온다
	var gap := LightningFx.STRIKE_GAP
	if gap >= LightningFx.BOLT_LIFE:
		_fail("간격 %.2fs 이 줄기 수명 %.2fs 보다 길다 — 겹치지 않는다" % [gap, LightningFx.BOLT_LIFE])
	# 뒤로 갈수록 굵다
	if strikes[2].swell <= strikes[0].swell:
		_fail("마지막 번개가 더 굵지 않다")

	# 겹치되 자리가 조금씩 어긋나야 두 번째·세 번째가 보인다
	var spread: float = strikes[1].position.distance_to(strikes[0].position)
	if spread < 1e-3:
		_fail("두 번째가 첫 번째와 똑같은 자리다")
	elif spread > 1.0:
		_fail("두 번째가 %.2fm 떨어졌다 — 한 지점이 아니다" % spread)
	else:
		print("  낙뢰 %d번, %.0fms 간격, 자리 어긋남 %.2fm, 마지막이 %.0f%% 굵다" % [
			strikes.size(), gap * 1000.0, spread, (strikes[2].swell - 1.0) * 100.0
		])


## **줄기는 리본 메시이고 두 겹이다.** 파티클에 메시를 붙여 날리면 선의 모양을
## 자리마다 바꿀 수 없어 다발로 뭉친다 (2026-09-18). 한 겹 가산 혼합은 밝은
## 바닥에서 흰색으로 날아가 색이 안 보인다
func _case_ribbon(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("리본을 볼 이펙트가 없다")
		return
	var first: LightningFx.Strike = _strikes(fx)[0]

	for pair in [["halo", first._halo], ["코어", first._core], ["금", first._crack]]:
		var node: MeshInstance3D = pair[1]
		if node == null:
			_fail("%s 메시가 없다" % pair[0])
		elif node.mesh == null or node.mesh.get_surface_count() == 0:
			_fail("%s 에 면이 하나도 없다 — 깎이지 않았다" % pair[0])

	# 두 겹 — halo 가 코어보다 굵어야 테두리가 된다
	if LightningFx.HALO_WIDTH <= LightningFx.CORE_WIDTH * 1.5:
		_fail("halo(%.2f)가 코어(%.2f)보다 충분히 굵지 않다" % [
			LightningFx.HALO_WIDTH, LightningFx.CORE_WIDTH
		])
	# 빛은 가산, 흙은 불투명
	if first._halo.material_override.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
		_fail("줄기가 가산 혼합이 아니다 — 겹쳐도 안 밝아진다")
	if first._crack.material_override.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		_fail("금이 가산 혼합이다 — 흙은 빛나지 않는다")

	# **가장자리를 죄는 것은 텍스처다** (`FxTex.streak`). 꼭짓점 알파로만 죄면
	# 삼각형 안에서 직선으로 줄어들어 가운데 심이 각져 보인다
	for pair in [["halo", first._halo], ["코어", first._core], ["금", first._crack]]:
		var mat: StandardMaterial3D = pair[1].material_override
		if mat.albedo_texture == null:
			_fail("%s 에 폭 방향 텍스처가 없다 — 가장자리가 또렷해진다" % pair[0])

	var faces: int = first._core.mesh.get_faces().size() / 3
	print("  리본: halo %.2fm · 코어 %.2fm, 줄기 삼각형 %d개" % [
		LightningFx.HALO_WIDTH, LightningFx.CORE_WIDTH, faces
	])


## **번개는 캐릭터 뒤 위쪽에서 앞 아래로 내리꽂힌다** (2026-09-18 지시).
## 시작점이 캐릭터보다 앞에 있거나 수직으로 떨어지면 그림이 어긋난다
func _case_direction(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("방향을 볼 이펙트가 없다")
		return
	var first: LightningFx.Strike = _strikes(fx)[0]

	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var here := Vector3(me.x, 0.0, me.z)
	var facing := Vector3(sin(float(me.rot)), 0.0, cos(float(me.rot)))

	# 떨어지는 자리는 **내가 선 자리**다 (2026-09-18 지시). 앞에 떨어뜨렸더니
	# 내가 부른 것이 아니라 저쪽에 떨어진 것으로 보였다
	var fell := fx.global_position - here
	fell.y = 0.0
	if fell.length() > LightningFx.AHEAD + 0.01:
		_fail("번개가 %.1fm 떨어져서 친다 — 내가 선 자리여야 한다" % fell.length())

	# **어느 쪽을 보든 시작점이 화면 밖이어야 한다** (2026-09-18 지적:
	# "방향에 따라 엄청 짧게 나오기도 하고 번개 시작지점이 보이기도 해").
	# 캐릭터가 보는 쪽 반대에 두면 카메라가 고정각이라 시작점이 화면 아래로 내려온다
	var cam: Camera3D = game._camera
	var worst := -99999.0
	var worst_at := 0.0
	for step in 16:
		var turn := TAU * float(step) / 16.0
		var sky: Vector3 = here + LightningFx.from_dir(turn) * LightningFx.BEHIND \
			+ Vector3.UP * LightningFx.SKY
		var on_screen := cam.unproject_position(sky).y
		if on_screen > worst:
			worst = on_screen
			worst_at = turn
	if worst > -40.0:
		_fail("%.0f° 를 볼 때 시작점이 화면 y=%.0f 다 — 화면 밖(음수)이어야 한다" % [
			rad_to_deg(worst_at), worst
		])
	else:
		print("  시작점: 열여섯 방향 전부 화면 밖 (가장 낮은 것이 y=%.0f)" % worst)

	var start: Vector3 = first.to_global(first._from) - here
	var high: float = start.y
	start.y = 0.0
	var behind: float = start.length()
	if high < 3.0:
		_fail("줄기가 %.1fm 에서 시작한다 — 하늘에서 와야 한다" % high)

	# 그린 것이 실제로 하늘에서 땅까지 닿나 — 메시가 덮는 높이로 잰다
	var box: AABB = first._core.get_aabb()
	if box.size.y < LightningFx.SKY * 0.8:
		_fail("줄기 메시가 %.1fm 밖에 안 덮는다 (하늘은 %.1fm)" % [box.size.y, LightningFx.SKY])
	else:
		print("  줄기: %.1fm 떨어진 높이 %.1fm 에서 내 자리로 (%.1fm 를 덮는다)" % [
			behind, high, box.size.y
		])


## **지글거려야 번개다.** 한 모양으로 서 있으면 붙여 놓은 그림과 다를 게 없다
func _case_flicker(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("지글거림을 볼 이펙트가 없다")
		return
	var first: LightningFx.Strike = _strikes(fx)[0]
	# 줄기는 **같은 메시를 비우고 다시 채운다** (`ribbon` 의 `into`) — 객체가 아니라 꼭짓점을 본다
	var was := _verts(first._core.mesh)

	# FLICK(45ms)이 지나도록 기다린다
	for i in 20:
		await process_frame
	var now := _verts(first._core.mesh)
	if now == was and first._core.visible:
		_fail("줄기가 한 모양 그대로다 — 지글거리지 않는다")
	else:
		print("  지글거림: %.0fms 마다 경로를 다시 잡는다" % (LightningFx.FLICK * 1000.0))


## **닿은 자리에서 땅이 갈라지고 파편이 튄다.** 금은 중심에서 자라고,
## 파편은 솟았다 떨어진다
func _case_ground(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("땅을 볼 이펙트가 없다")
		return
	var first: LightningFx.Strike = _strikes(fx)[0]

	# 금은 지면에 눕는다
	if first._crack.position.y > 0.4:
		_fail("금이 %.2fm 에 떠 있다" % first._crack.position.y)
	var flat: AABB = first._crack.get_aabb()
	if flat.size.y > 0.3:
		_fail("금이 %.2fm 나 솟았다 — 지면을 따라 갈라져야 한다" % flat.size.y)
	# 가지를 친다 — 갈래마다 한 번 더 갈라져 나뭇가지가 된다
	if first._crack_paths.size() < LightningFx.CRACKS * 2:
		_fail("금이 %d갈래다 — 가지를 안 친다" % first._crack_paths.size())

	# 터지는 것은 **흙이 아니라 전기다** (2026-09-19 지시: "바닥에 먼지가 아니라
	# 번개가 터지는 이펙트로"). 빛이므로 가산 혼합이고, 중력을 세게 주면 도로
	# 흙처럼 떨어진다
	var sparks: CPUParticles3D = first._sparks
	if sparks.direction.y <= 0.0:
		_fail("불똥이 위로 안 튄다 (y=%.2f)" % sparks.direction.y)
	if sparks.material_override.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
		_fail("불똥이 가산 혼합이 아니다 — 전기는 빛난다")
	if sparks.gravity.y < -6.0:
		_fail("불똥이 중력 %.1f 로 떨어진다 — 흙으로 보인다" % sparks.gravity.y)

	# 지면 전기 가닥은 **리본 메시**다 (알갱이가 아니다). 금과 달리 밝고 빨리 꺼진다
	for pair in [["가닥 halo", first._arc_halo], ["가닥 심", first._arc_core]]:
		var arc: MeshInstance3D = pair[1]
		if arc.mesh == null or arc.mesh.get_surface_count() == 0:
			_fail("%s 에 면이 하나도 없다" % pair[0])
		elif arc.material_override.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
			_fail("%s 가 가산 혼합이 아니다" % pair[0])
	if first._arc_halo.get_aabb().size.y > 0.4:
		_fail("전기 가닥이 %.2fm 솟았다 — 지면을 타야 한다" % first._arc_halo.get_aabb().size.y)
	if LightningFx.ARC_LIFE >= LightningFx.CRACK_LIFE:
		_fail("전기 가닥이 금보다 오래 남는다 — 전기는 빨리 꺼진다")

	# 번쩍임 — 줄기 모양만으로는 번개로 안 읽힌다
	if first._light == null:
		_fail("번쩍임(조명)이 없다")

	# 그을림 — **불규칙한 얼룩 텍스처**여야 판 모서리가 사각형으로 보이지 않는다
	if first._stain.material_override.albedo_texture == null:
		_fail("그을림에 얼룩 텍스처가 없다 — 사각형 판으로 보인다")
	if first._stain.rotation.x != 0.0 and absf(first._stain.get_aabb().size.y) > 0.1:
		_fail("그을림이 지면에 안 눕는다")

	# 섬광은 **퍼지지 않고 제자리에서 사그라든다** (규칙 3절)
	if LightningFx.FLARE_SWELL > 1.5:
		_fail("섬광이 %.2f배까지 퍼진다 — 충격 파동 고리가 된다" % LightningFx.FLARE_SWELL)

	print("  땅: 금 %d갈래가 %.0fms 에 걸쳐 자라고, 전기 가닥 %d개와 불똥 %d개가 터진다" % [
		first._crack_paths.size(), LightningFx.CRACK_GROW * 1000.0,
		LightningFx.ARCS, sparks.amount
	])


## **화면에서 몇 px 로 보이나.** 미터로 정하면 서기만 하고 안 보인다.
## **얇게 깎는 것으로 문제를 풀지 않는다** — 뭉쳐 보이면 가닥 수를 줄인다
func _case_visible(game: Node3D) -> void:
	var cam: Camera3D = game._camera
	var at: Vector3 = game._player.global_position + Vector3.UP
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	var halo := LightningFx.HALO_WIDTH * per_m
	var core := LightningFx.CORE_WIDTH * per_m
	var sky := LightningFx.SKY * per_m
	var crack := LightningFx.CRACK_LENGTH * per_m
	var chunk := LightningFx.SPARK_SIZE * per_m
	print("  1m=%.0fpx — 줄기 halo %.0fpx(코어 %.0fpx) · 높이 %.0fpx · 금 %.0fpx · 파편 %.0fpx" % [
		per_m, halo, core, sky, crack, chunk
	])

	# **얇은 쪽이 낫다** (2026-09-18 지시). 다만 파티클로 만들던 때처럼 3px 까지
	# 깎지는 않는다 — 그때 실이 된 것은 굵기가 아니라 가닥이 뭉쳐서였다
	if halo < 10.0:
		_fail("halo 가 %.0fpx 다 — 코어를 감싸는 번짐이 안 보인다" % halo)
	if core < 3.0:
		_fail("코어가 %.1fpx 다 — 한 픽셀 밑이면 렌더에서 끊긴다" % core)
	if crack < 40.0:
		_fail("금이 %.0fpx 다 — 갈라진 것으로 안 보인다" % crack)
	# **작고 많아야 한다.** 8px 짜리 상자 열 개를 굴렸더니 "입자가 너무 크고
	# 두껍고 사각사각하다" 는 말을 들었다 (2026-09-18) — 크기를 반으로 줄인 만큼
	# 개수를 늘렸으니, 하한도 개수와 함께 본다
	if chunk < 3.0:
		_fail("불똥이 %.1fpx 다 — 한 픽셀 밑이면 안 보인다" % chunk)
	if chunk > 7.0:
		_fail("불똥이 %.0fpx 다 — 크면 덩어리로 보인다" % chunk)
	if LightningFx.SPARK_COUNT < 20:
		_fail("불똥이 %d개뿐이다 — 작게 줄인 만큼 많아야 한다" % LightningFx.SPARK_COUNT)
	if sky < 150.0:
		_fail("시작 높이가 %.0fpx 다 — 하늘에서 오는 것으로 안 보인다" % sky)


## 다른 스킬은 이 이펙트를 그리지 않는다. 스킬마다 그림이 달라야 한다
func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "fireball", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("화염구에 낙뢰 이펙트가 떴다")


## 스스로 사라진다. 부르는 쪽이 목록을 들고 있지 않으므로 여기서 안 지우면 쌓인다
func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 500:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


## **"기절" 강화가 붙으면 붉은 번개**, 떼면 다시 푸른 번개 (2026-09-23 요청).
## 테스트 단추 요청("전체 1번 강화")으로 붙인다. 풀이 한 벌을 되감아
## 쓰므로 붉게 칠한 것이 **다음 푸른 낙뢰에 남지 않는지**도 본다
func _case_red(game: Node3D) -> void:
	game._transport.send(&"debugUpgradeAll", {"slot": 0})
	for pair in [[true, "붉은"], [false, "푸른"]]:
		if not pair[0]:
			game._transport.send(&"debugResetUpgrades", {})
		game._transport.send(&"skill", {"skill": "thunder_fall"})
		for i in 4:
			await process_frame
		var fx := _newest(game)
		if fx == null:
			_fail("%s 낙뢰가 안 섰다" % pair[1])
			return
		var halo: Color = _strikes(fx)[0]._halo.material_override.albedo_color
		var spark: Color = _strikes(fx)[0]._sparks.color
		var red: bool = halo.r > halo.b and spark.r > spark.b
		var blue: bool = halo.b > halo.r and spark.b > spark.r
		if (pair[0] and not red) or (not pair[0] and not blue):
			_fail("%s 번개여야 하는데 헤일로 %s · 불똥 %s" % [pair[1], halo.to_html(false), spark.to_html(false)])
		else:
			print("  %s 번개: 헤일로 #%s" % [pair[1], halo.to_html(false)])
		while _newest(game) != null:
			await process_frame


## **"범위" 강화가 붙으면 가운데 세 번 뒤에 좌우 살짝 옆에서 한 번씩 더** 치고,
## 땅의 흔적(금)이 1.5배다 (2026-09-23 요청). 색은 안 바뀐다 — 기절과 따로 논다.
## 떼면 다시 세 번이다 (풀이 한 벌이라 옆 번개가 남으면 안 된다)
func _case_wide(game: Node3D) -> void:
	game._transport.send(&"debugResetUpgrades", {})
	game._transport.send(&"debugUpgradeAll", {"slot": 1})
	game._transport.send(&"skill", {"skill": "thunder_fall"})
	for i in 4:
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("넓은 낙뢰가 안 섰다")
		return
	var strikes := _strikes(fx)
	if strikes.size() != LightningFx.STRIKES + LightningFx.SIDE_STRIKES:
		_fail("넓은 낙뢰가 %d번이다 (다섯 번이어야 한다)" % strikes.size())
		return
	var facing: float = game._me().rot
	var ahead := Vector3(sin(facing), 0.0, cos(facing))
	var left: Vector3 = strikes[3].position
	var right: Vector3 = strikes[4].position
	if absf(left.dot(ahead)) > 0.05 or absf(right.dot(ahead)) > 0.05 or left.dot(right) >= 0.0:
		_fail("옆 번개가 캐릭터 좌우가 아니다 (%s · %s)" % [left, right])
	elif absf(left.length() - LightningFx.SIDE_GAP) > 0.01:
		_fail("옆 번개가 %.2fm 옆이다 (%.2f 여야 한다)" % [left.length(), LightningFx.SIDE_GAP])
	if strikes[4].at <= strikes[3].at or strikes[3].at <= strikes[2].at:
		_fail("옆 번개가 가운데 뒤에 차례로 치지 않는다")
	if absf(strikes[0].ground_mul - LightningFx.WIDE) > 1e-3:
		_fail("땅의 흔적이 %.2f배다" % strikes[0].ground_mul)
	var halo: Color = strikes[0]._halo.material_override.albedo_color
	if halo.r > halo.b:
		_fail("범위만 붙었는데 번개가 붉다")
	else:
		print("  넓은 낙뢰: %d번 · 옆 번개 좌우 %.1fm · 땅 흔적 %.1f배 · 색 그대로" % [
			strikes.size(), left.length(), strikes[0].ground_mul])
	while _newest(game) != null:
		await process_frame
	game._transport.send(&"debugResetUpgrades", {})
	game._transport.send(&"skill", {"skill": "thunder_fall"})
	for i in 4:
		await process_frame
	fx = _newest(game)
	if fx != null and _strikes(fx).size() != LightningFx.STRIKES:
		_fail("범위를 뗐는데 %d번 친다" % _strikes(fx).size())


## 낙뢰 한 번씩 (붙인 순서대로). **이번에 치는 것만** — 옆 번개는 넓힘이 없으면 쉰다
func _strikes(fx: LightningFx) -> Array:
	var found: Array = []
	for child in fx.get_children():
		if child is LightningFx.Strike and child.active:
			found.append(child)
	return found


func _verts(mesh: Mesh) -> PackedVector3Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _newest(game: Node3D) -> LightningFx:
	if game._fx == null:
		return null
	var found: LightningFx = null
	for child in game._fx.get_children():
		if child is LightningFx and FxPool.busy(child):
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._fx == null:
		return 0
	var n := 0
	for child in game._fx.get_children():
		if child is LightningFx and FxPool.busy(child):
			n += 1
	return n


func _done() -> void:
	if _failed == 0:
		print("낙뢰 이펙트: 통과")
		quit(0)
	else:
		print("낙뢰 이펙트: %d개 실패" % _failed)
		quit(1)
