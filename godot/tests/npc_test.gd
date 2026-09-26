extends SceneTree

## NPC 와 말 거는 것 — **거리는 World 가 다시 잰다.**
## 창이 열려 있다고 되는 게 아니다 (웹 클라와 같은 규칙, NPC_REACH 4.5).
##
##   godot --headless --path godot --script tests/npc_test.gd

## 시험용 상인·대장장이를 세우는 손 — 마을에서 뺐다 (shop_test.stand_shops)
const ShopTest := preload("res://tests/shop_test.gd")

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
	ShopTest.stand_shops(w)
	w.join("me")
	return w


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


## 마을에는 **전직관 한 명만** 선다 (2026-09-26 요청: "지금은 전직 교관만 있으면 되겠어")
func _case_list() -> void:
	var w := World.new()
	w.open("village")
	var npcs: Array = w.snapshot().get("npcs", [])
	if npcs.size() != 1 or str(npcs[0].get("role", "")) != "jobs":
		_fail("마을 NPC 가 전직관 한 명이 아니다: %s" % str(npcs.map(func(n): return n.get("name", ""))))
	else:
		print("  마을 NPC: %s 한 명" % npcs[0].name)
	# 시험용으로 세운 상인이 전역 존 표로 새지 않았나 (복사해서 고친다)
	_village()
	if GameData.zone("village").get("npcs", []).size() != 1:
		_fail("시험용 상인이 GameData 의 존 표로 샜다")


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
## 상점 창 모양과 누르기 — 화면 가운데 안 · HUD 위 층 · 줄이 창 안 · X 가 오른쪽 위 ·
## 줄을 누르면 산다 · 팔기 탭 · 대장간은 강화 탭 하나
func _check_shop(game: Node3D, panel: NpcPanel, me: Dictionary) -> void:
	await process_frame
	var rect := panel.get_global_rect()
	if not Rect2(0, 0, 1280, 720).encloses(rect) or absf(rect.get_center().x - 640.0) > 2.0:
		_fail("상점 창이 화면 가운데 안이 아니다 (%s)" % rect)
	var layer := panel.get_parent() as CanvasLayer
	if layer == null or layer.layer < 10:
		_fail("상점 창이 HUD 위 층이 아니다")
	var close: Control = panel.find_child("close", true, false)
	if close == null or close.get_global_rect().get_center().x < rect.get_center().x:
		_fail("닫기 X 가 오른쪽 위가 아니다")
	var first: Control = panel.list.get_child(0)
	if not rect.encloses(first.get_global_rect()) or first.get_node_or_null("hit") == null:
		_fail("첫 줄이 창 밖이거나 누름 자리가 없다")

	# 골드를 쥐여 주고 첫 줄을 누르면 산다
	me.gold = 1000000
	var before: int = me.bag.size()
	panel.redraw()
	(panel.list.get_child(0).get_node("hit") as Button).pressed.emit()
	await process_frame
	if me.bag.size() != before + 1:
		_fail("줄을 눌렀는데 안 샀다 (가방 %d → %d)" % [before, me.bag.size()])

	# 팔기 탭 — 가방의 장비가 줄로 선다
	(panel.find_child("tab_sell", true, false) as Button).pressed.emit()
	await process_frame
	var rows := panel.list.get_child_count()
	if rows < 1 or panel.list.get_child(0).get_node_or_null("hit") == null:
		_fail("팔기 탭에 산 장비가 없다 (%d줄)" % rows)
	var wallet: Label = panel.find_child("wallet", true, false)
	print("  상점 창: %s · 샀다 · 팔기 %d줄 · '%s'" % [rect.size, rows, wallet.text])

	# 대장간 — 강화 탭 하나, 값표에 "+0 → +1"
	me.x = 0.0
	me.z = 4.5
	game._transport.send(&"npc", {"name": "대장장이 군터"})
	await process_frame
	if panel.title_label.text != "대장간" or panel.find_child("tab_sell", true, false) != null:
		_fail("대장간 창이 다르다 ('%s')" % panel.title_label.text)
	elif panel.list.get_child_count() < 1:
		_fail("대장간 목록이 비었다")
	else:
		var tag: Label = panel.list.get_child(0).find_child("tag", true, false).get_child(0)
		if not tag.text.begins_with("+"):
			_fail("강화 값표가 '%s'" % tag.text)
		print("  대장간 창: 첫 줄 '%s'" % tag.text)


func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# 마을에 상인이 없다 — 판정 쪽에 시험용으로 세운다 (창은 판정이 여는 대로 뜬다)
	ShopTest.stand_shops(game._transport._world)
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	me.x = -7.0
	me.z = 2.5
	game._transport.send(&"npc", {"name": "상인 보리스"})
	await process_frame

	var panel: NpcPanel = game._npc_panel
	if not panel.visible:
		_fail("화면에서 창이 안 떴다")
	elif panel.title_label.text != "상점":
		_fail("창 제목이 다르다: %s" % panel.title_label.text)
	else:
		# 상점이면 파는 목록이 줄로 서 있어야 한다 (줄마다 아이콘 · 이름 · 값표 · 누름 자리)
		var lines: int = panel.list.get_child_count()
		print("  창: '%s', 줄 %d개, 파는 것 %d종" % [
			panel.title_label.text, lines, panel.items.size()
		])
		if panel.items.is_empty() or lines != panel.items.size():
			_fail("상점 목록이 비었거나 줄 수가 다르다 (%d줄 · %d종)" % [lines, panel.items.size()])
		else:
			await _check_shop(game, panel, me)

	Save.clear()
	if _failed == 0:
		print("NPC: 전부 통과")
		quit(0)
	else:
		print("NPC: %d개 실패" % _failed)
		quit(1)
