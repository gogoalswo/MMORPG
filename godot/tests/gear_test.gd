extends SceneTree

## 갑옷·투구·신발을 입히면 그 부위 스킨이 등급대로 바뀌는지 본다 (`Armor`).
##
##   godot --headless --path godot --script tests/gear_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await _case_rig()
	await _case_game()
	print("장비 스킨 테스트 %s" % ("통과" if _failed == 0 else "실패 %d" % _failed))
	quit(1 if _failed > 0 else 0)


## 부위마다 껍데기가 몸에 붙고, 등급을 바꾸면 모양은 그대로 재질만 바뀐다
func _case_rig() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	root.add_child(rig)
	var tris := {}
	for slot in Armor.SLOTS:
		var mesh: Mesh = null
		for grade in range(1, 8):
			rig.set_gear(slot, grade)
			await process_frame
			var shell: MeshInstance3D = rig.find_child("Gear_" + slot, true, false)
			if shell == null or not shell.visible:
				_fail("%s %d등급을 입혔는데 껍데기가 안 보인다" % [slot, grade])
				continue
			if not (shell.get_node_or_null(shell.skeleton) is Skeleton3D):
				_fail("%s 껍데기가 뼈대에 안 묶였다 — 몸과 같이 안 움직인다" % slot)
			if mesh == null:
				mesh = shell.mesh
			elif shell.mesh != mesh:
				_fail("%s 등급을 바꿀 때마다 껍데기를 다시 뗀다" % slot)
			var got: Color = (shell.material_override as StandardMaterial3D).albedo_color
			if not got.is_equal_approx(Armor.LOOK[grade][0]):
				_fail("%s %d등급 색이 %s" % [slot, grade, got.to_html(false)])
			if grade >= 3 and _decor(rig, slot) == 0:
				_fail("%s %d등급인데 장식이 없다" % [slot, grade])
		tris[slot] = _count(mesh)
		rig.set_gear(slot, 0)
		await process_frame
		var gone: MeshInstance3D = rig.find_child("Gear_" + slot, true, false)
		if gone != null and gone.visible:
			_fail("%s 를 벗었는데 껍데기가 남았다" % slot)
		if _decor(rig, slot) != 0:
			_fail("%s 를 벗었는데 장식이 남았다" % slot)
	# 부위 크기 — 갑옷이 가장 넓고, 투구는 얼굴을 빼서 좁다
	if int(tris.get("armor", 0)) < 1000 or int(tris.get("boots", 0)) < 500 or int(tris.get("helmet", 0)) < 200:
		_fail("껍데기 삼각형이 너무 적다 %s" % str(tris))
	if int(tris.get("helmet", 0)) >= _head_tris(rig):
		_fail("투구가 머리 전체(%d)를 덮는다 — 얼굴을 빼야 한다" % _head_tris(rig))
	print("  껍데기 삼각형: 갑옷 %d · 투구 %d (머리 %d 중) · 신발 %d" % [tris.armor, tris.helmet, _head_tris(rig), tris.boots])

	# 배 — 갑옷 아래 끝이 반바지 허리(골반 뼈 + WAIST)까지 내려와야 사이가 안 드러난다
	var body: MeshInstance3D = Armor._body(rig)
	var armor_mesh := Armor.shell_mesh(body, "armor")
	var hips_y := 0.0
	for i in body.skin.get_bind_count():
		if str(body.skin.get_bind_name(i)) == "Hips":
			hips_y = body.skin.get_bind_pose(i).affine_inverse().origin.y
	var bottom := armor_mesh.get_aabb().position.y - hips_y
	if bottom > Armor.WAIST + 0.01:
		_fail("갑옷 아래 끝이 골반 위 %.3f — 배가 드러난다 (허리선 %.3f)" % [bottom, Armor.WAIST])

	# 주먹 — 손가락 뼈를 말아 쥐고 있어야 한다 (가운데 마디가 60° 넘게 굽었나)
	var skeleton0: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var curled := 0
	for i in skeleton0.get_bone_count():
		if skeleton0.get_bone_name(i).ends_with("Finger21") or skeleton0.get_bone_name(i).ends_with("Finger11"):
			if skeleton0.get_bone_rest(i).basis.get_rotation_quaternion().get_angle() > deg_to_rad(60):
				curled += 1
	if curled < 4:
		_fail("손가락이 말려 있지 않다 (%d/4) — 주먹이 아니다 (scripts/curl-fingers.mjs)" % curled)
	print("  배: 갑옷 아래 끝이 골반 위 %.3f · 주먹: 손가락 마디 %d/4 가 말려 있다" % [bottom, curled])

	# 달리는 동안 껍데기가 몸을 따라간다 — 정강이 껍데기 상자가 멈춰 있을 때와 달라야 한다
	rig.set_gear("boots", 3)
	rig.play("Run")
	var shell: MeshInstance3D = rig.find_child("Gear_boots", true, false)
	var skeleton: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var bone := skeleton.find_bone("LeftFoot")
	var foot_a := skeleton.get_bone_global_pose(bone).origin
	for i in 12:
		await process_frame
	var foot_b := skeleton.get_bone_global_pose(bone).origin
	if foot_a.distance_to(foot_b) < 0.001:
		_fail("달리기에서 발이 안 움직인다 — 동작이 안 옮겨졌다")
	if shell.skin != (Armor._body(rig) as MeshInstance3D).skin:
		_fail("신발 껍데기가 몸과 다른 스킨을 쓴다")
	rig.queue_free()


## 게임에서 장비를 입고 벗으면 캐릭터 부위가 따라 바뀐다
func _case_game() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node_or_null("Game")
	await process_frame
	if game == null or not game._player is Rig:
		_fail("게임 화면·캐릭터 모델을 못 띄웠다")
		return
	var rig: Rig = game._player
	for slot in Armor.SLOTS:
		if rig.gear_grade(slot) != 0:
			_fail("처음부터 %s 를 입고 있다 (%d등급)" % [slot, rig.gear_grade(slot)])
	for grade in [2, 6]:
		game._transport.send(&"debugGear", {"level": 200, "grade": grade, "enhance": 0})
		for i in 3:
			await process_frame
		for slot in Armor.SLOTS:
			if rig.gear_grade(slot) != grade:
				_fail("%d등급 세트를 입혔는데 %s 가 %d등급" % [grade, slot, rig.gear_grade(slot)])
	game._transport.send(&"unequip", {"slot": "helmet"})
	for i in 3:
		await process_frame
	if rig.gear_grade("helmet") != 0 or rig.gear_grade("armor") != 6:
		_fail("투구만 벗었는데 투구 %d · 갑옷 %d" % [rig.gear_grade("helmet"), rig.gear_grade("armor")])
	print("  게임: 고급 → 초월 세트로 갈아입으면 세 부위가 따라 바뀌고, 투구만 벗으면 투구만 사라진다")


func _decor(rig: Rig, slot: String) -> int:
	var count := 0
	for node in rig.find_children("GearDecor_" + slot, "Node3D", true, false):
		count += node.get_child_count()
	return count


func _count(mesh: Mesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


## 머리 뼈에 절반 넘게 묶인 삼각형 수 — 투구가 이보다 적어야 얼굴이 드러난다
func _head_tris(rig: Rig) -> int:
	var body: MeshInstance3D = Armor._body(rig)
	var whole := 0
	for s in body.mesh.get_surface_count():
		var arrays: Array = body.mesh.surface_get_arrays(s)
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := weights.size() / pos.size()
		var head := -1
		for i in body.skin.get_bind_count():
			if str(body.skin.get_bind_name(i)) == "Head":
				head = i
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size() - 2, 3):
			var ok := true
			for v in [idx[t], idx[t + 1], idx[t + 2]]:
				var w := 0.0
				for k in per:
					if int(bones[v * per + k]) == head:
						w += weights[v * per + k]
				ok = ok and w > 0.5
			if ok:
				whole += 1
	return whole
