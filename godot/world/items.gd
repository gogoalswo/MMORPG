class_name Items
extends RefCounted

## packages/shared/src/items.ts 이식본 — 등급·랜덤옵션·강화.
##
## **수치는 여기 적지 않는다.** 표(`data/items.json`)에서 읽는다. 아이템 내용을
## 다시 만들어도 이 규칙들은 그대로 간다 (2026-09-17 에 그러기로 했다).
##
## 굴림은 전부 `RandomNumberGenerator` 를 받는다. **굴리는 쪽은 언제나 판정하는
## 쪽**이고, 테스트가 결과를 고정할 수 있어야 하기 때문이다.

static func _t() -> Dictionary:
	return GameData.load_table("items")


static func all() -> Dictionary:
	return _t().get("items", {})


static func get_item(id: String) -> Dictionary:
	return all().get(id, {})


static func slots() -> Array:
	return _t().get("slots", [])


## 창에 적는 칸 이름. 표는 shared 의 slotLabel 이 낸다.
## `job` 은 보조 슬롯 때문에 받던 것인데 보조를 없애 쓰이지 않는다 — 부르는 쪽을
## 다 고치지 않아도 되도록 남겨 둔다
static func slot_label(slot: String, _job: String = "") -> String:
	return str(_t().get("slotLabels", {}).get(slot, slot))


static func bag_size() -> int:
	return int(_t().get("bagSize", 200))


## 설계표(`balance.json`)의 장비 쪽 — 옵션 수치도 여기 들어 있다
static func _g() -> Dictionary:
	return GameData.balance().get("gear", {})


static func max_enhance() -> int:
	return int(_t().get("maxEnhance", 10))


## 이 캐릭터가 낄 수 있나 — **판정하는 쪽이 반드시 다시 확인한다**
static func can_equip(item: Dictionary, job: String, level: int) -> bool:
	if item.is_empty() or item.get("slot", null) == null:
		return false  # 슬롯이 없는 것은 못 낀다
	if item.has("job") and str(item.job) != job:
		return false
	return level >= int(item.get("level", 1))


## 등급이 올릴 값 배율. 능력치에는 안 곱한다 — 판매가와 제작 수수료에만 쓴다
static func grade_multiplier(grade: int) -> float:
	var g := clampi(grade, int(_t().get("gradeMin", 1)), int(_t().get("gradeMax", 10)))
	return 1.0 + (g - 1) * 0.3


## 품질 등급이 옵션 수치에 주는 배율 — 1등급이 최대의 25%, 10등급이 100%.
## 0 에서 시작하지 않는다: **옵션은 1등급 물건에도 붙어야 "물건마다 다르다" 가 성립**한다
static func option_grade_scale(grade: int) -> float:
	var top := int(_g().get("optionGradeMax", 10))
	var g := clampi(grade, 1, top)
	return 0.25 + 0.75 * float(g - 1) / float(top - 1)


## **여섯 종이 전부 퍼센트다** — 공격력·방어력을 빼면서 수치로 주는 옵션이 없어졌다
static func is_percent_option(_kind: String) -> bool:
	return true


## 안 쓰는 자리 — 옛 표가 수치 옵션에 쓰던 것이다
static func _base_option_range(kind: String, level: int) -> Dictionary:
	match kind:
		"crit":
			return {"min": 1, "max": 3}
		"attackSpeed":
			return {"min": 1, "max": 3}
		"critDamage":
			return {"min": 4, "max": 10}
		"attack":
			return {"min": roundi(1 + level * 0.06), "max": roundi(1 + level * 0.12)}
		"defense":
			return {"min": roundi(1 + level * 0.04), "max": roundi(1 + level * 0.08)}
		"maxHp":
			return {"min": roundi(3 + level * 0.6), "max": roundi(5 + level * 1.2)}
	return {"min": 1, "max": 1}


## 이 등급에서 이 옵션이 나올 수 있는 범위. 창에 그대로 보여준다 —
## "몇 등급이면 얼마까지 뜨나" 를 알 수 없으면 등급을 올릴 이유를 설명할 수 없다
## 그 품질 등급에서 이 옵션이 나올 수 있는 범위 — 설계표(`balance.json`)다.
## **레벨은 안 본다.** 여섯 종이 전부 퍼센트라 어디서나 같은 뜻이라야 한다
static func option_range(kind: String, grade: int, _level: int = 1) -> Dictionary:
	var top := float(_g().get("optionMaxValue", {}).get(kind, 0.0)) * option_grade_scale(grade)
	return {"min": snappedf(top * 0.5, 0.1), "max": snappedf(top, 0.1)}


## 옵션을 굴린다. **종류는 겹치지 않게 고른다** — 치명타가 셋 붙으면 옵션이
## 하나 붙은 것과 다르지 않으면서 설명만 길어진다
static func roll_options(item: Dictionary, grade: int, rng: RandomNumberGenerator) -> Array:
	# **개수는 품질 등급이 정한다** — 등급이 오르면 개수와 수치가 같이 커진다
	var counts: Array = _g().get("optionCount", [])
	var top := int(_g().get("optionGradeMax", 10))
	var row: Array = counts[clampi(grade, 1, top) - 1] if not counts.is_empty() else [1, 1]
	var low := int(row[0])
	var high := int(row[1])
	var count := low + int(rng.randf() * (high - low + 1))
	var pool: Array = _t().get("optionKinds", []).duplicate()

	var out: Array = []
	for i in mini(count, pool.size()):
		var kind := str(pool.pop_at(int(rng.randf() * pool.size())))
		var span := option_range(kind, grade)
		# 소수 한 자리로 저장한다 — 정수로 자르면 낮은 등급에서 0 이 되어 버린다
		out.append({
			"kind": kind,
			"value": snappedf(span.min + rng.randf() * (span.max - span.min), 0.1),
		})
	return out


static func describe_option(option: Dictionary) -> String:
	var label: Dictionary = _t().get("optionLabel", {})
	var suffix := "%" if is_percent_option(str(option.kind)) else ""
	return "%s +%d%s" % [label.get(option.kind, option.kind), int(option.value), suffix]


## 강화 수치가 올리는 배율
## 강화 배율 — **설계표를 그대로 쓴다**(`Stats`). `+0` 이 1단, `+9` 가 10단이다.
## 총 배수 ×6 이고 증가율이 고강화일수록 크다 (첫 구간 : 마지막 = 1 : 7)
static func enhance_multiplier(level: int) -> float:
	return Stats.enhance_multiplier(clampi(level, 0, max_enhance()) + 1)


## +level 에서 한 번 더 두드릴 때의 확률 — **설계표 그대로**(90/80/…/10%).
##
## **"유지" 가 없다. 실패하면 무조건 파괴된다.** 재료도 값도 없으니 실패의 대가는
## 아이템 하나뿐이고 무한히 재시도할 수 있다 — 도달 단계는 "아이템이 몇 개
## 들어오느냐" 로만 결정되고, 그래서 드랍률이 경험치와 같은 급의 손잡이가 된다
static func enhance_odds(level: int) -> Dictionary:
	var odds: Array = GameData.balance().get("gear", {}).get("enhOdds", [])
	if odds.is_empty():
		return {"success": 0.9, "keep": 0.0, "destroy": 0.1}
	var success := float(odds[clampi(level, 0, odds.size() - 1)])
	return {"success": success, "keep": 0.0, "destroy": 1.0 - success}


## 한 번 두드리는 값 — **공짜다.** 설계에 강화 재료도 비용도 없다.
## 값을 매기면 강화가 "골드를 모으는 일" 이 되는데, 설계는 그 자리에 드랍을 놓았다
static func enhance_cost(_item: Dictionary, _level: int) -> int:
	return 0


static func can_enhance(level: int) -> bool:
	return level < max_enhance()


## 굴림값(0~1)에서 결과 하나 — "success" · "keep" · "destroy"
static func roll_enhance(level: int, roll: float) -> String:
	var odds := enhance_odds(level)
	var r := clampf(roll, 0.0, 0.999999)
	if r < odds.success:
		return "success"
	if r < odds.success + odds.keep:
		return "keep"
	return "destroy"


## 아이템에 박힌 기본 능력치. **등급을 타지 않는다** — 물건마다 달라지는 부분은
## 전부 옵션이 맡는다. 강화만 이 위에 곱한다
static func base_bonus(item: Dictionary, enhance: int = 0) -> Dictionary:
	var m := enhance_multiplier(enhance)
	var bonus: Dictionary = item.get("bonus", {})
	# **소수 한 자리를 남긴다** — 이 값들은 절대 수치가 아니라 **%** 라서 정수로
	# 자르면 낮은 단계에서 오차가 커진다 (등급1 갑옷 방어 8.4% → 8%)
	return {
		"attack": snappedf(float(bonus.get("attack", 0)) * m, 0.1),
		"defense": snappedf(float(bonus.get("defense", 0)) * m, 0.1),
		"maxHp": snappedf(float(bonus.get("maxHp", 0)) * m, 0.1),
		# **강화는 공격·방어·HP 에만 곱한다** — 치확·공속까지 곱하면 목걸이·반지
		# 두 자리가 강화 한 번에 다른 슬롯 넷을 합친 값을 넘어선다
		"crit": int(bonus.get("crit", 0)),
		"attackSpeed": int(bonus.get("attackSpeed", 0)),
	}


static func empty_stats() -> Dictionary:
	return {
		"attack": 0.0, "defense": 0.0, "maxHp": 0.0,
		"crit": 0.0, "critDamage": 0.0, "attackSpeed": 0.0,
		# 옵션으로만 붙는 두 축 — 쿨타임 감소와 방어력 관통
		"cooldown": 0.0, "penetration": 0.0,
	}


## 물건 하나가 주는 것 전부
static func stack_stats(stack: Dictionary) -> Dictionary:
	var total := empty_stats()
	var item := get_item(str(stack.get("id", "")))
	if item.is_empty():
		return total

	var base := base_bonus(item, int(stack.get("enhance", 0)))
	total.attack = base.attack
	total.defense = base.defense
	total.maxHp = base.maxHp
	# 치확·공속은 퍼센트 정수로 들어 있다 (목걸이 50 = +50%p)
	total.crit = base.crit / 100.0
	total.attackSpeed = base.attackSpeed / 100.0

	# 옵션 여섯 종은 전부 퍼센트다. HP 만 **기본 스탯에 곱할 %** 라 같은 자리에 더하고,
	# 나머지 다섯은 비율(0.07 = 7%)로 바꿔 담는다
	for option in stack.get("options", []):
		var value := float(option.value)
		match str(option.kind):
			"maxHp": total.maxHp += value
			"crit": total.crit += value / 100.0
			"critDamage": total.critDamage += value / 100.0
			"attackSpeed": total.attackSpeed += value / 100.0
			"cooldown": total.cooldown += value / 100.0
			"penetration": total.penetration += value / 100.0
	return total


## 장착 중인 것들이 더해주는 능력치 합
static func equipment_stats(equipped: Dictionary) -> Dictionary:
	var total := empty_stats()
	for slot in slots():
		var stack: Dictionary = equipped.get(slot, {})
		if stack.is_empty() or get_item(str(stack.get("id", ""))).is_empty():
			continue
		var one := stack_stats(stack)
		for key in total:
			total[key] += one[key]
	return total


static func tier_for_level(monster_level: int) -> int:
	return clampi(monster_level / 10, 0, int(_t().get("tierCount", 20)) - 1)


## 등급별 상대 빈도 — 한 등급 오를 때마다 절반으로 준다.
## 7등급은 전체 드롭의 1% 이하라 나오면 기억에 남는다
static func roll_grade(roll: float) -> int:
	var low := int(_t().get("gradeMin", 1))
	var high := int(_t().get("maxDropGrade", 7))
	var weights: Array = []
	var total := 0.0
	for g in range(low, high + 1):
		var w: float = pow(2.0, high - g)
		weights.append(w)
		total += w

	var cursor := clampf(roll, 0.0, 0.999999) * total
	for i in weights.size():
		cursor -= weights[i]
		if cursor < 0.0:
			return low + i
	return high


## 처치 보상을 굴린다.
## **떨어지는 장비는 잡은 사람이 쓸 수 있는 것만 고른다** — 못 쓰는 무기가
## 가방을 채우면 정리하는 게 일이 된다
static func roll_drop(monster_level: int, job: String, rng: RandomNumberGenerator) -> Dictionary:
	var base := 2.0 + monster_level * 1.5
	# ±30% 흔들어 매번 같은 숫자가 나오지 않게 한다
	var gold := maxi(1, roundi(base * (0.7 + rng.randf() * 0.6)))

	if rng.randf() >= float(_t().get("dropChance", 0.14)):
		return {"gold": gold}

	var tag := "%02d" % tier_for_level(monster_level)
	var job_slots: Array = _t().get("jobSlots", [])
	var codes: Dictionary = _t().get("slotCode", {})

	# 슬롯 8종이 고루 나와야 한다. 한쪽만 나오면 나머지 자리는 영영 빈다
	var candidates: Array = []
	for slot in slots():
		var code := str(codes.get(slot, "?"))
		candidates.append(
			"%s_%s_%s" % [code, job, tag] if slot in job_slots else "%s_%s" % [code, tag]
		)
	var id := str(candidates[mini(candidates.size() - 1, int(rng.randf() * candidates.size()))])

	var grade := roll_grade(rng.randf())
	var def := get_item(id)
	return {
		"gold": gold,
		"item": {
			"id": id,
			"grade": grade,
			"enhance": 0,
			"options": roll_options(def, grade, rng) if not def.is_empty() else [],
		},
	}


## 상점에 뜨는 것 — **자기 직업의 무기만.** 방어구·장신구는 사냥으로만 줍는다.
## 레벨 부근 것만 올린다
static func shop_stock(job: String, level: int) -> Array:
	var max_tier := tier_for_level(level)
	var out: Array = []
	for id in all():
		var item: Dictionary = all()[id]
		if str(item.get("slot", "")) != "weapon":
			continue
		if str(item.get("job", "")) != job:
			continue
		if int(item.level) <= level and tier_for_level(int(item.level)) >= max_tier - 1:
			out.append(id)
	out.sort()
	return out


## 팔 때 받는 값. **등급이 높으면 더 쳐준다** — 애써 올린 걸 헐값에 넘기면
## 팔 이유가 없다
static func sell_price(item: Dictionary, grade: int) -> int:
	return maxi(1, roundi(float(item.get("price", 0)) * 0.4 * grade_multiplier(grade)))


## 제작(등급 올리기·새로 만들기)은 2026-09-20 에 걷었다 — 장비는 사냥으로만
## 나온다. 되살리려면 이 커밋을 뒤집는 게 빠르다.
