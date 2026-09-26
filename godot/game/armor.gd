class_name Armor
extends RefCounted

## 갑옷·투구·신발을 **몸에 입힌다** — 장비 칸의 등급이 바뀌면 그 부위의 스킨이 바뀐다.
##
## 뼈에 딱딱한 도형을 붙이지 않는다. 몸 메시에서 **그 부위의 삼각형만 떼어** 법선 쪽으로
## 조금 부풀린 껍데기를 만들고, 같은 뼈대·같은 스킨에 묶는다 — 그래서 달리고 차는 동안
## 몸과 같이 휘고, 모델을 갈아 끼워도 잰 수치가 없다. 어느 삼각형이 어느 부위인지는
## **뼈 가중치**가 정한다 (`BONES` 에 든 뼈에 0.5 넘게 묶인 정점).
##
## 껍데기 모양은 부위마다 한 번만 짓고(`_shells` 캐시), 등급은 **재질**과 뼈에 붙이는
## **장식**(보석·가시·고리)만 바꾼다. 색은 건틀릿(`Gauntlet`)과 같은 등급 색이다 —
## 붕대 → 가죽 → 은 → 보라 쇠 → 금 → 검은 쇠 → 흰빛.
## → docs/features/characters-and-animation.md "장비 스킨"

## 부위 → 덮는 뼈
const BONES := {
	"armor": ["Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm"],
	"helmet": ["Head"],
	"boots": ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"],
}
const SLOTS := ["armor", "helmet", "boots"]
## 그 부위 뼈에 묶인 가중치 합이 이만큼 넘는 정점만 덮는다. 갑옷은 배까지 덮으려고 낮췄다 —
## 배는 몸통 뼈와 골반 뼈에 반반 묶여 있어서 0.5 로는 가슴과 반바지 사이가 비었다
const COVER := {"armor": 0.3, "helmet": 0.5, "boots": 0.5}
## 법선 쪽으로 부풀리는 두께 (모델 단위 — 게임에서 1.85배쯤 커진다. 0.006 ≈ 1.1cm)
const PUSH := {"armor": 0.007, "helmet": 0.009, "boots": 0.007}
## 껍데기를 몇 번 펴나 — 근육·머리카락 굴곡을 죽여 판처럼 보이게 (`_smooth`)
const SMOOTH := {"armor": 8, "helmet": 6, "boots": 6}
## 투구는 얼굴을 덮지 않는다 — 머리 뼈 좌표로 이마 위(`BROW`)와 뒤통수(`BACK`)만 덮는다.
## 앞이 +Z 다 (모델이 +Z 를 본다)
const HELMET_BROW := 0.058
const HELMET_BACK := -0.012

## 등급 재질 — [색, 금속성, 거칠기, 빛 색, 빛 세기]. 건틀릿과 같은 색이다
const LOOK := {
	1: [Color("#e6dcc3"), 0.0, 1.0, Color.BLACK, 0.0],
	2: [Color("#4a2616"), 0.0, 0.6, Color.BLACK, 0.0],
	3: [Color("#c9ced6"), 0.9, 0.3, Color.BLACK, 0.0],
	4: [Color("#3b3450"), 0.85, 0.35, Color.BLACK, 0.0],
	5: [Color("#d98a2b"), 0.9, 0.3, Color.BLACK, 0.0],
	6: [Color("#1b1818"), 0.8, 0.45, Color.BLACK, 0.0],
	7: [Color("#f6f2e6"), 0.3, 0.3, Color("#fff6dc"), 0.2],
}
## 장식 색 — 테두리·보석
const TRIM := {
	1: Color("#a8987a"), 2: Color("#3f2716"), 3: Color("#7d848f"), 4: Color("#8c7ab8"),
	5: Color("#8a3a18"), 6: Color("#ff3a1a"), 7: Color("#ffd27a"),
}

## 몸 메시 → {부위 → ArrayMesh}. 등급을 바꿀 때마다 다시 떼지 않는다
static var _shells := {}
## 몸 메시 → {뼈 이름 → [뼈 좌표 상자 AABB, 앞쪽 방향]}. 장식 자리를 잡는다
static var _boxes := {}
static var _mats := {}


## 부위 하나를 등급으로 입힌다. 0 이면 벗긴다(맨몸). 몸 메시·뼈가 없으면 조용히 넘어간다
static func wear(rig: Node3D, slot: String, grade: int) -> void:
	var body := _body(rig)
	if body == null:
		return
	var shell := body.get_parent().get_node_or_null("Gear_" + slot) as MeshInstance3D
	if shell == null:
		var mesh := shell_mesh(body, slot)
		if mesh == null:
			return
		shell = MeshInstance3D.new()
		shell.name = "Gear_" + slot
		shell.mesh = mesh
		shell.skin = body.skin
		shell.cast_shadow = body.cast_shadow
		body.get_parent().add_child(shell)
		# 몸과 형제라 몸이 뼈대를 가리키는 상대 경로가 그대로 맞는다
		shell.skeleton = body.skeleton
	shell.visible = grade > 0
	if grade > 0:
		shell.material_override = material(grade)
	_decorate(rig, body, slot, grade)


## 등급 재질 (등급마다 한 벌을 나눠 쓴다)
static func material(grade: int) -> StandardMaterial3D:
	grade = clampi(grade, 1, 7)
	if _mats.has(grade):
		return _mats[grade]
	var look: Array = LOOK[grade]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = look[0]
	mat.metallic = look[1]
	mat.roughness = look[2]
	if float(look[4]) > 0.0:
		mat.emission_enabled = true
		mat.emission = look[3]
		mat.emission_energy_multiplier = look[4]
	_mats[grade] = mat
	return mat


## 부위 껍데기 — 몸 메시에서 그 부위 삼각형을 떼어 부풀린 것. 몸이 스킨이 아니면 null
static func shell_mesh(body: MeshInstance3D, slot: String) -> ArrayMesh:
	var key := body.mesh.get_instance_id()
	if _shells.has(key) and _shells[key].has(slot):
		return _shells[key][slot]
	var mesh := _cut(body, slot)
	if not _shells.has(key):
		_shells[key] = {}
	_shells[key][slot] = mesh
	return mesh


static func _cut(body: MeshInstance3D, slot: String) -> ArrayMesh:
	var skin := body.skin
	var source := body.mesh as ArrayMesh
	if skin == null or source == null:
		return null
	# 스킨 인덱스 → 이 부위 뼈인가
	var wanted: Array = BONES[slot]
	var bind_in := PackedByteArray()
	bind_in.resize(skin.get_bind_count())
	var head := -1
	for i in skin.get_bind_count():
		var bone_name := str(skin.get_bind_name(i))
		bind_in[i] = 1 if bone_name in wanted else 0
		if bone_name == "Head":
			head = i

	var out := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights.is_empty():
			continue
		var per := weights.size() / pos.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(pos.size())
			for i in pos.size():
				indices[i] = i
		# 정점마다 — 이 부위 뼈에 묶인 가중치 합이 절반을 넘는가
		var inside := PackedByteArray()
		inside.resize(pos.size())
		for v in pos.size():
			var sum := 0.0
			var on_head := 0.0
			for k in per:
				var w := weights[v * per + k]
				var b := int(bones[v * per + k])
				if bind_in[b]:
					sum += w
				if b == head:
					on_head += w
			var yes := sum > float(COVER[slot])
			if yes and slot == "helmet" and on_head > 0.5:
				# 머리 뼈 좌표로 옮겨 얼굴을 걸러 낸다
				var local := skin.get_bind_pose(head) * pos[v]
				yes = local.y > HELMET_BROW or local.z < HELMET_BACK
			inside[v] = 1 if yes else 0

		# 세 정점이 다 들어온 삼각형만 — 새 번호를 매겨 옮긴다
		var remap := PackedInt32Array()
		remap.resize(pos.size())
		remap.fill(-1)
		var new_pos := PackedVector3Array()
		var new_normal := PackedVector3Array()
		var new_bones := PackedInt32Array()
		var new_weights := PackedFloat32Array()
		var new_index := PackedInt32Array()
		var push: float = PUSH[slot]
		for t in range(0, indices.size() - 2, 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if not (inside[a] and inside[b] and inside[c]):
				continue
			for v in [a, b, c]:
				if remap[v] < 0:
					remap[v] = new_pos.size()
					new_pos.append(pos[v])
					for k in per:
						new_bones.append(int(bones[v * per + k]))
						new_weights.append(weights[v * per + k])
				new_index.append(remap[v])
		if new_index.is_empty():
			continue
		# 근육 굴곡을 죽여 판처럼 — 편 다음 새 법선 쪽으로 부풀린다
		var smoothed := _smooth(new_pos, new_index, SMOOTH[slot])
		new_pos = smoothed[0]
		new_normal = smoothed[1]
		for v in new_pos.size():
			new_pos[v] += new_normal[v] * push
		var cut := []
		cut.resize(Mesh.ARRAY_MAX)
		cut[Mesh.ARRAY_VERTEX] = new_pos
		cut[Mesh.ARRAY_NORMAL] = new_normal
		cut[Mesh.ARRAY_BONES] = new_bones
		cut[Mesh.ARRAY_WEIGHTS] = new_weights
		cut[Mesh.ARRAY_INDEX] = new_index
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cut, [], {}, flags)
	return out if out.get_surface_count() > 0 else null


## 껍데기를 편다 (Taubin — 줄었다 늘었다 하며 부피를 지킨다). 몸 메시는 UV 이음새마다
## 정점이 갈라져 있어서, **같은 자리 정점을 한 점으로 묶어** 편다 — 안 그러면 이음새가 벌어진다.
## 가장자리(한 삼각형에만 쓰인 변) 점은 그대로 둔다. 돌려주는 것: [자리, 법선]
static func _smooth(pos: PackedVector3Array, index: PackedInt32Array, rounds: int) -> Array:
	# 같은 자리 → 한 점
	var ids := {}
	var point := PackedInt32Array()
	point.resize(pos.size())
	var at := PackedVector3Array()
	for v in pos.size():
		var key := Vector3i((pos[v] * 100000.0).round())
		if not ids.has(key):
			ids[key] = at.size()
			at.append(pos[v])
		point[v] = ids[key]
	# 이웃과 가장자리
	var near := []
	near.resize(at.size())
	for p in at.size():
		near[p] = {}
	var edges := {}
	for t in range(0, index.size() - 2, 3):
		for e in 3:
			var a := point[index[t + e]]
			var b := point[index[t + (e + 1) % 3]]
			near[a][b] = true
			near[b][a] = true
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = int(edges.get(key, 0)) + 1
	var rim := PackedByteArray()
	rim.resize(at.size())
	for key in edges:
		if edges[key] == 1:
			rim[key.x] = 1
			rim[key.y] = 1
	for round in rounds:
		for step in [0.5, -0.53]:
			var moved := at.duplicate()
			for p in at.size():
				if rim[p] or near[p].is_empty():
					continue
				var mean := Vector3.ZERO
				for q in near[p]:
					mean += at[q]
				mean /= near[p].size()
				moved[p] = at[p] + (mean - at[p]) * step
			at = moved
	# 면 법선을 모아 점 법선으로
	var normal := PackedVector3Array()
	normal.resize(at.size())
	for t in range(0, index.size() - 2, 3):
		var a := point[index[t]]
		var b := point[index[t + 1]]
		var c := point[index[t + 2]]
		# 고도는 시계 방향 감김이 앞면이라 (c-a)×(b-a) 가 바깥이다
		var face := (at[c] - at[a]).cross(at[b] - at[a])
		normal[a] += face
		normal[b] += face
		normal[c] += face
	var out_pos := PackedVector3Array()
	var out_normal := PackedVector3Array()
	out_pos.resize(pos.size())
	out_normal.resize(pos.size())
	for v in pos.size():
		out_pos[v] = at[point[v]]
		out_normal[v] = normal[point[v]].normalized()
	return [out_pos, out_normal]


# ─── 장식 ─────────────────────────────────────────────────
# 껍데기만으로는 은 갑옷과 은빛 페인트가 구별이 안 된다. 등급이 오를수록 뼈에 붙는
# 조각이 는다 — 어깨받이(3~) · 가슴·이마 보석(4~) · 가시(5~6) · 떠 있는 고리(7).
# 자리는 **그 뼈에 묶인 정점의 상자**(`_box`)와 **앞쪽**(모델 +Z 를 뼈 좌표로 옮긴 것)으로 잡는다.

static func _decorate(rig: Node3D, body: MeshInstance3D, slot: String, grade: int) -> void:
	var sockets := _decor_bones(slot)
	for bone in sockets:
		var socket: BoneAttachment3D = rig.fist_socket(bone)
		if socket == null:
			continue
		var old := socket.get_node_or_null("GearDecor_" + slot)
		if old != null:
			socket.remove_child(old)
			old.queue_free()
	if grade < 3:
		return
	var trim := _plain(TRIM[grade], 0.9, 0.3, grade >= 4)
	var base := material(grade)
	match slot:
		"armor":
			for bone in ["LeftArm", "RightArm"]:
				var holder := _holder(rig, bone, slot)
				if holder == null:
					continue
				# 어깨받이 — 위팔 뿌리를 덮는 반구. 크기는 위팔 굵기에서
				var box := _box(body, bone)
				var r := maxf(box[0].size.x, box[0].size.z) * 0.62
				var pad := _part(holder, _sphere(r), base, Vector3(0, r * 0.35, 0))
				pad.scale = Vector3(1.0, 0.7, 1.0)
				if grade in [5, 6]:
					_spike(holder, trim if grade == 6 else base, Vector3(0, r * 0.9, 0), Vector3.UP, r * 0.9)
			if grade >= 4:
				var chest := _holder(rig, "Spine1", slot)
				if chest != null:
					var box := _box(body, "Spine1")
					var front: Vector3 = box[1]
					var at: Vector3 = box[0].get_center() + front * _reach(box[0], front) + front * 0.012
					_part(chest, _sphere(0.02), _gem(grade), at)
			if grade == 7:
				var back := _holder(rig, "Spine2", slot)
				if back != null:
					var box := _box(body, "Spine1")
					var ring := _part(back, _ring(0.075, 0.005), trim, -box[1] * 0.13 + Vector3(0, 0.05, 0))
					ring.basis = Basis.looking_at(box[1], Vector3.UP)
		"helmet":
			var holder := _holder(rig, "Head", slot)
			if holder == null:
				return
			var box := _box(body, "Head")
			var front: Vector3 = box[1]
			var top := Vector3(0, box[0].end.y, 0) + Vector3(box[0].get_center().x, 0, box[0].get_center().z)
			# 이마 테 — 투구 가장자리를 따라 두른다
			var band := _part(holder, _ring(box[0].size.x * 0.52, 0.006), trim, Vector3(box[0].get_center().x, HELMET_BROW, box[0].get_center().z))
			band.scale = Vector3(1.0, 1.0, box[0].size.z / box[0].size.x)
			if grade >= 4:
				_part(holder, _sphere(0.014), _gem(grade), Vector3(0, HELMET_BROW + 0.012, 0) + front * (_reach(box[0], front) + 0.004))
			if grade in [5, 6]:
				# 뿔 둘 — 정수리 양옆에서 비스듬히
				for side in [-1.0, 1.0]:
					var dir := (Vector3.UP * 0.8 + Vector3(side, 0, 0) * 0.6 - front * 0.2).normalized()
					_spike(holder, trim if grade == 6 else base, top + Vector3(side * box[0].size.x * 0.3, -0.02, 0), dir, 0.06)
			if grade == 7:
				_part(holder, _ring(0.06, 0.005), trim, top + Vector3(0, 0.045, 0))
		"boots":
			for bone in ["LeftLeg", "RightLeg"]:
				var holder := _holder(rig, bone, slot)
				if holder == null:
					continue
				var box := _box(body, bone)
				var front: Vector3 = box[1]
				# 무릎받이 — 정강이 뼈 뿌리(무릎) 앞
				var knee := front * (_reach(box[0], front) + 0.004) + Vector3(0, 0.012, 0)
				var cap := _part(holder, _sphere(0.034), base, knee)
				cap.basis = Basis.looking_at(front, Vector3.UP).scaled(Vector3(1.0, 1.0, 0.55))
				if grade >= 4:
					_part(holder, _sphere(0.012), _gem(grade), knee + front * 0.018)
				if grade in [5, 6]:
					_spike(holder, trim if grade == 6 else base, knee + front * 0.01, front, 0.04)


static func _decor_bones(slot: String) -> Array:
	match slot:
		"armor":
			return ["LeftArm", "RightArm", "Spine1", "Spine2"]
		"helmet":
			return ["Head"]
		"boots":
			return ["LeftLeg", "RightLeg"]
	return []


## 뼈 소켓 안의 부위 묶음. 뼈가 없으면 null
static func _holder(rig: Node3D, bone: String, slot: String) -> Node3D:
	var socket: BoneAttachment3D = rig.fist_socket(bone)
	if socket == null:
		return null
	var holder := Node3D.new()
	holder.name = "GearDecor_" + slot
	socket.add_child(holder)
	return holder


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


## 상자 가운데에서 `dir` 쪽 겉면까지의 거리
static func _reach(box: AABB, dir: Vector3) -> float:
	var half := box.size * 0.5
	return absf(dir.x) * half.x + absf(dir.y) * half.y + absf(dir.z) * half.z


## 몸 메시 — 스킨이 붙은 것 중 가장 큰 것
static func _body(rig: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.skin == null or mesh_node.name.begins_with("Gear_") or not (mesh_node.mesh is ArrayMesh):
			continue
		if best == null or mesh_node.mesh.get_aabb().size.length() > best.mesh.get_aabb().size.length():
			best = mesh_node
	return best


static func _gem(grade: int) -> StandardMaterial3D:
	var glow: Color = {4: Color("#b85cff"), 5: Color("#ffb347"), 6: Color("#ff2a10"), 7: Color("#fff1c0")}.get(grade, Color("#b85cff"))
	return _plain(glow, 0.2, 0.1, true)


static func _plain(color: Color, metal: float, rough: float, glow: bool) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.6
	_mats[key] = mat
	return mat


static func _spike(root: Node3D, mat: Material, at: Vector3, dir: Vector3, length: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = length * 0.28
	cone.height = length
	cone.radial_segments = 10
	var node := _part(root, cone, mat, at + dir.normalized() * length * 0.5)
	node.basis = _up_to(dir)


## +Y 를 `dir` 로 돌리는 기저
static func _up_to(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length() < 1e-4:
		return Basis() if d.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(d))


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


static func _ring(radius: float, thick: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thick
	torus.outer_radius = radius + thick
	torus.rings = 24
	torus.ring_segments = 6
	return torus
