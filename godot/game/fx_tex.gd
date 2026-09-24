class_name FxTex
extends RefCounted

## 이펙트용 텍스처를 **런타임에 굽는다.** 파일로 받아 두지 않는다.
##
## 규칙 문서(1절)가 "MIX(알파) 혼합이 필요한 원형·링은 런타임에 `_alpha_tex()` 가
## 만든다" 고 한 자리다 — 이 저장소는 `assets/fx/` 흑백 이미지가 없으므로
## **전부** 여기서 굽는다 (2026-09-18: "텍스쳐 바르코든 고도엔진이든 직접
## 만들면 되잖아?"). 에셋을 안 받은 사람도 보이고, `index.pck` 이 안 늘어나고,
## 크기·감쇠가 상수라 고쳐서 바로 확인할 수 있다
## → [effect-rules.md](../../docs/features/effect-rules.md)
##
## **한 번 구우면 캐시에 남는다.** 같은 낙뢰가 세 번 쳐도 굽는 것은 한 번이다.

static var _cache: Dictionary = {}


## 가운데가 희고 가장자리로 갈수록 사라지는 **방사형 글로우.**
## 섬광에 쓴다 — 저해상도 구를 여럿 띄우면 화면에서 육각형 덩어리가 된다
static func glow(size := 96) -> ImageTexture:
	var key := "glow_%d" % size
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - mid, float(y) - mid).length() / mid
			# 가운데는 오래 밝고 바깥은 빨리 죈다 — 선형이면 테두리가 보인다
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.4)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 가로(U)로 **가운데가 진하고 양끝이 사라지는 띠.** 리본의 폭 방향에 쓴다 —
## 폭 전체를 같은 알파로 채우면 양쪽에 또렷한 선이 생겨 테두리가 된다
static func streak(size := 64) -> ImageTexture:
	var key := "streak_%d" % size
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, 4, false, Image.FORMAT_RGBA8)
	for x in size:
		var t := absf(float(x) / float(size - 1) * 2.0 - 1.0)
		var a := pow(clampf(1.0 - t, 0.0, 1.0), 1.7)
		for y in 4:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## **불규칙한 얼룩.** 지면 그을림에 쓴다 — 동그란 원을 깔면 고리로 보이고,
## 규칙(3절)이 "퍼지는 동그란 충격 파동 고리는 쓰지 않는다" 고 했다
static func scorch(size := 128) -> ImageTexture:
	var key := "scorch_%d" % size
	if _cache.has(key):
		return _cache[key]

	# 각도마다 반지름을 흔들어 둔다 — 원이 아니라 얼룩이 되는 자리다
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260918
	# **판 모서리에 닿으면 안 된다** — 얼룩이 잘려 사각형으로 보인다
	# (2026-09-18 캡처). 가장 긴 갈래도 판 반지름의 0.8 에서 멈춘다
	var lobes := 16
	var edge: Array[float] = []
	for i in lobes:
		edge.append(rng.randf_range(0.45, 0.8))

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var away := Vector2(float(x) - mid, float(y) - mid)
			var d := away.length() / mid
			var turn := (atan2(away.y, away.x) + PI) / TAU * float(lobes)
			var i0 := int(floor(turn)) % lobes
			var i1 := (i0 + 1) % lobes
			# 이웃한 두 반지름을 부드럽게 잇는다 — 안 그러면 톱니가 보인다
			var reach: float = lerpf(edge[i0], edge[i1], smoothstep(0.0, 1.0, turn - floor(turn)))
			var a := pow(clampf(1.0 - d / reach, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## **웅덩이.** 안쪽은 **고르게 불투명**하고 가장자리만 울퉁불퉁 부드럽게 끊긴다.
## `scorch` 는 가운데로 갈수록 진해지는 얼룩이라(평균 알파 0.04) 웅덩이로 깔면
## **발밑 한 점만 남아 안 보였다** (2026-09-24, 천붕각 균열 지대 진흙)
static func pool(size := 128) -> ImageTexture:
	var key := "pool_%d" % size
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var lobes := 12
	var edge: Array[float] = []
	for i in lobes:
		# 판 모서리에 닿지 않게 0.9 에서 멈춘다 (scorch 와 같은 이유)
		edge.append(rng.randf_range(0.72, 0.9))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var away := Vector2(float(x) - mid, float(y) - mid)
			var d := away.length() / mid
			var turn := (atan2(away.y, away.x) + PI) / TAU * float(lobes)
			var i0 := int(floor(turn)) % lobes
			var i1 := (i0 + 1) % lobes
			var reach: float = lerpf(edge[i0], edge[i1], smoothstep(0.0, 1.0, turn - floor(turn)))
			var a := 1.0 - smoothstep(reach - 0.12, reach, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## **흙먼지 뭉치.** 가운데가 넓게 고르고 가장자리가 울퉁불퉁 흐려진다.
## `glow` 로 먼지를 띄웠더니 가운데만 진한 점이라 **물방울무늬**가 됐다
## (2026-09-23 천붕각 캡처) — 먼지는 겹쳐서 한 덩어리 구름이 되어야 한다.
## 안쪽도 잡음으로 얼룩지게 해서, 여럿이 겹쳐도 찍어낸 것으로 안 보인다
static func puff(size := 96) -> ImageTexture:
	var key := "puff_%d" % size
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 20260923
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - mid, float(y) - mid).length() / mid
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# 가장자리를 잡음으로 들쭉날쭉하게 — 둥근 원이면 동전이다
			var edge := 1.0 - smoothstep(0.35 + n * 0.3, 1.0, d)
			var a := edge * lerpf(0.55, 1.0, n)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
