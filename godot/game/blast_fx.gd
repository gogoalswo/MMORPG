class_name BlastFx
extends Node3D

## 폭렬 찍기(`blast_heel`) 연출 — **한 발로 땅을 쾅 찍으면 겨눈 놈 자리에서 폭발 기둥이
## 솟는다** (2026-09-29 요청: "내 주변으로 연기가 퍼지는 게 아니라 타겟 위치에 폭발하는
## 기둥" · "불꽃 잔해 없애"). 자리는 판정(`World.cast`)이 누르는 순간 정해 `skill` 이벤트의
## `tx`·`tz` 로 보낸다 — 이펙트는 그 자리에 설 뿐이다.
##
## 지나온 시안: 1차는 내 발밑에서 터지고 용암빛 금·잔불이 4초 남았다. 2차는 "지면에 용암은
## 제거" 로 금을 걷고 빛살을 더했다. 3차(이것)는 **자리를 타겟으로 옮기고, 옆으로 퍼지던
## 불덩이·바닥 불길·연기와 잔불을 모두 걷고, 전부 위로 솟게** 했다.
##
## - **기둥** — 세로로 선 판 두 겹(`PILLAR_*`): 바깥은 주황(알파), 안은 흰 노랑(가산).
##   불꽃 혀 텍스처(`FxTex.flame` — 아래가 굵고 위로 가늘어진다)를 **Y 축으로만 카메라를
##   보게** 세운다. 0.14초에 땅에서 치솟고, 가늘어지며 사그라든다.
## - **불덩이 기둥** — 발밑 좁은 원에서 곧장 위로 치솟는 불덩이(알파)와 같은 결의 가산 불빛.
##   감속으로 기둥 높이(`COLUMN_TOP`)쯤에서 멎는다. 옆으로 퍼지지 않는다.
## - **빛살·잔금** — 위쪽으로 치우쳐 튀는 빛줄기와 기둥 둘레에서 번쩍이는 짧은 잔금.
##   띠라서 메시 한 장(규칙 3절) — 폭렬권 빛살 셰이더(`NovaFx.swirl_material`)를 돌려 쓴다.
## - **불똥 분수 · 섬광 · 빛 · 흔들림**. 돌 조각은 뺐다 — 시작 순간 밑동에 뭉쳐 검은 덩이였다.
##
## **판정을 하지 않는다.** 끝나면 풀로 돌아간다 (`FxPool`).

const GROUND := 0.05

## 기둥 판 — 바깥(주황, 알파)과 안(흰 노랑, 가산)의 폭·높이(m)
const PILLAR_WIDTH := 2.6
const PILLAR_HEIGHT := 7.5
const PILLAR_CORE_WIDTH := 1.3
const PILLAR_CORE_HEIGHT := 6.5
## 땅에서 치솟는 시간 · 다 서 있다가 가늘어지기 시작하는 때 · 사그라져 끝나는 때 (초)
const PILLAR_RISE := 0.14
const PILLAR_HOLD := 0.35
const PILLAR_END := 0.9

## 불덩이 기둥 — 발밑 좁은 원(`COLUMN_RADIUS`)에서 곧장 위로. 멎는 높이 v²/2d 가 `COLUMN_TOP` 쯤
const COLUMN_COUNT := 56
const COLUMN_SIZE := 1.7
const COLUMN_LIFE := 0.85
const COLUMN_RADIUS := 0.5
const COLUMN_SPEED_MIN := 7.0
const COLUMN_SPEED_MAX := 13.0
const COLUMN_DAMP := 14.0
const COLUMN_TOP := 6.0
## 불덩이 위 가산 불빛 수 — 알파 불덩이만으로는 한 빛깔로 칠해진다 (1차 캡처)
const BLAZE_COUNT := 24
## 불꽃 혀 — 기둥 밑동에서 날름 치솟는다
const TONGUE_COUNT := 30
const TONGUE_SIZE := Vector2(0.9, 1.9)
const TONGUE_LIFE := 0.55
## 불똥 분수 (가산)
const SPARK_COUNT := 70
const SPARK_SIZE := 0.13
const SPARK_LIFE := 1.0

## 빛살 — 위쪽으로 치우쳐 튀는 빛줄기
const RAYS := 26
const RAY_MIN := 3.0
const RAY_MAX := 6.5
const RAY_SEGMENTS := 6
## 잔금 — 기둥 둘레(높이 0~4m)에서 번쩍이는 들쭉날쭉한 짧은 빛줄기
const CRACKLES := 14
const CRACKLE_MIN := 1.2
const CRACKLE_MAX := 2.6
## 빛살 두 겹의 폭(m) · 꼬리 비율 · 숨기는 때(초 — `ray_end()` 보다 크게)
const RAY_HALO := 0.34
const RAY_CORE := 0.09
const RAY_TRAIL := 0.5
const RAY_END := 0.6

## 섬광·빛
const FLARE_SIZE := 3.0
const FLARE_LIFE := 0.26
const LIGHT_RANGE := 10.0
## 9 로 두었더니 캐릭터가 하얗게 날아갔다 (1차 캡처) — 천붕각(5)만큼
const LIGHT_ENERGY := 5.0
const LIGHT_LIFE := 0.5

## 흔들림 — 천붕각(0.14 · 0.35)보다 조금 세다
const SHAKE := 0.16
const SHAKE_TIME := 0.4

const COLOR_FLARE := Color("#fff1c4")
const COLOR_LIGHT := Color("#ff8a2a")
const COLOR_PILLAR := Color("#ff8a24")
const COLOR_PILLAR_CORE := Color("#fff0b0")
const COLOR_HEAT := Color("#ffb347")
const COLOR_SPARK := Color("#ffd27a")
const COLOR_RAY := Color("#ff9a30")
const COLOR_RAY_CORE := Color("#fff4c8")

## 빛살·잔금 메시 — 게임 전체에서 한 번만 깐다
static var _ray_mesh: ArrayMesh

var _t := 0.0
var _started := false
var _flare: MeshInstance3D
var _light: OmniLight3D
var _pillar: MeshInstance3D
var _pillar_core: MeshInstance3D
var _ray_halo: MeshInstance3D
var _ray_core: MeshInstance3D
## 한 번 터지는 것 — [불덩이, 가산 불빛, 불꽃 혀, 불똥]
var _bursts: Array[CPUParticles3D] = []


## 폭렬 찍기를 띄운다. `at` 은 **폭발 기둥이 설 자리**(타겟 발밑, 월드 좌표),
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


## 끝나는 시각(초) — 가장 오래 가는 불똥이 떨어질 때
static func span() -> float:
	return maxf(maxf(SPARK_LIFE, PILLAR_END), COLUMN_LIFE + 0.2) + 0.1


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	_pillar = _sheet(_pillar_mat(false, COLOR_PILLAR))
	_pillar.mesh = _blade(PILLAR_WIDTH, PILLAR_HEIGHT)
	_pillar_core = _sheet(_pillar_mat(true, COLOR_PILLAR_CORE))
	_pillar_core.mesh = _blade(PILLAR_CORE_WIDTH, PILLAR_CORE_HEIGHT)
	# 밑동을 조금 땅에 묻는다 — 흐린 밑동이 땅 위에 떠 있으면 기둥이 떠 보인다
	for node in [_pillar, _pillar_core]:
		node.position.y = GROUND - 0.5

	# 빛살·잔금 두 겹 — 넓은 주황 헤일로 위에 가는 흰 심
	_ray_halo = _sheet(NovaFx.swirl_material(RAY_HALO, COLOR_RAY))
	_ray_core = _sheet(NovaFx.swirl_material(RAY_CORE, COLOR_RAY_CORE))
	for node in [_ray_halo, _ray_core]:
		node.mesh = ray_mesh()
		node.material_override.set_shader_parameter(&"trail", RAY_TRAIL)

	_flare = _sheet(LightningFx.flare(COLOR_FLARE))
	var glare := QuadMesh.new()
	glare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.mesh = glare
	_flare.position.y = 0.6

	_light = OmniLight3D.new()
	_light.position.y = 1.5
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_LIGHT
	add_child(_light)

	_bursts = [_column(), _blaze(), _tongues(), _sparks()]
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


## 기둥이 얼마나 서 있나 — (높이 배율, 폭 배율, 진하기)
func pillar_state() -> Vector3:
	var rise := QuakeFx.ease_out(clampf(_t / PILLAR_RISE, 0.0, 1.0))
	var fade := clampf((_t - PILLAR_HOLD) / (PILLAR_END - PILLAR_HOLD), 0.0, 1.0)
	return Vector3(lerpf(0.15, 1.0, rise) + 0.1 * fade, lerpf(1.0, 0.45, fade), 1.0 - fade * fade)


func _show() -> void:
	# 섬광은 **세게 켜고 제자리에서 빠르게 죈다** (규칙 3절 — 퍼지지 않는다)
	var f := _t / FLARE_LIFE
	_flare.visible = f < 1.0
	if _flare.visible:
		_flare.scale = Vector3.ONE * lerpf(0.8, 1.2, sqrt(f))
		_flare.material_override.albedo_color = Color(
			COLOR_FLARE.r, COLOR_FLARE.g, COLOR_FLARE.b, pow(1.0 - f, 1.2))
	_light.visible = _t < LIGHT_LIFE
	if _light.visible:
		_light.light_energy = LIGHT_ENERGY * (1.0 - _t / LIGHT_LIFE)

	# 기둥 — 땅에서 치솟았다가(높이) 가늘어지며(폭) 사그라든다(진하기)
	var p := pillar_state()
	for node in [_pillar, _pillar_core]:
		node.visible = p.z > 0.0
		node.scale = Vector3(p.y, p.x, 1.0)
	_pillar.material_override.albedo_color = Color(
		COLOR_PILLAR.r, COLOR_PILLAR.g, COLOR_PILLAR.b, p.z)
	_pillar_core.material_override.albedo_color = Color(
		COLOR_PILLAR_CORE.r, COLOR_PILLAR_CORE.g, COLOR_PILLAR_CORE.b, 0.8 * p.z)

	for node in [_ray_halo, _ray_core]:
		node.material_override.set_shader_parameter(&"now", _t)
		node.visible = _t < RAY_END


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 기둥 판 — 밑동이 원점에 오게 올려 둔다 (그래야 땅에서 솟는다)
static func _blade(width: float, height: float) -> QuadMesh:
	var blade := QuadMesh.new()
	blade.size = Vector2(width, height)
	blade.center_offset = Vector3(0.0, height * 0.5, 0.0)
	return blade


## 기둥 재질 — **Y 축으로만 카메라를 본다** (`BILLBOARD_FIXED_Y`). 다 돌면 위에서 내려다보는
## 카메라에 기둥이 누워 보인다. 바깥은 알파(밝은 바닥에서도 보이게), 안은 가산(빛)
static func _pillar_mat(additive: bool, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_texture = FxTex.pillar()
	mat.albedo_color = color
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = true
	return mat


## 불 색 띠 — 노랑에서 주황·붉은빛을 지나 사라진다. 붉게 식는 꼬리는 짧고 옅게 —
## 길면 **붉은 솜뭉치**가 부푼 채 남는다 (1차 캡처)
static func fire_ramp(peak: float) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.88, 0.5, peak))
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, Color(0.75, 0.12, 0.02, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.62, 0.16, peak))
	ramp.add_point(0.5, Color(0.9, 0.26, 0.05, peak * 0.35))
	ramp.add_point(0.8, Color(0.6, 0.1, 0.02, peak * 0.12))
	return ramp


## 방출기 한 벌. `texture` 가 있으면 그 결(뭉치·불꽃 혀), 없으면 둥근 점. `additive` 면 빛이다
func _emitter(count: int, life: float, size: Vector2, additive: bool,
		texture: Texture2D) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 1.0
	# **그림자를 끈다** — 방출기는 기본으로 그림자를 드리워, 땅 가까운 불덩이가 기둥 밑동에
	# **어두운 호**를 그렸다 (3차 캡처). 빛이 그림자를 드리울 리 없다
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = size
	e.mesh = quad
	var mat := LightningFx.mote(Color.WHITE, additive)
	# 색은 입자 색(`color_ramp`)으로만 준다 — 재질 색까지 두면 두 번 곱해진다
	mat.albedo_color = Color.WHITE
	if texture != null:
		mat.albedo_texture = texture
		# 땅에 가까울수록 옅게 — 큰 판이 바닥에 잘린 곧은 모서리가 안 보이게. 짧게 둔다:
		# 1m 에 걸쳐 옅어지면 발밑 한가운데가 비어 보인다 (1차 캡처)
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.35
	e.material_override = mat
	return e


## 불덩이 기둥 — 발밑 좁은 원에서 **곧장 위로** 치솟아 기둥 높이쯤에서 멎는다.
## 한꺼번에가 아니라 0.15초 남짓에 걸쳐 나가서 기둥이 아래부터 차오른다
func _column() -> CPUParticles3D:
	var e := _emitter(COLUMN_COUNT, COLUMN_LIFE, Vector2.ONE * COLUMN_SIZE, false, FxTex.puff())
	_rising(e, 0.8)
	var ramp := fire_ramp(0.85)
	ramp.set_color(0, Color(1.0, 0.7, 0.28, 0.85))
	e.color_ramp = ramp
	e.scale_amount_curve = LightningFx.grow_curve(1.7)
	return e


## 불덩이 기둥 위에 겹치는 **가산 불빛** — 같은 결이라 겹친 곳만 밝아져 속에 결이 생긴다
func _blaze() -> CPUParticles3D:
	var e := _emitter(BLAZE_COUNT, COLUMN_LIFE * 0.8, Vector2.ONE * COLUMN_SIZE, true, FxTex.puff())
	_rising(e, 0.85)
	e.color_ramp = LightningFx.fade_ramp(COLOR_HEAT, 0.3)
	e.scale_amount_curve = LightningFx.grow_curve(1.4)
	return e


## 곧장 위로 — 발밑 좁은 원에서 좁은 각으로, 감속으로 `COLUMN_TOP` 쯤에서 멎는다
func _rising(e: CPUParticles3D, explosive: float) -> void:
	e.explosiveness = explosive
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = COLUMN_RADIUS
	e.direction = Vector3.UP
	e.spread = 9.0
	e.initial_velocity_min = COLUMN_SPEED_MIN
	e.initial_velocity_max = COLUMN_SPEED_MAX
	e.damping_min = COLUMN_DAMP
	e.damping_max = COLUMN_DAMP
	e.angular_velocity_min = -60.0
	e.angular_velocity_max = 60.0
	e.position.y = 0.4


## 불꽃 혀 — 기둥 밑동에서 날름 치솟는다. 판을 돌리지 않고 세운다 (둥글게 돌리면 방울이다)
func _tongues() -> CPUParticles3D:
	var e := _emitter(TONGUE_COUNT, TONGUE_LIFE, TONGUE_SIZE, false, FxTex.flame())
	(e.mesh as QuadMesh).center_offset = Vector3(0.0, TONGUE_SIZE.y * 0.4, 0.0)
	e.angle_min = 0.0
	e.angle_max = 0.0
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.9
	e.direction = Vector3.UP
	e.spread = 20.0
	e.initial_velocity_min = 3.0
	e.initial_velocity_max = 6.0
	e.damping_min = 4.0
	e.damping_max = 4.0
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.4
	var lick := Curve.new()
	lick.add_point(Vector2(0.0, 0.6))
	lick.add_point(Vector2(0.25, 1.0))
	lick.add_point(Vector2(1.0, 0.15))
	e.scale_amount_curve = lick
	e.color_ramp = fire_ramp(0.95)
	e.position.y = GROUND
	return e


## 불똥 분수 — 가산, 위로 솟았다 떨어진다
func _sparks() -> CPUParticles3D:
	var e := _emitter(SPARK_COUNT, SPARK_LIFE, Vector2.ONE * SPARK_SIZE, true, null)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 35.0
	e.initial_velocity_min = 8.0
	e.initial_velocity_max = 15.0
	e.gravity = Vector3(0.0, -14.0, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.4
	e.color_ramp = LightningFx.fade_ramp(COLOR_SPARK, 1.0)
	e.scale_amount_curve = LightningFx.fade_curve()
	e.position.y = 0.3
	return e


## 빛살·잔금 전부를 한 메시에 — **처음 한 번만** 깐다 (가운데 = 원점). 꼭짓점 배치는
## `NovaFx.swirl_mesh` 와 같다: `UV` = (나가기 시작하는 시각, 걸리는 시간), `UV2` = (가닥 위
## 자리 0~1, 폭 방향 −1·0·1), `COLOR.r` = 폭 배율. 셰이더가 `now` 로 머리~꼬리만 벌린다
static func ray_mesh() -> ArrayMesh:
	if _ray_mesh != null:
		return _ray_mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for strand in ray_strands():
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
	_ray_mesh = ArrayMesh.new()
	_ray_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _ray_mesh


## 가닥 전부 — [경로(기둥 밑동 기준), 시작(초), 걸리는 시간(초), 폭 배율]. 씨앗이 고정이다
static func ray_strands() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2809290
	var out: Array = []
	# 빛살 — **위쪽으로** 치우쳐 곧게. 옆으로 눕힌 것은 적다 (옆으로 퍼지면 기둥이 아니다)
	for i in RAYS:
		var yaw := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(RAYS)
		var dir := Vector3(sin(yaw), rng.randf_range(0.5, 2.6), cos(yaw)).normalized()
		var length := rng.randf_range(RAY_MIN, RAY_MAX)
		var from := Vector3.UP * rng.randf_range(0.2, 1.2)
		var path := PackedVector3Array()
		for p in RAY_SEGMENTS + 1:
			path.append(from + dir * lerpf(0.2, length, float(p) / float(RAY_SEGMENTS)))
		out.append([path, rng.randf_range(0.0, 0.08), rng.randf_range(0.16, 0.28),
			rng.randf_range(0.5, 1.0)])
	# 잔금 — 기둥 둘레 여러 높이에서 들쭉날쭉한 짧은 빛줄기가 번쩍인다
	for i in CRACKLES:
		var yaw := rng.randf_range(0.0, TAU)
		var from := Vector3(sin(yaw), 0.0, cos(yaw)) * rng.randf_range(0.2, 0.9) \
			+ Vector3.UP * rng.randf_range(0.3, 4.0)
		var away := Vector3(sin(yaw + rng.randf_range(-0.8, 0.8)), rng.randf_range(-0.2, 1.0),
			cos(yaw + rng.randf_range(-0.8, 0.8))).normalized()
		var to := from + away * rng.randf_range(CRACKLE_MIN, CRACKLE_MAX)
		out.append([LightningFx.trail(from, to, 7, 0.26, rng), rng.randf_range(0.02, 0.22),
			rng.randf_range(0.1, 0.18), rng.randf_range(0.4, 0.7)])
	return out


## 빛살 끝 — 가장 늦게 나가는 가닥이 다 지나간 뒤
static func ray_end() -> float:
	var end := 0.0
	for strand in ray_strands():
		end = maxf(end, float(strand[1]) + float(strand[2]) * (1.0 + RAY_TRAIL))
	return end
