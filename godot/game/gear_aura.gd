class_name GearAura
extends Node3D

## 갑옷·투구·신발에 감도는 기운(오로라) — **좋은 등급일수록 화려하다** (2026-09-26 요청:
## "좋은 등급일수록 장비에 오로라를 줘 · 오로라 붙이는 것도 고도엔진에서 이펙트로 만들어서 붙여").
## 4등급부터 나오고, 색은 그 등급 아이콘의 빛 색이다.
##
## | 등급 | 더해지는 것 |
## |---|---|
## | 4 영웅 | 부위 겉에서 피어오르는 보랏빛 |
## | 5 전설 | + 흩어지며 오르는 금빛 불티 |
## | 6 초월 | + 일렁이는 붉은 불꽃, 불티가 굵어진다 |
## | 7 태초 | + 부위 둘레를 도는 빛알과 흰 심, 가장 많고 밝다 |
##
## 부위의 뼈 소켓(`BoneAttachment3D`)마다 하나씩 붙는다. 알갱이가 나오는 상자는
## **그 뼈에 묶인 정점의 상자**(`Armor._box`)다 — 부위 겉에서 피어오르게.
## 규칙(docs/features/effect-rules.md)대로 코드로 짓고 텍스처는 `FxTex.glow` 를 굽는다.
## 늘 켜져 있으므로 **깊이 검사를 켠다.** 알갱이는 월드에 남아(`local_coords` 꺼짐)
## 달리면 궤적처럼 흩어진다. 좌표는 **미터**다 — 소켓(모델 단위)의 배율을 되돌려 둔다.

const FIRST := 4
## 등급 → 빛 색
const COLORS := {
	4: Color("#b464ff"),
	5: Color("#ffb03a"),
	6: Color("#ff3a14"),
	7: Color("#fff0c0"),
}
## 부위 → 기운이 붙는 뼈
const BONES := {
	"armor": ["Spine1", "LeftArm", "RightArm"],
	"helmet": ["Head"],
	"boots": ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot"],
}

static var _mats := {}

var _grade := FIRST
## 알갱이가 나오는 상자 (미터, 뼈 좌표)
var _box := AABB()
var _t := 0.0
var _orbit: Node3D
var _halo: MeshInstance3D


static func shows(grade: int) -> bool:
	return grade >= FIRST


## 부위의 기운을 등급으로 갈아 끼운다. 4등급 아래거나 0 이면 걷기만 한다
static func wear(rig: Node3D, body: MeshInstance3D, slot: String, grade: int) -> void:
	var meters: float = rig.get_child(0).scale.x
	for bone in BONES.get(slot, []):
		var socket: BoneAttachment3D = rig.fist_socket(bone)
		if socket == null:
			continue
		var old := socket.get_node_or_null("GearAura_" + slot)
		if old != null:
			socket.remove_child(old)
			old.queue_free()
		if not shows(grade) or body == null:
			continue
		var box: AABB = Armor._box(body, bone)[0]
		var aura := GearAura.new()
		aura.name = "GearAura_" + slot
		aura._grade = clampi(grade, FIRST, 7)
		# 소켓은 모델 단위 — 배율을 되돌려 미터로 짓고, 상자도 미터로 옮긴다
		aura.scale = Vector3.ONE / meters
		aura._box = AABB(box.position * meters, box.size * meters)
		aura._build()
		socket.add_child(aura)


func _build() -> void:
	var g := _grade
	var tint: Color = COLORS[g]
	var span := _box.size.length()
	# 빛무리 — 부위를 감싸는 은은한 빛 한 장이 숨 쉬듯 뛴다. 늘 보이는 바탕이다
	# (알갱이만으로는 드문드문해서 4등급은 거의 안 보였다 — 찍어 보고 더했다)
	_halo = MeshInstance3D.new()
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2.ONE * (span * 1.25 + 0.08)
	_halo.mesh = halo_quad
	_halo.position = _box.get_center()
	_halo.material_override = _mat("halo", tint * Color(1, 1, 1, 0.3 + 0.08 * (g - 4)))
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	# 피어오르는 빛 — 부위 겉에서 큰 빛뭉치가 천천히 오르며 사그라든다
	_particles("wisp", 10 + 5 * (g - 4), 1.1, 0.14 + 0.06 * span + 0.03 * (g - 4), 0.3 + 0.06 * (g - 4),
		tint * Color(1, 1, 1, 0.75))
	if g >= 5:
		# 불티 — 작은 빛알이 흩어지며 빠르게 오른다
		_particles("spark", 10 + 6 * (g - 5), 0.8, 0.045 + 0.01 * (g - 5), 0.65, tint.lerp(Color.WHITE, 0.45))
	if g >= 6:
		# 불꽃 — 일렁이는 큰 뭉치
		_particles("flame", 8 + 5 * (g - 6), 0.55, 0.2 + 0.05 * (g - 6), 0.85, tint * Color(1, 1, 1, 0.7))
	if g >= 7:
		# 흰 심 — 가는 빛이 촘촘히
		_particles("core", 10, 0.6, 0.05, 0.4, Color(1, 1, 1, 0.9))
		# 빛알 셋이 부위 둘레를 돈다
		_orbit = Node3D.new()
		_orbit.position = _box.get_center()
		add_child(_orbit)
		var radius := maxf(_box.size.x, _box.size.z) * 0.7 + 0.04
		for i in 3:
			var mote := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.09, 0.09)
			mote.mesh = quad
			mote.material_override = _mat("mote", tint.lerp(Color.WHITE, 0.3))
			mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var angle := TAU * i / 3.0
			mote.position = Vector3(cos(angle), 0.3 * sin(angle * 2.0), sin(angle)) * radius
			_orbit.add_child(mote)


func _process(delta: float) -> void:
	_t += delta
	if _halo != null:
		_halo.scale = Vector3.ONE * (1.0 + (0.06 + 0.02 * _grade) * sin(_t * (1.5 + 0.3 * _grade)))
	if _orbit != null:
		_orbit.rotation.y = _t * 2.4
		_orbit.rotation.x = 0.35 * sin(_t * 0.9)


## 늘 켜진 방출기 — 부위 상자 겉에서 나와 위로 오른다
func _particles(key: String, amount: int, life: float, size: float, rise: float, tint: Color) -> void:
	var emitter := GPUParticles3D.new()
	emitter.name = key
	emitter.amount = amount
	emitter.lifetime = life
	emitter.local_coords = false
	emitter.randomness = 0.6
	emitter.position = _box.get_center()
	emitter.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = _box.size * 0.55
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = rise * 0.4
	process.initial_velocity_max = rise
	process.gravity = Vector3(0, rise * 0.6, 0)
	process.damping_min = 0.3
	process.damping_max = 0.8
	process.scale_min = 0.6
	process.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.3, 1.0))
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


## 가산 빛 재질 (등급·조각마다 한 벌). 깊이 검사는 켠다 — 몸 뒤의 빛이 몸을 뚫지 않게
func _mat(key: String, tint: Color, particles := false) -> StandardMaterial3D:
	var id := "%s_%d" % [key, _grade]
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
	else:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mats[id] = mat
	return mat
