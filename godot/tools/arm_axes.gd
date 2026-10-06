extends SceneTree

## 트레이너 모델마다 **팔 벌리기 · 팔꿈치 굽히기 축**을 잰다 (2026-10-06, 주먹 쥔 트레이너).
##
## 바르코 뼈대는 모델마다 윗팔·아래팔의 로컬 축이 조금씩 달라서, 한 모델에서 손으로 구한 축을 다른 모델에 쓰면
## 손이 앞뒤로 흔들린다. 그래서 대기 0.5초 자세에서 뼈를 로컬 X · Z 로 10° 씩 돌려 **손이 어디로 가는지** 재고,
##   - 팔 벌리기(윗팔): 손이 **바깥으로만** 가는 X·Z 섞음 (앞뒤 0)
##   - 팔꿈치 굽히기(아래팔): 손이 **앞으로만** 가는 X·Z 섞음 (좌우 0)
## 을 풀어 `scripts/rotate-bones.mjs` 에 넣을 축을 JSON 한 줄로 낸다. 모델 앞은 +Z, 왼쪽은 +X.
##
##   godot --headless --path godot --script tools/arm_axes.gd -- n02 n03 …
##   → {"n02": {"LeftArm": [x, 0, z], "RightArm": …, "LeftForeArm": …, "RightForeArm": …}, …}

const STEP := 10.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = []
	var after := false
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if after:
			ids.append(arg)
		if arg == "--":
			after = true
	if ids.is_empty():
		ids = OS.get_cmdline_user_args()
	var out := {}
	for id in ids:
		var rig := Rig.create(Trainers.look(str(id)), 1.8)
		if rig == null:
			continue
		root.add_child(rig)
		await process_frame
		var sk: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		rig._anim.play("Idle")
		rig._anim.seek(0.5, true)
		rig._anim.pause()
		var axes := {}
		for side in ["Left", "Right"]:
			var outward := 1.0 if side == "Left" else -1.0
			axes[side + "Arm"] = _solve(sk, side + "Arm", side + "Hand", "side", outward)
			axes[side + "ForeArm"] = _solve(sk, side + "ForeArm", side + "Hand", "front", 1.0)
		out[str(id)] = axes
		rig.queue_free()
		await process_frame
	print("AXES " + JSON.stringify(out))
	quit(0)


## 로컬 X · Z 로 돌렸을 때 손이 가는 방향(vx, vz)에서, 버릴 성분이 0 이 되게 섞는다.
## `want` 가 "side" 면 앞뒤(z)를 버리고 좌우(x)가 `sign` 쪽, "front" 면 좌우를 버리고 앞(+z)
func _solve(sk: Skeleton3D, bone_name: String, hand_name: String, want: String, sign: float) -> Array:
	var bone := sk.find_bone(bone_name)
	var hand := sk.find_bone(hand_name)
	var q := sk.get_bone_pose_rotation(bone)
	var base := sk.get_bone_global_pose(hand).origin
	var moves := []
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		sk.set_bone_pose_rotation(bone, q * Quaternion(axis, deg_to_rad(STEP)))
		moves.append(sk.get_bone_global_pose(hand).origin - base)
	sk.set_bone_pose_rotation(bone, q)
	var vx: Vector3 = moves[0]
	var vz: Vector3 = moves[1]
	# 버릴 성분 d, 남길 성분 k
	var dx := vx.z if want == "side" else vx.x
	var dz := vz.z if want == "side" else vz.x
	# a·dx + b·dz = 0 → (a, b) = (dz, -dx)
	var a := dz
	var b := -dx
	var keep := a * (vx.x if want == "side" else vx.z) + b * (vz.x if want == "side" else vz.z)
	if keep * sign < 0.0:
		a = -a
		b = -b
	var length := sqrt(a * a + b * b)
	return [snappedf(a / length, 0.001), 0, snappedf(b / length, 0.001)]
