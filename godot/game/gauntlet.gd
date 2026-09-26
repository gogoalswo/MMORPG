class_name Gauntlet
extends RefCounted

## 주먹에 끼는 무기(건틀릿) 모델. **등급마다 생김새가 다르다** — 아이콘
## (`weapon_g1`~`weapon_g7`)과 같은 결로 붕대 → 가죽 → 은빛 판금 → 보석 →
## 용린 → 붉게 갈라진 검은 쇠 → 빛나는 흰 주먹과 고리.
##
## 받은 무기 모델이 없어서 **코드로 짓는다** (이펙트처럼 에셋을 안 받은 사람도
## 보여야 한다). `assets/models/weapon_g<등급>.glb` 가 있으면 그걸 주먹 크기에
## 맞춰 대신 쓴다 — 모델을 받으면 파일을 넣고 `sync-godot-assets.mjs` 의
## `MODELS` 에 이름만 더하면 된다.
##
## 좌표는 **손 뼈 기준**(`BoneAttachment3D` 안)이고 단위는 격투가 모델 단위다
## (모델 전체가 1.85배로 커지므로 여기 0.1 은 화면에서 약 0.19m).
## 손 뼈의 +Y 가 손가락(주먹이 나가는) 쪽이다. 수치는 손에 묶인 정점을 재서 얻었다
## → docs/features/characters-and-animation.md "무기 소켓"

const DIR := "res://assets/models/"

## 오른손 가운데와 반 크기 (손·손가락 뼈에 묶인 정점 871개의 상자). 왼손은 x 를 뒤집는다.
## 2026-09-26 — 주먹 이식을 걷고 **편 손**으로 돌아갔다 ("주먹은 틀려 먹은 것 같다"). 잴 때는
## `node scripts/measure-bones.mjs <glb> RightHand --posed` (손가락 뼈 정점을 그 손 몫으로 센다).
## 옛 몸: (-0.011, 0.046, -0.014) ± (0.049, 0.050, 0.036)
const FIST_CENTER := Vector3(-0.012, 0.063, -0.007)
const FIST_HALF := Vector3(0.046, 0.063, 0.028)
## 손목 토시 — 아래팔 정점이 손목에서 반지름 0.041
const CUFF_Y := -0.028
const CUFF_R := 0.046
const CUFF_H := 0.07


## 주먹 가운데 (손 뼈 기준, 모델 단위). 기운(`FistAura`)을 여기 둔다
static func fist_center(left: bool) -> Vector3:
	return Vector3(FIST_CENTER.x * (-1.0 if left else 1.0), FIST_CENTER.y, FIST_CENTER.z)


## 등급 하나로 한 손 몫을 짓는다. `left` 면 왼손(좌우 반전)
static func build(grade: int, left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Gauntlet%d" % grade
	var glb := "%sweapon_g%d.glb" % [DIR, grade]
	if ResourceLoader.exists(glb):
		_fit_glb(root, load(glb), left)
		return root

	var side := -1.0 if left else 1.0
	var c := Vector3(FIST_CENTER.x * side, FIST_CENTER.y, FIST_CENTER.z)
	match clampi(grade, 1, 7):
		1: _bandage(root, c)
		2: _leather(root, c)
		3: _plate(root, c)
		4: _gem(root, c)
		5: _dragon(root, c)
		6: _cracked(root, c)
		7: _primal(root, c)
	return root


# ─── 등급별 생김새 ──────────────────────────────────────────

## 일반 — 붕대 감은 주먹. 천 주먹에 어두운 띠 셋
static func _bandage(root: Node3D, c: Vector3) -> void:
	var cloth := _mat(Color("#e6dcc3"), 0.0, 1.0)
	var band := _mat(Color("#a8987a"), 0.0, 1.0)
	_shell(root, c, cloth, 1.04)
	_cuff(root, cloth)
	for y in [CUFF_Y - 0.022, CUFF_Y + 0.004, c.y + 0.012]:
		_ring(root, Vector3(0, y, 0), 0.052 if y < 0.0 else 0.058, 0.006, band)


## 고급 — 가죽 덮개와 주먹 앞 리벳 넷
static func _leather(root: Node3D, c: Vector3) -> void:
	var leather := _mat(Color("#6e4526"), 0.0, 0.8)
	var dark := _mat(Color("#3f2716"), 0.0, 0.85)
	var rivet := _mat(Color("#b8a47a"), 0.9, 0.35)
	_shell(root, c, leather, 1.08)
	_cuff(root, dark)
	_knuckle(root, c, dark, 0.016)
	_studs(root, c, rivet, 4, 0.009)


## 희귀 — 은빛 판금. 주먹 앞 판과 토시 테
static func _plate(root: Node3D, c: Vector3) -> void:
	var silver := _mat(Color("#c9ced6"), 0.95, 0.28)
	var steel := _mat(Color("#7d848f"), 0.9, 0.4)
	_shell(root, c, silver, 1.1)
	_cuff(root, silver)
	_knuckle(root, c, steel, 0.022)
	_ring(root, Vector3(0, CUFF_Y + CUFF_H * 0.5, 0), CUFF_R + 0.004, 0.007, steel)
	_ring(root, Vector3(0, CUFF_Y - CUFF_H * 0.5, 0), CUFF_R + 0.002, 0.006, steel)


## 영웅 — 검보랏빛 쇠에 빛나는 보라 보석
static func _gem(root: Node3D, c: Vector3) -> void:
	var iron := _mat(Color("#3b3450"), 0.85, 0.35)
	var trim := _mat(Color("#8c7ab8"), 0.9, 0.3)
	var gem := _mat(Color("#b85cff"), 0.2, 0.1, Color("#b85cff"), 2.0)
	_shell(root, c, iron, 1.1)
	_cuff(root, iron)
	_knuckle(root, c, trim, 0.022)
	_ring(root, Vector3(0, CUFF_Y + CUFF_H * 0.5, 0), CUFF_R + 0.004, 0.006, gem)
	# 주먹 앞 가운데 보석 — 주먹이 나가는 쪽이라 칠 때 눈에 띈다
	_part(root, _sphere(0.017), gem, c + Vector3(0, FIST_HALF.y + 0.03, 0))


## 전설 — 용린. 금빛 비늘을 토시에 두르고 주먹 앞에 가시 셋
static func _dragon(root: Node3D, c: Vector3) -> void:
	var gold := _mat(Color("#d98a2b"), 0.9, 0.3)
	var scale_mat := _mat(Color("#8a3a18"), 0.85, 0.35)
	_shell(root, c, gold, 1.1)
	_cuff(root, scale_mat)
	_knuckle(root, c, gold, 0.022)
	# 비늘 — 토시 둘레에 두 줄, 엇갈려 겹친다
	for row in 2:
		for i in 8:
			var angle := TAU * (i + row * 0.5) / 8.0
			var dir := Vector3(cos(angle), 0, sin(angle))
			var pos := dir * (CUFF_R + 0.003) + Vector3(0, CUFF_Y - 0.018 + row * 0.03, 0)
			var plate := _part(root, _box(Vector3(0.026, 0.03, 0.006)), gold, pos)
			# 트리 밖에서 지으므로 look_at 대신 기저를 바로 준다
			plate.basis = Basis.looking_at(dir, Vector3.UP).rotated(dir.cross(Vector3.UP).normalized(), 0.35)
	_spikes(root, c, gold, 3, 0.03)


## 초월 — 검은 쇠에 붉게 갈라진 금. 가시 넷
static func _cracked(root: Node3D, c: Vector3) -> void:
	var black := _mat(Color("#1b1818"), 0.8, 0.45)
	var ember := _mat(Color("#ff3a1a"), 0.0, 0.5, Color("#ff2a10"), 2.5)
	_shell(root, c, black, 1.12)
	_cuff(root, black)
	_knuckle(root, c, black, 0.024)
	# 갈라진 금 — 주먹 껍데기 위에 가는 빛줄기를 비스듬히 얹는다
	var cracks := [
		[Vector3(1, 0.1, 0), 0.5], [Vector3(-1, -0.2, 0), -0.6],
		[Vector3(0, 0.2, 1), 0.3], [Vector3(0, -0.1, -1), -0.4],
		[Vector3(0.7, 0.5, 0.7), 0.9], [Vector3(-0.7, 0.4, -0.7), -0.8],
	]
	for crack in cracks:
		var normal: Vector3 = (crack[0] as Vector3).normalized()
		var pos: Vector3 = c + normal * FIST_HALF * 1.12
		var line := _part(root, _box(Vector3(0.004, 0.05, 0.004)), ember, pos)
		line.rotate_object_local(normal, float(crack[1]))
	_ring(root, Vector3(0, CUFF_Y + CUFF_H * 0.5, 0), CUFF_R + 0.004, 0.005, ember)
	_spikes(root, c, black, 4, 0.034)


## 태초 — 빛나는 흰 주먹과 손목을 도는 금빛 고리
static func _primal(root: Node3D, c: Vector3) -> void:
	var white := _mat(Color("#f6f2e6"), 0.3, 0.3, Color("#fff6dc"), 1.4)
	var gold := _mat(Color("#ffd27a"), 0.6, 0.2, Color("#ffcf66"), 2.2)
	_shell(root, c, white, 1.1)
	_cuff(root, white)
	_knuckle(root, c, gold, 0.02)
	# 떠 있는 고리 — 몸에 닿지 않게 토시보다 넉넉히, 살짝 기울인다
	var halo := _ring(root, Vector3(0, CUFF_Y + 0.01, 0), 0.085, 0.006, gold)
	halo.rotation = Vector3(0.35, 0, 0.2)


# ─── 조각 ────────────────────────────────────────────────

## 주먹 껍데기 — 주먹 상자를 감싸는 타원체. `grow` 만큼 부풀린다
static func _shell(root: Node3D, c: Vector3, mat: Material, grow: float) -> void:
	var shell := _part(root, _sphere(1.0), mat, c)
	shell.scale = FIST_HALF * grow


## 손목 토시
static func _cuff(root: Node3D, mat: Material) -> void:
	var cuff := CylinderMesh.new()
	cuff.top_radius = CUFF_R
	cuff.bottom_radius = CUFF_R - 0.004
	cuff.height = CUFF_H
	cuff.radial_segments = 16
	cuff.rings = 1
	_part(root, cuff, mat, Vector3(0, CUFF_Y, 0))


## 주먹 앞 너클 판 — 주먹 폭만큼 가로로 놓는다
static func _knuckle(root: Node3D, c: Vector3, mat: Material, depth: float) -> void:
	var size := Vector3(FIST_HALF.x * 2.1, depth, FIST_HALF.z * 1.6)
	_part(root, _box(size), mat, c + Vector3(0, FIST_HALF.y * 1.02, 0))


## 너클 앞에 가로로 늘어선 둥근 징
static func _studs(root: Node3D, c: Vector3, mat: Material, count: int, radius: float) -> void:
	for i in count:
		var x := lerpf(-FIST_HALF.x * 0.75, FIST_HALF.x * 0.75, float(i) / (count - 1))
		_part(root, _sphere(radius), mat, c + Vector3(x, FIST_HALF.y * 1.02 + 0.01, 0))


## 너클 앞에서 주먹이 나가는 쪽(+Y)으로 솟은 가시
static func _spikes(root: Node3D, c: Vector3, mat: Material, count: int, length: float) -> void:
	for i in count:
		var x := lerpf(-FIST_HALF.x * 0.7, FIST_HALF.x * 0.7, float(i) / (count - 1))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.009
		cone.height = length
		cone.radial_segments = 8
		cone.rings = 1
		_part(root, cone, mat, c + Vector3(x, FIST_HALF.y * 1.02 + 0.01 + length * 0.5, 0))


## 손목을 두르는 고리 (Y 축이 손목 방향이라 토러스를 그대로 눕히면 맞는다)
static func _ring(root: Node3D, pos: Vector3, radius: float, thick: float, mat: Material) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thick
	torus.outer_radius = radius + thick
	torus.rings = 24
	torus.ring_segments = 6
	return _part(root, torus, mat, pos)


static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	root.add_child(node)
	return node


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _mat(color: Color, metal: float, rough: float, glow := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = energy
	return mat


## 받은 모델을 주먹 크기에 맞춘다 — 가장 긴 변을 주먹(+토시) 길이에 맞추고
## 가운데를 주먹 가운데에 둔다. 모델이 어느 축으로 서 있는지는 모르므로 돌리지 않는다
static func _fit_glb(root: Node3D, packed: PackedScene, left: bool) -> void:
	var model: Node3D = packed.instantiate()
	root.add_child(model)
	var box := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true):
		var mesh_box: AABB = (child as MeshInstance3D).get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	var longest := box.get_longest_axis_size()
	if longest <= 0.0:
		return
	var target := FIST_HALF.y * 2.0 + CUFF_H
	model.scale = Vector3.ONE * (target / longest)
	var side := -1.0 if left else 1.0
	var mid := Vector3(FIST_CENTER.x * side, (FIST_CENTER.y + FIST_HALF.y + CUFF_Y - CUFF_H * 0.5) * 0.5, FIST_CENTER.z)
	model.position = mid - box.get_center() * model.scale
