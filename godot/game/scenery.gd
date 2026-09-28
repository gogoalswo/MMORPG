class_name Scenery
extends RefCounted

## 존 꾸밈 — **풀포기 · 바위 · 나무** 를 지형 위에 흩뿌린다. **길을 막지 않는다** —
## 판정(`World`)은 모른다. 그래서 걷는 땅(±12.5) 안에는 발목 높이의 풀과 작은 돌만
## 두고, 큰 바위·나무는 이동 끝 너머 언덕에 둔다.
##
## - 풀포기·바위는 **코드로 짓는다** (메시 + 셰이더). 모양이 단순해서 코드로 충분하다
## - 나무는 **바르코 모델**을 자리에 세운다 (`assets/models/prop_tree_*.glb`). 파일이
##   없으면 그 자리는 비워 둔다 — 모델이 올 때까지 맵은 풀·바위만으로 선다
##
## 지형이 있는 존(`Terrain.RECIPES`) 가운데 여기 `RECIPES` 에도 적힌 곳만 꾸민다.
## 규칙과 수치의 이유는 docs/features/world-zones.md 의 "덤불숲" 절에 있다.

const DIR := "res://assets/models/"
const TUFT_SHADER := preload("res://game/grass_tuft.gdshader")
const ROCK_SHADER := preload("res://game/rock.gdshader")

## 이동 끝 (Movement.zone_half_size(33)). 이 안에는 발목 높이만 둔다
const WALK := 12.5
## 카메라 시선 기울기(피치 42도). 카메라 쪽 끝(+x · +z) 너머의 것은 끝에 선 캐릭터를
## 가리지 않게 이 기울기 아래로 눕힌다 — 높이 ≤ (끝까지 거리) × 이 값
const SIGHT := 0.9
## 풀포기를 이동 끝에서 이만큼 안쪽까지만 심는다 (포기 반폭 ≈ 0.3~0.4m)
const EDGE_GAP := 0.35

## 존별 꾸밈. 좌표는 판정과 같은 (x, z) 미터다.
## - `tufts`      : 풀포기 수. `tuft_half` 안에 흩뿌린다 (카메라가 끝에 서도 화면 밖까지)
## - `rocks`      : 바위 무더기 [x, z, 흩뿌릴 반지름, 개수, 가장 큰 것(m)]
## - `trees`      : 나무 자리 [x, z, 높이(m), 방향(도)]. 모델은 `tree_models` 를 돌려 쓴다
const RECIPES := {
	"thicket": {
		"tufts": 1600,
		"tuft_half": 12.5,
		# 뿌리 쪽 · 잎 끝 색 — 지형의 풀 층(`looks`)과 맞춘다
		# 끝 색이 형광 연두(#86a648)였을 때 "눈이 너무 아파" — 채도·밝기를 낮췄다
		"tuft_colors": ["#26331a", "#6a7f3e"],
		# 이동 끝 너머는 검은 바닥이라(terrain `void`) 풀·돌은 끝 안에만 둔다 — 걷는 땅 안이니
		# 전부 발목 높이다. 끝 너머에 두던 큰 바위 무더기는 뺐다 (검은 바닥 위에 떠 보인다)
		"rocks": [
			[-6.0, 7.0, 1.2, 4, 0.45],
			[9.5, -3.5, 1.0, 3, 0.4],
			[-3.5, -9.5, 0.9, 3, 0.4],
			[-10.5, -1.5, 1.1, 4, 0.45],
			[-1.5, -11.0, 1.0, 3, 0.4],
			[3.0, 10.5, 0.9, 3, 0.35],
		],
		# 나무는 화면 위쪽 두 변(-x · -z)의 **끝선에 걸쳐** 선다 — 줄기는 검은 쪽(끝에서 0.6m),
		# 가지는 숲 위로 드리운다. 카메라 쪽 두 변(+x · +z)에는 없다 (끝에 선 캐릭터 앞이라)
		"trees": [
			[-13.1, -7.5, 7.5, 20], [-13.1, -1.0, 8.5, 110], [-13.1, 5.5, 7.0, 250], [-13.3, 11.0, 6.5, 180],
			[-5.0, -13.1, 8.0, 70], [1.5, -13.1, 7.0, 160], [8.0, -13.1, 7.5, 300],
			[-13.6, -13.6, 9.0, 200],
		],
		"tree_models": ["prop_tree_a", "prop_tree_b"],
	},
}

## 바위 모양 몇 가지 — 한 번 지어 모든 존이 돌려 쓴다
const ROCK_SHAPES := 6
static var _rock_meshes: Array[ArrayMesh] = []
static var _tuft_mesh: ArrayMesh = null


static func build(zone_id: String, terrain: Terrain, env: Dictionary) -> Node3D:
	if terrain == null or not RECIPES.has(zone_id):
		return null
	var recipe: Dictionary = RECIPES[zone_id]
	var root := Node3D.new()
	root.name = "Scenery"
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_id.hash()
	root.add_child(_tufts(recipe, terrain, env, rng))
	for c in recipe.get("rocks", []):
		_rock_pile(root, c, terrain, rng)
	_trees(root, recipe, terrain)
	return root


## 카메라 쪽 끝(+x · +z)까지 넘어간 거리. 0 이면 끝 안이거나 반대쪽이다
static func _past_near_edge(x: float, z: float) -> float:
	return maxf(0.0, maxf(x, z) - WALK)


## 이 자리에 세워도 되는 가장 큰 높이 — 카메라 쪽 끝 너머면 시선 아래로
static func height_cap(x: float, z: float, want: float) -> float:
	var past := _past_near_edge(x, z)
	if past <= 0.0:
		return want
	return minf(want, past * SIGHT)


# ─── 풀포기 ──────────────────────────────────────────────────────────


static func _tufts(recipe: Dictionary, terrain: Terrain, env: Dictionary, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var placed := _tuft_placements(recipe, terrain, rng)
	var xforms: Array = placed[0]
	var customs: Array = placed[1]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _tuft()
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_custom_data(k, customs[k])
	var node := MultiMeshInstance3D.new()
	node.name = "Tufts"
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = TUFT_SHADER
	var colors: Array = recipe.get("tuft_colors", [env.get("grassDark", "#2f3a28"), env.get("grassLight", "#4a5936")])
	mat.set_shader_parameter("base_color", Color(str(colors[0])))
	mat.set_shader_parameter("tip_color", Color(str(colors[1])))
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## 풀포기 자리 — `build` 와 같은 씨앗으로 다시 뽑는다. 헤드리스(더미 렌더러)에서는
## MultiMesh 가 자리를 들고 있지 않아서 테스트는 이걸 읽는다
static func tuft_transforms(zone_id: String, terrain: Terrain) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_id.hash()
	return _tuft_placements(RECIPES[zone_id], terrain, rng)[0]


## [자리들, 커스텀 데이터들]
static func _tuft_placements(recipe: Dictionary, terrain: Terrain, rng: RandomNumberGenerator) -> Array:
	var half := float(recipe.get("tuft_half", 26.0))
	var want := int(recipe.get("tufts", 2000))
	var road_w := float(terrain._recipe.get("road_w", 1.0))
	var flats: Array = terrain._recipe.get("flats", [])
	var clump := FastNoiseLite.new()
	clump.seed = rng.randi()
	clump.frequency = 0.18

	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var tries := 0
	while xforms.size() < want and tries < want * 6:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		# 무리 지어 난다 — 빽빽한 데와 성긴 데
		var dense := clampf(clump.get_noise_2d(x, z) * 1.4 + 0.45, 0.0, 1.0)
		if rng.randf() > 0.12 + 0.88 * dense:
			continue
		# 길 위·맨땅에는 드물게
		if terrain.road_distance(x, z) < road_w + 0.3 and rng.randf() < 0.9:
			continue
		if terrain.ground_mix(x, z).z > 0.5 and rng.randf() < 0.75:
			continue
		# 끝 너머는 검은 바닥 — 잎이 선을 넘어 검은 데로 삐져나가지 않게 조금 안쪽까지만
		if maxf(absf(x), absf(z)) > WALK - EDGE_GAP:
			continue
		var skip := false
		for f in flats:
			if Vector2(x - float(f[0]), z - float(f[1])).length() < float(f[2]) * 0.8:
				skip = true
		if skip:
			continue
		# 크기 — 걷는 땅 안은 발목, 끝 너머는 무릎·허리까지 (덤불)
		var edge := maxf(absf(x), absf(z))
		var tall := 0.35 + 0.35 * rng.randf()
		if edge > WALK:
			tall += minf(1.0, (edge - WALK) / 4.0) * rng.randf_range(0.2, 0.8)
		tall = maxf(0.25, height_cap(x, z, tall))
		# 한 자리에 몇 포기씩 — 참고 그림의 덤불처럼 뭉친다. 빽빽한 데일수록 많이
		var bunch := 1 + int(rng.randf() * (1.0 + dense * 5.0))
		for b in bunch:
			var bx := x + rng.randf_range(-0.45, 0.45) * float(b > 0)
			var bz := z + rng.randf_range(-0.45, 0.45) * float(b > 0)
			var bt := tall * (1.0 if b == 0 else rng.randf_range(0.6, 1.0))
			# 뭉치 곁포기가 끝 안으로 들어오면 발목 높이로 — 자리마다 다시 자른다
			if maxf(absf(bx), absf(bz)) <= WALK:
				bt = minf(bt, 0.7)
			bt = maxf(0.25, height_cap(bx, bz, bt))
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bt * rng.randf_range(0.9, 1.4), bt, bt * rng.randf_range(0.9, 1.4)))
			if maxf(absf(bx), absf(bz)) > WALK - EDGE_GAP:
				continue
			xforms.append(Transform3D(basis, Vector3(bx, terrain.height_at(bx, bz) - 0.03, bz)))
			# 색 흔들기(r) · 모양 씨앗(g)
			customs.append(Color(rng.randf(), rng.randf(), 0.0, 0.0))
	return [xforms, customs]


## 풀포기 하나 = 세 장을 60도씩 엇갈려 세운 판. 잎 모양은 셰이더가 판 위에 오린다.
## 법선은 전부 위(+y) — 풀이 바닥과 같은 빛을 받아 바닥에서 튀지 않는다
static func _tuft() -> ArrayMesh:
	if _tuft_mesh != null:
		return _tuft_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var side := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var quad := [
			[-side, Vector2(0, 0)], [side, Vector2(1, 0)],
			[side + Vector3.UP, Vector2(1, 1)], [-side + Vector3.UP, Vector2(0, 1)],
		]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])
	_tuft_mesh = st.commit()
	return _tuft_mesh


# ─── 바위 ───────────────────────────────────────────────────────────


static func _rock_pile(root: Node3D, c: Array, terrain: Terrain, rng: RandomNumberGenerator) -> void:
	var cx := float(c[0])
	var cz := float(c[1])
	var spread := float(c[2])
	var count := int(c[3])
	var biggest := float(c[4])
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	for k in count:
		# 첫째가 가장 크고 나머지는 둘레에 작게
		var size := biggest if k == 0 else biggest * rng.randf_range(0.3, 0.7)
		var ang := rng.randf() * TAU
		var dist := 0.0 if k == 0 else spread * rng.randf_range(0.4, 1.0)
		var x := cx + cos(ang) * dist
		var z := cz + sin(ang) * dist
		size = minf(size, maxf(0.2, height_cap(x, z, size * 0.65) / 0.65))
		var rock := MeshInstance3D.new()
		rock.mesh = _rock(rng.randi() % ROCK_SHAPES)
		rock.material_override = mat
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.rotated(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.25))
		rock.transform = Transform3D(basis.scaled(Vector3.ONE * size), Vector3(x, terrain.height_at(x, z) - size * 0.12, z))
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rock)


## 바위 한 덩이 (지름 1 안팎). 구를 노이즈로 울퉁불퉁하게 하고, 평면 몇 장으로
## 깎아 모난 면을 낸 뒤, 아래를 눌러 땅에 앉힌다
static func _rock(shape: int) -> ArrayMesh:
	if _rock_meshes.is_empty():
		for s in ROCK_SHAPES:
			_rock_meshes.append(_make_rock(s))
	return _rock_meshes[shape]


static func _make_rock(shape: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 18
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var noise := FastNoiseLite.new()
	noise.seed = 7919 * (shape + 1)
	noise.frequency = 1.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * (shape + 1)
	var cuts: Array = []
	for k in 5:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		cuts.append([n, rng.randf_range(0.3, 0.42)])
	var squash := Vector3(rng.randf_range(0.9, 1.15), rng.randf_range(0.75, 0.95), rng.randf_range(0.8, 1.0))

	for i in verts.size():
		var p := verts[i]
		var dir := p.normalized()
		p = dir * 0.5 * (1.0 + noise.get_noise_3dv(dir * 1.3) * 0.35)
		for cut in cuts:
			var over: float = p.dot(cut[0]) - float(cut[1])
			if over > 0.0:
				p -= cut[0] * over
		p *= squash
		# 아래는 눌러서 편평하게 — 땅에 앉는다
		var floor_y := -0.12
		if p.y < floor_y:
			p.y = floor_y + (p.y - floor_y) * 0.15
		verts[i] = p

	# 법선 — 같은 자리 꼭짓점(구의 이음새)끼리 모아 평균 낸다. 안 모으면 이음새가 줄로 보인다
	var acc := {}
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var b := verts[indices[t + 1]]
		var c := verts[indices[t + 2]]
		var fn := (b - a).cross(c - a)
		for v in [a, b, c]:
			var key := _key(v)
			acc[key] = acc.get(key, Vector3.ZERO) + fn
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = acc.get(_key(verts[i]), Vector3.UP)
		n = n.normalized() if n.length() > 0.0 else Vector3.UP
		# 바위는 원점에서 보면 어디든 바깥이 보인다 — 법선이 안쪽을 보면 뒤집는다
		normals[i] = -n if n.dot(verts[i] - Vector3(0, -0.05, 0)) < 0.0 else n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))


# ─── 나무 (바르코 모델) ────────────────────────────────────────────────


static func _trees(root: Node3D, recipe: Dictionary, terrain: Terrain) -> void:
	var scenes: Array[PackedScene] = []
	for name in recipe.get("tree_models", []):
		var path := DIR + str(name) + ".glb"
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	var k := 0
	for t in recipe.get("trees", []):
		var x := float(t[0])
		var z := float(t[1])
		var tree: Node3D = scenes[k % scenes.size()].instantiate()
		k += 1
		var box := _bounds(tree)
		var want := height_cap(x, z, float(t[2]))
		var s := want / maxf(0.01, box.size.y)
		tree.scale = Vector3.ONE * s
		tree.rotation.y = deg_to_rad(float(t[3]))
		tree.position = Vector3(x, terrain.height_at(x, z) - box.position.y * s - 0.1, z)
		root.add_child(tree)


## 모델 전체의 경계 상자 (모델 자기 좌표)
static func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var local := _local_xform(node, mi) * mi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


static func _local_xform(root: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
