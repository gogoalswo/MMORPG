class_name TrainerDraw
extends Control

## 트레이너 뽑기 연출 (2026-10-06 요청: 체스판 스크린샷 두 장 + "뽑기 갯수에 따라 3D 모델이 이렇게 나올거고, 배치는 좀
## 다르게. 체스말이 아니라 덤벨이 나오게 … 일반 등급은 흰색 덤벨, 희귀 이상 등급은 황금색 덤벨. 보기 버튼 누르면 …
## 이펙트가 나오면서 어떤 캐릭터가 나왔는지 표시하고, 이름은 등급 색상에 맞게").
##
##   어두운 돌판 위로 뽑은 수만큼 덤벨이 하나씩 떨어져 선다 (10회면 두 줄 초승달 — 뒤 6 · 앞 4, 앞줄은 뒷줄 사이사이)
##   → [모두 보기] → 덤벨마다 차례로 빛기둥이 솟고 덤벨이 빛 속으로 사라지며 그 자리에 트레이너 카드가 선다
##   → 카드 위 이름은 등급 색 · 새로 얻은 것은 NEW → [확인]
##
## 덤벨 모델은 바르코(`draw_dumbbell_white.glb` · `draw_dumbbell_gold.glb`), 바닥판 그림도 바르코(`trainer_board.jpg`).
## 빛기둥·섬광·반짝이는 코드로 짓는다 (effect-rules.md). 카드는 3D 가 아니라 **화면 위 조각** — 덤벨 발밑을 화면에
## 비춰 그 자리에 세우고 멀수록 작게 그린다 → docs/features/trainers.md "뽑기 연출"

## 확인을 눌렀다 — 상점이 판을 걷는다
signal closed

## 이 등급부터 금 덤벨 (희귀)
const GOLD_GRADE := 3
const DUMBBELL_HEIGHT := 1.15
## 판 — 칸 수 · 한 칸(m)
const BOARD_TILES := 8
const TILE := 1.0
## 자리 — 뒷줄 · 앞줄의 앞뒤 자리(z), 뒷줄 간격(앞줄은 그 두 배라 뒷줄 사이사이에 선다), 양끝이 앞으로 휘는 정도
const BACK_Z := -1.5
const FRONT_Z := 1.0
const COL_GAP := 1.05
const ARC := 0.6
const FOV := 40.0
const CAMERA_POS := Vector3(0.0, 4.3, 6.6)
const LOOK_AT := Vector3(0.0, 0.5, -0.6)

## 떨어지기 — 하나 간격 · 걸리는 시간 · 높이
const DROP_GAP := 0.07
const DROP_TIME := 0.42
const DROP_HEIGHT := 3.2
## 보기 — 하나 간격 · 빛 한 바퀴 · 카드가 서는 때
const REVEAL_GAP := 0.13
const REVEAL_TIME := 1.1
const CARD_AT := 0.3
const CARD_POP := 0.25
## 빛기둥 키(m)
const BEAM_HEIGHT := 5.5

## 카드(화면 조각) — 그림 크기 · 기준 화면 높이 · 기준 깊이에서의 배율
const ART := Vector2(126, 168)
const BASE_VIEW_H := 720.0
const CARD_SCALE := 1.0

const IVORY := Color("#eeead7")
const GOLD := GatePanel.CARD_GOLD

var _view: SubViewport
var _camera: Camera3D
var _pieces: Array = []  # {id, grade, fresh, gold, slot: Vector3, node: Node3D, fx: Node3D, card: Control, started}
var _layer: Control
var _reveal: Button
var _ok: Button
var _time := 0.0
var _reveal_at := -1.0
var _portrait := Callable()
var _ref_depth := 1.0

static var _beam_tex: ImageTexture


## `got` 은 뽑힌 트레이너 id, `fresh` 는 새로 얻었나(같은 순서), `portrait` 는 id → 카드 그림
static func make(got: Array, fresh: Array, portrait: Callable) -> TrainerDraw:
	var draw := TrainerDraw.new()
	draw._portrait = portrait
	draw._build(got, fresh)
	return draw


func _build(got: Array, fresh: Array) -> void:
	name = "draw_result"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := SubViewportContainer.new()
	box.name = "stage"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_view)
	_build_world()

	_layer = Control.new()
	_layer.name = "cards"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)

	# 좋은 등급이 눈에 잘 띄는 자리(앞줄 가운데)부터 — 정렬은 안정 정렬이라 같은 등급은 나온 순서 그대로
	var entries: Array = []
	for i in got.size():
		var id := str(got[i])
		entries.append({"id": id, "grade": int(Trainers.trainer(id).get("grade", 1)),
			"fresh": i < fresh.size() and bool(fresh[i]), "order": i})
	entries.sort_custom(func(a, b): return a.grade > b.grade or (a.grade == b.grade and a.order < b.order))
	var slots := TrainerDraw.slots(entries.size())
	for i in entries.size():
		var entry: Dictionary = entries[i]
		entry.gold = int(entry.grade) >= GOLD_GRADE
		entry.slot = slots[i]
		entry.node = _dumbbell(bool(entry.gold))
		entry.node.position = Vector3(entry.slot.x, DROP_HEIGHT, entry.slot.z)
		entry.node.visible = false
		entry.fx = null
		entry.card = null
		entry.started = false
		_pieces.append(entry)
	_ref_depth = _camera.position.distance_to(Vector3.ZERO)

	_reveal = _button("reveal", "모두 보기")
	_reveal.pressed.connect(reveal_all)
	_ok = _button("ok", "확인")
	_ok.visible = false
	_ok.pressed.connect(func() -> void: closed.emit())


## 자리 — 눈에 잘 띄는 순서(앞줄 가운데 → 바깥 → 뒷줄 가운데 → 바깥)로 낸다. 여섯 개부터 두 줄(앞 = 2/5),
## 앞줄 간격은 뒷줄의 두 배라 뒷줄 사이사이에 서서 뒤 카드의 얼굴을 덜 가린다. 두 줄 다 양끝이 앞으로 휜다
static func slots(count: int) -> Array:
	if count <= 0:
		return []
	if count == 1:
		return [Vector3.ZERO]
	var front := count * 2 / 5 if count >= 6 else 0
	var out: Array = TrainerDraw._row(front, FRONT_Z, COL_GAP * 2.0)
	out.append_array(TrainerDraw._row(count - front, BACK_Z if front > 0 else 0.0, COL_GAP * (1.0 if front > 0 else 1.6)))
	return out


static func _row(n: int, z: float, gap: float) -> Array:
	var row: Array = []
	var half := maxf(1.0, float(n - 1) * 0.5 * gap)
	for i in n:
		var x := (float(i) - float(n - 1) * 0.5) * gap
		row.append(Vector3(x, 0.0, z + ARC * pow(x / half, 2.0)))
	row.sort_custom(func(a: Vector3, b: Vector3) -> bool: return absf(a.x) < absf(b.x) - 0.001 or (absf(absf(a.x) - absf(b.x)) <= 0.001 and a.x < b.x))
	return row


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.055, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.66, 0.66)
	environment.ambient_light_energy = 0.18
	env.environment = environment
	_view.add_child(env)
	# 위에서 판 가운데로 떨어지는 빛 — 가장자리는 어둠에 묻힌다 (받은 스크린샷의 결)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.0, 9.0, 2.5)
	spot.look_at_from_position(spot.position, Vector3(0.0, 0.0, 0.2))
	spot.spot_angle = 34.0
	spot.spot_range = 20.0
	spot.spot_attenuation = 0.6
	spot.light_energy = 5.0
	spot.light_color = Color(0.92, 0.97, 0.95)
	spot.shadow_enabled = true
	_view.add_child(spot)
	# 앞에서 덤벨 몸을 살리는 약한 빛
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -25, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.85, 0.85)
	_view.add_child(fill)

	var span := BOARD_TILES * TILE
	var board := MeshInstance3D.new()
	board.name = "board"
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	board.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TrainerDraw._board_texture()
	mat.albedo_color = Color(0.62, 0.66, 0.66)
	mat.roughness = 0.55
	board.material_override = mat
	_view.add_child(board)
	# 판 테두리 — 판보다 조금 큰 어두운 돌 받침
	var rim := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(span + 0.5, 0.3, span + 0.5)
	rim.mesh = slab
	rim.position.y = -0.151
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.12, 0.11, 0.1)
	rim_mat.roughness = 0.8
	rim.material_override = rim_mat
	_view.add_child(rim)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_view.add_child(_camera)
	_camera.look_at_from_position(CAMERA_POS, LOOK_AT)


## 바르코 바닥판 그림. 없으면(에셋을 안 받은 사람) 흑백 체크로
static func _board_texture() -> Texture2D:
	var path := "res://assets/trainers/trainer_board.jpg"
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(BOARD_TILES, BOARD_TILES, false, Image.FORMAT_RGB8)
	for x in BOARD_TILES:
		for y in BOARD_TILES:
			img.set_pixel(x, y, Color(0.62, 0.63, 0.62) if (x + y) % 2 == 0 else Color(0.16, 0.17, 0.17))
	var tex := ImageTexture.create_from_image(img)
	return tex


## 덤벨 하나 — 바르코 모델. 없으면 같은 키의 기둥으로 대신한다 (다른 모델과 같은 규칙)
func _dumbbell(gold: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "dumbbell"
	var rig := Rig.create("dumbbell_gold" if gold else "dumbbell_white", DUMBBELL_HEIGHT)
	if rig != null:
		holder.add_child(rig)
	else:
		var pillar := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.18
		mesh.bottom_radius = 0.22
		mesh.height = DUMBBELL_HEIGHT
		pillar.mesh = mesh
		pillar.position.y = DUMBBELL_HEIGHT * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.68, 0.25) if gold else Color(0.9, 0.9, 0.88)
		mat.metallic = 0.8 if gold else 0.0
		mat.roughness = 0.3
		pillar.material_override = mat
		holder.add_child(pillar)
	_view.add_child(holder)
	return holder


func _button(id: String, text: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(220, 58)
	button.add_theme_font_size_override("font_size", 24)
	button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	button.offset_left = -110
	button.offset_right = 110
	button.offset_top = -86
	button.offset_bottom = -28
	add_child(button)
	ButtonFx.attach(button)
	return button


## 모두 보기 — 덤벨이 아직 떨어지는 중이면 다 선 것으로 치고 바로 시작한다
func reveal_all() -> void:
	if _reveal_at >= 0.0:
		return
	_reveal_at = _time
	_reveal.visible = false


## 연출을 건너뛰고 끝 상태로 (테스트 · 다시 그릴 때)
func finish() -> void:
	if _reveal_at < 0.0:
		reveal_all()
	_step(1000.0)


## 덤벨 노드들 — 테스트가 본다 (`gold` · `id`)
func pieces() -> Array:
	return _pieces


## 선 카드들 (보기 전에는 비어 있다)
func cards() -> Array:
	var out: Array = []
	for piece in _pieces:
		if piece.card != null:
			out.append(piece.card)
	return out


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_step(delta)


func _step(delta: float) -> void:
	_time += delta
	for i in _pieces.size():
		var piece: Dictionary = _pieces[i]
		_drop(piece, i)
		if _reveal_at >= 0.0:
			_reveal_piece(piece, _time - _reveal_at - REVEAL_GAP * float(_order(i)))
	if _reveal_at >= 0.0 and not _ok.visible:
		var last := REVEAL_GAP * float(maxi(0, _pieces.size() - 1)) + CARD_AT + CARD_POP
		if _time - _reveal_at >= last:
			_ok.visible = true
	_place_cards()


## 떨어지고 보는 순서 — 덜 띄는 자리부터, 가장 좋은 것(자리 0)이 마지막
func _order(i: int) -> int:
	return _pieces.size() - 1 - i


func _drop(piece: Dictionary, i: int) -> void:
	var node: Node3D = piece.node
	if piece.started:
		return
	var t := _time - DROP_GAP * float(_order(i))
	if _reveal_at >= 0.0:
		t = DROP_TIME  # 보기를 누르면 다 선 것으로
	if t < 0.0:
		return
	node.visible = true
	var k := clampf(t / DROP_TIME, 0.0, 1.0)
	# 떨어져 살짝 튀었다가 앉는다
	var fall := 1.0 - k * k if k < 0.75 else 0.06 * sin((k - 0.75) / 0.25 * PI)
	node.position = Vector3(piece.slot.x, DROP_HEIGHT * maxf(0.0, fall), piece.slot.z)
	if k >= 1.0:
		node.position.y = 0.0
		piece.started = true


## 한 덤벨의 보기 — `t` 는 그 덤벨 차례가 온 뒤 지난 초
func _reveal_piece(piece: Dictionary, t: float) -> void:
	if t < 0.0:
		return
	var node: Node3D = piece.node
	if piece.fx == null:
		piece.fx = _make_fx(piece)
	var fx: Node3D = piece.fx
	# 덤벨은 살짝 뜨며 빛 속으로 줄어든다
	var gone := clampf(t / CARD_AT, 0.0, 1.0)
	node.scale = Vector3.ONE * (1.0 - gone * gone)
	node.position.y = 0.25 * gone
	node.visible = gone < 1.0
	_tick_fx(fx, t)
	if t >= CARD_AT and piece.card == null:
		piece.card = _make_card(piece)
	if piece.card != null:
		var k := clampf((t - CARD_AT) / CARD_POP, 0.0, 1.0)
		var card: Control = piece.card
		card.modulate.a = k
		card.set_meta("pop", 0.7 + 0.3 * (1.0 - pow(1.0 - k, 3.0)) + 0.06 * sin(k * PI))


## 빛 — 기둥(세로 띠, 카메라를 보며 Y 축으로만 돈다) · 발밑 섬광(제자리에서 사그라든다) · 바닥 빛 · 희귀 이상은 반짝이
func _make_fx(piece: Dictionary) -> Node3D:
	var color := TrainerPanel.grade_color(int(piece.grade)).lightened(0.25)
	if not bool(piece.gold) and int(piece.grade) <= 1:
		color = Color(0.85, 0.9, 1.0)
	var root := Node3D.new()
	root.name = "fx"
	root.position = piece.slot
	_view.add_child(root)

	# 기둥은 폭만 다른 3겹 — 넓은 번짐 · 등급 색 · 가는 흰 심 (effect-rules.md 5절). 영웅부터 더 굵다
	var beam := Node3D.new()
	beam.name = "beam"
	root.add_child(beam)
	var thick := 1.0 + 0.25 * maxf(0.0, float(int(piece.grade) - GOLD_GRADE))
	for layer in [[2.4, 0.35, color], [1.1, 0.85, color], [0.32, 1.0, color.lerp(Color.WHITE, 0.8)]]:
		var strip := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(float(layer[0]) * thick, BEAM_HEIGHT)
		quad.center_offset = Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
		strip.mesh = quad
		strip.material_override = TrainerDraw._glow_mat(TrainerDraw._beam(), layer[2], BaseMaterial3D.BILLBOARD_FIXED_Y)
		strip.set_meta("alpha", layer[1])
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(strip)

	var core := MeshInstance3D.new()
	core.name = "flash"
	var core_quad := QuadMesh.new()
	core_quad.size = Vector2(2.0, 2.0)
	core.mesh = core_quad
	core.position.y = 0.55
	core.material_override = TrainerDraw._glow_mat(FxTex.glow(), color.lerp(Color.WHITE, 0.5), BaseMaterial3D.BILLBOARD_ENABLED)
	root.add_child(core)

	var floor_glow := MeshInstance3D.new()
	floor_glow.name = "floor"
	var floor_quad := QuadMesh.new()
	floor_quad.size = Vector2(2.2, 2.2)
	floor_glow.mesh = floor_quad
	floor_glow.rotation_degrees.x = -90.0
	floor_glow.position.y = 0.02
	floor_glow.material_override = TrainerDraw._glow_mat(FxTex.glow(), color, BaseMaterial3D.BILLBOARD_DISABLED)
	root.add_child(floor_glow)

	if bool(piece.gold):
		var sparks := CPUParticles3D.new()
		sparks.name = "sparks"
		sparks.one_shot = true
		sparks.emitting = false
		sparks.amount = 14 + 8 * (int(piece.grade) - GOLD_GRADE)
		sparks.lifetime = 1.0
		sparks.explosiveness = 1.0
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sparks.emission_sphere_radius = 0.35
		sparks.direction = Vector3.UP
		sparks.spread = 30.0
		sparks.initial_velocity_min = 1.6
		sparks.initial_velocity_max = 3.4
		sparks.gravity = Vector3(0.0, -1.2, 0.0)
		sparks.scale_amount_min = 0.5
		sparks.scale_amount_max = 1.0
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		sparks.scale_amount_curve = curve
		var dot := QuadMesh.new()
		dot.size = Vector2(0.14, 0.14)
		sparks.mesh = dot
		sparks.material_override = TrainerDraw._glow_mat(FxTex.glow(), color.lerp(Color.WHITE, 0.35), BaseMaterial3D.BILLBOARD_PARTICLES)
		sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sparks.position.y = 0.4
		root.add_child(sparks)
	return root


func _tick_fx(fx: Node3D, t: float) -> void:
	var beam: Node3D = fx.get_node("beam")
	# 기둥 — 0.12초에 솟아 0.45초까지 버티고 끝까지 가늘어지며 사그라든다
	var rise := clampf(t / 0.12, 0.0, 1.0)
	var fade := 1.0 - clampf((t - 0.45) / (REVEAL_TIME - 0.45), 0.0, 1.0)
	beam.scale = Vector3(lerpf(0.35, 1.0, rise) * lerpf(0.45, 1.0, fade), rise, 1.0)
	for strip in beam.get_children():
		_alpha(strip, float(strip.get_meta("alpha", 1.0)) * rise * fade)
	var flash: MeshInstance3D = fx.get_node("flash")
	_alpha(flash, clampf(1.0 - t / 0.55, 0.0, 1.0) * clampf(t / 0.05, 0.0, 1.0))
	var floor_glow: MeshInstance3D = fx.get_node("floor")
	_alpha(floor_glow, 0.8 * fade * rise)
	if fx.has_node("sparks"):
		var sparks: CPUParticles3D = fx.get_node("sparks")
		# 만든 다음 프레임에 한 번만 켠다 (effect-rules.md 3절)
		if t > 0.0 and not sparks.has_meta("fired"):
			sparks.set_meta("fired", true)
			sparks.restart()
	fx.visible = t < REVEAL_TIME + 0.2


func _alpha(mesh: MeshInstance3D, a: float) -> void:
	var mat: StandardMaterial3D = mesh.material_override
	mat.albedo_color.a = a


static func _glow_mat(tex: Texture2D, color: Color, billboard: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.billboard_mode = billboard
	mat.billboard_keep_scale = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.vertex_color_use_as_albedo = billboard == BaseMaterial3D.BILLBOARD_PARTICLES
	return mat


## 기둥 그림 — 가로는 가운데가 밝은 띠, 세로는 아래가 밝고 위로 사그라든다
static func _beam() -> ImageTexture:
	if _beam_tex != null:
		return _beam_tex
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var up := float(y) / float(h - 1)  # 0 = 위
		var v := pow(up, 1.6) * clampf((1.0 - up) / 0.04, 0.0, 1.0)
		for x in w:
			var u := absf(float(x) / float(w - 1) * 2.0 - 1.0)
			var core := pow(maxf(0.0, 1.0 - u), 2.2)
			var hot := pow(maxf(0.0, 1.0 - u * 3.0), 2.0)
			var c := clampf(core * 0.8 + hot, 0.0, 1.0) * v
			img.set_pixel(x, y, Color(c, c, c, c))
	_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


## 카드 — 이름(등급 색) · 그림(등급 색 테) · NEW
func _make_card(piece: Dictionary) -> Control:
	var info := Trainers.trainer(str(piece.id))
	var grade := int(piece.grade)
	var color := TrainerPanel.grade_color(grade)
	var card := VBoxContainer.new()
	card.name = "card_%s" % str(piece.id)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_constant_override("separation", 2)
	card.modulate.a = 0.0

	var label := Label.new()
	label.name = "name"
	label.text = str(info.get("name", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)

	var frame := PanelContainer.new()
	frame.name = "frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.06, 0.05)
	box.border_color = color.lightened(0.15)
	box.set_border_width_all(3)
	box.set_content_margin_all(4)
	if grade >= GOLD_GRADE:
		box.shadow_color = Color(color.r, color.g, color.b, 0.55)
		box.shadow_size = 10
	frame.add_theme_stylebox_override("panel", box)
	card.add_child(frame)
	var pic := TextureRect.new()
	pic.name = "art"
	pic.custom_minimum_size = ART
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = _portrait.call(str(piece.id)) if _portrait.is_valid() else null
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	if bool(piece.fresh):
		var tag := Label.new()
		tag.name = "tag"
		tag.text = "NEW"
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", GOLD)
		tag.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
		tag.add_theme_constant_override("outline_size", 5)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.anchor_left = 1.0
		tag.anchor_right = 1.0
		tag.offset_left = -60
		tag.offset_right = -4
		tag.offset_top = 2
		tag.offset_bottom = 24
		pic.add_child(tag)

	# 뒤 줄 카드가 먼저 깔리고 앞 줄이 그 위에 덮인다
	var index := 0
	for other in _layer.get_children():
		if float(other.get_meta("z", 0.0)) <= float(piece.slot.z):
			index += 1
	card.set_meta("z", float(piece.slot.z))
	card.set_meta("pop", 0.7)
	_layer.add_child(card)
	_layer.move_child(card, index)
	return card


## 카드를 덤벨 발밑 자리에 세운다 — 화면 크기 · 깊이를 따라 배율을 매 프레임 다시 잡는다
func _place_cards() -> void:
	var view_h := size.y if size.y > 0.0 else BASE_VIEW_H
	for piece in _pieces:
		var card: Control = piece.card
		if card == null:
			continue
		var foot: Vector3 = piece.slot + Vector3(0.0, 0.0, 0.25)
		var depth := _camera.position.distance_to(foot)
		var k := CARD_SCALE * (view_h / BASE_VIEW_H) * (_ref_depth / maxf(0.1, depth)) * float(card.get_meta("pop", 1.0))
		var at := _camera.unproject_position(foot)
		var box := card.get_combined_minimum_size()
		card.size = box
		card.pivot_offset = Vector2(box.x * 0.5, box.y)
		card.scale = Vector2.ONE * k
		card.position = at - card.pivot_offset
