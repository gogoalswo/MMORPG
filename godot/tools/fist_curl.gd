extends SceneTree

## 트레이너 주먹을 **꽉 쥐게** 손가락 마디를 굽힐 축을 잰다 (2026-10-07 — "이게 사람 손 이냐?").
##
## 바르코가 조각한 주먹은 손가락 끝이 손바닥에 닿지 않고 C 자로 떠 있어서, 가까이 보면 가운데가 뚫린 갈퀴 손이었다.
## 그래서 검지~새끼(Finger1~4)의 마디 셋을 손바닥 쪽으로 더 굽힌다. 굽힐 축은 손가락 리깅마다 달라서 **메시로** 고른다:
## 마디 방향에 수직인 축 36개 가운데, 그 마디부터 끝까지의 정점 무게중심을 30° 돌렸을 때 **손바닥(손 뼈에 묶인 정점의
## 무게중심)에 가장 가까워지는** 축. 각도는 `trainer-arms.mjs` 의 CURL 이다.
##
##   godot --headless --path godot --script tools/fist_curl.gd -- n01 n02 …
##   → CURL {"n01": {"HandLoRA_Bip01_L_Finger1": [x, y, z], …}, …}   (뼈 로컬 축)

const SEGS := ["", "1", "2"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := {}
	for id in OS.get_cmdline_user_args():
		var rig := Rig.create(Trainers.look(str(id)), 1.8)
		if rig == null:
			continue
		root.add_child(rig)
		await process_frame
		var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		var mi: MeshInstance3D = rig.find_children("*", "MeshInstance3D", true, false)[0]
		var pts := _points(mi, sk)
		var entry := {}
		for s in ["L", "R"]:
			var palm := _centroid(pts.get(("Left" if s == "L" else "Right") + "Hand", []))
			for f in range(1, 5):
				for k in SEGS.size():
					var name := "HandLoRA_Bip01_%s_Finger%d%s" % [s, f, SEGS[k]]
					var bone := sk.find_bone(name)
					var origin := sk.get_bone_global_pose(bone).origin
					var distal: Array = []
					for j in range(k, SEGS.size()):
						distal.append_array(pts.get("HandLoRA_Bip01_%s_Finger%d%s" % [s, f, SEGS[j]], []))
					if distal.is_empty():
						continue
					var tip := _centroid(distal)
					var dir := (tip - origin).normalized()
					var u := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
					var best := Vector3.ZERO
					var best_d := INF
					for step in 36:
						var axis := u.rotated(dir, TAU * step / 36.0)
						var moved := origin + (tip - origin).rotated(axis, deg_to_rad(30.0))
						var d := moved.distance_to(palm)
						if d < best_d:
							best_d = d
							best = axis
					var local := sk.get_bone_global_pose(bone).basis.orthonormalized().inverse() * best
					entry[name] = [snappedf(local.x, 0.0001), snappedf(local.y, 0.0001), snappedf(local.z, 0.0001)]
		out[str(id)] = entry
		rig.queue_free()
		await process_frame
	print("CURL " + JSON.stringify(out))
	quit(0)


## 뼈 이름 → 그 뼈에 가장 크게 묶인 정점들(지금 자세, 뼈대 기준)
func _points(mi: MeshInstance3D, sk: Skeleton3D) -> Dictionary:
	var skin := mi.skin
	var out := {}
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, verts.size())
		for v in verts.size():
			var top := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + top]:
					top = k
			if weights[v * per + top] < 0.5:
				continue
			var name := skin.get_bind_name(bones[v * per + top])
			if not (name.ends_with("Hand") or name.begins_with("HandLoRA_")):
				continue
			var p := sk.get_bone_global_pose(sk.find_bone(name)) * (skin.get_bind_pose(bones[v * per + top]) * verts[v])
			if not out.has(name):
				out[name] = []
			out[name].append(p)
	return out


func _centroid(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / maxf(1.0, points.size())
