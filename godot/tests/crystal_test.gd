extends SceneTree

## 옵션 차수와 크리스탈 (2026-09-23).
##
## **1차는 드랍, 2차는 크리스탈, 3차는 비워 둔다.** 크리스탈을 쓰면 2차 1줄을
## 통째로 다시 굴린다. 크리스탈은 장비와 따로 떨어지고 가방 한 칸에 겹친다.
##
##   godot --headless --path godot --script tests/crystal_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_tiers()
	_case_drop()
	_case_stack()
	_case_use_bag()
	_case_use_worn()
	_case_no_crystal()
	_case_restore()
	_case_grant_once()
	Save.clear()

	if _failed == 0:
		print("크리스탈: 전부 통과")
		quit(0)
	else:
		print("크리스탈: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _world() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.bag.clear()
	return [w, me]


func _crystal(count: int) -> Dictionary:
	return {"id": Items.crystal_id(), "count": count}


func _case_tiers() -> void:
	var counts: Array = []
	for row in Items.option_tiers():
		counts.append([int(row.tier), str(row.key), int(row.count)])
	_eq("차수 표", counts, [[1, "options", 1], [2, "options2", 1], [3, "options3", 0]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for grade in range(1, 8):
		var second := Items.roll_tier_options(2, grade, rng)
		_eq("%d등급 2차 줄 수" % grade, second.size(), 1)
		var span := Items.option_range(str(second[0].kind), grade)
		if float(second[0].value) < span.min or float(second[0].value) > span.max:
			_fail("%d등급 2차가 범위 밖: %s" % [grade, second[0]])
		_eq("3차는 비어 있다", Items.roll_tier_options(3, grade, rng).size(), 0)
	if Items.get_material(Items.crystal_id()).get("name", "") != "크리스탈":
		_fail("크리스탈 표가 없다")
	if not Items.get_item(Items.crystal_id()).is_empty():
		_fail("크리스탈이 장비 표에 들어 있다")


## 드랍은 1차만 붙인다. 크리스탈은 장비와 따로 — 0.01% 언저리로 나와야 한다.
## 1만 마리에 하나라 30만 번 굴려 30개 언저리를 본다 (씨앗이 고정이라 흔들리지 않는다)
func _case_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var crystals := 0
	var tries := 300000
	for i in tries:
		var loot := Items.roll_drop(50, "fighter", rng)
		if loot.has("item") and loot.item.has("options2"):
			_fail("드랍에 2차 옵션이 붙었다")
			break
		crystals += int(loot.get("crystal", 0))
	var rate := float(crystals) / tries
	var want := Items.crystal_drop_chance()
	if absf(rate - want) > want * 0.5:
		_fail("크리스탈 드랍률 %.4f — %.4f 언저리여야 한다" % [rate, want])
	print("  크리스탈 드랍: %d마리에 %d개 (%.3f%%)" % [tries, crystals, rate * 100.0])


## 크리스탈은 한 칸에 겹친다 — **가방이 꽉 차도** 이미 있는 칸에는 들어간다
func _case_stack() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w._give(me, _crystal(1))
	w._give(me, _crystal(1))
	_eq("크리스탈 칸 수", me.bag.size(), 1)
	_eq("크리스탈 개수", int(me.bag[0].count), 2)
	while me.bag.size() < Items.bag_size():
		me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	if not w._give(me, _crystal(1)):
		_fail("가방이 꽉 찼어도 크리스탈 칸에는 겹쳐야 한다")
	_eq("꽉 찬 가방에 겹친 개수", int(me.bag[0].count), 3)
	w.sort_bag("me")
	if str(me.bag[me.bag.size() - 1].id) != Items.crystal_id():
		_fail("정렬하면 재료는 장비 뒤로 가야 한다")

	# 테스트 단추 "크리스탈 30" — 있던 칸에 겹친다
	var t := _world()
	var tw: World = t[0]
	var tme: Dictionary = t[1]
	tw.debug_crystals("me", 30)
	tw.debug_crystals("me", 30)
	_eq("테스트 단추 두 번 — 칸 수", tme.bag.size(), 1)
	_eq("테스트 단추 두 번 — 개수", int(tme.bag[0].count), 60)


## 가방의 장비에 쓴다 — 크리스탈이 앞 칸이어도 **고른 장비에** 붙어야 한다
func _case_use_bag() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append(_crystal(2))
	me.bag.append({"id": "g3_r", "grade": 3, "enhance": 0, "options": []})
	w.use_crystal("me", "bag", 1)
	var ring: Dictionary = me.bag[1]
	_eq("2차 줄 수", ring.get("options2", []).size(), 1)
	_eq("크리스탈 하나 썼다", int(me.bag[0].count), 1)

	# 다시 쓰면 **통째로 다시 굴린다** — 쌓이지 않는다. 마지막 하나를 쓰면 칸이 빠지고
	# 장비가 앞으로 당겨진다
	w.use_crystal("me", "bag", 1)
	_eq("크리스탈을 다 쓰면 칸이 빠진다", me.bag.size(), 1)
	_eq("다시 굴려도 2차는 1줄", me.bag[0].get("options2", []).size(), 1)
	_eq("1차는 그대로", me.bag[0].options.size(), 0)

	# 크리스탈에 크리스탈을 쓸 수는 없다
	me.bag.append(_crystal(1))
	w.use_crystal("me", "bag", 1)
	_eq("재료에는 안 붙는다", int(me.bag[1].count), 1)

	var stats := Items.stack_stats(me.bag[0])
	var plain := Items.stack_stats({"id": "g3_r", "grade": 3, "enhance": 0, "options": []})
	var kind := str(me.bag[0].options2[0].kind)
	if not float(stats.get(kind, 0.0)) > float(plain.get(kind, 0.0)):
		_fail("2차 옵션(%s)이 능력치에 안 더해졌다" % kind)


## 끼고 있는 것에도 쓴다 — 스탯을 다시 만든다
func _case_use_worn() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.equipped["ring"] = {"id": "g1_r", "grade": 1, "enhance": 0, "options": []}
	w._refresh_stats(me)
	me.bag.append(_crystal(1))
	var before: Dictionary = me.stats.duplicate()
	w.use_crystal("me", "equip", "ring")
	_eq("낀 반지 2차 줄 수", me.equipped.ring.get("options2", []).size(), 1)
	_eq("크리스탈을 썼다", me.bag.size(), 0)
	if me.stats == before:
		_fail("낀 장비에 쓰고 스탯을 다시 안 만들었다")


func _case_no_crystal() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	w.drain_events()
	w.use_crystal("me", "bag", 0)
	if me.bag[0].has("options2"):
		_fail("크리스탈이 없는데 2차가 붙었다")
	var told := false
	for e in w.drain_events():
		if e.get("type", "") == "notice" and str(e.text).contains("크리스탈"):
			told = true
	if not told:
		_fail("크리스탈이 없다고 알려 주지 않았다")


## 접속할 때 크리스탈 30개를 **한 번만** 준다 — 저장했다 다시 들어와도 또 주지 않는다
func _case_grant_once() -> void:
	Save.clear()
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var gift := _crystal(30)
	w.grant_once("me", "crystal30", gift)
	w.grant_once("me", "crystal30", gift)
	_eq("한 번만 준다", int(me.bag[0].count), 30)
	w.save("me")

	var again := World.new()
	again.open("village")
	again.restore("me")
	again.grant_once("me", "crystal30", gift)
	var bag: Array = again.snapshot().players["me"].bag
	_eq("다시 들어와도 또 주지 않는다", int(bag[0].count), 30)


## 저장했다 불러도 크리스탈 개수와 2차가 남는다. **옛 저장(2차 칸 없음)도 그대로 읽힌다**
func _case_restore() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append(_crystal(4))
	me.bag.append({
		"id": "g2_a", "grade": 2, "enhance": 1, "options": [],
		"options2": [{"kind": "crit", "value": 3.0}],
	})
	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	w.save("me")

	var again := World.new()
	again.open("village")
	if not again.restore("me"):
		_fail("저장을 못 읽었다")
		return
	var bag: Array = again.snapshot().players["me"].bag
	_eq("되살린 가방 칸 수", bag.size(), 3)
	_eq("크리스탈 개수", int(bag[0].get("count", 0)), 4)
	_eq("2차 옵션", bag[1].get("options2", []).size(), 1)
	_eq("옛 물건은 2차 없음", bag[2].get("options2", []).size(), 0)
