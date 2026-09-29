extends SceneTree

## 덤불숲 — 흙 지형(`terrain.gd` 의 "thicket"). 풀·나무·돌 꾸밈은 2026-09-29 에 전부 뺐다.
##
## 생김새는 찍어서 본다(`npm run shot:godot -- scene`). 여기서는 글로 잴 수 있는 것만 —
## 차원문·도착 지점이 평평한지, 바닥이 흙 한 장인지, 이동 끝 너머가 검은지.
##
##   godot --headless --path godot --script tests/thicket_test.gd

const ZONE := "thicket"

var _failed := 0


func _init() -> void:
	var t := Terrain.build(ZONE)
	if t == null:
		_fail("덤불숲에 지형이 없다")
		_finish()
		return
	var zone := GameData.zone(ZONE)
	_case_flats(t, zone)
	_case_soil(t, zone)
	_case_village()
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


func _case_soil(t: Terrain, zone: Dictionary) -> void:
	# 바닥은 흙 한 장 (2026-09-29 "스크린샷처럼") — 섞기 그림이 어디든 0 번 층(흙)이다
	var worst := 0.0
	var x := -12.0
	while x <= 12.0:
		var z := -12.0
		while z <= 12.0:
			var w := t.ground_mix(x, z)
			worst = maxf(worst, w.x + w.y + w.z)
			z += 1.0
		x += 1.0
	if worst > 0.01:
		_fail("걷는 땅에 흙 아닌 층이 %.2f 섞였다" % worst)
	var node := t.mesh_instance(zone.get("env", {}))
	var mat := node.material_override
	if not (mat is ShaderMaterial):
		_fail("덤불숲 바닥이 셰이더가 아니다 — 흙 텍스처를 못 찾았다 (npm run sync:godot)")
	else:
		var tex = mat.get_shader_parameter("albedo0")
		if tex == null or not str(tex.resource_path).contains("soil"):
			_fail("덤불숲 바닥 0 번 층이 흙이 아니다 (%s)" % tex)
		# 이동 끝 너머는 검은 바닥 — 선이 판정의 이동 끝과 같아야 누른 곳과 맞는다
		var walk := Movement.zone_half_size(float(zone.get("size", 66)))
		var edge = mat.get_shader_parameter("void_edge")
		if edge == null or absf(float(edge) - walk) > 0.001:
			_fail("검은 바닥 선이 %s — 이동 끝(%.1f)과 같아야 한다" % [edge, walk])
	node.free()


func _case_village() -> void:
	# 마을 바닥에는 풀빛 얼룩이 없다 — 알파가 가운데
	var v := Terrain.build("village")
	if absf(v._shade(3, 3) - 0.5) > 0.001:
		_fail("마을 바닥에 풀빛 얼룩이 들었다")
