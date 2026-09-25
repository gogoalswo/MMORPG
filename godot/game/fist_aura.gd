class_name FistAura
extends Node3D

## 무기(건틀릿)를 낀 주먹에 감도는 기운(오로라). **강화 +6 부터 나온다** —
## +5 까지는 없다. **색은 강화 단계가 정한다**: +6 초록 · +7 파랑 · +8 빨강 ·
## +9 하양 · +10 황금 (2026-09-25 요청: "등급에 따라서 오로라 색상을 바꾸지 말고
## 강화 단계에 따라서"). 그 전엔 등급 색이었다. 강화 한 단계마다 커지고(`GROW`),
## **좋은 무기일수록 겹이 는다** ("좋은 무기일수록 이펙트 더 화려하게"):
##
## | 등급 | 더해지는 것 |
## |---|---|
## | 1 일반 | 은은한 빛무리 하나 |
## | 2 고급 | + 피어오르는 불티 |
## | 3 희귀 | + 흰 심 (빛무리가 3겹이 된다) |
## | 4 영웅 | + 일렁이는 불꽃 |
## | 5 전설 | + 주먹을 도는 빛알 둘 |
## | 6 초월 | 빛알 셋, 불꽃·불티가 굵어진다 |
## | 7 태초 | 빛알 넷 + 주먹에서 뻗는 빛살 |
##
## 규칙(docs/features/effect-rules.md)대로 **코드로 짓고 텍스처는 `FxTex.glow` 를
## 굽는다.** 늘 켜져 있으므로 **깊이 검사를 켠다** — 끄면 몸 뒤로 돈 주먹의 빛이
## 몸을 뚫고 보인다. 빛은 모두 가산 혼합이다.
##
## 좌표는 **미터**다. `Rig.set_weapon` 이 주먹 소켓(모델 단위, 1.85배) 안에
## 두면서 배율을 되돌려 놓는다. 불티·불꽃은 **월드 좌표로 남아서** 주먹을
## 휘두르면 궤적처럼 흩어진다.

## 빛무리 지름(m) — 등급마다 이만큼 커진다
const HALO := 0.26
const HALO_STEP := 0.05
## 빛알이 도는 반지름(m)과 빠르기(rad/s)
const ORBIT_R := 0.15
const ORBIT_SPIN := 5.0
## 빛살 길이(m)
const RAY := 1.15
## 건틀릿 껍데기 반지름(m)쯤. 빛무리는 이만큼 카메라 쪽으로 당기고, 알갱이는
## 이 겉면에서 나온다 — 주먹 가운데에 두면 껍데기에 가려 안 보였다 (2026-09-25 찍어 봄)
const SHELL := 0.11
## 강화 한 단계마다 기운이 이만큼 커진다 (+9 면 1.9배). 2026-09-25 요청:
## "강화 수치에 따라 주먹에서 오로라가 커지게"
const GROW := 0.1

## 등급마다 재질을 한 벌만 짓는다 — 두 주먹·다시 낀 무기가 같이 쓰고, 살아 있는 동안
## 셰이더도 남는다 (FxWarm 의 "구운 셰이더가 남으려면")
static var _mats: Dictionary = {}

var _grade := 1
## 강화 단계 — 색을 정한다
var _enhance := FIRST
## 강화로 커진 배율 (1 = +0)
var _grow := 1.0
var _t := 0.0
## 빛무리·심을 담는 자리. 매 프레임 카메라 쪽으로 `SHELL` 만큼 당긴다
var _front: Node3D
var _halo: MeshInstance3D
var _core: MeshInstance3D
var _orbit: Node3D
var _rays: Node3D


## 오로라가 나오는 첫 강화 단계
const FIRST := 6
## 강화 단계별 색 (+6 ~ +10). 최대 강화가 +9 라 황금(+10)은 지금은 안 나온다.
## **하양만 알파를 낮춘다** — 가산이라 R·G·B 가 다 차 있는 하양은 겹치는 곳마다
## 하얗게 타서 태초 +9 가 주먹 둘레 전체가 흰 덩어리로 보였다 (2026-09-25 찍어 봄)
const COLORS := {
	6: Color("#46ff78"),
	7: Color("#3d8cff"),
	8: Color("#ff3838"),
	9: Color("#e8eeff", 0.5),
	10: Color("#ffc53a"),
}


## 이 강화 단계에 오로라가 나오나 (+5 까지는 없다)
static func shows(enhance: int) -> bool:
	return enhance >= FIRST


## 강화 단계의 오로라 색. 표보다 높으면 마지막 색
static func color(enhance: int) -> Color:
	return COLORS[clampi(enhance, FIRST, COLORS.keys().max())]


## 강화 배율 — +0 이 1, 한 단계마다 `GROW` 씩
static func grow(enhance: int) -> float:
	return 1.0 + GROW * maxi(enhance, 0)


static func build(grade: int, enhance := 0) -> FistAura:
	var aura := FistAura.new()
	aura.name = "FistAura"
	aura._grade = clampi(grade, 1, 7)
	aura._enhance = enhance
	aura._grow = grow(enhance)
	aura._build()
	return aura


func _build() -> void:
	var g := _grade
	var tint := color(_enhance)
	# 오르는 등급마다 진해진다
	var power := 0.5 + 0.07 * g
	# 강화로 커지는 것: 빛무리·심·알갱이 크기, 알갱이 수, 솟는 높이, 빛알 궤도, 빛살 길이.
	# 알갱이 수도 같이 늘려야 넓어진 기운이 성기지 않다
	var k := _grow

	_front = Node3D.new()
	add_child(_front)
	_halo = _sprite((HALO + HALO_STEP * g) * k, _mat("halo", tint * Color(1, 1, 1, power)), _front)
	if g >= 3:
		# 폭만 다른 3겹 — 넓은 빛무리 + 색 빛 + 가는 흰 심
		_sprite((HALO + HALO_STEP * g) * 0.55 * k, _mat("color", tint * Color(1, 1, 1, 0.7)), _front)
		_core = _sprite((0.08 + 0.012 * g) * k, _mat("core", tint.lerp(Color.WHITE, 0.6)), _front)
	if g >= 2:
		# 불티 — 작은 빛알이 흩어지며 오른다
		_particles("sparks", roundi((3 + 3 * g) * k), 0.75, (0.035 + 0.005 * g) * k, 0.45 * k, tint.lerp(Color.WHITE, 0.3))
	if g >= 4:
		# 불꽃 — 큰 뭉치가 빠르게 솟았다 사그라든다
		_particles("flame", roundi((6 + 4 * (g - 4)) * k), 0.5, (0.14 + 0.03 * (g - 4)) * k, 0.7 * k, tint * Color(1, 1, 1, 0.6))
	if g >= 5:
		_orbit = Node3D.new()
		add_child(_orbit)
		var count := g - 3
		for i in count:
			var angle := TAU * i / count
			var pivot := Node3D.new()
			pivot.rotation = Vector3(0.0, angle, 0.5 * (1 if i % 2 == 0 else -1))
			_orbit.add_child(pivot)
			var mote := _sprite(0.11 * k, _mat("mote", tint.lerp(Color.WHITE, 0.3)), pivot)
			mote.position = Vector3(ORBIT_R * k, 0, 0)
			var glint := _sprite(0.035 * k, _mat("core", tint.lerp(Color.WHITE, 0.7)), pivot)
			glint.position = Vector3(ORBIT_R * k, 0, 0)
	if g >= 7:
		# 빛살 — 판은 카메라를 보고, 판 안에서 천천히 돈다 (`_process`)
		_rays = Node3D.new()
		add_child(_rays)
		for i in 4:
			var ray := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(RAY * k * (1.0 if i % 2 == 0 else 0.6), 0.022 * sqrt(k))
			ray.mesh = quad
			ray.material_override = _mat("ray", tint * Color(1, 1, 1, 0.9), false)
			ray.rotation.z = PI * 0.25 * i
			ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_rays.add_child(ray)


func _process(delta: float) -> void:
	_t += delta
	# 숨 쉬듯 — 좋은 무기일수록 빠르게 뛴다
	var beat := 1.0 + (0.06 + 0.012 * _grade) * sin(_t * (2.0 + 0.4 * _grade))
	_halo.scale = Vector3.ONE * beat
	if _core != null:
		_core.scale = Vector3.ONE * (2.0 - beat)
	if _orbit != null:
		_orbit.rotation.y = _t * ORBIT_SPIN
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var to_camera := (camera.global_position - global_position).normalized()
	# 껍데기 앞으로 — 몸 뒤로 돈 주먹은 몸이 가린다(깊이 검사는 켜 둔다)
	_front.global_position = global_position + to_camera * SHELL
	if _rays != null:
		# 판 법선만 카메라 쪽 — 빛살이 늘 판 가득 보인다
		_rays.global_position = _front.global_position
		_rays.global_basis = Basis.looking_at(to_camera, Vector3.UP)
		_rays.rotate_object_local(Vector3.FORWARD, _t * 0.6)
		_rays.scale = Vector3.ONE * beat


# ─── 조각 ────────────────────────────────────────────────

## 카메라를 보는 빛 한 장
func _sprite(size: float, mat: Material, parent: Node = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## 늘 켜진 방출기. 알갱이는 월드에 남아 흩어진다(`local_coords` 꺼짐)
func _particles(key: String, amount: int, life: float, size: float, rise: float,
		tint: Color) -> void:
	var emitter := GPUParticles3D.new()
	emitter.name = key
	emitter.amount = amount
	emitter.lifetime = life
	emitter.local_coords = false
	emitter.randomness = 0.5
	emitter.visibility_aabb = AABB(Vector3(-1, -1, -1) * _grow, Vector3(2, 2.5, 2) * _grow)
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	# 껍데기 겉면에서 바깥으로 튀어 나와 위로 오른다
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	# 강화로 커지면 조금 더 바깥에서 나온다 — 껍데기는 그대로라 절반만 키운다
	process.emission_sphere_radius = SHELL * (1.0 + (_grow - 1.0) * 0.5)
	process.direction = Vector3.UP
	process.spread = 60.0
	process.radial_velocity_min = rise * 0.3
	process.radial_velocity_max = rise * 0.6
	process.initial_velocity_min = rise * 0.3
	process.initial_velocity_max = rise
	process.gravity = Vector3(0, rise * 0.8, 0)
	process.damping_min = 0.5
	process.damping_max = 1.0
	process.scale_min = 0.6
	process.scale_max = 1.0
	# 태어나 부풀었다가 사그라든다
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	process.scale_curve = scale_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	process.color_ramp = fade_tex
	emitter.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _mat(key, tint, true)
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.emitting = true


## 가산 빛 재질. `particles` 면 알갱이 빌보드에 정점 색(사그라듦)을 곱한다
func _mat(key: String, tint: Color, particles := false) -> StandardMaterial3D:
	# 같은 등급·같은 색이면 재질을 같이 쓴다 (겹 진하기는 등급, 색은 강화가 정한다)
	var id := "%s_%d_%d" % [key, _grade, clampi(_enhance, FIRST, COLORS.keys().max())]
	if _mats.has(id):
		return _mats[id]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = FxTex.glow()
	mat.albedo_color = tint
	if particles:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
	elif key != "ray":
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mats[id] = mat
	return mat
