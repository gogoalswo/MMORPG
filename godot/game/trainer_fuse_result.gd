class_name TrainerFuseResult
extends Control

## 트레이너 합성 결과 판 (2026-10-08 요청 "합성 버튼 누르면 이런식으로 나오면 좋겠어" + 뽑기 결과 스크린샷 한 장) —
## 뒤 화면을 흐리게 덮고, 위 가운데 **합성 결과** 제목(금빛 가는 선 양쪽), 가운데 도전마다 카드 한 장, 오른쪽 위 X.
##
##   ─────◆  합성 결과  ◆─────                                    [X]
##
##          (빛)┌────┐      ┌────┐
##              │모델│      │실패│        ← 성공은 얻은 트레이너(뒤에서 일렁이는 빛), 실패는 돌려받은 같은 등급 1장
##              └────┘      └────┘          — 둘 다 테두리가 그 카드의 등급 색 (`edge_color`)
##               이름         이름
##
## 카드 그림은 트레이너 창이 3D 모델로 찍은 것(`TrainerPortraits`) — 아직 못 찍었으면 비워 두고 찍히면 채운다(`set_art`).
## 불길은 이펙트 규칙대로 코드로 짓는다 — 셰이더 한 장(`FLAME_SHADER`, 테두리 거리 + 위로 흐르는 노이즈) → docs/features/trainers.md "합성"

## X 를 눌렀다 — 트레이너 창이 판을 걷는다
signal closed

const ART := Vector2(150, 200)
const NAME_ROOM := 56.0
const CARD_GAP := 56
## 한 줄 카드 수 · 줄 사이 · 두 줄일 때 판 전체 배율 (1280 × 720 에 10장이 들어가게)
const ROW_MAX := 5
const ROW_GAP := 28
const MANY_SCALE := 0.78
## 카드가 하나씩 튀어나오는 간격 · 걸리는 시간 · 처음 배율
const POP_GAP := 0.18
const POP_TIME := 0.28
const POP_SCALE := 1.3
## 테두리 불길 — 카드 밖으로 뻗는 길이(px, 노이즈로 0.45 ~ 1.35 배). 색은 카드 등급 색(`edge_color`)
const FLAME_REACH := 36.0
## 불길 셰이더 — 카드 테두리까지의 거리(`d`) + 위로 흐르는 값 노이즈. 위쪽 불길이 더 길다. 가산
const FLAME_SHADER := "shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color;
uniform vec2 box;
uniform vec2 rect;
uniform float reach = 30.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 p = (UV - 0.5) * rect;
	vec2 q = abs(p) - box;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	float t = TIME;
	vec2 s = p + vec2(seed * 31.0, seed * 17.0);
	float n = fbm(vec2(s.x * 0.05, s.y * 0.05 + t * 1.7));
	float n2 = fbm(vec2(s.x * 0.11, s.y * 0.11 + t * 2.9));
	float up = clamp(-p.y / box.y, 0.0, 1.0);
	float len = reach * (0.45 + 0.9 * n) * (1.0 + 0.7 * up);
	float f = 1.0 - smoothstep(-2.0, len, d);
	f = f * f * (0.55 + 0.75 * n2);
	float halo = 0.24 * exp(-max(d, 0.0) / (reach * 1.4)) * (1.0 - smoothstep(reach * 1.2, reach * 2.3, d));
	float a = clamp(f + halo, 0.0, 1.0) * step(-3.0, d);
	vec3 col = mix(tint.rgb, mix(tint.rgb, vec3(1.0), 0.75), smoothstep(0.55, 1.0, f));
	COLOR = vec4(col, a);
}"

const IVORY := Color("#eeead7")
const GOLD := GatePanel.CARD_GOLD
const DIM := Color("#948c7a")

## 뒤 화면 흐리게 + 가장자리 어둡게 (모바일 렌더러는 화면 텍스처 밉맵을 쓴다)
const BLUR_SHADER := "shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.0;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, lod).rgb;
	float edge = clamp(distance(UV, vec2(0.5)) * 1.3, 0.0, 1.0);
	COLOR = vec4(c * (0.42 - edge * 0.3), 1.0);
}"

var _cards: Array = []  # {id, holder: Control, art: TextureRect}
var _time := 0.0
var _close: Button


## `results` 는 장부의 `trainerFuse` 결과 `[{used, got, back}]` — got 이 "" 면 실패, back 은 실패 때 돌려받은 같은 등급 1장
static func make(results: Array) -> TrainerFuseResult:
	var view := TrainerFuseResult.new()
	view._build(results)
	return view


func _build(results: Array) -> void:
	name = "TrainerFuseResult"
	# 트레이너 창(컨테이너) 안에 붙어도 판 크기에 끼이지 않고 화면 전체를 덮는다
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.02, 0.02, 0.03, 0.85)
	var blur := ShaderMaterial.new()
	blur.shader = Shader.new()
	blur.shader.code = BLUR_SHADER
	back.material = blur
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_build_title()

	# 도전은 한 번에 10번까지라(칸 30개, 2026-10-08) 한 줄에 `ROW_MAX` 장 — 넘으면 줄을 나눠 고르게 담고 조금 줄인다
	var column := VBoxContainer.new()
	column.name = "cards"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", ROW_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var rows := maxi(1, ceili(results.size() / float(ROW_MAX)))
	var per := ceili(results.size() / float(rows))
	if rows > 1:
		column.scale = Vector2.ONE * MANY_SCALE
		column.resized.connect(func() -> void: column.pivot_offset = column.size * 0.5)
	var row: HBoxContainer = null
	for i in results.size():
		if i % maxi(per, 1) == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", CARD_GAP)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(row)
		var holder := _card(results[i])
		holder.modulate.a = 0.0
		row.add_child(holder)

	_close = Button.new()
	_close.name = "close"
	_close.text = "✕"
	_close.focus_mode = Control.FOCUS_NONE
	_close.custom_minimum_size = Vector2(56, 56)
	_close.add_theme_font_size_override("font_size", 30)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.06, 0.9)
	box.border_color = GOLD.darkened(0.2)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed"]:
		_close.add_theme_stylebox_override(state, box)
	_close.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close.add_theme_color_override("font_color", IVORY)
	_close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close.offset_left = -84
	_close.offset_right = -28
	_close.offset_top = 24
	_close.offset_bottom = 80
	_close.pressed.connect(func() -> void: closed.emit())
	add_child(_close)


## 위 가운데 제목 — 금빛 가는 선 + 마름모 + 글자 (받은 그림의 "뽑기 결과" 결)
func _build_title() -> void:
	var bar := HBoxContainer.new()
	bar.name = "title_bar"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -360
	bar.offset_right = 360
	bar.offset_top = 34
	bar.offset_bottom = 84
	add_child(bar)
	bar.add_child(_line(true))
	bar.add_child(_diamond())
	var title := Label.new()
	title.name = "title"
	title.text = "합성 결과"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#f4d9a0"))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.02))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.15, 0.45))
	title.add_theme_constant_override("shadow_outline_size", 14)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	bar.add_child(title)
	bar.add_child(_diamond())
	bar.add_child(_line(false))


## 가는 금선 — 글자 쪽이 진하고 바깥으로 사라진다
func _line(left: bool) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(GOLD, 0.0) if left else Color(GOLD, 0.9))
	gradient.set_color(1, Color(GOLD, 0.9) if left else Color(GOLD, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 2
	var line := TextureRect.new()
	line.texture = tex
	line.custom_minimum_size = Vector2(190, 2)
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _diamond() -> Control:
	var room := Control.new()
	room.custom_minimum_size = Vector2(12, 12)
	room.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = GOLD
	dot.size = Vector2(8, 8)
	dot.position = Vector2(2, 2)
	dot.pivot_offset = Vector2(4, 4)
	dot.rotation_degrees = 45.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(dot)
	return room


## 카드 테두리 색 — 등급 색(`Items.grade_color`)은 어두운 판 위 글자용이라 탁하다. 색조는 두고 채도·밝기만 올려
## 테두리·불길로 또렷하게 (2026-10-08 요청 "합성 결과를 등급에 맞는 색상으로 테두리를 만들어")
static func edge_color(grade: int) -> Color:
	var base := TrainerPanel.grade_color(grade)
	return Color.from_hsv(base.h, minf(base.s * 1.25, 1.0), maxf(base.v, 0.9))


## 도전 하나의 카드 — 성공(`got`)은 얻은 트레이너, 실패는 돌려받은 같은 등급 1장(`back`, 옛 결과라 없으면 어두운 칸).
## 테두리는 그 카드의 등급 색, 불길은 성공에만
func _card(result: Dictionary) -> Control:
	var won := str(result.get("got", "")) != ""
	var id := str(result.get("got", "")) if won else str(result.get("back", ""))
	var info := Trainers.trainer(id)
	var has := not info.is_empty()
	var color := TrainerFuseResult.edge_color(int(info.get("grade", 1))) if has else DIM
	var holder := Control.new()
	holder.name = "card_%s" % id if won else ("card_fail_%s" % id if has else "card_fail")
	holder.custom_minimum_size = Vector2(ART.x + 8, ART.y + 8 + NAME_ROOM)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.pivot_offset = holder.custom_minimum_size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := Vector2(ART.x + 8, ART.y + 8) * 0.5
	if won:
		# 테두리 불길 — 셰이더 한 장(`FLAME_SHADER`): 카드 테두리까지의 거리로 띠를 그리고, 위로 흐르는 노이즈로 길이·밝기를
		# 흔든다. 색은 테두리와 같은 등급 색(`edge_color`) — 전엔 불빛 주황을 75% 섞어 등급이 다 주황으로 보였다.
		# 조각을 늘어놓던 시안은 버렸다 (2026-10-08 찍어 보고) — 뭉게 텍스처는 갈색 연기, 세로 빛 혀는 햇살 무늬·전구 줄이 됐다
		var edge := Vector2(ART.x + 8, ART.y + 8)
		var room := edge + Vector2.ONE * FLAME_REACH * 5.0
		var flame := ColorRect.new()
		flame.name = "flame"
		flame.size = room
		flame.position = center - room * 0.5
		var mat := ShaderMaterial.new()
		mat.shader = TrainerFuseResult._flame_shader()
		mat.set_shader_parameter("tint", color)
		mat.set_shader_parameter("box", edge * 0.5)
		mat.set_shader_parameter("rect", room)
		mat.set_shader_parameter("reach", FLAME_REACH)
		mat.set_shader_parameter("seed", float(_cards.size()) * 7.3)
		flame.material = mat
		flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(flame)

	var frame := Panel.new()
	frame.name = "frame"
	frame.size = Vector2(ART.x + 8, ART.y + 8)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.05, 0.05) if has else Color(0.07, 0.07, 0.07, 0.92)
	box.border_color = color if has else Color(0.3, 0.3, 0.28)
	box.set_border_width_all(4 if has else 3)
	# 테두리 바깥으로 번지는 등급 색 빛 — 성공은 진하게, 실패는 옅게
	box.shadow_color = Color(color, 0.6 if won else 0.3) if has else Color(0, 0, 0, 0)
	box.shadow_size = 10 if has else 0
	frame.add_theme_stylebox_override("panel", box)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var art := TextureRect.new()
	art.name = "art"
	art.position = Vector2(4, 4)
	art.size = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = TrainerPortraits.cached(id) if has else null
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	if not won:
		# 실패 — 돌려받은 카드 위에 어두운 띠 + `실패` (그림이 없으면 칸 가운데)
		var fail := Label.new()
		fail.name = "fail"
		fail.text = "실패"
		fail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fail.add_theme_font_size_override("font_size", 22 if has else 30)
		fail.add_theme_color_override("font_color", Color("#e8a39a") if has else DIM)
		fail.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
		fail.add_theme_constant_override("outline_size", 6)
		fail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if has:
			var band := StyleBoxFlat.new()
			band.bg_color = Color(0.05, 0.04, 0.04, 0.78)
			fail.add_theme_stylebox_override("normal", band)
			fail.position = Vector2(4, 4)
			fail.size = Vector2(ART.x, 34)
		else:
			fail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_child(fail)

	var label := Label.new()
	label.name = "name"
	label.text = str(info.get("name", "")) if has else "재료 %d장 소멸" % Trainers.fuse_cost()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20 if has else 16)
	label.add_theme_color_override("font_color", color.lightened(0.2) if has else DIM)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	label.add_theme_constant_override("outline_size", 6)
	label.position = Vector2(-30, ART.y + 16)
	label.size = Vector2(ART.x + 68, 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)
	_cards.append({"id": id, "holder": holder, "art": art})
	return holder

## 불길 셰이더 — 한 번 지어 카드들이 같이 쓴다 (매개변수만 카드마다)
static var _flame: Shader


static func _flame_shader() -> Shader:
	if _flame == null:
		_flame = Shader.new()
		_flame.code = FLAME_SHADER
	return _flame


## 트레이너 창이 3D 모델을 한 장 찍었다 — 빈 카드 그림을 채운다
func set_art(id: String, texture: Texture2D) -> void:
	for card in _cards:
		if str(card.id) == id:
			(card.art as TextureRect).texture = texture


## 카드들 — 테스트가 본다 (이름 `card_<id>` · `card_fail`)
func cards() -> Array:
	return _cards.map(func(c: Dictionary) -> Control: return c.holder)


func close_button() -> Button:
	return _close


## 튀어나오기를 건너뛰고 끝 상태로 (테스트 · 찍기)
func finish() -> void:
	_step(10.0)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_step(delta)


func _step(delta: float) -> void:
	_time += delta
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var k := clampf((_time - POP_GAP * float(i)) / POP_TIME, 0.0, 1.0)
		var holder: Control = card.holder
		holder.modulate.a = k
		holder.scale = Vector2.ONE * lerpf(POP_SCALE, 1.0, 1.0 - pow(1.0 - k, 3.0))
