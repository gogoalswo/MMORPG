class_name KiFx
extends Node3D

## 파천장(`ki_burst`) 연출 — **손바닥을 내지르면 기가 앞으로 휘몰아친다.**
##
## 2026-09-28 요청, 사용자가 준 스크린샷(흰·금빛 소용돌이 호가 겹겹이 앞으로 퍼지고,
## 먹선 같은 검은 호가 그 사이를 감고, 가는 흰 빛살이 앞으로 튀고, 모래 먼지가 인다)을
## 조각으로 나눠 짓는다:
##
## | 무엇 | 어떻게 |
## |---|---|
## | 소용돌이 호 | 앞축을 감는 나선 띠 여덟. 손바닥에서 작게 나와 앞으로 가며 커지고 돈다 (3겹 가산) |
## | 먹선 | 같은 나선을 검고 가늘게 셋 — 밝은 모래 바닥에서 가산 빛만으로는 흐려서 윤곽을 준다 |
## | 빛살 | 앞 부채꼴로 뻗는 곧은 선 마흔 개가 한 메시다. 짧은 토막이 선을 따라 앞으로 달린다 |
## | 먼지 · 알갱이 · 섬광 | 모래 먼지(알파) · 금빛 알갱이(가산) · 손바닥의 번쩍임(제자리에서 사그라든다) |
##
## 띠는 전부 **할퀴기 셰이더**(`SkillFx.CLAW_SHADER`)를 쓴다 — 메시는 게임 전체에서 한 번만
## 깔고, 셰이더가 `head`·`tail` 사이만 벌린다. 방향은 캐릭터 기준이다(루트를 보는 쪽으로 돌린다).
## 판정 사거리(6m) 안에서 끝난다 — `REACH`. 거리는 2026-09-29 에 1.5배로 늘렸다 (요청).
## 이펙트는 판정 시각(스킬 표의 `delayMs`)에 선다 — 주먹을 내지르고 0.2초 멈춘 뒤다.

## 손바닥 높이 · 몸 앞 거리 (발밑 기준)
const HEIGHT := 1.15
const PALM := 0.55
## 가장 먼 것이 닿는 곳 (발밑에서 앞으로). 판정 사거리 6m 안 (처음 3.8m 의 1.5배)
const REACH := 5.7

## 소용돌이 — 여덟 개가 `SWIRL_GAP` 씩 늦게 나온다
const SWIRLS := 12
const SWIRL_GAP := 0.025
const SWIRL_DELAY := 0.04
## 앞으로 나가는 시간 · 그리는 시간 · 머무는 시간 · 사그라드는 시간
## 거리를 1.5배로 늘리며 0.42 → 0.55 — 같은 시간이면 너무 빨라 한 번에 튄다
const TRAVEL := 0.55
const DRAW := 0.2
const HOLD := 0.08
const FADE := 0.26
## 띠가 한 번에 보이는 길이 (나선 전체를 1 로 친다)
const SWIRL_TRAIL := 0.8
## 도는 양(rad) — 앞으로 가는 동안
const SPIN := 1.3
const SWIRL_SEGMENTS := 48
## 소용돌이마다: 멈추는 거리(발밑에서 앞으로) · 감는 각 · 판 기울기 · 시작 각 · 도는 쪽
## 나선은 제 반지름의 `SWIRL_DEPTH` 배만큼 앞으로 깊다 — 가장 먼 것도 끝이 3.9m 다 (사거리 4m)
const SWIRL_Z: Array[float] = [2.1, 3.9, 2.85, 4.65, 2.4, 4.2, 3.3, 4.95, 1.8, 3.6, 4.4, 2.6]
const SWIRL_SWEEP: Array[float] = [4.2, 3.6, 4.6, 3.9, 3.4, 4.4, 3.8, 4.0, 3.2, 4.5, 3.7, 4.1]
const SWIRL_TILT: Array[float] = [0.12, -0.18, 0.22, -0.08, 0.3, -0.26, 0.05, 0.16, -0.3, 0.2, -0.12, 0.26]
const SWIRL_ROLL: Array[float] = [0.0, 2.4, 4.8, 1.1, 3.5, 5.9, 2.0, 4.1, 5.3, 0.7, 3.0, 1.6]
const SWIRL_SPIN: Array[float] = [1.0, -1.0, 1.0, 1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0, -1.0]
const SWIRL_DEPTH := 0.3
## 손바닥에서 나올 때의 반지름 · 앞으로 갈수록 커지는 정도 · 상한.
## 참고 그림의 소용돌이는 캐릭터 키만 하다 — 1.2m 로는 화면에서 손바닥 크기였다 (1차 시안)
const RADIUS_START := 0.3
const RADIUS_BASE := 0.25
const RADIUS_PER_M := 0.42
const RADIUS_MAX := 1.65
## 3겹 — 넓은 금빛 헤일로 · 옅은 금빛 · 흰 심 (규칙 5절).
## 참고 그림은 흰 띠가 굵게 번져 있다 — 1차 시안(0.42 · 0.16 · 0.05)은 실처럼 보였다
const SWIRL_LAYERS := [
	[0.75, Color(1.0, 0.78, 0.38, 0.38)],
	[0.3, Color(1.0, 0.95, 0.78, 0.8)],
	[0.09, Color(1.0, 1.0, 1.0, 1.0)],
]

## 먹선 — 소용돌이 몇 번의 나선을 조금 크게, 다른 각으로 다시 쓴다
const INKS: Array[int] = [1, 3, 5, 9]
const INK_SCALE := 1.1
const INK_ROLL := 1.3
const INK_WIDTH := 0.09
const COLOR_INK := Color(0.07, 0.05, 0.04, 0.8)

## 빛살 — 앞 부채꼴의 곧은 선들
const STREAKS := 56
const STREAK_SEGMENTS := 16
const STREAK_DELAY := 0.03
## 토막이 선 끝까지 달리는 시간
const STREAK_TIME := 0.7
## 토막 길이 (선 하나를 1 로 친다)
const STREAK_TRAIL := 0.4
## 선마다 늦게 출발하는 폭 (선 길이 단위)
const STREAK_STAGGER := 0.9
const STREAK_LAYERS := [
	[0.1, Color(1.0, 0.82, 0.45, 0.5)],
	[0.03, Color(1.0, 1.0, 1.0, 1.0)],
]

const FLASH_SIZE := 1.8
const FLASH_LIFE := 0.22
const COLOR_FLASH := Color(1.0, 0.93, 0.72)

const DUST_COUNT := 28
const DUST_LIFE := 1.0
const COLOR_DUST := Color(0.93, 0.86, 0.7)
## 기운 뭉치 — 참고 그림의 소용돌이 속 흰 덩어리. 빛이라 가산이다
const AURA_COUNT := 16
const AURA_LIFE := 0.6
const COLOR_AURA := Color(1.0, 0.94, 0.78)
const MOTE_COUNT := 36
const MOTE_LIFE := 0.5
const COLOR_MOTE := Color("#ffe3a0")

## 화면 흔들림 — 낙뢰·빙주각보다 약하다 (땅을 치는 게 아니라 앞으로 쏜다)
const SHAKE := 0.07
const SHAKE_TIME := 0.18

static var _swirl_meshes: Array = []
static var _streak_mesh: ArrayMesh
static var _ink_shader: Shader

var _t := 0.0
## 손바닥 자리 (소용돌이·빛살·섬광이 여기서 나온다)
var _palm: Node3D
## 소용돌이 하나 = {node, layers: [ShaderMaterial…], delay, index, ink}
var _swirls: Array = []
var _streaks: Array = []
var _flash: MeshInstance3D
var _dust: CPUParticles3D
var _motes: CPUParticles3D
var _aura: CPUParticles3D


## 파천장을 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다
static func burst(parent: Node3D, at: Vector3, facing: float) -> KiFx:
	var fx := FxPool.take(parent, &"ki") as KiFx
	if fx == null:
		fx = KiFx.new()
		fx.name = "KiFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 끝나는 시각(초) — 마지막 소용돌이가 사그라들고 먼지가 가라앉을 때
static func span() -> float:
	var swirl := SWIRL_DELAY + float(SWIRLS - 1) * SWIRL_GAP + DRAW + HOLD + FADE
	return maxf(maxf(swirl, STREAK_DELAY + STREAK_TIME), DUST_LIFE + 0.05)


## 소용돌이가 멈추는 자리의 반지름 — 앞으로 갈수록 넓어지는 원뿔
static func radius_at(z: float) -> float:
	return minf(RADIUS_BASE + z * RADIUS_PER_M, RADIUS_MAX)


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	_palm = Node3D.new()
	_palm.position = Vector3(0.0, HEIGHT, PALM)
	add_child(_palm)
	for i in SWIRLS:
		var layers: Array = []
		for layer in SWIRL_LAYERS:
			layers.append(SkillFx.claw_material(layer[0], layer[1]))
		_swirls.append(_swirl_node(i, layers, false))
	for i in INKS:
		_swirls.append(_swirl_node(i, [ink_material(INK_WIDTH, COLOR_INK)], true))
	for layer in STREAK_LAYERS:
		var mesh := MeshInstance3D.new()
		mesh.mesh = streak_mesh()
		mesh.material_override = SkillFx.claw_material(layer[0], layer[1])
		mesh.extra_cull_margin = 1.0
		mesh.visible = false
		_palm.add_child(mesh)
		_streaks.append({"node": mesh, "color": layer[1]})
	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	_flash.mesh = quad
	_flash.material_override = LightningFx.flare(COLOR_FLASH)
	_flash.visible = false
	_palm.add_child(_flash)
	_dust = _make_dust()
	add_child(_dust)
	_motes = _make_motes()
	_palm.add_child(_motes)
	_aura = _make_aura()
	_palm.add_child(_aura)


## 나선 하나를 겹 수만큼 — 겹은 같은 메시를 쓰고 재질(폭·색)만 다르다
func _swirl_node(i: int, materials: Array, ink: bool) -> Dictionary:
	var node := Node3D.new()
	node.visible = false
	_palm.add_child(node)
	for mat in materials:
		var mesh := MeshInstance3D.new()
		mesh.mesh = swirl_mesh(i)
		mesh.material_override = mat
		# 꼭짓점을 셰이더가 벌리므로 원래 상자(폭 0)보다 넉넉히 잡는다
		mesh.extra_cull_margin = 1.0
		node.add_child(mesh)
	var colors: Array = []
	for mat: ShaderMaterial in materials:
		colors.append(mat.get_shader_parameter(&"tint"))
	return {
		"node": node, "materials": materials, "colors": colors, "index": i, "ink": ink,
		# 먹선은 바로 곁 소용돌이보다 한 박자 늦다 — 흰 빛을 뒤따라 감긴다
		"delay": SWIRL_DELAY + float(i) * SWIRL_GAP + (0.05 if ink else 0.0),
	}


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	# 방향은 캐릭터 기준 — 루트를 보는 쪽으로 돌리면 +Z 가 정면이다
	rotation = Vector3(0.0, facing, 0.0)
	_t = 0.0
	for swirl in _swirls:
		(swirl.node as Node3D).visible = false
	for streak in _streaks:
		(streak.node as MeshInstance3D).visible = false
	_flash.visible = false
	# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
	_dust.restart()
	_motes.restart()
	_aura.restart()


func _process(delta: float) -> void:
	_t += delta
	for swirl in _swirls:
		_draw_swirl(swirl)
	_draw_streaks()
	_draw_flash()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"ki")


## 소용돌이 하나를 지금 시각에 맞춘다 — 앞으로 가며 커지고 돌고, 그려졌다 사그라든다
func _draw_swirl(swirl: Dictionary) -> void:
	var node: Node3D = swirl.node
	var s := _t - float(swirl.delay)
	if s < 0.0:
		node.visible = false
		return
	var i: int = swirl.index
	var e := SkillFx._ease_out(clampf(s / TRAVEL, 0.0, 1.0))
	var stop := SWIRL_Z[i]
	var radius := lerpf(RADIUS_START, radius_at(stop), e)
	var roll := SWIRL_ROLL[i] + SWIRL_SPIN[i] * SPIN * e
	if bool(swirl.ink):
		radius *= INK_SCALE
		roll += INK_ROLL
	node.position = Vector3(0.0, 0.0, lerpf(0.0, stop - PALM, e))
	node.scale = Vector3.ONE * radius
	node.rotation = Vector3(SWIRL_TILT[i], 0.0, roll)

	var head := SkillFx._ease_out(clampf(s / DRAW, 0.0, 1.0))
	var tail := maxf(0.0, head - SWIRL_TRAIL)
	var fade := clampf((s - DRAW - HOLD) / FADE, 0.0, 1.0)
	# 사그라들 때 꼬리가 머리 쪽으로 모인다 — 제자리에서 옅어지기만 하면 "그림 한 장" 이 된다
	if fade > 0.0:
		tail = lerpf(tail, head, SkillFx._ease_out(fade) * 0.85)
	var alpha := 1.0 - fade * fade
	node.visible = alpha > 0.01 and head - tail > 0.01
	if not node.visible:
		return
	for k in swirl.materials.size():
		var mat: ShaderMaterial = swirl.materials[k]
		var c: Color = swirl.colors[k]
		mat.set_shader_parameter(&"head", head)
		mat.set_shader_parameter(&"tail", tail)
		mat.set_shader_parameter(&"tint", Color(c.r, c.g, c.b, c.a * alpha))


## 빛살 — 짧은 토막이 선마다 조금씩 늦게 출발해 앞으로 달린다
func _draw_streaks() -> void:
	var s := _t - STREAK_DELAY
	var end := STREAK_STAGGER + 1.0 + STREAK_TRAIL
	var p := clampf(s / STREAK_TIME, 0.0, 1.0)
	var head := end * p
	var tail := head - STREAK_TRAIL
	for streak in _streaks:
		var node: MeshInstance3D = streak.node
		node.visible = s > 0.0 and p < 1.0
		if not node.visible:
			continue
		var mat: ShaderMaterial = node.material_override
		var c: Color = streak.color
		mat.set_shader_parameter(&"head", head)
		mat.set_shader_parameter(&"tail", tail)
		mat.set_shader_parameter(&"tint", Color(c.r, c.g, c.b, c.a * (1.0 - p * p)))


## 손바닥의 번쩍임 — 퍼지지 않고 제자리에서 사그라든다 (규칙 3절)
func _draw_flash() -> void:
	var f := clampf(_t / FLASH_LIFE, 0.0, 1.0)
	_flash.visible = f < 1.0
	var mat: StandardMaterial3D = _flash.material_override
	mat.albedo_color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 1.0 - f)


## `i` 번째 나선 — **게임 전체에서 한 번만** 만든다. 반지름 1 기준으로 앞축(+Z)을 감으며
## 조금씩 벌어지고 앞으로 나간다. 꼭짓점 배치는 할퀴기 호(`SkillFx.arc_mesh`)와 같다 —
## 점마다 셋(바깥 · 가운데 · 바깥)이 같은 자리에 있고, `NORMAL` 은 나선의 진행 방향,
## `UV2.x` 는 나선 위 자리(0~1), `UV2.y` 는 벌리는 쪽이다
static func swirl_mesh(i: int) -> ArrayMesh:
	if _swirl_meshes.size() > i and _swirl_meshes[i] != null:
		return _swirl_meshes[i]
	var path := PackedVector3Array()
	var params := PackedFloat32Array()
	for p in SWIRL_SEGMENTS + 1:
		var u := float(p) / float(SWIRL_SEGMENTS)
		var a := SWIRL_SWEEP[i] * u
		var r := 0.8 + 0.3 * u
		path.append(Vector3(cos(a) * r, sin(a) * r * 0.85, SWIRL_DEPTH * u))
		params.append(u)
	var mesh := strip_mesh([path], [params], [1.0])
	if _swirl_meshes.size() <= i:
		_swirl_meshes.resize(i + 1)
	_swirl_meshes[i] = mesh
	return mesh


## 빛살 쉰여섯 개를 한 메시로 — 손바닥에서 앞 부채꼴(좌우 ±37°, 위아래 -16~18°)로 뻗는다.
## 선마다 `UV2.x` 를 조금씩 밀어 두면(`STREAK_STAGGER`) 셰이더의 `head` 하나로 늦게 출발한다.
## **끝이 판정 사거리 안이다** — 발밑 기준 `REACH` 에서 자른다
static func streak_mesh() -> ArrayMesh:
	if _streak_mesh != null:
		return _streak_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var paths: Array = []
	var params: Array = []
	var scales: Array = []
	for n in STREAKS:
		var yaw := rng.randf_range(-0.65, 0.65)
		var pitch := rng.randf_range(-0.28, 0.32)
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var start := dir * rng.randf_range(0.3, 1.35)
		var length := minf(rng.randf_range(2.4, 4.5), (REACH - PALM - start.z) / dir.z)
		var offset := rng.randf_range(0.0, STREAK_STAGGER)
		var path := PackedVector3Array()
		var param := PackedFloat32Array()
		for p in STREAK_SEGMENTS + 1:
			var v := float(p) / float(STREAK_SEGMENTS)
			path.append(start + dir * length * v)
			param.append(offset + v)
		paths.append(path)
		params.append(param)
		scales.append(rng.randf_range(0.6, 1.2))
	_streak_mesh = strip_mesh(paths, params, scales)
	return _streak_mesh


## 폭 0 인 띠 여럿을 한 메시로 (할퀴기 셰이더 규격)
static func strip_mesh(paths: Array, params: Array, scales: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for k in paths.size():
		var path: PackedVector3Array = paths[k]
		var param: PackedFloat32Array = params[k]
		var last := path.size() - 1
		var base := verts.size()
		for p in path.size():
			var dir := (path[mini(p + 1, last)] - path[maxi(p - 1, 0)]).normalized()
			for side in [-1.0, 0.0, 1.0]:
				verts.append(path[p])
				normals.append(dir)
				uvs.append(Vector2(0.5 + side * 0.5, float(p) / float(last)))
				uv2s.append(Vector2(param[p], side * float(scales[k])))
		for p in last:
			var a := base + p * 3
			var b := a + 3
			index.append_array([a, a + 1, b, b, a + 1, b + 1])
			index.append_array([a + 2, a + 1, b + 2, b + 2, a + 1, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 먹선 재질 — 할퀴기 셰이더에서 혼합만 알파로 바꾼다 (검은색은 가산으로 안 보인다)
static func ink_material(width: float, tint: Color) -> ShaderMaterial:
	if _ink_shader == null:
		_ink_shader = Shader.new()
		_ink_shader.code = SkillFx.CLAW_SHADER.replace("blend_add", "blend_mix")
	var mat := ShaderMaterial.new()
	mat.shader = _ink_shader
	mat.set_shader_parameter(&"streak", FxTex.streak())
	mat.set_shader_parameter(&"width", width)
	mat.set_shader_parameter(&"tint", tint)
	return mat


## 모래 먼지 — 발 앞에서 앞으로 밀려나며 부푼다. 흙이라 알파다 (규칙 1절)
func _make_dust() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = DUST_COUNT
	e.lifetime = DUST_LIFE
	e.one_shot = true
	e.explosiveness = 0.85
	e.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	e.mesh = quad
	e.position = Vector3(0.0, 0.3, 1.8)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(0.5, 0.2, 0.9)
	e.direction = Vector3(0.0, 0.35, 1.0)
	e.spread = 30.0
	# 멈추는 거리 = 속도² / (2 × 감속) — 가장 빠른 것도 사거리 안(발밑에서 5.8m 쯤)에서 선다
	e.initial_velocity_min = 2.0
	e.initial_velocity_max = 4.3
	e.damping_min = 3.0
	e.damping_max = 4.0
	e.gravity = Vector3(0.0, 0.3, 0.0)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -60.0
	e.angular_velocity_max = 60.0
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color = COLOR_DUST
	e.color_ramp = LightningFx.fade_ramp(COLOR_DUST, 0.45)
	var mat := LightningFx.mote(COLOR_DUST)
	# 색은 입자 색으로만 — 재질 색까지 두면 두 번 곱해져 진흙색이 된다 (천붕각에서 배웠다)
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = FxTex.puff()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.2
	e.material_override = mat
	return e


## 기운 뭉치 — 뭉게뭉게한 흰 덩어리가 손바닥에서 앞으로 밀려나며 부풀고 사그라든다
func _make_aura() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = AURA_COUNT
	e.lifetime = AURA_LIFE
	e.one_shot = true
	e.explosiveness = 0.7
	e.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	e.mesh = quad
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.2
	e.direction = Vector3(0.0, 0.0, 1.0)
	e.spread = 22.0
	# 멈추는 거리 = 속도² / (2 × 감속) ≈ 4.5m — 손바닥(0.55m)에서 사거리 안
	e.initial_velocity_min = 4.0
	e.initial_velocity_max = 7.4
	e.damping_min = 6.0
	e.damping_max = 7.0
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -120.0
	e.angular_velocity_max = 120.0
	e.scale_amount_curve = LightningFx.grow_curve(2.2)
	e.color = COLOR_AURA
	# 가산이라 겹치면 하얗게 탄다 — 0.55 에서 소용돌이를 덮는 흰 공이 됐다 (2차 시안)
	e.color_ramp = LightningFx.fade_ramp(COLOR_AURA, 0.2)
	var mat := LightningFx.mote(COLOR_AURA, true)
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = FxTex.puff()
	e.material_override = mat
	return e


## 금빛 알갱이 — 손바닥에서 앞 부채꼴로 튄다. 빛이라 가산이다
func _make_motes() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = MOTE_COUNT
	e.lifetime = MOTE_LIFE
	e.one_shot = true
	e.explosiveness = 0.9
	e.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	e.mesh = quad
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.15
	e.direction = Vector3(0.0, 0.1, 1.0)
	e.spread = 28.0
	e.initial_velocity_min = 4.0
	e.initial_velocity_max = 9.0
	e.damping_min = 8.0
	e.damping_max = 10.0
	e.scale_amount_curve = LightningFx.fade_curve()
	e.color = COLOR_MOTE
	e.color_ramp = LightningFx.fade_ramp(COLOR_MOTE)
	e.material_override = LightningFx.mote(COLOR_MOTE, true)
	return e
