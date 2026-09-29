class_name CrushFx
extends Node3D

## 무적파쇄권(`crush_fist`) 연출 — **기마 자세로 1초 동안 파란 기를 모았다가, 주먹을 내지르는
## 순간 주먹 자리에서 흰 심과 파란 가시 빛살이 사방으로 터진다** (2026-09-29 요청: "공수도 자세로
## 기 모은다음 주먹을 강하게 내질러서 이펙트 터트리는 스킬". 참고 그림 — 흰 심에서 날카로운 파란
## 가시가 제멋대로 길게 뻗고, 파란 불티가 튄다).
##
## 시간 순서 (시전부터 초):
## - `GATHER` ~ `PUNCH` — **기를 모은다.** 둘레에서 파란 빛알이 몸으로 빨려 들고, 몸에서 푸른
##   기운이 피어오르고, 허리의 두 주먹이 점점 밝아지고, 몸 둘레에 짧은 전기가 튄다.
## - `PUNCH`(1.08) — **내지른다.** 판정도 이때다(스킬 표의 `delayMs`). 흰 섬광 · 가시 별 두 장 ·
##   날카로운 가시 빛살(메시) · 파란 기운 · 불티 · 발밑 흙먼지 · 화면 흔들림.
##
## **빛살·전기는 파티클이 아니라 메시다** (규칙 3절) — 게임 전체에서 **한 번만** 깔고
## (`ray_mesh`·`crackle_mesh`), 폭렬권 셰이더(`NovaFx.SWIRL_SHADER`)가 `now` 로 머리~꼬리 사이만
## 벌린다. 폭은 시선에 수직이다. 밝은 바닥에서 가산 빛만으로는 윤곽이 흐려서, 빛살 밑에 짙은 남색
## 알파 겹(`ink`)을 먼저 깐다 — 파천장의 먹선과 같은 생각이다.
##
## 퍼지는 동그란 충격 고리는 **쓰지 않는다** (규칙 3절) — 섬광·가시 별은 제자리에서 사그라든다.
## **방향은 캐릭터 기준** — 노드를 보는 쪽으로 돌린다.
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 끝나면 스스로 풀로 돌아간다 (`FxPool`).

## 기마 자세를 잡는 시각 — 동작 `CrushFist` 가 0.15초에 자세를 잡는다
const GATHER := 0.12
## 주먹이 닿는 시각 = 스킬 표의 `delayMs`(1080ms) = 동작 `CrushFist` 의 내지르는 키.
## **셋은 같이 고친다** (`crush_fx_test.gd`)
const PUNCH := 1.08
## 내지른 오른주먹 자리 (캐릭터 기준 — 오른쪽 −X · 앞 +Z). 동작의 1.08 키에서 잰 값이다 —
## `crush_fx_test.gd` 가 모델의 `RightHand` 뼈를 그 순간 재어 대조한다
const FIST := Vector3(-0.07, 1.17, 0.74)
## 터지는 가운데 — 주먹보다 조금 앞
const CENTER := Vector3(-0.07, 1.17, 1.0)
## 기를 모을 때 허리 앞 두 주먹 자리 (동작의 기마 자세)
const HAND_L := Vector3(0.34, 0.85, 0.23)
const HAND_R := Vector3(-0.34, 0.85, 0.23)
## 몸 가운데 — 빛알이 빨려 드는 곳
const BODY := Vector3(0.0, 0.95, 0.1)

## 가시 빛살 — 수 · 길이(m) · 뻗는 시간. 제멋대로 길어야 참고 그림처럼 가시가 된다
const RAYS := 44
const RAY_MIN := 1.0
const RAY_MAX := 2.8
const RAY_SWEEP_MIN := 0.06
const RAY_SWEEP_MAX := 0.12
## 한 가닥을 몇 토막으로 — 꺾인 자리마다 옆으로 조금 비틀어 전기처럼 들쭉날쭉하다
const RAY_SEGMENTS := 6
## 빛살이 다 뻗은 뒤 버티다가 알파를 빼며 사그라드는 시간
const RAY_HOLD := 0.1
const RAY_FADE := 0.4
## 빛살 네 겹의 폭 — 짙은 남색 알파 밑겹 · 파란 헤일로 · 하늘빛 · 흰 심 (규칙 5절: 폭만 다른 겹)
## 1차 캡처(0.5 · 0.42 · 0.16 · 0.05)는 실처럼 가늘고 거의 희게 보였다 — 참고 그림의 가시는 굵고 파랗다
const INK_WIDTH := 0.95
const HALO_WIDTH := 0.8
const MID_WIDTH := 0.3
const CORE_WIDTH := 0.08
## 모을 때 몸 둘레에 튀는 짧은 전기
const CRACKLES := 20
const CRACKLE_WIDTH := 0.1
## 가시 별 두 장 — 크기(m)
const STAR_BIG := 6.4
const STAR_SMALL := 3.2
const STAR_LIFE := 0.42
## 섬광 — 흰 심과 파란 번짐. 퍼지지 않고 제자리에서 사그라든다
const FLASH_SIZE := 1.8
const FLASH_LIFE := 0.2
const BLOOM_SIZE := 6.0
const BLOOM_LIFE := 0.4
## 불티 — 멎는 거리(v²/2d)가 빛살 끝 안이다
const SPARK_COUNT := 120
const SPARK_SPEED_MIN := 4.0
const SPARK_SPEED_MAX := 8.0
const SPARK_DAMP := 12.0
const SPARK_LIFE := 0.6
## 터질 때 밀려나는 파란 기운 (가산 뭉치)
const PUFF_COUNT := 18
const PUFF_SIZE := 1.0
const PUFF_LIFE := 0.6
## 발밑 흙먼지 (알파)
const DUST_COUNT := 16
const DUST_SIZE := 1.1
const DUST_LIFE := 0.8
## 빛 — 모으는 동안 차오르고, 터질 때 번쩍였다 꺼진다
const LIGHT_RANGE := 8.0
const LIGHT_GATHER := 2.0
const LIGHT_BLAST := 7.0
const LIGHT_LIFE := 0.4
## 터질 때 화면 흔들림
const SHAKE := 0.22
const SHAKE_TIME := 0.45

const COLOR_INK := Color(0.03, 0.2, 0.75, 0.6)
const COLOR_HALO := Color(0.08, 0.35, 1.0, 0.8)
const COLOR_MID := Color(0.35, 0.72, 1.0, 0.9)
const COLOR_CORE := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_BLUE := Color(0.25, 0.55, 1.0)
const COLOR_DEEP := Color(0.1, 0.38, 1.0)
const COLOR_SKY := Color(0.6, 0.88, 1.0)
const COLOR_DUST := Color(0.8, 0.8, 0.84)
const COLOR_LIGHT := Color(0.45, 0.7, 1.0)

static var _ink_shader: Shader
static var _ray_mesh: ArrayMesh
static var _crackle_mesh: ArrayMesh

var _t := 0.0
var _gathering := false
var _hit := false
var _ink: MeshInstance3D
var _halo: MeshInstance3D
var _mid: MeshInstance3D
var _core: MeshInstance3D
var _crackle: MeshInstance3D
var _crackle_core: MeshInstance3D
var _fist_l: MeshInstance3D
var _fist_r: MeshInstance3D
var _flash: MeshInstance3D
var _bloom: MeshInstance3D
var _star_big: MeshInstance3D
var _star_small: MeshInstance3D
var _light: OmniLight3D
var _gather: CPUParticles3D
var _aura: CPUParticles3D
var _sparks: CPUParticles3D
var _puffs: CPUParticles3D
var _dust: CPUParticles3D


## 무적파쇄권을 띄운다. `at` 은 시전자 발밑(월드), `facing` 은 보는 쪽(rad).
## 누르자마자 띄운다 — 기를 모으다가 `PUNCH` 에 스스로 터진다.
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다
static func burst(parent: Node3D, at: Vector3, facing: float) -> CrushFx:
	var fx := FxPool.take(parent, &"crush") as CrushFx
	if fx == null:
		fx = CrushFx.new()
		fx.name = "CrushFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 끝나는 시각(초)
static func span() -> float:
	return PUNCH + maxf(0.04 + RAY_SWEEP_MAX + RAY_HOLD + RAY_FADE, DUST_LIFE) + 0.1


## 불티가 가운데에서 가장 멀리 가는 거리(m)
static func spark_reach() -> float:
	return SPARK_SPEED_MAX * SPARK_SPEED_MAX / (2.0 * SPARK_DAMP)


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	_ink = _sheet(ink_material(INK_WIDTH, COLOR_INK))
	_halo = _sheet(_ray_material(HALO_WIDTH, COLOR_HALO))
	_mid = _sheet(_ray_material(MID_WIDTH, COLOR_MID))
	_core = _sheet(_ray_material(CORE_WIDTH, COLOR_CORE))
	for node in [_ink, _halo, _mid, _core]:
		node.mesh = ray_mesh()
		node.position = CENTER
		# 셰이더가 폭을 벌리므로 경계 상자를 넉넉히 — 안 그러면 비껴 볼 때 통째로 잘린다
		node.extra_cull_margin = 3.0

	_crackle = _sheet(_ray_material(CRACKLE_WIDTH * 3.0, COLOR_HALO, 1.0, 0.03, 0.1))
	_crackle_core = _sheet(_ray_material(CRACKLE_WIDTH, COLOR_CORE, 1.0, 0.03, 0.1))
	for node in [_crackle, _crackle_core]:
		node.mesh = crackle_mesh()
		node.position = BODY
		node.extra_cull_margin = 2.0

	_fist_l = _flare(COLOR_SKY, 1.0)
	_fist_l.position = HAND_L
	_fist_r = _flare(COLOR_SKY, 1.0)
	_fist_r.position = HAND_R
	_flash = _flare(Color.WHITE, FLASH_SIZE)
	_flash.position = CENTER
	_bloom = _flare(COLOR_BLUE, BLOOM_SIZE)
	_bloom.position = CENTER
	# 가시 별 — 씨앗이 다른 두 장을 겹쳐 가시를 촘촘하게. **큰 것은 알파(파랑)** 로 빛보다 먼저 깐다 —
	# 가산 파랑은 회색 바닥에서 하늘빛으로 바래서 참고 그림의 짙은 파란 윤곽이 안 나왔다 (1차 캡처)
	_star_big = _flare(COLOR_DEEP, STAR_BIG)
	var deep := _star_big.material_override as StandardMaterial3D
	deep.albedo_texture = FxTex.star(7)
	deep.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	deep.render_priority = -1
	_star_big.position = CENTER
	_star_small = _flare(COLOR_SKY, STAR_SMALL)
	(_star_small.material_override as StandardMaterial3D).albedo_texture = FxTex.star(23)
	_star_small.position = CENTER

	_light = OmniLight3D.new()
	_light.position = BODY
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_LIGHT
	add_child(_light)

	_gather = _gather_emitter()
	_aura = _aura_emitter()
	_sparks = _spark_emitter()
	_puffs = _puff_emitter()
	_dust = _dust_emitter()
	for e in _emitters():
		e.emitting = false
		# 그림자를 끈다 — 기본으로 켜져 있어 땅 가까운 덩이가 어두운 호를 드리운다 (규칙 3절)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
	_gather.position = BODY
	_aura.position = BODY
	for e in [_sparks, _puffs]:
		e.position = CENTER
	_dust.position = Vector3(CENTER.x, 0.2, CENTER.z)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	rotation.y = facing
	_t = 0.0
	_gathering = false
	_hit = false
	_show()


func _process(delta: float) -> void:
	_t += delta
	# 방출기는 제때 처음부터 다시 켠다 (되감아 쓰는 방출기라 `restart`)
	if not _gathering and _t >= GATHER:
		_gathering = true
		_gather.restart()
		_aura.restart()
	if not _hit and _t >= PUNCH:
		_hit = true
		# 모으던 것은 더 안 낸다 — 이미 나온 것은 제 수명대로 사그라든다
		_gather.emitting = false
		_aura.emitting = false
		for e in [_sparks, _puffs, _dust]:
			e.restart()
	_show()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"crush")


func _show() -> void:
	for node in [_ink, _halo, _mid, _core, _crackle, _crackle_core]:
		(node.material_override as ShaderMaterial).set_shader_parameter(&"now", _t)
	var rays := _t >= PUNCH and _t < PUNCH + 0.04 + RAY_SWEEP_MAX + RAY_HOLD + RAY_FADE
	for node in [_ink, _halo, _mid, _core]:
		node.visible = rays
	var charging := _t >= GATHER and _t < PUNCH
	_crackle.visible = charging
	_crackle_core.visible = charging

	# 허리의 두 주먹 — 모을수록 커지고 밝아지며 떨린다. 내지르면 꺼진다
	var k := clampf((_t - GATHER) / (PUNCH - GATHER), 0.0, 1.0)
	for node in [_fist_l, _fist_r]:
		node.visible = charging
		if charging:
			node.scale = Vector3.ONE * lerpf(0.25, 0.6, k * k) * (1.0 + 0.15 * sin(_t * 60.0))
			_tint(node, COLOR_BLUE, lerpf(0.3, 0.75, k))

	var since := _t - PUNCH
	# 흰 섬광과 파란 번짐 — 퍼지지 않고 제자리에서 사그라든다 (규칙 3절)
	_fade_in_place(_flash, Color.WHITE, since / FLASH_LIFE, 0.95)
	_fade_in_place(_bloom, COLOR_DEEP, since / BLOOM_LIFE, 0.45)
	# 가시 별 — 0.05초에 튀어 나와 버티다가 알파가 빠진다. 크기는 거의 그대로다
	var s := since / STAR_LIFE
	for pair in [[_star_big, COLOR_DEEP, 0.85], [_star_small, COLOR_SKY, 1.0]]:
		var node: MeshInstance3D = pair[0]
		node.visible = s >= 0.0 and s < 1.0
		if node.visible:
			node.scale = Vector3.ONE * lerpf(0.55, 1.0, minf(since / 0.05, 1.0)) * lerpf(1.0, 1.08, s)
			_tint(node, pair[1], pair[2] * (1.0 - smoothstep(0.3, 1.0, s)))

	# 빛 — 모으는 동안 차오르고, 터질 때 번쩍였다 꺼진다
	var energy := 0.0
	if charging:
		energy = LIGHT_GATHER * k
	elif since >= 0.0 and since < LIGHT_LIFE:
		energy = LIGHT_BLAST * (1.0 - since / LIGHT_LIFE)
	_light.visible = energy > 0.0
	_light.light_energy = energy
	_light.position = BODY if charging else CENTER


func _fade_in_place(node: MeshInstance3D, color: Color, f: float, peak: float) -> void:
	node.visible = f >= 0.0 and f < 1.0
	if node.visible:
		node.scale = Vector3.ONE * lerpf(0.9, 1.1, sqrt(f))
		_tint(node, color, peak * pow(1.0 - f, 1.8))


static func _tint(node: MeshInstance3D, color: Color, alpha: float) -> void:
	(node.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, alpha)


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 카메라를 마주 보는 섬광 판 (`LightningFx.flare`)
func _flare(color: Color, size: float) -> MeshInstance3D:
	var node := _sheet(LightningFx.flare(color))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	node.mesh = quad
	return node


## 떠 있는 방출기 전부
func _emitters() -> Array:
	return [_gather, _aura, _sparks, _puffs, _dust]


## 기를 모으는 빛알 — 몸 둘레 구에서 나와 **몸 한가운데로 빨려 든다**(음의 방사 가속).
## 모으는 동안 고르게 나온다(`explosiveness` 0 — 가산이라 안 나온 알이 검게 안 보인다)
func _gather_emitter() -> CPUParticles3D:
	var e := NovaFx._emitter(80, PUNCH - GATHER, 0.0, 1.7)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	e.mesh = NovaFx._dot(0.16)
	e.initial_velocity_min = 0.0
	e.initial_velocity_max = 0.3
	e.radial_accel_min = -14.0
	e.radial_accel_max = -9.0
	e.damping_min = 2.0
	e.damping_max = 3.0
	e.gravity = Vector3.ZERO
	# 나타나 몸에 닿을 즈음(수명의 40%) 사라진다 — 가운데에 모여 뭉치지 않게
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.12, 1.0))
	curve.add_point(Vector2(0.4, 0.0))
	curve.add_point(Vector2(1.0, 0.0))
	e.scale_amount_curve = curve
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.4
	e.color_ramp = LightningFx.fade_ramp(COLOR_SKY)
	e.material_override = LightningFx.mote(Color.WHITE, true)
	return e


## 몸에서 피어오르는 푸른 기운 (가산 뭉치) — 모을수록 몸이 파랗게 달아오른다
func _aura_emitter() -> CPUParticles3D:
	var e := NovaFx._emitter(30, PUNCH - GATHER, 0.0, 0.45)
	e.mesh = NovaFx._dot(0.8)
	e.spread = 30.0
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -90.0
	e.angular_velocity_max = 90.0
	e.initial_velocity_min = 0.3
	e.initial_velocity_max = 0.8
	e.gravity = Vector3(0.0, 1.4, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(1.6)
	# 옅게 — 0.3 이면 가산이 겹쳐 몸이 흰 덩어리에 가려졌다 (1차 캡처)
	e.color_ramp = KiFx.soft_ramp(COLOR_DEEP, 0.13)
	var mat := LightningFx.mote(Color.WHITE, true)
	mat.albedo_texture = FxTex.puff()
	e.material_override = mat
	return e


## 터질 때 튀는 불티 — 흰빛으로 튀어 하늘빛 → 파랑으로 식는다
func _spark_emitter() -> CPUParticles3D:
	var e := NovaFx._emitter(SPARK_COUNT, SPARK_LIFE, 1.0, 0.3)
	e.mesh = NovaFx._dot(0.14)
	e.initial_velocity_min = SPARK_SPEED_MIN
	e.initial_velocity_max = SPARK_SPEED_MAX
	e.damping_min = SPARK_DAMP
	e.damping_max = SPARK_DAMP
	e.gravity = Vector3(0.0, -3.0, 0.0)
	e.scale_amount_min = 0.5
	e.scale_amount_max = 1.5
	e.scale_amount_curve = LightningFx.fade_curve()
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_offset(1, 0.35)
	ramp.set_color(1, COLOR_SKY)
	ramp.add_point(1.0, Color(COLOR_BLUE.r, COLOR_BLUE.g, COLOR_BLUE.b, 0.0))
	e.color_ramp = ramp
	e.material_override = LightningFx.mote(Color.WHITE, true)
	return e


## 터질 때 밀려나는 파란 기운 — 가산 뭉치라 진하기를 누른다 (겹치면 흰 공이 된다, 폭렬권 2차)
func _puff_emitter() -> CPUParticles3D:
	var e := NovaFx._emitter(PUFF_COUNT, PUFF_LIFE, 1.0, 0.4)
	e.mesh = NovaFx._dot(PUFF_SIZE)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -90.0
	e.angular_velocity_max = 90.0
	e.initial_velocity_min = 2.0
	e.initial_velocity_max = 4.0
	e.damping_min = 6.0
	e.damping_max = 6.0
	e.gravity = Vector3.ZERO
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color_ramp = KiFx.soft_ramp(COLOR_BLUE, 0.32)
	var mat := LightningFx.mote(Color.WHITE, true)
	mat.albedo_texture = FxTex.puff()
	e.material_override = mat
	return e


## 발밑 흙먼지 — 땅을 따라 낮게 밀려나다 멎는다. 흙이라 알파, 재질 색은 흰색
## (입자 색과 두 번 곱해지면 탁해진다), 땅 가까이서 옅어진다
func _dust_emitter() -> CPUParticles3D:
	var e := NovaFx._emitter(DUST_COUNT, DUST_LIFE, 1.0, 0.4)
	e.mesh = NovaFx._dot(DUST_SIZE)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.flatness = 1.0
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.initial_velocity_min = 3.0
	e.initial_velocity_max = 5.0
	e.damping_min = 8.0
	e.damping_max = 8.0
	e.gravity = Vector3.ZERO
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color_ramp = KiFx.soft_ramp(COLOR_DUST, 0.45)
	var mat := LightningFx.mote(Color.WHITE)
	mat.albedo_texture = FxTex.puff()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.8
	e.material_override = mat
	return e


## 빛살 한 겹의 가산 재질 — 폭렬권 셰이더를 쓰고 꼬리·사라짐만 바꾼다.
## 꼬리를 1 로 두면 머리가 끝에 닿은 뒤에도 가시 전체가 남는다
static func _ray_material(width: float, tint: Color, trail := 1.0,
		hold := RAY_HOLD, fade := RAY_FADE) -> ShaderMaterial:
	var mat := NovaFx.swirl_material(width, tint)
	mat.set_shader_parameter(&"trail", trail)
	mat.set_shader_parameter(&"hold", hold)
	mat.set_shader_parameter(&"fade", fade)
	return mat


## 빛살 밑의 **짙은 남색 알파 겹** — 같은 셰이더를 알파 혼합으로 바꾼 것이다. 빛(가산)보다
## 먼저 그려 가시 윤곽을 밝은 바닥에서도 세운다
static func ink_material(width: float, tint: Color) -> ShaderMaterial:
	if _ink_shader == null:
		_ink_shader = Shader.new()
		_ink_shader.code = NovaFx.SWIRL_SHADER.replace("blend_add", "blend_mix")
	var mat := _ray_material(width, tint)
	mat.shader = _ink_shader
	mat.render_priority = -1
	return mat


## 가시 빛살 전부를 한 메시에 — **처음 한 번만** 만든다 (가운데 = 원점, 보는 쪽 +Z)
static func ray_mesh() -> ArrayMesh:
	if _ray_mesh == null:
		_ray_mesh = _mesh_of(rays())
	return _ray_mesh


## 모으는 동안의 전기 전부를 한 메시에 — 처음 한 번만 (몸 가운데 = 원점)
static func crackle_mesh() -> ArrayMesh:
	if _crackle_mesh == null:
		_crackle_mesh = _mesh_of(crackles())
	return _crackle_mesh


## 가닥 목록 → 메시. 꼭짓점 규격은 폭렬권 셰이더의 것이다 (`NovaFx.swirl_mesh` 와 같다)
static func _mesh_of(strands: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for strand in strands:
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
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 가시 빛살 — [경로(가운데 기준), 시작(초), 걸리는 시간(초), 폭 배율]. 씨앗이 고정이다.
## 사방(구 전체)으로 고르게 뻗되 길이가 제멋대로다. 셋에 하나는 짧고 굵다 — 길이가 고르면
## 동그란 성게가 된다. 꺾인 자리마다 옆으로 조금 비틀어 전기처럼 들쭉날쭉하다
static func rays() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1080
	var out: Array = []
	for i in RAYS:
		# 황금각 나선으로 구에 고르게 — 난수로만 뿌리면 한쪽에 몰린다
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(RAYS)
		var ring := sqrt(1.0 - y * y)
		var a := float(i) * 2.39996 + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a) * ring, y, sin(a) * ring).normalized()
		var short := i % 3 == 0
		var length := rng.randf_range(RAY_MIN, RAY_MIN + 0.6) if short else rng.randf_range(RAY_MIN + 0.6, RAY_MAX)
		# 아래로 뻗는 가시는 땅 위에서 끝낸다 — 가운데가 주먹 높이라 길면 땅을 뚫는다
		if dir.y < 0.0:
			length = minf(length, (CENTER.y - 0.2) / -dir.y)
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var path := PackedVector3Array()
		for p in RAY_SEGMENTS + 1:
			var f := float(p) / float(RAY_SEGMENTS)
			var kink := 0.0 if p == 0 or p == RAY_SEGMENTS else rng.randf_range(-0.07, 0.07) * length
			path.append(dir * lerpf(0.15, length, f) + side * kink)
		out.append([path, PUNCH + rng.randf_range(0.0, 0.04),
			rng.randf_range(RAY_SWEEP_MIN, RAY_SWEEP_MAX),
			rng.randf_range(1.2, 1.6) if short else rng.randf_range(0.7, 1.1)])
	return out


## 모으는 동안 몸 둘레에 튀는 짧은 전기 — 몸을 감는 쪽으로 들쭉날쭉 한 뼘씩
static func crackles() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var out: Array = []
	for i in CRACKLES:
		var at := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.4, 0.75)
		var from := Vector3(cos(at) * radius, rng.randf_range(-0.7, 0.6), sin(at) * radius)
		var along := Vector3(-sin(at), rng.randf_range(-0.8, 0.8), cos(at)).normalized()
		var length := rng.randf_range(0.35, 0.7)
		var path := PackedVector3Array()
		for p in 5:
			var jolt := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.06
			path.append(from + along * length * float(p) / 4.0 + (jolt if p > 0 and p < 4 else Vector3.ZERO))
		# 모을수록 잦아진다 — 앞쪽은 드문드문, 뒤로 갈수록 촘촘하다
		var k := sqrt(float(i) / float(CRACKLES - 1))
		out.append([path, lerpf(GATHER + 0.1, PUNCH - 0.08, k), 0.05, rng.randf_range(0.8, 1.2)])
	return out
