extends SceneTree

## 주먹 소켓에 무기(건틀릿)가 붙고, 무기를 바꾸면 모델이 바뀌는지 본다.
##
##   godot --headless --path godot --script tests/weapon_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
	Save.clear()
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await _case_socket()
	await _case_game()
	print("무기 소켓 테스트 %s" % ("통과" if _failed == 0 else "실패 %d" % _failed))
	quit(1 if _failed > 0 else 0)


## 소켓이 손 뼈를 따라가고, 등급마다 다른 모델이 두 주먹에 한 짝씩 붙는다
func _case_socket() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	root.add_child(rig)
	var skeleton: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var shapes := {}
	for grade in range(1, 8):
		rig.set_weapon(grade)
		await process_frame
		for bone in Rig.FIST_BONES:
			var socket := rig.fist_socket(bone)
			if socket.get_child_count() != 1:
				_fail("%d등급: %s 소켓에 붙은 것이 %d개" % [grade, bone, socket.get_child_count()])
				continue
			var weapon: Node3D = socket.get_child(0)
			if weapon.name != "Gauntlet%d" % grade:
				_fail("%s 소켓에 %s (Gauntlet%d 여야 한다)" % [bone, weapon.name, grade])
			# 주먹 자리에 있어야 한다 — 손 뼈에서 20cm 안
			var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))).origin
			var gap := _center(weapon).distance_to(hand)
			if gap > 0.2:
				_fail("%d등급 %s 무기가 손에서 %.2fm 떨어져 있다" % [grade, bone, gap])
		var right: Node3D = rig.fist_socket("RightHand").get_child(0)
		shapes[_signature(right)] = grade
	# 일곱 등급이 서로 다르게 생겨야 한다 (조각 수·색으로 잰다)
	if shapes.size() != 7:
		_fail("등급 일곱 개가 %d가지 모양뿐이다" % shapes.size())

	# 걷는 동안 소켓이 손을 따라간다
	rig.play("Run")
	for i in 10:
		await process_frame
	var socket := rig.fist_socket("RightHand")
	var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))).origin
	if socket.global_position.distance_to(hand) > 0.01:
		_fail("달리는 중에 소켓이 손을 놓쳤다 (%.3fm)" % socket.global_position.distance_to(hand))

	rig.set_weapon(0)
	await process_frame
	for bone in Rig.FIST_BONES:
		if rig.fist_socket(bone).get_child_count() != 0:
			_fail("무기를 벗었는데 %s 에 남아 있다" % bone)
	print("  소켓: 등급 7가지 모양 · 두 주먹 · 달리는 중에도 손을 따라간다 · 벗으면 맨주먹")
	rig.queue_free()


## 게임에서 장비 칸의 무기를 바꾸면 캐릭터 주먹의 모델이 바뀐다
func _case_game() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node_or_null("Game")
	await process_frame
	if game == null or game.get_script() == null:
		_fail("게임 화면을 못 띄웠다")
		return
	if not game._player is Rig:
		_fail("캐릭터가 모델이 아니다 — npm run sync:godot 을 돌렸나")
		return
	var rig: Rig = game._player
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	me.bag.clear()
	me.equipped.erase("weapon")
	game._transport.send(&"debugGauntlets", {})
	for i in 3:
		await process_frame
	if rig.weapon_grade() != 0:
		_fail("무기를 안 꼈는데 %d등급이 보인다" % rig.weapon_grade())
	me.level = 999
	for grade in [3, 7, 1]:
		var index := -1
		for i in me.bag.size():
			if int(me.bag[i].grade) == grade and str(Items.get_item(str(me.bag[i].id)).get("slot", "")) == "weapon":
				index = i
		game._transport.send(&"equip", {"index": index})
		for i in 3:
			await process_frame
		if rig.weapon_grade() != grade:
			_fail("%d등급 무기를 꼈는데 주먹에 %d등급" % [grade, rig.weapon_grade()])
		elif rig.fist_socket("RightHand").get_child(0).name != "Gauntlet%d" % grade:
			_fail("%d등급을 꼈는데 모델이 %s" % [grade, rig.fist_socket("RightHand").get_child(0).name])
	game._transport.send(&"unequip", {"slot": "weapon"})
	for i in 3:
		await process_frame
	if rig.weapon_grade() != 0:
		_fail("무기를 벗었는데 주먹에 %d등급이 남았다" % rig.weapon_grade())
	print("  게임: 희귀 → 태초 → 일반으로 바꾸면 주먹 모델이 따라 바뀌고, 벗으면 맨주먹")


func _center(node: Node3D) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		sum += (child as Node3D).global_position
		count += 1
	return sum / maxi(count, 1)


func _signature(node: Node3D) -> String:
	var parts: Array = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = (child as MeshInstance3D).material_override
		parts.append(mat.albedo_color.to_html())
	parts.sort()
	return "%d:%s" % [parts.size(), ",".join(parts)]
