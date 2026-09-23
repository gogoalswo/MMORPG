extends SceneTree

## 맞았을 때 피격 이펙트가 실제로 서고, 제 시간에 사라지는지 본다.
##
## 스크린샷을 찍지 않는다 — "숫자가 떴나 · 몸이 붉어졌나 · 화면이 붉어졌나 ·
## 치우고 갔나" 는 전부 노드로 읽을 수 있다. 눈으로 볼 것은 색과 세기뿐이다.
##
##   godot --headless --path godot --script tests/hit_fx_test.gd

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

	# 마을에는 몬스터가 없다. 사냥터로 옮겨야 때릴 것이 생긴다
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 3:
		await process_frame

	var mobs: Array = game._transport.snapshot().get("monsters", [])
	# 이 테스트는 이벤트를 직접 넣어 본다. 맵을 2/3 로 줄인 뒤로(2026-09-23) 도착 지점이
	# 무리의 인식 범위 안이라, 진짜 몬스터가 알아채고 때리면 그 이펙트가 섞인다
	for m in mobs:
		m.aggro = 0.0
		m.target = ""
	if mobs.is_empty():
		_fail("존에 몬스터가 없다 — 이펙트를 걸 자리가 없다")
		_done()
		return
	var mob: Dictionary = mobs[0]
	var body: Node3D = game._mob_nodes.get(str(mob.id))

	await _case_monster(game, mob, body)
	await _case_visible(game, mob)
	await _case_crit(game, mob)
	await _case_feel(game, mob, body)
	await _case_gone(game, body)
	await _case_model(game)
	await _case_player(game)
	await _case_heal(game)
	_done()


## 몬스터를 때리면 그 자리 가슴 높이에서 터지고, 맞은 몸이 붉어진다
func _case_monster(game: Node3D, mob: Dictionary, body: Node3D) -> void:
	game._on_event(&"hit", _hit(mob, 37, false, false))
	await process_frame

	var fx := _newest(game)
	if fx == null:
		_fail("몬스터를 때렸는데 이펙트가 안 섰다")
		return
	if fx._number == null or fx._number.text != "37":
		_fail("피해 숫자가 37 이 아니다 (%s)" % ("없음" if fx._number == null else fx._number.text))
	if fx._flash == null:
		_fail("섬광이 없다")
	if fx._sparks.size() != HitFx.SPARKS:
		_fail("파편이 %d개다" % fx._sparks.size())

	# 발밑(0)이나 머리 위가 아니라 몸통에서 터져야 한다
	var top := _top_of(body)
	if fx.position.y < top * 0.3 or fx.position.y > top:
		_fail("이펙트가 몸통 높이가 아니다 (y %.2f, 키 %.2f)" % [fx.position.y, top])
	else:
		print("  때림: 숫자 %s, (%.1f, %.2f, %.1f) 에서 터짐" % [
			fx._number.text, fx.position.x, fx.position.y, fx.position.z
		])

	var painted := 0
	for mesh in HitFx.meshes_of(body):
		if mesh.material_overlay != null:
			painted += 1
	if painted == 0:
		_fail("맞은 몸이 붉어지지 않았다")
	else:
		print("  맞은 몸 %d장이 붉어짐" % painted)


## **화면에서 몇 px 로 보이나.** 이펙트가 서기만 하고 안 보인 적이 있다 —
## 숫자 16px · 파편 4px 로 잡았다가 "맞아도 이펙트가 안 나온다" 는 말을 들었다
## (2026-09-17). 미터로는 안 잡히고 px 로 재야 잡힌다
func _case_visible(game: Node3D, mob: Dictionary) -> void:
	game._on_event(&"hit", _hit(mob, 44, false, false))
	await process_frame
	var fx := _newest(game)
	if fx == null or fx._number == null or fx._flash == null:
		_fail("크기를 잴 이펙트가 없다")
		return

	# **내 캐릭터 자리에서 잰다.** 멀리 있는 보스 자리에서 재면 원근 때문에
	# 실제보다 크게 나와 검사가 헐거워진다
	var cam: Camera3D = game._camera
	var at: Vector3 = game._player.global_position + Vector3.UP
	# 1m 위를 같이 투영해 환산한다 (카메라 FOV·거리가 그대로 반영된다)
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	var screen := cam.get_viewport().get_visible_rect().size
	var number: float = fx._number.font_size * fx._number.pixel_size * per_m
	# 섬광은 터지면서 2배까지 커진다
	var flash: float = fx._flash.mesh.radius * 2.0 * 2.0 * per_m
	var spark: float = HitFx.SPARK_SIZE * per_m
	print("  화면 %d×%d, 1m=%.0fpx — 숫자 %.0fpx · 섬광 %.0fpx · 파편 %.0fpx" % [
		screen.x, screen.y, per_m, number, flash, spark
	])

	# 기준은 **눈으로 보고 정했다** — 16px 은 안 보였고, 58px 은 너무 컸다.
	# 지금은 HUD 글자(28px)와 비슷한 선이다 (2026-09-17)
	if number < 24.0:
		_fail("피해 숫자가 %.0fpx 다 — HUD 글자(28px)만 해야 읽힌다" % number)
	if flash < 40.0:
		_fail("섬광이 %.0fpx 다 — 0.2초만 뜨므로 작으면 못 본다" % flash)
	if spark < 5.0:
		_fail("파편이 %.0fpx 다 — 점으로도 안 보인다" % spark)

	var waited := 0
	while _newest(game) != null and waited < 240:
		await process_frame
		waited += 1


## 치명타는 숫자가 더 크고 느낌표가 붙는다 — 읽지 않아도 크기로 안다
func _case_crit(game: Node3D, mob: Dictionary) -> void:
	game._on_event(&"hit", _hit(mob, 91, true, false))
	await process_frame
	var fx := _newest(game)
	if fx == null or fx._number == null:
		_fail("치명타 이펙트가 안 섰다")
		return
	if fx._number.text != "91!":
		_fail("치명타 숫자가 '91!' 이 아니다 (%s)" % fx._number.text)
	if fx._number.modulate.to_html(false) != HitFx.COLOR_CRIT.to_html(false):
		_fail("치명타 숫자가 치명타 색이 아니다 (%s)" % fx._number.modulate.to_html(false))
	if fx._number.pixel_size <= 0.006:
		_fail("치명타가 평타보다 크지 않다 (%.4f)" % fx._number.pixel_size)
	else:
		print("  치명타: %s, 글자 %.3f (평타 %.3f)" % [
			fx._number.text, fx._number.pixel_size, HitFx.NUMBER_SIZE
		])


## 타격감 — 단계가 평타 < 치명타 < 처치 < 보스 로 오르고, 맞은 몸이 퍼졌다가
## 제 모양으로 돌아오고, 치명타에 화면이 흔들리고, 히트스톱이 풀린다
func _case_feel(game: Node3D, mob: Dictionary, body: Node3D) -> void:
	var tiers := [
		HitFx.tier_of(_hit(mob, 1, false, false), false),
		HitFx.tier_of(_hit(mob, 1, true, false), false),
		HitFx.tier_of(_hit(mob, 1, false, true), false),
		HitFx.tier_of(_hit(mob, 1, false, true), true),
	]
	if tiers != [0, 1, 2, 3]:
		_fail("단계가 평타·치명타·처치·보스처치 순으로 0~3 이 아니다 %s" % [tiers])
	var hurt := _hit(mob, 1, false, false)
	hurt.target_kind = "player"
	if HitFx.tier_of(hurt, false) < 1:
		_fail("내가 맞았는데 평타 단계다 — 진동이 안 온다")
	var heal := hurt.duplicate()
	heal.heal = true
	if HitFx.tier_of(heal, false) != -1:
		_fail("회복에 타격감이 걸린다")
	for i in HitFx.TIERS.size() - 1:
		var lo: Dictionary = HitFx.TIERS[i]
		var hi: Dictionary = HitFx.TIERS[i + 1]
		for key in ["stop", "shake", "kick", "squash", "buzz"]:
			if float(hi[key]) < float(lo[key]):
				_fail("%d단계 %s 가 %d단계보다 약하다" % [i + 1, key, i])
	if float(HitFx.TIERS[0].shake) > 0.0:
		_fail("평타에 화면이 흔들린다 — 초당 몇 번씩 흔들리면 멀미가 난다")

	game._camera._shake_left = 0.0
	game._on_event(&"hit", _hit(mob, 50, true, false))
	await process_frame
	await process_frame
	if game._camera._shake_left <= 0.0:
		_fail("치명타에 화면이 안 흔들렸다")
	if body != null:
		if not body.has_meta(&"hit_react"):
			_fail("맞은 몸에 반응이 안 걸렸다")
		elif body.scale.x <= 1.0:
			_fail("맞은 몸이 안 퍼졌다 (%.3f)" % body.scale.x)
		var waited := 0
		while body.has_meta(&"hit_react") and waited < 240:
			await process_frame
			waited += 1
		if body.has_meta(&"hit_react") or not body.scale.is_equal_approx(Vector3.ONE):
			_fail("맞은 몸이 제 모양으로 안 돌아왔다 (%s)" % body.scale)

	# 히트스톱 — 모델 파일이 없는 곳(CI)에서도 보도록 빈 재생기를 단 리그로 본다
	var rig := Rig.new()
	var player := AnimationPlayer.new()
	rig.add_child(player)
	rig._anim = player
	game.add_child(rig)
	rig.freeze(0.05)
	if player.speed_scale != 0.0:
		_fail("히트스톱에 동작이 안 멈췄다")
	var waited_stop := 0
	while player.speed_scale == 0.0 and waited_stop < 240:
		await process_frame
		waited_stop += 1
	if player.speed_scale != 1.0:
		_fail("히트스톱이 안 풀렸다 (배속 %.2f)" % player.speed_scale)
	else:
		print("  타격감: 단계 %s, 히트스톱 %d프레임 뒤 풀림" % [tiers, waited_stop])
	rig.queue_free()


## 스스로 사라지고 **덧칠도 걷어 간다.** 안 걷으면 몬스터가 영영 빨갛다
func _case_gone(game: Node3D, body: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 240:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("%d프레임이 지나도 이펙트가 안 사라졌다" % waited)
		return
	for mesh in HitFx.meshes_of(body):
		if mesh.material_overlay != null:
			_fail("이펙트가 사라졌는데 몸이 붉은 채로 남았다")
			return
	print("  %d프레임(약 %.1f초) 뒤 스스로 사라지고 덧칠도 걷힘" % [waited, waited / 60.0])


## 모델로 선 몬스터는 메시가 여러 장이다 — 덧칠(`material_overlay`)이 거기까지
## 닿는지 본다. 에셋을 안 받았으면 기둥뿐이라 건너뛴다
func _case_model(game: Node3D) -> void:
	var mob: Dictionary = {}
	for monster in game._transport.snapshot().get("monsters", []):
		if game._mob_nodes.get(str(monster.id)) is Rig:
			mob = monster
			break
	if mob.is_empty():
		print("  모델로 선 몬스터가 없다 (에셋 미동기화) — 모델 덧칠은 건너뜀")
		return

	var body: Node3D = game._mob_nodes[str(mob.id)]
	game._on_event(&"hit", _hit(mob, 12, false, false))
	await process_frame
	# 모델 메시는 Rig 아래 깊이 들어 있다 — 한 장이라도 빠지면 얼룩덜룩해진다
	var meshes := HitFx.meshes_of(body)
	var painted := 0
	for mesh in meshes:
		if mesh.material_overlay != null:
			painted += 1
	if painted == 0 or painted != meshes.size():
		_fail("모델 몬스터 메시 %d장 중 %d장만 붉어졌다" % [meshes.size(), painted])
	else:
		print("  모델 몬스터(%s): 메시 %d장 전부 붉어짐" % [mob.kind, painted])

	# 다음 검사가 이 이펙트를 보지 않도록 사라질 때까지 기다린다
	var waited := 0
	while _newest(game) != null and waited < 240:
		await process_frame
		waited += 1


## 내가 맞으면 화면 가장자리가 붉어졌다가 잦아든다
func _case_player(game: Node3D) -> void:
	if game._hurt.visible:
		_fail("맞기도 전에 화면이 붉다")
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	game._on_event(&"hit", {
		"target": game._transport.my_id(),
		"target_kind": "player",
		"amount": int(me.stats.maxHp) / 4,
		"crit": false,
		"killed": false,
		"x": me.x,
		"z": me.z,
	})
	await process_frame
	if not game._hurt.visible or game._hurt.modulate.a <= 0.0:
		_fail("내가 맞았는데 화면이 안 붉어졌다")
		return
	var peak: float = game._hurt.modulate.a
	var waited := 0
	while game._hurt.modulate.a > 0.0 and waited < 240:
		await process_frame
		waited += 1
	if game._hurt.visible:
		_fail("화면이 붉은 채로 남았다")
	else:
		print("  내가 맞음: 화면 %.2f 까지 붉어졌다가 %d프레임 뒤 걷힘" % [peak, waited])


## 회복은 때린 것이 아니다 — 초록 + 숫자만 뜨고 섬광·파편이 없다
func _case_heal(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	game._on_event(&"hit", {
		"target": game._transport.my_id(),
		"target_kind": "player",
		"amount": 25,
		"heal": true,
		"crit": false,
		"killed": false,
		"x": me.x,
		"z": me.z,
	})
	await process_frame
	var fx := _newest(game)
	if fx == null or fx._number == null:
		_fail("회복 숫자가 안 떴다")
		return
	if fx._number.text != "+25":
		_fail("회복 숫자가 '+25' 가 아니다 (%s)" % fx._number.text)
	# 풀에서 되감아 쓰므로 노드는 있다 — **꺼져 있어야** 한다
	var shown := fx._flash.visible
	for spark in fx._sparks:
		shown = shown or spark.node.visible
	if shown:
		_fail("회복인데 섬광·파편이 있다")
	if fx._number.modulate != HitFx.COLOR_HEAL:
		_fail("회복 숫자가 초록이 아니다")
	if game._hurt.visible:
		_fail("회복했는데 화면이 붉어졌다")
	if _failed == 0:
		print("  회복: %s, 섬광 없음, 화면 안 붉어짐" % fx._number.text)


func _hit(mob: Dictionary, amount: int, crit: bool, killed: bool) -> Dictionary:
	return {
		"target": str(mob.id),
		"target_kind": "monster",
		"amount": amount,
		"crit": crit,
		"killed": killed,
		"x": mob.x,
		"z": mob.z,
	}


## 존 아래 살아 있는 이펙트 중 마지막 것
func _newest(game: Node3D) -> HitFx:
	var found: HitFx = null
	for child in game._fx.get_children():
		if child is HitFx and FxPool.busy(child):
			found = child
	return found


func _top_of(body: Node3D) -> float:
	var box := AABB()
	var first := true
	for mesh in HitFx.meshes_of(body):
		var world: AABB = mesh.global_transform * mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return 0.0 if first else box.position.y + box.size.y


func _done() -> void:
	if _failed == 0:
		print("피격 이펙트: 통과")
		quit(0)
	else:
		print("피격 이펙트: %d개 실패" % _failed)
		quit(1)
