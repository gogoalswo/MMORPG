class_name NovaFx
extends Node3D

## 폭렬권(`nova_fist`) 연출 — **주먹이 닿은 자리에서 흰·금빛 기운이 소용돌이치며
## 끓어오르다가 대폭발한다** (2026-09-28 요청: "적을 주먹으로 이렇게 치면 이펙트가
## 이렇게 나오기 시작하면서 대폭발". 참고 그림 — 캐릭터 앞에서 금빛 소용돌이 호가
## 겹겹이 솟고, 가운데가 하얗게 달아오르고, 금가루 불티가 흩날린다).
##
## 시간 순서 (시전부터 초):
## - `IMPACT`(0.10) — 주먹을 뻗는 순간(`NovaFist`). 주먹 자리에 섬광이 튄다.
## - `IMPACT` ~ `EXPLODE` — **끓는다.** 가운데 빛무리가 부풀며 떨리고, 흰·금빛
##   소용돌이 호(`GATHER_ARCS`)가 가운데를 감아 돌며 위로 솟고, 금가루가 흩날린다.
## - `EXPLODE`(0.75) — **대폭발.** 판정도 이때다(스킬 표의 `delayMs`). 큰 섬광,
##   바깥으로 크게 감아 도는 호(`BLAST_ARCS`), 사방으로 뻗는 빛살(`RAYS`),
##   불덩이·불티·연기·땅을 쓰는 흙먼지, 그을림, 화면 흔들림.
##
## **호와 빛살은 파티클이 아니라 메시다** (규칙 3절) — 게임 전체에서 **한 번만**
## 깔고(`swirl_mesh`), 꼭짓점마다 언제 지나가나(`UV`)를 넣어 두면 셰이더가 `now`
## 로 머리~꼬리 사이만 벌린다. 매 프레임 메시를 깎으면 폰에서 히치가 난다
## (할퀴기, 2026-09-23). 폭 방향은 셰이더가 시선에 수직으로 잡는다.
##
## 퍼지는 동그란 충격 고리는 **쓰지 않는다** (규칙 3절) — 폭발이 퍼지는 것은
## 불덩이·흙먼지가 밀려나다 멎는 것으로 보인다. 섬광도 제자리에서 사그라든다.
## **방향은 캐릭터 기준** — 노드를 보는 쪽으로 돌린다.
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 끝나면 스스로 풀로 돌아간다 (`FxPool`).

## **이펙트 전체 크기 배율** (2026-09-29 요청: "이펙트를 지금보다 1.5배 키워"). 아래 크기(m)·
## 속도는 1배 기준이고, 쓰는 자리에서 곱한다 — 방출기는 속도·감속·중력을 같이 곱해야 **같은
## 시간에 그만큼 멀리** 간다(`_grow`). 주먹 자리(`AHEAD`·`CORE_Y`)는 동작과 맞물려 곱하지 않는다.
## 판정 사거리(스킬 표 `range`)도 같이 넓혔다 (5 → 7.5m) — `nova_fx_test.gd` 가 잰다
const SIZE := 1.5
## 주먹이 닿는 시각 — `NovaFist` 가 0.10초에 뻗는다 (characters-and-animation.md).
## 동작은 0.70초까지 뻗은 채 버티다가 0.77초에 두 팔을 펼친다 — `EXPLODE` 와 같이 고친다
const IMPACT := 0.10
## 터지는 시각 = 스킬 표의 `delayMs`(750ms). **둘은 같이 고친다** (`nova_fx_test.gd`)
const EXPLODE := 0.75
## 기운이 모이는 자리 — 보는 쪽(+Z)으로 이만큼, 뻗은 주먹 높이
const AHEAD := 0.9
const CORE_Y := 1.25
const GROUND := 0.05

## 호 한 가닥 = [시작(초), 지나가는 데 걸리는 시간(초)]. 머리가 끝까지 가며 꼬리가
## 따라와 사라진다. 꼬리 길이(호 길이에 대한 비율)
const TRAIL := 0.6
## 끓는 동안 가운데를 감아 도는 호 — 수 · 반지름 · 지나가는 시간
const GATHER_ARCS := 28
const GATHER_RADIUS_MIN := 0.4
const GATHER_RADIUS_MAX := 1.3
const GATHER_SWEEP_MIN := 0.3
const GATHER_SWEEP_MAX := 0.45
## 터질 때 바깥으로 감아 돌며 **크게 솟는** 호. 반지름이 고르고 누운 원이면
## 자이로스코프 고리로 읽혀서(첫 캡처) 호를 짧게, 솟는 높이를 크게 뒀다
const BLAST_ARCS := 18
const BLAST_RADIUS_MIN := 0.9
const BLAST_RADIUS_MAX := 2.4
const BLAST_SWEEP_MIN := 0.3
const BLAST_SWEEP_MAX := 0.45
## 터질 때 사방으로 뻗는 빛살 — 길이(m)
const RAYS := 22
const RAY_MIN := 2.0
const RAY_MAX := 3.4
const RAY_SWEEP_MIN := 0.2
const RAY_SWEEP_MAX := 0.3
## 호 한 가닥을 몇 토막으로 까나
const SEGMENTS := 24
const RAY_SEGMENTS := 8
## 두 겹 — 넓은 금빛 헤일로 + 가는 흰 심 (규칙 5절: 폭만 다른 겹)
const HALO_WIDTH := 1.1
const CORE_WIDTH := 0.28

## 가운데 빛무리 — 끓는 동안 이만큼까지 부푼다 (m)
## 너무 크고 진하면 몸을 통째로 덮는다 (2차 캡처) — 참고 그림처럼 몸이 비쳐야 한다
const ORB_MIN := 0.8
const ORB_MAX := 2.6
## 끓는 동안 가운데에서 피어오르는 금빛 기운 (가산 뭉치) — 참고 그림의 뿌연 금빛
const AURA_COUNT := 40
const AURA_SIZE := 0.9
## 터지는 섬광 크기 · 수명
const FLASH_SIZE := 8.0
const FLASH_LIFE := 0.35
## 불덩이 — 터지며 밀려나다 감속으로 멎는다. 멎는 거리(v²/2d)+부푼 크기가
## 사거리(5m) 안이어야 한다 (`nova_fx_test.gd` 가 잰다)
## 가산 뭉치가 많이 겹치면 **하얀 공 하나**로 포화된다 (2차 캡처) — 수와 진하기를 누른다
const FIRE_COUNT := 26
const FIRE_SIZE := 1.5
const FIRE_SPEED_MIN := 3.0
const FIRE_SPEED_MAX := 5.5
const FIRE_DAMP := 7.0
const FIRE_LIFE := 0.65
## 연기 — 불덩이 뒤에 남아 천천히 떠오른다 (알파)
const SMOKE_COUNT := 22
const SMOKE_SIZE := 1.8
const SMOKE_LIFE := 1.4
## 연기는 불덩이가 한 번 부푼 뒤에 나온다 — 같이 나오면 섬광 한가운데가 검은 원이 됐다
const SMOKE_AFTER := 0.2
## 흙먼지 — 땅을 따라 밀려나다 멎는다
const DUST_COUNT := 30
const DUST_SIZE := 1.3
const DUST_SPEED_MIN := 5.0
const DUST_SPEED_MAX := 7.0
const DUST_DAMP := 9.0
const DUST_LIFE := 0.9
## 금가루 — 끓는 동안 흩날리는 것과 터질 때 튀는 것
const GLITTER_COUNT := 90
const GLITTER_LIFE := 0.7
const SPARK_COUNT := 110
const SPARK_LIFE := 0.9
## 그을림 — 터진 뒤 이만큼 남고, 마지막 0.8초에 흐려진다
const MARK_SIZE := 5.0
const MARK_LIFE := 2.2
const MARK_FADE := 0.8
## 빛 — 끓는 동안 차오르고, 터질 때 번쩍였다 꺼진다
const LIGHT_RANGE := 10.0
const LIGHT_GATHER := 2.5
const LIGHT_BLAST := 7.0
const LIGHT_LIFE := 0.45
## 터질 때 화면 흔들림 — 천붕각(0.14)보다 세다
const SHAKE := 0.2
const SHAKE_TIME := 0.45

const COLOR_HALO := Color(1.0, 0.7, 0.18, 0.55)
const COLOR_CORE := Color(1.0, 0.96, 0.82, 0.95)
const COLOR_ORB := Color("#ffe39a")
const COLOR_FLASH := Color("#ffd98a")
const COLOR_GOLD := Color("#ffd04a")
const COLOR_FIRE_HOT := Color("#fff6d8")
const COLOR_FIRE := Color("#ffb53a")
const COLOR_FIRE_END := Color("#ff6a14")
const COLOR_SMOKE := Color("#8a7e70")
const COLOR_DUST := Color("#c8ae86")
const COLOR_SCORCH := Color("#1e1409")
const COLOR_LIGHT := Color("#ffc65a")

## 호·빛살 셰이더. `UV` = (지나가기 시작하는 시각, 걸리는 시간), `UV2` = (호 위의
## 자리 0~1, 폭 방향 −1·0·1), `COLOR.r` = 폭 배율. 셰이더가 `now` 로 머리~꼬리
## 사이만 초승달 폭으로 벌린다 — 할퀴기(`SkillFx.CLAW_SHADER`)와 같은 생각이다.
## 시각을 `COLOR` 에 넣지 않는 것은 꼭짓점 색이 8비트라 시각이 뭉개져서다
const SWIRL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, cull_disabled, world_vertex_coords;
uniform sampler2D streak : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float width = 0.3;
uniform float now = 0.0;
uniform float trail = 0.6;
varying float side;
void vertex() {
	float lt = now - UV.x;
	float head = lt / max(UV.y, 1e-3) * (1.0 + trail);
	float u = (UV2.x - (head - trail)) / trail;
	float w = (lt < 0.0 || u < 0.0 || u > 1.0) ? 0.0 : sin(PI * pow(u, 1.6));
	vec3 across = normalize(cross(INV_VIEW_MATRIX[2].xyz, NORMAL));
	VERTEX += across * UV2.y * width * COLOR.r * 0.5 * w;
	side = UV2.y;
}
void fragment() {
	vec4 t = texture(streak, vec2(side * 0.5 + 0.5, 0.5));
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = tint.a * t.a;
}
"""
static var _shader: Shader
static var _mesh: ArrayMesh

var _t := 0.0
var _hit := false
var _blown := false
var _smoked := false
var _halo: MeshInstance3D
var _core: MeshInstance3D
var _orb: MeshInstance3D
var _flash: MeshInstance3D
var _scorch: MeshInstance3D
var _light: OmniLight3D
var _glitter: CPUParticles3D
var _aura: CPUParticles3D
var _sparks: CPUParticles3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _dust: CPUParticles3D


## 폭렬권을 띄운다. `at` 은 시전자 발밑(월드), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다
static func burst(parent: Node3D, at: Vector3, facing: float) -> NovaFx:
	var fx := FxPool.take(parent, &"nova") as NovaFx
	if fx == null:
		fx = NovaFx.new()
		fx.name = "NovaFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing)
	return fx


## 끝나는 시각(초)
static func span() -> float:
	return EXPLODE + maxf(MARK_LIFE, SMOKE_AFTER + SMOKE_LIFE) + 0.1


## 불덩이가 가운데에서 가장 멀리 가는 거리(m) — 멎는 거리 + 다 부푼 반지름
static func fire_reach() -> float:
	return (FIRE_SPEED_MAX * FIRE_SPEED_MAX / (2.0 * FIRE_DAMP) + FIRE_SIZE * 2.2 * 0.5) * SIZE


## 흙먼지가 가운데에서 가장 멀리 가는 거리(m)
static func dust_reach() -> float:
	return (DUST_SPEED_MAX * DUST_SPEED_MAX / (2.0 * DUST_DAMP) + DUST_SIZE * 2.0 * 0.5) * SIZE


## 노드를 만든다 — 한 번만. 되감기는 `_start`
func _build() -> void:
	var core_at := Vector3(0.0, CORE_Y, AHEAD)
	_halo = _sheet(swirl_material(HALO_WIDTH * SIZE, COLOR_HALO))
	_halo.mesh = swirl_mesh()
	_halo.position = core_at
	# 셰이더가 폭을 벌리므로 경계 상자를 넉넉히 — 안 그러면 비껴 볼 때 통째로 잘린다
	_halo.extra_cull_margin = 3.0 * SIZE
	_core = _sheet(swirl_material(CORE_WIDTH * SIZE, COLOR_CORE))
	_core.mesh = _halo.mesh
	_core.position = core_at
	_core.extra_cull_margin = 3.0 * SIZE

	_orb = _sheet(LightningFx.flare(COLOR_ORB))
	var orb := QuadMesh.new()
	orb.size = Vector2.ONE
	_orb.mesh = orb
	_orb.position = core_at
	_flash = _sheet(LightningFx.flare(COLOR_FLASH))
	var flash := QuadMesh.new()
	flash.size = Vector2.ONE * FLASH_SIZE * SIZE
	_flash.mesh = flash
	_flash.position = core_at

	_scorch = _sheet(LightningFx.stain(COLOR_SCORCH))
	var mark := PlaneMesh.new()
	mark.size = Vector2.ONE * MARK_SIZE * SIZE
	_scorch.mesh = mark
	_scorch.position = Vector3(0.0, GROUND, AHEAD)

	_light = OmniLight3D.new()
	_light.position = core_at
	_light.omni_range = LIGHT_RANGE * SIZE
	_light.light_color = COLOR_LIGHT
	add_child(_light)

	_glitter = _glitter_emitter()
	_aura = _aura_emitter()
	_sparks = _spark_emitter()
	_fire = _fire_emitter()
	_smoke = _smoke_emitter()
	_dust = _dust_emitter()
	for e in _emitters():
		_grow(e)
		e.emitting = false
		add_child(e)
	_dust.position = Vector3(0.0, 0.25, AHEAD)
	for e in [_glitter, _aura, _sparks, _fire, _smoke]:
		e.position = core_at


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float) -> void:
	position = at
	rotation.y = facing
	_t = 0.0
	_hit = false
	_blown = false
	_smoked = false
	_show()


func _process(delta: float) -> void:
	_t += delta
	# 방출기는 제때 처음부터 다시 켠다 (되감아 쓰는 방출기라 `restart`)
	if not _hit and _t >= IMPACT:
		_hit = true
		_glitter.restart()
		_aura.restart()
	if not _blown and _t >= EXPLODE:
		_blown = true
		for e in [_sparks, _fire, _dust]:
			e.restart()
	if not _smoked and _t >= EXPLODE + SMOKE_AFTER:
		_smoked = true
		_smoke.restart()
	_show()
	if _t >= span():
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"nova")


func _show() -> void:
	for node in [_halo, _core]:
		(node.material_override as ShaderMaterial).set_shader_parameter(&"now", _t)
	_halo.visible = _t < EXPLODE + BLAST_SWEEP_MAX + 0.2
	_core.visible = _halo.visible

	# 가운데 빛무리 — 닿는 순간 튀고, 끓는 동안 떨며 부풀고, 터지면 빠르게 죈다
	var orb_size := 0.0
	var orb_alpha := 0.0
	if _t >= IMPACT and _t < EXPLODE:
		var k := (_t - IMPACT) / (EXPLODE - IMPACT)
		var pop := maxf(0.0, 1.0 - (_t - IMPACT) / 0.08)
		orb_size = lerpf(ORB_MIN, ORB_MAX, k * k) * (1.0 + 0.12 * sin(_t * 70.0)) + pop * 0.8
		orb_alpha = 0.45 + 0.35 * k
	elif _t >= EXPLODE:
		var k := (_t - EXPLODE) / 0.25
		orb_size = ORB_MAX * (1.0 - k * 0.5)
		# 끓을 때의 진하기에서 사그라든다 — 1.0 으로 튀면 섬광과 겹쳐 흰 덩어리가 된다
		orb_alpha = 0.8 * (1.0 - k)
	_orb.visible = orb_alpha > 0.0
	if _orb.visible:
		_orb.scale = Vector3.ONE * orb_size * SIZE
		_orb.material_override.albedo_color = Color(COLOR_ORB.r, COLOR_ORB.g, COLOR_ORB.b, orb_alpha)

	# 터지는 섬광 — 퍼지지 않고 제자리에서 사그라든다 (규칙 3절)
	var f := (_t - EXPLODE) / FLASH_LIFE
	_flash.visible = f >= 0.0 and f < 1.0
	if _flash.visible:
		_flash.scale = Vector3.ONE * lerpf(0.9, 1.1, sqrt(f))
		_flash.material_override.albedo_color = Color(
			COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 0.55 * pow(1.0 - f, 1.8))

	# 그을림 — 터지는 순간 드러나 남았다가 마지막 0.8초에만 흐려진다
	var since := _t - EXPLODE
	var mark := clampf(since / 0.08, 0.0, 1.0) * clampf((MARK_LIFE - since) / MARK_FADE, 0.0, 1.0)
	_scorch.visible = mark > 0.0
	if _scorch.visible:
		_scorch.material_override.albedo_color = Color(
			COLOR_SCORCH.r, COLOR_SCORCH.g, COLOR_SCORCH.b, 0.7 * mark)

	# 빛 — 끓는 동안 차오르고, 터질 때 번쩍였다 꺼진다
	var energy := 0.0
	if _t >= IMPACT and _t < EXPLODE:
		energy = LIGHT_GATHER * (_t - IMPACT) / (EXPLODE - IMPACT)
	elif since < LIGHT_LIFE:
		energy = LIGHT_BLAST * (1.0 - since / LIGHT_LIFE)
	_light.visible = energy > 0.0
	_light.light_energy = energy


func _sheet(mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 떠 있는 방출기 전부
func _emitters() -> Array:
	return [_glitter, _aura, _sparks, _fire, _smoke, _dust]


## 방출기 공통 — 한 번 쏘고 끝, 사방 구에서 나온다
static func _emitter(count: int, life: float, explosive: float, radius: float) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = explosive
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = radius
	e.direction = Vector3.UP
	e.spread = 180.0
	return e


## 방출기를 `SIZE` 배로 — 나오는 구 · 알갱이 크기 · 속도 · 감속 · 중력을 같이 곱한다.
## 속도와 감속을 같이 곱하면 궤적이 시간은 그대로 거리만 `SIZE` 배가 된다
static func _grow(e: CPUParticles3D) -> void:
	e.emission_sphere_radius *= SIZE
	(e.mesh as QuadMesh).size *= SIZE
	e.initial_velocity_min *= SIZE
	e.initial_velocity_max *= SIZE
	e.damping_min *= SIZE
	e.damping_max *= SIZE
	e.gravity *= SIZE


static func _dot(size: float) -> QuadMesh:
	var dot := QuadMesh.new()
	dot.size = Vector2(size, size)
	return dot


## 금가루 — 끓는 동안 가운데에서 **고르게 흘러나와** 흩날리다 천천히 떨어진다.
## 참고 그림의 반짝이는 금빛 알갱이다. 빛이라 가산
func _glitter_emitter() -> CPUParticles3D:
	var e := _emitter(GLITTER_COUNT, GLITTER_LIFE, 0.0, 0.45)
	e.mesh = _dot(0.2)
	e.initial_velocity_min = 1.2
	e.initial_velocity_max = 4.0
	e.damping_min = 1.5
	e.damping_max = 2.5
	e.gravity = Vector3(0.0, -2.5, 0.0)
	e.scale_amount_min = 0.5
	e.scale_amount_max = 1.4
	e.scale_amount_curve = LightningFx.fade_curve()
	e.color_ramp = LightningFx.fade_ramp(COLOR_GOLD)
	e.material_override = LightningFx.mote(Color.WHITE, true)
	return e


## 금빛 기운 — 끓는 동안 가운데에서 뭉게뭉게 **피어오른다.** 가는 호만으로는 기운이
## 끓는 덩어리가 안 보였다 (첫 캡처). 빛이라 가산
func _aura_emitter() -> CPUParticles3D:
	var e := _emitter(AURA_COUNT, EXPLODE - IMPACT, 0.0, 0.5)
	e.mesh = _dot(AURA_SIZE)
	e.spread = 50.0
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -120.0
	e.angular_velocity_max = 120.0
	e.initial_velocity_min = 1.2
	e.initial_velocity_max = 2.6
	e.gravity = Vector3(0.0, 1.5, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(1.8)
	e.color_ramp = LightningFx.fade_ramp(COLOR_FIRE, 0.55)
	var mat := LightningFx.mote(Color.WHITE, true)
	mat.albedo_texture = FxTex.puff()
	e.material_override = mat
	return e


## 터질 때 튀는 불티 — 빠르게 뻗다가 감속하며 떨어진다
func _spark_emitter() -> CPUParticles3D:
	var e := _emitter(SPARK_COUNT, SPARK_LIFE, 0.95, 0.5)
	e.mesh = _dot(0.15)
	e.initial_velocity_min = 5.0
	e.initial_velocity_max = 11.0
	e.damping_min = 4.0
	e.damping_max = 6.0
	e.gravity = Vector3(0.0, -6.0, 0.0)
	e.scale_amount_min = 0.5
	e.scale_amount_max = 1.5
	e.scale_amount_curve = LightningFx.fade_curve()
	var ramp := Gradient.new()
	ramp.set_color(0, COLOR_FIRE_HOT)
	ramp.set_offset(1, 0.4)
	ramp.set_color(1, COLOR_GOLD)
	ramp.add_point(1.0, Color(COLOR_FIRE_END.r, COLOR_FIRE_END.g, COLOR_FIRE_END.b, 0.0))
	e.color_ramp = ramp
	e.material_override = LightningFx.mote(Color.WHITE, true)
	return e


## 불덩이 — 흰 속 → 금빛 → 주황으로 식으며 밀려나다 멎는다. 빛이라 가산,
## 뭉게뭉게한 뭉치(`FxTex.puff`)라야 물방울무늬가 안 된다 (천붕각 먼지와 같다)
func _fire_emitter() -> CPUParticles3D:
	var e := _emitter(FIRE_COUNT, FIRE_LIFE, 1.0, 0.9)
	e.mesh = _dot(FIRE_SIZE)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -90.0
	e.angular_velocity_max = 90.0
	e.initial_velocity_min = FIRE_SPEED_MIN
	e.initial_velocity_max = FIRE_SPEED_MAX
	e.damping_min = FIRE_DAMP
	e.damping_max = FIRE_DAMP
	e.scale_amount_curve = LightningFx.grow_curve(2.2)
	var ramp := Gradient.new()
	# 첫 색도 흰색이 아니라 옅은 금빛이다 — 흰 속이 한가운데 겹치면 흰 공이 된다
	ramp.set_color(0, Color(COLOR_ORB.r, COLOR_ORB.g, COLOR_ORB.b, 0.32))
	ramp.set_offset(1, 0.3)
	ramp.set_color(1, Color(COLOR_FIRE.r, COLOR_FIRE.g, COLOR_FIRE.b, 0.4))
	ramp.add_point(0.7, Color(COLOR_FIRE_END.r, COLOR_FIRE_END.g, COLOR_FIRE_END.b, 0.25))
	ramp.add_point(1.0, Color(COLOR_FIRE_END.r, COLOR_FIRE_END.g, COLOR_FIRE_END.b, 0.0))
	e.color_ramp = ramp
	var mat := LightningFx.mote(Color.WHITE, true)
	mat.albedo_texture = FxTex.puff()
	e.material_override = mat
	return e


## 연기 — 불덩이가 식은 자리에 남아 천천히 떠오른다. 흙빛이라 알파,
## 재질 색은 흰색 (입자 색과 두 번 곱해지면 탁해진다), 땅 가까이서 옅어진다
func _smoke_emitter() -> CPUParticles3D:
	# 가운데에 몰리면 검은 구멍이 된다 (2차 캡처) — 넓게 흩어 낸다
	var e := _emitter(SMOKE_COUNT, SMOKE_LIFE, 0.9, 1.4)
	e.mesh = _dot(SMOKE_SIZE)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -40.0
	e.angular_velocity_max = 40.0
	e.initial_velocity_min = 1.0
	e.initial_velocity_max = 2.8
	e.damping_min = 1.5
	e.damping_max = 1.5
	e.gravity = Vector3(0.0, 0.7, 0.0)
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color_ramp = LightningFx.fade_ramp(COLOR_SMOKE, 0.3)
	var mat := LightningFx.mote(Color.WHITE)
	mat.albedo_texture = FxTex.puff()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.0
	# 빛(가산)보다 먼저 그린다 — 나중에 그리면 불덩이 위를 검게 덮는다
	mat.render_priority = -1
	e.material_override = mat
	return e


## 흙먼지 — **땅을 따라 수평으로** 밀려나다 멎는다. 폭발이 퍼지는 것이 이것으로
## 보인다 (고리 메시를 쓰지 않는다, 규칙 3절)
func _dust_emitter() -> CPUParticles3D:
	var e := _emitter(DUST_COUNT, DUST_LIFE, 1.0, 0.5)
	e.mesh = _dot(DUST_SIZE)
	e.direction = Vector3(1.0, 0.0, 0.0)
	e.flatness = 1.0
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.initial_velocity_min = DUST_SPEED_MIN
	e.initial_velocity_max = DUST_SPEED_MAX
	e.damping_min = DUST_DAMP
	e.damping_max = DUST_DAMP
	e.scale_amount_curve = LightningFx.grow_curve(2.0)
	e.color_ramp = LightningFx.fade_ramp(COLOR_DUST, 0.55)
	var mat := LightningFx.mote(Color.WHITE)
	mat.albedo_texture = FxTex.puff()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.8
	e.material_override = mat
	return e


## 호·빛살 한 겹의 재질. 셰이더는 한 번만 만들어 모두가 같이 쓴다
static func swirl_material(width: float, tint: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SWIRL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter(&"streak", FxTex.streak())
	mat.set_shader_parameter(&"width", width)
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"trail", TRAIL)
	return mat


## 호·빛살 전부를 한 메시에 — **처음 한 번만** 만든다 (가운데 = 원점, 보는 쪽 +Z).
## 가닥마다 [경로, 시작, 걸리는 시간, 폭 배율]
static func swirl_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for strand in strands():
		var path: PackedVector3Array = strand[0]
		# 폭은 재질(`width`)이 `SIZE` 배로 벌린다 — 여기서는 자리만
		for p in path.size():
			path[p] *= SIZE
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
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


## 가닥 전부 — [경로(가운데 기준), 시작(초), 걸리는 시간(초), 폭 배율].
## 난수 씨앗이 고정이라 늘 같은 모양이다 (테스트가 끝점을 잰다)
static func strands() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2809
	var out: Array = []
	# 끓는 소용돌이 — 가운데를 **한쪽으로** 감아 돌며 위로 솟는다. 몇 가닥만 거꾸로
	# 돌아 엉킨다 — 다 같은 쪽이면 팽이가 돈다
	for i in GATHER_ARCS:
		var start := IMPACT + (EXPLODE - IMPACT - 0.18) * float(i) / float(GATHER_ARCS - 1)
		var sweep := rng.randf_range(GATHER_SWEEP_MIN, GATHER_SWEEP_MAX)
		var radius := rng.randf_range(GATHER_RADIUS_MIN, GATHER_RADIUS_MAX)
		var turn := -1.0 if i % 5 == 3 else 1.0
		out.append([_spiral(rng, radius, turn, rng.randf_range(0.6, 1.3), 30.0),
			start, sweep, rng.randf_range(0.5, 0.9)])
	# 터지는 소용돌이 — 크게 감아 돌며 바깥으로 벌어진다
	for i in BLAST_ARCS:
		var start := EXPLODE + rng.randf_range(0.0, 0.12)
		var sweep := rng.randf_range(BLAST_SWEEP_MIN, BLAST_SWEEP_MAX)
		var radius := rng.randf_range(BLAST_RADIUS_MIN, BLAST_RADIUS_MAX)
		var turn := -1.0 if i % 4 == 2 else 1.0
		out.append([_spiral(rng, radius, turn, rng.randf_range(1.4, 2.8), 55.0, 90.0, 170.0, 1.6),
			start, sweep, rng.randf_range(1.0, 1.6)])
	# 빛살 — 가운데에서 사방(위쪽 반구에 몰리게)으로 곧게 뻗는다
	for i in RAYS:
		var yaw := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(RAYS)
		var up := rng.randf_range(-0.2, 0.9)
		var dir := Vector3(sin(yaw), up, cos(yaw)).normalized()
		var length := rng.randf_range(RAY_MIN, RAY_MAX)
		var path := PackedVector3Array()
		for p in RAY_SEGMENTS + 1:
			path.append(dir * lerpf(0.3, length, float(p) / float(RAY_SEGMENTS)))
		out.append([path, EXPLODE + rng.randf_range(0.0, 0.06),
			rng.randf_range(RAY_SWEEP_MIN, RAY_SWEEP_MAX), rng.randf_range(0.45, 0.75)])
	return out


## 가운데를 감아 도는 나선 한 가닥 — 반지름이 조금씩 벌어지며 `rise` 만큼 솟고,
## 판을 아무 쪽으로나 `tilt`(도)까지 기울인다. 곧게 누운 원만 겹치면 과녁이 된다
static func _spiral(rng: RandomNumberGenerator, radius: float, turn: float,
		rise: float, tilt: float, arc_min := 160.0, arc_max := 260.0,
		spread := 1.15) -> PackedVector3Array:
	var from := rng.randf_range(0.0, TAU)
	var sweep := deg_to_rad(rng.randf_range(arc_min, arc_max))
	var low := rng.randf_range(-0.5, 0.1)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var lean := deg_to_rad(rng.randf_range(-tilt, tilt))
	var path := PackedVector3Array()
	for p in SEGMENTS + 1:
		var k := float(p) / float(SEGMENTS)
		var a := from + turn * sweep * k
		var r := radius * lerpf(0.75, spread, k)
		var point := Vector3(cos(a) * r, low + rise * k, sin(a) * r)
		path.append(point.rotated(axis, lean))
	return path
