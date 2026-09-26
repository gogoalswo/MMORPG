extends SceneTree

## NPC 와 말 거는 것 — **거리는 World 가 다시 잰다.**
## 창이 열려 있다고 되는 게 아니다 (웹 클라와 같은 규칙, NPC_REACH 4.5).
##
##   godot --headless --path godot --script tests/npc_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_list()
	_case_talk()
	_case_too_far()
	_case_dead()
	_case_unknown()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _village() -> World:
	var w := World.new()
	w.open("village")
	w.join("me")
	return w


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


func _case_list() -> void:
	var npcs: Array = _village().snapshot().get("npcs", [])
	# 상인 · 대장장이 · 전직관(2026-09-26) + 마을 사람 넷
	if npcs.size() != 7:
		_fail("마을 NPC 가 7명이어야 하는데 %d명" % npcs.size())
	var roles: Array = []
	for npc in npcs:
		if npc.has("role"):
			roles.append(str(npc.role))
	if not ("shop" in roles and "smith" in roles):
		_fail("상점·대장간이 없다: %s" % str(roles))
	else:
		print("  마을 NPC %d명, 역할 %s" % [npcs.size(), str(roles)])


func _case_talk() -> void:
	var w := _village()
	var me: Dictionary = w.snapshot().players["me"]
	# 상인 보리스 (-7, 4) 바로 옆
	me.x = -7.0
	me.z = 2.5
	w.npc_open("me", "상인 보리스")
	var opened := _first(w.drain_events(), "npc")
	if opened.is_empty():
		_fail("옆에 섰는데 창이 안 열렸다")
	elif str(opened.role) != "shop" or str(opened.title) != "상점":
		_fail("역할·직함이 다르다 (%s / %s)" % [opened.role, opened.title])
	else:
		print("  말 걸기: %s (%s)" % [opened.name, opened.title])


func _case_too_far() -> void:
	var w := _village()
	var me: Dictionary = w.snapshot().players["me"]
	# 상인에게서 10m — NPC_REACH 4.5 보다 멀다
	me.x = -7.0
	me.z = 14.0
	w.npc_open("me", "상인 보리스")
	var events := w.drain_events()
	if not _first(events, "npc").is_empty():
		_fail("10m 인데 창이 열렸다")
	elif _first(events, "notice").get("text", "") != "너무 멉니다":
		_fail("멀다고 알려 주지 않았다")
	else:
		print("  10m 에서는 안 열림 (닿는 거리 %.1f)" % World.NPC_REACH)


func _case_dead() -> void:
	var w := _village()
	var me: Dictionary = w.snapshot().players["me"]
	me.x = -7.0
	me.z = 2.5
	me["dead"] = true
	w.npc_open("me", "상인 보리스")
	if not _first(w.drain_events(), "npc").is_empty():
		_fail("죽었는데 창이 열렸다")


func _case_unknown() -> void:
	var w := _village()
	w.npc_open("me", "없는사람")
	if not w.drain_events().is_empty():
		_fail("없는 이름에 뭔가 응답했다")


## 화면에서 눌러 창이 뜨는지
func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	me.x = -7.0
	me.z = 2.5
	game._transport.send(&"npc", {"name": "상인 보리스"})
	await process_frame

	if not game._npc_panel.visible:
		_fail("화면에서 창이 안 떴다")
	elif not game._npc_title.text.begins_with("상인 보리스"):
		_fail("창 제목이 다르다: %s" % game._npc_title.text)
	else:
		# 상점이면 파는 목록이 줄로 서 있어야 한다 (탭 줄 + 단추들)
		var lines: int = game._npc_rows.get_child_count()
		print("  창: '%s', 줄 %d개, 파는 것 %d종" % [
			game._npc_title.text, lines, game._npc_items.size()
		])
		if game._npc_items.is_empty():
			_fail("상점에 파는 것이 없다")

	Save.clear()
	if _failed == 0:
		print("NPC: 전부 통과")
		quit(0)
	else:
		print("NPC: %d개 실패" % _failed)
		quit(1)
