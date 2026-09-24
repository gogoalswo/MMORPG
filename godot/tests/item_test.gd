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
	_case_option_steps()
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
	# 옵션 등급 배율 — 7등급이 100%, 한 칸 내려갈 때마다 ×0.65 (등비).
	# 2026-09-21 에 선형(25%→100%)에서 등비로 바꿨다 — 선형이면 후반 한 칸(+14%)이
	# 굴림 폭(±33%)보다 작아 "이전 등급이 더 좋은" 물건이 나왔다
	_eq("옵션 등급 배율 1", snappedf(Items.option_grade_scale(1), 0.01), 0.08)
	_eq("옵션 등급 배율 6", snappedf(Items.option_grade_scale(6), 0.01), 0.65)
	_eq("옵션 등급 배율 7", snappedf(Items.option_grade_scale(7), 0.01), 1.0)
	# 범위 밖은 잘린다
	_eq("등급 배율 상한", Items.grade_multiplier(99), Items.grade_multiplier(7))


## 옵션 여섯 종 — 공속·치확·치피·HP·쿨감·관통. **전부 퍼센트고 레벨을 안 탄다**
func _case_options() -> void:
	# 설계표에서 나온 최대치 (옵션 하나 = DPS +1% 에서 역산)
	# 2026-09-21 에 옵션 수치를 **50배**로 올렸다 (`OPTION_POWER`) —
	# 반올림 다음에 곱하므로 태초 치확이 37.5 가 아니라 **40~75** 다
	var crit := Items.option_range("crit", 7)
	_eq("치명타 옵션 7등급 최소", snappedf(crit.min, 0.1), 38.0)
	_eq("치명타 옵션 7등급 최대", snappedf(crit.max, 0.1), 75.0)
	_eq("치명타는 레벨 무관", Items.option_range("crit", 7, 200).max, crit.max)
	_eq("관통 옵션 7등급 최대", snappedf(Items.option_range("penetration", 7).max, 0.1), 165.0)
	_eq("쿨감 옵션 7등급 최대", snappedf(Items.option_range("cooldown", 7).max, 0.1), 50.0)

	# 굴린 옵션은 등급이 정한 개수만큼, 종류가 겹치지 않고, 범위 안이다
	var rng := RandomNumberGenerator.new()
	var item := Items.get_item("g3_w")
	for seed_value in 50:
		rng.seed = seed_value
		var rolled := Items.roll_options(item, 4, rng)
		if rolled.size() != 1:
			_fail("옵션은 1개 고정인데 %d개다" % rolled.size())
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
	# 개수는 등급을 안 탄다 — 2026-09-24 지시로 전 등급 1개 고정이다
	rng.seed = 7
	if Items.roll_options(item, 7, rng).size() != 1:
		_fail("7등급도 옵션은 1개여야 한다")
	print("  옵션 50번 굴림: 개수·종류·범위 모두 규칙대로")


## 옵션 수치는 5단계 확률(40·30·20·8·2%)이다 — 2026-09-24 지시. 1차·2차가 같은 함수를 탄다
func _case_option_steps() -> void:
	var weights: Array = Items._t().get("optionStepWeights", [])
	_eq("단계 확률", weights, [40.0, 30.0, 20.0, 8.0, 2.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts := [0, 0, 0, 0, 0]
	var rolls := 50000
	for i in rolls:
		var value := Items.roll_option_value({"min": 0.0, "max": 1000.0}, rng)
		counts[mini(4, int(value / 200.0))] += 1
	for step in 5:
		var got: float = 100.0 * counts[step] / rolls
		if absf(got - float(weights[step])) > 1.0:
			_fail("%d단계가 %.1f%% 나왔다 (설계 %d%%)" % [step + 1, got, int(weights[step])])
	print("  옵션 수치 5단계: %s / %d번" % [str(counts), rolls])


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
	_eq("강화는 공짜", Items.enhance_cost(Items.get_item("g3_a"), 5), 0)
	_eq("+9 면 못 두드린다", Items.can_enhance(9), false)
	_eq("+8 이면 두드릴 수 있다", Items.can_enhance(8), true)


## 장비 수치는 이제 절대값이 아니라 **기본 스탯의 %** 다 (설계 3장).
## 등급1 무기는 공격 예산 35% 의 60% = 21%
func _case_stats() -> void:
	var item := Items.get_item("g1_w")
	_eq("기본 공격 %", item.bonus.attack, 17.5)
	# 강화 +5 = 6단 = ×1.78
	_eq("강화 +5 기본 공격 %", snappedf(Items.base_bonus(item, 5).attack, 0.1), 31.1)

	# 옵션은 공격력을 안 준다 — 슬롯 기본 수치가 이미 담당하기 때문이다.
	# 대신 기본이 안 건드리는 축(쿨감·관통)과 치확·치피·공속·HP 가 붙는다
	var stack := {
		"id": "g1_w", "grade": 1, "enhance": 5,
		"options": [
			{"kind": "crit", "value": 0.7},
			{"kind": "penetration", "value": 1.4},
			{"kind": "cooldown", "value": 0.4},
		],
	}
	var stats := Items.stack_stats(stack)
	_eq("물건 하나 공격 %", snappedf(stats.attack, 0.1), 31.1)
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
	# **20,000번 돌린다.** 설계 드랍률을 붙이고 나서 Lv35 는 340마리에 하나라
	# 200번으로는 0개가 나와 아무것도 확인이 안 된다 (2026-09-21)
	for seed_value in 20000:
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
		# 장비는 직업을 안 탄다 (2026-09-21)
		if def.has("job"):
			_fail("직업을 타는 장비가 떨어졌다: %s" % loot.item.id)
			return
		# 등급이 곧 요구 레벨이다. Lv35 는 사냥터 4 라 1등급(요구 Lv1)만 나온다
		if int(def.level) != 1:
			_fail("등급이 안 맞다: %s (요구 레벨 %d)" % [loot.item.id, def.level])
			return
		# **사냥터가 등급을 정한다** — Lv35 는 사냥터 4 라 1등급만 나와야 한다
		if not (int(loot.item.grade) in Items.drop_grades(35)):
			_fail("사냥터 4 에서 %d등급이 떨어졌다" % loot.item.grade)
			return
	if drops == 0:
		_fail("20,000번 돌렸는데 하나도 안 떨어졌다")
	# 설계값(stat-balance.md 7장)과 맞나 — 1등급 0.2963%
	var by_design := Items.drop_chance(35)
	var measured := float(drops) / 20000.0
	if absf(measured - by_design) > by_design * 0.35:
		_fail("드랍률이 %.4f%% 여야 하는데 %.4f%%" % [by_design * 100.0, measured * 100.0])
	else:
		print("  드롭 20,000번: %d개 (%.4f%%, 설계 %.4f%%) — 전부 %s등급" % [
			drops, measured * 100.0, by_design * 100.0, str(Items.drop_grades(35))
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

	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": [{"kind": "attack", "value": 5}]})
	w.equip("me", 0)
	if me.equipped.get("weapon", {}).is_empty():
		_fail("무기를 못 꼈다")
		return
	# 장비는 **곱한다** — 맨몸 공격에 (1 + 장비 % 합계) 를 곱한 값이 된다
	if int(me.stats.attack) <= before:
		_fail("끼면 공격이 올라야 한다 (%d -> %d)" % [before, int(me.stats.attack)])
	_eq("가방에서 빠진다", me.bag.size(), 0)

	# 요구 레벨이 높은 것은 못 낀다 (직업 제한은 2026-09-21 에 없어졌다)
	me.bag.append({"id": "g4_w", "grade": 4, "enhance": 0, "options": []})
	w.equip("me", me.bag.size() - 1)
	if str(me.equipped.weapon.id) != "g1_w":
		_fail("91레벨 장비를 1레벨이 꼈다")

	# 벗으면 되돌아온다
	w.unequip("me", "weapon")
	_eq("벗으면 공격이 돌아온다", int(me.stats.attack), before)
	if me.equipped.has("weapon"):
		_fail("벗었는데 남아 있다")
	print("  장착: 공격 %d -> %d -> %d" % [before, before + 8, me.stats.attack])
