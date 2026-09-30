class_name DamageFont
extends RefCounted

## 피해 숫자 전용 **이미지 폰트** — 게임 폰트에서 숫자만 뽑아 색·테두리·기울기를
## 그림에 **구워 둔** 비트맵 글꼴이다 (2026-09-30, 참고 그림을 받고 "데미지 텍스트가
## 이런 식으로 그라데이션 들어가고 이런 폰트 느낌이면 좋겠다").
##
## - 평타 `plain` — **흰 글씨 · 검은 테두리.** 채움이 흰색이라 `modulate` 로 물들이면
##   내가 맞음(빨강)·회복(초록)도 같은 글꼴로 쓴다 (검은 테두리는 곱해도 검다)
## - 치명타 `crit` — **연노랑 → 노랑 → 주황 → 붉은 주황** 세로 그라데이션 · 짙은 갈색
##   테두리. 색이 그림에 들어 있으므로 `modulate` 는 흰색으로 둔다
##
## **에셋이 아니다.** 게임 시작 때 한 번 코드로 굽는다 — 이펙트는 에셋을 안 받은
## 사람도 보여야 한다 (effect-rules.md). `Label3D` 는 글자에 그라데이션을 못 칠하므로
## (`material_override` 를 주면 글꼴 텍스처가 안 묶인다) 색을 글꼴 그림에 넣었다.
##
## 굽는 법: 원본 폰트를 복사해 **굵게(`EMBOLDEN`)·기울여(`SLANT`)** 두고, 텍스트 서버가
## 래스터한 글리프(채움 한 장 + 테두리 한 장)를 읽어 한 장의 아틀라스에 겹쳐 칠한다.
## 그 아틀라스로 고도의 이미지 폰트 가져오기(`ResourceImporterImageFont`)와 같은
## 방식의 `FontFile` 을 만든다.

## 구울 글자. 피해·치명타 `!`·회복 `+`
const CHARS := "0123456789+!-"
## 구울 글자 크기(px). `Label3D.font_size` 도 이것을 쓴다
const SIZE := 64
## 테두리 굵기(텍스트 서버 외곽선 크기)
const OUTLINE := 22
## 굵게. 참고 그림의 숫자는 획이 뭉툭하다
const EMBOLDEN := 0.9
## 기울기 — 윗부분이 오른쪽으로 이만큼(글자 높이 대비) 넘어간다
const SLANT := 0.18
## 글자 간격. 참고 그림처럼 테두리가 겹쳐 붙게 조금 좁힌다
const TIGHT := 0.86

## 평타 — 위는 흰색, 아래로 아주 조금 가라앉는다 (입체감만)
const PLAIN_STOPS := [[0.0, Color("#ffffff")], [0.6, Color("#ffffff")], [1.0, Color("#d8d8d8")]]
const PLAIN_EDGE := Color("#000000")
## 치명타 — 참고 그림에서 딴 색
const CRIT_STOPS := [
	[0.0, Color("#fffbd2")],
	[0.22, Color("#fff04a")],
	[0.55, Color("#ffc42a")],
	[0.8, Color("#ff8a1a")],
	[1.0, Color("#e2500c")],
]
const CRIT_EDGE := Color("#2c0c00")

static var _plain: FontFile
static var _crit: FontFile


## 평타 글꼴. `source` 는 게임 폰트 (없으면 엔진 기본 폰트)
static func plain(source: Font) -> FontFile:
	if _plain == null:
		_plain = _bake(source, PLAIN_STOPS, PLAIN_EDGE)
	return _plain


## 치명타 글꼴
static func crit(source: Font) -> FontFile:
	if _crit == null:
		_crit = _bake(source, CRIT_STOPS, CRIT_EDGE)
	return _crit


static func _bake(source: Font, stops: Array, edge: Color) -> FontFile:
	var src := _copy(source)
	var fill_size := Vector2i(SIZE, 0)
	var edge_size := Vector2i(SIZE, OUTLINE)
	var ascent := src.get_ascent(SIZE)
	var descent := src.get_descent(SIZE)
	# 테두리·기울기로 글자 칸 밖으로 넘치는 만큼 칸에 여백을 둔다
	var pad := OUTLINE + int(ceil(SIZE * SLANT))
	var cell_h := int(ceil(ascent + descent)) + pad * 2
	var base := pad + int(ceil(ascent))

	# 그라데이션은 **글자마다가 아니라 줄 전체에** 건다 — '0' 의 위아래를 잣대로
	# 삼아야 1 과 7 의 색이 같은 높이에서 같다
	var zero := src.get_glyph_index(SIZE, "0".unicode_at(0), 0)
	src.render_glyph(0, fill_size, zero)
	var top := base + src.get_glyph_offset(0, fill_size, zero).y
	var bottom := top + src.get_glyph_size(0, fill_size, zero).y

	var cells: Array = []
	var width := 0
	for i in CHARS.length():
		var code := CHARS.unicode_at(i)
		var glyph := src.get_glyph_index(SIZE, code, 0)
		src.render_glyph(0, fill_size, glyph)
		src.render_glyph(0, edge_size, glyph)
		var advance := src.get_glyph_advance(0, SIZE, glyph).x
		var cell_w := int(ceil(advance)) + pad * 2
		var cell := Image.create(cell_w, cell_h, false, Image.FORMAT_RGBA8)
		_paint(cell, src, edge_size, glyph, Vector2i(pad, base), func(_y: int) -> Color: return edge)
		_paint(cell, src, fill_size, glyph, Vector2i(pad, base),
			func(y: int) -> Color: return _gradient(stops, (float(y) - top) / maxf(1.0, bottom - top)))
		cells.append({"code": code, "image": cell, "advance": advance, "x": width})
		width += cell_w

	var atlas := Image.create(width, cell_h, false, Image.FORMAT_RGBA8)
	for c in cells:
		var image: Image = c.image
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(c.x, 0))

	var font := FontFile.new()
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	font.allow_system_fallback = false
	font.fixed_size = SIZE
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var key := Vector2i(SIZE, 0)
	font.set_texture_image(0, key, 0, atlas)
	for c in cells:
		var image: Image = c.image
		var code: int = c.code
		font.set_glyph_advance(0, SIZE, code, Vector2(float(c.advance) * TIGHT, 0.0))
		font.set_glyph_offset(0, key, code, Vector2(-pad, -base))
		font.set_glyph_size(0, key, code, Vector2(image.get_size()))
		font.set_glyph_uv_rect(0, key, code, Rect2(Vector2(c.x, 0), Vector2(image.get_size())))
		font.set_glyph_texture_idx(0, key, code, 0)
	font.set_cache_ascent(0, SIZE, ascent)
	font.set_cache_descent(0, SIZE, descent)
	return font


## 원본 폰트를 복사해 굵게·기울여 둔다. **원본을 건드리면 UI 글자가 전부 기운다**
static func _copy(source: Font) -> FontFile:
	var data := PackedByteArray()
	if source is FontFile:
		data = (source as FontFile).data
	if data.is_empty() and ThemeDB.fallback_font is FontFile:
		data = (ThemeDB.fallback_font as FontFile).data
	var font := FontFile.new()
	font.data = data
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.multichannel_signed_distance_field = false
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.set_embolden(0, EMBOLDEN)
	font.set_transform(0, Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO))
	return font


## 글리프 한 장을 `cell` 에 덮어 칠한다. 글리프는 알파(덮인 정도)만 쓰고 색은 `tint(y)` 다
static func _paint(cell: Image, src: FontFile, size: Vector2i, glyph: int, pen: Vector2i, tint: Callable) -> void:
	var rect := src.get_glyph_uv_rect(0, size, glyph)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var sheet := src.get_texture_image(0, size, src.get_glyph_texture_idx(0, size, glyph))
	var at := pen + Vector2i(src.get_glyph_offset(0, size, glyph).round())
	var from := Vector2i(rect.position)
	for y in int(rect.size.y):
		var cy := at.y + y
		if cy < 0 or cy >= cell.get_height():
			continue
		var color: Color = tint.call(cy)
		for x in int(rect.size.x):
			var cx := at.x + x
			if cx < 0 or cx >= cell.get_width():
				continue
			var a := sheet.get_pixel(from.x + x, from.y + y).a
			if a <= 0.0:
				continue
			var under := cell.get_pixel(cx, cy)
			# 위에 얹는다(over) — 채움이 테두리를 덮는다
			var out_a := a + under.a * (1.0 - a)
			var mixed := (Color(color.r, color.g, color.b) * a + Color(under.r, under.g, under.b) * under.a * (1.0 - a)) / out_a
			cell.set_pixel(cx, cy, Color(mixed.r, mixed.g, mixed.b, out_a))


static func _gradient(stops: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	for i in range(1, stops.size()):
		if t <= float(stops[i][0]):
			var a: float = stops[i - 1][0]
			var b: float = stops[i][0]
			return (stops[i - 1][1] as Color).lerp(stops[i][1], (t - a) / maxf(0.0001, b - a))
	return stops[stops.size() - 1][1]
