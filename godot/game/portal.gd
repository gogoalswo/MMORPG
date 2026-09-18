class_name Portal
extends RefCounted

## 차원문 3D — 돌 아치 모델 하나. 모든 존의 같은 자리(GATE_SPOT)에 선다.
##
## 모델이 없으면(`npm run sync:godot` 을 안 돌렸으면) 예전처럼 **빛나는 원판**을 그린다.
## 누른 걸 알아보는 건 `hit` 이다 — 아치는 높이가 있어서 바닥 점만 보면 윗부분을
## 눌렀을 때 문 뒤의 땅이 잡힌다 (docs/features/portal-ui.md)

const MODEL := "res://assets/models/varco_portal.glb"

## 누르는 기둥의 높이. 모델은 폭 = 2 × 반지름으로 맞추므로 높이도 그쯤이다
const HIT_HEIGHT := 5.0


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
	return root


## 화면에서 쏜 선이 문(반지름 × HIT_HEIGHT 기둥)에 닿나.
## 선에서 기둥 높이 안에 드는 구간을 잘라 그 구간과 기둥 축의 수평 거리를 잰다
static func hit(from: Vector3, dir: Vector3, gate: Dictionary) -> bool:
	if gate.is_empty() or absf(dir.y) < 0.0001:
		return false
	var pos: Array = gate.get("position", [0, 0])
	var center := Vector2(float(pos[0]), float(pos[1]))
	var radius := float(gate.get("radius", 2.6))
	var t0 := (HIT_HEIGHT - from.y) / dir.y
	var t1 := (0.0 - from.y) / dir.y
	var a := from + dir * minf(t0, t1)
	var b := from + dir * maxf(t0, t1)
	var closest := Geometry2D.get_closest_point_to_segment(center, Vector2(a.x, a.z), Vector2(b.x, b.z))
	return closest.distance_to(center) <= radius
