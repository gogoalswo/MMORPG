class_name BlastFx
extends Node3D

## 폭렬 찍기(`blast_heel`) 연출 — **뒤꿈치로 땅을 찍은 자리가 불길로 터지고,
## 달아오른 금과 불씨가 잔불로 남는다** (2026-09-28 요청, 참고 그림 두 장:
## 화면을 뒤덮는 주황·노랑 폭발 / 돌바닥에 용암빛 금이 갈라지고 작은 불꽃·연기가 남은 자리).
##
## 두 벌이다.
## - **터짐** (0~1.2초) — 섬광·빛, 발밑에서 부푸는 **불덩이**(`FIRE_*`)와 그 속의
##   **달아오른 심**(`HEAT_*`, 가산), 땅을 따라 사방으로 밀려나다 멈추는 **바닥 불길**
##   (`WAVE_*` — 고리 메시가 아니라 덩이가 밀려난다, 규칙 3절), 튀는 **불똥**(가산)과
##   **돌 조각**(알파), 뒤따라 피어오르는 **검은 연기**.
## - **잔불** (`EMBER_TIME` 4초 + `EMBER_FADE`) — 천붕각 금 메시를 **그을린 틈 + 용암빛 심 +
##   가산 달무리** 세 겹으로 깔아 일렁이게 하고, 금 둘레에 **녹은 자국**(`POOLS`)이 깜빡인다.
##   **금 위에서 작은 불꽃**이 계속 날름거리고, **불씨**가 떠오르고, 가는 연기가 오른다.
##
## 불은 빛이지만 **불꽃·불덩이는 알파 혼합**이다 — 밝은 돌바닥에서 가산은 안 보인다
## (천붕각 "달아오른 심" 과 같은 결론). 밝은 노랑~주황을 알파로 칠하고, 그 위에 가산을
## 조금 얹어 어두운 바닥에서도 빛나 보이게 한다.
##
## **판정을 하지 않는다.** 잔불도 그림일 뿐 피해가 없다. 끝나면 풀로 돌아간다 (`FxPool`).
## **방향은 캐릭터 기준이다** — 금과 불꽃 자리를 보는 쪽으로 돌린다.

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
## 금 둘레 달무리·그을린 가장자리의 폭(m) — 천붕각 금(0.5)보다 넓게 따로 한 번 깐다
const HALO_WIDTH := 1.3
## 넓은 겹은 발밑 이만큼(m) 안쪽을 서서히 비운다 (금 셰이더의 `inner`). 여덟 갈래가 한가운데서
## 겹쳐 **검은 원판**이 됐고(2차 캡처), 1m 를 잘라내니 잘린 끝단이 **고리**가 됐다(5차 캡처)
const HALO_INNER := 1.8
## 달아오른 발밑 — 둥근 빛 판. 달무리가 비운 발밑이 **맨바닥으로 드러나 검은 구멍**처럼
## 보였다 (8차 캡처). 참고 그림 2 처럼 금이 모이는 한가운데가 가장 뜨겁다
const HOT_SIZE := 3.6
const HOT_ALPHA := 0.6
## 그을림
const STAIN_SIZE := 6.2
## 그을림은 **폭발이 걷힌 뒤에 스며든다** — 처음부터 짙으면 땅 가까이서 옅어지는 불덩이 사이로
## 비쳐 캐릭터 둘레가 **검은 원판**이 됐다 (6차 캡처)
const STAIN_ALPHA := 0.4
## 그을림이 스미기 시작하는 때(초) — 불덩이·가운데 불기둥이 다 걷힌 뒤
const STAIN_DELAY := 1.3
## 불꽃이 나는 금 위의 자리 — 발밑에서 이만큼(m) 안쪽만 쓴다 (끝까지 쓰면 흩어져 보인다)
## 3.6 이었을 때 고른 원뿔이 넓게 흩어져 사탕 밭이었다 (2차 캡처) — 가운데로 모은다
const FLAME_REACH := 2.8

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
const COLOR_CHAR := Color("#170c07")
const COLOR_STAIN := Color("#21140d")
## 용암빛 심 — 두 색 사이를 일렁인다
const COLOR_LAVA := Color("#ffb13a")
const COLOR_LAVA_DEEP := Color("#ff5a14")
## 금 둘레 달무리 (가산)
const COLOR_HALO := Color("#ff6a1c")
## 가운데 흰 심 — 가장 뜨거운 줄
const COLOR_CORE := Color("#fff0a8")

## 달무리 메시 — 게임 전체에서 한 번만 깐다 (천붕각 금 경로 그대로, 폭만 넓다)
static var _wide: ArrayMesh

var _t := 0.0
var _started := false
var _embers_on := true
var _flare: MeshInstance3D
var _light: OmniLight3D
var _stain: MeshInstance3D
var _char: MeshInstance3D
var _halo: MeshInstance3D
var _lava: MeshInstance3D
var _core: MeshInstance3D
var _hot: MeshInstance3D
## 한 번 터지는 것 — [불덩이, 불꽃 혀, 심, 바닥 불길, 불똥, 돌 조각, 연기]
var _bursts: Array[CPUParticles3D] = []
## 잔불 동안 계속 나는 것 — [불꽃, 불씨, 연기]
var _embers: Array[CPUParticles3D] = []
## 보는 쪽을 따라 도는 것 (금·자국·불꽃 자리)
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
	var meshes := QuakeFx.crack_meshes()
	if _wide == null:
		_wide = QuakeFx._crack_mesh(QuakeFx.crack_paths(), HALO_WIDTH)
	# 그을림 → 그을린 가장자리 → 달무리 → 용암 → 흰 심 순으로 쌓는다. 같은 높이면 서로 깜빡인다
	_stain = _sheet(LightningFx.stain(COLOR_STAIN), _turn)
	var quad := QuadMesh.new()
	quad.size = Vector2(STAIN_SIZE, STAIN_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	_stain.mesh = quad
	_stain.position.y = GROUND

	_char = _sheet(QuakeFx.crack_material("blend_mix", COLOR_CHAR), _turn)
	_char.mesh = _wide
	_char.position.y = GROUND + 0.005
	_char.material_override.set_shader_parameter(&"inner", HALO_INNER)
	_hot = _sheet(LightningFx.stain(COLOR_HALO), _turn)
	_hot.material_override.albedo_texture = FxTex.glow()
	var hot := QuadMesh.new()
	hot.size = Vector2(HOT_SIZE, HOT_SIZE)
	hot.orientation = PlaneMesh.FACE_Y
	_hot.mesh = hot
	_hot.position.y = GROUND + 0.008
	_halo = _sheet(QuakeFx.crack_material("blend_add", COLOR_HALO), _turn)
	_halo.mesh = _wide
	_halo.position.y = GROUND + 0.01
	_halo.material_override.set_shader_parameter(&"inner", HALO_INNER)
	_lava = _sheet(QuakeFx.crack_material("blend_mix", COLOR_LAVA), _turn)
	_lava.mesh = meshes[0]
	_lava.position.y = GROUND + 0.015
	_core = _sheet(QuakeFx.crack_material("blend_mix", COLOR_CORE), _turn)
	_core.mesh = meshes[1]
	_core.position.y = GROUND + 0.02

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
	# 막 터졌을 때 가장 밝고, 0.8초에 걸쳐 잔불 밝기로 가라앉는다
	var boom := clampf(1.0 - _t / 0.8, 0.0, 1.0)
	if _t < LIGHT_LIFE:
		_light.light_energy = lerpf(EMBER_LIGHT, LIGHT_ENERGY, 1.0 - _t / LIGHT_LIFE)
	else:
		_light.light_energy = EMBER_LIGHT * flicker * warm
	_light.visible = _light.light_energy > 0.01

	for node in [_char, _halo, _lava, _core]:
		(node.material_override as ShaderMaterial).set_shader_parameter(&"now", _t)
	(_char.material_override as ShaderMaterial).set_shader_parameter(
		&"tint", Color(COLOR_CHAR.r, COLOR_CHAR.g, COLOR_CHAR.b, 0.75 * warm))
	# 용암은 깊은 주황과 밝은 주황 사이를 일렁이고, 흰 심은 식을수록 먼저 사그라든다
	var lava := COLOR_LAVA_DEEP.lerp(COLOR_LAVA, clampf(flicker + boom * 0.5, 0.0, 1.0))
	(_lava.material_override as ShaderMaterial).set_shader_parameter(
		&"tint", Color(lava.r, lava.g, lava.b, warm))
	(_core.material_override as ShaderMaterial).set_shader_parameter(
		&"tint", Color(COLOR_CORE.r, COLOR_CORE.g, COLOR_CORE.b, flicker * warm * warm))
	(_halo.material_override as ShaderMaterial).set_shader_parameter(
		&"tint", Color(COLOR_HALO.r, COLOR_HALO.g, COLOR_HALO.b, (0.7 + 0.3 * boom) * flicker * warm))
	for node in [_char, _halo, _lava, _core, _hot]:
		node.visible = warm > 0.0
	_hot.material_override.albedo_color = Color(
		COLOR_HALO.r, COLOR_HALO.g, COLOR_HALO.b, HOT_ALPHA * flicker * warm)

	# 그을림은 금이 뻗는 동안 넓어지고(규칙 3절) 잔불과 같이 흐려진다
	var grow := clampf(_t * QuakeFx.CRACK_SPEED / QuakeFx.CRACK_LENGTH, 0.0, 1.0)
	_stain.scale = Vector3.ONE * lerpf(0.4, 1.0, sqrt(grow))
	_stain.visible = warm > 0.0
	_stain.material_override.albedo_color = Color(
		COLOR_STAIN.r, COLOR_STAIN.g, COLOR_STAIN.b,
		STAIN_ALPHA * warm * clampf((_t - STAIN_DELAY) / 1.0, 0.0, 1.0))


## 불꽃이 나는 자리 — 금 경로의 점 중 `FLAME_REACH` 안쪽 (보는 쪽 0 기준)
static func flame_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry in QuakeFx.crack_paths():
		var path: PackedVector3Array = entry[0]
		for p in path:
			if Vector2(p.x, p.z).length() <= FLAME_REACH:
				out.append(Vector3(p.x, GROUND, p.z))
	return out


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
