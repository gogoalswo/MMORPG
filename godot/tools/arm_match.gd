extends SceneTree

## 트레이너마다 **대기 자세의 윗팔·아래팔 방향을 n01 과 같게** 맞출 돌림을 잰다 (2026-10-07).
##
## "첫 번째 스샷(n03)은 주먹 방향이 이상해. 두 번째(n01)처럼" — 바르코 대기 동작을 모델마다 옮겨 붙이면 팔꿈치를 굽히는
## 정도가 모델마다 달라서(n03 은 아래팔이 거의 수평), 같은 비틀기를 줘도 주먹이 딴 데를 봤다. 그래서 대기 0.5초에서
##   1. 윗팔 방향(어깨 → 팔꿈치)을 n01 과 같게 하는 돌림 R1 을 윗팔에,
##   2. 그 뒤 아래팔 방향(팔꿈치 → 손목)을 n01 과 같게 하는 돌림 R2 를 아래팔에
## 준다. 둘 다 **뼈 로컬 축 + 각도**로 바꿔 낸다 — `rotate-bones.mjs` 가 대기 클립 키마다 곱한다(`q' = q · r`).
## n01 은 이미 사용자가 고른 자세(`trainer-arms.mjs` 의 벌림·굽힘)를 입은 것을 과녁으로 쓴다. 다른 모델도 같은 벌림·굽힘을
## 입은 뒤에 잰다(그래야 맞춘 돌림이 작다).
##
##   godot --headless --path godot --script tools/arm_match.gd -- n02 n03 …
##   → MATCH {"n02": {"LeftArm": [x, y, z, 도], "LeftForeArm": […], "RightArm": …, "RightForeArm": …}, …}

const REF := "n01"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var ref := await _pose(REF)
	var target := {}
	for side in ["Left", "Right"]:
		target[side] = _dirs(ref, side)
	ref.queue_free()
	var out := {}
	for id in ids:
		var rig := await _pose(str(id))
		if rig == null:
			continue
		var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		var entry := {}
		for side in ["Left", "Right"]:
			var arm := sk.find_bone(side + "Arm")
			var fore := sk.find_bone(side + "ForeArm")
			var now: Array = _dirs(rig, side)
			# 1. 윗팔
			var r1 := _swing(now[0], target[side][0])
			entry[side + "Arm"] = _local(sk, arm, r1)
			sk.set_bone_pose_rotation(arm, sk.get_bone_pose_rotation(arm) * _local_quat(sk, arm, r1))
			# 2. 아래팔 (윗팔을 돌린 뒤에 다시 잰다)
			now = _dirs(rig, side)
			var r2 := _swing(now[1], target[side][1])
			entry[side + "ForeArm"] = _local(sk, fore, r2)
		out[str(id)] = entry
		rig.queue_free()
		await process_frame
	print("MATCH " + JSON.stringify(out))
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


## [윗팔 방향, 아래팔 방향] — 뼈대 기준, 단위 벡터
func _dirs(rig: Rig, side: String) -> Array:
	var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var shoulder := sk.get_bone_global_pose(sk.find_bone(side + "Arm")).origin
	var elbow := sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).origin
	var wrist := sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
	return [(elbow - shoulder).normalized(), (wrist - elbow).normalized()]


## a 를 b 로 돌리는 가장 짧은 돌림 (뼈대 기준)
func _swing(a: Vector3, b: Vector3) -> Quaternion:
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), a.angle_to(b))


## 뼈대 기준 돌림 → 그 뼈의 로컬 돌림 (`G⁻¹ · R · G`)
func _local_quat(sk: Skeleton3D, bone: int, r: Quaternion) -> Quaternion:
	var g := sk.get_bone_global_pose(bone).basis.orthonormalized().get_rotation_quaternion()
	return g.inverse() * r * g


func _local(sk: Skeleton3D, bone: int, r: Quaternion) -> Array:
	var q := _local_quat(sk, bone, r)
	var angle := rad_to_deg(q.get_angle())
	if angle < 0.01:
		return [0, 1, 0, 0]
	var axis := q.get_axis()
	return [snappedf(axis.x, 0.0001), snappedf(axis.y, 0.0001), snappedf(axis.z, 0.0001), snappedf(angle, 0.01)]
