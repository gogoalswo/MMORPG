class_name EnhanceFx
extends Control

## 강화 칸 연출 — 강화 팝업(`EnhancePopup`)이 칸 위에 얹는다
## (2026-09-24 요청: "자동강화 할 때 1초마다 장비별로 슬라이드로 올라가는 연출 넣어.
## 성공한 건 반짝이는 이펙트 넣고 실패한 건 x자리 깨지는 연출 넣어").
##
##   slide   — 칸의 `+N` 이 위로 밀려 사라지고 `+N+1` 이 아래에서 올라와 앉는다 (칸 안으로 잘린다)
##   sparkle — 성공. 금빛 글로우가 부풀었다 가라앉고, 네 갈래 별빛 다섯이 차례로 반짝이고,
##             칸 테가 한 번 번쩍인다. 빛이라 **가산** 혼합
##   shatter — 실패. 붉은 X 가 두 획으로 그어지고(0.18초), 아이콘이 쐐기 조각으로 갈라져
##             튀어 올랐다 떨어지며 흐려진다. 조각은 아이콘 그림을 그대로 잘라 그린다
##   cross   — 깨진 칸에 남는 흐린 X (칸의 자식으로 붙어 칸을 따라간다, 사라지지 않는다)
##
## 그림 파일 없이 코드로 그린다 — 이펙트 규칙 1절(에셋을 안 받은 사람도 보여야 한다).
## 시간은 `_process` 의 delta 라 `Engine.time_scale` 을 따른다 (찍을 때 늦출 수 있다).
## → docs/features/effect-rules.md · docs/features/items.md "강화"

const SLIDE_TIME := 0.38
const SPARKLE_TIME := 0.75
const CROSS_TIME := 0.2
const SHATTER_TIME := 0.8
const RED := Color("#e0453a")
const GOLD := Color("#ffd98a")
## 조각 수 — 칸이 작아서 여덟이면 "깨졌다" 로 읽히고, 더 많으면 가루가 된다
const PIECES := 8
const GRAVITY := 900.0

var kind := ""
var _t := 0.0
var _life := 1.0
# slide
var _from := ""
var _to := ""
var _font: Font
var _font_size := 15
var _ink := Color.WHITE
var _badge: CanvasItem
# sparkle
var _stars: Array = []
# shatter
var _texture: Texture2D
var _icon_rect := Rect2()
var _pieces: Array = []


## 숫자 슬라이드 — `badge` 는 칸의 배지 글자. 도는 동안 감춰 두고 끝나면 다시 켠다
static func slide(layer: Control, badge: Label, from_text: String, to_text: String) -> EnhanceFx:
	var fx := _make(layer, "slide", _local_rect(layer, badge), SLIDE_TIME)
	fx.clip_contents = true
	fx._from = from_text
	fx._to = to_text
	fx._font = badge.get_theme_font("font")
	fx._font_size = badge.get_theme_font_size("font_size")
	fx._ink = badge.get_theme_color("font_color")
	fx._badge = badge
	badge.modulate.a = 0.0
	return fx


static func sparkle(layer: Control, cell: Control) -> EnhanceFx:
	var fx := _make(layer, "sparkle", _local_rect(layer, cell), SPARKLE_TIME)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx.material = mat
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := fx.size
	for i in 4:
		fx._stars.append({
			"pos": Vector2(rng.randf_range(0.12, 0.88) * s.x, rng.randf_range(0.1, 0.8) * s.y),
			"delay": 0.08 * i + rng.randf_range(0.0, 0.05),
			"size": rng.randf_range(0.26, 0.38) * s.x,
			"spin": rng.randf_range(-0.6, 0.6),
		})
	return fx


## 깨짐 — `texture` · `icon_rect` 는 깨지기 **전** 아이콘 (칸은 이미 비었을 수 있다)
static func shatter(layer: Control, cell: Control, texture: Texture2D, icon_rect: Rect2) -> EnhanceFx:
	var fx := _make(layer, "shatter", _local_rect(layer, cell), CROSS_TIME + SHATTER_TIME)
	fx._texture = texture
	fx._icon_rect = Rect2(icon_rect.position - cell.get_global_rect().position, icon_rect.size)
	fx._cut()
	return fx


## 깨진 칸에 남는 흐린 X — 칸의 자식이라 칸이 움직여도 따라간다
static func cross(cell: Control) -> EnhanceFx:
	var fx := EnhanceFx.new()
	fx.name = "broken"
	fx.kind = "cross"
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(fx)
	return fx


static func _make(layer: Control, what: String, rect: Rect2, life: float) -> EnhanceFx:
	var fx := EnhanceFx.new()
	fx.kind = what
	fx._life = life
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.position = rect.position
	fx.size = rect.size
	layer.add_child(fx)
	return fx


static func _local_rect(layer: Control, node: Control) -> Rect2:
	var box := node.get_global_rect()
	return Rect2(box.position - layer.get_global_rect().position, box.size)


func _process(delta: float) -> void:
	if kind == "cross":
		return
	_t += delta
	if kind == "shatter" and _t > CROSS_TIME:
		for piece in _pieces:
			piece.vel.y += GRAVITY * delta
			piece.at += piece.vel * delta
			piece.angle += piece.spin * delta
	if _t >= _life:
		if kind == "slide" and is_instance_valid(_badge):
			_badge.modulate.a = 1.0
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	match kind:
		"slide": _draw_slide()
		"sparkle": _draw_sparkle()
		"shatter": _draw_shatter()
		"cross": _draw_cross(0.55, 3.0, 1.0)


## 옛 숫자는 위로 한 줄 밀려 흐려지고, 새 숫자는 아래 한 줄에서 올라온다 (끝이 느린 곡선)
func _draw_slide() -> void:
	var k := ease(clampf(_t / SLIDE_TIME, 0.0, 1.0), 0.35)
	var rise := float(_font_size) * 1.25
	_badge_text(_from, -rise * k, 1.0 - k)
	_badge_text(_to, rise * (1.0 - k), k)


## 칸 배지와 같은 자리(오른쪽 아래) · 같은 글꼴 · 검은 윤곽
func _badge_text(text: String, lift: float, alpha: float) -> void:
	if text == "" or alpha <= 0.0:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	var at := Vector2(size.x - width, size.y - _font.get_descent(_font_size) + lift)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, 4, Color(0, 0, 0, alpha))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(_ink, alpha))


func _draw_sparkle() -> void:
	var k := _t / SPARKLE_TIME
	var mid := size * 0.5
	# 글로우 — 빨리 부풀고 천천히 가라앉는다
	var glow := sin(PI * pow(k, 0.45))
	var radius := size.x * (0.55 + 0.35 * k)
	draw_texture_rect(
		FxTex.glow(), Rect2(mid - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, Color(GOLD, 0.75 * glow)
	)
	# 칸 테 섬광 — 처음 0.3초
	var edge := clampf(1.0 - _t / 0.3, 0.0, 1.0)
	if edge > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size).grow(1.0), Color(GOLD, edge), false, 2.0)
	# 네 갈래 별빛 — 차례로 켜졌다 꺼진다
	for star in _stars:
		var local := (_t - float(star.delay)) / 0.4
		if local <= 0.0 or local >= 1.0:
			continue
		var r := float(star.size) * sin(PI * local)
		_star(star.pos, r, float(star.spin) * local, Color(1.0, 0.85, 0.5, 0.9))


## 네 갈래 별 — 가는 십자 두 겹(긴 것 + 45° 짧은 것)
func _star(at: Vector2, r: float, turn: float, tint: Color) -> void:
	for layer in 2:
		var long := r if layer == 0 else r * 0.45
		var waist := long * 0.16
		var points := PackedVector2Array()
		for i in 8:
			var angle := turn + PI * 0.25 * i + (PI * 0.25 if layer == 1 else 0.0)
			var reach := long if i % 2 == 0 else waist
			points.append(at + Vector2(cos(angle), sin(angle)) * reach)
		draw_colored_polygon(points, tint)


## 붉은 X 두 획 → 조각이 흩어진다. X 는 조각이 날기 시작하면 빠르게 흐려진다
func _draw_shatter() -> void:
	if _t < CROSS_TIME:
		if _texture != null:
			draw_texture_rect(_texture, _icon_rect, false)
		_draw_cross(1.0, 5.0, _t / CROSS_TIME)
		return
	var k := (_t - CROSS_TIME) / SHATTER_TIME
	var fade := clampf(1.0 - (k - 0.45) / 0.55, 0.0, 1.0)
	# 깨지는 순간 칸이 붉게 한 번 번쩍인다 (0.15초)
	var flash := clampf(1.0 - (_t - CROSS_TIME) / 0.15, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(RED, 0.45 * flash))
	for piece in _pieces:
		var xform := Transform2D(piece.angle, piece.at)
		var points := PackedVector2Array()
		for p in piece.poly:
			points.append(xform * p)
		# 조각은 아이콘 그림 그대로, 떨어질수록 어두워진다. 테를 두르면 붉은 색종이처럼 보였다
		var dark := lerpf(0.9, 0.45, k)
		if _texture != null:
			draw_colored_polygon(points, Color(dark, dark * 0.82, dark * 0.78, fade), piece.uv, _texture)
		else:
			draw_colored_polygon(points, Color(0.5, 0.45, 0.4, fade))
	_draw_cross(clampf(1.0 - k * 3.0, 0.0, 1.0), 5.0, 1.0)


## X — `grow` 가 0→1 이면 첫 획, 그다음 둘째 획이 그어진다. 어두운 밑줄을 먼저 깐다
func _draw_cross(alpha: float, width: float, grow: float) -> void:
	if alpha <= 0.0:
		return
	var pad := size * 0.2
	var strokes := [
		[pad, size - pad],
		[Vector2(size.x - pad.x, pad.y), Vector2(pad.x, size.y - pad.y)],
	]
	for i in 2:
		var k := clampf(grow * 2.0 - i, 0.0, 1.0)
		if k <= 0.0:
			continue
		var a: Vector2 = strokes[i][0]
		var b: Vector2 = a.lerp(strokes[i][1], k)
		draw_line(a, b, Color(0, 0, 0, 0.6 * alpha), width + 3.0, true)
		draw_line(a, b, Color(RED, alpha), width, true)


## 아이콘 칸을 쐐기 조각으로 자른다 — 가운데 근처 한 점에서 테두리로 금을 긋고,
## 이웃한 금 사이(와 그 사이 모서리)를 한 조각으로. 조각은 제 무게중심 기준으로 두고
## 밖으로 튀어 오르며(위로 조금 더) 돈다
func _cut() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var box := _icon_rect if _icon_rect.size.x > 0.0 else Rect2(Vector2.ZERO, size)
	var mid := box.get_center() + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)) * box.size
	var angles: Array = []
	for i in PIECES:
		angles.append(TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / PIECES)
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in PIECES:
		var a0: float = angles[i]
		var a1: float = angles[(i + 1) % PIECES] + (TAU if i == PIECES - 1 else 0.0)
		var poly := PackedVector2Array([mid, _ray(box, mid, a0)])
		for corner in corners:
			var ca := fposmod((corner - mid).angle() - a0, TAU) + a0
			if ca > a0 and ca < a1:
				poly.append(corner)
		poly.append(_ray(box, mid, a1))
		# 모서리를 각도 순으로 — 위에서 corners 순서대로 넣었으니 다시 줄 세운다
		var inner := Array(poly.slice(1))
		inner.sort_custom(func(p: Vector2, q: Vector2) -> bool:
			return fposmod((p - mid).angle() - a0 + 0.0001, TAU) < fposmod((q - mid).angle() - a0 + 0.0001, TAU))
		poly = PackedVector2Array([mid] + inner)
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= poly.size()
		var local := PackedVector2Array()
		var uv := PackedVector2Array()
		for p in poly:
			local.append(p - center)
			uv.append((p - box.position) / box.size)
		var out := (center - mid).normalized()
		_pieces.append({
			"poly": local, "uv": uv, "at": center, "angle": 0.0,
			"vel": out * rng.randf_range(35.0, 80.0) + Vector2(0.0, -rng.randf_range(60.0, 110.0)),
			"spin": rng.randf_range(-4.0, 4.0),
		})


## mid 에서 angle 쪽으로 쏜 선이 상자 테두리와 만나는 점
func _ray(box: Rect2, from: Vector2, angle: float) -> Vector2:
	var dir := Vector2(cos(angle), sin(angle))
	var best := INF
	if absf(dir.x) > 0.0001:
		for x in [box.position.x, box.end.x]:
			var t: float = (x - from.x) / dir.x
			if t > 0.0:
				best = minf(best, t)
	if absf(dir.y) > 0.0001:
		for y in [box.position.y, box.end.y]:
			var t: float = (y - from.y) / dir.y
			if t > 0.0:
				best = minf(best, t)
	return from + dir * best
