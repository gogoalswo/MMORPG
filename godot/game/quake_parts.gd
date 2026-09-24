class_name QuakeParts
extends RefCounted

## 천붕각 **강화 이펙트** 두 벌 — `QuakeFx` 가 짓고(`_build`) 되감고(`_start`) 매 프레임
## 시각을 넘긴다(`tick`). 둘 다 아무것도 새로 만들지 않고 되감아 쓴다 (풀 규칙).
##
## - `Tornado` — "진폭": 모래 바람 띠가 캐릭터를 휘감으며 9m 까지 휙 돌았다 흩어진다.
## - `Mud` — "균열 지대": 진흙 웅덩이 위로 진흙 띠가 소용돌이처럼 가운데로 빨려 들고,
##   피해가 들어가는 0.5초마다 한 번 세게 조여든다.
##
## 2026-09-24 요청: "진폭은 모래 먼지가 토네이도 처럼 바람이 주변을 휙 감싸서 공격하게"
## 그리고 균열 지대는 (용암 분수를 거절하고) "진흙이 소용돌이처럼 빨려들어가는 이펙트로".
## 참고 그림은 없었다 — 말로 정한 시안이다 (skill-upgrades.md "천붕각 강화").


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


## 균열 지대 **진흙 소용돌이** (3차 시안, 2026-09-24) — 내리찍은 자리가 3초 동안 질척한
## **진흙 웅덩이**가 되고, 웅덩이 위의 **진흙 띠가 나선을 그리며 가운데로 빨려 든다.**
## 가장자리의 진흙 덩이도 가운데로 끌려가 가라앉는다. 피해가 들어가는 틱(0.5초)마다
## 소용돌이가 **한 번 세게 조여든다** (도는 속도가 확 빨라졌다 풀리고 살짝 오므라든다).
##
## 요청: "균열지대 이펙트 별로다. 진흙이 소용돌이처럼 빨려들어가는 이펙트로" — 그 전의
## 용암 분수(2차)·붉은 틈(1차)은 거절됐다.
##
## 진흙은 빛이 아니라 흙이라 **알파 혼합**이다. 띠는 파티클이 아니라 **한 번 깐 메시를
## 셰이더가 돌린다** (토네이도와 같은 방식 — 매 프레임 깎지 않는다).
class Mud:
	extends Node3D

	## 웅덩이 반지름(m) — 천붕각 사거리와 같다. 진폭이면 `mul` 배 (판정 반경과 같다)
	const RADIUS := 6.0
	## 웅덩이가 번지는 시간 · 다 끝나고 마르는 시간
	const GROW := 0.3
	const DRY := 0.6
	## 나선 띠 수 · 띠 하나가 바깥에서 가운데까지 감기는 바퀴 수 · 점 수
	## 1차 캡처에서 다섯 줄 · 1.15바퀴는 **겹쳐 동심원**으로 보였고, 셋 · 0.85바퀴도 여전히
	## 옅은 고랑의 동심원이었다. **반 바퀴**면 가운데로 휘어 드는 팔로 읽힌다
	const ARMS := 4
	const TURNS := 0.5
	const POINTS := 56
	## 띠 폭(m, 바깥 끝 기준 — 가운데로 갈수록 가늘어진다)
	const ARM_WIDTH := 2.2
	## 평소 도는 빠르기(rad/s) · 틱에 조여들 때 더하는 빠르기 · 잦아드는 시간 상수
	const SPIN := 1.6
	const SQUEEZE_SPIN := 7.0
	const SQUEEZE_DECAY := 0.18
	## 조여들 때 오므라드는 비율
	const SQUEEZE_SHRINK := 0.08
	## 띠 무늬가 가운데로 흘러드는 빠르기 (띠 길이 비율/초)
	const FLOW := 0.9
	## 웅덩이는 짙고 띠는 조금 밝은 젖은 흙이다 — 같으면 띠가 안 보인다
	## 1차는 짙은 웅덩이가 **어두운 바닥에 묻혀 안 보였고**, 띠의 밝은 줄이 **주황 고리**였다.
	## 웅덩이는 바닥보다 밝은 젖은 흙, 띠는 그보다 짙은 진흙, 줄은 옅은 흙빛이다
	const COLOR_POOL := Color(0.36, 0.25, 0.14, 0.92)
	const COLOR_ARM := Color(0.11, 0.07, 0.035, 0.95)
	const COLOR_SHEEN := Color(0.72, 0.6, 0.44, 0.85)
	const COLOR_CLUMP := Color("#4a3320")
	const CLUMPS := 36

	## 점마다: `VERTEX.x` = 각(rad), `VERTEX.z` = 반지름 비율(바깥 1 → 가운데 0).
	## `UV.x` = 폭 방향(0~1), `UV.y` = 띠를 따라(바깥 0 → 가운데 1).
	## 폭은 **반지름 방향**으로 벌린다 — 촘촘히 감긴 나선이라 띠에 거의 수직이다
	const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D streak : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float radius = 6.0;
uniform float spin = 0.0;
uniform float width = 1.0;
uniform float flow = 0.0;
void vertex() {
	float a = VERTEX.x + spin;
	float r = radius * VERTEX.z + (UV.x * 2.0 - 1.0) * width * 0.5 * VERTEX.z;
	VERTEX = vec3(sin(a) * r, 0.0, cos(a) * r);
}
void fragment() {
	vec4 t = texture(streak, UV);
	// 진흙 띠는 **속이 차 있고 가장자리만 부드럽다** — 띠 텍스처를 그대로 쓰면 가운데 한
	// 줄만 진해서(평균 알파 0.25) 웅덩이 위에서 옅은 고랑으로만 보였다 (캡처)
	float body = smoothstep(0.0, 0.3, t.a);
	// 띠를 따라 끊긴 무늬가 **가운데로 흘러든다** — 가만히 도는 띠는 빨려 드는 것으로 안 읽힌다
	float dash = 0.7 + 0.3 * sin((UV.y * 5.0 - flow) * 6.2832);
	// 바깥 끝은 웅덩이에 녹아들고, 가운데 끝은 가라앉아 사라진다
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * body * dash * ends;
}
"""
	static var _mesh: ArrayMesh
	static var _shader: Shader

	var active := false
	## 조여든 횟수 — 테스트가 "틱마다 조여드나" 를 센다
	var squeezes := 0
	var _t := 0.0
	var _spin := 0.0
	var _next := 0.0
	var _since := 99.0
	var _radius := RADIUS
	var _pool: MeshInstance3D
	var _arms: Array = []
	var _clumps: CPUParticles3D

	func build() -> void:
		# 웅덩이 — 가장자리가 부드러운 원판 (`FxTex.glow` 를 알파로). 금보다 위에 깐다 —
		# 갈라진 틈이 진흙 속으로 묻힌다
		_pool = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		quad.orientation = PlaneMesh.FACE_Y
		_pool.mesh = quad
		var pool_mat := StandardMaterial3D.new()
		pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# 가장자리가 불규칙한 얼룩 — 동그란 원판이면 웅덩이가 아니라 표지판이다
		pool_mat.albedo_texture = FxTex.pool()
		pool_mat.albedo_color = COLOR_POOL
		# **그리는 순서를 못 박는다** — 웅덩이와 띠가 둘 다 투명이고 중심이 같아 순서가
		# 제멋대로라, 92% 불투명한 웅덩이가 띠를 덮어 띠가 옅은 고랑으로만 보였다
		pool_mat.render_priority = -1
		_pool.material_override = pool_mat
		_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pool.position.y = QuakeFx.GROUND + 0.03
		add_child(_pool)
		# 띠 두 겹 — 젖은 흙 띠 + 가운데 번들거리는 줄
		var order := 1
		for layer in [[ARM_WIDTH, COLOR_ARM, 0.05], [ARM_WIDTH * 0.45, COLOR_SHEEN, 0.06]]:
			var node := MeshInstance3D.new()
			node.mesh = arm_mesh()
			node.material_override = _material(layer[0], layer[1])
			node.material_override.render_priority = order
			order += 1
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.custom_aabb = AABB(Vector3(-RADIUS * 2.0, -0.5, -RADIUS * 2.0),
				Vector3(RADIUS * 4.0, 1.0, RADIUS * 4.0))
			node.position.y = QuakeFx.GROUND + float(layer[2])
			add_child(node)
			_arms.append({"node": node, "color": layer[1]})
		_clumps = _make_clumps()
		add_child(_clumps)
		visible = false

	## 되감는다. `mul` 은 진폭 배율 — 웅덩이도 판정 반경만큼 넓어진다
	func start(on: bool, mul: float) -> void:
		active = on
		visible = on
		squeezes = 0
		_t = 0.0
		_spin = 0.0
		_since = 99.0
		_next = QuakeFx.ZONE_TICK
		_radius = RADIUS * mul
		_clumps.emission_ring_radius = _radius * 0.95
		_clumps.emission_ring_inner_radius = _radius * 0.6
		_clumps.emitting = false
		_show()

	func tick(delta: float) -> void:
		if not active:
			return
		_t += delta
		_since += delta
		if _t >= _next and _next <= QuakeFx.ZONE_TIME + 1e-3:
			_since = 0.0
			squeezes += 1
			_next += QuakeFx.ZONE_TICK
		# 평소엔 천천히, 틱 직후엔 확 빨라졌다 풀린다. **가운데로 감겨 드는 쪽**으로 돈다
		_spin += (SPIN + SQUEEZE_SPIN * exp(-_since / SQUEEZE_DECAY)) * delta
		_clumps.emitting = _t < QuakeFx.ZONE_TIME
		_show()

	## 지금 반지름 — 틱 직후 살짝 오므라든다
	func radius() -> float:
		var grow := clampf(_t / GROW, 0.0, 1.0)
		return _radius * sqrt(grow) * (1.0 - SQUEEZE_SHRINK * exp(-_since / SQUEEZE_DECAY))

	func alpha() -> float:
		return clampf((QuakeFx.ZONE_TIME + DRY - _t) / DRY, 0.0, 1.0)

	func _show() -> void:
		var a := alpha() if active else 0.0
		var r := radius()
		_pool.visible = active and a > 0.0
		_pool.scale = Vector3(r * 1.12, 1.0, r * 1.12)
		var pool_mat: StandardMaterial3D = _pool.material_override
		pool_mat.albedo_color = Color(COLOR_POOL.r, COLOR_POOL.g, COLOR_POOL.b, COLOR_POOL.a * a)
		for arm in _arms:
			var node: MeshInstance3D = arm.node
			node.visible = active and a > 0.0
			var mat: ShaderMaterial = node.material_override
			var c: Color = arm.color
			mat.set_shader_parameter(&"tint", Color(c.r, c.g, c.b, c.a * a))
			mat.set_shader_parameter(&"radius", r)
			mat.set_shader_parameter(&"spin", _spin)
			mat.set_shader_parameter(&"flow", _t * FLOW * 5.0 + _spin * 0.5)

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

	## 나선 띠 다섯 — 처음 한 번만. 바깥(반지름 1)에서 가운데(0)로 감겨 든다.
	## 반지름을 `(1 - u)^0.8` 로 줄여 가운데 쪽이 촘촘하다 — 빨려 드는 구멍이 보인다
	static func arm_mesh() -> ArrayMesh:
		if _mesh != null:
			return _mesh
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var index := PackedInt32Array()
		for b in ARMS:
			var base := TAU * float(b) / float(ARMS)
			var first := verts.size()
			for p in POINTS + 1:
				var u := float(p) / float(POINTS)
				# 가운데로 갈수록 각이 빨리 돈다 — 안으로 감겨 드는 나선
				var angle := base - u * TURNS * TAU
				var rf := 1.0 - u
				for side in [0.0, 1.0]:
					verts.append(Vector3(angle, 0.0, rf))
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

	## 가장자리에서 가운데로 끌려가는 진흙 덩이 — **안으로 당기고**(`radial_accel` 음수)
	## 옆으로 돌리며(`tangential_accel`) 땅에 붙어 있다가 가라앉는다
	func _make_clumps() -> CPUParticles3D:
		var e := CPUParticles3D.new()
		e.amount = CLUMPS
		e.lifetime = 1.1
		e.explosiveness = 0.0
		var dot := QuadMesh.new()
		dot.size = Vector2(0.45, 0.45)
		e.mesh = dot
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		e.emission_ring_axis = Vector3.UP
		e.emission_ring_radius = RADIUS * 0.95
		e.emission_ring_inner_radius = RADIUS * 0.6
		e.emission_ring_height = 0.0
		e.position.y = 0.15
		e.direction = Vector3.UP
		e.spread = 10.0
		e.initial_velocity_min = 0.3
		e.initial_velocity_max = 0.8
		e.radial_accel_min = -9.0
		e.radial_accel_max = -6.0
		e.tangential_accel_min = 4.0
		e.tangential_accel_max = 7.0
		e.gravity = Vector3(0.0, -1.5, 0.0)
		e.scale_amount_curve = LightningFx.grow_curve(0.3)
		e.color = COLOR_CLUMP
		e.color_ramp = LightningFx.fade_ramp(COLOR_CLUMP, 0.95)
		var mat := LightningFx.mote(COLOR_CLUMP)
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = FxTex.puff()
		e.material_override = mat
		e.emitting = false
		return e
