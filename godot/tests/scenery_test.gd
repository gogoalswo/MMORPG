extends SceneTree

## 덤불숲 — 숲 지형(`terrain.gd` 의 "thicket")과 꾸밈(`game/scenery.gd`).
##
## 생김새는 찍어서 본다(`npm run shot:godot -- scene`). 여기서는 글로 잴 수 있는 것만 —
## 차원문·도착 지점이 평평한지, 걷는 땅 안의 꾸밈이 발목 높이인지, 카메라 쪽 끝 너머의
## 것이 끝에 선 캐릭터를 가리지 않는지, 섞기 그림 끝이 풀인지.
##
##   godot --headless --path godot --script tests/scenery_test.gd

const ZONE := "thicket"
## 걷는 땅 안에 두는 꾸밈의 최대 높이(m). 이보다 높으면 캐릭터가 뚫고 지나가는 게 보인다
const ANKLE := 0.75

var _failed := 0
var _terrain: Terrain = null


func _init() -> void:
	var started := Time.get_ticks_msec()
	var t := Terrain.build(ZONE)
	_terrain = t
	if t == null:
		_fail("덤불숲에 지형이 없다")
		_finish()
		return
	var zone := GameData.zone(ZONE)
	var scenery := Scenery.build(ZONE, t, zone.get("env", {}))
	print("  덤불숲 지형 + 꾸밈 짓기 %dms" % (Time.get_ticks_msec() - started))
	if scenery == null:
		_fail("덤불숲에 꾸밈이 없다")
		_finish()
		return

	_case_flats(t, zone)
	_case_walkable(t)
	_case_splat_edge(t)
	_case_tufts(scenery, zone)
	_case_rocks(scenery)
	_case_sight(scenery)
	_case_void(t)
	_case_village()
	scenery.free()
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("덤불숲: 전부 통과")
		quit(0)
	else:
		print("덤불숲: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_flats(t: Terrain, zone: Dictionary) -> void:
	# 차원문과 도착 지점은 평평하게 — 문 모델이 비스듬한 땅에 서면 한쪽이 묻힌다
	var gate: Array = zone.get("gate", {}).get("position", [0, 0])
	for p in [Vector2.ZERO, Vector2(gate[0], gate[1])]:
		var h := t.height_at(p.x, p.y)
		if absf(h) > 0.02:
			_fail("%s 의 높이가 %.2f — 평평해야 한다" % [p, h])


func _case_walkable(t: Terrain) -> void:
	var e := float(Terrain.RECIPES[ZONE].rim)
	var steepest := 0.0
	var x := -e
	while x <= e:
		var z := -e
		while z <= e:
			var h := t.height_at(x, z)
			steepest = maxf(steepest, absf(t.height_at(x + 0.5, z) - h) / 0.5)
			steepest = maxf(steepest, absf(t.height_at(x, z + 0.5) - h) / 0.5)
			z += 0.5
		x += 0.5
	print("  걷는 땅 가장 가파른 기울기 %.2f" % steepest)
	if steepest > 0.45:
		_fail("걷는 땅 기울기 %.2f — 걷는 게 비탈 오르기로 보인다" % steepest)


func _case_splat_edge(t: Terrain) -> void:
	# 섞기 그림의 가장자리는 그림 밖으로 늘어난다 — 풀이 아니면 줄무늬가 생긴다.
	# 흙길 두 갈래가 언덕으로 빠지므로 여기서 걷혀야 한다
	var worst := 0.0
	var e := Terrain.SPLAT_HALF - 0.2
	var s := -e
	while s <= e:
		for p in [Vector2(s, e), Vector2(s, -e), Vector2(e, s), Vector2(-e, s)]:
			var w := t.ground_mix(p.x, p.y)
			worst = maxf(worst, w.x + w.y + w.z)
		s += 0.5
	if worst > 0.01:
		_fail("섞기 그림 가장자리에 풀 아닌 것이 %.2f 섞였다" % worst)
	# 흙길 위는 흙이다 (숲은 자갈이 아니다)
	var on := t.ground_mix(-6, -3)
	if on.z < 0.9 or on.y > 0.01:
		_fail("흙길 위가 흙이 아니다 (%s)" % on)


func _case_tufts(scenery: Node3D, zone: Dictionary) -> void:
	var tufts := Scenery.tuft_transforms(ZONE, _terrain)
	var node: MultiMeshInstance3D = scenery.get_node("Tufts")
	print("  풀포기 %d" % tufts.size())
	if node.multimesh.instance_count != tufts.size():
		_fail("풀포기 수가 다시 뽑은 것(%d)과 다르다 (%d)" % [tufts.size(), node.multimesh.instance_count])
	if tufts.size() < 1000:
		_fail("풀포기가 %d 뿐 — 바닥이 맨땅처럼 보인다" % tufts.size())
	var gate: Array = zone.get("gate", {}).get("position", [0, 0])
	var tallest_in := 0.0
	var at_gate := 0
	for xf: Transform3D in tufts:
		var p := xf.origin
		var tall := xf.basis.y.length()
		if maxf(absf(p.x), absf(p.z)) <= Scenery.WALK:
			tallest_in = maxf(tallest_in, tall)
		else:
			_fail("풀포기가 이동 끝 너머 %s 에 있다 — 검은 바닥 위에 뜬다" % p)
			break
		if Vector2(p.x - float(gate[0]), p.z - float(gate[1])).length() < 2.0:
			at_gate += 1
	print("  걷는 땅 안 가장 큰 풀포기 %.2fm" % tallest_in)
	if tallest_in > ANKLE:
		_fail("걷는 땅 안 풀포기가 %.2fm — 캐릭터가 덤불을 뚫고 지나간다" % tallest_in)
	if at_gate > 0:
		_fail("차원문 발치에 풀포기가 %d 개 — 문 받침을 뚫고 나온다" % at_gate)


## 꾸밈 하나의 월드 높이 (메시 경계 상자 기준)
func _height_of(node: Node3D) -> float:
	var box := Scenery._bounds(node) if not (node is MeshInstance3D) else (node as MeshInstance3D).get_aabb()
	var s := node.transform.basis.get_scale()
	return box.size.y * s.y


func _case_rocks(scenery: Node3D) -> void:
	var biggest_in := 0.0
	var rocks := 0
	for child in scenery.get_children():
		if child is MeshInstance3D:
			rocks += 1
			var p: Vector3 = child.position
			if maxf(absf(p.x), absf(p.z)) <= Scenery.WALK:
				biggest_in = maxf(biggest_in, _height_of(child))
			else:
				_fail("바위가 이동 끝 너머 %s 에 있다 — 검은 바닥 위에 뜬다" % p)
	print("  바위 %d개, 걷는 땅 안 가장 큰 것 %.2fm" % [rocks, biggest_in])
	if rocks < 10:
		_fail("바위가 %d 개 뿐" % rocks)
	if biggest_in > ANKLE:
		_fail("걷는 땅 안 바위가 %.2fm — 판정에 없는 벽처럼 보인다" % biggest_in)


func _case_sight(scenery: Node3D) -> void:
	# 카메라 쪽 끝(+x · +z) 너머는 끝에 선 캐릭터 앞이다 — 시선 기울기 아래여야 한다
	var worst := 0.0
	for child in scenery.get_children():
		if not (child is Node3D) or child is MultiMeshInstance3D:
			continue
		var p: Vector3 = child.position
		var past := Scenery._past_near_edge(p.x, p.z)
		if past > 0.0:
			worst = maxf(worst, _height_of(child) - past * Scenery.SIGHT)
	for xf: Transform3D in Scenery.tuft_transforms(ZONE, _terrain):
		var past := Scenery._past_near_edge(xf.origin.x, xf.origin.z)
		if past > 0.0:
			worst = maxf(worst, xf.basis.y.length() - maxf(0.25, past * Scenery.SIGHT))
	if worst > 0.05:
		_fail("카메라 쪽 끝 너머 꾸밈이 시선보다 %.2fm 높다 — 끝에 선 캐릭터를 가린다" % worst)


func _case_void(t: Terrain) -> void:
	# 이동 끝 너머는 검은 바닥 (2026-09-28 "해당 위치부터는 그냥 검은색") — 끝이 이동 끝과 같아야
	# 누르면 끝으로 당겨지는 선과 검은 선이 맞는다
	var node := t.mesh_instance(GameData.zone(ZONE).get("env", {}))
	var edge = node.material_override.get_shader_parameter("void_edge")
	if edge == null or absf(float(edge) - Scenery.WALK) > 0.001:
		_fail("검은 바닥 선이 %s — 이동 끝(%.1f)과 달라야 할 이유가 없다" % [edge, Scenery.WALK])
	node.free()


func _case_village() -> void:
	# 마을은 꾸밈이 없다 (RECIPES 에 없다) — 풀빛 얼룩도 없어서 알파가 가운데
	var v := Terrain.build("village")
	if Scenery.build("village", v, {}) != null:
		_fail("마을에 꾸밈이 생겼다")
	if absf(v._shade(3, 3) - 0.5) > 0.001:
		_fail("마을 바닥에 풀빛 얼룩이 들었다")
