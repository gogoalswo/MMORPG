class_name SkillFx
extends Node3D

## 스킬을 쓸 때 시전자 앞에서 터지는 연출. 지금은 **할퀴기(`rising_kick`)** 하나다.
##
## **파티클로 만든다** (`CPUParticles3D` 셋). 처음에는 판 모양 메시를 세워 뒀는데
## "이미지 붙여 놓은 것 같다" 는 지적을 받았다 (2026-09-17) — 텍스처를 쓴 것은
## 아니었지만 **평평한 판이 한 자리에 서 있으면 그림 한 장과 다를 게 없다.**
## 지금은 중심에서 **뻗어 나가는** 것이 곧 이펙트다: 코어가 터지고, 발톱 광선이
## 양쪽에서 X 로 내달리고, 불똥이 사방으로 튄다.
##
## **`GPUParticles3D` 가 아니라 `CPUParticles3D` 다.** 화면은 모바일 렌더러로
## 굽고 웹(Compatibility)으로도 나가는데, CPU 쪽은 어디서나 같게 돌고 헤드리스
## 테스트에서 값을 그대로 읽을 수 있다. 수백 개 규모라 폰에서도 부담이 없다.
##
## **에셋을 쓰지 않는다.** 불똥 하나까지 코드로 짓는다 — 에셋을 안 받은 사람도
## 보여야 하고, 색·시간·크기가 상수라 고쳐서 바로 확인할 수 있어야 한다.
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 스스로 `queue_free` 하므로 부르는 쪽이 목록을 들고 있을 필요가 없다.

## 발톱이 양쪽에서 들어온다 — 왼쪽에서 한 번, 오른쪽에서 한 번.
## 한 세트가 **서로 반대쪽으로 뻗는 방출기 둘**이라 화면에서는 한 줄기로 가로지른다.
const SETS := 2
## 한 방향으로 몇 가닥 나가나
const STROKES := 3

## 긋는 각(rad). 두 세트가 +0.7 / -0.7 로 **X 로 엇갈린다**
const TILT := 0.7
## 가닥이 흩어지는 각(도). 넓히면 할퀸 자국이 아니라 별표가 된다
const SPREAD := 7.0
## 두 번째 세트가 늦게 들어오는 시간. 동시에 그으면 X 가 한 번에 찍혀
## 손이 두 번 지나간 것으로 안 읽힌다
const SET_DELAY := 0.09

## 발톱 광선 하나의 길이·폭. **미터가 아니라 px 로 정한다** — 카메라가 화면 세로
## 14.3m 를 보므로 720p 에서 1m 가 38~41px 다
## ([hit-effects.md](../../docs/features/hit-effects.md)). 길이 1.5m = 57px,
## 폭 0.16m = 6px 으로 피격 파편만 한 굵기다
const CLAW_LENGTH := 1.5
const CLAW_WIDTH := 0.16
## 광선이 뻗어 나가는 속도(m/s)와 사는 시간. 빨리 내달렸다가 제자리에서 스러진다
const CLAW_SPEED := 7.0
const CLAW_LIFE := 0.34

## 한가운데서 터지는 코어. 작은 구 여럿이 살짝 퍼지며 번진다 —
## 하나만 크게 띄우면 그거야말로 그림 한 장이다
const CORE_COUNT := 10
const CORE_SIZE := 0.55
const CORE_LIFE := 0.24

## 사방으로 튀는 불똥. 바늘처럼 길쭉한 것이 진행 방향으로 선다
const SPARK_COUNT := 30
const SPARK_LENGTH := 0.45
const SPARK_WIDTH := 0.05
const SPARK_LIFE := 0.4

## 발톱은 자홍, 코어는 흰빛, 불똥은 노랑. 피해 숫자(연노랑)·치명타(주황)·
## 피격(붉은색)과 한 화면에서 갈려야 한다 (`hit_fx.gd` 의 색 표)
const COLOR_CLAW := Color("#e85cff")
const COLOR_CORE := Color("#ffffff")
const COLOR_SPARK := Color("#ffd24a")

## 시전자 앞 얼마에서 터지나. **화면이 아니라 캐릭터가 보는 쪽**이어야
## "내가 앞을 긁었다" 가 된다
const FORWARD := 1.1
## 가슴 높이. 발밑에서 터지면 긁은 것으로 안 보인다
const HEIGHT := 1.05

## [{node, delay}, ...] — 늦게 켤 방출기들
var _delayed: Array = []
var _t := 0.0
var _span := 0.0


## 할퀴기를 터뜨린다.
##
## `at` 은 시전자 발밑(월드 좌표), `facing` 은 시전자가 보는 쪽(rad, `player.rot`).
static func claw(parent: Node3D, at: Vector3, facing: float) -> SkillFx:
	var fx := SkillFx.new()
	fx.position = at + Vector3(sin(facing) * FORWARD, HEIGHT, cos(facing) * FORWARD)
	# **X 자는 화면에서 X 로 보여야 한다.** 카메라가 고정각(요 45°·피치 42°)이라
	# 그 시선에 수직인 평면을 그대로 만든다 — 로컬 X 가 화면 가로, Y 가 화면 세로다.
	# 월드 방향으로 뻗으면 카메라 각에 따라 눕혀져 한 줄로 겹쳐 보인다
	fx.rotation = Vector3(-deg_to_rad(CameraRig.PITCH), CameraRig.YAW, 0.0)
	parent.add_child(fx)
	fx._build()
	return fx


func _build() -> void:
	_add(_core(), 0.0)
	for s in SETS:
		var tilt := TILT if s == 0 else -TILT
		var delay := float(s) * SET_DELAY
		# 한 세트가 서로 반대쪽으로 뻗는 방출기 둘이다 — 가운데서 갈라져
		# 양쪽으로 그어진다. 한쪽만 두면 한 손으로만 긁은 빗금이 된다
		for way in [1.0, -1.0]:
			var claw := _claw_jet(Vector3(cos(tilt) * way, sin(tilt) * way, 0.0))
			_add(claw, delay)
	_add(_sparks(), 0.02)


func _add(node: CPUParticles3D, delay: float) -> void:
	add_child(node)
	if delay > 0.0:
		node.emitting = false
		_delayed.append({"node": node, "delay": delay})
	_span = maxf(_span, delay + float(node.lifetime) + 0.1)


func _process(delta: float) -> void:
	_t += delta
	for i in range(_delayed.size() - 1, -1, -1):
		var waiting: Dictionary = _delayed[i]
		if _t >= float(waiting.delay):
			var node: CPUParticles3D = waiting.node
			node.emitting = true
			_delayed.remove_at(i)
	if _t >= _span:
		queue_free()


## 한 방향으로 내달리는 발톱 광선. `dir` 은 이 노드 기준(로컬 X = 화면 가로).
##
## **파티클을 진행 방향으로 세운다** (`particle_flag_align_y`) — 가닥 메시가 +Y 로
## 뻗어 있으므로, 날아가는 쪽이 곧 자국의 길이 방향이 된다. 판을 세워 두는 것과
## 여기서 갈린다: 같은 모양이라도 **뻗어 나가면** 긁은 것으로 읽힌다
func _claw_jet(dir: Vector3) -> CPUParticles3D:
	var jet := CPUParticles3D.new()
	jet.amount = STROKES
	jet.lifetime = CLAW_LIFE
	jet.one_shot = true
	# 셋이 같은 순간에 튀어나가야 한 번 긁은 것이다. 흘려 보내면 분수가 된다
	jet.explosiveness = 1.0
	jet.mesh = _needle_mesh(CLAW_LENGTH, CLAW_WIDTH)
	jet.direction = dir
	jet.spread = SPREAD
	jet.initial_velocity_min = CLAW_SPEED * 0.8
	jet.initial_velocity_max = CLAW_SPEED
	# 뻗다가 제자리에서 스러진다 — 끝까지 같은 속도로 가면 날아간 물건이 된다
	jet.damping_min = CLAW_SPEED * 0.9
	jet.damping_max = CLAW_SPEED * 1.4
	jet.gravity = Vector3.ZERO
	jet.particle_flag_align_y = true
	jet.scale_amount_min = 0.85
	jet.scale_amount_max = 1.15
	jet.scale_amount_curve = _grow_curve()
	jet.color = COLOR_CLAW
	jet.color_ramp = _fade_ramp(COLOR_CORE, COLOR_CLAW)
	jet.material_override = _glow()
	return jet


## 한가운데서 번지는 코어
func _core() -> CPUParticles3D:
	var core := CPUParticles3D.new()
	core.amount = CORE_COUNT
	core.lifetime = CORE_LIFE
	core.one_shot = true
	core.explosiveness = 1.0
	var ball := SphereMesh.new()
	ball.radius = CORE_SIZE * 0.5
	ball.height = CORE_SIZE
	ball.radial_segments = 6
	ball.rings = 3
	core.mesh = ball
	core.direction = Vector3.ZERO
	core.spread = 180.0
	# 거의 제자리에서 부푼다. 멀리 나가면 코어가 아니라 또 하나의 불똥이 된다
	core.initial_velocity_min = 0.4
	core.initial_velocity_max = 1.6
	core.damping_min = 4.0
	core.damping_max = 7.0
	core.gravity = Vector3.ZERO
	core.scale_amount_min = 0.6
	core.scale_amount_max = 1.4
	core.scale_amount_curve = _burst_curve()
	core.color = COLOR_CORE
	core.color_ramp = _fade_ramp(COLOR_CORE, COLOR_CLAW)
	core.material_override = _glow()
	return core


## 사방으로 튀는 불똥
func _sparks() -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = SPARK_COUNT
	sparks.lifetime = SPARK_LIFE
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.mesh = _needle_mesh(SPARK_LENGTH, SPARK_WIDTH)
	sparks.direction = Vector3.ZERO
	sparks.spread = 180.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 11.0
	sparks.damping_min = 6.0
	sparks.damping_max = 12.0
	# 살짝 떨어진다 — 전부 곧게만 뻗으면 그린 그림처럼 보인다
	sparks.gravity = Vector3(0, -3.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.3
	sparks.scale_amount_curve = _grow_curve()
	sparks.color = COLOR_SPARK
	sparks.color_ramp = _fade_ramp(COLOR_CORE, COLOR_SPARK)
	sparks.material_override = _glow()
	return sparks


## 원점에서 +Y 로 뻗는 바늘. 가운데가 굵고 양 끝이 뾰족하며 살짝 휜다 —
## 폭이 일정한 막대면 끝이 뭉툭해서 "막대가 날아간다" 로 보인다.
##
## 파티클이 진행 방향으로 서므로(`align_y`) **원점에서 한쪽으로만** 뻗어야
## 터진 자리에서 자라 나가는 그림이 된다
static func _needle_mesh(length: float, width: float) -> ArrayMesh:
	var steps := 10
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a := _edge(float(i) / float(steps), length, width)
		var b := _edge(float(i + 1) / float(steps), length, width)
		# 앞뒤 어느 쪽에서 봐도 보여야 한다 (재질에서 컬링을 끈다)
		tool.add_vertex(a[0])
		tool.add_vertex(a[1])
		tool.add_vertex(b[0])
		tool.add_vertex(b[0])
		tool.add_vertex(a[1])
		tool.add_vertex(b[1])
	return tool.commit()


## 길이 방향 t(0~1) 에서 바늘의 좌·우 점
static func _edge(t: float, length: float, width: float) -> Array:
	var y := t * length
	# 휨 — 가운데가 옆으로 부푼다
	var bow := sin(t * PI) * width * 0.6
	# 굵기 — 가운데가 가장 굵고 양 끝이 0 으로 모인다
	var half := pow(sin(t * PI), 0.6) * width * 0.5
	return [Vector3(bow + half, y, 0.0), Vector3(bow - half, y, 0.0)]


## 튀어나가며 길어졌다가 끝에서 오그라든다
static func _grow_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(0.7, 0.9))
	curve.add_point(Vector2(1.0, 0.0))
	return curve


## 확 부풀었다가 꺼진다
static func _burst_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	return curve


## **빠르게 켜고 · 떠 있는 동안 유지하다 · 끝에서 끈다.** 처음부터 옅어지면
## 가장 커지는 순간이 가장 투명한 순간과 겹쳐 어느 프레임에도 안 걸린다.
## 속은 희고 꼬리로 갈수록 제 색이 난다
static func _fade_ramp(head: Color, tail: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(head.r, head.g, head.b, 1.0))
	ramp.set_offset(1, 0.45)
	ramp.set_color(1, Color(tail.r, tail.g, tail.b, 1.0))
	ramp.add_point(1.0, Color(tail.r, tail.g, tail.b, 0.0))
	return ramp


## 조명을 받지 않는 가산 혼합. 겹칠수록 밝아지고 어두운 사냥터에서도 같게 읽힌다.
## **깊이 검사를 끈다** — 몸 앞에서 터지므로 켜 두면 몸통이 가린다.
## 파티클은 꼭짓점 색으로 물들므로 `vertex_color_use_as_albedo` 를 켠다
static func _glow() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	return mat
