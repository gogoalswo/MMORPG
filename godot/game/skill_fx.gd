class_name SkillFx
extends Node3D

## 스킬을 쓸 때 시전자 앞에서 터지는 연출. 지금은 **할퀴기(`rising_kick`)** 하나다.
##
## **앞 120° 를 다섯 번 긁는다** (2026-09-23 요청 — 참고 그림: 희고 푸른 초승달
## 궤적 여러 줄이 나란히 휘어 지나가고, 닿는 자리에서 노란 불꽃이 튄다).
## 한 번 긁을 때 **나란한 발톱 자국 셋**이 부채꼴을 쓸고 가고, 다섯 번이
## 좌 → 우, 우 → 좌로 번갈아 기울기를 달리해 겹친다.
##
## **줄기는 파티클이 아니라 직접 메시다** (effect-rules.md 3절). 프레임마다 머리가
## 호를 따라 나아가고 꼬리가 따라붙는 초승달을 다시 깎는다. 폭은 시선에 수직
## (`LightningFx.view_dir`)이라 카메라 각이 어떻든 같은 굵기로 보인다.
## **방향은 캐릭터 기준이다** — 호의 가운데가 늘 캐릭터가 보는 쪽이다.
##
## **에셋을 쓰지 않는다.** 텍스처도 런타임에 굽는다 (`FxTex`).
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 스스로 `queue_free` 하므로 부르는 쪽이 목록을 들고 있을 필요가 없다.

## 긁는 횟수 = 판정의 `hits`. 간격도 판정의 `hitGap`(80ms)과 같아야 **한 줄기가
## 지나갈 때 숫자 하나가 뜬다** (`skill_fx_test.gd` 가 표와 맞춰 본다)
const SLASHES := 5
const GAP := 0.08
## 한 번 긁는 동안 발톱 자국 수 — 손톱 셋
const CLAWS := 3
## 자국 사이 간격(m). 호의 반지름을 이만큼씩 늘린다
const CLAW_SPACING := 0.3

## 쓸고 가는 각 — 판정(120°)보다 조금 넓게 둬서 끝이 부채꼴 밖까지 흘러야
## 부채꼴 끝에 선 놈도 긁힌 것으로 보인다
const SWEEP_ARC := deg_to_rad(140.0)
## 머리가 끝까지 가는 시간. 짧아야 "긁었다" 가 된다
const SWEEP := 0.12
## 꼬리 길이(각). 이보다 길면 원을 그린 것으로, 짧으면 점이 지나간 것으로 보인다
const TRAIL := deg_to_rad(115.0)
## 다 쓸고 나서 꼬리가 머리로 모이며 사라지는 시간
const FADE := 0.16

## 가장 안쪽 자국의 반지름(m). 사거리 3m 부채꼴 한가운데를 지난다
const RADIUS := 2.0
## 가슴 높이. 발밑이 아니라 몸 앞을 긁는다
const HEIGHT := 1.0
## 번마다 기울기(rad) — 부호가 번갈아야 참고 그림처럼 대각선이 엇갈린다.
## 같으면 한 줄로 겹쳐 다섯 번이 한 번으로 보인다
const TILTS: Array[float] = [-0.34, 0.3, -0.14, 0.4, -0.24]
## 번마다 높이를 조금씩 흔든다 — 같은 자리를 다섯 번 지나면 한 줄이 된다
const LIFTS: Array[float] = [0.05, -0.1, 0.15, -0.02, 0.08]

## 호를 몇 토막으로 깎나
const SEGMENTS := 22

## 세 겹 — **폭만 다르고 같은 길**이다 (effect-rules.md 5절). 넓은 청백 빛 +
## 밝은 테 + 가는 흰 심. 폭은 초승달의 가장 굵은 자리 기준(m)
const HALO_WIDTH := 0.85
const SHEEN_WIDTH := 0.32
const CORE_WIDTH := 0.1
const COLOR_HALO := Color(0.42, 0.72, 1.0, 0.45)
const COLOR_SHEEN := Color(0.78, 0.9, 1.0, 0.85)
const COLOR_CORE := Color(1.0, 1.0, 1.0, 1.0)
## 가운데 자국이 가장 굵고 안·밖은 가늘다 — 셋이 같으면 판자 세 장이다
const CLAW_SCALE: Array[float] = [0.7, 1.0, 0.8]

## 닿는 자리의 불꽃 — **퍼지지 않고 제자리에서 사그라든다** (3절)
const FLASH_SIZE := 1.5
const FLASH_LIFE := 0.16
const COLOR_FLASH := Color("#ffc24a")
const SPARK_COUNT := 12
const SPARK_SIZE := 0.13
const SPARK_LIFE := 0.26
const COLOR_SPARK := Color("#ffd98a")

var _t := 0.0
var _facing := 0.0
var _slashes: Array = []


## 할퀴기를 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
static func claw(parent: Node3D, at: Vector3, facing: float) -> SkillFx:
	var fx := SkillFx.new()
	fx.name = "ClawFx"
	# **회전은 주지 않는다.** 리본 폭을 월드 시선으로 재므로 좌표도 월드 방향이어야
	# 한다 — 보는 쪽은 점을 찍을 때 넣는다
	fx.position = at + Vector3(0.0, HEIGHT, 0.0)
	fx._facing = facing
	parent.add_child(fx)
	fx._build()
	return fx


## 끝나는 시각(초) — 마지막 긁기가 사라지고 불똥까지 떨어질 때
static func span() -> float:
	return float(SLASHES - 1) * GAP + maxf(SWEEP + FADE, SWEEP * 0.5 + SPARK_LIFE)


func _build() -> void:
	for i in SLASHES:
		var slash := {
			"at": float(i) * GAP,
			# 좌 → 우, 우 → 좌 번갈아
			"side": 1.0 if i % 2 == 0 else -1.0,
			"tilt": TILTS[i % TILTS.size()],
			"lift": LIFTS[i % LIFTS.size()],
			"flashed": false,
			"layers": [],
		}
		for layer in [[HALO_WIDTH, COLOR_HALO], [SHEEN_WIDTH, COLOR_SHEEN], [CORE_WIDTH, COLOR_CORE]]:
			var mesh := MeshInstance3D.new()
			mesh.material_override = LightningFx.glow(layer[1])
			mesh.visible = false
			add_child(mesh)
			slash.layers.append({"node": mesh, "width": layer[0], "color": layer[1]})
		slash["flash"] = _flash()
		slash["sparks"] = _sparks()
		_slashes.append(slash)


func _process(delta: float) -> void:
	_t += delta
	for slash in _slashes:
		_draw(slash)
	if _t >= span():
		queue_free()


## 한 번 긁는 것을 지금 시각에 맞춰 다시 깎는다
func _draw(slash: Dictionary) -> void:
	var s := _t - float(slash.at)
	if s < 0.0:
		return
	var sweep := clampf(s / SWEEP, 0.0, 1.0)
	var fade := clampf((s - SWEEP) / FADE, 0.0, 1.0)
	var head := -SWEEP_ARC * 0.5 + SWEEP_ARC * _ease_out(sweep)
	var tail := maxf(-SWEEP_ARC * 0.5, head - TRAIL)
	# 다 쓸고 나면 꼬리가 머리 쪽으로 모인다 — 제자리에서 옅어지기만 하면
	# 호가 한동안 그려져 있어 "그림 한 장" 이 된다
	if fade > 0.0:
		tail = lerpf(tail, head, _ease_out(fade) * 0.8)
	var alpha := 1.0 - fade * fade

	for layer in slash.layers:
		var node: MeshInstance3D = layer.node
		if alpha <= 0.01 or head - tail < 0.01:
			node.visible = false
			continue
		node.visible = true
		node.mesh = _crescents(slash, tail, head, float(layer.width))
		var mat: StandardMaterial3D = node.material_override
		var c: Color = layer.color
		mat.albedo_color = Color(c.r, c.g, c.b, c.a * alpha)

	# 머리가 가운데(보는 쪽 정면)를 지날 때 닿는다 — 거기서 불꽃
	if not bool(slash.flashed) and sweep >= 0.5:
		slash.flashed = true
		var hit := arc_point(0.0, RADIUS + CLAW_SPACING, slash)
		var flash: MeshInstance3D = slash.flash
		flash.position = hit
		flash.visible = true
		var sparks: CPUParticles3D = slash.sparks
		sparks.position = hit
		sparks.emitting = true
		slash["flash_t"] = s
	if bool(slash.flashed):
		var f := clampf((s - float(slash.flash_t)) / FLASH_LIFE, 0.0, 1.0)
		var flash: MeshInstance3D = slash.flash
		flash.visible = f < 1.0
		var mat: StandardMaterial3D = flash.material_override
		mat.albedo_color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 1.0 - f)


## 발톱 자국 셋을 한 메시로. 각은 `tail` → `head`(보는 쪽 기준 rad, 부호는 `side`)
func _crescents(slash: Dictionary, tail: float, head: float, width: float) -> ArrayMesh:
	var view := LightningFx.view_dir()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in CLAWS:
		var radius := RADIUS + CLAW_SPACING * float(k)
		var w := width * CLAW_SCALE[k % CLAW_SCALE.size()]
		var path := PackedVector3Array()
		for i in SEGMENTS + 1:
			path.append(arc_point(lerpf(tail, head, float(i) / float(SEGMENTS)), radius, slash))
		var across: Array = []
		for i in path.size():
			var along := path[mini(i + 1, SEGMENTS)] - path[maxi(i - 1, 0)]
			across.append(view.cross(along.normalized()).normalized())
		for i in SEGMENTS:
			var wa: Vector3 = across[i] * crescent(float(i) / float(SEGMENTS)) * w * 0.5
			var wb: Vector3 = across[i + 1] * crescent(float(i + 1) / float(SEGMENTS)) * w * 0.5
			LightningFx._half(tool, path[i] - wa, path[i], path[i + 1] - wb, path[i + 1], 0.0)
			LightningFx._half(tool, path[i] + wa, path[i], path[i + 1] + wb, path[i + 1], 1.0)
	return tool.commit()


## 호 위의 한 점 (이펙트 원점 = 가슴 기준, 월드 방향).
## `angle` 0 이 캐릭터가 보는 쪽이고, `side` 가 쓸고 가는 쪽을 뒤집는다.
## 호를 품은 판을 **보는 쪽을 축으로 `tilt` 만큼 기울여** 한쪽 끝이 높아진다
func arc_point(angle: float, radius: float, slash: Dictionary) -> Vector3:
	var a := angle * float(slash.side)
	var local := Vector3(sin(a) * radius, 0.0, cos(a) * radius)
	local = local.rotated(Vector3.BACK, float(slash.tilt))
	local.y += float(slash.lift)
	return local.rotated(Vector3.UP, _facing)


## 초승달 폭 (0 = 꼬리, 1 = 머리). 꼬리는 실처럼 가늘고, 머리 쪽 3분의 2 에서
## 가장 굵고, **머리 끝은 뾰족하다** — 폭이 일정하면 막대가 날아가는 것으로 보인다
static func crescent(t: float) -> float:
	return sin(PI * pow(clampf(t, 0.0, 1.0), 1.6))


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func _flash() -> MeshInstance3D:
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	flash.mesh = quad
	flash.material_override = LightningFx.flare(COLOR_FLASH)
	flash.visible = false
	add_child(flash)
	return flash


## 닿는 자리에서 튀는 불똥. 빛이라 가산 혼합이다
func _sparks() -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = SPARK_COUNT
	sparks.lifetime = SPARK_LIFE
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = false
	var dot := QuadMesh.new()
	dot.size = Vector2(SPARK_SIZE, SPARK_SIZE)
	sparks.mesh = dot
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 7.0
	sparks.gravity = Vector3(0.0, -9.0, 0.0)
	sparks.scale_amount_curve = LightningFx.fade_curve()
	sparks.color = COLOR_SPARK
	sparks.color_ramp = LightningFx.fade_ramp(COLOR_SPARK)
	sparks.material_override = LightningFx.mote(COLOR_SPARK, true)
	add_child(sparks)
	return sparks
