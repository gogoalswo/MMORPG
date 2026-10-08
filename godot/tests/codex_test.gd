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
	_case_all()
	_case_stats()
	_case_save()
	_case_server()
	_case_auto_loot()
	_case_auto_kill()
	_case_auto_save()
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


## 자동 등록 — 등급 가리지 않고 넣을 수 있는 칸 전부, 칸마다 하나, 옵션 적은 것부터. 찬 칸 · 끼운 것 · 재료는 그대로
func _case_all() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var rich := _gear(5, "boots", 7)
	rich.options = [{"kind": "crit", "value": 5}, {"kind": "attack", "value": 3}]
	var poor := _gear(5, "boots", 7)
	poor.options = [{"kind": "crit", "value": 1}]
	me.codex = {Items.item_id(2, "helmet"): 1}
	me.equipped = {"armor": _gear(3, "armor", 0)}
	var kept := _gear(4, "armor", 1)
	kept.locked = true
	me.bag = [
		_gear(1, "weapon", 0, 3), rich, _gear(2, "helmet", 0), {"id": "없는것", "count": 4}, poor, _gear(7, "ring", 9), kept,
	]
	w.codex_register_all("me")
	for cell in [[1, "weapon", 0], [5, "boots", 7], [7, "ring", 9]]:
		if not Codex.has(me.codex, Items.item_id(cell[0], cell[1]), cell[2]):
			_fail("자동 등록인데 %s 칸이 안 찼다: %s" % [cell, me.codex])
	if Codex.filled(me.codex) != 4 or Codex.has(me.codex, Items.item_id(3, "armor"), 0):
		_fail("자동 등록 뒤 찬 칸 %d (4 여야 한다) · 끼운 갑옷 %s" % [
			Codex.filled(me.codex), Codex.has(me.codex, Items.item_id(3, "armor"), 0)
		])
	# 남는 것: 겹친 무기 2 · 옵션 많은 신발 · 이미 찬 투구 · 재료 · 잠근 갑옷
	var left: Array = []
	for stack in me.bag:
		left.append("%s+%d*%d/%d" % [stack.id, int(stack.get("enhance", 0)), int(stack.get("count", 1)), (stack.get("options", []) as Array).size()])
	var want := ["%s+0*2/0" % Items.item_id(1, "weapon"), "%s+7*1/2" % Items.item_id(5, "boots"),
		"%s+0*1/0" % Items.item_id(2, "helmet"), "없는것+0*4/0", "%s+1*1/0" % Items.item_id(4, "armor")]
	if left != want:
		_fail("자동 등록 뒤 가방 %s (바라는 것 %s)" % [left, want])
	# 넣을 것이 없으면 아무것도 안 바뀐다
	var before: Dictionary = me.codex.duplicate()
	w.codex_register_all("me")
	if me.codex != before or me.bag.size() != 5:
		_fail("넣을 것이 없는데 바뀌었다: %s · 가방 %d" % [me.codex, me.bag.size()])


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
	if not LedgerServer.OPS.has("codex_register_all") or str(LedgerServer.OPS.codex_register_all) != "":
		_fail("서버가 codex_register_all 요청을 모른다")
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


## 주울 때 자동 등록 (codex.md "주울 때 자동 등록") — 꺼진 등급 · 빈 칸이면 바로 · 찬 칸이면 다음 빈 단계까지
## 두드린다(성공하면 등록, 실패하면 부서짐) · 빈 칸이 없으면 둔다 · 잠근 것 · 본 표시 지우기
func _case_auto_loot() -> void:
	var id := Items.item_id(3, "weapon")
	var ledger := Ledger.new()
	var p := Ledger.fresh("fighter")
	p.bag = [_gear(3, "weapon", 0)]
	ledger._codex_auto(p, 0)
	if p.bag.size() != 1 or not p.codex.is_empty():
		_fail("자동 등록을 안 켰는데 넣었다: 가방 %s · 도감 %s" % [p.bag, p.codex])
	# 등급마다 부위를 고른다 — 희귀는 갑옷만이면 무기는 안 넣는다 (2026-10-02 "등급마다 아이템 종류도 선택")
	ledger.set_codex_auto_grade(p, 3, ["armor", "없는것", "armor"])
	ledger.set_codex_auto_grade(p, 9, ["weapon"])
	if Ledger.codex_auto(p) != {"3": ["armor"]}:
		_fail("다듬은 자동 등록 표가 {3: [armor]} 가 아니라 %s" % [Ledger.codex_auto(p)])
	ledger._codex_auto(p, 0)
	if p.bag.size() != 1:
		_fail("희귀는 갑옷만 켰는데 무기가 들어갔다")
	ledger.set_codex_auto_grade(p, 3, ["ring", "weapon"])
	if Ledger.codex_auto_slots(p, 3) != ["weapon", "ring"]:
		_fail("부위는 표 순서로 — %s" % [Ledger.codex_auto_slots(p, 3)])
	ledger._codex_auto(p, 0)
	if not p.bag.is_empty() or not Codex.has(p.codex, id, 0) or not Codex.has(Ledger.codex_new(p), id, 0):
		_fail("+0 빈 칸인데 바로 안 들어갔다: 가방 %s · 도감 %s · 새 칸 %s" % [p.bag, p.codex, p.codex_new])
	var auto_event := false
	var logged := {}
	for event in ledger.take_events():
		if event.type == "codexResult" and bool(event.get("auto", false)):
			auto_event = true
		if event.type == "codexAuto":
			logged = event
	if not auto_event:
		_fail("자동 등록이 codexResult(auto) 를 안 냈다")
	# 채팅창에 남길 한 줄 (2026-10-02 지적 "채팅창에 기록 안 남는거 같은데")
	if logged.get("result", "") != "register" or int(logged.get("level", -1)) != 0 or str(logged.get("stat", "")).is_empty():
		_fail("자동 등록이 채팅용 codexAuto(register) 를 안 냈다: %s" % [logged])
	# +0 ~ +2 가 찼다 → +3 까지 두드린다. 씨앗을 돌려 성공과 파괴가 둘 다 나오는지 본다
	var reached := 0
	var broke := 0
	for seed in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var roll := Ledger.new(rng)
		var q := Ledger.fresh("fighter")
		q.codex_auto = {"3": ["weapon"]}
		q.codex = {id: 0b111}
		q.bag = [_gear(3, "weapon", 0)]
		roll._codex_auto(q, 0)
		var told := ""
		for event in roll.take_events():
			if event.type == "codexAuto":
				told = str(event.result)
		if told != ("register" if Codex.has(q.codex, id, 3) else "destroy"):
			_fail("씨앗 %d: 채팅용 codexAuto 결과가 %s" % [seed, told])
		if not q.bag.is_empty():
			_fail("씨앗 %d: 두드린 장비가 가방에 남았다 %s" % [seed, q.bag])
		elif Codex.has(q.codex, id, 3):
			reached += 1
			if int(q.codex[id]) != 0b1111 or int(Ledger.codex_new(q).get(id, 0)) != 0b1000:
				_fail("씨앗 %d: +3 만 새로 차야 하는데 도감 %s · 새 칸 %s" % [seed, q.codex, q.codex_new])
		else:
			broke += 1
			if int(q.codex[id]) != 0b111:
				_fail("씨앗 %d: 부서졌는데 도감이 바뀌었다 %s" % [seed, q.codex])
	if reached == 0 or broke == 0:
		_fail("40 씨앗에서 +3 등록 %d번 · 파괴 %d번 — 둘 다 나와야 한다" % [reached, broke])
	# 지금 단계 이상이 다 찼으면 가방에 그대로 둔다
	p.codex[id] = Codex.full_mask()
	p.bag = [_gear(3, "weapon", 4)]
	ledger._codex_auto(p, 0)
	if p.bag.size() != 1 or int(p.bag[0].enhance) != 4:
		_fail("넣을 칸이 없는데 장비가 바뀌었다 %s" % [p.bag])
	# 활성화된 1차 옵션이 붙은 것만 넣는다 — 등급마다 (2026-10-02 "옵션도 활성화 된 옵션만 자동등록하는걸로 바꿔")
	ledger.set_codex_auto_grade(p, 1, Items.slots())
	var every := Ledger.clean_option_kinds(Items._t().get("optionKinds", []))
	if Ledger.codex_auto_option_kinds(p, 1) != every:
		_fail("정하지 않은 등급은 전 옵션이어야 하는데 %s" % [Ledger.codex_auto_option_kinds(p, 1)])
	ledger.set_codex_auto_options(p, 1, ["maxHp", "없는것", "dropRate", "maxHp"])
	ledger.set_codex_auto_options(p, 2, [])
	ledger.set_codex_auto_options(p, 9, ["crit"])
	if Ledger.codex_auto_options(p) != {"1": ["maxHp", "dropRate"], "2": []}:
		_fail("다듬은 넣을 옵션 표 %s (빈 목록도 남아야 한다)" % [Ledger.codex_auto_options(p)])
	# 옛 칸(막을 옵션)은 전 옵션 − 막은 것 — 공통 목록이면 모든 등급, 등급 표면 그 등급만
	var old_common := Ledger.codex_auto_options({"codex_auto_block": ["penetration"]})
	var old_graded := Ledger.codex_auto_options({"codex_auto_block": {"4": ["crit"]}})
	if "penetration" in old_common.get("6", every) or old_common.get("6", []).size() != every.size() - 1 \
			or "crit" in old_graded.get("4", every) or old_graded.has("3"):
		_fail("옛 막은 옵션 읽기 — 공통 %s · 등급 %s" % [old_common, old_graded])
	var critty := _gear(1, "boots", 0)
	critty.options = [{"kind": "crit", "value": 1.0}]
	p.bag = [critty]
	ledger._codex_auto(p, 0)
	if p.bag.size() != 1 or Codex.has(p.codex, Items.item_id(1, "boots"), 0):
		_fail("일반에서 치명타를 안 켰는데 치명타 장비가 도감에 들어갔다")
	critty.options = [{"kind": "maxHp", "value": 1.0}]
	ledger._codex_auto(p, 0)
	if not p.bag.is_empty() or not Codex.has(p.codex, Items.item_id(1, "boots"), 0):
		_fail("일반에서 켠 체력 옵션 장비가 안 들어갔다")
	ledger.set_codex_auto_options(p, 1, every)
	# 잠근 것은 건드리지 않는다
	var locked := _gear(1, "ring", 0)
	locked.locked = true
	p.bag = [locked]
	ledger._codex_auto(p, 0)
	if p.bag.size() != 1 or Codex.has(p.codex, Items.item_id(1, "ring"), 0):
		_fail("잠근 장비가 도감에 들어갔다")
	# 본 표시 — 그 등급만 지운다
	p.codex_new = {id: 1, Items.item_id(1, "ring"): 2}
	ledger.codex_seen(p, 3)
	if p.codex_new != {Items.item_id(1, "ring"): 2}:
		_fail("희귀 탭을 봤는데 새 칸 표시 %s" % [p.codex_new])
	ledger.codex_seen(p, 0)
	if not p.codex_new.is_empty():
		_fail("0 이면 전부 지워야 하는데 %s" % [p.codex_new])


## 처치와 이어졌나 — 다 켜고 200마리를 잡으면 자동 등록이 일어난다
func _case_auto_kill() -> void:
	var kind_id := ""
	for id in GameData.load_table("monsters").kinds:
		if not bool(GameData.load_table("monsters").kinds[id].get("boss", false)):
			kind_id = str(id)
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ledger := Ledger.new(rng)
	var p := Ledger.fresh("fighter")
	# 옛 모양(켠 등급 목록)은 그 등급의 전 부위로 읽는다
	p.codex_auto = [1, 2, 3, 4, 5, 6, 7]
	if Ledger.codex_auto_slots(p, 5) != Items.slots():
		_fail("옛 모양 자동 등록을 전 부위로 못 읽었다: %s" % [Ledger.codex_auto_slots(p, 5)])
	var autos := 0
	var gone := 0
	var broke := 0
	for i in 200:
		ledger.kill(p, {"kind": kind_id, "zone": ""})
		for event in ledger.take_events():
			if event.type == "codexResult" and bool(event.get("auto", false)):
				autos += 1
			elif event.type == "loot" and event.has("item") and not bool(event.get("kept", true)):
				gone += 1
			elif event.type == "notice" and "부서졌습니다" in str(event.get("text", "")):
				broke += 1
	# 도감에 들어갔거나 부서져 가방에 안 남은 것은 `kept: false` 로 나가야 가방 빨간 점이 안 켜진다
	if gone != autos + broke:
		_fail("가방에 안 남은 줍기 %d 가 자동 등록 %d + 부서짐 %d 과 다르다" % [gone, autos, broke])
	if autos == 0 or Codex.filled(p.codex) != autos:
		_fail("200마리를 잡았는데 자동 등록 %d번 · 찬 칸 %d" % [autos, Codex.filled(p.codex)])
	if Codex.filled(Ledger.codex_new(p)) != autos:
		_fail("새 칸 표시 %d 가 자동 등록 %d 과 다르다" % [Codex.filled(Ledger.codex_new(p)), autos])


## 저장 · 서버 — 자동 등록 등급과 새 칸 표시가 남는다, 요청 표에 있다
func _case_auto_save() -> void:
	var s := _me()
	var w: World = s[0]
	w.set_codex_auto_grade("me", 5, ["ring"])
	w.set_codex_auto_grade("me", 2, ["weapon", "boots"])
	w.set_codex_auto_options("me", 4, ["penetration"])
	var me: Dictionary = w.snapshot().players["me"]
	me.codex_new = {Items.item_id(2, "helmet"): 4}
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if back.codex_auto != {"2": ["weapon", "boots"], "5": ["ring"]} or back.codex_new != {Items.item_id(2, "helmet"): 4} \
			or back.codex_auto_options != {"4": ["penetration"]}:
		_fail("불러온 자동 등록 %s · 새 칸 %s · 넣을 옵션 %s" % [back.codex_auto, back.codex_new, back.codex_auto_options])
	if str(LedgerServer.OPS.get("set_codex_auto_options", "")) != "iw":
		_fail("서버가 set_codex_auto_options 요청을 모른다")
	again.codex_seen("me", 2)
	if not again.snapshot().players["me"].codex_new.is_empty():
		_fail("World.codex_seen 이 장부에 안 닿았다")
	if str(LedgerServer.OPS.get("set_codex_auto_grade", "")) != "iw" or str(LedgerServer.OPS.get("codex_seen", "")) != "i":
		_fail("서버가 set_codex_auto_grade · codex_seen 요청을 모른다")
	# 서버 인자 — 글자 목록("w")을 받고, 숫자가 섞이면 거절한다
	var server := LedgerServer.new(AccountStore.new("user://codex_test_accounts"))
	if server._args("iw", [3.0, ["weapon", "ring"]]) != [3, ["weapon", "ring"]] or server._args("w", [[1]]) != null:
		_fail("서버 글자 목록 인자 %s · %s" % [server._args("iw", [3.0, ["weapon", "ring"]]), server._args("w", [[1]])])
	for key in ["codex_auto", "codex_auto_options", "codex_new"]:
		if not key in Ledger.KEYS or not Ledger.fresh("fighter").has(key):
			_fail("장부 칸·새 계정에 %s 가 없다" % key)


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
	# 자동 등록 — 단추 → 들어갈 것 전부를 늘어놓은 확인 창 → [등록] 이 요청 하나를 낸다. 넣을 게 없으면 단추가 꺼진다
	var all_asked := [0]
	panel.register_all_requested.connect(func() -> void: all_asked[0] += 1)
	panel.refresh({"codex": {}, "bag": [_gear(3, "ring", 0), many, few, _gear(6, "weapon", 2)]})
	await process_frame
	if panel.auto_button().disabled:
		_fail("넣을 장비가 있는데 자동 등록 단추가 꺼져 있다")
	panel.auto_button().pressed.emit()
	if not picker.visible or not picker.is_all() or picker.choices() != [0, 2, 3] or all_asked[0] != 0:
		_fail("자동 등록 확인 창: 보임 %s · 전부 %s · 후보 %s (옵션 적은 갑옷 2번) · 요청 %d" % [
			picker.visible, picker.is_all(), picker.choices(), all_asked[0]
		])
	# 확인 창에서는 하나를 고르지 않는다 — 눌러도 그대로, [등록] 은 전부
	var first: Control = picker.find_child("choice_0", true, false)
	if first != null:
		first.get_node("hit").pressed.emit()
	picker.confirm_button().pressed.emit()
	if picker.visible or all_asked[0] != 1 or asked.size() != 1:
		_fail("자동 등록 확인 → 창 %s · 자동 요청 %d · 한 칸 요청 %d" % [picker.visible, all_asked[0], asked.size()])
	# 그 뒤 [등록] 은 다시 하나 고르는 창이다
	(panel.find_child("tab_2", true, false) as Button).pressed.emit()
	(panel.find_child("cell_armor_4", true, false) as Button).pressed.emit()
	panel.register_button().pressed.emit()
	if picker.is_all() or picker.choice() != 2:
		_fail("자동 등록 뒤 [등록] 이 하나 고르는 창이 아니다: 전부 %s · 고른 것 %d" % [picker.is_all(), picker.choice()])
	picker.close()
	var locked := _gear(5, "weapon", 0)
	locked.locked = true
	panel.refresh({"codex": {Items.item_id(3, "ring"): 1}, "bag": [_gear(3, "ring", 0), locked]})
	await process_frame
	if not panel.auto_button().disabled:
		_fail("넣을 장비가 없는데(찬 칸 · 잠근 것뿐) 자동 등록 단추가 켜져 있다")
	# [강화] — 고른 칸을 채울 장비: 목표 아래에서 가장 가까운 것, 같으면 옵션 줄 적은 것, 잠근 것 · 목표 이상은 빼고
	var rich := _gear(2, "boots", 3)
	rich.options = [{"kind": "crit", "value": 5}]
	var shut := _gear(2, "boots", 4)
	shut.locked = true
	var bag := [_gear(2, "boots", 1), rich, _gear(2, "boots", 3), shut, _gear(2, "boots", 6), _gear(3, "boots", 3)]
	var boots := Items.item_id(2, "boots")
	if Codex.enhance_source(bag, boots, 5) != 2 or Codex.enhance_source(bag, boots, 2) != 0 \
			or Codex.enhance_source(bag, boots, 1) != -1:
		_fail("강화할 장비 %d (2) · %d (0) · %d (-1)" % [
			Codex.enhance_source(bag, boots, 5), Codex.enhance_source(bag, boots, 2), Codex.enhance_source(bag, boots, 1)
		])
	var lifts: Array = []
	panel.enhance_requested.connect(func(index: int, goal: int) -> void: lifts.append([index, goal]))
	panel.refresh({"codex": {boots: 1 << 7}, "bag": bag})
	(panel.find_child("tab_2", true, false) as Button).pressed.emit()
	if not panel.enhance_button().disabled:
		_fail("칸을 직접 누르기 전인데 강화 단추가 켜져 있다")
	(panel.find_child("cell_boots_7", true, false) as Button).pressed.emit()
	if not panel.enhance_button().disabled:
		_fail("이미 찬 칸인데 강화 단추가 켜져 있다")
	(panel.find_child("cell_boots_5", true, false) as Button).pressed.emit()
	panel.enhance_button().pressed.emit()
	if lifts != [[2, 5]]:
		_fail("강화 단추가 낸 요청 %s (가방 2번을 +5 까지)" % [lifts])
	# 자동 등록 설정 — 등급 줄마다 ON/OFF + 부위 칩. 요청은 등급 하나의 부위 목록, 그림은 장부 값을 따른다
	var autos: Array = []
	panel.auto_changed.connect(func(grade: int, slots: Array) -> void: autos.append([grade, slots]))
	panel.auto_setting_button().pressed.emit()
	var sheet: CodexAutoSheet = panel.auto_sheet()
	if not sheet.visible or sheet.is_on(3):
		_fail("자동 등록 설정 창: 보임 %s · 희귀 켜짐 %s" % [sheet.visible, sheet.is_on(3)])
	(sheet.find_child("auto_3", true, false).get_node("on") as Button).pressed.emit()
	panel.refresh({"codex": {}, "bag": [], "codex_auto": {"3": Items.slots().duplicate()}})
	(sheet.find_child("slot_3_weapon", true, false) as Button).pressed.emit()
	(sheet.find_child("slot_7_ring", true, false) as Button).pressed.emit()
	(sheet.find_child("auto_3", true, false).get_node("off") as Button).pressed.emit()
	var rest: Array = Items.slots().duplicate()
	rest.erase("weapon")
	if autos != [[3, Items.slots()], [3, rest], [7, ["ring"]], [3, []]]:
		_fail("자동 등록 요청 %s" % [autos])
	if not sheet.is_on(3) or sheet.is_on(7) or not sheet.slot_on(3, "weapon") or sheet.slot_on(7, "ring"):
		_fail("그림은 장부 값 — 희귀 %s · 태초 %s · 희귀 무기 %s · 태초 반지 %s" % [
			sheet.is_on(3), sheet.is_on(7), sheet.slot_on(3, "weapon"), sheet.slot_on(7, "ring")])
	var sheet_size := (sheet.find_child("sheet", true, false) as Control).get_combined_minimum_size()
	if sheet_size.x > 1280.0 or sheet_size.y > 720.0:
		_fail("자동 등록 설정 창 %s 가 화면(1280x720)보다 크다" % sheet_size)
	# 1차 옵션 — 등급마다, 처음엔 제외 없음. **고른 옵션은 제외한다** (2026-10-08) — 칩은 넣을 목록 전체를 요청한다
	var picks: Array = []
	panel.auto_options_changed.connect(func(grade: int, kinds: Array) -> void: picks.append([grade, kinds]))
	var every := Ledger.clean_option_kinds(Items._t().get("optionKinds", []))
	if sheet.option_excluded(3, "crit"):
		_fail("처음인데 희귀 치명타 옵션이 제외로 골라져 있다")
	(sheet.find_child("option_3_crit", true, false) as Button).pressed.emit()
	var no_crit: Array = every.filter(func(kind: String) -> bool: return kind != "crit")
	panel.refresh({"codex": {}, "bag": [], "codex_auto": {"3": ["armor"]}, "codex_auto_options": {"3": ["maxHp"]}})
	(sheet.find_child("option_3_crit", true, false) as Button).pressed.emit()
	if picks != [[3, no_crit], [3, ["crit", "maxHp"]]] \
			or not sheet.option_excluded(3, "crit") or sheet.option_excluded(3, "maxHp") \
			or not sheet.option_excluded(3, "penetration") or sheet.option_excluded(5, "crit"):
		_fail("옵션 칩 요청 %s · 제외 — 희귀 치명타 %s · 희귀 체력 %s · 전설 치명타 %s" % [
			picks, sheet.option_excluded(3, "crit"), sheet.option_excluded(3, "maxHp"), sheet.option_excluded(5, "crit")])
	# 꺼진 등급(태초)은 옵션 칩도 종류 칩과 같은 꺼진 판 색 — 값(전 옵션)은 남아 있다
	var off_slot: StyleBoxFlat = (sheet.find_child("slot_7_weapon", true, false) as Button).get_theme_stylebox("normal")
	var off_option: StyleBoxFlat = (sheet.find_child("option_7_crit", true, false) as Button).get_theme_stylebox("normal")
	if off_slot.bg_color != off_option.bg_color or sheet.option_excluded(7, "crit"):
		_fail("꺼진 등급의 칩 색 — 종류 %s · 옵션 %s · 옵션 제외 %s" % [off_slot.bg_color, off_option.bg_color, sheet.option_excluded(7, "crit")])
	# 등급을 켜면 제외 옵션을 비운다(전 옵션을 넣는다)
	(sheet.find_child("auto_6", true, false).get_node("on") as Button).pressed.emit()
	if picks.back() != [6, every]:
		_fail("등급을 켰는데 전 옵션 요청이 아니다 %s" % [picks.back()])
	# 등급 탭 — 고른 탭의 쪽만 보인다, 켠 등급 탭에 금빛 점
	sheet.pick_grade(5)
	if not (sheet.find_child("page_5", true, false) as Control).visible \
			or (sheet.find_child("page_3", true, false) as Control).visible \
			or not (sheet.find_child("tab_3", true, false).get_node("on_mark") as Control).visible \
			or (sheet.find_child("tab_5", true, false).get_node("on_mark") as Control).visible:
		_fail("자동 등록 설정 등급 탭 — 쪽 · 켠 점이 어긋났다")
	# 도감 창 X 는 `game.gd` 가 나중에 맨 뒤 자식으로 붙인다 — 위에 뜨는 창은 열 때 그보다 앞(뒤 번호)으로 와야
	# X 가 그 창 위에서 안 눌린다 (2026-10-02 지적)
	var panel_close := Button.new()
	panel.add_child(panel_close)
	panel.auto_setting_button().pressed.emit()
	if sheet.get_index() < panel_close.get_index():
		_fail("자동 등록 설정 창(%d)이 도감 창 X(%d)보다 아래다" % [sheet.get_index(), panel_close.get_index()])
	# [닫기] 단추는 없고 오른쪽 위 X 로 닫는다
	var sheet_x: Button = sheet.find_child("close", true, false)
	if sheet.find_child("done", true, false) != null or sheet_x == null:
		_fail("자동 등록 설정 창에 [닫기] 가 남았거나 X 가 없다")
	sheet_x.pressed.emit()
	if sheet.visible:
		_fail("자동 등록 설정 창 X 를 눌렀는데 남았다")
	panel.register_button().pressed.emit()
	if panel.picker().visible and panel.picker().get_index() < panel_close.get_index():
		_fail("고르기 창(%d)이 도감 창 X(%d)보다 아래다" % [panel.picker().get_index(), panel_close.get_index()])
	panel.picker().close()
	panel_close.queue_free()
	# [자동 등록 설정] 은 [등록] 옆(옛 [자동 등록] 자리), [자동 등록] 은 숨김
	if panel.auto_button().visible or panel.auto_setting_button().get_parent() != panel.register_button().get_parent():
		_fail("자동 등록 숨김 %s · 설정 단추가 등록 줄에 있나 %s" % [
			not panel.auto_button().visible, panel.auto_setting_button().get_parent() == panel.register_button().get_parent()])
	if sheet.visible:
		_fail("자동 등록 설정 창 [닫기] 를 눌렀는데 남았다")
	# 새로 찬 칸 — 칸 · 탭에 빨간 점. 탭을 떠나면 그 등급을 봤다고 알린다 (다른 등급은 남는다)
	var looked: Array = []
	panel.seen.connect(func(grade: int) -> void: looked.append(grade))
	var marks := {Items.item_id(5, "armor"): 1 << 2, Items.item_id(6, "ring"): 1}
	panel.refresh({"codex": marks.duplicate(), "bag": [], "codex_new": marks})
	(panel.find_child("tab_5", true, false) as Button).pressed.emit()
	if not panel.cell_dot("armor", 2) or panel.cell_dot("armor", 1) or panel.dotted_tabs() != [5, 6]:
		_fail("새 칸 빨간 점: 칸 %s · 옆 칸 %s · 탭 %s" % [panel.cell_dot("armor", 2), panel.cell_dot("armor", 1), panel.dotted_tabs()])
	(panel.find_child("tab_1", true, false) as Button).pressed.emit()
	panel.close_panel()
	if looked != [5]:
		_fail("새 칸이 있는 탭을 떠났는데 알림 %s (전설만)" % [looked])
	# 다시 열면 새 칸이 남은 탭(초월)으로 연다 — 장부가 전설 표시를 지운 뒤다
	panel.refresh({"codex": marks.duplicate(), "bag": [], "codex_new": {Items.item_id(6, "ring"): 1}})
	panel.open()
	if panel.grade() != 6:
		_fail("새 칸이 남은 초월 탭으로 안 열렸다: %d" % panel.grade())
	# 기준 화면(1280x720)에 들어가나 — 돌판 틀 여백(카드 34 · 안 30)을 뺀 알맹이로 본다
	var inner := panel.get_combined_minimum_size()
	if inner.x > 1280.0 - 128.0 or inner.y > 720.0 - 128.0:
		_fail("도감 창 최소 크기 %s 가 틀 안(1152x592)보다 크다" % inner)
	panel.queue_free()
	print("  창: 탭 7 · 칸 60 · 상태 · 빨간 점 · 등록 요청 · 최소 크기 %s" % inner)
