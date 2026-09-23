extends SceneTree

## 빙주각(`frost_pillar`) 이펙트 — **밟은 자리 사방에서 얼음 기둥이 고리로 솟는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — `npm run shot:godot -- frost_pillar 3,8,14,40,160,200`
## 로 찍어서 눈으로 본다 → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/ice_fx_test.gd

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
	_case_layout()
	_case_rise()
	await _case_once(game)
	await _case_other_skill(game)
	await _case_gone(game)
	_done()


## 액션바의 빙주각을 누르면 이펙트가 서고 화면이 흔들린다 — **실제 경로로 쏜다.**
## Lv.40 스킬이라 레벨과 포인트를 직접 올린다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 40
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "frost_pillar"})
	game._transport.send(&"setSkillBar", {"bar": ["frost_pillar"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("frost_pillar" in me.get("skill_bar", [])):
		_fail("액션바에 빙주각이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "frost_pillar"})
	for i in 4:
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("빙주각을 썼는데 이펙트가 안 섰다")
		return
	if game._camera._shake_left <= 0.0:
		_fail("빙주각을 썼는데 화면이 안 흔들린다")
	for e: CPUParticles3D in [fx._burst, fx._mist]:
		if not e.emitting:
			_fail("솟을 때 켜질 방출기가 안 켜졌다")
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")


## 기둥 배치 — **사방**에 서고, **판정 사거리 안**이고, 안쪽부터 **차례로** 솟는다
func _case_layout() -> void:
	var reach := float(Skills.get_skill("fighter", "frost_pillar").get("range", 0.0))
	if reach <= 0.0:
		_fail("판정 표에 빙주각이 없다")
		return
	var list := IceFx.crystals()
	var far := 0.0
	var quarters := {}
	var starts := {}
	var first_ring := IceFx.RINGS[0][0] as float
	var last_ring := IceFx.RINGS[IceFx.RINGS.size() - 1][0] as float
	var inner_start := INF
	var outer_start := -INF
	for c in list:
		var base: Vector3 = c[0]
		var axis: Vector3 = c[1]
		var tip := base + axis * float(c[2])
		far = maxf(far, Vector2(tip.x, tip.z).length())
		quarters[int(floor((atan2(base.x, base.z) + PI) / (PI / 2.0))) % 4] = true
		starts[snappedf(float(c[4]), 0.001)] = true
		var r := Vector2(base.x, base.z).length()
		if absf(r - first_ring) < 0.4:
			inner_start = minf(inner_start, float(c[4]))
		if absf(r - last_ring) < 0.4:
			outer_start = maxf(outer_start, float(c[4]))
		if axis.y < cos(deg_to_rad(IceFx.TILT_MAX + 25.0)):
			_fail("결정이 %.0f° 나 누웠다 — 기둥이 아니라 가시다" % rad_to_deg(acos(axis.y)))
			break
	if far > reach:
		_fail("기둥 끝이 %.2fm 까지 닿는다 — 사거리 %.1fm 밖까지 맞는 것으로 읽힌다" % [far, reach])
	if quarters.size() < 4:
		_fail("기둥이 %d방향에만 선다 — 사방이 아니다" % quarters.size())
	if starts.size() < IceFx.RINGS.size():
		_fail("기둥이 %d번에 솟는다 — 한꺼번에 켜지면 얼음 숲 한 장이다" % starts.size())
	if not (inner_start < outer_start):
		_fail("바깥 고리가 안쪽보다 먼저 솟는다 — 밟은 힘이 퍼져 나가는 것으로 안 읽힌다")
	# 냉기·조각은 **기둥에서** 나온다 — 한가운데서 나오면 캐릭터가 뿜는 것으로 읽힌다
	var feet: PackedVector3Array = IceFx.emit_points(false)[0]
	var nearest := INF
	for p in feet:
		nearest = minf(nearest, Vector2(p.x, p.z).length())
	if feet.size() != IceFx.RINGS.reduce(func(n, r): return n + int(r[1]), 0):
		_fail("나오는 자리 %d곳 — 큰 결정마다 하나여야 한다" % feet.size())
	if nearest < first_ring - 0.4:
		_fail("냉기·조각이 한가운데(%.1fm)에서 나온다 — 기둥에서 나와야 한다" % nearest)
	print("  결정 %d개 · 고리 %d겹 · 끝 %.2fm (사거리 %.0fm) · 안 %.2fs → 밖 %.2fs" % [
		list.size(), IceFx.RINGS.size(), far, reach, inner_start, outer_start])


## 솟기 — 셰이더와 같은 식으로 기둥 끝 높이를 따라가 본다. 처음엔 **땅속**,
## 다 솟으면 **땅 위**, 끝나면 **도로 땅속**이다. 이펙트 수명이 기둥보다 길어야 한다
func _case_rise() -> void:
	var c: Array = IceFx.crystals()[0]
	var total := float(c[2]) + IceFx.SUNK
	var start := float(c[4])
	var tip_at := func(now: float) -> float:
		var t := clampf((now - start) / IceFx.RISE, 0.0, 1.0) - 1.0
		var up := 1.0 + 2.70158 * t * t * t + 1.70158 * t * t
		var s := clampf((now - start - IceFx.RISE - IceFx.HOLD) / IceFx.SINK, 0.0, 1.0)
		var lift := up - s * s
		var foot: Vector3 = c[0] - c[1] * IceFx.SUNK
		return (foot + c[1] * total * lift).y
	var before: float = tip_at.call(0.0)
	var peak: float = tip_at.call(start + IceFx.RISE + 0.2)
	var after: float = tip_at.call(IceFx.span())
	if before > 0.0:
		_fail("솟기 전에 기둥 끝이 땅 위(%.2fm)에 있다" % before)
	if peak < 1.0:
		_fail("다 솟은 기둥이 %.2fm 뿐이다" % peak)
	if after > 0.0:
		_fail("끝났는데 기둥이 땅 위(%.2fm)에 남았다 — 뚝 사라진다" % after)
	# 꺼진 뒤 지면 자국이 흐려진다 — 기둥보다 먼저 끝나면 뚝 끊긴다
	if IceFx.span() < IceFx.last_start() + IceFx.RISE + IceFx.HOLD + IceFx.SINK:
		_fail("이펙트가 기둥이 다 꺼지기 전에 끝난다")
	print("  기둥 끝 %.2f → %.2f → %.2fm · %.2f초" % [before, peak, after, IceFx.span()])


## 기둥 메시는 **한 번만** 깐다 — 쓸 때마다 깎으면 웹·폰에서 멈칫한다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := IceFx.burst(game._zone_node, Vector3.ZERO, 1.0)
	if fx._pillars.mesh != first._pillars.mesh:
		_fail("기둥 메시를 쓸 때마다 새로 깎는다")
	if absf(fx._pillars.rotation.y - 1.0) > 1e-4:
		_fail("기둥이 캐릭터가 보는 쪽으로 안 돌았다")
	var code: String = (fx._pillars.material_override as ShaderMaterial).shader.code
	if code.contains("blend_add") or code.contains("depth_test_disabled"):
		_fail("기둥이 가산이거나 깊이 검사를 끈다 — 땅속 부분이 바닥을 뚫고 보인다")
	fx.queue_free()
	await process_frame


func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "tiger_roar", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("호포각에 빙주각 이펙트가 떴다")


func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 600:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


func _newest(game: Node3D) -> IceFx:
	if game._fx == null:
		return null
	var found: IceFx = null
	for child in game._fx.get_children():
		if child is IceFx and FxPool.busy(child):
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._fx == null:
		return 0
	var n := 0
	for child in game._fx.get_children():
		if child is IceFx and FxPool.busy(child):
			n += 1
	return n


func _done() -> void:
	if _failed == 0:
		print("빙주각 이펙트: 통과")
		quit(0)
	else:
		print("빙주각 이펙트: %d개 실패" % _failed)
		quit(1)
