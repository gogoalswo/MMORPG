extends SceneTree

## 바닥 재질 — 텍스처·타일 크기·존 틴트.
##
## 바닥은 원래 **눈으로 봐야 하는 것**이지만(world-zones.md), 색을 정하는 계산은
## 글로 확인할 수 있다. 기준값은 ground.ts 와 같은 식을 node 로 돌려 뽑았다
## (2026-09-17).
##
##   godot --headless --path godot --script tests/ground_test.gd

const Game := preload("res://game/game.gd")

var _failed := 0


func _init() -> void:
	_case_textures()
	_case_looks()
	_case_tint()
	_case_material()
	_case_contrast()
	_case_fog()

	if _failed == 0:
		print("바닥: 전부 통과")
		quit(0)
	else:
		print("바닥: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_textures() -> void:
	# 일곱 장을 전부 넣는다 — 존마다 받으면 존 구성이 비동기가 된다
	var kinds: Array = GameData.zones().get("groundKinds", [])
	if kinds.size() != 7:
		_fail("바닥 종류가 7종이어야 하는데 %d종" % kinds.size())
	var missing: Array = []
	for kind in kinds:
		for suffix in ["color", "normal"]:
			var path := "res://assets/ground/ground_%s_%s.ktx2" % [kind, suffix]
			if not ResourceLoader.exists(path):
				missing.append(path.get_file())
	if not missing.is_empty():
		_fail("없는 텍스처: %s — npm run sync:godot 을 돌렸나" % str(missing))
	else:
		var sample: Texture2D = load("res://assets/ground/ground_grass_color.ktx2")
		print("  텍스처 %d종 x 2장, 풀 %dx%d" % [kinds.size(), sample.get_width(), sample.get_height()])


func _case_looks() -> void:
	# 텍스처 성질은 shared 의 GROUND_LOOKS 에서 온다 — 두 클라이언트가 같은 값을 쓴다
	var looks: Dictionary = GameData.zones().get("groundLooks", {})
	for kind in GameData.zones().get("groundKinds", []):
		if not looks.has(kind):
			_fail("%s 의 성질이 없다" % kind)
			return
	# 모양이 뚜렷한 것은 섞지 않는다 — 섞으면 판석이 두 겹으로 비친다
	for kind in ["stone", "cobble", "lava"]:
		if float(looks[kind].blend) != 0.0:
			_fail("%s 의 blend 가 0 이 아니다" % kind)
	if float(looks.lava.glow) <= 0.0:
		_fail("용암이 안 빛난다")
	print("  성질: 돌판 타일 %.0fm · 자갈 %.0fm · 용암 %.0fm" % [
		looks.stone.tile, looks.cobble.tile, looks.lava.tile
	])


## 무늬가 얼마나 또렷해지는지. 텍스처 자체는 대비가 있는데(돌판은 밝기 폭이 6배)
## 화면에서 희미하다는 지적을 받아 셰이더에서 벌린다 (2026-09-17)
func _case_contrast() -> void:
	var mat := Ground.material_for(GameData.zone("village").env, 92.0)
	if not (mat is ShaderMaterial):
		_fail("마을 바닥이 셰이더 재질이 아니다")
		return
	var sm := mat as ShaderMaterial
	var contrast := float(sm.get_shader_parameter("contrast"))
	if contrast <= 1.0:
		_fail("대비가 1.0 이하다 — 벌리지 않으면 무늬가 희미하다")
	if float(sm.get_shader_parameter("normal_depth")) <= 1.0:
		_fail("노멀 세기가 1.0 이하다")
	# 평균색을 축으로 벌리므로 평균 밝기는 그대로다.
	# 돌판 텍스처의 어두운 쪽(선형 0.016)과 밝은 쪽(0.102)이 얼마나 벌어지나
	var mean: Color = sm.get_shader_parameter("mean_color")
	var m := 0.299 * mean.r + 0.587 * mean.g + 0.114 * mean.b
	var lo: float = m * pow(0.016 / m, contrast)
	var hi: float = m * pow(0.102 / m, contrast)
	print("  돌판 밝기 폭 %.1f배 -> %.1f배 (대비 %.2f · 노멀 %.1f)" % [
		0.102 / 0.016, hi / lo, contrast, float(sm.get_shader_parameter("normal_depth"))
	])


## 안개가 바닥 무늬를 씻지 않는지. 안개는 곱이 아니라 더하기라, 카메라 거리에
## 걸리면 돌 틈처럼 어두운 데가 그대로 들려 무늬가 사라진다 (2026-09-18)
func _case_fog() -> void:
	var env: Dictionary = GameData.zone("village").env
	var e: Environment = Game.environment_for(env)
	if e.fog_mode != Environment.FOG_MODE_DEPTH:
		_fail("안개가 깊이 안개가 아니다 — 지수 안개는 카메라 앞부터 낀다")
		return
	var near := float(env.get("fogNear", 70))
	if absf(e.fog_depth_begin - near) > 1e-6:
		_fail("안개 시작이 %.0fm 여야 하는데 %.0fm" % [near, e.fog_depth_begin])
	# 카메라는 초점에서 이만큼 떨어져 있다. 바닥은 그보다 가까이도 온다
	if CameraRig.DISTANCE >= e.fog_depth_begin:
		_fail("카메라 거리 %.1fm 가 안개 시작 %.0fm 안에 있다" % [
			CameraRig.DISTANCE, e.fog_depth_begin])
	else:
		print("  안개 %.0f~%.0fm (카메라 거리 %.1fm — 바닥에는 안 낀다)" % [
			e.fog_depth_begin, e.fog_depth_end, CameraRig.DISTANCE])


func _case_tint() -> void:
	# ground.ts 와 같은 식이어야 한다 (선형에서 비율, TINT_PULL 0.5, ALBEDO 0.3)
	var cases := [
		["village", Vector3(0.4127, 0.3984, 0.3553)],
		["meadow", Vector3(0.5250, 0.4476, 0.5105)],
		["saltflat", Vector3(0.3999, 0.5171, 0.5250)],
	]
	for row in cases:
		var zone := GameData.zone(str(row[0]))
		var env: Dictionary = zone.env
		var look := Ground.look_of(str(env.ground))
		var got := Ground.tint_for(str(env.groundTint), str(look.mean)) * Ground.ALBEDO
		var want: Vector3 = row[1]
		if (absf(got.r - want.x) > 0.001 or absf(got.g - want.y) > 0.001
				or absf(got.b - want.z) > 0.001):
			_fail("%s 틴트가 (%.4f, %.4f, %.4f) 여야 하는데 (%.4f, %.4f, %.4f)" % [
				row[0], want.x, want.y, want.z, got.r, got.g, got.b
			])
		else:
			print("  %s 틴트 (%.3f, %.3f, %.3f)" % [row[0], got.r, got.g, got.b])


func _case_material() -> void:
	var zone := GameData.zone("meadow")
	var size := float(zone.size)
	var mat := Ground.material_for(zone.env, size)
	if not (mat is ShaderMaterial):
		_fail("바닥이 셰이더 재질이 아니다 — 대비·아니소트로픽을 못 준다")
		return
	var sm := mat as ShaderMaterial
	if sm.get_shader_parameter("albedo_tex") == null:
		_fail("텍스처가 안 붙었다")
		return
	if not bool(sm.get_shader_parameter("has_normal")) or sm.get_shader_parameter("normal_tex") == null:
		_fail("노멀이 안 붙었다")
	# 초원 92m, 풀 타일 4m -> 23번 반복
	var want := size / float(Ground.look_of("grass").tile)
	var tiling: Vector2 = sm.get_shader_parameter("tiling")
	if absf(tiling.x - want) > 1e-6:
		_fail("반복이 %.1f 여야 하는데 %.1f" % [want, tiling.x])
	else:
		print("  초원 %.0fm 에 풀 타일 %.0fm -> %.0f번 반복" % [
			size, Ground.look_of("grass").tile, tiling.x
		])
