class_name BlastFx
extends Node3D

## 폭렬 찍기(`blast_heel`) 연출 — **발로 쾅 찍은 자리에서 연기가 솟고, 그 둘레로 날카로운
## 기(氣) 줄기가 부채처럼 휘며 터져 나간다** (2026-09-29 요청: "네모난 기둥처럼 하지 말고, 연기가
## 발생하면서 주변에 날카롭게 기가 터져 나가는 식 … 위치도 발 위치에 맞춰서" — 막대 그림:
## 밑동의 연기 덩이와 거기서 위·바깥으로 휘어 뻗는 줄기들).
##
## 자리는 **찍는 발**이다 — 시전자 발밑에서 `FOOT` 만큼(캐릭터 기준 오른쪽 앞) 옮긴다
## (`foot_point`). 동작(`BlastHeel`)이 0.42초에 오른발을 거기 내려놓는다 — `blast_fx_test.gd` 가
## 모델의 발 뼈로 잰다. 둘은 같이 고친다.
##
## - **기 줄기** (`STREAKS` · `SHORTS`) — 밑동에서 곧게 솟다가 바깥으로 휘며 뻗는 가는 띠.
##   양끝이 뾰족하게 좁아지는 셰이더라 날카롭다. 띠라서 메시 한 장(규칙 3절)을 폭렬권 빛살
##   셰이더(`NovaFx.swirl_material`)로 두 겹(금빛 헤일로 + 흰 심) 그린다.
## - **연기** — 밑동에서 뭉게뭉게 **위로** 솟는 덩이(`BILLOW_*`)와 찍는 순간 발밑에서 낮게
##   살짝 번지는 흙먼지(`PUFF_*`, 1.5m 안). 옆으로 멀리 퍼지지 않는다 — 그러면 "내 주변 연기" 다.
## - **번쩍임 · 빛 · 불티 · 흔들림**.
##
## 지나온 시안: 불덩이 폭발 + 용암 금 + 잔불(1차) → 빛살 폭발(2차) → 타겟 자리 불기둥(3차,
## "네모난 기둥" 이라 거절). 불·기둥·잔해는 이제 없다.
##
## **판정을 하지 않는다.** 끝나면 풀로 돌아간다 (`FxPool`).

const GROUND := 0.05

## 찍는 발 자리 — 시전자 발밑 기준, 캐릭터가 +Z 를 볼 때의 자리(m). x 가 + 면 캐릭터 왼쪽이다.
## 모델에서 잰 값(0.42~0.43초의 `RightFoot`)이다
const FOOT := Vector3(-0.3, 0.0, 0.43)

## 기 줄기 — 밑동에서 솟아 바깥으로 휘며 뻗는다. 가로로 `REACH_*`, 위로 `RISE_*` 까지(m)
const STREAKS := 30
const REACH_MIN := 2.0
const REACH_MAX := 4.2
const RISE_MIN := 2.0
const RISE_MAX := 4.8
## 짧은 줄기 — 안쪽을 채운다 (긴 것만 있으면 밑동이 비어 부채살 끝만 보인다)
const SHORTS := 16
const SHORT_SCALE := 0.45
const STREAK_SEGMENTS := 10
## 줄기 두 겹의 폭(m) · 꼬리 비율 · 숨기는 때(초 — `streak_end()` 보다 크게)
const STREAK_HALO := 0.26
const STREAK_CORE := 0.07
const STREAK_TRAIL := 0.45
const STREAK_END := 0.5

## 솟는 연기
const BILLOW_COUNT := 36
const BILLOW_SIZE := 2.0
const BILLOW_LIFE := 1.6
## 발밑 흙먼지 — 낮게 살짝. 멎는 거리 v²/2d 가 1.5m 안
const PUFF_COUNT := 14
const PUFF_SIZE := 1.3
const PUFF_LIFE := 0.8
const PUFF_SPEED := 4.5
const PUFF_DAMP := 8.0
## 불티 (가산)
const GLINT_COUNT := 50
const GLINT_SIZE := 0.1
const GLINT_LIFE := 0.8

## 번쩍임·빛
const FLARE_SIZE := 2.6
const FLARE_LIFE := 0.22
const LIGHT_RANGE := 8.0
const LIGHT_ENERGY := 4.0
const LIGHT_LIFE := 0.35

## 흔들림 — 천붕각(0.14 · 0.35)보다 조금 세다
const SHAKE := 0.16
const SHAKE_TIME := 0.4

const COLOR_FLARE := Color("#fff6d8")
const COLOR_LIGHT := Color("#ffd27a")
const COLOR_HALO := Color("#ffc95a")
const COLOR_CORE := Color("#fffbea")
const COLOR_GLINT := Color("#ffe39a")
## 연기 — 옅은 잿빛 흙색. 짙으면 캐릭터 둘레에 어두운 덩이가 남는다 (1차 캡처)
const COLOR_SMOKE := Color("#a39688")

## 기 줄기 메시 — 게임 전체에서 한 번만 깐다
static var _streak_mesh: ArrayMesh

var _t := 0.0
var _started := false
var _flare: MeshInstance3D
var _light: OmniLight3D
var _halo: MeshInstance3D
var _core: MeshInstance3D
## 한 번 터지는 것 — [솟는 연기, 발밑 흙먼지, 불티]
var _bursts: Array[CPUParticles3D] = []


## 폭렬 찍기를 띄운다. `at` 은 **터질 자리**(찍는 발 — `foot_point` 로 구한다, 월드 좌표),
## `facing` 은 시전자가 보는 쪽(rad). 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다
static func blast(parent: Node3D, at: Vector3, facing: float) -> BlastFx:
	var fx := FxPool.take(parent, &"blast") as BlastFx
	if fx == null:
		fx = BlastFx.new()
		fx.name = "BlastFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 찍는 발 자리 — 시전자 발밑 `feet` 에서 보는 쪽 `facing` 으로 돌린 `FOOT`
static func foot_point(feet: Vector3, facing: float) -> Vector3:
	return feet + FOOT.rotated(Vector3.UP, facing)


## 끝나는 시각(초) — 연기가 다 사라질 때
static func span() -> float:
	return maxf(BILLOW_LIFE, GLINT_LIFE) + 0.1


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	# 기 줄기 두 겹 — 넓은 금빛 헤일로 위에 가는 흰 심
	_halo = _sheet(NovaFx.swirl_material(STREAK_HALO, COLOR_HALO))
	_core = _sheet(NovaFx.swirl_material(STREAK_CORE, COLOR_CORE))
	for node in [_halo, _core]:
		node.mesh = streak_mesh()
		node.material_override.set_shader_parameter(&"trail", STREAK_TRAIL)

	_flare = _sheet(LightningFx.flare(COLOR_FLARE))
	var glare := QuadMesh.new()
	glare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.mesh = glare
	_flare.position.y = 0.4

	_light = OmniLight3D.new()
	_light.position.y = 1.0
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_LIGHT
	add_child(_light)

	_bursts = [_billow(), _puff(), _glints()]
	# **만든 다음 프레임에 켠다** — 같은 프레임에 켜면 방출이 안 나온 적이 있다 (3절)
	for e in _bursts:
		e.emitting = false
		add_child(e)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	rotation.y = facing
	_t = 0.0
	_started = false
	_show()


func _process(delta: float) -> void:
	if not _started:
		_started = true
		# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
		for e in _bursts:
			e.restart()
	_t += delta
	_show()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"blast")


func _show() -> void:
	# 번쩍임은 **세게 켜고 제자리에서 빠르게 죈다** (규칙 3절 — 퍼지지 않는다)
	var f := _t / FLARE_LIFE
	_flare.visible = f < 1.0
	if _flare.visible:
		_flare.scale = Vector3.ONE * lerpf(0.8, 1.15, sqrt(f))
		_flare.material_override.albedo_color = Color(
			COLOR_FLARE.r, COLOR_FLARE.g, COLOR_FLARE.b, pow(1.0 - f, 1.2))
	_light.visible = _t < LIGHT_LIFE
	if _light.visible:
		_light.light_energy = LIGHT_ENERGY * (1.0 - _t / LIGHT_LIFE)
	for node in [_halo, _core]:
		node.material_override.set_shader_parameter(&"now", _t)
		node.visible = _t < STREAK_END


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 방출기 한 벌. `puffy` 면 뭉게뭉게한 덩이(`FxTex.puff`), 아니면 둥근 점. `additive` 면 빛이다
func _emitter(count: int, life: float, size: float, additive: bool, puffy: bool) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	# **한꺼번에 내보낸다(1.0).** 되감아 쓰는 1회용 방출기를 조금씩 나눠 내보내면(0.85) **아직 안
	# 나온 입자가 첫 순간 검은 판으로** 그려졌다 (4차 캡처 — 발밑의 검은 덩이). 늦게 나오는 결은
	# 속도를 흩어서 낸다
	e.explosiveness = 1.0
	# **그림자를 끈다** — 방출기는 기본으로 그림자를 드리워, 땅 가까운 덩이가 밑동에
	# **어두운 호**를 그렸다 (3차 캡처)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	e.mesh = quad
	e.angle_min = -180.0
	e.angle_max = 180.0
	var mat := LightningFx.mote(Color.WHITE, additive)
	# 색은 입자 색(`color_ramp`)으로만 준다 — 재질 색까지 두면 두 번 곱해진다
	mat.albedo_color = Color.WHITE
	if puffy:
		mat.albedo_texture = FxTex.puff()
		# 땅에 가까울수록 옅게 — 큰 판이 바닥에 잘린 곧은 모서리가 안 보이게. 짧게 둔다:
		# 1m 에 걸쳐 옅어지면 밑동 한가운데가 비어 보인다 (1차 캡처)
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.35
	e.material_override = mat
	return e


## 연기 색 띠 — **처음엔 투명하다가** 짙어져 옅게 사라진다 (처음부터 짙으면 번쩍임을 덮는다)
static func smoke_ramp(peak: float) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.0))
	ramp.set_color(1, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.0))
	ramp.add_point(0.15, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, peak))
	ramp.add_point(0.6, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, peak * 0.6))
	return ramp


## 솟는 연기 — 밑동에서 뭉게뭉게 **위로** 오르며 부푼다 (그림의 연기 덩이)
func _billow() -> CPUParticles3D:
	var e := _emitter(BILLOW_COUNT, BILLOW_LIFE, BILLOW_SIZE, false, true)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 30.0
	e.initial_velocity_min = 2.2
	e.initial_velocity_max = 5.2
	e.damping_min = 2.4
	e.damping_max = 2.4
	e.angular_velocity_min = -40.0
	e.angular_velocity_max = 40.0
	e.color_ramp = smoke_ramp(0.62)
	e.scale_amount_curve = LightningFx.grow_curve(2.3)
	e.position.y = 0.5
	return e


## 발밑 흙먼지 — 찍는 순간 낮게 살짝 번지고 멎는다 (1.5m 안)
func _puff() -> CPUParticles3D:
	var e := _emitter(PUFF_COUNT, PUFF_LIFE, PUFF_SIZE, false, true)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.spread = 180.0
	e.flatness = 1.0
	e.initial_velocity_min = PUFF_SPEED * 0.7
	e.initial_velocity_max = PUFF_SPEED
	e.damping_min = PUFF_DAMP
	e.damping_max = PUFF_DAMP
	e.gravity = Vector3(0.0, 0.8, 0.0)
	e.color_ramp = smoke_ramp(0.5)
	e.scale_amount_curve = LightningFx.grow_curve(1.6)
	e.position.y = 0.2
	return e


## 불티 — 가산 금빛 점이 줄기를 따라 위·바깥으로 튀었다 떨어진다
func _glints() -> CPUParticles3D:
	var e := _emitter(GLINT_COUNT, GLINT_LIFE, GLINT_SIZE, true, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.4
	e.direction = Vector3.UP
	e.spread = 55.0
	e.initial_velocity_min = 6.0
	e.initial_velocity_max = 12.0
	e.gravity = Vector3(0.0, -12.0, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.4
	e.color_ramp = LightningFx.fade_ramp(COLOR_GLINT, 1.0)
	e.scale_amount_curve = LightningFx.fade_curve()
	e.position.y = 0.2
	return e


## 기 줄기 전부를 한 메시에 — **처음 한 번만** 깐다 (밑동 = 원점). 꼭짓점 배치는
## `NovaFx.swirl_mesh` 와 같다: `UV` = (나가기 시작하는 시각, 걸리는 시간), `UV2` = (줄기 위
## 자리 0~1, 폭 방향 −1·0·1), `COLOR.r` = 폭 배율. 셰이더가 `now` 로 머리~꼬리만 벌린다 —
## 양끝이 뾰족하게 좁아지므로 날카롭다
static func streak_mesh() -> ArrayMesh:
	if _streak_mesh != null:
		return _streak_mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for strand in streaks():
		var path: PackedVector3Array = strand[0]
		var last := path.size() - 1
		var base := verts.size()
		for p in path.size():
			var along := path[mini(p + 1, last)] - path[maxi(p - 1, 0)]
			for side in [-1.0, 0.0, 1.0]:
				verts.append(path[p])
				normals.append(along.normalized())
				colors.append(Color(strand[3], 0.0, 0.0, 1.0))
				uvs.append(Vector2(strand[1], strand[2]))
				uv2s.append(Vector2(float(p) / float(last), side))
		for p in last:
			var a := base + p * 3
			var b := a + 3
			index.append_array([a, a + 1, b, b, a + 1, b + 1])
			index.append_array([a + 2, a + 1, b + 2, b + 2, a + 1, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = index
	_streak_mesh = ArrayMesh.new()
	_streak_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _streak_mesh


## 줄기 전부 — [경로(밑동 기준), 시작(초), 걸리는 시간(초), 폭 배율]. 씨앗이 고정이다.
## 줄기 하나는 **밑동에서 곧게 솟다가 바깥으로 휜다** — 위로는 사인(처음 빠르고 끝에서 느림),
## 옆으로는 거듭제곱(처음 느리고 끝에서 빠름)이라 그림처럼 부채살이 바깥으로 휜다
static func streaks() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2809291
	var out: Array = []
	for i in STREAKS + SHORTS:
		var short := i >= STREAKS
		var n := SHORTS if short else STREAKS
		var yaw := TAU * (float(i % n) + rng.randf_range(-0.4, 0.4)) / float(n)
		var size := SHORT_SCALE if short else 1.0
		var reach := rng.randf_range(REACH_MIN, REACH_MAX) * size
		var rise := rng.randf_range(RISE_MIN, RISE_MAX) * size
		var bend := rng.randf_range(2.0, 2.8)
		var out_dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var path := PackedVector3Array()
		for p in STREAK_SEGMENTS + 1:
			var s := float(p) / float(STREAK_SEGMENTS)
			path.append(out_dir * (0.15 + reach * pow(s, bend)) + Vector3.UP * (0.1 + rise * sin(s * PI * 0.5)))
		out.append([path, rng.randf_range(0.0, 0.06), rng.randf_range(0.14, 0.24),
			rng.randf_range(0.55, 1.0) * (0.7 if short else 1.0)])
	return out


## 줄기 끝 — 가장 늦게 나가는 줄기가 다 지나간 뒤
static func streak_end() -> float:
	var end := 0.0
	for strand in streaks():
		end = maxf(end, float(strand[1]) + float(strand[2]) * (1.0 + STREAK_TRAIL))
	return end
