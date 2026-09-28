class_name BlastFx
extends Node3D

## 폭렬 찍기(`blast_heel`) 연출 — **한 발로 땅을 쾅 찍은 자리가 빛살과 불길로 터지고,
## 작은 불꽃과 불씨가 잔불로 남는다** (2026-09-28 요청, 참고 그림: 방사형 빛살이 튀는 주황 폭발.
## 처음엔 바닥에 용암빛 금을 깔았는데 같은 날 "지면에 용암은 제거해" 로 걷어냈다).
##
## 두 벌이다.
## - **터짐** (0~1.2초) — 섬광·빛, 사방으로 튀는 **빛살**(`RAYS`)과 **잔금 번쩍임**(`CRACKLES`)
##   (띠라서 메시 — 규칙 3절), 발밑에서 부푸는 **불덩이**(`FIRE_*`)와 그 속의 가산 불빛,
##   땅을 따라 밀려나다 멈추는 **바닥 불길**(`WAVE_*` — 고리 메시가 아니라 덩이가 밀려난다),
##   튀는 **불똥**(가산)과 **돌 조각**(알파), 뒤따라 피어오르는 옅은 연기.
## - **잔불** (`EMBER_TIME` 4초 + `EMBER_FADE`) — 발밑 둘레에 흩은 자리에서 **작은 불꽃**이
##   날름거리고, **불씨**가 떠오르고, 가는 연기가 오른다. 그을림이 옅게 스민다.
##
## 불은 빛이지만 **불꽃·불덩이는 알파 혼합**이다 — 밝은 돌바닥에서 가산은 안 보인다
## (천붕각 "달아오른 심" 과 같은 결론). 밝은 노랑~주황을 알파로 칠하고, 그 위에 가산을
## 조금 얹어 어두운 바닥에서도 빛나 보이게 한다.
##
## **판정을 하지 않는다.** 잔불도 그림일 뿐 피해가 없다. 끝나면 풀로 돌아간다 (`FxPool`).
## **방향은 캐릭터 기준이다** — 빛살과 불꽃 자리를 보는 쪽으로 돌린다.

const GROUND := 0.05

## 섬광·빛
const FLARE_SIZE := 3.0
const FLARE_LIFE := 0.26
const LIGHT_RANGE := 11.0
## 9 로 두었더니 캐릭터가 하얗게 날아갔다 (2차 캡처) — 천붕각(5)만큼
const LIGHT_ENERGY := 5.0
const LIGHT_LIFE := 0.35
## 잔불이 비추는 빛 — 일렁이며 잔불과 같이 꺼진다
const EMBER_LIGHT := 1.6

## 불덩이 — 발밑에서 위·옆으로 부풀며 식는다 (노랑 → 주황 → 붉은빛으로 사라진다).
## 크고 오래 두었더니 **크림색 솜뭉치**가 캐릭터를 덮었다 (1차 캡처) — 작고 짧게, 짙게
const FIRE_COUNT := 44
const FIRE_SIZE := 1.8
const FIRE_LIFE := 0.75
## 불덩이 위 가산 불빛 수
const BLAZE_COUNT := 26
## 가운데 불기둥 — 불덩이가 바깥으로만 퍼지면 **가운데가 비어 고리**가 된다 (7차 캡처).
## 천천히 오르며 오래 남아 그 자리를 채운다 (천붕각의 가운데 먼지 기둥과 같은 까닭)
const CORE_COUNT := 16
const CORE_SIZE := 2.0
const CORE_LIFE := 1.3
const FIRE_SPEED_MIN := 3.5
const FIRE_SPEED_MAX := 7.5
const FIRE_DAMP := 5.0
## 불꽃 혀 — 폭발에서 위·바깥으로 날름 치솟는다 (`FxTex.flame`, 세로로 긴 판)
const TONGUE_COUNT := 34
const TONGUE_SIZE := Vector2(0.9, 1.9)
const TONGUE_LIFE := 0.55
## 불덩이 속 달아오른 심 — 가산이라 어두운 바닥에서 빛난다
## 16개를 진하게 겹쳤더니 **포화돼 납작한 주황 판**이 됐다 (3차 캡처) — 적고 옅게
const HEAT_COUNT := 8
const HEAT_SIZE := 3.0
const HEAT_LIFE := 0.55
## 바닥 불길 — 지면을 따라 수평으로 밀려나다 멈춘다. 멈추는 거리 v²/2d 가 사거리(6m) 안
const WAVE_COUNT := 40
const WAVE_SIZE := 1.5
const WAVE_SPEED_MIN := 9.5
const WAVE_SPEED_MAX := 12.0
const WAVE_DAMP := 12.5
const WAVE_LIFE := 0.8
## 불똥 — 튀어 올랐다 떨어진다 (가산)
const SPARK_COUNT := 70
const SPARK_SIZE := 0.13
const SPARK_SPEED_MIN := 6.0
const SPARK_SPEED_MAX := 13.0
const SPARK_LIFE := 1.0
const SPARK_GRAVITY := -14.0
## 돌 조각 — 흙이라 알파다
const CHIP_COUNT := 24
const CHIP_SIZE := 0.22
const CHIP_LIFE := 0.9
## 폭발 뒤 검은 연기 — 늦게 짙어져 천천히 오른다
const SMOKE_COUNT := 16
const SMOKE_SIZE := 2.8
const SMOKE_LIFE := 2.4

## 잔불 — 이만큼 타다가 `EMBER_FADE` 동안 식는다
const EMBER_TIME := 4.0
const EMBER_FADE := 1.2
## 금 위의 작은 불꽃 — 계속 날름거린다. **세운 혀**다 (`FxTex.flame`) — 둥근 뭉치로 띄웠더니
## 동그란 방울이었다 (1차 캡처)
const FLAME_COUNT := 50
const FLAME_SIZE := Vector2(0.55, 1.15)
const FLAME_LIFE := 0.55
## 떠오르는 불씨 (가산)
const CINDER_COUNT := 32
const CINDER_SIZE := 0.09
const CINDER_LIFE := 1.6
## 잔불 연기
const WISP_COUNT := 10
const WISP_SIZE := 1.7
const WISP_LIFE := 2.2
## 빛살 — 발밑에서 사방(위쪽으로 치우쳐)으로 곧게 튀는 빛줄기. 참고 그림 3 의 방사형 불빛이다.
## 띠라서 파티클이 아니라 **메시**(규칙 3절) — 폭렬권 빛살 셰이더(`NovaFx.swirl_material`)를 돌려 쓴다
const RAYS := 30
const RAY_MIN := 2.4
const RAY_MAX := 5.0
const RAY_SEGMENTS := 6
## 잔금 번쩍임 — 들쭉날쭉한 짧은 빛줄기가 폭발 속에서 번쩍인다 (참고 그림 3 의 노란 잔금)
const CRACKLES := 14
const CRACKLE_MIN := 1.4
const CRACKLE_MAX := 3.2
## 빛살 두 겹의 폭(m) — 주황 헤일로 + 흰 심
const RAY_HALO := 0.34
const RAY_CORE := 0.09
## 머리 뒤로 끌리는 꼬리 비율 (셰이더 `trail`)
const RAY_TRAIL := 0.5
## 빛살이 다 지나가는 때(초) — 이 뒤로는 숨긴다 (`ray_end()` 가 가닥에서 셈한 값보다 크게)
const RAY_END := 0.6
## 그을림
const STAIN_SIZE := 6.2
## 그을림은 **폭발이 걷힌 뒤에 스며든다** — 처음부터 짙으면 땅 가까이서 옅어지는 불덩이 사이로
## 비쳐 캐릭터 둘레가 **검은 원판**이 됐다 (6차 캡처)
const STAIN_ALPHA := 0.28
## 그을림이 스미기 시작하는 때(초) — 불덩이·가운데 불기둥이 다 걷힌 뒤
const STAIN_DELAY := 1.3
## 불꽃이 나는 자리 — 발밑에서 이만큼(m) 안쪽에 흩는다
## 3.6 이었을 때 고른 원뿔이 넓게 흩어져 사탕 밭이었다 (2차 캡처) — 가운데로 모은다
const FLAME_REACH := 2.8
## 불꽃이 나는 자리 수
const FLAME_SPOTS := 36

## 흔들림 — 천붕각(0.14 · 0.35)보다 조금 세다
const SHAKE := 0.16
const SHAKE_TIME := 0.4

const COLOR_FLARE := Color("#fff1c4")
const COLOR_LIGHT := Color("#ff8a2a")
const COLOR_HEAT := Color("#ffb347")
const COLOR_SPARK := Color("#ffd27a")
const COLOR_CHIP := Color("#3b2a20")
## 짙은 회색이면 캐릭터 둘레에 **어두운 고리**가 남았다 (4차 캡처) — 옅은 잿빛으로 높이 띄운다
const COLOR_SMOKE := Color("#6e625a")
const COLOR_WISP := Color("#5b514c")
const COLOR_STAIN := Color("#21140d")
const COLOR_RAY := Color("#ff9a30")
const COLOR_RAY_CORE := Color("#fff4c8")

## 빛살·잔금 메시 — 게임 전체에서 한 번만 깐다
static var _ray_mesh: ArrayMesh

var _t := 0.0
var _started := false
var _embers_on := true
var _flare: MeshInstance3D
var _light: OmniLight3D
var _stain: MeshInstance3D
var _ray_halo: MeshInstance3D
var _ray_core: MeshInstance3D
## 한 번 터지는 것 — [불덩이, 불꽃 혀, 심, 바닥 불길, 불똥, 돌 조각, 연기]
var _bursts: Array[CPUParticles3D] = []
## 잔불 동안 계속 나는 것 — [불꽃, 불씨, 연기]
var _embers: Array[CPUParticles3D] = []
## 보는 쪽을 따라 도는 것 (빛살·그을림·불꽃 자리)
var _turn: Node3D


## 폭렬 찍기를 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다
static func blast(parent: Node3D, at: Vector3, facing: float) -> BlastFx:
	var fx := FxPool.take(parent, &"blast") as BlastFx
	if fx == null:
		fx = BlastFx.new()
		fx.name = "BlastFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 끝나는 시각(초) — 잔불이 식고 마지막 연기가 사라질 때
static func span() -> float:
	return maxf(EMBER_TIME + EMBER_FADE, EMBER_TIME + WISP_LIFE) + 0.1


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	_turn = Node3D.new()
	add_child(_turn)
	_stain = _sheet(LightningFx.stain(COLOR_STAIN), _turn)
	var quad := QuadMesh.new()
	quad.size = Vector2(STAIN_SIZE, STAIN_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	_stain.mesh = quad
	_stain.position.y = GROUND
	# 빛살·잔금 두 겹 — 넓은 주황 헤일로 위에 가는 흰 심
	_ray_halo = _sheet(NovaFx.swirl_material(RAY_HALO, COLOR_RAY), _turn)
	_ray_core = _sheet(NovaFx.swirl_material(RAY_CORE, COLOR_RAY_CORE), _turn)
	for node in [_ray_halo, _ray_core]:
		node.mesh = ray_mesh()
		node.position.y = 0.4
		node.material_override.set_shader_parameter(&"trail", RAY_TRAIL)

	_flare = _sheet(LightningFx.flare(COLOR_FLARE), self)
	var glare := QuadMesh.new()
	glare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.mesh = glare
	_flare.position.y = 0.6

	_light = OmniLight3D.new()
	_light.position.y = 1.0
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_LIGHT
	add_child(_light)

	_bursts = [_fireball(), _blaze(), _pillar(), _tongues(), _heat(), _wave(), _sparks(), _chips(), _smoke()]
	var spots := flame_points()
	_embers = [_flames(spots), _cinders(), _wisps(spots)]
	# **만든 다음 프레임에 켠다** — 같은 프레임에 켜면 방출이 안 나온 적이 있다 (3절)
	for e in _bursts:
		e.emitting = false
		add_child(e)
	for e in _embers:
		e.emitting = false
		_turn.add_child(e)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	_turn.rotation.y = facing
	_t = 0.0
	_started = false
	_embers_on = true
	_show()


func _process(delta: float) -> void:
	if not _started:
		_started = true
		# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
		for e in _bursts:
			e.restart()
		for e in _embers:
			e.restart()
	_t += delta
	if _embers_on and _t >= EMBER_TIME:
		# 잔불이 식기 시작하면 새 불꽃은 안 난다 — 떠 있는 것만 제 수명을 마친다
		_embers_on = false
		for e in _embers:
			e.emitting = false
	_show()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"blast")


## 잔불이 얼마나 남았나 (1 = 한창, 0 = 다 식음)
func heat() -> float:
	return clampf((EMBER_TIME + EMBER_FADE - _t) / EMBER_FADE, 0.0, 1.0)


func _show() -> void:
	# 섬광은 **세게 켜고 제자리에서 빠르게 죈다** (규칙 3절 — 퍼지지 않는다)
	var f := _t / FLARE_LIFE
	_flare.visible = f < 1.0
	if _flare.visible:
		_flare.scale = Vector3.ONE * lerpf(0.8, 1.2, sqrt(f))
		_flare.material_override.albedo_color = Color(
			COLOR_FLARE.r, COLOR_FLARE.g, COLOR_FLARE.b, pow(1.0 - f, 1.2))

	var warm := heat()
	# 일렁임 — 두 사인을 곱해 규칙적으로 안 보이게 한다
	var flicker := 0.82 + 0.18 * sin(_t * 13.0) * sin(_t * 7.3 + 1.1)
	if _t < LIGHT_LIFE:
		_light.light_energy = lerpf(EMBER_LIGHT, LIGHT_ENERGY, 1.0 - _t / LIGHT_LIFE)
	else:
		_light.light_energy = EMBER_LIGHT * flicker * warm
	_light.visible = _light.light_energy > 0.01

	for node in [_ray_halo, _ray_core]:
		node.material_override.set_shader_parameter(&"now", _t)
		node.visible = _t < RAY_END

	# 그을림은 폭발이 걷힌 뒤 스며들며 넓어지고(규칙 3절) 잔불과 같이 흐려진다
	var grow := clampf((_t - STAIN_DELAY) / 1.0, 0.0, 1.0)
	_stain.scale = Vector3.ONE * lerpf(0.6, 1.0, sqrt(grow))
	_stain.visible = warm > 0.0
	_stain.material_override.albedo_color = Color(
		COLOR_STAIN.r, COLOR_STAIN.g, COLOR_STAIN.b,
		STAIN_ALPHA * warm * grow)


## 불꽃이 나는 자리 — 발밑 둘레 `FLAME_REACH` 안에 흩는다 (씨앗을 박아 늘 같다).
## 전엔 금 경로 위였는데 바닥 용암을 걷어내며(2026-09-28 요청) 금도 없어졌다.
## 가운데 0.6m 는 비운다 — 캐릭터 발에서 불이 나면 몸이 타는 것으로 보인다
static func flame_points() -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var out := PackedVector3Array()
	for i in FLAME_SPOTS:
		var a := rng.randf_range(0.0, TAU)
		var r := lerpf(0.6, FLAME_REACH, sqrt(rng.randf()))
		out.append(Vector3(sin(a) * r, GROUND, cos(a) * r))
	return out


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


## 가닥 전부 — [경로(가운데 기준), 시작(초), 걸리는 시간(초), 폭 배율]. 씨앗이 고정이다
static func ray_strands() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2809280
	var out: Array = []
	# 빛살 — 곧게, 위쪽으로 치우쳐 사방으로. 조금씩 어긋나 나간다
	for i in RAYS:
		var yaw := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(RAYS)
		var dir := Vector3(sin(yaw), rng.randf_range(-0.05, 0.8), cos(yaw)).normalized()
		var length := rng.randf_range(RAY_MIN, RAY_MAX)
		var path := PackedVector3Array()
		for p in RAY_SEGMENTS + 1:
			path.append(dir * lerpf(0.3, length, float(p) / float(RAY_SEGMENTS)))
		out.append([path, rng.randf_range(0.0, 0.06), rng.randf_range(0.16, 0.28),
			rng.randf_range(0.5, 1.0)])
	# 잔금 — 들쭉날쭉하게 굽은 짧은 빛줄기가 폭발 속 여기저기서 번쩍인다
	for i in CRACKLES:
		var yaw := rng.randf_range(0.0, TAU)
		var from := Vector3(sin(yaw), 0.0, cos(yaw)) * rng.randf_range(0.2, 1.2) \
			+ Vector3.UP * rng.randf_range(0.0, 1.4)
		var away := Vector3(sin(yaw + rng.randf_range(-0.8, 0.8)), rng.randf_range(-0.3, 0.6),
			cos(yaw + rng.randf_range(-0.8, 0.8))).normalized()
		var to := from + away * rng.randf_range(CRACKLE_MIN, CRACKLE_MAX)
		out.append([LightningFx.trail(from, to, 7, 0.28, rng), rng.randf_range(0.02, 0.2),
			rng.randf_range(0.1, 0.18), rng.randf_range(0.4, 0.7)])
	return out


## 빛살 끝 — 가장 늦게 나가는 가닥이 다 지나간 뒤
static func ray_end() -> float:
	var end := 0.0
	for strand in ray_strands():
		end = maxf(end, float(strand[1]) + float(strand[2]) * (1.0 + RAY_TRAIL))
	return end


func _sheet(mat: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## 불 색 띠 — 노랑에서 주황·붉은빛을 지나 그을음으로 식으며 사라진다
static func fire_ramp(peak: float, sooty: bool) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.88, 0.5, peak))
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, Color(0.18, 0.12, 0.1, 0.0) if sooty else Color(0.75, 0.12, 0.02, 0.0))
	# 붉게 식는 꼬리는 짧고 옅게 — 길면 **붉은 솜뭉치**가 부푼 채 남는다 (2차 캡처)
	ramp.add_point(0.2, Color(1.0, 0.62, 0.16, peak))
	ramp.add_point(0.5, Color(0.9, 0.26, 0.05, peak * 0.35))
	if sooty:
		ramp.add_point(0.75, Color(0.32, 0.18, 0.12, peak * 0.3))
	else:
		ramp.add_point(0.8, Color(0.6, 0.1, 0.02, peak * 0.12))
	return ramp


## 불·연기 방출기 한 벌. `puffy` 면 뭉게뭉게한 덩이(`FxTex.puff`), 아니면 둥근 점. `additive` 면 빛이다
func _emitter(count: int, life: float, size: float, additive: bool, puffy: bool) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 1.0
	var dot := QuadMesh.new()
	dot.size = Vector2(size, size)
	e.mesh = dot
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.material_override = _mote_mat(additive, FxTex.puff() if puffy else null)
	return e


## 불덩이는 땅에서 덜 옅어지게 한다 — 1m 에 걸쳐 옅어지면 발밑 한가운데가 비어 보인다
func _fire_emitter(count: int, life: float, size: float, additive: bool) -> CPUParticles3D:
	var e := _emitter(count, life, size, additive, true)
	(e.material_override as StandardMaterial3D).proximity_fade_distance = 0.35
	return e


## 세운 불꽃 방출기 — 세로로 긴 판에 불꽃 혀(`FxTex.flame`)를 **돌리지 않고** 세운다.
## 판의 밑동이 방출 자리에 오게 올려 둔다 (그래야 땅에서 날름거린다)
func _flame_emitter(count: int, life: float, size: Vector2) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 1.0
	var blade := QuadMesh.new()
	blade.size = size
	blade.center_offset = Vector3(0.0, size.y * 0.4, 0.0)
	e.mesh = blade
	var mat := _mote_mat(false, FxTex.flame())
	mat.proximity_fade_distance = 0.2
	e.material_override = mat
	return e


func _mote_mat(additive: bool, texture: Texture2D) -> StandardMaterial3D:
	var mat := LightningFx.mote(Color.WHITE, additive)
	# 색은 입자 색(`color_ramp`)으로만 준다 — 재질 색까지 두면 두 번 곱해진다
	mat.albedo_color = Color.WHITE
	if texture != null:
		mat.albedo_texture = texture
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.0
	return mat


## 불덩이 — 발밑에서 위·옆으로 부풀며 식는다
func _fireball() -> CPUParticles3D:
	var e := _fire_emitter(FIRE_COUNT, FIRE_LIFE, FIRE_SIZE, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.7
	e.direction = Vector3.UP
	e.spread = 80.0
	e.initial_velocity_min = FIRE_SPEED_MIN
	e.initial_velocity_max = FIRE_SPEED_MAX
	e.damping_min = FIRE_DAMP
	e.damping_max = FIRE_DAMP
	e.gravity = Vector3(0.0, 1.8, 0.0)
	e.angular_velocity_min = -60.0
	e.angular_velocity_max = 60.0
	# 노랑보다 주황에서 시작한다 — 밝은 쪽은 위의 가산 불빛(`_blaze`)이 낸다
	var ramp := fire_ramp(0.8, false)
	ramp.set_color(0, Color(1.0, 0.7, 0.28, 0.8))
	e.color_ramp = ramp
	e.scale_amount_curve = LightningFx.grow_curve(1.6)
	e.position.y = 0.5
	return e


## 불덩이 위에 겹치는 **가산 불빛** — 같은 결(`FxTex.puff`)이라 겹친 곳만 밝아져 불덩이 속에
## 결이 생긴다. 알파 불덩이만으로는 한 빛깔로 칠해져 **크림색 구름**이었다 (4차 캡처)
func _blaze() -> CPUParticles3D:
	var e := _fire_emitter(BLAZE_COUNT, FIRE_LIFE * 0.8, FIRE_SIZE, true)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.6
	e.direction = Vector3.UP
	e.spread = 70.0
	e.initial_velocity_min = FIRE_SPEED_MIN
	e.initial_velocity_max = FIRE_SPEED_MAX
	e.damping_min = FIRE_DAMP
	e.damping_max = FIRE_DAMP
	e.gravity = Vector3(0.0, 1.8, 0.0)
	e.angular_velocity_min = -60.0
	e.angular_velocity_max = 60.0
	e.color_ramp = LightningFx.fade_ramp(COLOR_HEAT, 0.3)
	e.scale_amount_curve = LightningFx.grow_curve(1.4)
	e.position.y = 0.5
	return e


## 가운데 불기둥 — 느리게 곧장 오른다
func _pillar() -> CPUParticles3D:
	var e := _fire_emitter(CORE_COUNT, CORE_LIFE, CORE_SIZE, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 25.0
	e.initial_velocity_min = 0.6
	e.initial_velocity_max = 2.0
	e.damping_min = 0.8
	e.damping_max = 0.8
	e.angular_velocity_min = -45.0
	e.angular_velocity_max = 45.0
	e.color_ramp = fire_ramp(0.85, false)
	e.scale_amount_curve = LightningFx.grow_curve(1.5)
	e.position.y = 0.6
	return e


## 불꽃 혀 — 폭발에서 위·바깥으로 날름 치솟는다 (참고 그림 1의 불길)
func _tongues() -> CPUParticles3D:
	var e := _flame_emitter(TONGUE_COUNT, TONGUE_LIFE, TONGUE_SIZE)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 1.3
	e.direction = Vector3.UP
	e.spread = 40.0
	e.initial_velocity_min = 2.5
	e.initial_velocity_max = 5.5
	e.damping_min = 4.0
	e.damping_max = 4.0
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.4
	e.scale_amount_curve = _lick_curve()
	e.color_ramp = fire_ramp(0.95, false)
	e.position.y = GROUND
	return e


## 날름거림 — 확 커졌다가 가늘게 잦아든다
static func _lick_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	return curve


## 달아오른 심 — 가산. 불덩이 속에서 잠깐 하얗게 빛난다
func _heat() -> CPUParticles3D:
	var e := _emitter(HEAT_COUNT, HEAT_LIFE, HEAT_SIZE, true, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.9
	e.direction = Vector3.UP
	e.spread = 60.0
	e.initial_velocity_min = 1.5
	e.initial_velocity_max = 3.5
	e.damping_min = 4.0
	e.damping_max = 4.0
	e.color_ramp = LightningFx.fade_ramp(COLOR_HEAT, 0.4)
	e.scale_amount_curve = LightningFx.grow_curve(1.6)
	e.position.y = 0.7
	return e


## 바닥 불길 — **지면을 따라 수평으로** 사방에 밀려나다 멈춘다 (`flatness` 1)
func _wave() -> CPUParticles3D:
	var e := _emitter(WAVE_COUNT, WAVE_LIFE, WAVE_SIZE, false, true)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.spread = 180.0
	e.flatness = 1.0
	e.initial_velocity_min = WAVE_SPEED_MIN
	e.initial_velocity_max = WAVE_SPEED_MAX
	e.damping_min = WAVE_DAMP
	e.damping_max = WAVE_DAMP
	e.gravity = Vector3(0.0, 1.2, 0.0)
	e.angular_velocity_min = -90.0
	e.angular_velocity_max = 90.0
	e.color_ramp = fire_ramp(0.9, false)
	e.scale_amount_curve = LightningFx.grow_curve(1.5)
	e.position.y = 0.35
	return e


## 불똥 — 가산, 튀어 올랐다 떨어진다
func _sparks() -> CPUParticles3D:
	var e := _emitter(SPARK_COUNT, SPARK_LIFE, SPARK_SIZE, true, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 70.0
	e.initial_velocity_min = SPARK_SPEED_MIN
	e.initial_velocity_max = SPARK_SPEED_MAX
	e.gravity = Vector3(0.0, SPARK_GRAVITY, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.4
	e.color_ramp = LightningFx.fade_ramp(COLOR_SPARK, 1.0)
	e.scale_amount_curve = LightningFx.fade_curve()
	e.position.y = 0.3
	return e


## 돌 조각 — 흙이라 알파, 튀어 올랐다 떨어진다
func _chips() -> CPUParticles3D:
	var e := _emitter(CHIP_COUNT, CHIP_LIFE, CHIP_SIZE, false, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 55.0
	e.initial_velocity_min = 5.0
	e.initial_velocity_max = 10.0
	e.gravity = Vector3(0.0, -22.0, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.3
	e.color_ramp = LightningFx.fade_ramp(COLOR_CHIP, 1.0)
	e.scale_amount_curve = LightningFx.fade_curve()
	e.position.y = GROUND
	return e


## 폭발 뒤 검은 연기 — **처음엔 투명하다가** 불덩이가 식을 즈음 짙어져 천천히 오른다
func _smoke() -> CPUParticles3D:
	var e := _emitter(SMOKE_COUNT, SMOKE_LIFE, SMOKE_SIZE, false, true)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 1.2
	e.direction = Vector3.UP
	e.spread = 35.0
	e.initial_velocity_min = 1.2
	e.initial_velocity_max = 2.6
	e.damping_min = 0.6
	e.damping_max = 0.6
	e.angular_velocity_min = -30.0
	e.angular_velocity_max = 30.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.0))
	ramp.set_color(1, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.0))
	ramp.add_point(0.4, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.28))
	ramp.add_point(0.7, Color(COLOR_SMOKE.r, COLOR_SMOKE.g, COLOR_SMOKE.b, 0.2))
	e.color_ramp = ramp
	e.scale_amount_curve = LightningFx.grow_curve(2.2)
	e.position.y = 1.8
	return e


## 금 위의 작은 불꽃 — 잔불 동안 계속 날름거린다. 오르며 가늘어진다
func _flames(spots: PackedVector3Array) -> CPUParticles3D:
	var e := _flame_emitter(FLAME_COUNT, FLAME_LIFE, FLAME_SIZE)
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.6
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	e.emission_points = spots
	e.direction = Vector3.UP
	e.spread = 12.0
	# 날아가지 않고 제자리에서 날름거린다 — 빠르면 불씨가 된다
	e.initial_velocity_min = 0.4
	e.initial_velocity_max = 1.1
	e.gravity = Vector3(0.0, 1.5, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.4
	e.scale_amount_curve = _lick_curve()
	e.color_ramp = fire_ramp(0.95, false)
	e.scale_amount_min = 0.45
	e.scale_amount_max = 1.4
	return e


## 떠오르는 불씨 — 가산 점, 흔들리며 오른다
func _cinders() -> CPUParticles3D:
	var e := _emitter(CINDER_COUNT, CINDER_LIFE, CINDER_SIZE, true, false)
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.8
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(FLAME_REACH * 0.8, 0.1, FLAME_REACH * 0.8)
	e.direction = Vector3.UP
	e.spread = 25.0
	e.initial_velocity_min = 0.8
	e.initial_velocity_max = 2.0
	e.gravity = Vector3(0.0, 0.3, 0.0)
	e.tangential_accel_min = -1.5
	e.tangential_accel_max = 1.5
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.5
	e.color_ramp = LightningFx.fade_ramp(COLOR_SPARK, 1.0)
	e.position.y = 0.2
	return e


## 잔불 연기 — 가늘고 옅게 오른다
func _wisps(spots: PackedVector3Array) -> CPUParticles3D:
	var e := _emitter(WISP_COUNT, WISP_LIFE, WISP_SIZE, false, true)
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.5
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	e.emission_points = spots
	e.direction = Vector3.UP
	e.spread = 15.0
	e.initial_velocity_min = 0.7
	e.initial_velocity_max = 1.3
	e.angular_velocity_min = -25.0
	e.angular_velocity_max = 25.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(COLOR_WISP.r, COLOR_WISP.g, COLOR_WISP.b, 0.0))
	ramp.set_color(1, Color(COLOR_WISP.r, COLOR_WISP.g, COLOR_WISP.b, 0.0))
	ramp.add_point(0.25, Color(COLOR_WISP.r, COLOR_WISP.g, COLOR_WISP.b, 0.3))
	e.color_ramp = ramp
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.position.y = 0.6
	return e
