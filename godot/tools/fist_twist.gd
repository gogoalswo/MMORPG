extends SceneTree

## 트레이너마다 **주먹을 얼마나 비틀지** 잰다 (2026-10-07 — "첫 번째 스샷(n03)은 주먹 방향이 이상해. 두 번째(n01)처럼").
##
## 주먹은 원화대로 조각돼서 아래팔에 붙은 방향이 모델마다 다르다. 그래서 모두 ±60° 로 비틀면 어떤 모델은 n01 과
## 딴 데를 본다. 여기서는 **메시 모양**으로 주먹 방향을 잰다:
##   1. 손 뼈에 가장 크게 묶인 정점(= 주먹)을 바인드 자세에서 손 뼈 기준으로 옮기고,
##   2. 손 길이 축(로컬 Y)에 수직인 면(XZ)에서 **가장 넓게 퍼진 방향** = 손가락 마디 줄(검지~새끼)을 구한다
##      (주먹은 두께보다 폭이 넓다). 손가락 뼈를 안 쓰므로 손가락 리깅이 뭉개진 모델도 잰다.
##   3. 대기 0.5초 자세에서 그 마디 줄의 방향을, n01 을 사용자가 고른 각도(왼 −60 · 오른 +60)로 비틀었을 때와
##      가장 가깝게 하는 아래팔 비틀기를 **−90 ~ 85°** 에서 5° 씩 찾는다 (마디 줄은 앞뒤가 없는 축이라 180° 마다
##      되풀이된다 — 그 안에서 고르면 손목이 꽈배기가 되는 큰 비틀기를 피한다).
## 모델은 비틀기 **전** 상태여야 한다 (`trainer-arms.mjs --no-twist`).
##
##   godot --headless --path godot --script tools/fist_twist.gd -- n01 n02 …
##   → TWIST {"n01": [-60, 60], "n02": [왼, 오른], …}   SCORE {…: [|cos|, |cos|]}

const REF := "n01"
const REF_TWIST := {"Left": -60.0, "Right": 60.0}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var ref := await _pose(REF)
	var target := {}
	for side in ["Left", "Right"]:
		target[side] = _knuckles(ref, side, _knuckle_local(ref, side), REF_TWIST[side])
	ref.queue_free()
	var out := {}
	var score := {}
	for id in ids:
		var rig := await _pose(str(id))
		if rig == null:
			continue
		var pair := []
		var cos := []
		for side in ["Left", "Right"]:
			var local := _knuckle_local(rig, side)
			var best := 0.0
			var best_dot := -1.0
			for step in 36:
				var deg := -90.0 + step * 5.0
				var dot := absf(_knuckles(rig, side, local, deg).dot(target[side]))
				if dot > best_dot:
					best_dot = dot
					best = deg
			pair.append(best)
			cos.append(snappedf(best_dot, 0.01))
		out[str(id)] = pair
		score[str(id)] = cos
		rig.queue_free()
		await process_frame
	print("TWIST " + JSON.stringify(out))
	print("SCORE " + JSON.stringify(score))
	quit(0)


func _pose(id: String) -> Rig:
	var rig := Rig.create(Trainers.look(id), 1.8)
	if rig == null:
		return null
	root.add_child(rig)
	await process_frame
	rig._anim.play("Idle")
	rig._anim.seek(0.5, true)
	rig._anim.pause()
	return rig


## 손 뼈 기준 손가락 마디 줄 방향 (XZ 면 위 단위 벡터) — 주먹 정점의 XZ 퍼짐 주축
func _knuckle_local(rig: Rig, side: String) -> Vector3:
	var mi: MeshInstance3D = rig.find_children("*", "MeshInstance3D", true, false)[0]
	var skin := mi.skin
	var hand_bind := -1
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == side + "Hand":
			hand_bind = i
	var to_hand := skin.get_bind_pose(hand_bind)
	var points: Array = []
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
			if bones[v * per + top] == hand_bind and weights[v * per + top] > 0.5:
				points.append(to_hand * verts[v])
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= maxf(1.0, points.size())
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for p in points:
		var d: Vector3 = p - mean
		sxx += d.x * d.x
		szz += d.z * d.z
		sxz += d.x * d.z
	# 2×2 대칭 행렬의 큰 고유벡터 방향
	var angle := 0.5 * atan2(2.0 * sxz, sxx - szz)
	return Vector3(cos(angle), 0.0, sin(angle))


## 아래팔을 `deg` 만큼 더 비틀었을 때 뼈대 기준 마디 줄 방향 — 끝나면 원래대로 돌려 놓는다
func _knuckles(rig: Rig, side: String, local: Vector3, deg: float) -> Vector3:
	var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var arm := sk.find_bone(side + "ForeArm")
	var hand := sk.find_bone(side + "Hand")
	var q := sk.get_bone_pose_rotation(arm)
	sk.set_bone_pose_rotation(arm, q * Quaternion(Vector3.UP, deg_to_rad(deg)))
	var basis := sk.get_bone_global_pose(hand).basis.orthonormalized()
	sk.set_bone_pose_rotation(arm, q)
	return (basis * local).normalized()
