class_name TrainerDraw
extends Control

## 트레이너 뽑기 연출 (2026-10-06 요청: 체스판 스크린샷 두 장 + "뽑기 갯수에 따라 3D 모델이 이렇게 나올거고 … 보기 버튼
## 누르면 … 이펙트가 나오면서 어떤 캐릭터가 나왔는지 표시하고, 이름은 등급 색상에 맞게". 같은 날 고침: "바닥을 똑같이
## 만들라는게 아니야. 배치를 저런 식으로 하라고 한 거야 … 덤벨로 하지 말고, 스샷 보내준 것 처럼 밀랍 느낌의 사람으로
## 만들어. 희귀 등급 이상부터는 금색 밀랍으로").
##
##   어두운 수련장 바닥 위로 뽑은 수만큼 **밀랍 조각상**(사람 넷 중 하나)이 하나씩 내려선다 — 자리는 받은 스크린샷의 대형
##   → [모두 보기] → 조각상마다 차례로 빛기둥이 솟고 조각상이 빛 속으로 사라지며 그 자리에 트레이너 카드가 선다
##   → 카드 위 이름은 등급 색 · 새로 얻은 것은 NEW → [확인]
##
## 조각상은 바르코(`draw_statue<1~4>_white.glb` · `_gold.glb`, 같은 메시에 금빛 텍스처만 다르다), 바닥 그림도 바르코
## (`trainer_floor.jpg`). 빛기둥·섬광·반짝이는 코드로 짓는다 (effect-rules.md). 카드는 3D 가 아니라 **화면 위 조각** —
## 조각상 발밑을 화면에 비춰 그 자리에 세우고 멀수록 작게 그린다 → docs/features/trainers.md "뽑기 연출"

## 확인을 눌렀다 — 상점이 판을 걷는다
signal closed
## [N회 뽑기] 를 눌렀다 — 상점이 같은 뽑기를 한 번 더 산다 (결과가 오면 이 판을 새 판으로 갈아 끼운다)
signal again(times: int)

## 이 등급부터 금빛 밀랍 (희귀)
const GOLD_GRADE := 3
## 조각상 종류 수(보디빌더 · 권투선수 · 격투가 · 노사범)와 키(m, 받침 포함)
const STATUE_KINDS := 4
const STATUE_HEIGHT := 1.6
## 바닥 한 변(m)
const FLOOR_SIZE := 11.0
## 자리 — 받은 스크린샷의 대형(뒤 2 · 둘째 2 · 셋째 3 · 넷째 2 · 앞 모서리 2 = 11자리)을 판 위 좌표로 옮겼다.
## 눈에 띄는 순서로 적는다(넷째 줄 → 앞 모서리 → 셋째 줄 양끝 → 둘째 → 뒤 → 셋째 가운데). 10회는 앞 열 자리라
## **가운데가 비고** 둘레로 선다. 1회는 판 가운데
const LAYOUT := [
	Vector3(-1.15, 0.0, 0.55), Vector3(1.15, 0.0, 0.55),
	Vector3(-2.35, 0.0, 1.45), Vector3(2.35, 0.0, 1.45),
	Vector3(-3.2, 0.0, -0.4), Vector3(3.2, 0.0, -0.4),
	Vector3(-2.05, 0.0, -1.4), Vector3(2.05, 0.0, -1.4),
	Vector3(-0.85, 0.0, -2.35), Vector3(0.85, 0.0, -2.35),
	Vector3(0.0, 0.0, -0.4),
]
const FOV := 40.0
const CAMERA_POS := Vector3(0.0, 4.1, 6.3)
const LOOK_AT := Vector3(0.0, 0.65, -0.5)

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

## 카드(화면 조각) — 그림 크기 · 기준 화면 높이 · 기준 배율
const ART := Vector2(126, 168)
const BASE_VIEW_H := 720.0
const CARD_SCALE := 1.2
## 카드가 서는 칸 — 한 줄 최대 장 수 · 칸 사이(기준 배율 전) · 화면 가장자리 · 아래 [확인] 자리
const ROW_MAX := 5
const CELL_GAP := Vector2(16, 14)
const EDGE := 20.0
const BUTTON_ROOM := 100.0

const IVORY := Color("#eeead7")
const GOLD := GatePanel.CARD_GOLD

var _view: SubViewport
var _camera: Camera3D
var _pieces: Array = []  # {id, grade, fresh, gold, slot: Vector3, node: Node3D, fx: Node3D, card: Control, started}
var _layer: Control
var _reveal: Button
var _ok: Button
## 확인 옆 다시 뽑기 — 1장이면 1회, 여러 장이면 `Trainers.draw_multi()` 회 (2026-10-08 요청 "1회 뽑기였으면 1회 뽑기,
## 10회 뽑기였으면 10회 뽑기 버튼을 확인 버튼 옆에")
var _again: Button
var _times := 1
var _time := 0.0
var _reveal_at := -1.0
## 칸 — 줄마다 장 수 · 칸 크기(기준 배율 전, 가장 긴 이름에 맞춘다 — 처음 그릴 때 잰다)
var _row_len: Array = []
var _cell := Vector2.ZERO
## 뽑힌 트레이너를 **3D 모델로 찍는 보이지 않는 무대** (2026-10-07 요청 "뽑기 화면이 2D 이미지로 나오는데, 3D 모델로
## 변경해") — 트레이너 창을 한 번도 안 열었으면 찍어 둔 그림이 없어 원화가 섰다. 판이 열리자마자 뽑힌 것만 찍는다
var _shots: TrainerPortraits

static var _beam_tex: ImageTexture


## `got` 은 뽑힌 트레이너 id, `fresh` 는 새로 얻었나(같은 순서). 카드 그림은 판이 3D 모델로 찍는다(`_shots`)
static func make(got: Array, fresh: Array) -> TrainerDraw:
	var draw := TrainerDraw.new()
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
		entry.node = _statue(i % STATUE_KINDS, bool(entry.gold))
		entry.node.position = Vector3(entry.slot.x, DROP_HEIGHT, entry.slot.z)
		entry.node.visible = false
		entry.fx = null
		entry.card = null
		entry.started = false
		_pieces.append(entry)
	_row_len = TrainerDraw.cells(_pieces)

	_shots = TrainerPortraits.new()
	add_child(_shots)
	_shots.baked.connect(_on_baked)
	_shots.request(got)

	_reveal = _button("reveal", "모두 보기")
	_reveal.pressed.connect(reveal_all)
	_ok = _button("ok", "확인")
	_ok.visible = false
	_ok.pressed.connect(func() -> void: closed.emit())
	_times = 1 if got.size() <= 1 else Trainers.draw_multi()
	_again = _button("again", "%d회 뽑기" % _times)
	_again.visible = false
	_again.pressed.connect(func() -> void: again.emit(_times))
	# 둘이 나란히 — [확인] 왼쪽 · [N회 뽑기] 오른쪽 (단추 폭 220 · 사이 20)
	_ok.offset_left = -230
	_ok.offset_right = -10
	_again.offset_left = 10
	_again.offset_right = 230


## 자리 — `LAYOUT` 앞에서부터 `count` 개. 1회는 판 가운데, 11개를 넘으면 맨 뒤에 한 줄씩 더 깐다
static func slots(count: int) -> Array:
	if count <= 0:
		return []
	if count == 1:
		return [Vector3.ZERO]
	var out: Array = LAYOUT.slice(0, mini(count, LAYOUT.size()))
	var extra := count - out.size()
	for i in extra:
		out.append(Vector3((float(i % 6) - 2.5) * 1.1, 0.0, -3.2 - 0.9 * float(i / 6)))
	return out


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.04, 0.04)
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
	# 앞에서 조각상 몸을 살리는 약한 빛
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -25, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.85, 0.85)
	_view.add_child(fill)

	# 바닥 — 판이 아니라 수련장 바닥 한 장. 가장자리는 스포트라이트 밖이라 어둠에 묻힌다
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TrainerDraw._floor_texture()
	mat.roughness = 0.75
	floor_mesh.material_override = mat
	_view.add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_view.add_child(_camera)
	_camera.look_at_from_position(CAMERA_POS, LOOK_AT)


## 바르코 바닥 그림. 없으면(에셋을 안 받은 사람) 어두운 나무색 한 장으로
static func _floor_texture() -> Texture2D:
	var path := "res://assets/trainers/trainer_floor.jpg"
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.15, 0.11))
	return ImageTexture.create_from_image(img)


## 조각상 하나 — 바르코 모델(`kind` 0~3, 흰 밀랍 / 금빛 밀랍). 없으면 같은 키의 기둥으로 대신한다 (다른 모델과 같은 규칙)
func _statue(kind: int, gold: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "statue"
	var rig := Rig.create("draw_statue%d_%s" % [kind + 1, "gold" if gold else "white"], STATUE_HEIGHT)
	if rig != null:
		holder.add_child(rig)
	else:
		var pillar := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.16
		mesh.bottom_radius = 0.24
		mesh.height = STATUE_HEIGHT
		pillar.mesh = mesh
		pillar.position.y = STATUE_HEIGHT * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.68, 0.25) if gold else Color(0.9, 0.88, 0.82)
		mat.metallic = 0.6 if gold else 0.0
		mat.roughness = 0.35
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


## 모두 보기 — 조각상이 아직 떨어지는 중이면 다 선 것으로 치고 바로 시작한다
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


## 카드 칸 — 조각상 대형 그대로는 앞뒤 줄 간격(화면 50~90px)이 카드 키(200px 넘게)보다 좁아 겹친다 (2026-10-08 "서로 겹치지
## 않게"). 그래서 카드는 한 줄 `ROW_MAX` 장 이하의 줄로 선다 — **뒤에 선 조각상이 윗줄**, 줄 안에서는 왼쪽부터라 카드가
## 제 조각상 가까운 칸으로 미끄러진다. 각 조각(`piece`)에 `cell`(열, 줄)을 매기고 줄마다 장 수를 돌려준다
static func cells(pieces: Array) -> Array:
	var count := pieces.size()
	if count == 0:
		return []
	var rows := ceili(float(count) / float(ROW_MAX))
	var order: Array = range(count)
	order.sort_custom(func(a, b): return pieces[a].slot.z < pieces[b].slot.z \
		or (pieces[a].slot.z == pieces[b].slot.z and pieces[a].slot.x < pieces[b].slot.x))
	var row_len: Array = []
	var at := 0
	for row in rows:
		# 남은 장을 남은 줄에 고르게 — 10 은 5 · 5, 7 은 4 · 3
		var n := ceili(float(count - at) / float(rows - row))
		var line: Array = order.slice(at, at + n)
		line.sort_custom(func(a, b): return pieces[a].slot.x < pieces[b].slot.x)
		for col in line.size():
			pieces[line[col]].cell = Vector2i(col, row)
		row_len.append(n)
		at += n
	return row_len


## 조각상 노드들 — 테스트가 본다 (`gold` · `id`)
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
			_again.visible = true
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


## 한 조각상의 보기 — `t` 는 그 조각상 차례가 온 뒤 지난 초
func _reveal_piece(piece: Dictionary, t: float) -> void:
	if t < 0.0:
		return
	var node: Node3D = piece.node
	if piece.fx == null:
		piece.fx = _make_fx(piece)
	var fx: Node3D = piece.fx
	# 조각상은 살짝 뜨며 빛 속으로 줄어든다
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
		card.set_meta("move", 1.0 - pow(1.0 - k, 3.0))


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


## 3D 그림이 찍혔다 — 이미 선 카드면 그림을 갈아 끼운다 (아직 안 선 카드는 설 때 찍은 것을 쓴다)
func _on_baked(id: String, texture: Texture2D) -> void:
	for piece in _pieces:
		if str(piece.id) == id and piece.card != null:
			var pic: TextureRect = piece.card.find_child("art", true, false)
			if pic != null:
				pic.texture = texture


## 카드 그림 — 찍은 3D 그림. 아직 못 찍었으면 **비워 두고** 찍히는 대로 채운다(`_on_baked`) — 원화를 먼저 세우면
## 2D 가 섰다가 3D 로 바뀐다 (2026-10-07)
func _art(id: String) -> Texture2D:
	return TrainerPortraits.cached(id)


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
	pic.texture = _art(str(piece.id))
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


## 카드를 세운다 — 조각상 발밑에서 솟아 제 칸(`cells`)으로 미끄러진다. 칸은 화면 안(가장자리 · 아래 [확인] 자리 빼고)에
## 다 들어가게 배율을 매 프레임 다시 잡는다 — 화면 크기가 바뀌어도 겹치지 않는다
func _place_cards() -> void:
	if _pieces.is_empty() or cards().is_empty():
		return
	var view := size if size.y > 0.0 else Vector2(BASE_VIEW_H * 16.0 / 9.0, BASE_VIEW_H)
	var cell := _cell_size()
	var rows := _row_len.size()
	var cols := 1
	for n in _row_len:
		cols = maxi(cols, int(n))
	var area := Rect2(EDGE, EDGE, view.x - EDGE * 2.0, view.y - EDGE - BUTTON_ROOM)
	var k := minf(CARD_SCALE * view.y / BASE_VIEW_H,
		minf(area.size.x / (cell.x * cols), area.size.y / (cell.y * rows)))
	var top := area.get_center().y - cell.y * k * rows * 0.5
	for piece in _pieces:
		var card: Control = piece.card
		if card == null:
			continue
		var at := Vector2(piece.cell)
		var spot := Vector2(area.get_center().x + (at.x - (float(_row_len[int(at.y)]) - 1.0) * 0.5) * cell.x * k,
			top + (at.y + 1.0) * cell.y * k - CELL_GAP.y * k * 0.5)
		var foot := _camera.unproject_position(piece.slot + Vector3(0.0, 0.0, 0.25))
		var box := card.get_combined_minimum_size()
		card.size = box
		card.pivot_offset = Vector2(box.x * 0.5, box.y)
		card.scale = Vector2.ONE * k * float(card.get_meta("pop", 1.0))
		card.position = foot.lerp(spot, float(card.get_meta("move", 1.0))) - card.pivot_offset


## 칸 크기(기준 배율 전) — 그림 테 · 가장 긴 이름 중 넓은 쪽 + 칸 사이. 글꼴을 재야 해서 처음 그릴 때 한 번 잰다
func _cell_size() -> Vector2:
	if _cell != Vector2.ZERO:
		return _cell
	var font := get_theme_font("font", "Label")
	var frame := ART + Vector2(14, 14)
	var wide := frame.x
	for piece in _pieces:
		var text := str(Trainers.trainer(str(piece.id)).get("name", ""))
		wide = maxf(wide, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 12.0)
	_cell = Vector2(wide, frame.y + 2.0 + font.get_height(19) + 12.0) + CELL_GAP
	return _cell
