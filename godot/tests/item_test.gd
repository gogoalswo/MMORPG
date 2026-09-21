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
	# 품질 등급 배율 — 1등급이 최대의 25%, 10등급이 100%
	_eq("옵션 등급 배율 1", snappedf(Items.option_grade_scale(1), 0.01), 0.25)
	_eq("옵션 등급 배율 10", snappedf(Items.option_grade_scale(10), 0.01), 1.0)
	# 범위 밖은 잘린다
	_eq("등급 배율 상한", Items.grade_multiplier(99), Items.grade_multiplier(10))


## 옵션 여섯 종 — 공속·치확·치피·HP·쿨감·관통. **전부 퍼센트고 레벨을 안 탄다**
func _case_options() -> void:
	# 설계표에서 나온 최대치 (옵션 하나 = DPS +1% 에서 역산)
	var crit := Items.option_range("crit", 10)
	_eq("치명타 옵션 10등급 최소", snappedf(crit.min, 0.1), 0.8)
	_eq("치명타 옵션 10등급 최대", snappedf(crit.max, 0.1), 1.5)
	_eq("치명타는 레벨 무관", Items.option_range("crit", 10, 200).max, crit.max)
	_eq("관통 옵션 10등급 최대", snappedf(Items.option_range("penetration", 10).max, 0.1), 3.3)
	_eq("쿨감 옵션 10등급 최대", snappedf(Items.option_range("cooldown", 10).max, 0.1), 1.0)

	# 굴린 옵션은 품질 등급이 정한 개수만큼, 종류가 겹치지 않고, 범위 안이다
	var rng := RandomNumberGenerator.new()
	var item := Items.get_item("w_fighter_05")
	for seed_value in 50:
		rng.seed = seed_value
		var rolled := Items.roll_options(item, 4, rng)
		if rolled.size() != 2:
			_fail("4등급은 옵션이 2개여야 하는데 %d개다" % rolled.size())
			return
		var seen: Array = []
		for option in rolled:
			if option.kind in seen:
				_fail("옵션 종류가 겹쳤다: %s" % option.kind)
				return
			seen.append(option.kind)
			var span := Items.option_range(str(option.kind), 4)
			if option.value < span.min or option.value > span.max:
				_fail("%s 값 %s 가 범위(%s~%s) 밖" % [option.kind, option.value, span.min, span.max])
				return
	# 10등급은 넷이 붙는다 — 개수도 등급을 탄다
	rng.seed = 7
	if Items.roll_options(item, 10, rng).size() != 4:
		_fail("10등급은 옵션이 4개여야 한다")
	print("  옵션 50번 굴림: 개수·종류·범위 모두 규칙대로")


## 강화는 설계표(stat-balance.md 4장)를 그대로 쓴다 — 총 ×6, **실패하면 무조건 파괴**
func _case_enhance() -> void:
	_eq("강화 배율 +0", snappedf(Items.enhance_multiplier(0), 0.01), 1.0)
	_eq("강화 배율 +9(=10단)", snappedf(Items.enhance_multiplier(9), 0.01), 6.0)
	_eq("강화 배율 상한", Items.enhance_multiplier(99), Items.enhance_multiplier(9))
	var odds := Items.enhance_odds(7)
	_eq("+7 성공률", odds.success, 0.2)
	_eq("+7 파괴율", snappedf(odds.destroy, 0.01), 0.8)
	_eq("+7 유지율", odds.keep, 0.0)
	_eq("+7 굴림 0.1", Items.roll_enhance(7, 0.1), "success")
	_eq("+7 굴림 0.5", Items.roll_enhance(7, 0.5), "destroy")
	_eq("+8 굴림 0.95", Items.roll_enhance(8, 0.95), "destroy")
	# 첫 칸부터 10% 로 부서진다 — 아이템 자체가 연료라 재시도는 무한하다
	_eq("+0 성공률", Items.enhance_odds(0).success, 0.9)
	_eq("강화는 공짜", Items.enhance_cost(Items.get_item("a_05"), 5), 0)
	_eq("+9 면 못 두드린다", Items.can_enhance(9), false)
	_eq("+8 이면 두드릴 수 있다", Items.can_enhance(8), true)


## 장비 수치는 이제 절대값이 아니라 **기본 스탯의 %** 다 (설계 3장).
## 등급1 무기는 공격 예산 35% 의 60% = 21%
func _case_stats() -> void:
	var item := Items.get_item("w_fighter_00")
	_eq("기본 공격 %", item.bonus.attack, 21.0)
	# 강화 +5 = 6단 = ×1.78
	_eq("강화 +5 기본 공격 %", snappedf(Items.base_bonus(item, 5).attack, 0.1), 37.3)

	# 옵션은 공격력을 안 준다 — 슬롯 기본 수치가 이미 담당하기 때문이다.
	# 대신 기본이 안 건드리는 축(쿨감·관통)과 치확·치피·공속·HP 가 붙는다
	var stack := {
		"id": "w_fighter_00", "grade": 3, "enhance": 5,
		"options": [
			{"kind": "crit", "value": 0.7},
			{"kind": "penetration", "value": 1.4},
			{"kind": "cooldown", "value": 0.4},
		],
	}
	var stats := Items.stack_stats(stack)
	_eq("물건 하나 공격 %", snappedf(stats.attack, 0.1), 37.3)
	_eq("물건 하나 치명타", snappedf(stats.crit, 0.001), 0.007)
	_eq("물건 하나 관통", snappedf(stats.penetration, 0.001), 0.014)
	_eq("물건 하나 쿨감", snappedf(stats.cooldown, 0.001), 0.004)
	print("  물건 하나: 공격 %.1f%%, 치확 %.3f, 관통 %.3f, 쿨감 %.3f" % [
		stats.attack, stats.crit, stats.penetration, stats.cooldown
	])


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
		# **사냥터가 등급을 정한다** — Lv35 는 사냥터 4 라 1등급만 나와야 한다
		if not (int(loot.item.grade) in Items.drop_grades(35)):
			_fail("사냥터 4 에서 %d등급이 떨어졌다" % loot.item.grade)
			return
	print("  드롭 200번: %d개 나옴 (확률 %.0f%%) — 전부 %s등급" % [
		drops, drops / 2.0, str(Items.drop_grades(35))
	])

	# 사냥터마다 나오는 등급이 다르다. 표는 shared 가 만들고 여기는 읽기만 한다
	var want := {1: [1], 45: [1, 2], 75: [2, 3], 105: [3, 4], 135: [4, 5], 165: [5, 6], 195: [6, 7]}
	for level in want:
		if Items.drop_grades(int(level)) != want[level]:
			_fail("Lv%d 등급이 %s 인데 %s 여야 한다" % [level, Items.drop_grades(int(level)), want[level]])
	# 최고 등급은 마지막 사냥터에서만
	for level in [1, 50, 100, 150, 190]:
		if 7 in Items.drop_grades(int(level)):
			_fail("Lv%d 에서 최고 등급이 나온다" % level)
	print("  사냥터별 등급: Lv1 [1] · Lv75 [2,3] · Lv195 [6,7] (7등급은 마지막 사냥터만)")


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
	# 장비는 **곱한다** — 맨몸 공격에 (1 + 장비 % 합계) 를 곱한 값이 된다
	if int(me.stats.attack) <= before:
		_fail("끼면 공격이 올라야 한다 (%d -> %d)" % [before, int(me.stats.attack)])
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
