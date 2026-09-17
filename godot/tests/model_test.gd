extends SceneTree

## 모델이 제대로 붙었는지, 없을 때 기둥으로 돌아가는지 본다.
##
##   godot --headless --path godot --script tests/model_test.gd

var _failed := 0


func _init() -> void:
	_case_knight()
	_case_ogre()
	_case_missing()
	_case_height_table()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 씌운 뒤 실제 높이 (모델은 1 로 정규화돼 오므로 배율이 곧 키다)
func _height(rig: Rig) -> float:
	var model: Node3D = rig.get_child(0)
	var box := AABB()
	var first := true
	for child in model.find_children("*", "", true):
		if child is MeshInstance3D:
			box = child.get_aabb() if first else box.merge(child.get_aabb())
			first = false
	return box.size.y * model.scale.y


func _case_knight() -> void:
	var rig := Rig.create("varco_knight", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("기사 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	for clip in ["Idle", "Run", "Attack", "Death"]:
		if not rig.has_clip(clip):
			_fail("기사에 %s 클립이 없다" % clip)
	var h := _height(rig)
	if absf(h - 1.8) > 0.02:
		_fail("기사 키가 1.8 이어야 하는데 %.2f" % h)
	else:
		print("  기사: 키 %.2f m, 클립 %s" % [h, rig.clips()])


func _case_ogre() -> void:
	# 초원 들늑대는 scale 1.01 -> 2.2 x 1.01 = 2.22 m
	var target := GameData.beast_height("varco_ogre1", 1.01)
	var rig := Rig.create("varco_ogre1", target)
	if rig == null:
		_fail("오우거 모델을 못 만들었다")
		return
	var h := _height(rig)
	if absf(h - target) > 0.02:
		_fail("오우거 키가 %.2f 이어야 하는데 %.2f" % [target, h])
	else:
		print("  오우거: 키 %.2f m, 클립 %s" % [h, rig.clips()])


func _case_missing() -> void:
	# 파일이 없는 look 은 null 을 준다 — 화면이 기둥으로 대신한다.
	# 보스(trex)와 나머지 사냥터 몬스터가 여기 해당한다
	if Rig.create("trex", 2.0) != null:
		_fail("파일도 없는 trex 로 리그가 만들어졌다")
	if Rig.create("없는이름", 1.0) != null:
		_fail("모르는 이름으로 리그가 만들어졌다")


func _case_height_table() -> void:
	# 키는 shared 에서 내보낸 표가 정한다
	var got := GameData.beast_height("varco_ogre1", 1.0)
	if absf(got - 2.2) > 1e-9:
		_fail("오우거 기본 키가 2.2 여야 하는데 %.2f" % got)
	var unknown := GameData.beast_height("없는짐승", 2.0)
	if absf(unknown - 1.8) > 1e-9:
		_fail("모르는 짐승은 기본 0.9 x 2.0 = 1.8 이어야 하는데 %.2f" % unknown)


## 실제 화면에서 초원까지 걸어가 몬스터가 모델로 서 있는지 본다
func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	if not game._player is Rig:
		_fail("캐릭터가 모델이 아니다")

	# 차원문(9, 0)으로 밀어 넣는다
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	me.x = 9.0
	me.z = 0.0
	for i in 5:
		await process_frame

	if game._shown_zone != "meadow":
		_fail("차원문을 밟았는데 화면이 %s 그대로다" % game._shown_zone)
	else:
		var rigs := 0
		var posts := 0
		for id in game._mob_nodes:
			if game._mob_nodes[id] is Rig:
				rigs += 1
			else:
				posts += 1
		print("  초원: 모델 %d마리, 기둥 %d마리 (기둥은 파일 없는 보스)" % [rigs, posts])
		if rigs < 80:
			_fail("모델로 선 몬스터가 %d마리뿐이다" % rigs)

	if _failed == 0:
		print("모델: 전부 통과")
		quit(0)
	else:
		print("모델: %d개 실패" % _failed)
		quit(1)
