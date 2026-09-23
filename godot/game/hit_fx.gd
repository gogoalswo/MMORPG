class_name HitFx
extends Node3D

## 맞은 자리에서 한 번 터지고 스스로 풀로 돌아가는 피격 연출.
##
## **에셋을 쓰지 않는다.** 섬광·파편·피해 숫자를 전부 코드로 짓는다 — 모델이 없으면
## 기둥으로 그리는 것과 같은 이유다. 이펙트 하나 보자고 `npm run sync:godot` 을
## 돌려야 하면 안 된다.
##
## **판정을 다시 하지 않는다.** 숫자·치명타·회복·처치는 `World` 가 낸 `hit` 이벤트에
## 다 들어 있으므로 그대로 읽어 그린다. 화면이 따로 계산하면 반드시 어긋난다.
##
## 끝나면 스스로 풀(`FxPool`)로 돌아가므로 부르는 쪽이 목록을 들고 있을 필요가 없다
## (보스 예고 원 `_aoe_marks` 와 달리, 터진 뒤에 손댈 일이 없다).
## **가장 자주 뜨는 이펙트다** — 할퀴기 한 번이 다섯 대 × 무리 수만큼 띄운다. 그래서
## 노드는 처음에 한 벌만 짓고(`_build`), 다시 쓸 때는 색·숫자·자리만 넣는다(`_start`).

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
## 전부 그 환산을 거친 것이고, `hit_fx_test.gd` 가 px 로 다시 잰다.
##
## **한 번 키웠다가 반으로 줄인 값이다** — 눈으로 보고 "너무 크다" 고 해서
## 그대로 반씩 나눴다 (2026-09-17). 숫자 29px 로 HUD 글자(28px)와 비슷하다
const NUMBER_SIZE := 0.011
const CRIT_SIZE := 0.017
const FLASH_RADIUS := 0.3
const SPARK_SIZE := 0.15

## 내가 때렸다
const COLOR_DAMAGE := Color("#ffe6a0")
## 치명타는 **색부터 다르다** — 주황(`#ff8a3d`)이던 것을 자홍으로 바꿨다 (2026-09-23,
## "크리티컬 터지면 데미지 플로터 색상도 바꿔"). 주황은 평타의 연노랑과 같은 난색이라
## 한 화면에 섞이면 크기로만 갈렸다. 자홍은 게임 안 어디에도 안 쓰는 색이다
## (내가 맞음 빨강 · 회복 초록 · 낙뢰 청백과도 겹치지 않는다)
const COLOR_CRIT := Color("#ff4fd8")
## 내가 맞았다 — 남을 때린 숫자와 색으로 갈라야 한 화면에서 구분이 된다
const COLOR_HURT := Color("#ff5a4a")
const COLOR_HEAL := Color("#7ce08a")

## ── 타격감 ─────────────────────────────────────────────
## 섬광·숫자 말고 **시간·움직임·손끝**으로 주는 것. 세기는 네 단계다 —
## **평타 < 치명타 < 처치 < 보스.** 매번 같은 세기면 금방 무뎌진다.
##
## - `stop`   히트스톱(초). 때린 쪽·맞은 쪽 동작을 멈춘다 (`Rig.freeze`)
## - `shake`  화면 흔들림 세기·`shake_time` 길이 (`CameraRig.shake`). **평타는 0** —
##            초당 몇 번씩 흔들리면 멀미가 난다
## - `kick`   맞은 몸이 밀려나는 거리(m). 몸만 밀고 판정 좌표는 그대로다
## - `squash` 맞은 몸이 옆으로 퍼지는 비율
## - `buzz`   폰 진동(ms). 평타는 0
const TIERS := [
	{"stop": 0.045, "shake": 0.0, "shake_time": 0.0, "kick": 0.12, "squash": 0.08, "buzz": 0},
	{"stop": 0.07, "shake": 0.05, "shake_time": 0.18, "kick": 0.22, "squash": 0.14, "buzz": 25},
	{"stop": 0.09, "shake": 0.09, "shake_time": 0.24, "kick": 0.32, "squash": 0.18, "buzz": 35},
	{"stop": 0.13, "shake": 0.14, "shake_time": 0.35, "kick": 0.40, "squash": 0.22, "buzz": 60},
]
## 밀려나는 데 걸리는 시간. 나머지(`REACT_TIME` 까지) 동안 제자리로 돌아온다
const KICK_OUT := 0.05
const REACT_TIME := 0.18
## 퍼졌다가 돌아오는 시간
const SQUASH_TIME := 0.14
## 보스는 무겁다 — 덜 밀린다
const BOSS_KICK := 0.5
## 진동 사이 최소 간격(ms). 할퀴기 한 번이 다섯 대라 그대로 떨면 한 덩어리로 뭉개진다
const BUZZ_GAP := 120
## 진동을 쓸까. 설정 창이 생기면 여기에 잇는다
static var buzz_on := true
static var _buzz_at := -BUZZ_GAP

var _t := 0.0
var _flash: MeshInstance3D
var _number: Label3D
## [{node, vel}, ...] — 튀어 나가 떨어지는 파편
var _sparks: Array = []
## 파편 일곱이 같이 쓰는 재질
var _spark_mat: StandardMaterial3D
## 섬광·파편이 있나 (회복이면 숫자만)
var _burst := true
## 처치면 섬광이 크다
var _flash_size := 1.0
## 맞은 몸 덧칠 — 모두가 같이 쓴다
static var _body_mat: StandardMaterial3D
## 붉게 칠해 둔 몸. 시간이 지나면 되돌린다
var _painted: Array = []


## 터뜨린다. `at` 은 월드 좌표(가슴 높이), `payload` 는 `hit` 이벤트 그대로다
static func spawn(parent: Node3D, at: Vector3, payload: Dictionary, font: Font = null) -> HitFx:
	var fx := FxPool.take(parent, &"hit") as HitFx
	if fx == null:
		fx = HitFx.new()
		parent.add_child(fx)
		fx._build(font)
	fx.position = at
	fx._start(payload, font)
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


## 노드를 만든다 — 한 번만. 섬광 · 파편 일곱 · 숫자
func _build(font: Font) -> void:
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = FLASH_RADIUS
	ball.height = ball.radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	_flash.mesh = ball
	_flash.material_override = _glow(COLOR_DAMAGE)
	add_child(_flash)

	var chip := BoxMesh.new()
	chip.size = Vector3(SPARK_SIZE, SPARK_SIZE, SPARK_SIZE)
	_spark_mat = _glow(COLOR_DAMAGE)
	for i in SPARKS:
		var node := MeshInstance3D.new()
		node.mesh = chip
		node.material_override = _spark_mat
		add_child(node)
		_sparks.append({"node": node, "vel": Vector3.ZERO})

	_number = Label3D.new()
	if font != null:
		_number.font = font
	_number.font_size = 64
	_number.outline_size = 16
	_number.outline_modulate = Color(0, 0, 0, 0.8)
	_number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 몬스터 몸에 가리면 안 보인다 — 숫자는 항상 앞에 그린다
	_number.no_depth_test = true
	add_child(_number)


## 처음으로 되감는다. **아무것도 만들지 않는다** — 색·숫자·파편이 튈 쪽만 새로 넣는다
func _start(payload: Dictionary, font: Font) -> void:
	var heal := bool(payload.get("heal", false))
	var crit := bool(payload.get("crit", false))
	var killed := bool(payload.get("killed", false))
	var on_me := str(payload.get("target_kind", "")) == "player"
	var amount: int = int(payload.get("amount", 0))
	_t = 0.0

	var tint := COLOR_DAMAGE
	if heal:
		tint = COLOR_HEAL
	elif on_me:
		tint = COLOR_HURT
	elif crit:
		tint = COLOR_CRIT

	# 회복은 때린 것이 아니다 — 섬광도 파편도 없이 숫자만 뜬다
	_burst = not heal
	_flash.visible = _burst
	_flash_size = 1.6 if killed else 1.0
	_flash.scale = Vector3.ONE * 0.5 * _flash_size
	var flash_mat: StandardMaterial3D = _flash.material_override
	flash_mat.albedo_color = tint
	_spark_mat.albedo_color = tint
	for spark in _sparks:
		var node: MeshInstance3D = spark.node
		node.visible = _burst
		node.position = Vector3.ZERO
		node.scale = Vector3.ONE
		var angle := randf() * TAU
		var out := randf_range(2.4, 4.2)
		spark.vel = Vector3(cos(angle) * out, randf_range(2.6, 4.0), sin(angle) * out)

	if heal:
		_number.text = "+%d" % amount
	elif crit:
		_number.text = "%d!" % amount
	else:
		_number.text = str(amount)
	if font != null and _number.font != font:
		_number.font = font
	# 치명타는 크게. 숫자를 읽지 않아도 크기로 먼저 안다
	_number.pixel_size = CRIT_SIZE if crit else NUMBER_SIZE
	_number.modulate = tint
	_number.position = Vector3(randf_range(-0.4, 0.4), 0.3, 0.0)


## 이 한 대가 몇 단계인가 (0~3). 회복은 때린 것이 아니라 -1.
##
## 치명타 1 · 처치 2 에서 시작해 **보스가 끼면 한 단계 올린다** — 보스 평타가
## 잡몹 치명타만큼, 보스를 잡으면 맨 위다. **내가 맞으면 적어도 1** 이다 —
## 맞은 걸 손끝으로 알아야 하는데 평타 단계는 진동이 없다
static func tier_of(payload: Dictionary, boss: bool) -> int:
	if bool(payload.get("heal", false)):
		return -1
	var tier := 0
	if bool(payload.get("crit", false)):
		tier = 1
	if bool(payload.get("killed", false)):
		tier = 2
	if str(payload.get("target_kind", "")) == "player":
		tier = maxi(tier, 1)
	if boss:
		tier += 1
	return mini(tier, TIERS.size() - 1)


## 히트스톱. 모델이 없는 기둥은 멈출 동작이 없다
static func hitstop(body: Node3D, seconds: float) -> void:
	if body is Rig and is_instance_valid(body):
		body.freeze(seconds)


## 맞은 몸을 밀고 퍼뜨린다. **값만 적어 두고 움직이는 건 `apply_react` 다.**
##
## 몸 자리는 화면이 매 프레임 `World` 좌표로 덮어쓴다. 그래서 여기서 자리를
## 옮기면 다음 프레임에 지워진다 — 덮어쓴 **뒤에** 부르는 `apply_react` 가
## 그 위에 얹는다. 새로 맞으면 적어 둔 값을 갈아 끼우므로 겹쳐도 되돌릴 게 없다.
## `kick` 이 0 이면 퍼지기만 한다 (내 캐릭터 — 아래 `apply_react` 참고)
static func react(body: Node3D, from: Vector3, kick: float, squash: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var dir := Vector3(body.position.x - from.x, 0.0, body.position.z - from.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	body.set_meta(&"hit_react", {"t": 0.0, "dir": dir, "kick": kick, "squash": squash})


## `react` 로 적어 둔 것을 얹는다. **자리를 `World` 좌표로 덮어쓴 바로 뒤에** 부른다
static func apply_react(body: Node3D, delta: float) -> void:
	if not body.has_meta(&"hit_react"):
		return
	var r: Dictionary = body.get_meta(&"hit_react")
	r.t += delta
	var t: float = r.t
	if t >= REACT_TIME:
		settle(body)
		return
	# 짧게 튀어 나갔다가 천천히 돌아온다 — 똑같은 속도로 오가면 흔들림으로 읽힌다
	var out := t / KICK_OUT if t < KICK_OUT else pow(1.0 - (t - KICK_OUT) / (REACT_TIME - KICK_OUT), 2.0)
	body.position += r.dir * float(r.kick) * out
	var s: float = float(r.squash) * maxf(0.0, 1.0 - t / SQUASH_TIME)
	body.scale = Vector3(1.0 + s, 1.0 - s * 0.5, 1.0 + s)


## 반응을 걷는다. 죽어서 숨긴 몸도 이걸로 되돌린다 — 안 걷으면 되살아날 때 찌그러져 있다
static func settle(body: Node3D) -> void:
	if body.has_meta(&"hit_react"):
		body.remove_meta(&"hit_react")
		body.scale = Vector3.ONE


## 폰 진동. 데스크톱에서는 아무 일도 없다
static func buzz(ms: int) -> void:
	if not buzz_on or ms <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _buzz_at < BUZZ_GAP:
		return
	_buzz_at = now
	Input.vibrate_handheld(ms)


## 맞은 몸을 잠깐 붉게 물들인다. **덧칠(`material_overlay`)이라 원래 재질을
## 건드리지 않는다** — 되돌릴 때 `null` 만 넣으면 끝이라 모델이든 기둥이든 같다
func flash_body(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	# 덧칠 재질은 **게임에 하나** — 맞을 때마다 만들면 다 걷힌 순간 셰이더가 버려진다 (`FxPool`)
	if _body_mat == null:
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.65)
		_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_body_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mat := _body_mat
	for mesh in meshes_of(body):
		mesh.material_overlay = mat
		_painted.append(mesh)


func _process(delta: float) -> void:
	_t += delta

	if _burst:
		var ratio := clampf(_t / FLASH, 0.0, 1.0)
		_flash.scale = Vector3.ONE * lerpf(0.5, 2.0, ratio) * _flash_size
		var mat: StandardMaterial3D = _flash.material_override
		mat.albedo_color.a = 1.0 - ratio
		_flash.visible = ratio < 1.0

	for spark in _sparks:
		if not _burst:
			break
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
		finish()


## 끝낸다 — 덧칠을 걷고 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	_unpaint()
	FxPool.give(self, &"hit")


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
