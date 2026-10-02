extends SceneTree

## 설정 창 (docs/features/hud.md "설정 창") — 전체 화면 · 탭 소리 / 아이템 습득.
## 습득은 **장부**(`Ledger.set_loot_grade` · `set_loot_options` · `Ledger.kill`)가 거른다 — 등급마다 고른 부위 ·
## 1차 옵션의 장비만 가방에 들어온다 (도감 자동 등록 설정과 같은 모양).
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


## 장부 칸 · 새 계정 · 서버 요청 · 등급마다 다듬기(표 밖 등급 · 부위 · 옵션) · 옛 칸 옮겨 읽기 · 줍기 판정
func _case_ledger() -> void:
	var p := Ledger.fresh("fighter")
	var every_slots: Array = Items.slots()
	var every_kinds := Ledger.clean_option_kinds(Items._t().get("optionKinds", []))
	for key in ["loot_slots", "loot_options"]:
		if not key in Ledger.KEYS or not p.get(key) is Dictionary:
			_fail("장부 칸·새 계정에 %s 이 없다" % key)
	for op in ["set_loot_grade", "set_loot_options"]:
		if str(LedgerServer.OPS.get(op, "")) != "iw":
			_fail("서버가 %s 요청을 모른다" % op)
	# 처음은 일곱 등급 다 전 부위 · 전 옵션
	var table := Ledger.loot_slots(p)
	if table.size() != 7 or table["1"] != every_slots or table["7"] != every_slots \
			or Ledger.loot_options(p)["4"] != every_kinds:
		_fail("새 계정이 다 줍지 않는다: %s" % [table])
	var ledger := Ledger.new()
	ledger.set_loot_grade(p, 3, ["ring", "없는칸", "weapon", "ring", 3])
	ledger.set_loot_options(p, 3, ["dropRate", "cooldown", "crit"])
	ledger.set_loot_grade(p, 5, [])
	ledger.set_loot_grade(p, 9, ["weapon"])
	if Ledger.loot_slots(p)["3"] != ["weapon", "ring"] or Ledger.loot_slots(p)["5"] != [] \
			or Ledger.loot_slots(p)["2"] != every_slots or Ledger.loot_slots(p).has("9"):
		_fail("다듬은 부위 표 %s" % [Ledger.loot_slots(p)])
	if Ledger.loot_options(p)["3"] != ["crit", "dropRate"] or Ledger.loot_options(p)["5"] != every_kinds:
		_fail("다듬은 옵션 표 %s (뺀 쿨감은 안 남는다)" % [Ledger.loot_options(p)])
	# 옛 칸(전 등급 공통 끄기) — 끈 등급은 빈 목록, 끈 부위·옵션은 전 등급에서 빠진다
	var old := {"loot_skip": [2], "loot_skip_slots": ["ring"], "loot_skip_options": ["crit"]}
	if Ledger.loot_slots(old)["2"] != [] or "ring" in Ledger.loot_slots(old)["1"] \
			or Ledger.loot_slots(old)["1"].size() != every_slots.size() - 1 or "crit" in Ledger.loot_options(old)["6"]:
		_fail("옛 칸을 옮겨 읽지 못했다: %s · %s" % [Ledger.loot_slots(old), Ledger.loot_options(old)])
	# 부위만 새로 정해도 옛 옵션 끄기가 남는다 — 두 표를 옮긴 뒤에 옛 칸을 지운다
	ledger.set_loot_grade(old, 4, ["weapon"])
	if old.has("loot_skip_options") or "crit" in Ledger.loot_options(old)["6"] or Ledger.loot_slots(old)["2"] != []:
		_fail("부위를 정했더니 옛 칸이 사라지며 설정이 되살아났다: %s" % [old])
	if Ledger.loot_slots({"loot_slots": null})["1"] != every_slots:
		_fail("칸이 null 인 장부가 다 줍기로 안 읽힌다")
	# 줍기 판정 — 그 등급의 고른 부위이고, 붙은 옵션이 전부 고른 옵션이어야. 옵션 없는 장비는 옵션으로 안 거른다
	var q := {"loot_slots": {"3": ["weapon"], "4": []}, "loot_options": {"3": ["maxHp"]}}
	var sword := {"id": Items.item_id(3, "weapon"), "grade": 3, "options": [{"kind": "maxHp", "value": 5}]}
	if not Ledger.loot_wanted(q, sword):
		_fail("켜 둔 부위·옵션 장비를 안 줍는다")
	if Ledger.loot_wanted(q, {"id": Items.item_id(3, "ring"), "grade": 3, "options": sword.options}):
		_fail("그 등급에서 안 고른 부위(반지)를 줍는다")
	if not Ledger.loot_wanted(q, {"id": Items.item_id(2, "ring"), "grade": 2, "options": [{"kind": "crit", "value": 5}]}):
		_fail("정하지 않은 등급(고급)은 다 주워야 한다")
	if Ledger.loot_wanted(q, {"id": Items.item_id(4, "weapon"), "grade": 4, "options": []}):
		_fail("끈 등급(영웅)을 줍는다")
	if Ledger.loot_wanted(q, {"id": sword.id, "grade": 3, "options": [{"kind": "crit", "value": 5}]}):
		_fail("안 고른 옵션(치명타)이 붙은 장비를 줍는다")
	if not Ledger.loot_wanted(q, {"id": sword.id, "grade": 3, "options": []}):
		_fail("옵션 없는 장비를 옵션으로 걸렀다")


## 같은 씨앗으로 200마리 — 다 끄면 장비가 하나도 안 들어오고, 골드·크리스탈은 그대로 받는다
func _case_kill() -> void:
	var kind_id := ""
	for id in GameData.load_table("monsters").kinds:
		if not bool(GameData.load_table("monsters").kinds[id].get("boss", false)):
			kind_id = str(id)
			break
	var results: Array = []
	# 다 줍기 · 등급 다 끔 · 옛 칸으로 부위 다 끔 · 옵션 다 끔 · 무기만 끔 (등급마다 표)
	var no_slots := {}
	var no_options := {}
	var no_weapon := {}
	for grade in range(1, 8):
		no_slots[str(grade)] = []
		no_options[str(grade)] = []
		no_weapon[str(grade)] = Items.slots().filter(func(slot: Variant) -> bool: return str(slot) != "weapon")
	for skip in [{}, {"loot_slots": no_slots}, {"loot_skip_slots": Items.slots()},
			{"loot_options": no_options}, {"loot_slots": no_weapon}]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var ledger := Ledger.new(rng)
		var p := Ledger.fresh("fighter")
		p.merge(skip, true)
		if skip.has("loot_skip_slots"):
			p.erase("loot_slots")  # 옛 계정 — 새 칸이 없어야 옛 칸을 읽는다
		var gear := 0
		var weapons := 0
		for i in 200:
			ledger.kill(p, {"kind": kind_id, "zone": ""})
		for stack in p.bag:
			if not Items.is_material(str(stack.id)):
				gear += 1
				if str(Items.get_item(str(stack.id)).get("slot", "")) == "weapon":
					weapons += 1
		results.append({"gear": gear, "weapons": weapons, "gold": int(p.gold)})
	if int(results[0].gear) == 0 or int(results[0].weapons) == 0:
		_fail("다 줍는데 200마리에서 장비(무기)가 안 나왔다 — 시험이 아무것도 못 본다")
	for at in [1, 2, 3]:
		if int(results[at].gear) != 0:
			_fail("%s 다 껐는데 장비 %d개가 들어왔다" % [["", "등급", "부위", "옵션"][at], results[at].gear])
	if int(results[4].weapons) != 0 or int(results[4].gear) != int(results[0].gear) - int(results[0].weapons):
		_fail("무기만 껐는데 %s (다 주울 때 %s)" % [results[4], results[0]])
	for result in results:
		if int(result.gold) != int(results[0].gold):
			_fail("거르는데 골드가 달라졌다 (굴림 순서가 바뀌었다): %d ≠ %d" % [result.gold, results[0].gold])


## 저장 — 등급마다 고른 부위 · 옵션이 남고, 옛 저장의 옛 칸(`loot_skip` …)은 옮겨 읽는다
func _case_save() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	w.set_loot_grade("me", 2, ["boots"])
	w.set_loot_options("me", 5, ["penetration"])
	var now: Dictionary = w.snapshot().players["me"]
	if Ledger.loot_slots(now)["2"] != ["boots"] or Ledger.loot_options(now)["5"] != ["penetration"]:
		_fail("World.set_loot_grade · set_loot_options 가 장부에 안 들어갔다: %s · %s" % [
			Ledger.loot_slots(now), Ledger.loot_options(now)])
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var me: Dictionary = again.snapshot().players["me"]
	if Ledger.loot_slots(me)["2"] != ["boots"] or Ledger.loot_slots(me)["1"] != Items.slots() \
			or Ledger.loot_options(me)["5"] != ["penetration"]:
		_fail("불러온 부위 %s · 옵션 %s" % [Ledger.loot_slots(me), Ledger.loot_options(me)])
	# 옛 저장 — 그 전 판의 칸만 있다
	var file := FileAccess.open(Save.PATH, FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	saved.erase("loot_slots")
	saved.erase("loot_options")
	saved["loot_skip"] = [7]
	saved["loot_skip_options"] = ["crit"]
	file = FileAccess.open(Save.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var third := World.new()
	third.open("village")
	third.restore("me")
	me = third.snapshot().players["me"]
	if me.loot_slots["7"] != [] or "crit" in me.loot_options["1"] or me.loot_slots["1"] != Items.slots():
		_fail("옛 저장을 옮겨 읽지 못했다: %s · %s" % [me.loot_slots, me.loot_options])


## 창 — 전체 화면 · 위 탭 둘(+ 왼쪽 세부 목록) · 습득 쪽은 도감 자동 등록 설정과 같은 모양(등급 탭 · ON/OFF ·
## 부위 칩 · 옵션 칩) · 누르면 등급 하나의 목록을 요청 · 검색
func _case_panel() -> void:
	var panel := SettingsPanel.make()
	root.add_child(panel)
	var every_kinds := Ledger.clean_option_kinds(Items._t().get("optionKinds", []))
	panel.refresh({"loot_slots": {"2": [], "3": ["weapon", "boots"]}, "loot_options": {"3": ["maxHp"]}})
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
	# 등급 탭 일곱 · 처음은 일반 탭. 켠 등급은 금빛 점 (끈 고급만 없다)
	var tab_names: Array = []
	for grade in range(1, 8):
		var tab: Button = panel.find_child("loot_tab_%d" % grade, true, false)
		tab_names.append(tab.text if tab != null else "")
		if tab != null and (tab.get_node("on_mark") as Control).visible != (grade != 2):
			_fail("%s 탭 금빛 점이 %s" % [tab.text, (tab.get_node("on_mark") as Control).visible])
	if tab_names.size() != 7 or tab_names[0] != Items.grade_name(1) or panel.loot_grade() != 1:
		_fail("등급 탭 %s · 고른 탭 %d" % [tab_names, panel.loot_grade()])
	if not (panel.find_child("loot_grade_1", true, false) as Control).visible \
			or (panel.find_child("loot_grade_3", true, false) as Control).visible:
		_fail("고른 등급(일반)의 쪽만 보여야 한다")
	if panel.loot_state(1) != "ON" or panel.loot_state(2) != "OFF" or panel.loot_state(3) != "ON":
		_fail("스위치 %s · %s · %s" % [panel.loot_state(1), panel.loot_state(2), panel.loot_state(3)])
	if not panel.slot_on(1, "ring") or panel.slot_on(3, "ring") or not panel.slot_on(3, "boots") \
			or not panel.option_on(1, "crit") or panel.option_on(3, "crit") or not panel.option_on(3, "maxHp"):
		_fail("부위·옵션 칩 일반 반지 %s · 희귀 반지 %s · 희귀 신발 %s · 일반 치명타 %s · 희귀 치명타 %s · 희귀 체력 %s" % [
			panel.slot_on(1, "ring"), panel.slot_on(3, "ring"), panel.slot_on(3, "boots"),
			panel.option_on(1, "crit"), panel.option_on(3, "crit"), panel.option_on(3, "maxHp")])
	if panel.find_child("loot_option_1_cooldown", true, false) != null:
		_fail("뺀 옵션(쿨감) 칩이 섰다")
	panel.pick_loot_grade(3)
	await process_frame
	if panel.loot_grade() != 3 or not (panel.find_child("loot_grade_3", true, false) as Control).visible \
			or (panel.find_child("loot_grade_1", true, false) as Control).visible:
		_fail("희귀 탭을 눌렀는데 그 쪽이 안 뜬다")
	var asked: Array = []
	panel.loot_changed.connect(func(grade: int, slots: Array) -> void: asked.append(["slots", grade, slots]))
	panel.loot_options_changed.connect(func(grade: int, kinds: Array) -> void: asked.append(["options", grade, kinds]))
	# 이미 켠 쪽을 또 누르면 요청하지 않는다
	(panel.find_child("loot_1", true, false).get_node("on") as Button).pressed.emit()
	(panel.find_child("loot_7", true, false).get_node("off") as Button).pressed.emit()
	(panel.find_child("loot_2", true, false).get_node("on") as Button).pressed.emit()
	(panel.find_child("loot_slot_3_ring", true, false) as Button).pressed.emit()
	(panel.find_child("loot_slot_3_weapon", true, false) as Button).pressed.emit()
	(panel.find_child("loot_option_3_crit", true, false) as Button).pressed.emit()
	(panel.find_child("loot_option_3_maxHp", true, false) as Button).pressed.emit()
	if asked != [["slots", 7, []], ["slots", 2, Items.slots()], ["options", 2, every_kinds],
			["slots", 3, ["weapon", "boots", "ring"]], ["slots", 3, ["boots"]], ["options", 3, ["crit", "maxHp"]],
			["options", 3, []]]:
		_fail("스위치·칩을 눌러 낸 요청 %s" % [asked])
	# 검색 — 모든 탭을 펼쳐 이름이 맞는 줄만 (띠는 남은 줄이 있을 때만)
	panel.search_box().text = "볼륨"
	panel.search_box().text_changed.emit("볼륨")
	await process_frame
	var sound_row: Control = panel.find_child("sound_slider", true, false).get_parent().get_parent().get_parent()
	var loot_row: Control = panel.find_child("loot_block", true, false)
	if not sound_row.is_visible_in_tree() or loot_row.is_visible_in_tree():
		_fail("'볼륨' 검색에 볼륨 줄 %s · 습득 묶음 %s" % [sound_row.is_visible_in_tree(), loot_row.is_visible_in_tree()])
	# 부위 이름으로 찾으면 습득 묶음이 남는다
	panel.search_box().text = "목걸이"
	panel.search_box().text_changed.emit("목걸이")
	await process_frame
	if not loot_row.is_visible_in_tree() or sound_row.is_visible_in_tree():
		_fail("'목걸이' 검색에 습득 묶음 %s · 볼륨 줄 %s" % [loot_row.is_visible_in_tree(), sound_row.is_visible_in_tree()])
	panel.search_box().text = "없는말"
	panel.search_box().text_changed.emit("없는말")
	await process_frame
	if not (panel.find_child("search_empty", true, false) as Control).visible:
		_fail("맞는 줄이 없는데 '검색 결과가 없습니다' 가 안 섰다")
	panel.pick_tab(0)
	if panel.search_box().text != "" or not (panel.find_child("sound_page", true, false) as Control).visible \
			or (panel.find_child("loot_page", true, false) as Control).visible:
		_fail("탭을 누르면 검색을 비우고 그 탭만 보여야 한다")
	# 기준 화면(1280x720)에 들어가나 — 쪽마다 본다
	panel.pick_tab(1)
	await process_frame
	var inner := panel.get_combined_minimum_size()
	if inner.x > 1280.0:
		_fail("설정 창 최소 폭 %.0f 가 화면을 넘는다" % inner.x)
	for id in ["sound_page", "loot_page"]:
		var page_height := (panel.find_child(id, true, false) as Control).get_combined_minimum_size().y
		if page_height > 720.0 - 50.0 - 52.0 - 40.0:
			_fail("%s 높이 %.0f 가 화면을 넘는다" % [id, page_height])
	panel.queue_free()
