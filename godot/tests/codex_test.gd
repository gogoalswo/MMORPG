extends SceneTree

## 장비 도감 (docs/features/codex.md) — 가방의 장비를 넣어(소모) 등급·부위·강화 칸을 채우면
## 그 부위의 능력치가 붙는다. **판정은 장부**(`Ledger.codex_register`)이고 보너스는 `World.stats_of` 가
## 장비 % · 헬스와 **따로 곱한다.**
##
##   godot --headless --path godot --script tests/codex_test.gd

var _failed := 0


func _init() -> void:
	_case_table()
	_case_register()
	_case_stack()
	_case_stats()
	_case_save()
	_case_server()
	_finish.call_deferred()


func _finish() -> void:
	await _case_panel()
	Save.clear()
	if _failed == 0:
		print("도감: 전부 통과")
		quit(0)
	else:
		print("도감: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _me() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.bag = []
	me.codex = {}
	return [w, me]


func _gear(grade: int, slot: String, enhance: int, count: int = 1) -> Dictionary:
	var stack := {"id": Items.item_id(grade, slot), "grade": grade, "enhance": enhance, "options": []}
	if count > 1:
		stack.count = count
	return stack


## 표 — 부위 여섯이 능력치 셋을 둘씩, 칸 몫은 등급 몫 × (강화+1)
func _case_table() -> void:
	var stats := {}
	for slot in Items.slots():
		var stat := Codex.slot_stat(str(slot))
		stats[stat] = int(stats.get(stat, 0)) + 1
	if stats != {"attack": 2, "defense": 2, "maxHp": 2}:
		_fail("부위 → 능력치 %s" % [stats])
	if Codex.max_enhance() != 9 or Codex.full_mask() != 1023:
		_fail("강화 끝 %d · 비트 %d" % [Codex.max_enhance(), Codex.full_mask()])
	if Codex.cell_value(1, 0) != 0.01 or Codex.cell_value(7, 9) != 2.0 or Codex.cell_value(4, 3) != 0.2:
		_fail("칸 몫 %s · %s · %s" % [Codex.cell_value(1, 0), Codex.cell_value(7, 9), Codex.cell_value(4, 3)])


## 등록 — 가방에서 빠지고 칸이 찬다. 같은 칸 두 번 · 가방에 없는 것 · 끼고 있는 것은 안 된다
func _case_register() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag = [_gear(3, "weapon", 2), _gear(3, "weapon", 5)]
	w.codex_register("me", Items.item_id(3, "weapon"), 2)
	if not Codex.has(me.codex, Items.item_id(3, "weapon"), 2):
		_fail("희귀 무기 +2 칸이 안 찼다: %s" % [me.codex])
	if me.bag.size() != 1 or int(me.bag[0].enhance) != 5:
		_fail("+2 하나만 빠져야 하는데 가방 %s" % [me.bag])
	w.codex_register("me", Items.item_id(3, "weapon"), 2)
	if me.bag.size() != 1:
		_fail("이미 찬 칸인데 또 빠졌다")
	# 가방에 없는 강화
	w.codex_register("me", Items.item_id(3, "weapon"), 7)
	if Codex.has(me.codex, Items.item_id(3, "weapon"), 7):
		_fail("가방에 없는 +7 칸이 찼다")
	# 끼고 있는 것은 안 받는다
	me.equipped = {"armor": _gear(2, "armor", 0)}
	w.codex_register("me", Items.item_id(2, "armor"), 0)
	if Codex.has(me.codex, Items.item_id(2, "armor"), 0) or me.equipped.is_empty():
		_fail("끼고 있는 갑옷이 도감에 들어갔다")
	# 표에 없는 id · 강화 범위 밖은 조용히 무시
	w.codex_register("me", "없는것", 0)
	w.codex_register("me", Items.item_id(3, "weapon"), 10)
	if me.codex.size() != 1:
		_fail("이상한 요청이 칸을 만들었다: %s" % [me.codex])


## 겹친 칸은 하나만 뗀다 · 옵션 줄이 적은 것부터 넣는다
func _case_stack() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag = [_gear(1, "ring", 0, 3)]
	w.codex_register("me", Items.item_id(1, "ring"), 0)
	if me.bag.size() != 1 or int(me.bag[0].get("count", 1)) != 2:
		_fail("겹친 반지 3개에서 하나만 빠져야 하는데 %s" % [me.bag])
	var rich := _gear(1, "boots", 0)
	rich.options = [{"kind": "crit", "value": 5}, {"kind": "attack", "value": 3}]
	var poor := _gear(1, "boots", 0)
	poor.options = [{"kind": "crit", "value": 1}]
	me.bag = [rich, poor]
	w.codex_register("me", Items.item_id(1, "boots"), 0)
	if me.bag.size() != 1 or (me.bag[0].options as Array).size() != 2:
		_fail("옵션이 적은 신발이 들어가야 하는데 남은 것 %s" % [me.bag])
	# 창에서 **고른 칸**(가방 번호)을 넣는다 — 옵션이 많아도 고른 것이 들어간다
	me.codex = {}
	me.bag = [poor.duplicate(true), rich.duplicate(true)]
	w.codex_register("me", Items.item_id(1, "boots"), 0, 1)
	if me.bag.size() != 1 or (me.bag[0].options as Array).size() != 1:
		_fail("고른 신발(옵션 둘)이 들어가야 하는데 남은 것 %s" % [me.bag])
	# 고른 번호에 다른 것이 서 있으면 넣지 않는다
	me.codex = {}
	me.bag = [_gear(1, "ring", 0), poor.duplicate(true)]
	w.codex_register("me", Items.item_id(1, "boots"), 0, 0)
	if me.bag.size() != 2 or not me.codex.is_empty():
		_fail("고른 번호가 반지인데 신발 칸이 찼다: %s" % [me.codex])


## 보너스는 장비 % · 헬스와 따로 곱한다. 정보 창용 `codex_*` 도 싣는다
func _case_stats() -> void:
	var codex := {Items.item_id(7, "weapon"): Codex.full_mask(), Items.item_id(7, "armor"): 1, Items.item_id(1, "boots"): 2}
	var bonus := Codex.stat_bonus(codex)
	# 태초 무기 +0~+9 = 0.2 × 55 = 11% · 태초 갑옷 +0 = 0.2% · 일반 신발 +1 = 0.02%
	if bonus != {"attack": 11.0, "defense": 0.2, "maxHp": 0.02}:
		_fail("도감 보너스 %s" % [bonus])
	if Codex.stat_bonus(codex, 7) != {"attack": 11.0, "defense": 0.2, "maxHp": 0.0}:
		_fail("태초만 센 보너스 %s" % [Codex.stat_bonus(codex, 7)])
	if Codex.filled(codex) != 12 or Codex.filled(codex, 1) != 1:
		_fail("찬 칸 수 %d · 일반 %d" % [Codex.filled(codex), Codex.filled(codex, 1)])
	var bare := World.stats_of("fighter", 100, {})
	var fit := {"bench": 20}
	var both := World.stats_of("fighter", 100, {}, {}, fit, codex)
	var only_fit := World.stats_of("fighter", 100, {}, {}, fit)
	if int(both.attack) != roundi(float(only_fit.attack) * 1.11):
		_fail("공격력 %d → %d (헬스 뒤에 × 1.11 이어야 한다)" % [int(only_fit.attack), int(both.attack)])
	if float(both.get("codex_attack", 0)) != 11.0 or float(bare.get("codex_attack", -1)) != 0.0:
		_fail("codex_attack 이 %s / %s" % [both.get("codex_attack"), bare.get("codex_attack")])
	# 판정 값에도 들어가나 — 등록하면 World 의 플레이어 공격력이 오른다
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var before := int(me.stats.attack)
	me.bag = [_gear(7, "weapon", 9)]
	w.codex_register("me", Items.item_id(7, "weapon"), 9)
	if float(me.stats.get("codex_attack", 0)) != 2.0:
		_fail("태초 무기 +9 를 넣었는데 codex_attack %s" % me.stats.get("codex_attack"))
	print("  스탯: 태초 무기 줄 다 채움 → 공격력 %d → %d (× 1.11) · 등록 전 %d" % [
		int(only_fit.attack), int(both.attack), before
	])


## 저장했다 불러와도 남는다. 표에 없는 id · 비트 밖 · 0 은 버린다
func _case_save() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.codex = {Items.item_id(2, "helmet"): 5, Items.item_id(5, "ring"): 4096 + 1, "없는것": 3, Items.item_id(1, "weapon"): 0}
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if back.codex != {Items.item_id(2, "helmet"): 5, Items.item_id(5, "ring"): 1}:
		_fail("불러온 도감 %s" % [back.codex])
	if float(back.stats.get("codex_defense", 0)) != Codex.cell_value(2, 0) + Codex.cell_value(2, 2):
		_fail("불러온 뒤 스탯에 도감이 안 들어갔다: %s" % back.stats.get("codex_defense"))


## 서버 — 요청 표에 있고, 새 계정에 칸이 있고, 처치 검증도 도감 공격력을 본다
func _case_server() -> void:
	if str(LedgerServer.OPS.get("codex_register", "")) != "sii":
		_fail("서버가 codex_register 요청을 모른다")
	var ledger := Ledger.fresh("fighter")
	if not "codex" in Ledger.KEYS or not ledger.has("codex"):
		_fail("장부 칸·새 계정에 codex 가 없다")
	var kind := {}
	for id in GameData.load_table("monsters").kinds:
		var each: Dictionary = GameData.load_table("monsters").kinds[id]
		if kind.is_empty() or int(each.get("level", 0)) > int(kind.get("level", 0)):
			kind = each
	ledger.level = 200
	var slow := KillCheck.min_ms(ledger, kind)
	ledger.codex = {Items.item_id(7, "weapon"): Codex.full_mask(), Items.item_id(7, "necklace"): Codex.full_mask()}
	var fast := KillCheck.min_ms(ledger, kind)
	if fast >= slow:
		_fail("태초 무기·목걸이 줄을 채웠는데 최소 처치 시간이 그대로다: %.0f → %.0fms" % [slow, fast])


## 창 — 탭 일곱 · 칸 60 · 칸 상태 · 탭 빨간 점 · 등록 단추가 요청을 낸다 · 화면 안
func _case_panel() -> void:
	var boxes := func(_name: String, _margin: int, _content: int) -> StyleBox: return StyleBoxFlat.new()
	var icons := func(_name: String) -> Texture2D: return null
	var panel := CodexPanel.make(boxes, icons)
	root.add_child(panel)
	panel.open()
	await process_frame
	var names: Array = []
	for grade in range(1, 8):
		var tab: Button = panel.find_child("tab_%d" % grade, true, false)
		names.append(tab.text if tab != null else "")
	if names != ["일반", "고급", "희귀", "영웅", "전설", "초월", "태초"]:
		_fail("탭 이름 %s" % [names])
	var cells := 0
	for slot in Items.slots():
		for enhance in 10:
			if panel.find_child("cell_%s_%d" % [slot, enhance], true, false) != null:
				cells += 1
	if cells != 60:
		_fail("한 탭의 칸이 60 이 아니라 %d" % cells)

	var me := {
		"codex": {Items.item_id(1, "weapon"): 1},
		"bag": [_gear(1, "weapon", 1), _gear(4, "ring", 3)],
	}
	panel.refresh(me)
	if panel.cell_state("weapon", 0) != "filled" or panel.cell_state("weapon", 1) != "owned" \
			or panel.cell_state("weapon", 2) != "empty":
		_fail("칸 상태 %s · %s · %s" % [
			panel.cell_state("weapon", 0), panel.cell_state("weapon", 1), panel.cell_state("weapon", 2)
		])
	if panel.dotted_tabs() != [1, 4]:
		_fail("빨간 점 탭이 [1, 4] 여야 하는데 %s" % [panel.dotted_tabs()])
	# 처음 고른 칸은 넣을 수 있는 첫 칸 — 일반 무기 +1
	if panel.picked() != ["weapon", 1] or panel.register_button().disabled:
		_fail("처음 고른 칸 %s · 단추 꺼짐 %s" % [panel.picked(), panel.register_button().disabled])
	var asked: Array = []
	panel.register_requested.connect(func(id: String, enhance: int, index: int) -> void: asked.append([id, enhance, index]))
	var picker: CodexPicker = panel.picker()
	# [등록] 은 바로 넣지 않고 **고르기 창**을 연다 → 창의 [등록] 이 요청을 낸다
	panel.register_button().pressed.emit()
	if not picker.visible or picker.choices() != [0] or picker.choice() != 0 or not asked.is_empty():
		_fail("등록 → 고르기 창: 보임 %s · 후보 %s · 고른 것 %d · 요청 %s" % [picker.visible, picker.choices(), picker.choice(), asked])
	picker.confirm_button().pressed.emit()
	if picker.visible:
		_fail("고르기 창의 등록을 눌렀는데 창이 남았다")
	# 찬 칸을 고르면 단추가 꺼진다
	(panel.find_child("cell_weapon_0", true, false) as Button).pressed.emit()
	if not panel.register_button().disabled:
		_fail("이미 찬 칸인데 등록 단추가 켜져 있다")
	# 영웅 탭 → 반지 +3
	(panel.find_child("tab_4", true, false) as Button).pressed.emit()
	if panel.grade() != 4 or panel.picked() != ["ring", 3]:
		_fail("영웅 탭: 등급 %d · 고른 칸 %s" % [panel.grade(), panel.picked()])
	panel.register_button().pressed.emit()
	picker.confirm_button().pressed.emit()
	if asked != [[Items.item_id(1, "weapon"), 1, 0], [Items.item_id(4, "ring"), 3, 1]]:
		_fail("단추가 낸 요청 %s" % [asked])

	# 고르기 창 — 같은 칸에 맞는 장비가 둘이면 둘, 처음엔 옵션 줄(1·2·3차 합)이 적은 것, 눌러서 바꾼다.
	# **2·3차도 보인다** (2026-10-01 지적 "2,3차 옵션은 안 보이자나")
	var many := _gear(2, "armor", 4)
	many.options = [{"kind": "crit", "value": 5}]
	many.options2 = [{"kind": "critDamage", "value": 9}]
	var few := _gear(2, "armor", 4)
	few.options = [{"kind": "crit", "value": 2}]
	panel.refresh({"codex": {}, "bag": [_gear(3, "ring", 0), many, few]})
	(panel.find_child("tab_2", true, false) as Button).pressed.emit()
	(panel.find_child("cell_armor_4", true, false) as Button).pressed.emit()
	panel.register_button().pressed.emit()
	await process_frame
	if picker.choices() != [1, 2] or picker.choice() != 2:
		_fail("후보 %s · 고른 것 %d (옵션 적은 2번이어야 한다)" % [picker.choices(), picker.choice()])
	var card: Control = picker.find_child("choice_1", true, false)
	if card == null:
		_fail("고르기 창에 1번 칸이 없다")
	else:
		var second: Control = card.find_child("tier_2_0", true, false)
		var third: Control = card.find_child("tier_3", true, false)
		if second == null or not (second.get_node("value") as Label).text.contains("치명타"):
			_fail("2차 옵션 줄이 안 보인다")
		if third == null or (third.get_node("value") as Label).text != "비어 있음":
			_fail("3차 줄이 '비어 있음' 이 아니다")
		card.get_node("hit").pressed.emit()
		if picker.choice() != 1:
			_fail("1번 칸을 눌렀는데 고른 것이 %d" % picker.choice())
	asked.clear()
	picker.confirm_button().pressed.emit()
	if asked != [[Items.item_id(2, "armor"), 4, 1]]:
		_fail("고른 갑옷을 넣는 요청이 아니다: %s" % [asked])
	# 취소는 아무것도 안 낸다
	panel.register_button().pressed.emit()
	(picker.find_child("cancel", true, false) as Button).pressed.emit()
	if picker.visible or asked.size() != 1:
		_fail("취소했는데 창 %s · 요청 %s" % [picker.visible, asked])
	# 기준 화면(1280x720)에 들어가나 — 돌판 틀 여백(카드 34 · 안 30)을 뺀 알맹이로 본다
	var inner := panel.get_combined_minimum_size()
	if inner.x > 1280.0 - 128.0 or inner.y > 720.0 - 128.0:
		_fail("도감 창 최소 크기 %s 가 틀 안(1152x592)보다 크다" % inner)
	panel.queue_free()
	print("  창: 탭 7 · 칸 60 · 상태 · 빨간 점 · 등록 요청 · 최소 크기 %s" % inner)
