class_name IceFx
extends Node3D

## 빙주각(`frost_pillar`) 연출 — **땅을 짓밟으면 발 주위 사방에서 얼음 기둥이
## 고리를 그리며 솟는다** (2026-09-23 요청: "지면을 강하게 밟아서 땅에서 얼음
## 기둥들이 튀어오르는 스킬". 참고 그림 없음 — 모양은 "사방으로 원형 분출" 로
## 골랐다).
##
## - **기둥**(`RINGS`) — 안쪽 고리부터 바깥으로 `RING_GAP` 씩 늦게 솟는다. 한꺼번에
##   솟으면 바닥에 얼음 숲 한 장이 켜진 것이지 밟은 힘이 퍼져 나간 것이 아니다.
##   기둥 하나는 **큰 결정 하나 + 작은 결정 한둘**이 바깥으로 기운 무더기다 —
##   곧게 선 기둥만 늘어서면 울타리로 보인다.
##   솟을 때 **살짝 넘쳤다 앉고**(easeOutBack), 머물다 **땅으로 도로 꺼진다.**
## - **파편** — 솟을 때 한 번, 꺼질 때 한 번 얼음 조각이 튀었다 떨어진다.
## - **금** — 천붕각의 금 메시를 **얼음 색으로** 다시 쓴다. 바닥에 까는 서리 판(얼음
##   장판)은 **없다** — 넣었다가 "바닥에 얼음 장판 이상하다" 는 말을 듣고 지웠다.
## - **냉기** — 낮게 깔려 밀려나는 흰 안개. 기둥 밑동을 감싼다.
## - **섬광·번쩍임** — 퍼지지 않고 제자리에서 사그라든다 (규칙 3절).
##
## **기둥 메시는 게임 전체에서 한 번만 깐다** (`pillar_mesh`). 솟고 꺼지는 것은
## 셰이더가 한다 — 꼭짓점마다 `UV2` = (언제 솟나, 기둥 길이), `COLOR.rgb` = 기둥
## 축을 넣어 두고, 셰이더가 `now` 로 기둥을 **축을 따라 땅속으로 밀어 넣는다.**
## 땅속 부분은 바닥이 가린다 — 그래서 기둥은 **불투명이고 깊이 검사를 켠다.**
## 매 프레임 메시를 깎으면 웹·폰에서 히치가 난다 (할퀴기, 2026-09-23).
## **방향은 캐릭터 기준이다** — 노드를 보는 쪽으로 돌린다.
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 끝나면 스스로 풀로 돌아간다 (`FxPool`).

## 고리마다 [반지름(m), 기둥 수, 큰 결정 길이(m)]. 안쪽이 크고 바깥이 작다 —
## 밟은 자리에서 멀어질수록 힘이 빠지는 것으로 읽힌다.
## 가장 바깥 기둥 끝이 판정 사거리(5m) 안에 들어야 한다 (`ice_fx_test.gd` 가 잰다).
## **첫 고리를 1.7m 밖에 둔다** — 1.2m 에 네 겹 92개를 세웠더니 얼음 덤불이 되어
## 캐릭터가 묻혔다 (2026-09-23 캡처). 세 겹으로 줄이고 굵게 했다
const RINGS := [[1.7, 7, 2.3], [2.9, 10, 1.9], [3.95, 13, 1.45]]
## 고리끼리 늦게 솟는 시간(s)과, 한 고리 안에서 흩어지는 시간
const RING_GAP := 0.07
const RING_JITTER := 0.03
## 솟는 데 걸리는 시간 — "튀어" 올라야 한다
const RISE := 0.14
## 다 솟은 뒤 서 있는 시간, 꺼지는 데 걸리는 시간
const HOLD := 0.95
const SINK := 0.28
## 바깥으로 기우는 각(도). 곧으면 울타리, 너무 기울면 가시덤불이다
const TILT_MIN := 10.0
const TILT_MAX := 24.0
## 결정 굵기(반지름) = 길이 × 이것
const GIRTH := 0.17
## 결정 옆면 수와, 몸통이 끝나고 뾰족한 머리가 시작하는 자리(길이 비율)
const SIDES := 6
const SHOULDER := 0.72
## 결정 밑동을 땅에 묻는다 — 솟을 때 1할쯤 넘쳤다 앉으므로(easeOutBack) 그만큼은
## 묻어야 뚫린 밑동이 안 보인다
const SUNK := 0.3

## 지면 자국이 사는 시간과, 마지막 이만큼만 흐려진다 (규칙 3절)
const MARK_LIFE := 1.9
const MARK_FADE := 0.8
## 금 심(푸른 빛)이 식는 시간
const GLOW_LIFE := 0.6
const GROUND := 0.05

## 솟을 때 **기둥 밑동에서** 튀는 얼음 조각 — 길쭉한 조각(`COUNT`)과 뭉툭한 덩이(`BITS`)
## 두 벌이다. 한 모양만 쓰면 찍어낸 것으로 보인다
const BURST_COUNT := 24
const BURST_BITS := 20
const BURST_SPEED_MIN := 3.5
const BURST_SPEED_MAX := 7.0
const BURST_LIFE := 0.8
## 꺼질 때 **기둥 허리에서** 부서지는 조각
const SHATTER_COUNT := 30
const SHATTER_BITS := 30
const SHATTER_SPEED_MIN := 2.0
const SHATTER_SPEED_MAX := 5.0
const SHATTER_LIFE := 0.7
const SHARD_GRAVITY := -20.0
## 조각이 도는 빠르기(도/s). 입자는 Y 축으로만 돌릴 수 있어서, 조각 메시를
## 비스듬히 눕혀 깔아 둔다 — 그러면 Y 로 돌려도 구르며 떨어지는 것으로 보인다
const SHARD_SPIN := 540.0
## 냉기 — **기둥 밑동마다** 흘러나와 바깥으로 느리게 번진다. 한가운데서 사방으로
## 밀려나게 했더니 "캐릭터에서 나온다" 로 읽혔다 (2026-09-23 지적)
const MIST_COUNT := 44
const MIST_SIZE := 1.5
const MIST_SPEED_MIN := 0.8
const MIST_SPEED_MAX := 2.0
const MIST_DAMP := 0.9
const MIST_LIFE := 1.2
## 1 이면 한꺼번에 — 낮출수록 수명에 걸쳐 나눠 흘린다. 기둥이 차례로 솟는 동안
## 계속 피어오르게 반쯤 둔다 (마지막 것도 이펙트가 끝나기 전에 스러진다)
const MIST_EXPLOSIVE := 0.5

const FLARE_SIZE := 2.6
const FLARE_LIFE := 0.22
const LIGHT_RANGE := 9.0
const LIGHT_ENERGY := 4.0
const LIGHT_LIFE := 0.3
## 화면 흔들림 — 천붕각(0.14)보다 조금 약하게. 밟는 것이지 무너뜨리는 것이 아니다
const SHAKE := 0.11
const SHAKE_TIME := 0.3

## 얼음 — 밑동은 짙은 청록, 머리는 거의 흰 하늘색, 모서리·가장자리는 흰 빛
const COLOR_DEEP := Color("#1f6fae")
const COLOR_PALE := Color("#bdeeff")
const COLOR_RIM := Color("#f4fdff")
const COLOR_CRACK := Color("#15314d")
const COLOR_GLOW := Color("#6fd6ff")
const COLOR_FLARE := Color("#bfeeff")
const COLOR_MIST := Color("#e6f7ff")

## 기둥 셰이더. 메시는 다 깔려 있고, **아직 솟지 않은 기둥은 땅속에 있다.**
## 빛은 받지 않는다(unshaded) — 면마다 구워 둔 밝기(`COLOR.a`)와 가장자리
## 빛(`VIEW` 와의 각)으로 결정다운 면을 낸다. 밤·낮 조명에 따라 얼음색이
## 흐려지지 않게 하려는 것이다
const PILLAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;
uniform float now = 0.0;
uniform float rise = 0.14;
uniform float hold = 0.95;
uniform float sink = 0.28;
uniform vec4 deep : source_color = vec4(0.12, 0.44, 0.68, 1.0);
uniform vec4 pale : source_color = vec4(0.74, 0.93, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
varying float shade;
void vertex() {
	float t = clamp((now - UV2.x) / rise, 0.0, 1.0) - 1.0;
	// easeOutBack — 튀어나와 살짝 넘쳤다가 앉는다 (t = 0 이면 0, 1 이면 1)
	float up = 1.0 + 2.70158 * t * t * t + 1.70158 * t * t;
	float s = clamp((now - UV2.x - rise - hold) / sink, 0.0, 1.0);
	float lift = up - s * s;
	vec3 axis = COLOR.rgb * 2.0 - 1.0;
	VERTEX -= axis * UV2.y * (1.0 - lift);
	shade = COLOR.a;
}
void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);
	float edge = smoothstep(0.72, 1.0, abs(UV.x * 2.0 - 1.0));
	vec3 c = mix(deep.rgb, pale.rgb, clamp(UV.y * 0.75 + shade * 0.5 - 0.15, 0.0, 1.0));
	c = mix(c, rim_color.rgb, clamp(rim * 0.8 + edge * 0.55 + smoothstep(0.85, 1.0, UV.y) * 0.4, 0.0, 1.0));
	ALBEDO = c;
}
"""
## 조각 셰이더 — 기둥 셰이더의 색 칠하기만 떼어 왔다. 빛(`light`)은 월드 방향이라
## 화면 공간으로 돌려 면 방향(`NORMAL`)과 댄다
const SHARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 deep : source_color = vec4(0.12, 0.44, 0.68, 1.0);
uniform vec4 pale : source_color = vec4(0.74, 0.93, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform vec3 light = vec3(0.35, 0.85, 0.4);
void fragment() {
	vec3 l = normalize((VIEW_MATRIX * vec4(light, 0.0)).xyz);
	float shade = clamp(dot(NORMAL, l) * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float edge = smoothstep(0.7, 1.0, abs(UV.x * 2.0 - 1.0));
	vec3 c = mix(deep.rgb, pale.rgb, clamp(shade * 0.9 + UV.y * 0.3 - 0.1, 0.0, 1.0));
	c = mix(c, rim_color.rgb, clamp(rim * 0.8 + edge * 0.5, 0.0, 1.0));
	ALBEDO = c;
}
"""
static var _shader: Shader
static var _mesh: ArrayMesh
## 굽는 빛의 방향 — 위 앞쪽. 면마다 밝기가 달라야 각진 결정으로 보인다
const LIGHT_DIR := Vector3(0.35, 0.85, 0.4)

var _t := 0.0
var _started := false
var _shattered := false
var _pillars: MeshInstance3D
var _crack: MeshInstance3D
var _glow: MeshInstance3D
var _flare: MeshInstance3D
var _light: OmniLight3D
var _burst: CPUParticles3D
var _burst_bits: CPUParticles3D
var _shatter: CPUParticles3D
var _shatter_bits: CPUParticles3D
var _mist: CPUParticles3D
## 조각 재질 — 기둥과 같은 결(면 밝기·가장자리 흰 빛)이고 게임에 하나다
static var _shard_mat: ShaderMaterial
## [길쭉한 조각, 뭉툭한 덩이]
static var _shard_meshes: Array = []


## 빙주각을 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다
static func burst(parent: Node3D, at: Vector3, facing: float) -> IceFx:
	var fx := FxPool.take(parent, &"ice") as IceFx
	if fx == null:
		fx = IceFx.new()
		fx.name = "IceFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 마지막 기둥이 솟기 시작하는 시각
static func last_start() -> float:
	return RING_GAP * float(RINGS.size() - 1) + RING_JITTER + 0.02


## 기둥이 꺼지기 시작하는 시각 (첫 고리 기준) — 부서지는 조각도 이때 튄다
static func shatter_at() -> float:
	return RISE + HOLD


## 끝나는 시각(초)
static func span() -> float:
	var pillars := last_start() + RISE + HOLD + SINK
	return maxf(pillars, maxf(MARK_LIFE, shatter_at() + SHATTER_LIFE)) + 0.1


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	# 틈 → 심 순으로 쌓는다. 같은 높이면 서로 깜빡인다.
	# 금은 천붕각 것을 **얼음 색으로** 다시 쓴다 — 메시도 셰이더도 같은 것이다
	var cracks := QuakeFx.crack_meshes()
	_crack = _sheet(QuakeFx.crack_material("blend_mix", COLOR_CRACK))
	_crack.mesh = cracks[0]
	_crack.position.y = GROUND + 0.01
	_glow = _sheet(QuakeFx.crack_material("blend_mix", COLOR_GLOW))
	_glow.mesh = cracks[1]
	_glow.position.y = GROUND + 0.02

	_pillars = _sheet(pillar_material())
	_pillars.mesh = pillar_mesh()
	# 셰이더가 기둥을 땅속으로 밀어 넣으므로 경계 상자를 넉넉히 — 안 그러면
	# 카메라가 조금만 비껴도 통째로 잘려 안 그린다
	_pillars.extra_cull_margin = 3.0

	_flare = _sheet(LightningFx.flare(COLOR_FLARE))
	var glare := QuadMesh.new()
	glare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.mesh = glare
	_flare.position.y = 0.4

	_light = OmniLight3D.new()
	_light.position.y = 1.2
	_light.omni_range = LIGHT_RANGE
	_light.light_color = COLOR_GLOW
	_light.light_energy = LIGHT_ENERGY
	add_child(_light)

	var feet := emit_points(false)
	var waist := emit_points(true)
	_burst = _shards(BURST_COUNT, BURST_LIFE, BURST_SPEED_MIN, BURST_SPEED_MAX, 25.0, 0, feet)
	_burst_bits = _shards(BURST_BITS, BURST_LIFE, BURST_SPEED_MIN, BURST_SPEED_MAX, 35.0, 1, feet)
	_shatter = _shards(SHATTER_COUNT, SHATTER_LIFE, SHATTER_SPEED_MIN, SHATTER_SPEED_MAX, 50.0, 0, waist)
	_shatter_bits = _shards(SHATTER_BITS, SHATTER_LIFE, SHATTER_SPEED_MIN, SHATTER_SPEED_MAX, 60.0, 1, waist)
	_mist = _mist_emitter(feet)
	# **만든 다음 프레임에 켠다** — 같은 프레임에 켜면 방출이 안 나온 적이 있다 (3절)
	for e in _emitters():
		e.emitting = false
		add_child(e)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	# **캐릭터가 보는 쪽 기준이다** — 메시는 보는 쪽 0 으로 깔려 있다
	# 방출기도 돌린다 — 나오는 자리가 기둥 밑동이라 기둥과 같이 돌아야 한다
	for node in [_crack, _glow, _pillars] + _emitters():
		node.rotation.y = facing
	_t = 0.0
	_started = false
	_shattered = false
	_show()


func _process(delta: float) -> void:
	if not _started:
		_started = true
		# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
		_burst.restart()
		_burst_bits.restart()
		_mist.restart()
	_t += delta
	if not _shattered and _t >= shatter_at():
		_shattered = true
		_shatter.restart()
		_shatter_bits.restart()
	_show()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"ice")


func _show() -> void:
	(_pillars.material_override as ShaderMaterial).set_shader_parameter(&"now", _t)
	_pillars.visible = _t < last_start() + RISE + HOLD + SINK

	# 지면 자국 — 마지막 0.8초에만 흐려진다
	var fade := clampf((MARK_LIFE - _t) / MARK_FADE, 0.0, 1.0)
	var heat := clampf(1.0 - _t / GLOW_LIFE, 0.0, 1.0)
	var crack: ShaderMaterial = _crack.material_override
	crack.set_shader_parameter(&"now", _t)
	crack.set_shader_parameter(&"tint", Color(COLOR_CRACK.r, COLOR_CRACK.g, COLOR_CRACK.b, fade))
	var glow: ShaderMaterial = _glow.material_override
	glow.set_shader_parameter(&"now", _t)
	glow.set_shader_parameter(&"tint", Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, sqrt(heat)))
	_crack.visible = fade > 0.0
	_glow.visible = heat > 0.0

	# 섬광과 번쩍임은 **세게 켜고 제자리에서 빠르게 죈다**
	var t := _t / FLARE_LIFE
	_flare.visible = t < 1.0
	if _flare.visible:
		_flare.scale = Vector3.ONE * lerpf(0.8, 1.15, sqrt(t))
		_flare.material_override.albedo_color = Color(
			COLOR_FLARE.r, COLOR_FLARE.g, COLOR_FLARE.b, pow(1.0 - t, 1.3))
	_light.visible = _t < LIGHT_LIFE
	if _light.visible:
		_light.light_energy = LIGHT_ENERGY * (1.0 - _t / LIGHT_LIFE)


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 떠 있는 방출기 전부
func _emitters() -> Array:
	return [_burst, _burst_bits, _shatter, _shatter_bits, _mist]


## 얼음 조각 — **기둥마다** 그 자리(`points`)에서 바깥 위로 튀었다 **구르며 떨어진다.**
## `shape` 0 은 길쭉한 조각, 1 은 뭉툭한 덩이. 옛날엔 흰 삼각기둥(`PrismMesh`)이
## 날아가는 쪽으로 누워 흰 바늘로 보였다 (2026-09-23 "파편이 생긴 게 좀 다르게")
func _shards(count: int, life: float, speed_min: float, speed_max: float,
		spread: float, shape: int, points: Array) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 0.85
	e.mesh = shard_meshes()[shape]
	_from_points(e, points, 0.9)
	e.spread = spread
	e.initial_velocity_min = speed_min
	e.initial_velocity_max = speed_max
	e.gravity = Vector3(0.0, SHARD_GRAVITY, 0.0)
	e.particle_flag_rotate_y = true
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -SHARD_SPIN
	e.angular_velocity_max = SHARD_SPIN
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.5
	e.scale_amount_curve = LightningFx.fade_curve()
	e.material_override = shard_material()
	return e


## 냉기 — **기둥 밑동마다** 흘러나와 바깥으로 느리게 번지며 조금 떠오른다.
## 먼지와 같은 뭉치(`FxTex.puff`)를 흰 하늘색으로 쓴다. 재질 색은 흰색이다 —
## 입자 색과 두 번 곱해지면 탁해진다
func _mist_emitter(points: Array) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = MIST_COUNT
	e.lifetime = MIST_LIFE
	e.one_shot = true
	e.explosiveness = MIST_EXPLOSIVE
	var dot := QuadMesh.new()
	dot.size = Vector2(MIST_SIZE, MIST_SIZE)
	e.mesh = dot
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -60.0
	e.angular_velocity_max = 60.0
	_from_points(e, points, 0.25)
	e.spread = 30.0
	e.initial_velocity_min = MIST_SPEED_MIN
	e.initial_velocity_max = MIST_SPEED_MAX
	e.damping_min = MIST_DAMP
	e.damping_max = MIST_DAMP
	e.gravity = Vector3(0.0, 0.35, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color = COLOR_MIST
	e.color_ramp = LightningFx.fade_ramp(COLOR_MIST, 0.5)
	var mat := LightningFx.mote(COLOR_MIST)
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = FxTex.puff()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.0
	e.material_override = mat
	return e


## 방출기가 `points` = [자리들, 바깥 방향들] 에서 나오게 한다. 방향은 바깥에서
## `up` 만큼 위로 든다. 입자는 `direction`(+Z)을 자리마다의 방향으로 돌려 쓴다
static func _from_points(e: CPUParticles3D, points: Array, up: float) -> void:
	var dirs := PackedVector3Array()
	for d: Vector3 in points[1]:
		dirs.append((d + Vector3.UP * up).normalized())
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	e.emission_points = points[0]
	e.emission_normals = dirs
	e.direction = Vector3(0.0, 0.0, 1.0)


## 큰 결정마다 [자리들, 바깥 방향들]. `waist` 면 기둥 허리(부서질 때), 아니면 밑동
static func emit_points(waist: bool) -> Array:
	var at := PackedVector3Array()
	var out := PackedVector3Array()
	for c in crystals():
		if not c[5]:
			continue
		var base: Vector3 = c[0]
		var axis: Vector3 = c[1]
		at.append(base + axis * float(c[2]) * 0.45 if waist else base + Vector3.UP * 0.2)
		out.append(Vector3(base.x, 0.0, base.z).normalized())
	return [at, out]


## 조각 재질. 기둥과 같은 색·가장자리 빛이다. 입자라 꼭짓점 색을 못 쓰므로
## 면 밝기는 면 방향과 고정된 빛(`LIGHT_DIR`)으로 그 자리에서 셈한다
static func shard_material() -> ShaderMaterial:
	if _shard_mat != null:
		return _shard_mat
	var shader := Shader.new()
	shader.code = SHARD_SHADER
	_shard_mat = ShaderMaterial.new()
	_shard_mat.shader = shader
	_shard_mat.set_shader_parameter(&"deep", COLOR_DEEP)
	_shard_mat.set_shader_parameter(&"pale", COLOR_PALE)
	_shard_mat.set_shader_parameter(&"rim_color", COLOR_RIM)
	_shard_mat.set_shader_parameter(&"light", LIGHT_DIR.normalized())
	return _shard_mat


## [길쭉한 조각, 뭉툭한 덩이] — 모난 쌍뿔(위아래가 뾰족한 결정)이다. 한 번만 깐다
static func shard_meshes() -> Array:
	if _shard_meshes.is_empty():
		_shard_meshes = [_shard(5, 0.06, 0.26, -0.1, 20260926),
			_shard(4, 0.11, 0.1, -0.09, 20260927)]
	return _shard_meshes


## 쌍뿔 조각 하나. 둘레 꼭짓점을 흔들어 모나게 하고, **55° 눕혀** 깐다 —
## 입자가 Y 로만 돌아서, 곧게 세우면 제자리 팽이가 된다
static func _shard(sides: int, radius: float, top: float, bottom: float,
		seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lean := Basis(Vector3.RIGHT, deg_to_rad(55.0))
	var ring: Array = []
	for i in sides:
		var a := TAU * float(i) / float(sides) + rng.randf_range(-0.3, 0.3)
		var r := radius * rng.randf_range(0.7, 1.25)
		ring.append(Vector3(cos(a) * r, rng.randf_range(-0.02, 0.02), sin(a) * r))
	var up := Vector3(rng.randf_range(-0.03, 0.03), top, rng.randf_range(-0.03, 0.03))
	var down := Vector3(rng.randf_range(-0.03, 0.03), bottom, rng.randf_range(-0.03, 0.03))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % sides]
		for face in [[a, b, up, Vector2(0.0, 0.4), Vector2(1.0, 0.4), Vector2(0.5, 1.0)],
				[b, a, down, Vector2(1.0, 0.4), Vector2(0.0, 0.4), Vector2(0.5, 0.0)]]:
			var p0: Vector3 = face[0]
			var p1: Vector3 = face[1]
			var p2: Vector3 = face[2]
			var n := (p1 - p0).cross(p2 - p0).normalized()
			if n.dot(p0 + p1 + p2) < 0.0:
				n = -n
			for k in 3:
				tool.set_normal(lean * n)
				tool.set_uv(face[3 + k])
				tool.add_vertex(lean * (face[k] as Vector3))
	return tool.commit()


## 기둥 재질 — 셰이더는 하나를 같이 쓰고, `now` 가 이펙트마다 달라 재질은 따로다
static func pillar_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PILLAR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter(&"rise", RISE)
	mat.set_shader_parameter(&"hold", HOLD)
	mat.set_shader_parameter(&"sink", SINK)
	mat.set_shader_parameter(&"deep", COLOR_DEEP)
	mat.set_shader_parameter(&"pale", COLOR_PALE)
	mat.set_shader_parameter(&"rim_color", COLOR_RIM)
	mat.set_shader_parameter(&"now", 0.0)
	return mat


## 결정들 — 각각 [밑동, 축(단위), 길이(m), 굵기(m), 솟기 시작하는 시각(s), 큰 결정인가].
## **씨앗을 박아 둔다** — 늘 같은 모양이어야 테스트가 읽고, 한 번만 깔면 된다
static func crystals() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var out: Array = []
	for k in RINGS.size():
		var radius: float = RINGS[k][0]
		var count: int = RINGS[k][1]
		var tall: float = RINGS[k][2]
		var turn := TAU / float(count)
		# 고리마다 돌려 놓는다 — 안팎 기둥이 한 줄로 서면 바큇살이다
		var offset := rng.randf() * turn
		for i in count:
			var angle := offset + turn * float(i) + rng.randf_range(-turn * 0.25, turn * 0.25)
			var out_dir := Vector3(sin(angle), 0.0, cos(angle))
			var r := radius + rng.randf_range(-0.2, 0.2)
			var base := out_dir * r
			var start := RING_GAP * float(k) + rng.randf_range(0.0, RING_JITTER)
			var length := tall * rng.randf_range(0.8, 1.2)
			var tilt := deg_to_rad(rng.randf_range(TILT_MIN, TILT_MAX))
			out.append([base, _axis(out_dir, tilt, rng), length, length * GIRTH, start, true])
			# 곁 결정 — 밑동 옆에서 더 기울어 짧게. 없거나 하나 — 둘씩 달면 덤불이다
			for _j in rng.randi_range(0, 1):
				var side := angle + rng.randf_range(0.35, 0.9) * (1.0 if rng.randf() > 0.5 else -1.0)
				var side_dir := Vector3(sin(side), 0.0, cos(side))
				var small := length * rng.randf_range(0.4, 0.6)
				var lean := tilt + deg_to_rad(rng.randf_range(12.0, 22.0))
				# 곁 결정은 **안쪽으로** 조금 물려 둔다 — 바깥으로 두면 사거리를 넘는다
				var at := base + side_dir * length * GIRTH * 1.2 - out_dir * 0.15
				out.append([at, _axis(side_dir, lean, rng), small, small * GIRTH * 1.1,
					start + 0.02, false])
	return out


## 위(Y)에서 `away` 쪽으로 `tilt` 만큼 기운 축. 조금 비튼다 — 다 같은 쪽으로
## 기울면 빗으로 빗은 것처럼 보인다
static func _axis(away: Vector3, tilt: float, rng: RandomNumberGenerator) -> Vector3:
	var twist := away.rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
	return (Vector3.UP * cos(tilt) + twist * sin(tilt)).normalized()


## 결정 무더기 메시 — 처음 한 번만 깐다
static func pillar_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light := LIGHT_DIR.normalized()
	for c in crystals():
		_crystal(tool, c[0], c[1], c[2], c[3], c[4], light)
	_mesh = tool.commit()
	return _mesh


## 결정 하나 — 육각 몸통(위로 조금 가늘어진다) + 뾰족한 머리.
## 밑동은 `SUNK` 만큼 땅에 묻힌다
static func _crystal(tool: SurfaceTool, base: Vector3, axis: Vector3, length: float,
		girth: float, start: float, light: Vector3) -> void:
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var foot := base - axis * SUNK
	var total := length + SUNK
	var neck := foot + axis * total * SHOULDER
	var tip := foot + axis * total
	var twist := fmod(length * 7.3, TAU)
	var low: Array = []
	var high: Array = []
	for i in SIDES:
		var a := twist + TAU * float(i) / float(SIDES)
		var out := u * cos(a) + v * sin(a)
		low.append(foot + out * girth)
		high.append(neck + out * girth * 0.82)
	var code := Color(axis.x * 0.5 + 0.5, axis.y * 0.5 + 0.5, axis.z * 0.5 + 0.5, 1.0)
	for i in SIDES:
		var j := (i + 1) % SIDES
		var a0: Vector3 = low[i]
		var a1: Vector3 = low[j]
		var b0: Vector3 = high[i]
		var b1: Vector3 = high[j]
		# 몸통 옆면
		var n := (a0 + a1 - foot * 2.0).normalized()
		code.a = clampf(n.dot(light) * 0.5 + 0.5, 0.0, 1.0)
		for p in [[a0, 0.0, 0.0], [a1, 1.0, 0.0], [b1, 1.0, SHOULDER],
				[a0, 0.0, 0.0], [b1, 1.0, SHOULDER], [b0, 0.0, SHOULDER]]:
			_vertex(tool, p[0], n, code, Vector2(p[1], p[2]), start, total)
		# 머리 — 가운데(0.5)가 끝이다
		var m := (b1 - b0).cross(tip - b0).normalized()
		if m.dot(b0 + b1 - neck * 2.0) < 0.0:
			m = -m
		code.a = clampf(m.dot(light) * 0.5 + 0.5, 0.0, 1.0)
		for p in [[b0, 0.0, SHOULDER], [b1, 1.0, SHOULDER], [tip, 0.5, 1.0]]:
			_vertex(tool, p[0], m, code, Vector2(p[1], p[2]), start, total)


static func _vertex(tool: SurfaceTool, at: Vector3, normal: Vector3, code: Color,
		uv: Vector2, start: float, total: float) -> void:
	tool.set_normal(normal)
	tool.set_color(code)
	tool.set_uv(uv)
	tool.set_uv2(Vector2(start, total))
	tool.add_vertex(at)
