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


static func bag_size() -> int:
	return int(_t().get("bagSize", 200))


static func max_enhance() -> int:
	return int(_t().get("maxEnhance", 10))


## 이 캐릭터가 낄 수 있나 — **판정하는 쪽이 반드시 다시 확인한다**
static func can_equip(item: Dictionary, job: String, level: int) -> bool:
	if item.is_empty() or item.get("slot", null) == null:
		return false  # 재료는 못 낀다
	if item.has("job") and str(item.job) != job:
		return false
	return level >= int(item.get("level", 1))


## 등급이 올릴 값 배율. 능력치에는 안 곱한다 — 판매가와 제작 수수료에만 쓴다
static func grade_multiplier(grade: int) -> float:
	var g := clampi(grade, int(_t().get("gradeMin", 1)), int(_t().get("gradeMax", 10)))
	return 1.0 + (g - 1) * 0.3


static func option_grade_scale(grade: int) -> float:
	var g := clampi(grade, int(_t().get("gradeMin", 1)), int(_t().get("gradeMax", 10)))
	return 1.0 + (g - 1) * 0.35


static func is_percent_option(kind: String) -> bool:
	return kind in ["crit", "attackSpeed", "critDamage"]


## 1등급 기준 범위. **퍼센트 옵션은 레벨을 타지 않는다** — 10% 는 어디서나 10% 다.
## 수치 옵션은 요구 레벨을 타야 한다, 안 그러면 200레벨 장비의 공격 +3 은 장식이다
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
static func option_range(kind: String, grade: int, level: int) -> Dictionary:
	var base := _base_option_range(kind, level)
	var scale := option_grade_scale(grade)
	var low := maxi(1, roundi(base.min * scale))
	return {"min": low, "max": maxi(low, roundi(base.max * scale))}


## 옵션을 굴린다. **종류는 겹치지 않게 고른다** — 치명타가 셋 붙으면 옵션이
## 하나 붙은 것과 다르지 않으면서 설명만 길어진다
static func roll_options(item: Dictionary, grade: int, rng: RandomNumberGenerator) -> Array:
	if bool(item.get("material", false)):
		return []  # 재료는 끼는 물건이 아니다

	var low := int(_t().get("optionMin", 1))
	var high := int(_t().get("optionMax", 3))
	var count := low + int(rng.randf() * (high - low + 1))
	var pool: Array = _t().get("optionKinds", []).duplicate()

	var out: Array = []
	for i in mini(count, pool.size()):
		var kind := str(pool.pop_at(int(rng.randf() * pool.size())))
		var span := option_range(kind, grade, int(item.get("level", 1)))
		out.append({
			"kind": kind,
			"value": span.min + roundi(rng.randf() * (span.max - span.min)),
		})
	return out


static func describe_option(option: Dictionary) -> String:
	var label: Dictionary = _t().get("optionLabel", {})
	var suffix := "%" if is_percent_option(str(option.kind)) else ""
	return "%s +%d%s" % [label.get(option.kind, option.kind), int(option.value), suffix]


## 강화 수치가 올리는 배율
static func enhance_multiplier(level: int) -> float:
	return 1.0 + clampi(level, 0, max_enhance()) * 0.08


## +level 에서 한 번 더 두드릴 때의 확률.
## 낮은 구간은 거의 성공하고, 중반부터 유지가 늘고, 높은 구간에서만 부서진다 —
## 처음부터 부서지면 강화를 아예 안 하게 되고, 끝까지 안 부서지면 골드만 있으면 된다
static func enhance_odds(level: int) -> Dictionary:
	var n := maxi(0, level)
	if n <= 3:
		return {"success": 0.95, "keep": 0.05, "destroy": 0.0}
	if n <= 6:
		return {"success": 0.7, "keep": 0.3, "destroy": 0.0}
	if n <= 8:
		return {"success": 0.45, "keep": 0.45, "destroy": 0.1}
	return {"success": 0.3, "keep": 0.5, "destroy": 0.2}


static func enhance_cost(item: Dictionary, level: int) -> int:
	return roundi(float(item.get("price", 0)) * 2.0 * (maxi(0, level) + 1) * grade_multiplier(1))


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
	return {
		"attack": roundi(float(bonus.get("attack", 0)) * m),
		"defense": roundi(float(bonus.get("defense", 0)) * m),
		"maxHp": roundi(float(bonus.get("maxHp", 0)) * m),
	}


static func empty_stats() -> Dictionary:
	return {"attack": 0, "defense": 0, "maxHp": 0, "crit": 0.0, "critDamage": 0.0, "attackSpeed": 0.0}


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

	for option in stack.get("options", []):
		var value := int(option.value)
		match str(option.kind):
			"attack": total.attack += value
			"defense": total.defense += value
			"maxHp": total.maxHp += value
			"crit": total.crit += value / 100.0
			"critDamage": total.critDamage += value / 100.0
			"attackSpeed": total.attackSpeed += value / 100.0
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


## 단계 번호에서 재료 id
static func material_id_for(tier: int) -> String:
	return "m_%02d" % tier


## 아이템 id 끝에 붙은 단계 번호
static func tier_index_of(item: Dictionary) -> int:
	var id := str(item.get("id", ""))
	return int(id.substr(id.length() - 2)) if id.length() >= 2 else 0


## 상점에 뜨는 것 — **자기 직업의 무기만.** 방어구·장신구는 사냥으로 줍거나
## 대장간에서 만든다. 레벨 부근 것만 올린다
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


## 목표 등급 하나를 만드는 데 드는 재료 수
static func materials_needed(target_grade: int) -> int:
	return maxi(1, target_grade - 1)


static func craft_cost(item: Dictionary, current_grade: int) -> int:
	return roundi(float(item.get("price", 0)) * 0.5 * grade_multiplier(current_grade))


static func can_craft_up(grade: int) -> bool:
	return grade >= int(_t().get("gradeMin", 1)) and grade < int(_t().get("gradeMax", 10))


## 한 등급 올리는 데 필요한 것. 재료는 **그 장비와 같은 단계**의 것을 쓴다 —
## 낮은 단계 재료로 최상위 장비를 올릴 수 있으면 초반 보스만 반복하면 끝난다
static func craft_requirement(item: Dictionary, current_grade: int) -> Dictionary:
	if not can_craft_up(current_grade) or bool(item.get("material", false)):
		return {}
	var material := material_id_for(tier_index_of(item))
	var target := current_grade + 1
	return {
		"targetGrade": target,
		"materialId": material,
		"materialName": get_item(material).get("name", material),
		"materialCount": materials_needed(target),
		"gold": craft_cost(item, current_grade),
	}


## 새로 만들기 — 없는 걸 마련한다. **등급 올리기보다 재료를 더 쓴다**:
## 없던 걸 만드는 쪽이 싸면 아무도 줍지 않는다
static func forge_recipe(item: Dictionary) -> Dictionary:
	if bool(item.get("material", false)):
		return {}
	var material := material_id_for(tier_index_of(item))
	return {
		"itemId": item.id,
		"materialId": material,
		"materialName": get_item(material).get("name", material),
		"materialCount": int(_t().get("forgeMaterials", 5)),
		"gold": roundi(float(item.get("price", 0)) * 1.5),
	}


## 그 캐릭터가 만들 수 있는 것 — 자기 레벨까지의 장비 전부
static func forgeable_for(job: String, level: int) -> Array:
	var out: Array = []
	for id in all():
		var item: Dictionary = all()[id]
		if bool(item.get("material", false)):
			continue
		if item.has("job") and str(item.job) != job:
			continue
		if int(item.level) <= level:
			out.append(id)
	out.sort_custom(func(a, b):
		var ia: Dictionary = all()[a]
		var ib: Dictionary = all()[b]
		if int(ia.level) != int(ib.level):
			return int(ia.level) < int(ib.level)
		return str(ia.slot) < str(ib.slot)
	)
	return out
