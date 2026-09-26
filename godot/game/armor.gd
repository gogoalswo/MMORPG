class_name Armor
extends RefCounted

## 갑옷·투구·신발을 **입힌다** — 장비 칸의 등급이 바뀌면 그 부위가 **바르코로 뽑은 모델**로 바뀐다.
##
## 외형은 코드로 짓지 않는다 (CLAUDE.md, 2026-09-26). 등급마다 바르코가 **지금 몸 그림 + 그 등급
## 아이콘 셋**(갑옷·투구·신발)으로 장비를 갖춰 입은 격투가를 뽑고, `scripts/build-gear-parts.mjs` 가
## 부위를 떼어 **우리 몸의 뼈대로 옮겨** `assets/models/gear_g<등급>.glb` 로 싼다 (메시 노드 이름이
## `armor` `helmet` `boots`). 여기서는 그 메시를 우리 뼈대·스킨에 묶어 몸 옆에 붙이기만 한다 —
## 그래서 동작은 우리 것을 그대로 탄다.
##
## **입은 부위 아래 맨몸은 숨긴다.** 몸을 처음 입힐 때 부위 넷(`BODY_PARTS`)으로 나눠 두고
## (`_split`), 그 부위를 입으면 그 조각을 끈다. 투구는 얼굴째 떼 온 것이라 머리 조각을 통째로 끈다.
## 어느 삼각형이 어느 부위인지는 뼈 가중치가 정한다 — `build-gear-parts.mjs` 와 **같은 규칙**이다.
##
## 오로라는 4등급부터 고도 이펙트로 붙는다 (`GearAura`).
## → docs/features/characters-and-animation.md "장비 스킨"

const DIR := "res://assets/models/"
const SLOTS := ["armor", "helmet", "boots"]
## 몸 조각 — 입는 부위 셋 + 나머지
const BODY_PARTS := ["armor", "helmet", "boots", "rest"]
## 부위 → 뼈 (build-gear-parts.mjs 와 같다). 갑옷은 가중치 합 0.3, 나머지는 0.5 를 넘어야 한다
const ARMOR_BONES := ["Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm"]
const BOOTS_BONES := ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
const LOWER_BONES := ["Hips", "LeftUpLeg", "RightUpLeg"]
## 배를 덮는 허리선 — 골반 뼈 자리에서 이만큼 위. 아랫배는 허벅지 뼈에 주로 묶여 있어서
## 가중치만으로는 가슴과 반바지 사이가 비었다 (몸통 쪽 정점 가운데 이보다 위는 갑옷 몫)
const WAIST := 0.025

## 등급 → 부위 메시 {이름 → [ArrayMesh, Skin]}. 파일을 한 번만 연다
static var _parts := {}
## 몸 메시 → {뼈 이름 → [뼈 좌표 상자, 앞쪽]}. 오로라 자리를 잡는다 (`GearAura`)
static var _boxes := {}


## 부위 하나를 등급으로 입힌다. 0 이면 벗긴다(맨몸). 그 등급 모델이 없으면 맨몸 그대로 둔다
static func wear(rig: Node3D, slot: String, grade: int) -> void:
	var body := _body(rig)
	if body == null:
		return
	var pieces := _split(body)
	var holder := body.get_parent()
	var old := holder.get_node_or_null("Gear_" + slot)
	if old != null:
		holder.remove_child(old)
		old.queue_free()
	var part: Array = part_mesh(grade, slot) if grade > 0 else []
	if not part.is_empty():
		var node := MeshInstance3D.new()
		node.name = "Gear_" + slot
		node.mesh = part[0]
		node.skin = part[1]
		node.cast_shadow = body.cast_shadow
		holder.add_child(node)
		# 몸과 형제라 몸이 뼈대를 가리키는 상대 경로가 그대로 맞는다
		node.skeleton = body.skeleton
	# 입은 부위 아래 맨몸은 끈다
	var piece: MeshInstance3D = pieces.get(slot)
	if piece != null:
		piece.visible = part.is_empty()
	# 오로라 — 4등급부터, 고도 이펙트로 뼈 소켓에 붙인다
	GearAura.wear(rig, body, slot, grade)


## 그 등급·부위의 메시와 스킨. 파일이 없거나 그 부위가 없으면 []
static func part_mesh(grade: int, slot: String) -> Array:
	grade = clampi(grade, 1, 7)
	if not _parts.has(grade):
		_parts[grade] = {}
		var path := "%sgear_g%d.glb" % [DIR, grade]
		if ResourceLoader.exists(path):
			var scene: Node = (load(path) as PackedScene).instantiate()
			for node in scene.find_children("*", "MeshInstance3D", true, false):
				var mesh_node := node as MeshInstance3D
				_parts[grade][str(mesh_node.name)] = [mesh_node.mesh, mesh_node.skin]
			scene.free()
	return _parts[grade].get(slot, [])


## 몸을 부위 넷으로 나눠 몸 옆에 붙이고 원래 몸은 끈다. 한 번만 나눈다 → {부위 → MeshInstance3D}
static func _split(body: MeshInstance3D) -> Dictionary:
	var holder := body.get_parent()
	var found := {}
	for part in BODY_PARTS:
		var node := holder.get_node_or_null("Body_" + part)
		if node != null:
			found[part] = node
	if found.size() == BODY_PARTS.size():
		return found
	var meshes := split_meshes(body)
	for part in BODY_PARTS:
		var node := MeshInstance3D.new()
		node.name = "Body_" + part
		node.mesh = meshes[part]
		node.skin = body.skin
		node.cast_shadow = body.cast_shadow
		holder.add_child(node)
		node.skeleton = body.skeleton
		found[part] = node
	body.visible = false
	return found


## 몸 메시를 부위 넷으로 — 정점을 다시 번호 매겨 조각마다 제 정점만 가진다 (스키닝이 네 배가 되지 않게)
static func split_meshes(body: MeshInstance3D) -> Dictionary:
	var skin := body.skin
	var source := body.mesh as ArrayMesh
	var names := []
	var hips_y := 0.0
	for i in skin.get_bind_count():
		names.append(str(skin.get_bind_name(i)))
		if names[i] == "Hips":
			hips_y = skin.get_bind_pose(i).affine_inverse().origin.y
	var out := {}
	for part in BODY_PARTS:
		out[part] = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per := weights.size() / maxi(pos.size(), 1)
		# 정점마다 부위 — 투구 > 신발 > 갑옷 > 나머지
		var kind := PackedByteArray()
		kind.resize(pos.size())
		for v in pos.size():
			var head := 0.0
			var boots := 0.0
			var armor := 0.0
			var lower := 0.0
			for k in per:
				var w := weights[v * per + k]
				var bone_name: String = names[int(bones[v * per + k])]
				if bone_name == "Head":
					head += w
				elif bone_name in BOOTS_BONES:
					boots += w
				elif bone_name in ARMOR_BONES:
					armor += w
				elif bone_name in LOWER_BONES:
					lower += w
			if head > 0.5:
				kind[v] = 1
			elif boots > 0.5:
				kind[v] = 2
			elif armor > 0.3 or (armor + lower > 0.9 and pos[v].y - hips_y > WAIST):
				kind[v] = 0
			else:
				kind[v] = 3
		var material := source.surface_get_material(surface)
		for p in BODY_PARTS.size():
			var tris := PackedInt32Array()
			for t in range(0, indices.size() - 2, 3):
				# 세 정점이 다 그 부위면 그 조각, 부위가 섞인 삼각형은 나머지 조각
				var a := kind[indices[t]]
				var same := a == kind[indices[t + 1]] and a == kind[indices[t + 2]]
				if (same and a == p) or (not same and p == 3):
					tris.append(indices[t])
					tris.append(indices[t + 1])
					tris.append(indices[t + 2])
			if tris.is_empty():
				continue
			var cut := _compact(arrays, tris, pos.size())
			var mesh: ArrayMesh = out[BODY_PARTS[p]]
			var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cut, [], {}, flags)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return out


## 삼각형 목록이 쓰는 정점만 남긴 배열 — 정점마다 붙은 배열은 모두 같은 순서로 옮긴다
static func _compact(arrays: Array, tris: PackedInt32Array, count: int) -> Array:
	var remap := PackedInt32Array()
	remap.resize(count)
	remap.fill(-1)
	var keep := PackedInt32Array()
	var index := PackedInt32Array()
	index.resize(tris.size())
	for i in tris.size():
		var v := tris[i]
		if remap[v] < 0:
			remap[v] = keep.size()
			keep.append(v)
		index[i] = remap[v]
	var cut := []
	cut.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var src = arrays[slot]
		if src == null or slot == Mesh.ARRAY_INDEX:
			continue
		var size: int = src.size()
		if size == 0:
			continue
		var stride := size / count
		var dst = src.duplicate()
		dst.resize(keep.size() * stride)
		for i in keep.size():
			for k in stride:
				dst[i * stride + k] = src[keep[i] * stride + k]
		cut[slot] = dst
	cut[Mesh.ARRAY_INDEX] = index
	return cut


## 그 뼈에 0.5 넘게 묶인 정점의 상자(뼈 좌표)와 앞쪽 방향(뼈 좌표)
static func _box(body: MeshInstance3D, bone: String) -> Array:
	var key := body.mesh.get_instance_id()
	if not _boxes.has(key):
		_boxes[key] = _measure(body)
	return _boxes[key].get(bone, [AABB(Vector3(-0.03, 0, -0.03), Vector3(0.06, 0.1, 0.06)), Vector3.BACK])


static func _measure(body: MeshInstance3D) -> Dictionary:
	var skin := body.skin
	var source := body.mesh as ArrayMesh
	var boxes := {}
	var first := {}
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights.is_empty():
			continue
		var per := weights.size() / pos.size()
		for v in pos.size():
			for k in per:
				if weights[v * per + k] <= 0.5:
					continue
				var b := int(bones[v * per + k])
				var p := skin.get_bind_pose(b) * pos[v]
				if first.has(b):
					boxes[b] = (boxes[b] as AABB).expand(p)
				else:
					boxes[b] = AABB(p, Vector3.ZERO)
					first[b] = true
	var out := {}
	for b in boxes:
		# 모델의 앞(+Z)을 뼈 좌표로 — 바인드 자세의 뼈 회전을 되돌린다
		var front := (skin.get_bind_pose(b).basis * Vector3.BACK).normalized()
		out[str(skin.get_bind_name(b))] = [boxes[b], front]
	return out


## 원래 몸 메시 — 스킨이 붙은 것 중 가장 큰 것 (나눈 조각·입힌 부위는 빼고)
static func _body(rig: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var node_name := str(mesh_node.name)
		if mesh_node.skin == null or node_name.begins_with("Gear_") or node_name.begins_with("Body_"):
			continue
		if not (mesh_node.mesh is ArrayMesh):
			continue
		if best == null or mesh_node.mesh.get_aabb().size.length() > best.mesh.get_aabb().size.length():
			best = mesh_node
	return best
