class_name Tomb
extends RefCounted

## 묘비 3D — 캐릭터가 쓰러진 자리에 선다 (2026-09-30 요청: "캐릭터가 죽으면 해당 위치에 묘비
## 만들어놔. 묘비는 게임 껐다 켜면 사라지게"). 자리는 `game.gd` 의 `_tombs` 가 **메모리에만**
## 들고 있고 저장하지 않는다 — 그래서 게임을 다시 켜면 없다. 보여주기만 하고 판정과 무관하다
## (막지도, 눌리지도 않는다) → docs/features/combat.md "사망"
##
## 모델(`MODEL`)이 있으면 그걸 세우고, 없으면 회색 돌판(받침 + 윗머리가 둥근 비석)을 그린다 —
## 차원문(`portal.gd`)과 같은 짜임이다. 바르코 모델을 받으면 이 자리에 넣기만 하면 된다

const MODEL := "res://assets/models/varco_tomb.glb"
## 묘비 높이(m) — 사람(1.8m)의 허리께. 처음엔 작게(0.5m) 했다가 2배로 키웠다
## (2026-09-30 "크기는 작게 만들어" → "지금의 2배로 키워"). 그 뒤 흙 둔덕을 뺀 모델로 바꿔서
## ("묘비만 냅두고 묘비 아래 흙은 제거해") 가장 긴 변이 높이다 — 폭 0.83 × 높이 1 × 깊이 0.55
const SIZE := 1.0
## 모델이 없을 때의 돌판 높이(m) — 모델의 키와 맞춘다
const FALLBACK_HEIGHT := 1.0
const STONE := Color("#77726a")


static func create(x: float, y: float, z: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Tomb"
	root.position = Vector3(x, y, z)
	# 정면(+z)이 카메라를 보게 돌린다 — 차원문과 같다
	root.rotation.y = CameraRig.YAW

	if ResourceLoader.exists(MODEL):
		var packed: PackedScene = load(MODEL)
		var model := packed.instantiate() as Node3D
		# 모델은 가장 긴 변이 1 로 정규화돼 있고 원점이 한가운데다 (portal.gd 와 같다).
		# 반을 올리는 대신 **바닥면**을 땅에 앉힌다 — 모델이 바뀌어도 받침이 땅에 붙게
		model.scale = Vector3.ONE * SIZE
		model.position.y = -_bottom(model) * SIZE
		root.add_child(model)
		return root

	# 모델이 없을 때의 돌판 — 높이 1 로 짓고 FALLBACK_HEIGHT 로 줄인다
	var stone := Node3D.new()
	stone.scale = Vector3.ONE * FALLBACK_HEIGHT
	root.add_child(stone)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE
	mat.roughness = 0.95
	# 받침
	stone.add_child(_part(_box(Vector3(0.95, 0.14, 0.45)), Vector3(0, 0.07, 0), Vector3.ZERO, mat))
	# 비석 몸통과 둥근 윗머리. 원기둥을 눕혀(축이 앞뒤) 몸통 위에 반쯤 묻는다
	var body_h := 1.0 - 0.14 - 0.35
	stone.add_child(_part(_box(Vector3(0.7, body_h, 0.16)), Vector3(0, 0.14 + body_h / 2.0, 0), Vector3.ZERO, mat))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.35
	cap.bottom_radius = 0.35
	cap.height = 0.16
	stone.add_child(_part(cap, Vector3(0, 0.14 + body_h, 0), Vector3(PI / 2.0, 0, 0), mat))
	return root


## 모델 메시들의 가장 낮은 y (모델 자기 좌표, 배율 전)
static func _bottom(model: Node3D) -> float:
	var low := 0.0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		low = minf(low, (mesh as MeshInstance3D).position.y + box.position.y)
	return low


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _part(mesh: Mesh, at: Vector3, turn: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = turn
	part.material_override = mat
	return part
