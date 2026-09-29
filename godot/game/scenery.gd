class_name Scenery
extends RefCounted

## 존 꾸밈 — **바위** 를 지형 위에 흩뿌린다 (코드로 짓는다 — 메시 + 셰이더).
## **길을 막지 않는다** — 판정(`World`)은 모른다. 그래서 전부 이동 끝 안의 발목 높이 돌이다.
##
## 풀포기(코드)와 나무(바르코 모델)도 있었는데 2026-09-29 "퀄리티 별로야. 나무랑 풀 제거해"
## 로 뺐다. 코드는 이 파일의 이력에 있다.
##
## 지형이 있는 존(`Terrain.RECIPES`) 가운데 여기 `RECIPES` 에도 적힌 곳만 꾸민다.
## 규칙과 수치의 이유는 docs/features/world-zones.md 의 "덤불숲" 절에 있다.

const ROCK_SHADER := preload("res://game/rock.gdshader")

## 이동 끝 (Movement.zone_half_size(66)). 이 안에는 발목 높이만 둔다
const WALK := 29.0

## 존별 꾸밈. 좌표는 판정과 같은 (x, z) 미터다.
## - `rocks`      : 바위 무더기 [x, z, 흩뿌릴 반지름, 개수, 가장 큰 것(m)]
const RECIPES := {
	"thicket": {
		# 이동 끝 너머는 검은 바닥이라(terrain `void`) 돌은 끝 안에만 둔다 — 걷는 땅 안이니
		# 전부 발목 높이다. 끝 너머에 두던 큰 바위 무더기는 뺐다 (검은 바닥 위에 떠 보인다)
		# 맵을 66 으로 키우며(2026-09-28) 자리를 두 배로 옮기고, 넓어진 만큼 무더기를 더했다
		"rocks": [
			[-12.0, 14.0, 1.2, 4, 0.45],
			[19.0, -7.0, 1.0, 3, 0.4],
			[-7.0, -19.0, 0.9, 3, 0.4],
			[-21.0, -3.0, 1.1, 4, 0.45],
			[-3.0, -22.0, 1.0, 3, 0.4],
			[6.0, 21.0, 0.9, 3, 0.35],
			[-18.0, 20.0, 1.1, 4, 0.45],
			[24.0, -20.0, 1.0, 3, 0.4],
			[-24.0, -12.0, 1.0, 3, 0.4],
			[8.0, -24.0, 0.9, 3, 0.35],
			[-10.0, 4.0, 0.9, 3, 0.35],
			[24.0, 5.0, 1.0, 3, 0.4],
		],
	},
}

## 바위 모양 몇 가지 — 한 번 지어 모든 존이 돌려 쓴다
const ROCK_SHAPES := 6
static var _rock_meshes: Array[ArrayMesh] = []


static func build(zone_id: String, terrain: Terrain, env: Dictionary) -> Node3D:
	if terrain == null or not RECIPES.has(zone_id):
		return null
	var recipe: Dictionary = RECIPES[zone_id]
	var root := Node3D.new()
	root.name = "Scenery"
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_id.hash()
	for c in recipe.get("rocks", []):
		_rock_pile(root, c, terrain, rng)
	return root


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

