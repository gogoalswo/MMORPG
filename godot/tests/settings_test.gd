extends SceneTree

## 설정 창 (docs/features/hud.md "설정 창") — 전체 화면 · 탭 소리 / 아이템 습득.
## 습득은 **장부**(`Ledger.set_loot_skip` · `Ledger.kill`)가 거른다: 끈 등급의 장비는 가방에 안 들어온다.
##
##   godot --headless --path godot --script tests/settings_test.gd

var _failed := 0


func _init() -> void:
	_case_ledger()
	_case_kill()
	_case_save()
	_finish.call_deferred()


func _finish() -> void:
	await _case_panel()
	Save.clear()
	if _failed == 0:
		print("설정: 전부 통과")
		quit(0)
	else:
		print("설정: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 장부 칸 · 새 계정 · 서버 요청 · 목록 다듬기(표 밖 등급 · 겹침 · JSON 실수)
func _case_ledger() -> void:
	var p := Ledger.fresh("fighter")
	if not "loot_skip" in Ledger.KEYS or p.get("loot_skip") != []:
		_fail("장부 칸·새 계정에 loot_skip 이 없다")
	if str(LedgerServer.OPS.get("set_loot_skip", "")) != "a":
		_fail("서버가 set_loot_skip 요청을 모른다")
	Ledger.new().set_loot_skip(p, [3, 1, 3, 9, 0, 2.0])
	if p.loot_skip != [1, 2, 3]:
		_fail("다듬은 목록이 [1, 2, 3] 이 아니라 %s" % [p.loot_skip])
	# 옛 계정 — 칸이 없거나 null 이면 다 줍는다
	if Ledger.loot_skip({}) != [] or Ledger.loot_skip({"loot_skip": null}) != []:
		_fail("칸이 없는 장부가 빈 목록으로 안 읽힌다")


## 같은 씨앗으로 200마리 — 다 끄면 장비가 하나도 안 들어오고, 골드·크리스탈은 그대로 받는다
func _case_kill() -> void:
	var kind_id := ""
	for id in GameData.load_table("monsters").kinds:
		if not bool(GameData.load_table("monsters").kinds[id].get("boss", false)):
			kind_id = str(id)
			break
	var results: Array = []
	for skip in [[], [1, 2, 3, 4, 5, 6, 7]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var ledger := Ledger.new(rng)
		var p := Ledger.fresh("fighter")
		p.loot_skip = skip
		var gear := 0
		for i in 200:
			ledger.kill(p, {"kind": kind_id, "zone": ""})
		for stack in p.bag:
			if not Items.is_material(str(stack.id)):
				gear += 1
		results.append({"gear": gear, "gold": int(p.gold)})
	if int(results[0].gear) == 0:
		_fail("다 줍는데 200마리에서 장비가 하나도 안 나왔다 — 시험이 아무것도 못 본다")
	if int(results[1].gear) != 0:
		_fail("다 껐는데 장비 %d개가 들어왔다" % results[1].gear)
	if int(results[0].gold) != int(results[1].gold):
		_fail("거르는데 골드가 달라졌다 (굴림 순서가 바뀌었다): %d ≠ %d" % [results[0].gold, results[1].gold])


## 저장 — 고른 목록이 남고, 옛 저장(칸 없음)은 다 줍는다
func _case_save() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	w.set_loot_skip("me", [5, 2])
	if w.snapshot().players["me"].loot_skip != [2, 5]:
		_fail("World.set_loot_skip 이 장부에 안 들어갔다: %s" % [w.snapshot().players["me"].loot_skip])
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	if again.snapshot().players["me"].loot_skip != [2, 5]:
		_fail("불러온 습득 목록 %s" % [again.snapshot().players["me"].loot_skip])


## 창 — 전체 화면 · 위 탭 둘(+ 왼쪽 세부 목록) · 등급 일곱 줄 ON/OFF · 누르면 목록 전체를 요청 · 검색
func _case_panel() -> void:
	var panel := SettingsPanel.make()
	root.add_child(panel)
	panel.refresh({"loot_skip": [2]})
	panel.open()
	await process_frame
	if panel.anchor_right != 1.0 or panel.anchor_bottom != 1.0:
		_fail("설정 창이 전체 화면이 아니다")
	var names: Array = []
	for id in ["tab_env", "tab_item", "sub_sound", "sub_loot"]:
		var tab: Button = panel.find_child(id, true, false)
		names.append(tab.text if tab != null else "")
	if names != ["환경", "아이템", "소리", "습득"]:
		_fail("탭 · 세부 목록 이름 %s" % [names])
	panel.pick_tab(1)
	await process_frame
	var page: Control = panel.find_child("loot_page", true, false)
	if page == null or not page.visible or (panel.find_child("sound_page", true, false) as Control).visible:
		_fail("아이템 습득 탭을 골랐는데 그 쪽이 안 보인다")
	if panel.loot_state(1) != "ON" or panel.loot_state(2) != "OFF":
		_fail("스위치 %s · %s" % [panel.loot_state(1), panel.loot_state(2)])
	var asked: Array = []
	panel.loot_skip_changed.connect(func(grades: Array) -> void: asked.append(grades))
	(panel.find_child("loot_7", true, false).get_node("off") as Button).pressed.emit()
	# 이미 켠 쪽을 또 누르면 요청하지 않는다
	(panel.find_child("loot_1", true, false).get_node("on") as Button).pressed.emit()
	panel.toggle_grade(2)
	if asked != [[2, 7], []]:
		_fail("스위치를 눌러 낸 요청 %s" % [asked])
	# 검색 — 모든 탭을 펼쳐 이름이 맞는 줄만 (띠는 남은 줄이 있을 때만)
	panel.search_box().text = "볼륨"
	panel.search_box().text_changed.emit("볼륨")
	await process_frame
	var sound_row: Control = panel.find_child("sound_slider", true, false).get_parent().get_parent().get_parent()
	var loot_row: Control = panel.find_child("loot_row_1", true, false)
	if not sound_row.is_visible_in_tree() or loot_row.is_visible_in_tree():
		_fail("'볼륨' 검색에 볼륨 줄 %s · 일반 줄 %s" % [sound_row.is_visible_in_tree(), loot_row.is_visible_in_tree()])
	panel.search_box().text = "없는말"
	panel.search_box().text_changed.emit("없는말")
	await process_frame
	if not (panel.find_child("search_empty", true, false) as Control).visible:
		_fail("맞는 줄이 없는데 '검색 결과가 없습니다' 가 안 섰다")
	panel.pick_tab(0)
	if panel.search_box().text != "" or not (panel.find_child("sound_page", true, false) as Control).visible \
			or (panel.find_child("loot_page", true, false) as Control).visible:
		_fail("탭을 누르면 검색을 비우고 그 탭만 보여야 한다")
	# 기준 화면(1280x720)에 들어가나 — 아이템 탭(줄이 가장 많다)으로 본다
	panel.pick_tab(1)
	await process_frame
	var inner := panel.get_combined_minimum_size()
	var page_height := (panel.find_child("loot_page", true, false) as Control).get_combined_minimum_size().y
	if inner.x > 1280.0 or page_height > 720.0 - 50.0 - 52.0 - 40.0:
		_fail("설정 창 최소 폭 %.0f · 아이템 쪽 높이 %.0f 가 화면을 넘는다" % [inner.x, page_height])
	panel.queue_free()
