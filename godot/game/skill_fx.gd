class_name SkillFx
extends Node3D

## 스킬을 쓸 때 시전자 앞에서 터지는 연출. 지금은 **할퀴기(`rising_kick`)** 하나다.
##
## **앞 120° 를 다섯 번 긁는다** (2026-09-23 요청 — 참고 그림: 희고 푸른 초승달
## 궤적 여러 줄이 나란히 휘어 지나가고, 닿는 자리에서 노란 불꽃이 튄다).
## 한 번 긁을 때 **나란한 발톱 자국 셋**이 부채꼴을 쓸고 가고, 다섯 번이
## 좌 → 우, 우 → 좌로 번갈아 기울기를 달리해 겹친다.
##
## **줄기는 파티클이 아니라 직접 메시다** (effect-rules.md 3절). 머리가 호를 따라
## 나아가고 꼬리가 따라붙는 초승달이다. 폭은 시선에 수직(`LightningFx.view_dir`)이라
## 카메라 각이 어떻든 같은 굵기로 보인다.
##
## **메시는 쓸 때 한 번만 만들고, 움직임은 셰이더가 한다** (`CLAW_SHADER`) ★
## 처음에는 프레임마다 메시 15장을 GDScript 로 다시 깎았는데 **스킬을 쓸 때마다
## 히치가 걸렸다** (2026-09-23 지적). 재 보니 떠 있는 동안 프레임당 1.6ms(최대 3ms,
## PC) — 낙뢰의 10배였고 웹·폰에서는 몇 배로 불어난다. 지금은 호 전체(140°)를
## 폭 0 으로 깔아 두고, 셰이더가 `tail`~`head` 사이만 초승달 폭으로 벌린다.
## 프레임마다 하는 일은 재질 세 개에 숫자 몇 개를 넣는 것뿐이다.
## **방향은 캐릭터 기준이다** — 호의 가운데가 늘 캐릭터가 보는 쪽이다.
##
## **에셋을 쓰지 않는다.** 텍스처도 런타임에 굽는다 (`FxTex`).
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 끝나면 스스로 풀로 돌아가므로(`FxPool`) 부르는 쪽이 목록을 들고 있을 필요가 없다.

## 긁는 횟수 = 판정의 `hits`. 간격도 판정의 `hitGap`(80ms)과 같아야 **한 줄기가
## 지나갈 때 숫자 하나가 뜬다** (`skill_fx_test.gd` 가 표와 맞춰 본다)
## 기본은 **세 번**이다 (2026-09-23 — 다섯에서 줄이고 "연타" 강화로 +2)
const SLASHES := 3
## "연타" 강화가 붙으면 더 긁는 수 — 판정의 `extraHits` 와 같아야 한다
const COMBO_SLASHES := 2
const GAP := 0.08
## 한 번 긁는 동안 발톱 자국 수 — 손톱 셋
const CLAWS := 3
## 자국 사이 간격(m). 호의 반지름을 이만큼씩 늘린다
const CLAW_SPACING := 0.3

## 쓸고 가는 각 — 판정(120°)보다 조금 넓게 둬서 끝이 부채꼴 밖까지 흘러야
## 부채꼴 끝에 선 놈도 긁힌 것으로 보인다
const SWEEP_ARC := deg_to_rad(140.0)
## "부채꼴" 강화가 붙으면 더 쓸고 가는 각 — 판정 각이 40° 넓어지는 만큼 호도 길어진다
## (2026-09-23 요청: "부채꼴 각도 40도 증가, 이펙트로 그 만큼 길이 증가")
const SWEEP_WIDE := deg_to_rad(40.0)
## 메시가 깔린 각 — 넓은 쪽까지 한 번에 깔아 두고, 얼마나 그릴지는 셰이더가 정한다
const MESH_ARC := SWEEP_ARC + SWEEP_WIDE
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

## 호 전체(`MESH_ARC` 180°)를 몇 토막으로 까나. 머리 끝이 토막 단위로 나아가므로
## 너무 성기면 끝이 뚝뚝 끊겨 보인다 (52 면 3.5° 씩 — 140° 에 40 토막이던 때와 같다)
const SEGMENTS := 52

## 세 겹 — **폭만 다르고 같은 길**이다 (effect-rules.md 5절). 넓은 청백 빛 +
## 밝은 테 + 가는 흰 심. 폭은 초승달의 가장 굵은 자리 기준(m)
const HALO_WIDTH := 0.85
const SHEEN_WIDTH := 0.32
const CORE_WIDTH := 0.1
const COLOR_HALO := Color(0.42, 0.72, 1.0, 0.45)
const COLOR_SHEEN := Color(0.78, 0.9, 1.0, 0.85)
const COLOR_CORE := Color(1.0, 1.0, 1.0, 1.0)
## 빛 두 겹의 색 한 벌. **흰 심과 닿는 자리의 노란 불꽃은 안 바뀐다**
const PALETTE_BLUE := {"halo": COLOR_HALO, "sheen": COLOR_SHEEN}
## "연타" 강화가 붙으면 보라 (2026-09-23, 사용자 선택). 청백 벌과 밝기·알파를 맞췄다.
## 낙뢰 기절(붉은색)·피격(붉은색)·치명타(주황)·피해 숫자(연노랑)와 갈린다
const PALETTE_PURPLE := {"halo": Color(0.66, 0.38, 1.0, 0.45), "sheen": Color(0.88, 0.76, 1.0, 0.85)}
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

## 초승달 셰이더. 꼭짓점은 전부 호 위(가운데 선)에 있고, 가장자리 꼭짓점만
## 시선 × `NORMAL`(호의 진행 방향) 쪽으로 `UV2.y`(±발톱 굵기) 만큼 벌린다. `UV2.x` 는 그 점의 각(rad)이라
## `tail`~`head` 밖이면 폭이 0 이 되어 안 보인다. 가장자리를 죄는 것은
## `LightningFx.glow` 와 같은 `FxTex.streak` 이다
const CLAW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, cull_disabled, world_vertex_coords;
uniform sampler2D streak : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float width = 0.3;
uniform float head = 0.0;
uniform float tail = 0.0;
void vertex() {
	// 초승달 폭 — 꼬리는 실처럼 가늘고, 머리 쪽 3분의 2 에서 가장 굵고, 머리 끝은
	// 뾰족하다. 폭이 일정하면 막대가 날아가는 것으로 보인다
	float u = (UV2.x - tail) / max(head - tail, 1e-4);
	float w = (u < 0.0 || u > 1.0) ? 0.0 : sin(PI * pow(u, 1.6));
	// 폭 방향은 **시선과 호의 진행 방향에 수직**이다. 월드에서 구하므로 메시는
	// 보는 쪽과 무관하다 — 노드만 돌리면 되고, 메시는 게임 전체에서 한 번만 만든다
	vec3 across = normalize(cross(INV_VIEW_MATRIX[2].xyz, NORMAL));
	VERTEX += across * UV2.y * width * 0.5 * w;
}
void fragment() {
	vec4 t = texture(streak, UV);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = tint.a * t.a;
}
"""
static var _shader: Shader
## 긁기 다섯의 호 메시 — **처음 한 번만** 만들어 모든 할퀴기가 같이 쓴다 (보는 쪽 0 기준)
static var _arcs: Array = []

var _t := 0.0
var _facing := 0.0
var _slashes: Array = []
## 이번에 긁는 수 · 쓸고 가는 각 · 꼬리 각 — 강화에 따라 되감을 때 정한다
var _count := SLASHES
var _sweep := SWEEP_ARC
var _trail := TRAIL


## 할퀴기를 띄운다. `at` 은 시전자 발밑(월드 좌표), `facing` 은 보는 쪽(rad).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다.
## `wide` 면 호가 40° 길고("부채꼴" 강화), `combo` 면 두 번 더 긁고 보라다("연타" 강화).
## 둘은 따로 논다
static func claw(parent: Node3D, at: Vector3, facing: float, wide := false, combo := false) -> SkillFx:
	var fx := FxPool.take(parent, &"claw") as SkillFx
	if fx == null:
		fx = SkillFx.new()
		fx.name = "ClawFx"
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing, wide, combo)
	return fx


## 끝나는 시각(초) — 마지막 긁기가 사라지고 불똥까지 떨어질 때
static func span(count := SLASHES) -> float:
	return float(count - 1) * GAP + maxf(SWEEP + FADE, SWEEP * 0.5 + SPARK_LIFE)


## 노드를 만든다 — 한 번만. 되감기는 `_start`.
## **"연타" 몫(둘)까지 늘 만들어 둔다** — 안 쓸 때는 쉬게 한다. 풀이 한 벌이라
## 강화한 할퀴기가 처음 나올 때 새로 만들면 그 순간 멈칫한다
func _build() -> void:
	for i in SLASHES + COMBO_SLASHES:
		var slash := {
			"at": float(i) * GAP,
			# 좌 → 우, 우 → 좌 번갈아
			"side": 1.0 if i % 2 == 0 else -1.0,
			"tilt": TILTS[i % TILTS.size()],
			"lift": LIFTS[i % LIFTS.size()],
			"flashed": false,
			"flash_t": 0.0,
			"layers": [],
			# 이번에 긁나 — "연타" 몫 둘은 강화가 없으면 쉰다 (`_start`)
			"active": true,
		}
		# 세 겹이 **같은 메시**를 쓴다 — 폭과 색만 재질이 다르다
		var arc := arc_mesh(i)
		for layer in [[HALO_WIDTH, COLOR_HALO], [SHEEN_WIDTH, COLOR_SHEEN], [CORE_WIDTH, COLOR_CORE]]:
			var mesh := MeshInstance3D.new()
			mesh.mesh = arc
			mesh.material_override = claw_material(layer[0], layer[1])
			# 꼭짓점을 셰이더가 벌리므로 원래 상자(폭 0)보다 넉넉히 잡는다
			mesh.extra_cull_margin = HALO_WIDTH
			mesh.visible = false
			add_child(mesh)
			slash.layers.append({"node": mesh, "width": layer[0], "color": layer[1]})
		slash["flash"] = _flash()
		slash["sparks"] = _sparks()
		_slashes.append(slash)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 자리·보는 쪽·시각만 넣는다
func _start(at: Vector3, facing: float, wide := false, combo := false) -> void:
	_count = SLASHES + (COMBO_SLASHES if combo else 0)
	_sweep = SWEEP_ARC + (SWEEP_WIDE if wide else 0.0)
	# 꼬리도 호에 비례해 늘린다 — 호만 늘리면 긴 호 위로 짧은 점이 지나가 보인다
	_trail = TRAIL * _sweep / SWEEP_ARC
	var pal: Dictionary = PALETTE_PURPLE if combo else PALETTE_BLUE
	# **회전은 주지 않는다.** 리본 폭을 월드 시선으로 재므로 좌표도 월드 방향이어야
	# 한다 — 보는 쪽은 점을 찍을 때 넣는다
	position = at + Vector3(0.0, HEIGHT, 0.0)
	_facing = facing
	_t = 0.0
	for index in _slashes.size():
		var slash: Dictionary = _slashes[index]
		slash.active = index < _count
		slash.flashed = false
		# 빛 두 겹(헤일로·테)만 색을 바꾼다 — 흰 심은 그대로
		slash.layers[0].color = pal.halo
		slash.layers[1].color = pal.sheen
		for layer in slash.layers:
			var node: MeshInstance3D = layer.node
			# 메시는 보는 쪽 0 으로 깔려 있다 — 노드를 돌려 캐릭터가 보는 쪽에 맞춘다
			node.rotation.y = facing
			node.visible = false
		var flash: MeshInstance3D = slash.flash
		flash.visible = false


func _process(delta: float) -> void:
	_t += delta
	for slash in _slashes:
		if slash.active:
			_draw(slash)
	if _t >= span(_count):
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"claw")


## 한 번 긁는 것을 지금 시각에 맞춰 다시 깎는다
func _draw(slash: Dictionary) -> void:
	var s := _t - float(slash.at)
	if s < 0.0:
		return
	var sweep := clampf(s / SWEEP, 0.0, 1.0)
	var fade := clampf((s - SWEEP) / FADE, 0.0, 1.0)
	var head := -_sweep * 0.5 + _sweep * _ease_out(sweep)
	var tail := maxf(-_sweep * 0.5, head - _trail)
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
		var mat: ShaderMaterial = node.material_override
		var c: Color = layer.color
		mat.set_shader_parameter(&"head", head)
		mat.set_shader_parameter(&"tail", tail)
		mat.set_shader_parameter(&"tint", Color(c.r, c.g, c.b, c.a * alpha))

	# 머리가 가운데(보는 쪽 정면)를 지날 때 닿는다 — 거기서 불꽃
	if not bool(slash.flashed) and sweep >= 0.5:
		slash.flashed = true
		var hit := arc_point(0.0, RADIUS + CLAW_SPACING, slash)
		var flash: MeshInstance3D = slash.flash
		flash.position = hit
		flash.visible = true
		var sparks: CPUParticles3D = slash.sparks
		sparks.position = hit
		# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
		sparks.restart()
		slash["flash_t"] = s
	if bool(slash.flashed):
		var f := clampf((s - float(slash.flash_t)) / FLASH_LIFE, 0.0, 1.0)
		var flash: MeshInstance3D = slash.flash
		flash.visible = f < 1.0
		var mat: StandardMaterial3D = flash.material_override
		mat.albedo_color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 1.0 - f)


## `i` 번째 긁기의 발톱 자국 셋을 한 메시로 — **게임 전체에서 한 번만** 만든다.
## 쓸 때마다 만들었더니 그것만으로 2.8ms(PC) 가 튀었다 (2026-09-23).
## 호 전체(`MESH_ARC`)를 보는 쪽 0 으로 깔아 두고 폭은 0 이다. 점마다 꼭짓점
## 셋(바깥 · 가운데 · 바깥)이 같은 자리에 있고, 셰이더가 바깥 둘만 벌린다.
## `NORMAL` 에는 폭 방향이 아니라 **호의 진행 방향**을 넣는다 — 폭 방향은 시선에
## 달려 있어서 셰이더가 월드에서 구한다
static func arc_mesh(i: int) -> ArrayMesh:
	if _arcs.size() > i and _arcs[i] != null:
		return _arcs[i]
	var side_sign := 1.0 if i % 2 == 0 else -1.0
	var tilt := TILTS[i % TILTS.size()]
	var lift := LIFTS[i % LIFTS.size()]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	for k in CLAWS:
		var radius := RADIUS + CLAW_SPACING * float(k)
		var scale := CLAW_SCALE[k % CLAW_SCALE.size()]
		var path := PackedVector3Array()
		var angles := PackedFloat32Array()
		for p in SEGMENTS + 1:
			var a := -MESH_ARC * 0.5 + MESH_ARC * float(p) / float(SEGMENTS)
			angles.append(a)
			path.append(local_point(a, radius, side_sign, tilt, lift))
		var base := verts.size()
		for p in path.size():
			var along := path[mini(p + 1, SEGMENTS)] - path[maxi(p - 1, 0)]
			var dir := along.normalized()
			# 바깥(-) · 가운데 · 바깥(+). 셰이더는 UV2.y 를 곱해 벌린다
			for side in [-1.0, 0.0, 1.0]:
				verts.append(path[p])
				normals.append(dir)
				uvs.append(Vector2(0.5 + side * 0.5, float(p) / float(SEGMENTS)))
				uv2s.append(Vector2(angles[p], side * scale))
		for p in SEGMENTS:
			var a := base + p * 3
			var b := a + 3
			# 왼쪽 반 · 오른쪽 반 (가운데 줄을 나눠 가진다)
			index.append_array([a, a + 1, b, b, a + 1, b + 1])
			index.append_array([a + 2, a + 1, b + 2, b + 2, a + 1, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _arcs.size() <= i:
		_arcs.resize(i + 1)
	_arcs[i] = mesh
	return mesh


## 초승달 한 겹의 재질. 셰이더는 한 번만 만들어 모두가 같이 쓴다
static func claw_material(width: float, tint: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CLAW_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter(&"streak", FxTex.streak())
	mat.set_shader_parameter(&"width", width)
	mat.set_shader_parameter(&"tint", tint)
	return mat


## 호 위의 한 점 (이펙트 원점 = 가슴 기준, 월드 방향).
## `angle` 0 이 캐릭터가 보는 쪽이고, `side` 가 쓸고 가는 쪽을 뒤집는다.
## 호를 품은 판을 **보는 쪽을 축으로 `tilt` 만큼 기울여** 한쪽 끝이 높아진다
func arc_point(angle: float, radius: float, slash: Dictionary) -> Vector3:
	return local_point(
		angle, radius, float(slash.side), float(slash.tilt), float(slash.lift)
	).rotated(Vector3.UP, _facing)


## 보는 쪽이 +Z(0) 일 때의 점. 메시는 이것으로 깔고 노드를 돌린다
static func local_point(angle: float, radius: float, side: float, tilt: float, lift: float) -> Vector3:
	var a := angle * side
	var local := Vector3(sin(a) * radius, 0.0, cos(a) * radius)
	local = local.rotated(Vector3.BACK, tilt)
	local.y += lift
	return local


## (초승달 폭 곡선은 셰이더에 있다 — `CLAW_SHADER`)


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
