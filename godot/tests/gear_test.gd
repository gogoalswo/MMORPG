extends SceneTree

## 갑옷·투구·신발을 입히면 그 부위가 바르코 모델(`gear_g<등급>.glb`)로 바뀌는지 본다 (`Armor`).
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


## 등급마다 다른 부위 모델이 뼈대에 묶이고, 그 아래 맨몸은 꺼진다
func _case_rig() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	root.add_child(rig)
	var tris := {}
	for slot in Armor.SLOTS:
		var meshes := {}
		var last_count := 0
		for grade in range(1, 8):
			rig.set_gear(slot, grade)
			await process_frame
			var part: MeshInstance3D = rig.find_child("Gear_" + slot, true, false)
			if part == null:
				_fail("%s %d등급 모델이 없다 — gear_g%d.glb 를 만들었나 (scripts/build-gear-parts.mjs)" % [slot, grade, grade])
				continue
			if not (part.get_node_or_null(part.skeleton) is Skeleton3D):
				_fail("%s %d등급이 뼈대에 안 묶였다 — 몸과 같이 안 움직인다" % [slot, grade])
			meshes[part.mesh] = grade
			tris["%s%d" % [slot, grade]] = _count(part.mesh)
			var piece: MeshInstance3D = rig.find_child("Body_" + slot, true, false)
			if piece == null or piece.visible:
				_fail("%s 를 입었는데 그 아래 맨몸이 보인다" % slot)
			# 오로라 — 4등급부터 이펙트(`GearAura`), 등급이 오를수록 알갱이가 많다
			var auras := rig.find_children("GearAura_" + slot, "", true, false)
			if auras.is_empty() != (grade < 4):
				_fail("%s %d등급 오로라가 %s" % [slot, grade, "없다" if auras.is_empty() else "있다 (4등급부터여야 한다)"])
			elif not auras.is_empty():
				var count := 0
				for node in auras:
					for emitter in node.find_children("*", "GPUParticles3D", true, false):
						count += (emitter as GPUParticles3D).amount
				if count <= last_count:
					_fail("%s %d등급 오로라 알갱이(%d)가 아래 등급보다 많지 않다" % [slot, grade, count])
				last_count = count
		if meshes.size() != 7:
			_fail("%s 일곱 등급이 서로 다른 모델이 아니다 (%d 가지)" % [slot, meshes.size()])
		rig.set_gear(slot, 0)
		await process_frame
		if rig.find_child("Gear_" + slot, true, false) != null:
			_fail("%s 를 벗었는데 모델이 남았다" % slot)
		var bare: MeshInstance3D = rig.find_child("Body_" + slot, true, false)
		if bare == null or not bare.visible:
			_fail("%s 를 벗었는데 맨몸이 안 돌아왔다" % slot)
	print("  부위 삼각형(1·4·7등급): 갑옷 %s · 투구 %s · 신발 %s" % [
		[tris.get("armor1"), tris.get("armor4"), tris.get("armor7")],
		[tris.get("helmet1"), tris.get("helmet4"), tris.get("helmet7")],
		[tris.get("boots1"), tris.get("boots4"), tris.get("boots7")]])

	# 주먹 — 손가락 뼈를 말아 쥐고 있어야 한다 (가운데 마디가 60° 넘게 굽었나)
	var skeleton: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var curled := 0
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with("Finger21") or skeleton.get_bone_name(i).ends_with("Finger11"):
			if skeleton.get_bone_rest(i).basis.get_rotation_quaternion().get_angle() > deg_to_rad(60):
				curled += 1
	if curled < 4:
		_fail("손가락이 말려 있지 않다 (%d/4) — 주먹이 아니다 (scripts/curl-fingers.mjs)" % curled)

	# 달리는 동안 부위가 몸을 따라간다 — 발 뼈가 움직여야 한다
	rig.set_gear("boots", 3)
	rig.play("Run")
	var bone := skeleton.find_bone("LeftFoot")
	var foot_a := skeleton.get_bone_global_pose(bone).origin
	for i in 12:
		await process_frame
	if foot_a.distance_to(skeleton.get_bone_global_pose(bone).origin) < 0.001:
		_fail("달리기에서 발이 안 움직인다 — 동작이 안 옮겨졌다")
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


func _count(mesh: Mesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total
