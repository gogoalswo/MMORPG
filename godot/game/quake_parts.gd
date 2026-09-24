class_name QuakeParts
extends RefCounted

## 천붕각 **강화 이펙트** 두 벌 — `QuakeFx` 가 짓고(`_build`) 되감고(`_start`) 매 프레임
## 시각을 넘긴다(`tick`). 둘 다 아무것도 새로 만들지 않고 되감아 쓴다 (풀 규칙).
##
## - `Tornado` — "진폭": 모래 바람 띠가 캐릭터를 휘감으며 9m 까지 휙 돌았다 흩어진다.
## - `Lava` — "균열 지대": 갈라진 틈에서 0.5초마다 용암이 분수처럼 솟고, 틱 사이에도
##   작은 방울이 뽀글뽀글 튄다.
##
## 2026-09-24 요청: "진폭은 모래 먼지가 토네이도 처럼 바람이 주변을 휙 감싸서 공격하게,
## 균열지대는 갈라진 틈새에서 지속적으로 용암이 터져 나오는 이펙트로". 참고 그림은
## 없었다 — 말로 정한 1차 시안이다 (skill-upgrades.md "천붕각 강화").


## 모래 토네이도 — **띠는 파티클이 아니라 직접 메시**다 (effect-rules.md 3절).
## 띠 넷이 나선으로 감겨 올라가는 메시를 **게임 전체에서 한 번만** 깔고, 반지름·높이·
## 도는 각은 셰이더(`SHADER`)가 넣는다 — 매 프레임 깎으면 폰에서 히치가 난다.
class Tornado:
	extends Node3D

	## 띠 수 · 띠 하나가 감기는 바퀴 수. **띠는 짧고 가파르게 감겨 올라간다** — 한 바퀴를
	## 넘게 낮게 두었더니 위에서 보면 **납작한 고리가 퍼지는 것**이었다 (1차 캡처)
	const BANDS := 6
	const TURNS := 0.65
	## 띠 하나의 점 수 — 성기면 곡선이 꺾여 보인다
	const POINTS := 48
	## 처음 반지름(m) — 캐릭터를 감싸는 자리에서 시작한다
	const R_START := 1.2
	## 끝 반지름(m) — 진폭의 판정 반경(9m)과 같다. 띠 바깥 끝이 여기에 닿는다
	const R_END := 9.0
	## 반지름이 끝까지 퍼지는 시간
	const SPREAD := 0.55
	## 높이(m) — 처음엔 발목, 휘감아 오르며 커진다
	const LIFT_START := 1.2
	const LIFT_END := 4.5
	## 도는 빠르기(rad/s) — 처음이 가장 빠르고 끝으로 갈수록 풀린다
	const SPIN_SPEED := 13.0
	## 사는 시간 · 마지막에 흩어지는 시간
	const LIFE := 0.9
	const FADE := 0.3
	## 두 겹 — 넓고 옅은 바람 + 좁고 진한 모래 줄기 (폭만 다르고 같은 길, 5절)
	const SOFT_WIDTH := 1.5
	const CORE_WIDTH := 0.5
	const COLOR_SOFT := Color(0.8, 0.7, 0.53, 0.45)
	const COLOR_CORE := Color(0.9, 0.82, 0.66, 0.85)
	const COLOR_GRAIN := Color("#bfae8e")
	## 띠 사이를 채우는 모래 먼지 덩이 — 띠만 있으면 선 몇 줄이다
	const GRAIN_COUNT := 64

	## 점마다: `VERTEX.x` = 각(rad), `VERTEX.y` = 높이 비율(0~1), `VERTEX.z` = 반지름 비율.
	## `UV.x` = 폭 방향(0~1), `UV.y` = 띠를 따라(0~1). 폭은 **위아래로** 벌린다 — 바람 띠는
	## 옆으로 누운 리본이다. 깔때기라 위로 갈수록 반지름 비율이 크다
	const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D streak : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float radius = 1.2;
uniform float lift = 1.0;
uniform float spin = 0.0;
uniform float width = 0.5;
void vertex() {
	float a = VERTEX.x + spin;
	float r = radius * VERTEX.z;
	float along = sin(PI * UV.y);
	float h = VERTEX.y * lift + (UV.x * 2.0 - 1.0) * width * 0.5 * along;
	VERTEX = vec3(sin(a) * r, h, cos(a) * r);
}
void fragment() {
	vec4 t = texture(streak, UV);
	// 띠 양끝은 옅게 — 뚝 잘린 끝이 보이면 판자가 돈다
	float along = pow(sin(PI * UV.y), 0.7);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = tint.a * t.a * along;
}
"""
	static var _mesh: ArrayMesh
	static var _shader: Shader

	var active := false
	var _t := 0.0
	var _spin := 0.0
	var _layers: Array = []
	var _grains: CPUParticles3D

	func build() -> void:
		for layer in [[SOFT_WIDTH, COLOR_SOFT], [CORE_WIDTH, COLOR_CORE]]:
			var node := MeshInstance3D.new()
			node.mesh = band_mesh()
			node.material_override = _material(layer[0], layer[1])
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 꼭짓점을 셰이더가 옮기므로 원래 상자로는 화면 밖으로 잘린다
			node.custom_aabb = AABB(Vector3(-R_END - 1.0, -1.0, -R_END - 1.0),
				Vector3(R_END * 2.0 + 2.0, LIFT_END + 3.0, R_END * 2.0 + 2.0))
			node.visible = false
			add_child(node)
			_layers.append({"node": node, "color": layer[1]})
		_grains = _make_grains()
		add_child(_grains)
		visible = false

	## 되감는다. `on` 이 아니면 쉰다
	func start(on: bool) -> void:
		active = on
		visible = on
		_t = 0.0
		_spin = 0.0
		if on:
			_grains.restart()
		else:
			_grains.emitting = false
		_show()

	func tick(delta: float) -> void:
		if not active:
			return
		_t += delta
		# 처음이 가장 빠르고 풀리며 느려진다 — 도는 각을 쌓아야 끊기지 않는다
		_spin -= SPIN_SPEED * (1.0 - 0.6 * clampf(_t / LIFE, 0.0, 1.0)) * delta
		_show()

	## 지금 반지름 — 테스트가 "9m 까지 퍼지나" 를 본다
	func radius() -> float:
		return lerpf(R_START, R_END, QuakeFx.ease_out(clampf(_t / SPREAD, 0.0, 1.0)))

	func _show() -> void:
		var fade_in := clampf(_t / 0.08, 0.0, 1.0)
		var fade_out := clampf((LIFE - _t) / FADE, 0.0, 1.0)
		var alpha := fade_in * fade_out
		var lift := lerpf(LIFT_START, LIFT_END, QuakeFx.ease_out(clampf(_t / 0.4, 0.0, 1.0)))
		for layer in _layers:
			var node: MeshInstance3D = layer.node
			node.visible = active and alpha > 0.0
			var mat: ShaderMaterial = node.material_override
			var c: Color = layer.color
			mat.set_shader_parameter(&"tint", Color(c.r, c.g, c.b, c.a * alpha))
			mat.set_shader_parameter(&"radius", radius())
			mat.set_shader_parameter(&"lift", lift)
			mat.set_shader_parameter(&"spin", _spin)

	func _material(width: float, color: Color) -> ShaderMaterial:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter(&"streak", FxTex.streak())
		mat.set_shader_parameter(&"width", width)
		mat.set_shader_parameter(&"tint", color)
		return mat

	## 띠 넷 — 처음 한 번만. 띠마다 시작 각과 높이 구간이 다르다 (같으면 한 줄로 겹친다)
	static func band_mesh() -> ArrayMesh:
		if _mesh != null:
			return _mesh
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var index := PackedInt32Array()
		for b in BANDS:
			var base := TAU * float(b) / float(BANDS) + 0.3 * float(b % 2)
			var h0 := 0.02 + 0.07 * float(b)
			var h1 := h0 + 0.55
			var first := verts.size()
			for p in POINTS + 1:
				var u := float(p) / float(POINTS)
				var h := lerpf(h0, h1, u)
				# 깔때기 — 아래는 좁고 위로 갈수록 넓다. 바깥 끝(1.0)이 판정 반경에 닿는다
				var rf := 0.3 + 0.7 * h
				for side in [0.0, 1.0]:
					verts.append(Vector3(base + u * TURNS * TAU, h, rf))
					uvs.append(Vector2(side, u))
			for p in POINTS:
				var a := first + p * 2
				index.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return _mesh

	## 띠 가장자리에서 날리는 모래 알갱이 — 둘레에서 솟아 바깥으로 휘돌며 흩어진다
	func _make_grains() -> CPUParticles3D:
		var e := CPUParticles3D.new()
		e.amount = GRAIN_COUNT
		e.lifetime = LIFE
		e.one_shot = true
		e.explosiveness = 0.85
		var dot := QuadMesh.new()
		dot.size = Vector2(2.1, 2.1)
		e.mesh = dot
		e.scale_amount_curve = LightningFx.grow_curve(1.8)
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		e.emission_ring_axis = Vector3.UP
		e.emission_ring_radius = 2.2
		e.emission_ring_inner_radius = 1.0
		e.emission_ring_height = 0.4
		e.direction = Vector3.UP
		e.spread = 35.0
		e.initial_velocity_min = 4.0
		e.initial_velocity_max = 8.0
		e.radial_accel_min = 9.0
		e.radial_accel_max = 14.0
		e.tangential_accel_min = 18.0
		e.tangential_accel_max = 26.0
		e.gravity = Vector3(0.0, -5.0, 0.0)
		e.color = COLOR_GRAIN
		e.color_ramp = LightningFx.fade_ramp(COLOR_GRAIN, 0.32)
		var mat := LightningFx.mote(COLOR_GRAIN)
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = FxTex.puff()
		# 큰 판이 바닥에 잘려 **곧은 모서리**가 보였다 (발밑 캡처) — 땅 가까이서 옅게
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.2
		e.material_override = mat
		e.emitting = false
		return e


## 균열 지대 용암 — 틈 위 자리(`QuakeFx.crack_paths` 에서 뽑는다)에서 **틱마다 분수**
## (`_fountain`)와 연기(`_smoke`)가 솟고, 지대 동안 작은 방울(`_bubbles`)이 계속 튄다.
## 방출기는 틈과 같은 쪽으로 돈 `_pivot` 아래에 있다 — 점도 캐릭터가 보는 쪽 기준이다.
## 용암은 빛이지만 **알파 혼합**이다 — 밝은 바닥에서 가산은 안 보인다 (흙먼지와 같은 결)
class Lava:
	extends Node3D

	## 분수가 솟는 자리 수 — 본줄기 금마다 하나
	const VENTS := 8
	## 분수 한 번에 튀는 덩이 수 · 크기 · 속도 · 사는 시간
	## 1차 캡처에서 0.26m · 64덩이는 **흩어진 불똥**이었다 — 용암은 굵은 덩이다
	const BURST := 110
	const BLOB_SIZE := 0.5
	const BURST_SPEED_MIN := 6.5
	const BURST_SPEED_MAX := 10.0
	const BURST_LIFE := 0.9
	const GRAVITY := -20.0
	## 틱 사이 방울
	const BUBBLES := 28
	const BUBBLE_LIFE := 0.5
	## 노랑 → 주황 → 검붉게 식는다. 흰빛에서 시작했더니 밝은 바닥에서 **옅은 불똥**이었다
	const COLOR_HOT := Color("#ffc83a")
	const COLOR_MID := Color("#ff5a12")
	const COLOR_COOL := Color("#7a1004")
	const COLOR_SMOKE := Color("#3b2f2a")

	var active := false
	var bursts := 0
	var _next := 0.0
	var _pivot: Node3D
	var _fountain: CPUParticles3D
	var _smoke: CPUParticles3D
	var _bubbles: CPUParticles3D
	var _vents := PackedVector3Array()
	var _along := PackedVector3Array()

	func build() -> void:
		_pick_points()
		_pivot = Node3D.new()
		add_child(_pivot)
		_fountain = _emitter(BURST, BURST_LIFE, BLOB_SIZE, true)
		_fountain.direction = Vector3.UP
		_fountain.spread = 10.0
		_fountain.initial_velocity_min = BURST_SPEED_MIN
		_fountain.initial_velocity_max = BURST_SPEED_MAX
		_fountain.gravity = Vector3(0.0, GRAVITY, 0.0)
		_bubbles = _emitter(BUBBLES, BUBBLE_LIFE, BLOB_SIZE * 0.6, false)
		_bubbles.direction = Vector3.UP
		_bubbles.spread = 30.0
		_bubbles.initial_velocity_min = 1.5
		_bubbles.initial_velocity_max = 3.2
		_bubbles.gravity = Vector3(0.0, GRAVITY * 0.5, 0.0)
		_smoke = _make_smoke()
		visible = false

	## 되감는다. `mul` 은 진폭 배율 — 틈이 넓어지면 솟는 자리도 따라 벌어진다
	func start(on: bool, facing: float, mul: float) -> void:
		active = on
		visible = on
		bursts = 0
		_next = QuakeFx.ZONE_TICK
		_pivot.rotation.y = facing
		var vents := PackedVector3Array()
		for p in _vents:
			vents.append(Vector3(p.x * mul, p.y, p.z * mul))
		var along := PackedVector3Array()
		for p in _along:
			along.append(Vector3(p.x * mul, p.y, p.z * mul))
		_fountain.emission_points = vents
		_smoke.emission_points = vents
		_bubbles.emission_points = along
		_fountain.emitting = false
		_smoke.emitting = false
		_bubbles.emitting = false

	## `t` 는 이펙트가 선 뒤 몇 초. 틱(0.5 · 1.0 · … · 3.0초)마다 분수, 그 사이 방울
	func tick(t: float) -> void:
		if not active:
			return
		if t >= _next and _next <= QuakeFx.ZONE_TIME + 1e-3:
			# 되감아 쓰는 방출기라 켜기가 아니라 처음부터 다시(`restart`)
			_fountain.restart()
			_smoke.restart()
			bursts += 1
			_next += QuakeFx.ZONE_TICK
		_bubbles.emitting = t >= 0.3 and t < QuakeFx.ZONE_TIME

	## 금 경로에서 솟는 자리를 뽑는다 — 본줄기마다 60% 지점 하나(분수), 모든 점(방울)
	func _pick_points() -> void:
		var paths := QuakeFx.crack_paths()
		for entry in paths:
			var points: PackedVector3Array = entry[0]
			for p in points:
				_along.append(Vector3(p.x, 0.05, p.z))
		for i in mini(VENTS, paths.size()):
			var points: PackedVector3Array = paths[i][0]
			var p := points[int(points.size() * 0.6)]
			_vents.append(Vector3(p.x, 0.05, p.z))

	func _emitter(count: int, life: float, size: float, one_shot: bool) -> CPUParticles3D:
		var e := CPUParticles3D.new()
		e.amount = count
		e.lifetime = life
		e.one_shot = one_shot
		e.explosiveness = 0.9 if one_shot else 0.0
		var dot := QuadMesh.new()
		dot.size = Vector2(size, size)
		e.mesh = dot
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		# 솟을수록 작아진다 — 덩이가 식으며 흩어지는 것
		e.scale_amount_curve = LightningFx.grow_curve(0.45)
		var ramp := Gradient.new()
		ramp.set_color(0, COLOR_HOT)
		ramp.set_color(1, Color(COLOR_COOL.r, COLOR_COOL.g, COLOR_COOL.b, 0.0))
		ramp.add_point(0.35, COLOR_MID)
		e.color_ramp = ramp
		var mat := LightningFx.mote(Color.WHITE)
		mat.albedo_color = Color.WHITE
		e.material_override = mat
		e.emitting = false
		_pivot.add_child(e)
		return e

	## 틱마다 틈에서 오르는 검은 연기 — 조금만, 느리게. 많으면 용암을 가린다
	func _make_smoke() -> CPUParticles3D:
		var e := CPUParticles3D.new()
		e.amount = 10
		e.lifetime = 1.2
		e.one_shot = true
		e.explosiveness = 0.8
		var dot := QuadMesh.new()
		dot.size = Vector2(1.1, 1.1)
		e.mesh = dot
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		e.direction = Vector3.UP
		e.spread = 20.0
		e.initial_velocity_min = 1.2
		e.initial_velocity_max = 2.2
		e.gravity = Vector3(0.0, 0.5, 0.0)
		e.scale_amount_curve = LightningFx.grow_curve(1.8)
		e.color = COLOR_SMOKE
		e.color_ramp = LightningFx.fade_ramp(COLOR_SMOKE, 0.45)
		var mat := LightningFx.mote(COLOR_SMOKE)
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = FxTex.puff()
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.0
		e.material_override = mat
		e.emitting = false
		_pivot.add_child(e)
		return e
