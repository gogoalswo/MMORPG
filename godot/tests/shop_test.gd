extends SceneTree

## 상점과 대장간 — 사고팔기·새로 만들기·강화·등급 올리기.
##
## **닿는 거리는 살 때마다 다시 잰다.** 창을 열어 두고 걸어 나가면 안 돼야 한다.
## 기준값은 packages/shared/src/items.ts 를 node 로 돌려 뽑았다 (2026-09-17).
##
##   godot --headless --path godot --script tests/shop_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_stock()
	_case_buy()
	_case_too_far()
	_case_sell()
	_case_forge()
	_case_enhance()
	_case_craft()
	Save.clear()

	if _failed == 0:
		print("상점·대장간: 전부 통과")
		quit(0)
	else:
		print("상점·대장간: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 상인(-7, 4) 또는 대장장이(0, 6.5) 옆에 세운다
func _at(role: String) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	if role == "shop":
		me.x = -7.0
		me.z = 2.5
	else:
		me.x = 0.0
		me.z = 5.0
	return [w, me]


func _notice_of(w: World) -> String:
	for e in w.drain_events():
		if e.get("type", "") == "notice":
			return str(e.text)
	return ""


func _case_stock() -> void:
	# 자기 직업 무기만, 레벨 부근 것만
	var stock := Items.shop_stock("fighter", 1)
	_eq("격투가 Lv1 재고", stock, ["w_fighter_00"])
	for id in Items.shop_stock("mage", 40):
		if not str(id).begins_with("w_mage_"):
			_fail("마법사 상점에 %s 가 있다" % id)
			return
	print("  재고: 격투가 Lv1 %s / 마법사 Lv40 %d종" % [str(stock), Items.shop_stock("mage", 40).size()])


func _case_buy() -> void:
	var s := _at("shop")
	var w: World = s[0]
	var me: Dictionary = s[1]

	# 골드가 없으면 못 산다
	w.npc_buy("me", "w_fighter_00")
	if not me.bag.is_empty():
		_fail("골드 0 인데 샀다")
	if not _notice_of(w).contains("모자"):
		_fail("모자란다고 알려 주지 않았다")

	me.gold = 100
	w.npc_buy("me", "w_fighter_00")
	_eq("사면 가방에 들어온다", me.bag.size(), 1)
	_eq("골드가 값만큼 준다", int(me.gold), 68)  # 100 - 32
	if me.bag[0].options.is_empty():
		_fail("옵션이 안 굴려졌다 — 물건이 생기는 자리마다 굴려야 한다")
	else:
		print("  구입: 골드 100 -> %d, 옵션 %d개" % [me.gold, me.bag[0].options.size()])

	# 파는 목록에 없는 것은 못 산다 — 화면이 보낸 id 를 믿지 않는다
	w.drain_events()
	w.npc_buy("me", "w_fighter_10")
	_eq("목록에 없는 것은 안 팔린다", me.bag.size(), 1)


func _case_too_far() -> void:
	var s := _at("shop")
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.gold = 100
	me.z = 20.0  # 상인에게서 멀리
	w.npc_buy("me", "w_fighter_00")
	if not me.bag.is_empty():
		_fail("멀리 있는데 샀다")
	else:
		print("  멀면 못 산다 (닿는 거리 %.1f)" % World.NPC_REACH)


func _case_sell() -> void:
	var s := _at("shop")
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append({"id": "w_fighter_00", "grade": 1, "enhance": 0, "options": []})
	w.npc_sell("me", 0)
	_eq("1등급 판매가", int(me.gold), 13)

	# 등급이 높으면 더 쳐준다 — 애써 올린 걸 헐값에 넘기면 팔 이유가 없다
	me.gold = 0
	me.bag.append({"id": "w_fighter_00", "grade": 5, "enhance": 0, "options": []})
	w.npc_sell("me", 0)
	_eq("5등급 판매가", int(me.gold), 28)
	_eq("팔면 가방에서 빠진다", me.bag.size(), 0)
	print("  판매: 1등급 13G, 5등급 28G")


func _case_forge() -> void:
	var s := _at("smith")
	var w: World = s[0]
	var me: Dictionary = s[1]

	# 재료가 없으면 못 만든다
	me.gold = 1000
	w.npc_forge("me", "a_00")
	if not me.bag.is_empty():
		_fail("재료 없이 만들어졌다")

	# 낡은 정수 5개 + 48골드
	for i in 5:
		me.bag.append({"id": "m_00", "grade": 1, "enhance": 0, "options": []})
	w.drain_events()
	w.npc_forge("me", "a_00")
	var made := 0
	for stack in me.bag:
		if str(stack.id) == "a_00":
			made += 1
	_eq("만들어진다", made, 1)
	_eq("재료 5개를 쓴다", me.bag.size(), 1)
	_eq("수수료 48G", int(me.gold), 952)
	print("  제작: 낡은 정수 5개 + 48G -> 낡은 갑옷")


func _case_enhance() -> void:
	var s := _at("smith")
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.gold = 10000
	me.bag.append({"id": "w_fighter_00", "grade": 1, "enhance": 0, "options": []})

	# **강화는 공짜이고 실패하면 무조건 파괴된다** (설계 4장). 재료도 값도 없으니
	# 실패의 대가는 아이템 하나뿐이고, 도달 단계는 "아이템이 몇 개 들어오느냐" 로만
	# 결정된다 — 그래서 드랍률이 경험치와 같은 급의 손잡이가 된다
	var results := {"success": 0, "keep": 0, "destroy": 0}
	var gold_before := int(me.gold)
	for i in 20:
		if me.bag.is_empty():
			break
		w.npc_enhance("me", 0)
		for e in w.drain_events():
			if e.get("type", "") == "enhanceResult":
				results[str(e.result)] += 1
	if int(me.gold) != gold_before:
		_fail("강화가 공짜인데 골드를 썼다 (%d -> %d)" % [gold_before, int(me.gold)])
	if results.keep > 0:
		_fail("유지가 나왔다 — 설계에는 유지 구간이 없다")
	if results.success + results.destroy == 0:
		_fail("강화가 한 번도 안 돌았다")
	print("  강화 시도: 성공 %d · 파괴 %d" % [results.success, results.destroy])


func _case_craft() -> void:
	var s := _at("smith")
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.gold = 1000
	me.bag.append({"id": "w_fighter_00", "grade": 1, "enhance": 0, "options": []})
	me.bag.append({"id": "m_00", "grade": 1, "enhance": 0, "options": []})

	w.npc_craft("me", 0)
	_eq("2등급이 된다", int(me.bag[0].grade), 2)
	_eq("수수료 16G", int(me.gold), 984)
	_eq("재료 1개를 쓴다", me.bag.size(), 1)
	if me.bag[0].options.is_empty():
		_fail("옵션이 다시 안 굴려졌다")
	else:
		print("  등급 올리기: 1 -> 2등급 (재료 1개 + 16G, 옵션 재굴림)")

	# 재료가 없으면 못 올린다
	w.drain_events()
	w.npc_craft("me", 0)
	_eq("재료 없으면 그대로", int(me.bag[0].grade), 2)
	if not _notice_of(w).contains("필요"):
		_fail("재료가 필요하다고 알려 주지 않았다")
