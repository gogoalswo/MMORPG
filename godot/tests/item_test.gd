extends SceneTree

## 아이템 시스템 — 등급·랜덤옵션·강화·드롭·장착.
##
## 기준값은 packages/shared/src/items.ts 를 node 로 직접 돌려 뽑았다 (2026-09-17).
## **아이템 내용은 다시 만들더라도 이 규칙들은 그대로 간다.**
##
##   godot --headless --path godot --script tests/item_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_grade()
	_case_options()
	_case_enhance()
	_case_stats()
	_case_drop()
	_case_equip()
	Save.clear()

	if _failed == 0:
		print("아이템: 전부 통과")
		quit(0)
	else:
		print("아이템: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if typeof(got) == TYPE_FLOAT or typeof(want) == TYPE_FLOAT:
		if absf(float(got) - float(want)) < 1e-9:
			return
	elif got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_grade() -> void:
	_eq("등급 배율 5", Items.grade_multiplier(5), 2.2)
	_eq("옵션 등급 배율 5", Items.option_grade_scale(5), 2.4)
	# 범위 밖은 잘린다
	_eq("등급 배율 상한", Items.grade_multiplier(99), Items.grade_multiplier(10))


func _case_options() -> void:
	# 수치 옵션은 요구 레벨을 탄다
	var attack := Items.option_range("attack", 5, 100)
	_eq("공격 옵션 5등급 100레벨 최소", attack.min, 17)
	_eq("공격 옵션 5등급 100레벨 최대", attack.max, 31)
	# 퍼센트 옵션은 레벨을 타지 않는다 — 10% 는 어디서나 10% 다
	var crit := Items.option_range("crit", 10, 1)
	_eq("치명타 옵션 10등급 최소", crit.min, 4)
	_eq("치명타 옵션 10등급 최대", crit.max, 12)
	_eq("치명타는 레벨 무관", Items.option_range("crit", 10, 200).max, crit.max)

	# 굴린 옵션은 1~3개, 종류가 겹치지 않고, 범위 안이다
	var rng := RandomNumberGenerator.new()
	var item := Items.get_item("w_fighter_05")
	for seed_value in 50:
		rng.seed = seed_value
		var rolled := Items.roll_options(item, 4, rng)
		if rolled.size() < 1 or rolled.size() > 3:
			_fail("옵션이 %d개다" % rolled.size())
			return
		var seen: Array = []
		for option in rolled:
			if option.kind in seen:
				_fail("옵션 종류가 겹쳤다: %s" % option.kind)
				return
			seen.append(option.kind)
			var span := Items.option_range(str(option.kind), 4, int(item.level))
			if option.value < span.min or option.value > span.max:
				_fail("%s 값 %d 가 범위(%d~%d) 밖" % [option.kind, option.value, span.min, span.max])
				return
	print("  옵션 50번 굴림: 개수·종류·범위 모두 규칙대로")

	# 재료는 끼는 물건이 아니라 옵션이 안 붙는다
	if not Items.roll_options(Items.get_item("m_00"), 7, rng).is_empty():
		_fail("재료에 옵션이 붙었다")


func _case_enhance() -> void:
	_eq("강화 배율 +10", Items.enhance_multiplier(10), 1.8)
	_eq("강화 배율 상한", Items.enhance_multiplier(99), 1.8)
	var odds := Items.enhance_odds(7)
	_eq("+7 성공률", odds.success, 0.45)
	_eq("+7 파괴율", odds.destroy, 0.1)
	_eq("+7 굴림 0.2", Items.roll_enhance(7, 0.2), "success")
	_eq("+7 굴림 0.5", Items.roll_enhance(7, 0.5), "keep")
	_eq("+9 굴림 0.95", Items.roll_enhance(9, 0.95), "destroy")
	# 낮은 구간은 안 부서진다 — 처음부터 부서지면 강화를 아예 안 하게 된다
	_eq("+0 은 파괴 없음", Items.enhance_odds(0).destroy, 0.0)
	_eq("강화 비용 +0", Items.enhance_cost(Items.get_item("w_fighter_00"), 0), 64)
	_eq("강화 비용 +3", Items.enhance_cost(Items.get_item("w_fighter_00"), 3), 256)
	_eq("+10 이면 못 두드린다", Items.can_enhance(10), false)


func _case_stats() -> void:
	var item := Items.get_item("w_fighter_00")
	_eq("기본 공격", item.bonus.attack, 3)
	_eq("강화 +5 기본 공격", Items.base_bonus(item, 5).attack, 4)

	var stack := {
		"id": "w_fighter_00", "grade": 3, "enhance": 5,
		"options": [{"kind": "attack", "value": 4}, {"kind": "crit", "value": 7}],
	}
	var stats := Items.stack_stats(stack)
	_eq("물건 하나 공격", stats.attack, 8)
	_eq("물건 하나 치명타", stats.crit, 0.07)
	print("  물건 하나: 공격 %d, 치명타 %.2f" % [stats.attack, stats.crit])


func _case_drop() -> void:
	# 떨어지는 장비는 **잡은 사람이 쓸 수 있는 것만** 고른다
	var rng := RandomNumberGenerator.new()
	var drops := 0
	for seed_value in 200:
		rng.seed = seed_value
		var loot := Items.roll_drop(35, "fighter", rng)
		if int(loot.gold) < 1:
			_fail("골드가 0 이다")
			return
		if not loot.has("item"):
			continue
		drops += 1
		var def := Items.get_item(str(loot.item.id))
		if def.is_empty():
			_fail("없는 아이템이 떨어졌다: %s" % loot.item.id)
			return
		if def.has("job") and str(def.job) != "fighter":
			_fail("다른 직업 장비가 떨어졌다: %s" % loot.item.id)
			return
		# 35레벨 몬스터는 3단계(요구 레벨 30) 물건을 떨군다
		if int(def.level) != 30:
			_fail("단계가 안 맞다: %s (레벨 %d)" % [loot.item.id, def.level])
			return
		if int(loot.item.grade) > 7:
			_fail("8등급 이상이 떨어졌다 — 제작으로만 나와야 한다")
			return
	print("  드롭 200번: %d개 나옴 (확률 %.0f%%)" % [drops, drops / 2.0])


func _case_equip() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	var before := int(me.stats.attack)

	me.bag.append({"id": "w_fighter_00", "grade": 1, "enhance": 0, "options": [{"kind": "attack", "value": 5}]})
	w.equip("me", 0)
	if me.equipped.get("weapon", {}).is_empty():
		_fail("무기를 못 꼈다")
		return
	# 기본 3 + 옵션 5 = 8 만큼 오른다
	_eq("끼면 공격이 오른다", int(me.stats.attack), before + 8)
	_eq("가방에서 빠진다", me.bag.size(), 0)

	# 남의 직업 장비는 못 낀다
	me.bag.append({"id": "w_mage_00", "grade": 1, "enhance": 0, "options": []})
	w.equip("me", 0)
	if not me.equipped.get("weapon", {}).id == "w_fighter_00":
		_fail("마법사 무기가 끼워졌다")

	# 요구 레벨이 높은 것도 못 낀다
	me.bag.append({"id": "w_fighter_10", "grade": 1, "enhance": 0, "options": []})
	w.equip("me", me.bag.size() - 1)
	if str(me.equipped.weapon.id) != "w_fighter_00":
		_fail("100레벨 장비를 1레벨이 꼈다")

	# 벗으면 되돌아온다
	w.unequip("me", "weapon")
	_eq("벗으면 공격이 돌아온다", int(me.stats.attack), before)
	if me.equipped.has("weapon"):
		_fail("벗었는데 남아 있다")
	print("  장착: 공격 %d -> %d -> %d" % [before, before + 8, me.stats.attack])
