class_name Portal
extends RefCounted

## 차원문 3D — 돌 아치 모델 하나. 모든 존의 같은 자리(GATE_SPOT)에 선다.
##
## 모델이 없으면(`npm run sync:godot` 을 안 돌렸으면) 예전처럼 **빛나는 원판**을 그린다.
## 누른 걸 알아보는 건 `hit` 이다 — **소용돌이가 도는 원판**만 문이다
## (docs/features/portal-ui.md)

const MODEL := "res://assets/models/varco_portal.glb"


## 존 노드에 세울 차원문. gate 는 zones.json 의 gate 그대로
static func create(gate: Dictionary) -> Node3D:
	var pos: Array = gate.get("position", [0, 0])
	var radius := float(gate.get("radius", 2.6))
	var color := Color(gate.get("color", "#4aa8ff"))
	var root := Node3D.new()
	root.name = "Portal"
	root.position = Vector3(float(pos[0]), 0.0, float(pos[1]))

	if ResourceLoader.exists(MODEL):
		var packed: PackedScene = load(MODEL)
		var model := packed.instantiate() as Node3D
		# 모델은 1×1×1 로 정규화돼 있고 원점이 한가운데다. 받침 폭이 문 폭(2 × 반지름)이
		# 되게 늘리고, 바닥에 앉힌다. 정면(+z)이 카메라를 보게 돌린다
		var s := radius * 2.0
		model.scale = Vector3.ONE * s
		model.position.y = 0.5 * s
		model.rotation.y = CameraRig.YAW
		root.add_child(model)
		root.add_child(PortalSwirl.create(radius, color, CameraRig.YAW))
		return root

	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.08
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	disc.material_override = mat
	disc.position.y = 0.04
	root.add_child(disc)
	# 모델이 없어도 소용돌이는 돈다 — 이펙트는 에셋을 안 받은 사람에게도 보여야 한다
	# (docs/features/effect-rules.md 1절)
	root.add_child(PortalSwirl.create(radius, color, CameraRig.YAW))
	return root


## 화면에서 쏜 선이 **소용돌이 원판**에 닿나.
##
## 2026-09-18 요청: "포탈 클릭 영역을 이펙트 있는 곳 눌러야 UI 열도록, 지금 너무 넓어".
## 그 전에는 아치 전체를 감싸는 반지름 2.6 × 높이 5 짜리 기둥이라 돌기둥·받침·
## 아치 위 빈 곳까지 다 문이었다. 지금은 **소용돌이가 도는 그 판**(`PortalSwirl` 의
## CENTER 높이, SPAN 반지름)만 문이다 — 보이는 것과 누르는 곳이 같아야 한다.
##
## 판은 아치와 같은 쪽을 보고 서 있으므로(`CameraRig.YAW`) 선과 판이 만나는
## 점을 구해 가운데와의 거리를 잰다
static func hit(from: Vector3, dir: Vector3, gate: Dictionary) -> bool:
	if gate.is_empty():
		return false
	var pos: Array = gate.get("position", [0, 0])
	var radius := float(gate.get("radius", 2.6))
	var model := radius * 2.0
	var center := Vector3(float(pos[0]), model * PortalSwirl.CENTER, float(pos[1]))
	# 소용돌이 판의 법선 — 아치가 보는 쪽이다
	var facing := Vector3(sin(CameraRig.YAW), 0.0, cos(CameraRig.YAW))
	var toward := dir.dot(facing)
	if absf(toward) < 0.0001:
		return false
	var span := (center - from).dot(facing) / toward
	if span <= 0.0:
		return false
	return (from + dir * span).distance_to(center) <= model * PortalSwirl.SPAN
