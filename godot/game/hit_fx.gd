class_name HitFx
extends Node3D

## 맞은 자리에서 한 번 터지고 스스로 사라지는 피격 연출.
##
## **에셋을 쓰지 않는다.** 섬광·파편·피해 숫자를 전부 코드로 짓는다 — 모델이 없으면
## 기둥으로 그리는 것과 같은 이유다. 이펙트 하나 보자고 `npm run sync:godot` 을
## 돌려야 하면 안 된다.
##
## **판정을 다시 하지 않는다.** 숫자·치명타·회복·처치는 `World` 가 낸 `hit` 이벤트에
## 다 들어 있으므로 그대로 읽어 그린다. 화면이 따로 계산하면 반드시 어긋난다.
##
## 스스로 `queue_free` 하므로 부르는 쪽이 목록을 들고 있을 필요가 없다
## (보스 예고 원 `_aoe_marks` 와 달리, 터진 뒤에 손댈 일이 없다).

## 숫자가 떠 있는 시간. 이보다 길면 무리를 칠 때 화면이 숫자로 덮인다
const LIFE := 0.75
## 섬광은 짧게. 오래 남으면 타격감이 아니라 조명이 된다
const FLASH := 0.22
## 맞은 몸이 붉어지는 시간
const BODY_FLASH := 0.2
## 숫자가 초당 떠오르는 높이(m)
const RISE := 1.8
const SPARKS := 7

## **화면에서 몇 px 로 보이는지로 크기를 정한다.** 카메라가 화면 세로 14.3m 를
## 보므로 720p 에서 1m 가 41px 다 — 처음에 숫자를 0.38m(16px)로 잡았다가
## "맞아도 이펙트가 안 나온다" 는 말을 들었다 (2026-09-17). 아래 미터 값은
## 전부 그 환산을 거친 것이고, `hit_fx_test.gd` 가 px 로 다시 잰다
const NUMBER_SIZE := 0.022
const CRIT_SIZE := 0.034
const FLASH_RADIUS := 0.6
const SPARK_SIZE := 0.3

## 내가 때렸다
const COLOR_DAMAGE := Color("#ffe6a0")
const COLOR_CRIT := Color("#ff8a3d")
## 내가 맞았다 — 남을 때린 숫자와 색으로 갈라야 한 화면에서 구분이 된다
const COLOR_HURT := Color("#ff5a4a")
const COLOR_HEAL := Color("#7ce08a")

var _t := 0.0
var _flash: MeshInstance3D
var _number: Label3D
## [{node, vel}, ...] — 튀어 나가 떨어지는 파편
var _sparks: Array = []
## 붉게 칠해 둔 몸. 시간이 지나면 되돌린다
var _painted: Array = []


## 터뜨린다. `at` 은 월드 좌표(가슴 높이), `payload` 는 `hit` 이벤트 그대로다
static func spawn(parent: Node3D, at: Vector3, payload: Dictionary, font: Font = null) -> HitFx:
	var fx := HitFx.new()
	fx.position = at
	parent.add_child(fx)
	fx._build(payload, font)
	return fx


## 몸에 붙은 메시 전부. 기둥(MeshInstance3D 하나)과 모델(Rig 아래 여러 장)을 같이 본다
static func meshes_of(body: Node3D) -> Array:
	var found: Array = []
	if body is MeshInstance3D:
		found.append(body)
	for child in body.find_children("*", "MeshInstance3D", true, false):
		found.append(child)
	return found


## 이펙트를 터뜨릴 높이. 발밑에서 터지면 맞은 것처럼 안 보인다 —
## 몸 높이의 6할쯤(가슴)에 둔다. 기둥이든 모델이든 실제 크기에서 잰다
static func chest_y(body: Node3D, fallback: float = 1.0) -> float:
	if body == null or not is_instance_valid(body):
		return fallback
	var box := AABB()
	var first := true
	for mesh in meshes_of(body):
		var world: AABB = mesh.global_transform * mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	if first:
		return fallback
	return box.position.y + box.size.y * 0.6


func _build(payload: Dictionary, font: Font) -> void:
	var heal := bool(payload.get("heal", false))
	var crit := bool(payload.get("crit", false))
	var killed := bool(payload.get("killed", false))
	var on_me := str(payload.get("target_kind", "")) == "player"
	var amount: int = int(payload.get("amount", 0))

	var tint := COLOR_DAMAGE
	if heal:
		tint = COLOR_HEAL
	elif on_me:
		tint = COLOR_HURT
	elif crit:
		tint = COLOR_CRIT

	# 회복은 때린 것이 아니다 — 섬광도 파편도 없이 숫자만 뜬다
	if not heal:
		_build_flash(tint, 1.6 if killed else 1.0)
		_build_sparks(tint)
	_build_number(amount, tint, heal, crit, font)


func _build_flash(tint: Color, size: float) -> void:
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = FLASH_RADIUS * size
	ball.height = ball.radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	_flash.mesh = ball
	_flash.material_override = _glow(tint)
	add_child(_flash)


func _build_sparks(tint: Color) -> void:
	var chip := BoxMesh.new()
	chip.size = Vector3(SPARK_SIZE, SPARK_SIZE, SPARK_SIZE)
	var mat := _glow(tint)
	for i in SPARKS:
		var node := MeshInstance3D.new()
		node.mesh = chip
		node.material_override = mat
		add_child(node)
		var angle := randf() * TAU
		var out := randf_range(2.4, 4.2)
		_sparks.append({
			"node": node,
			"vel": Vector3(cos(angle) * out, randf_range(2.6, 4.0), sin(angle) * out),
		})


func _build_number(amount: int, tint: Color, heal: bool, crit: bool, font: Font) -> void:
	_number = Label3D.new()
	if heal:
		_number.text = "+%d" % amount
	elif crit:
		_number.text = "%d!" % amount
	else:
		_number.text = str(amount)
	if font != null:
		_number.font = font
	_number.font_size = 64
	# 치명타는 크게. 숫자를 읽지 않아도 크기로 먼저 안다
	_number.pixel_size = CRIT_SIZE if crit else NUMBER_SIZE
	_number.modulate = tint
	_number.outline_size = 16
	_number.outline_modulate = Color(0, 0, 0, 0.8)
	_number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 몬스터 몸에 가리면 안 보인다 — 숫자는 항상 앞에 그린다
	_number.no_depth_test = true
	_number.position = Vector3(randf_range(-0.4, 0.4), 0.3, 0.0)
	add_child(_number)


## 맞은 몸을 잠깐 붉게 물들인다. **덧칠(`material_overlay`)이라 원래 재질을
## 건드리지 않는다** — 되돌릴 때 `null` 만 넣으면 끝이라 모델이든 기둥이든 같다
func flash_body(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.25, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for mesh in meshes_of(body):
		mesh.material_overlay = mat
		_painted.append(mesh)


func _process(delta: float) -> void:
	_t += delta

	if _flash != null:
		var ratio := clampf(_t / FLASH, 0.0, 1.0)
		_flash.scale = Vector3.ONE * lerpf(0.5, 2.0, ratio)
		var mat: StandardMaterial3D = _flash.material_override
		mat.albedo_color.a = 1.0 - ratio
		_flash.visible = ratio < 1.0

	for spark in _sparks:
		var node: MeshInstance3D = spark.node
		spark.vel.y -= 11.0 * delta
		node.position += spark.vel * delta
		node.scale = Vector3.ONE * maxf(0.05, 1.0 - _t / LIFE)

	if _t >= BODY_FLASH:
		_unpaint()

	if _number != null:
		_number.position.y += RISE * delta
		# 끝 45% 동안만 흐려진다. 처음부터 흐려지면 읽을 겨를이 없다
		_number.modulate.a = clampf((LIFE - _t) / (LIFE * 0.45), 0.0, 1.0)

	if _t >= LIFE:
		queue_free()


## 존을 옮기거나 대상이 사라져 통째로 지워질 때도 덧칠은 걷어 낸다
func _exit_tree() -> void:
	_unpaint()


func _unpaint() -> void:
	if _painted.is_empty():
		return
	for mesh in _painted:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_painted.clear()


func _glow(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat
