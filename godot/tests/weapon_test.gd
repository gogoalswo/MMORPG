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
	var layers: Array = []
	# 오로라는 강화 +6 부터 — 겹은 등급마다 느는지 보려고 +9 로 끼운다
	for grade in range(1, 8):
		rig.set_weapon(grade, 9)
		await process_frame
		for bone in Rig.FIST_BONES:
			var socket := rig.fist_socket(bone)
			# 건틀릿 + 기운
			if socket.get_child_count() != 2:
				_fail("%d등급: %s 소켓에 붙은 것이 %d개 (건틀릿·기운 둘이어야 한다)" % [grade, bone, socket.get_child_count()])
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
		_check_aura(rig, grade, skeleton)
		layers.append(_layers(rig.fist_socket("RightHand").get_node("FistAura")))
	# 일곱 등급이 서로 다르게 생겨야 한다 (조각 수·색으로 잰다)
	if shapes.size() != 7:
		_fail("등급 일곱 개가 %d가지 모양뿐이다" % shapes.size())
	# 좋은 무기일수록 기운이 화려하다 — 빛 조각·알갱이 수가 등급마다 늘어야 한다
	for i in range(1, layers.size()):
		if layers[i] <= layers[i - 1]:
			_fail("기운이 %d등급(%d)보다 %d등급(%d)이 화려하지 않다" % [i, layers[i - 1], i + 1, layers[i]])
	print("  기운: 등급별 빛 조각·알갱이 %s" % str(layers))

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
	# 강화 단계에 따라 — +5 까지는 오로라가 없고, +6 초록 · +7 파랑 · +8 빨강 · +9 하양,
	# 한 단계마다 커진다
	var names := {6: "초록", 7: "파랑", 8: "빨강", 9: "하양"}
	var first_size := 0.0
	for enhance in [5, 6, 7, 8, 9]:
		me.equipped.weapon["enhance"] = enhance
		for i in 3:
			await process_frame
		var aura: FistAura = rig.fist_socket("RightHand").get_node_or_null("FistAura")
		if enhance < 6:
			if aura != null:
				_fail("+%d 인데 오로라가 나온다 (+6 부터여야 한다)" % enhance)
			continue
		if aura == null:
			_fail("+%d 인데 오로라가 없다" % enhance)
			continue
		var got: Color = (aura._halo.material_override as StandardMaterial3D).albedo_color
		var want: Color = FistAura.COLORS[enhance]
		if not Vector3(got.r, got.g, got.b).is_equal_approx(Vector3(want.r, want.g, want.b)):
			_fail("+%d 오로라가 %s 이 아니다 (%s)" % [enhance, names[enhance], got.to_html(false)])
		if enhance == 6:
			first_size = _halo_size(rig)
		elif not is_equal_approx(_halo_size(rig) / first_size, FistAura.grow(enhance) / FistAura.grow(6)):
			_fail("+6 → +%d 오로라가 %.2f배" % [enhance, _halo_size(rig) / first_size])
	print("  강화: +5 없음 · +6 초록 · +7 파랑 · +8 빨강 · +9 하양 (+9 는 +6 의 %.2f배)" % (FistAura.grow(9) / FistAura.grow(6)))

	game._transport.send(&"unequip", {"slot": "weapon"})
	for i in 3:
		await process_frame
	if rig.weapon_grade() != 0:
		_fail("무기를 벗었는데 주먹에 %d등급이 남았다" % rig.weapon_grade())
	print("  게임: 희귀 → 태초 → 일반으로 바꾸면 주먹 모델이 따라 바뀌고, 벗으면 맨주먹")


## 기운이 주먹 자리에 미터로 있고, 색이 등급 색 계열인가
func _check_aura(rig: Rig, grade: int, skeleton: Skeleton3D) -> void:
	var aura: FistAura = rig.fist_socket("RightHand").get_node_or_null("FistAura")
	if aura == null:
		_fail("%d등급 기운이 없다" % grade)
		return
	# 배율을 되돌렸으니 월드에서 1배여야 한다 — 아니면 빛이 1.85배로 부푼다
	var world_scale := aura.global_basis.get_scale().x
	if absf(world_scale - 1.0) > 0.05:
		_fail("%d등급 기운 배율이 %.2f (1 이어야 한다)" % [grade, world_scale])
	var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))).origin
	if aura.global_position.distance_to(hand) > 0.2:
		_fail("%d등급 기운이 손에서 %.2fm" % [grade, aura.global_position.distance_to(hand)])
	# 색은 등급이 아니라 강화 단계가 정한다 (+9 = 하양)
	var got: Color = (aura._halo.material_override as StandardMaterial3D).albedo_color
	var want: Color = FistAura.COLORS[9]
	if not Vector3(got.r, got.g, got.b).is_equal_approx(Vector3(want.r, want.g, want.b)):
		_fail("%d등급 +9 오로라 색이 %s (하양 %s 이어야 한다)" % [grade, got.to_html(false), want.to_html(false)])


## 오른주먹 빛무리 지름(m)
func _halo_size(rig: Rig) -> float:
	var aura: FistAura = rig.fist_socket("RightHand").get_node("FistAura")
	return (aura._halo.mesh as QuadMesh).size.x


## 기운의 화려함 — 빛 조각 수 + 방출기 알갱이 수
func _layers(aura: Node) -> int:
	var total := 0
	for child in aura.find_children("*", "", true, false):
		if child is GPUParticles3D:
			total += (child as GPUParticles3D).amount
		elif child is MeshInstance3D:
			total += 1
	return total


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
