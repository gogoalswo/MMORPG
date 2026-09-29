class_name Terrain
extends RefCounted

## 존 지형 — **높낮이** 와 **바닥 여러 장을 섞은 것** 을 한 장의 메시로 깐다.
## **장애물은 없다** (2026-09-26 지시: "맵 장애물은 넣지말고 지형 만들어 봐").
## 나무·바위·건물처럼 길을 막는 것은 하나도 없고, 높낮이는 그리기만 한다 —
## 판정(`World`)은 여전히 평면(x, z)에서 돈다.
##
## 지형이 있는 존은 `RECIPES` 에 적힌 곳뿐이고(마을 · 덤불숲), 나머지는 예전처럼
## 평평한 바닥 한 장(`Ground`)이다. 규칙과 수치의 이유는
## docs/features/world-zones.md 의 "지형" 절에 있다.

## 메시 격자 간격(m). 1m 면 완만한 굴곡에는 충분하다
const STEP := 1.0
## 메시 반경(m). 맵(66 → 반경 33)보다 넓게 깔아 **바깥 언덕이 마을을 감싼다** —
## 맵 끝에서 바닥이 끊겨 하늘색이 비치지 않게
const HALF := 64
## 바닥 섞기 그림이 덮는 반경(m)과 해상도(1m 에 몇 칸). 그 밖은 전부 풀이다
const SPLAT_HALF := 40.0
const SPLAT_RES := 3

## 층 순서 = 섞기 그림의 채널 순서. 0 번(풀)은 나머지를 채운다
const LAYERS := ["grass", "stone", "cobble", "dirt"]

## 존별 지형. 좌표는 판정과 같은 (x, z) 미터다.
## - `plaza`   : 가운데 돌판 광장 반지름. NPC 가 여기 선다 — 맵을 반(33)으로 줄이며
##               (2026-09-28) 문이 (-9, -9)로 가서 11 → 12 로 넓혔다. 같은 날 맵을 다시
##               66 으로 키워 문이 (-18, -18)로 나가서, 문 자리는 광장 대신 `flats` 로 누른다
## - `roads`   : 자갈길 — 꺾은선. 광장 안에서 시작해 언덕으로 사라진다
## - `road_w`  : 자갈길 반폭
## - `bumps`   : 걸어 다니는 땅의 굴곡 높이(±m). 광장은 평평하게 눌러 둔다
## - `rim`     : 이 거리(맵 가운데서 x·z 중 큰 쪽)부터 언덕이 솟는다 — 이동 끝(±29)과 같다
## - `rim_top` : 메시 끝(64)에서의 언덕 높이
## 아래는 없어도 된다
## - `road_layer`: 길을 칠할 층 — `"cobble"`(기본, 자갈길) · `"dirt"`(숲의 흙길)
## - `flats`   : [x, z, 반지름] — 굴곡을 눌러 평평하게 둘 자리 (차원문·도착 지점)
## - `patch`   : 군데군데 맨땅의 양 (기본 0.85)
## - `shade`   : 풀빛 얼룩 세기 (0~1). 이끼 낀 어두운 데와 볕 든 연두 데가 섞인다 —
##               풀 한 장이 넓게 깔리면 밋밋해서, 숲 바닥의 얼룩덜룩함을 준다
## - `looks`   : {층: [목표색, 밝기 배율]} — 존 색 대신 이 층을 이 색으로 끌어당긴다
## - `layers`  : 층 넷 (기본 `LAYERS`). 0 번이 나머지를 채우는 바닥이다
## - `void`    : true 면 이동 끝(`rim`) 너머 바닥을 **검게** 칠한다 — 갈 수 없는 곳은 땅이 아니다
const RECIPES := {
	"village": {
		"plaza": 12.0,
		"roads": [
			[[1, 8], [3, 17], [0, 25], [2, 38]],
			[[8, -1], [17, 1], [25, -2], [38, 0]],
			[[-1, -8], [-3, -17], [0, -25], [-2, -38]],
			[[-8, 1], [-17, 3], [-25, 0], [-38, 2]],
		],
		"road_w": 1.7,
		"bumps": 0.7,
		"rim": 29.0,
		# 이동 끝부터는 검은 바닥 — 덤불숲과 같다 (2026-09-28 "사냥터와 동일하게 마을에서도
		# 이동할 수 없는 영역은 어둡게"). 맵을 반(33)으로 줄인 뒤에도 언덕·길이 옛 크기(±38)로
		# 뻗어 있어 걸을 수 있는 땅과 그림이 안 맞았다. 길은 끝에서 검은 바닥에 잘린다.
		# 같은 날 맵을 다시 66(±29)으로 키웠다
		"rim_top": 0.0,
		"void": true,
		# 마을 차원문은 맵 한가운데(0, 0)라 광장(12) 안이다 — 따로 누를 자리가 없다 (2026-09-29)
		"flats": [],
	},
	# 덤불숲 — 2026-09-28 "제안하는 방식으로 맵 하나 만들어 봐" (참고 그림: 리니지풍
	# 어두운 숲 바닥). 광장 없이 흙길 하나가 차원문(-18, -18) → 도착 지점 → 무리
	# (16, 16)로 굽이치고, 한 갈래가 오른쪽 언덕으로 빠진다. 나무·바위·풀포기는 Scenery.
	# 맵을 66 으로 키우며(2026-09-28) 길 자리를 두 배로 늘렸다
	"thicket": {
		# 바닥은 **흙 한 장** (2026-09-29 "기존 바닥은 뭔가 바닥 느낌이 잘 안나. 스크린샷처럼") —
		# 리니지 흙바닥 스크린샷을 물려 바르코로 뽑은 `soil`. 풀·흙길·맨땅·풀빛 얼룩은 뺐다
		"layers": ["soil", "stone", "cobble", "dirt"],
		"plaza": 0.0,
		"roads": [],
		"road_layer": "dirt",
		"road_w": 0.9,
		"bumps": 0.55,
		"rim": 29.0,
		"rim_top": 0.0,
		"flats": [[-18, -18, 3.0], [0, 0, 2.0]],
		"patch": 0.0,
		"shade": 0.0,
		# 이동 끝부터는 검은 바닥 (2026-09-28 "해당 위치부터는 그냥 검은색으로 나와야 하는 것
		# 아니야?") — 끝 너머가 풀밭으로 이어져 있으니 누르면 끝으로 당겨지는 게 고장으로 보였다.
		# 그늘·턱으로 경계를 그어 봤는데 서서히 어두워져 선으로 안 읽혔다. 언덕도 없이 평평하게
		"void": true,
		"specular": 0.0,
		# 흙 밝기 — 기존 바닥 규칙(반사율 0.3배)으로는 이 존의 어두운 조명에서 거의 검다.
		# 화면이 참고 스크린샷(평균 #261b14)과 같아지게 재서 맞춘 배율
		"looks": {"soil": ["#1e1d1c", 28.0]},
		# 무늬 대비는 원본 그대로 — 1.4 제곱이면 흙의 밝은 티만 튀어 반짝이 가루가 된다
		"contrast": 1.0,
	},
}

## 존마다 한 번만 짓는다 — PC 에서 섞기 그림까지 0.26초라 폰에서는 마을을 드나들
## 때마다 멈칫한다. 지형은 존 id 로만 정해지므로 다시 지을 이유가 없다
static var _built := {}

var _n := 0
var _mesh_cache: ArrayMesh = null
var _splat_cache: ImageTexture = null
var _heights := PackedFloat32Array()
var _recipe: Dictionary = {}
## 섞기 그림 칸마다 가장 가까운 자갈길 가운데선까지의 거리(m)
var _road_dist := PackedFloat32Array()
var _splat_n := 0
var _noise := FastNoiseLite.new()


## 지형이 있는 존이면 지어서 돌려주고, 없으면 `null` — 평평한 바닥을 깐다
static func build(zone_id: String) -> Terrain:
	if not RECIPES.has(zone_id):
		return null
	if _built.has(zone_id):
		return _built[zone_id]
	var t := Terrain.new()
	t._recipe = RECIPES[zone_id]
	t._noise.seed = zone_id.hash()
	t._noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	t._noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	t._noise.fractal_octaves = 3
	t._noise.frequency = 1.0
	t._bake_roads()
	t._bake_heights()
	_built[zone_id] = t
	return t


## 발밑 높이. **메시와 같은 삼각형으로** 보간한다 — 다른 식으로 재면 칸 한가운데서
## 발이 몇 cm 뜨거나 묻힌다
func height_at(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / STEP, 0.0, _n - 1.001)
	var gz := clampf((z + HALF) / STEP, 0.0, _n - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var ha := _heights[j * _n + i]
	var hb := _heights[j * _n + i + 1]
	var hc := _heights[(j + 1) * _n + i]
	var hd := _heights[(j + 1) * _n + i + 1]
	if fx >= fz:
		return ha + (hb - ha) * fx + (hd - hb) * fz
	return ha + (hc - ha) * fz + (hd - hc) * fx


## 화면 광선이 땅에 닿는 곳. 평면(높이 0)에서 시작해 그 자리 높이의 평면으로
## 몇 번 다시 맞춘다 — 카메라가 42도로 내려다보고 걷는 땅의 기울기는 그보다
## 훨씬 완만해서 몇 번이면 수 cm 안으로 모인다
func ray_hit(from: Vector3, dir: Vector3) -> Vector3:
	var h := 0.0
	var hit = null
	for _k in 8:
		hit = Plane(Vector3.UP, h).intersects_ray(from, dir)
		if hit == null:
			return Vector3.INF
		var next := height_at(hit.x, hit.z)
		if absf(next - h) < 0.01:
			break
		h = next
	return hit


func mesh_instance(env: Dictionary) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	if _mesh_cache == null:
		_mesh_cache = _mesh()
		_splat_cache = _splat_texture()
	node.mesh = _mesh_cache
	node.material_override = Ground.terrain_material(env, _recipe.get("layers", LAYERS), _splat_cache, SPLAT_HALF, _recipe.get("looks", {}))
	if node.material_override is ShaderMaterial:
		if _recipe.get("void", false):
			node.material_override.set_shader_parameter("void_edge", float(_recipe.rim))
		node.material_override.set_shader_parameter("specular", float(_recipe.get("specular", 0.5)))
		if _recipe.has("contrast"):
			node.material_override.set_shader_parameter("contrast", float(_recipe.contrast))
	return node


# ─── 짓기 ──────────────────────────────────────────────────────────────


func _n01(x: float, z: float, scale: float, offset: float) -> float:
	return _noise.get_noise_2d(x / scale + offset, z / scale - offset)


## 자갈길 거리장. 칸마다 꺾은선 전부를 재면 느려서, 선분마다 **그 둘레 상자 안의
## 칸만** 잰다
func _bake_roads() -> void:
	_splat_n = int(SPLAT_HALF * 2.0 * SPLAT_RES)
	_road_dist.resize(_splat_n * _splat_n)
	_road_dist.fill(1e6)
	var reach := float(_recipe.road_w) + 4.0
	for road in _recipe.roads:
		for k in road.size() - 1:
			var a := Vector2(road[k][0], road[k][1])
			var b := Vector2(road[k + 1][0], road[k + 1][1])
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
			var i0 := maxi(0, int((lo.x + SPLAT_HALF) * SPLAT_RES))
			var i1 := mini(_splat_n - 1, int((hi.x + SPLAT_HALF) * SPLAT_RES))
			var j0 := maxi(0, int((lo.y + SPLAT_HALF) * SPLAT_RES))
			var j1 := mini(_splat_n - 1, int((hi.y + SPLAT_HALF) * SPLAT_RES))
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := _splat_world(i, j)
					var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					var at := j * _splat_n + i
					if d < _road_dist[at]:
						_road_dist[at] = d


func _splat_world(i: int, j: int) -> Vector2:
	return Vector2((i + 0.5) / SPLAT_RES - SPLAT_HALF, (j + 0.5) / SPLAT_RES - SPLAT_HALF)


func _road_dist_at(x: float, z: float) -> float:
	var i := int((x + SPLAT_HALF) * SPLAT_RES)
	var j := int((z + SPLAT_HALF) * SPLAT_RES)
	if i < 0 or j < 0 or i >= _splat_n or j >= _splat_n:
		return 1e6
	return _road_dist[j * _splat_n + i]


## 맵 가운데서 x·z 중 먼 쪽 거리 — 맵이 정사각이라 언덕도 네모나게 두른다
static func _edge(x: float, z: float) -> float:
	return maxf(absf(x), absf(z))


## 층 무게 (돌판, 자갈, 흙). 풀은 나머지다
func _weights(x: float, z: float) -> Vector3:
	var edge := _edge(x, z)
	# 언덕으로 올라가면 길도 흙도 풀 속으로 사라진다. 섞기 그림의 가장자리 칸은
	# 그림 밖으로 늘어나므로(clamp) 거기는 반드시 풀이어야 한다
	var fade := 1.0 - smoothstep(SPLAT_HALF - 9.0, SPLAT_HALF - 3.0, edge)

	var r := Vector2(x, z).length()
	var plaza_r := float(_recipe.plaza)
	var stone := 0.0
	if plaza_r > 0.0:
		stone = 1.0 - smoothstep(plaza_r - 0.8, plaza_r + 0.8, r + _n01(x, z, 4.0, 11.0) * 1.3)

	var w := float(_recipe.road_w)
	var d := _road_dist_at(x, z) + _n01(x, z, 2.5, 37.0) * 0.45
	var road := (1.0 - smoothstep(w - 0.35, w + 0.35, d)) * (1.0 - stone) * fade
	var dirt_road := str(_recipe.get("road_layer", "cobble")) == "dirt"
	var cobble := 0.0 if dirt_road else road

	# 흙 — 길섶(밟혀서 풀이 벗겨진 곳), 광장 둘레, 그리고 군데군데 맨땅
	var shoulder := 1.0 - smoothstep(w + 0.4, w + 2.2, d + _n01(x, z, 3.0, 53.0) * 0.9)
	var ring := 0.0
	if plaza_r > 0.0:
		ring = 1.0 - smoothstep(plaza_r + 0.5, plaza_r + 3.5, r + _n01(x, z, 3.0, 71.0) * 1.5)
	var patch := smoothstep(0.28, 0.5, _n01(x, z, 9.0, 97.0))
	var dirt := maxf(maxf(shoulder * (0.55 if dirt_road else 1.0), ring), patch * float(_recipe.get("patch", 0.85)))
	if dirt_road:
		dirt = maxf(dirt, road)
	dirt = clampf(dirt, 0.0, 1.0) * (1.0 - stone - cobble) * fade
	return Vector3(stone, cobble, maxf(dirt, 0.0))


## 풀빛 얼룩 (0.5 = 그대로, 0 = 이끼 낀 그늘, 1 = 볕 든 연두). 섞기 그림의 알파에 굽는다
func _shade(x: float, z: float) -> float:
	var amount := float(_recipe.get("shade", 0.0))
	if amount <= 0.0:
		return 0.5
	var big := _n01(x, z, 7.0, 211.0)
	var small := _n01(x, z, 2.2, 257.0)
	return clampf(0.5 + (big * 0.75 + small * 0.35) * amount, 0.0, 1.0)


## 이 자리의 바닥 섞기 (돌판, 자갈, 흙). 풀은 나머지 — 풀포기·돌을 흩뿌릴 때 본다
func ground_mix(x: float, z: float) -> Vector3:
	return _weights(x, z)


## 가장 가까운 길 가운데선까지(m)
func road_distance(x: float, z: float) -> float:
	return _road_dist_at(x, z)


func _splat_texture() -> ImageTexture:
	var img := Image.create(_splat_n, _splat_n, false, Image.FORMAT_RGBA8)
	for j in _splat_n:
		for i in _splat_n:
			var p := _splat_world(i, j)
			var w := _weights(p.x, p.y)
			img.set_pixel(i, j, Color(w.x, w.y, w.z, _shade(p.x, p.y)))
	return ImageTexture.create_from_image(img)


func _bake_heights() -> void:
	_n = int(HALF * 2 / STEP) + 1
	_heights.resize(_n * _n)
	var plaza_r := float(_recipe.plaza)
	var rim := float(_recipe.rim)
	var rim_top := float(_recipe.rim_top)
	var bumps := float(_recipe.bumps)
	var w := float(_recipe.road_w)
	for j in _n:
		for i in _n:
			var x := i * STEP - HALF
			var z := j * STEP - HALF
			# 걸어 다니는 땅 — 완만한 굴곡. 광장은 평평하게, 길은 반쯤 눌러 둔다
			var h := _n01(x, z, 16.0, 0.0) * bumps
			if plaza_r > 0.0:
				h *= smoothstep(plaza_r + 1.0, plaza_r + 7.0, Vector2(x, z).length())
			for f in _recipe.get("flats", []):
				var fr := float(f[2])
				h *= smoothstep(fr, fr + 4.0, Vector2(x - float(f[0]), z - float(f[1])).length())
			h *= lerpf(0.4, 1.0, smoothstep(w, w + 3.0, _road_dist_at(x, z)))
			# 바깥 언덕 — 이동 끝에서 0 으로 시작해 점점 가팔라진다. 가장 가파른 곳도
			# 카메라 시선(42도)보다 한참 눕혀 둬서, 끝에 선 캐릭터를 가리지 않는다
			var e := maxf(0.0, _edge(x, z) - rim)
			if e > 0.0:
				var t := e / (HALF - rim)
				h += rim_top * pow(t, 1.6)
				h += _n01(x, z, 14.0, 131.0) * minf(e, 8.0) * 0.12
			_heights[j * _n + i] = h


func _mesh() -> ArrayMesh:
	var count := _n * _n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	tangents.resize(count * 4)
	uvs.resize(count)
	for j in _n:
		for i in _n:
			var at := j * _n + i
			var x := i * STEP - HALF
			var z := j * STEP - HALF
			verts[at] = Vector3(x, _heights[at], z)
			# UV 는 월드 미터 그대로 — 층마다 타일 크기로 나누는 건 셰이더가 한다
			uvs[at] = Vector2(x, z)
			var dx := _h(i + 1, j) - _h(i - 1, j)
			var dz := _h(i, j + 1) - _h(i, j - 1)
			var n := Vector3(-dx, 2.0 * STEP, -dz).normalized()
			normals[at] = n
			# 탄젠트는 UV 의 u(= +x) 쪽. PlaneMesh·SurfaceTool 과 같은 규약(w = 1)
			var t := Vector3(2.0 * STEP, dx, 0.0)
			t = (t - n * n.dot(t)).normalized()
			tangents[at * 4] = t.x
			tangents[at * 4 + 1] = t.y
			tangents[at * 4 + 2] = t.z
			tangents[at * 4 + 3] = 1.0

	# 고도의 앞면은 시계 방향이다. 위에서 보면 +z 가 화면 아래라 (a, b, d)·(a, d, c)
	var indices := PackedInt32Array()
	indices.resize((_n - 1) * (_n - 1) * 6)
	var k := 0
	for j in _n - 1:
		for i in _n - 1:
			var a := j * _n + i
			var b := a + 1
			var c := a + _n
			var d := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = d
			indices[k + 3] = a
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _h(i: int, j: int) -> float:
	return _heights[clampi(j, 0, _n - 1) * _n + clampi(i, 0, _n - 1)]
