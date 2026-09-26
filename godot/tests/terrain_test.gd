extends SceneTree

## 지형 — 높낮이와 바닥 섞기 (`game/terrain.gd`).
##
## 생김새는 눈으로 봐야 하지만, 발이 땅에 붙는지 · 광장이 평평한지 · 언덕이
## 끝에 선 캐릭터를 가리지 않는지 · 섞기 그림 끝이 풀인지는 글로 잰다.
##
##   godot --headless --path godot --script tests/terrain_test.gd

## 카메라 시선의 기울기 (피치 42도 → tan 0.9). 언덕이 이보다 가파르면 끝에 선
## 캐릭터가 언덕 뒤로 숨는다
const SIGHT_SLOPE := 0.9

var _failed := 0


func _init() -> void:
	var started := Time.get_ticks_msec()
	var t := Terrain.build("village")
	var took := Time.get_ticks_msec() - started
	if t == null:
		_fail("마을에 지형이 없다")
		_finish()
		return
	print("  마을 지형 짓기 %dms" % took)
	if took > 1500:
		_fail("지형 짓기가 %dms — 존을 옮길 때마다 멈칫한다" % took)

	_case_no_terrain()
	_case_plaza_flat(t)
	_case_walkable(t)
	_case_rim(t)
	_case_mesh_matches(t)
	_case_ray(t)
	_case_splat(t)
	_case_material(t)
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("지형: 전부 통과")
		quit(0)
	else:
		print("지형: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_no_terrain() -> void:
	# 사냥터는 아직 평평한 한 장이다 — 지형은 마을부터
	if Terrain.build(str(GameData.zones().get("fieldOrder", ["x"])[0])) != null:
		_fail("사냥터에 지형이 생겼다 — 아직 마을만이다")


func _case_plaza_flat(t: Terrain) -> void:
	# NPC·차원문·도착 지점은 광장 위라 평평해야 한다 — 모델이 비스듬한 땅에 서면
	# 한쪽 발이 묻힌다
	var zone := GameData.zone("village")
	var spots: Array = [Vector2.ZERO]
	var gate: Array = zone.get("gate", {}).get("position", [0, 0])
	spots.append(Vector2(gate[0], gate[1]))
	for npc in zone.get("npcs", []):
		if Vector2(npc.x, npc.z).length() < float(Terrain.RECIPES.village.plaza):
			spots.append(Vector2(npc.x, npc.z))
	for p in spots:
		var h := t.height_at(p.x, p.y)
		if absf(h) > 0.02:
			_fail("광장 %s 의 높이가 %.2f — 평평해야 한다" % [p, h])


func _case_walkable(t: Terrain) -> void:
	# 걸어 다니는 땅은 완만하다 — 굴곡 ±bumps, 기울기는 시선보다 한참 눕게
	var bumps := float(Terrain.RECIPES.village.bumps)
	var lo := 1e6
	var hi := -1e6
	var steepest := 0.0
	var x := -29.0
	while x <= 29.0:
		var z := -29.0
		while z <= 29.0:
			var h := t.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			steepest = maxf(steepest, absf(t.height_at(x + 0.5, z) - h) / 0.5)
			steepest = maxf(steepest, absf(t.height_at(x, z + 0.5) - h) / 0.5)
			z += 0.5
		x += 0.5
	print("  걷는 땅 높이 %.2f ~ %.2f, 가장 가파른 기울기 %.2f" % [lo, hi, steepest])
	if lo < -bumps - 0.05 or hi > bumps + 0.05:
		_fail("걷는 땅이 굴곡(±%.1f)을 넘었다" % bumps)
	if steepest > 0.45:
		_fail("걷는 땅 기울기 %.2f — 걷는 게 비탈 오르기로 보인다" % steepest)
	if hi - lo < 0.4:
		_fail("걷는 땅 높낮이가 %.2f 뿐 — 평평한 것과 다르지 않다" % (hi - lo))


func _case_rim(t: Terrain) -> void:
	# 바깥 언덕 — 끝에서 솟고, 가장 가파른 곳도 카메라 시선보다 눕는다
	var top := t.height_at(Terrain.HALF - 1, 0)
	var steepest := 0.0
	var e := 29.0
	while e < Terrain.HALF - 1:
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var a := t.height_at(dir.x * e, dir.y * e)
			var b := t.height_at(dir.x * (e + 1.0), dir.y * (e + 1.0))
			steepest = maxf(steepest, b - a)
		e += 1.0
	print("  바깥 언덕 끝 높이 %.1fm, 가장 가파른 오르막 %.2f" % [top, steepest])
	if top < 8.0:
		_fail("바깥 언덕이 %.1fm 뿐 — 마을을 감싸지 못한다" % top)
	if steepest >= SIGHT_SLOPE:
		_fail("언덕 오르막 %.2f 가 시선(%.2f)보다 가파르다 — 끝에 선 캐릭터를 가린다" % [steepest, SIGHT_SLOPE])


func _case_mesh_matches(t: Terrain) -> void:
	# 발 높이는 메시 꼭짓점과 같아야 한다 — 다르면 발이 뜨거나 묻힌다
	var node := t.mesh_instance({})
	var verts: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for k in range(0, verts.size(), 97):
		var v: Vector3 = verts[k]
		worst = maxf(worst, absf(t.height_at(v.x, v.z) - v.y))
	# 꼭짓점 사이 — 삼각형 한가운데도 평면 위에 있어야 한다
	var mid := Vector3(-10.25, 0, 7.75)
	var tri: Variant = Geometry3D.ray_intersects_triangle(
		Vector3(mid.x, 100, mid.z), Vector3.DOWN,
		Vector3(-11, t.height_at(-11, 7), 7), Vector3(-10, t.height_at(-10, 7), 7),
		Vector3(-10, t.height_at(-10, 8), 8)
	)
	if tri != null:
		worst = maxf(worst, absf(tri.y - t.height_at(mid.x, mid.z)))
	node.free()
	if worst > 0.001:
		_fail("발 높이와 메시가 %.3fm 어긋난다" % worst)


func _case_ray(t: Terrain) -> void:
	# 화면을 누른 곳 = 땅. 카메라처럼 42도로 내려다보는 광선으로 잰다
	var dir := Vector3(-1, -1.35, -1).normalized()
	for aim in [Vector2(-14, 9), Vector2(22, -20), Vector2(5, 25)]:
		var ground := Vector3(aim.x, t.height_at(aim.x, aim.y), aim.y)
		var from := ground - dir * 30.0
		var hit := t.ray_hit(from, dir)
		if hit == Vector3.INF or Vector2(hit.x - aim.x, hit.z - aim.y).length() > 0.1:
			_fail("누른 곳 %s 이 %s 로 잡혔다" % [aim, hit])


func _case_splat(t: Terrain) -> void:
	var at_center := t._weights(0, 0)
	if at_center.x < 0.95:
		_fail("광장 가운데가 돌판이 아니다 (%s)" % at_center)
	var road: Array = Terrain.RECIPES.village.roads[0]
	var on_road := t._weights(float(road[1][0]), float(road[1][1]))
	if on_road.y < 0.9:
		_fail("길 위가 자갈이 아니다 (%s)" % on_road)
	# 섞기 그림의 가장자리는 그림 밖으로 늘어난다 — 풀이 아니면 줄무늬가 생긴다
	var worst := 0.0
	var e := Terrain.SPLAT_HALF - 0.2
	var s := -e
	while s <= e:
		for p in [Vector2(s, e), Vector2(s, -e), Vector2(e, s), Vector2(-e, s)]:
			var w := t._weights(p.x, p.y)
			worst = maxf(worst, w.x + w.y + w.z)
		s += 0.5
	if worst > 0.01:
		_fail("섞기 그림 가장자리에 풀 아닌 것이 %.2f 섞였다" % worst)


func _case_material(t: Terrain) -> void:
	var node := t.mesh_instance(GameData.zone("village").get("env", {}))
	var mat := node.material_override
	if not (mat is ShaderMaterial):
		_fail("지형 재질이 셰이더가 아니다 — 텍스처를 못 찾았다 (npm run sync:godot)")
	else:
		for k in Terrain.LAYERS.size():
			if mat.get_shader_parameter("albedo%d" % k) == null:
				_fail("%s 층 텍스처가 없다" % Terrain.LAYERS[k])
	node.free()
