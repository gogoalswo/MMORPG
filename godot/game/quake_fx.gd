class_name QuakeFx
extends Node3D

## 천붕각(`sky_breaker`) 연출 — **지면을 내리찍어 땅이 갈라지고, 모래 먼지가
## 충격파처럼 사방으로 터진다** (2026-09-23 요청. 참고 그림 없음 — 옛 웹
## 천붕각의 결론을 따랐다: 가는 금이 어긋난 시간차로 갈라지고, 먼지는 고리가
## 아니라 터짐).
##
## - **금**(`CRACKS`) — 발밑에서 여덟 갈래가 `CRACK_STAGGER` 씩 어긋나게 뻗는다.
##   한꺼번에 띄우면 바닥에 무늬 한 장이 켜진 것이지 갈라진 것이 아니다.
##   갈래마다 **곁가지**가 있다 — 곁가지가 금다움의 전부다. 막 갈라진 금에는
##   **달아오른 심**(가산)이 비쳤다가 식고, 어두운 틈(알파)만 남는다.
## - **먼지 충격파** — 고리 메시가 아니라 **먼지 덩이가 바깥으로 밀려나다
##   멈춘다** (규칙 3절: 퍼지는 동그란 고리는 쓰지 않는다). 두 벌이다:
##   빠르고 낮게 깔리는 앞머리(`FRONT_*`)와, 뒤따라 느릿하게 부푸는 큰 덩이
##   (`PUFF_*`). 가운데서 **곧장 솟는 기둥**(`CORE_*`)이 없으면 가운데가 비어
##   먼지 고리로 보인다 (옛 웹에서 겪은 일).
## - **파편** — 흙 알갱이가 튀어 올랐다 **떨어진다.** 빛이 아니라 흙이라 알파다.
## - **섬광·번쩍임** — 퍼지지 않고 제자리에서 사그라든다 (규칙 3절).
##
## **금 메시는 게임 전체에서 한 번만 깐다** (`_crack_mesh`). 자라는 것은
## 셰이더가 한다 — 꼭짓점마다 "중심에서 몇 m 인가(`UV2.x`)" 와 "언제
## 갈라지기 시작하나(`UV2.y`)" 를 넣어 두고, 셰이더가 `now` 로 잘라 보인다.
## 매 프레임 `SurfaceTool` 로 깎으면 웹·폰에서 히치가 난다 (할퀴기, 2026-09-23).
## **방향은 캐릭터 기준이다** — 노드를 보는 쪽으로 돌린다.
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 끝나면 스스로 풀로 돌아간다 (`FxPool`).

## 금 갈래 수와 길이(m). 캐릭터 키 1.7m 의 1.5~4배(2.6~6.8m, 규칙 3절)이고
## 판정 사거리 6m 안이다 — 금 끝이 사거리를 넘으면 "저기까지 맞는다" 로 읽힌다
const CRACKS := 8
const CRACK_LENGTH := 4.2
const CRACK_SEGMENTS := 6
## 갈래끼리 어긋나는 시간(s). 순서는 둘레를 도는 게 아니라 섞는다 — 돌면
## 금이 아니라 시곗바늘이 한 바퀴 돈 것으로 보인다
const CRACK_STAGGER := 0.02
## 금 끝이 뻗는 빠르기(m/s). 4m 가 0.12초 — "쩍" 하고 갈라져야 한다.
## 먼지 앞머리(12m/s)보다 빨라야 금이 먼지에 묻히기 전에 보인다
const CRACK_SPEED := 34.0
## 어두운 틈과 달아오른 심의 폭(m). **가는 금이지 벌어진 도랑이 아니다** —
## 옛 웹에서 굵게 했다가 "두꺼운 선" 이라는 지적을 받았다
const CRACK_WIDTH := 0.5
const CRACK_GLOW_WIDTH := 0.16
const CRACK_LIFE := 2.0
## 마지막 이만큼만 흐려진다 (규칙 3절)
const CRACK_FADE := 0.8
## 달아오른 심이 식는 시간
const GLOW_LIFE := 0.8

## 지면에서 띄우는 높이 — 바닥과 같은 높이면 깜빡인다
const GROUND := 0.05

## 먼지 앞머리 — 빠르고 낮게, 작은 덩이. 여기가 "충격파" 다.
## 멈추는 거리 = 속도² / (2 × 감속) ≈ 3.8~6m
const FRONT_COUNT := 44
const FRONT_SIZE := 1.5
const FRONT_SPEED_MIN := 10.0
const FRONT_SPEED_MAX := 12.5
const FRONT_DAMP := 13.0
const FRONT_LIFE := 0.85
## 뒤따르는 큰 덩이 — 느리게 밀려나며 부푼다. ≈ 3~5.6m
const PUFF_COUNT := 30
const PUFF_SIZE := 2.3
const PUFF_SPEED_MIN := 7.0
const PUFF_SPEED_MAX := 9.5
const PUFF_DAMP := 8.0
const PUFF_LIFE := 1.5
## 가운데 기둥 — 곧장 솟는다
const CORE_COUNT := 14
const CORE_SIZE := 2.4
const CORE_LIFE := 1.6

## 튀는 흙 알갱이 — 작고 많게 (낙뢰에서 "크고 사각사각하다" 는 말을 들었다)
const CHIP_COUNT := 28
const CHIP_SIZE := 0.2
const CHIP_SPEED_MIN := 5.0
const CHIP_SPEED_MAX := 10.0
const CHIP_LIFE := 0.9
const CHIP_GRAVITY := -22.0

const FLARE_SIZE := 2.4
const FLARE_LIFE := 0.22
const STAIN_SIZE := 5.2
const STAIN_ALPHA := 0.5
const LIGHT_RANGE := 8.0
const LIGHT_ENERGY := 5.0
const LIGHT_LIFE := 0.2
## 화면 흔들림 — **살짝**(2026-09-23 "그럼 살짝 흔들어"). 세기(m)와 길이(s).
## 초점까지 26.7m 라 0.14m 면 720p 에서 4px 남짓이다 — 크면 멀미가 난다.
## 흔드는 것은 `CameraRig.shake` 이고, 부르는 쪽은 `game.gd` 의 `_show_skill` 이다
## (이펙트가 카메라를 찾아다니지 않는다)
const SHAKE := 0.14
const SHAKE_TIME := 0.35

## 옛 천붕각의 금빛(0xffc23c) — 진해야 가산으로 겹쳐도 흰 덩어리가 안 된다
## **"진폭" 강화** — 판정 사거리가 1.5배(6 → 9m)라 땅에 남는 것(금·그을림)과 먼지
## 충격파가 멈추는 거리도 1.5배다. 먼지는 멈추는 거리가 v²/2d 라 속도에 √1.5 를 곱한다
const WIDE := 1.5
## **"균열 지대" 강화** — 진흙 소용돌이(`QuakeParts.Mud`)가 이만큼 남는다. 판정의
## `zoneMs`(3초)와 같아야 "아직 빨려 든다" 가 곧 "아직 피해가 들어온다" 로 읽힌다
const ZONE_TIME := 3.0
## 지대 피해 간격 — 판정의 `zoneTickMs`(0.5초). 틱마다 소용돌이가 한 번 세게 조여든다
const ZONE_TICK := 0.5
## 지대가 끝나고 소용돌이가 흐려지는 시간 (`QuakeParts.Mud.DRY` 와 같다)
const ZONE_FADE := 0.6
const COLOR_GLOW := Color("#ffb13c")
const COLOR_FLARE := Color("#ffd27a")
const COLOR_CRACK := Color("#231910")
const COLOR_STAIN := Color("#3a2c1e")
## 모래 먼지 — 앞머리는 밝고, 뒤 덩이·기둥은 조금 짙다
## 짙은 갈색으로 두었더니 먼지가 아니라 **진흙 얼룩**이었다 (2026-09-23 캡처)
const COLOR_FRONT := Color("#e2cfa8")
const COLOR_PUFF := Color("#d3bb90")
const COLOR_CORE := Color("#c8ad82")
const COLOR_CHIP := Color("#5a4531")

## 금 셰이더. 메시는 다 깔려 있고, **아직 금이 닿지 않은 자리는 투명하다.**
## 앞머리를 `soft`(m) 만큼 부드럽게 죈다 — 딱 자르면 금 끝이 뭉툭하다.
## `%s` 에 혼합이 들어간다 (틈은 알파, 심은 가산)
const CRACK_SHADER := """
shader_type spatial;
render_mode unshaded, %s, cull_disabled, depth_draw_never;
uniform sampler2D streak : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float now = 0.0;
uniform float speed = 26.0;
uniform float soft = 0.3;
void fragment() {
	float front = (now - UV2.y) * speed;
	float shown = clamp((front - UV2.x) / soft, 0.0, 1.0);
	vec4 t = texture(streak, UV);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = tint.a * t.a * shown;
}
"""
static var _shaders: Dictionary = {}
## [틈 메시, 심 메시] — 처음 한 번만 깐다 (보는 쪽 0 기준)
static var _meshes: Array = []

var _t := 0.0
var _started := false
var _crack: MeshInstance3D
var _glow: MeshInstance3D
var _stain: MeshInstance3D
var _flare: MeshInstance3D
var _light: OmniLight3D
var _emitters: Array[CPUParticles3D] = []
## 이번 것의 땅 배율(진폭이면 `WIDE`) · 지대인가 · 몇 초짜리인가 — 되감을 때 정한다
var _mul := 1.0
var _zone := false
var _span := 0.0
## 금·그을림을 그리나 — 진폭만 붙으면 토네이도가 대신하므로 안 그린다
var _ground := true
## 강화 이펙트 — 진폭(모래 토네이도) · 균열 지대(진흙 소용돌이) → `quake_parts.gd`
var _tornado: QuakeParts.Tornado
var _mud: QuakeParts.Mud


## 천붕각을 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다.
## `wide` 면 모래 토네이도("진폭"), `zone` 이면 진흙 소용돌이가 3초 남는다
## ("균열 지대"). 둘은 따로 논다
static func slam(parent: Node3D, at: Vector3, facing: float, wide := false, zone := false) -> QuakeFx:
	var fx := FxPool.take(parent, &"slam") as QuakeFx
	if fx == null:
		fx = QuakeFx.new()
		fx.name = "QuakeFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing, wide, zone)
	return fx


## 끝나는 시각(초). 지대면 진흙 소용돌이가 사라질 때까지
static func span(zone := false) -> float:
	var ground := ZONE_TIME + ZONE_FADE if zone else CRACK_LIFE
	return maxf(ground, maxf(PUFF_LIFE, CORE_LIFE)) + 0.1


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	var meshes := crack_meshes()
	# 그을림 → 틈 → 심 순으로 쌓는다. 같은 높이면 서로 깜빡인다
	_stain = _sheet(LightningFx.stain(COLOR_STAIN))
	var quad := QuadMesh.new()
	quad.size = Vector2(STAIN_SIZE, STAIN_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	_stain.mesh = quad
	_stain.position.y = GROUND

	_crack = _sheet(crack_material("blend_mix", COLOR_CRACK))
	_crack.mesh = meshes[0]
	_crack.position.y = GROUND + 0.01
	# 달아오른 심도 **알파 혼합**이다 — 가산으로 두었더니 밝은 바닥에서 안 보였다
	_glow = _sheet(crack_material("blend_mix", COLOR_GLOW))
	_glow.mesh = meshes[1]
	_glow.position.y = GROUND + 0.02

	_flare = _sheet(LightningFx.flare(COLOR_FLARE))
	var glare := QuadMesh.new()
	glare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.mesh = glare
	_flare.position.y = 0.4

	_light = OmniLight3D.new()
	_light.position.y = 1.0
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_GLOW
	_light.light_energy = LIGHT_ENERGY
	add_child(_light)

	_tornado = QuakeParts.Tornado.new()
	_tornado.build()
	add_child(_tornado)
	_mud = QuakeParts.Mud.new()
	_mud.build()
	add_child(_mud)

	_emitters = [_front(), _puffs(), _core(), _chips()]
	# **만든 다음 프레임에 켠다** — 같은 프레임에 켜면 방출이 안 나온 적이 있다 (3절)
	for e in _emitters:
		e.emitting = false
		add_child(e)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float, wide := false, zone := false) -> void:
	position = at
	_mul = WIDE if wide else 1.0
	_zone = zone
	_span = span(zone)
	# **금은 캐릭터가 보는 쪽 기준이다** — 메시는 보는 쪽 0 으로 깔려 있다.
	# 진폭이면 땅에 눕힌 채로 가로세로만 키운다 (그을림은 `_show_cracks` 가 매 프레임)
	for node in [_crack, _glow]:
		node.rotation.y = facing
		node.scale = Vector3(_mul, 1.0, _mul)
	_stain.rotation.y = facing
	# **진폭이면 먼지 충격파·금 대신 모래 토네이도**가 휘감는다 (2026-09-24 요청).
	# 균열 지대가 같이 붙으면 금은 남긴다 (1.5배)
	_ground = zone or not wide
	_tornado.start(wide)
	_mud.start(zone, _mul)
	_t = 0.0
	_started = false
	_show_cracks()
	_show_flash()


func _process(delta: float) -> void:
	if not _started:
		_started = true
		# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
		# 진폭이면 먼지 충격파(앞머리·덩이·기둥)는 토네이도가 대신한다 — 흙 알갱이만 튄다.
		# 균열 지대면 먼지가 진흙 소용돌이를 덮어서(캡처) 역시 끄고, **흙 알갱이도 끈다**
		# (2026-09-24 "조그만한 모래알 같은 파티클은 제거해")
		for i in _emitters.size():
			if not (_tornado.active or _mud.active) or (i == 3 and not _mud.active):
				_emitters[i].restart()
	_t += delta
	_tornado.tick(delta)
	_mud.tick(delta)
	_show_cracks()
	_show_flash()
	if _t >= _span:
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"slam")


## 금은 **셰이더가 자라게** 하고, 여기서는 시각과 알파만 넣는다
func _show_cracks() -> void:
	# 마지막 0.8초에만 흐려진다 — 금은 남는 자국이다
	var fade := clampf((CRACK_LIFE - _t) / CRACK_FADE, 0.0, 1.0)
	var heat := clampf(1.0 - _t / GLOW_LIFE, 0.0, 1.0)
	var crack: ShaderMaterial = _crack.material_override
	crack.set_shader_parameter(&"now", _t)
	crack.set_shader_parameter(&"tint", Color(COLOR_CRACK.r, COLOR_CRACK.g, COLOR_CRACK.b, fade))
	var glow: ShaderMaterial = _glow.material_override
	glow.set_shader_parameter(&"now", _t)
	var tint := Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, sqrt(heat))
	glow.set_shader_parameter(&"tint", tint)
	_glow.visible = _ground and tint.a > 0.0
	_crack.visible = _ground and fade > 0.0
	# 그을림은 금이 뻗는 동안 같이 넓어진다 (규칙 3절)
	var grow := clampf(_t * CRACK_SPEED / CRACK_LENGTH, 0.0, 1.0)
	_stain.scale = Vector3.ONE * lerpf(0.4, 1.0, sqrt(grow)) * _mul
	_stain.visible = _ground and fade > 0.0
	_stain.material_override.albedo_color = Color(
		COLOR_STAIN.r, COLOR_STAIN.g, COLOR_STAIN.b, fade * STAIN_ALPHA)


## 섬광과 번쩍임은 **세게 켜고 제자리에서 빠르게 죈다**
func _show_flash() -> void:
	var t := _t / FLARE_LIFE
	_flare.visible = t < 1.0
	if _flare.visible:
		_flare.scale = Vector3.ONE * lerpf(0.8, 1.15, sqrt(t))
		_flare.material_override.albedo_color = Color(
			COLOR_FLARE.r, COLOR_FLARE.g, COLOR_FLARE.b, pow(1.0 - t, 1.3))
	_light.visible = _t < LIGHT_LIFE
	if _light.visible:
		_light.light_energy = LIGHT_ENERGY * (1.0 - _t / LIGHT_LIFE)


## 처음 빠르고 끝에서 느려진다 (`QuakeParts.Tornado` 가 퍼질 때 쓴다)
static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 먼지 앞머리 — **지면을 따라 수평으로** 사방에 밀려난다 (`flatness` 1).
## 감속(`damping`)이 세서 빠르게 나갔다 멈춘다 — 그게 충격파의 결이다
func _front() -> CPUParticles3D:
	var e := _motes(FRONT_COUNT, FRONT_LIFE, FRONT_SIZE, COLOR_FRONT, 0.75, true)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.spread = 180.0
	e.flatness = 1.0
	e.initial_velocity_min = FRONT_SPEED_MIN
	e.initial_velocity_max = FRONT_SPEED_MAX
	e.damping_min = FRONT_DAMP
	e.damping_max = FRONT_DAMP
	e.gravity = Vector3(0.0, 0.6, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(1.6)
	e.position.y = 0.25
	return e


## 뒤따르는 큰 덩이 — 앞머리보다 느리고 크게 부푼다. 조금 위로 뜬다
func _puffs() -> CPUParticles3D:
	var e := _motes(PUFF_COUNT, PUFF_LIFE, PUFF_SIZE, COLOR_PUFF, 0.6, true)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.spread = 180.0
	e.flatness = 0.85
	e.initial_velocity_min = PUFF_SPEED_MIN
	e.initial_velocity_max = PUFF_SPEED_MAX
	e.damping_min = PUFF_DAMP
	e.damping_max = PUFF_DAMP
	e.gravity = Vector3(0.0, 0.9, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.position.y = 0.4
	return e


## 가운데 기둥 — 이게 없으면 가운데가 비어 먼지 **고리**로 보인다
func _core() -> CPUParticles3D:
	var e := _motes(CORE_COUNT, CORE_LIFE, CORE_SIZE, COLOR_CORE, 0.4, true)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.6
	e.direction = Vector3.UP
	e.spread = 30.0
	e.initial_velocity_min = 1.8
	e.initial_velocity_max = 3.4
	e.damping_min = 1.6
	e.damping_max = 1.6
	e.scale_amount_curve = LightningFx.grow_curve(1.9)
	e.position.y = 0.3
	return e


## 흙 알갱이 — 튀어 올랐다 **떨어진다.** 빛이 아니므로 가산이 아니다
func _chips() -> CPUParticles3D:
	var e := _motes(CHIP_COUNT, CHIP_LIFE, CHIP_SIZE, COLOR_CHIP, 1.0, false)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.5
	e.direction = Vector3.UP
	e.spread = 50.0
	e.initial_velocity_min = CHIP_SPEED_MIN
	e.initial_velocity_max = CHIP_SPEED_MAX
	e.gravity = Vector3(0.0, CHIP_GRAVITY, 0.0)
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.3
	e.scale_amount_curve = LightningFx.fade_curve()
	e.position.y = GROUND
	return e


## 둥근 점 방출기 한 벌 — 먼지와 알갱이가 같은 뼈대를 쓴다.
## `dust` 면 뭉게뭉게한 먼지 뭉치(`FxTex.puff`), 아니면 둥근 알갱이
func _motes(count: int, life: float, size: float, color: Color, peak: float,
		dust: bool) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 1.0
	var dot := QuadMesh.new()
	dot.size = Vector2(size, size)
	e.mesh = dot
	# 굴린다 — 같은 그림이 여럿이면 찍어낸 것으로 보인다
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -90.0
	e.angular_velocity_max = 90.0
	e.color = color
	e.color_ramp = LightningFx.fade_ramp(color, peak)
	var mat := LightningFx.mote(color)
	# 색은 입자 색(`color_ramp`)으로만 준다 — 재질 색까지 두면 **두 번 곱해져**
	# 옅은 모래색이 주황 갈색이 된다 (2026-09-23 캡처)
	mat.albedo_color = Color.WHITE
	if dust:
		mat.albedo_texture = FxTex.puff()
		# 큰 판이 바닥을 뚫고 들어가면 **땅에 잘린 곧은 모서리**가 보인다.
		# 땅에 가까울수록 옅어지게 한다
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.2
	e.material_override = mat
	return e


## 금 재질 — 틈(`blend_mix`)과 심(`blend_add`)이 셰이더만 다르다
static func crack_material(blend: String, color: Color) -> ShaderMaterial:
	if not _shaders.has(blend):
		var shader := Shader.new()
		shader.code = CRACK_SHADER % blend
		_shaders[blend] = shader
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[blend]
	mat.set_shader_parameter(&"streak", FxTex.streak())
	mat.set_shader_parameter(&"tint", color)
	mat.set_shader_parameter(&"speed", CRACK_SPEED)
	mat.set_shader_parameter(&"now", 0.0)
	return mat


## [틈 메시, 심 메시]. **씨앗을 박아 둔다** — 늘 같은 모양이어야 테스트가 읽고,
## 한 번만 깔면 되니 스킬을 쓸 때 멈칫하지 않는다
static func crack_meshes() -> Array:
	if not _meshes.is_empty():
		return _meshes
	var paths := crack_paths()
	_meshes = [_crack_mesh(paths, CRACK_WIDTH), _crack_mesh(paths, CRACK_GLOW_WIDTH)]
	return _meshes


## 금 경로들 — 각각 [점들, 굵기 배율, 시작 거리(m), 갈라지기 시작하는 시각(s)].
## 곁가지는 **본줄기 금이 그 자리에 닿을 때** 갈라진다 — 시작 거리를 본줄기
## 그 점까지의 길이로 두면 셰이더가 알아서 이어 붙인다
static func crack_paths() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	var order: Array = range(CRACKS)
	# 섞는다 — 둘레를 따라 돌면 시곗바늘이 된다
	for i in range(CRACKS - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp

	var out: Array = []
	var turn := TAU / float(CRACKS)
	for i in CRACKS:
		var angle := turn * float(i) + rng.randf_range(-turn * 0.3, turn * 0.3)
		var reach := CRACK_LENGTH * rng.randf_range(0.8, 1.3)
		var tip := Vector3(sin(angle), 0.0, cos(angle)) * reach
		# 발밑 한가운데서 시작하지 않는다 — 여덟 갈래가 한 점에 모이면 별 모양
		# 스탬프다. 조금 떨어진 곳에서 시작해 가운데는 그을림이 채운다
		var start := tip.normalized() * 0.35
		var path := LightningFx.trail(start, tip, CRACK_SEGMENTS, reach * 0.14, rng, true)
		var delay := float(order[i]) * CRACK_STAGGER
		out.append([path, 1.0, 0.35, delay])
		# 곁가지 — 중간 어디쯤에서 옆으로 벌어져 더 가늘게 뻗는다
		# 곁가지는 **하나씩**만 — 둘씩 달았더니 금이 아니라 마른 나뭇가지였다
		for _k in 1:
			var at := int(path.size() * rng.randf_range(0.35, 0.7))
			var root := path[at]
			var away := angle + rng.randf_range(0.45, 0.95) * (1.0 if rng.randf() > 0.5 else -1.0)
			var twig := root + Vector3(sin(away), 0.0, cos(away)) * reach * rng.randf_range(0.3, 0.45)
			out.append([LightningFx.trail(root, twig, 3, reach * 0.08, rng, true), 0.55,
				0.35 + _length(path, at), delay])
	return out


## 경로 처음부터 `upto` 번째 점까지의 길이
static func _length(path: PackedVector3Array, upto: int) -> float:
	var sum := 0.0
	for i in upto:
		sum += path[i].distance_to(path[i + 1])
	return sum


## 금을 **지면에 누운 리본**으로 깐다. `LightningFx.ribbon` 과 같은 모양인데
## 꼭짓점마다 `UV2` = (중심에서 몇 m, 언제 갈라지나) 를 더 넣는다 — 셰이더가
## 이것으로 금을 자라게 한다. 끝으로 갈수록 가늘어진다
static func _crack_mesh(paths: Array, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in paths:
		var path: PackedVector3Array = entry[0]
		var scale: float = entry[1]
		var dist: float = entry[2]
		var delay: float = entry[3]
		var last := path.size() - 1
		var across: Array = []
		var along_m: Array = []
		for i in path.size():
			var along: Vector3
			if i == 0:
				along = path[1] - path[0]
			elif i == last:
				along = path[last] - path[last - 1]
			else:
				along = path[i + 1] - path[i - 1]
			across.append(Vector3.UP.cross(along.normalized()).normalized())
			along_m.append(dist)
			if i < last:
				dist += path[i].distance_to(path[i + 1])
		for i in last:
			var ha: Vector3 = across[i] * width * scale * 0.5 * (1.0 - 0.85 * float(i) / float(last))
			var hb: Vector3 = across[i + 1] * width * scale * 0.5 * (1.0 - 0.85 * float(i + 1) / float(last))
			var a := path[i]
			var b := path[i + 1]
			var da: float = along_m[i]
			var db: float = along_m[i + 1]
			for side in [[-1.0, 0.0], [1.0, 1.0]]:
				var s: float = side[0]
				var u: float = side[1]
				_vertex(tool, a + ha * s, Vector2(u, 0.0), da, delay)
				_vertex(tool, a, Vector2(0.5, 0.0), da, delay)
				_vertex(tool, b + hb * s, Vector2(u, 1.0), db, delay)
				_vertex(tool, b + hb * s, Vector2(u, 1.0), db, delay)
				_vertex(tool, a, Vector2(0.5, 0.0), da, delay)
				_vertex(tool, b, Vector2(0.5, 1.0), db, delay)
	return tool.commit()


static func _vertex(tool: SurfaceTool, at: Vector3, uv: Vector2, dist: float, delay: float) -> void:
	tool.set_uv(uv)
	tool.set_uv2(Vector2(dist, delay))
	tool.add_vertex(at)
