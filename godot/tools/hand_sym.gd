extends SceneTree

## 트레이너 대기 자세의 **두 손을 좌우 대칭으로** 맞출 돌림을 잰다 (2026-10-07 — "지금 왼손이랑 오른손이랑 차렷 자세
## 위치가 다르자나? 그리고 이게 사람 손 이냐?").
##
## 둘이 어긋난 까닭이 둘이었다:
##   · **주먹 방향** — `fist_twist.gd` 는 마디 줄(앞뒤 없는 축)만 맞춰서, 한 손은 손등이 밖을, 다른 손은 손바닥이 밖을
##     볼 수 있었다 (n03 비틀기가 왼 −75 · 오른 −40 — 거울이면 부호가 반대여야 한다).
##   · **손 자리** — 바르코 대기가 몸통을 살짝 비틀고 어깨를 다르게 둬서, 골반 기준 손목이 왼쪽만 15% 바깥에 있었다.
## 그래서 대기 0.5초에서
##   1. 골반 기준 두 손목 자리를 **왼쪽과 오른쪽 거울(x 뒤집기)의 평균**으로 옮기도록 윗팔을 돌리고(R),
##   2. **오른손을 기준으로**, 왼손 메시 점들이 오른손 메시를 거울한 것과 가장 잘 겹치는(Chamfer) 아래팔 비틀기를
##      −180 ~ 175° 에서 5° 씩 찾는다 — 축이 아니라 모양을 대므로 손바닥·손등이 뒤집히지 않는다.
## 지금 모델(`trainer-arms.mjs` 를 다 입은 것) 위에서 잰다. 1 은 대기에만, 2 는 `twist[0]` 에 더해 모든 클립에.
##
##   godot --headless --path godot --script tools/hand_sym.gd -- n01 n02 …
##   → SYM {"n01": {"LeftArm": [x, y, z, 도], "RightArm": […], "twistL": 도}, …}
##     GAP {"n01": [손목 어긋남 %, 맞추기 전 겹침, 맞춘 뒤 겹침]}

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := {}
	var gap := {}
	for id in OS.get_cmdline_user_args():
		var rig := Rig.create(Trainers.look(str(id)), 1.8)
		if rig == null:
			continue
		root.add_child(rig)
		await process_frame
		rig._anim.play("Idle")
		rig._anim.seek(0.5, true)
		rig._anim.pause()
		var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		var mi: MeshInstance3D = rig.find_children("*", "MeshInstance3D", true, false)[0]
		var entry := {}
		# 1. 손목 자리
		var hips := sk.get_bone_global_pose(sk.find_bone("Hips"))
		var wl := hips.affine_inverse() * _origin(sk, "LeftHand")
		var wr := hips.affine_inverse() * _origin(sk, "RightHand")
		var off := (wl - _mirror(wr)).length() / maxf(0.001, wl.length())
		var target_l := (wl + _mirror(wr)) * 0.5
		for side in ["Left", "Right"]:
			var arm := sk.find_bone(side + "Arm")
			var shoulder := _origin(sk, side + "Arm")
			var target: Vector3 = hips * (target_l if side == "Left" else _mirror(target_l))
			var swing := _swing(_origin(sk, side + "Hand") - shoulder, target - shoulder)
			var local := _local_quat(sk, arm, swing)
			entry[side + "Arm"] = _pack(local)
			sk.set_bone_pose_rotation(arm, sk.get_bone_pose_rotation(arm) * local)
		# 2. 왼손 비틀기 — 오른손 거울과 겹치게
		var clouds := _hand_points(mi)
		var right := _world(sk, clouds.Right, "RightHand", hips, true)
		var fore := sk.find_bone("LeftForeArm")
		var q := sk.get_bone_pose_rotation(fore)
		var best := 0.0
		var best_d := INF
		var start_d := 0.0
		for step in 72:
			var deg := -180.0 + step * 5.0
			sk.set_bone_pose_rotation(fore, q * Quaternion(Vector3.UP, deg_to_rad(deg)))
			var d := _chamfer(_world(sk, clouds.Left, "LeftHand", hips, false), right)
			if deg == 0.0:
				start_d = d
			if d < best_d:
				best_d = d
				best = deg
		sk.set_bone_pose_rotation(fore, q)
		entry["twistL"] = best
		out[str(id)] = entry
		gap[str(id)] = [snappedf(off * 100.0, 0.1), snappedf(start_d * 100.0, 0.01), snappedf(best_d * 100.0, 0.01)]
		rig.queue_free()
		await process_frame
	print("SYM " + JSON.stringify(out))
	print("GAP " + JSON.stringify(gap))
	quit(0)


func _origin(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## 손·손가락 뼈에 가장 크게 묶인 정점을 손 뼈 기준으로 — {"Left": [[뼈 이름, 점], …], "Right": …}
func _hand_points(mi: MeshInstance3D) -> Dictionary:
	var skin := mi.skin
	var side_of := {}
	for i in skin.get_bind_count():
		var n := skin.get_bind_name(i)
		if n == "LeftHand" or n.begins_with("HandLoRA_Bip01_L_"):
			side_of[i] = "Left"
		elif n == "RightHand" or n.begins_with("HandLoRA_Bip01_R_"):
			side_of[i] = "Right"
	var out := {"Left": [], "Right": []}
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, verts.size())
		for v in range(0, verts.size(), 2):
			var top := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + top]:
					top = k
			var b := bones[v * per + top]
			if side_of.has(b) and weights[v * per + top] > 0.5:
				out[side_of[b]].append([skin.get_bind_name(b), skin.get_bind_pose(b) * verts[v]])
	return out


## 지금 자세의 점들을 골반 기준 · 손목 원점으로 (거울이면 x 뒤집기)
func _world(sk: Skeleton3D, cloud: Array, wrist: String, hips: Transform3D, mirror: bool) -> PackedVector3Array:
	var inv := hips.affine_inverse()
	var w := inv * _origin(sk, wrist)
	var out := PackedVector3Array()
	for item in cloud:
		var p: Vector3 = inv * (sk.get_bone_global_pose(sk.find_bone(item[0])) * item[1]) - w
		out.append(_mirror(p) if mirror else p)
	return out


## 평균 최근접 거리 (a → b)
func _chamfer(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var sum := 0.0
	for p in a:
		var near := INF
		for r in b:
			near = minf(near, p.distance_squared_to(r))
		sum += sqrt(near)
	return sum / maxf(1.0, a.size())


func _swing(a: Vector3, b: Vector3) -> Quaternion:
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), a.angle_to(b))


## 뼈대 기준 돌림 → 그 뼈의 로컬 돌림 (`G⁻¹ · R · G`)
func _local_quat(sk: Skeleton3D, bone: int, r: Quaternion) -> Quaternion:
	var g := sk.get_bone_global_pose(bone).basis.orthonormalized().get_rotation_quaternion()
	return g.inverse() * r * g


func _pack(q: Quaternion) -> Array:
	var angle := rad_to_deg(q.get_angle())
	if angle < 0.01:
		return [0, 1, 0, 0]
	var axis := q.get_axis()
	return [snappedf(axis.x, 0.0001), snappedf(axis.y, 0.0001), snappedf(axis.z, 0.0001), snappedf(angle, 0.01)]
