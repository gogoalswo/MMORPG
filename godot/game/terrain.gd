class_name Terrain
extends RefCounted

## 존 지형 — **높낮이** 와 **바닥 여러 장을 섞은 것** 을 한 장의 메시로 깐다.
## **장애물은 없다** (2026-09-26 지시: "맵 장애물은 넣지말고 지형 만들어 봐").
## 나무·바위·건물처럼 길을 막는 것은 하나도 없고, 높낮이는 그리기만 한다 —
## 판정(`World`)은 여전히 평면(x, z)에서 돈다.
##
## 지형이 있는 존은 `RECIPES` 에 적힌 곳뿐이고(지금은 마을), 나머지는 예전처럼
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
## - `plaza`   : 가운데 돌판 광장 반지름. NPC 와 차원문이 여기 선다
## - `roads`   : 자갈길 — 꺾은선. 광장 안에서 시작해 언덕으로 사라진다
## - `road_w`  : 자갈길 반폭
## - `bumps`   : 걸어 다니는 땅의 굴곡 높이(±m). 광장은 평평하게 눌러 둔다
## - `rim`     : 이 거리(맵 가운데서 x·z 중 큰 쪽)부터 언덕이 솟는다 — 이동 끝(±29)과 같다
## - `rim_top` : 메시 끝(64)에서의 언덕 높이
const RECIPES := {
	"village": {
		"plaza": 11.0,
		"roads": [
			[[1, 8], [3, 17], [0, 25], [2, 38]],
			[[8, -1], [17, 1], [25, -2], [38, 0]],
			[[-1, -8], [-3, -17], [0, -25], [-2, -38]],
			[[-8, 1], [-17, 3], [-25, 0], [-38, 2]],
		],
		"road_w": 1.7,
		"bumps": 0.7,
		"rim": 29.0,
		"rim_top": 12.0,
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
	node.material_override = Ground.terrain_material(env, LAYERS, _splat_cache, SPLAT_HALF)
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
	var stone := 1.0 - smoothstep(plaza_r - 0.8, plaza_r + 0.8, r + _n01(x, z, 4.0, 11.0) * 1.3)

	var w := float(_recipe.road_w)
	var d := _road_dist_at(x, z) + _n01(x, z, 2.5, 37.0) * 0.45
	var cobble := (1.0 - smoothstep(w - 0.35, w + 0.35, d)) * (1.0 - stone) * fade

	# 흙 — 길섶(밟혀서 풀이 벗겨진 곳), 광장 둘레, 그리고 군데군데 맨땅
	var shoulder := 1.0 - smoothstep(w + 0.4, w + 2.2, d + _n01(x, z, 3.0, 53.0) * 0.9)
	var ring := 1.0 - smoothstep(plaza_r + 0.5, plaza_r + 3.5, r + _n01(x, z, 3.0, 71.0) * 1.5)
	var patch := smoothstep(0.28, 0.5, _n01(x, z, 9.0, 97.0))
	var dirt := clampf(maxf(maxf(shoulder, ring), patch * 0.85), 0.0, 1.0)
	dirt *= (1.0 - stone - cobble) * fade
	return Vector3(stone, cobble, maxf(dirt, 0.0))


func _splat_texture() -> ImageTexture:
	var img := Image.create(_splat_n, _splat_n, false, Image.FORMAT_RGB8)
	for j in _splat_n:
		for i in _splat_n:
			var p := _splat_world(i, j)
			var w := _weights(p.x, p.y)
			img.set_pixel(i, j, Color(w.x, w.y, w.z))
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
			h *= smoothstep(plaza_r + 1.0, plaza_r + 7.0, Vector2(x, z).length())
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
