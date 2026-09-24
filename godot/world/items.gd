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


## --- 재료 (크리스탈) ---
## 장비 표(`items`)와 따로 있다 — 넣으면 슬롯·등급을 묻는 자리마다 "장비가 아니면"
## 을 걸어야 한다. 가방에는 `{ id, count }` 로 겹쳐 쌓인다 (shared 의 `MATERIALS`)

static func get_material(id: String) -> Dictionary:
	return _t().get("materials", {}).get(id, {})


static func is_material(id: String) -> bool:
	return not get_material(id).is_empty()


## 스킬 경험치북이면 넣는 경험치, 아니면 0 (`SKILL_EXP_BOOKS` → 재료의 `skillExp`)
static func book_exp(id: String) -> int:
	return int(get_material(id).get("skillExp", 0))


static func crystal_id() -> String:
	return str(_t().get("crystalId", "crystal"))


static func crystal_drop_chance() -> float:
	return float(_t().get("crystalDropChance", 0.0))


## 가방 물건의 이름 — 장비든 재료든
static func stack_name(stack: Dictionary) -> String:
	var id := str(stack.get("id", ""))
	if is_material(id):
		return str(get_material(id).get("name", id))
	return str(get_item(id).get("name", id))


static func slots() -> Array:
	return _t().get("slots", [])


## 창에 적는 칸 이름. 표는 shared 의 slotLabel 이 낸다.
## `job` 은 보조 슬롯 때문에 받던 것인데 보조를 없애 쓰이지 않는다 — 부르는 쪽을
## 다 고치지 않아도 되도록 남겨 둔다
static func slot_label(slot: String, _job: String = "") -> String:
	return str(_t().get("slotLabels", {}).get(slot, slot))


static func bag_size() -> int:
	return int(_t().get("bagSize", 200))


## 등급 이름 (1 일반 → 7 태초). 표는 shared 의 gradeName 이 낸다
static func grade_name(grade: int) -> String:
	var names: Array = _t().get("gradeNames", [])
	if names.is_empty():
		return "%d등급" % grade
	return str(names[clampi(grade - 1, 0, names.size() - 1)])


## 등급 색. 표(shared 의 GRADE_COLOR)는 어두운 흙빛에서 시작하므로
## 어두운 창 위에 글자로 쓸 때는 부르는 쪽이 밝혀 쓴다
static func grade_color(grade: int) -> Color:
	var colors: Array = _t().get("gradeColors", [])
	if colors.is_empty():
		return Color.WHITE
	return Color(str(colors[clampi(grade - 1, 0, colors.size() - 1)]))


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
	var top := int(_g().get("optionGradeMax", 7))
	var g := clampi(grade, 1, top)
	return pow(float(_g().get("optionStep", 0.65)), float(top - g))


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
## 그 등급에서 이 옵션이 나올 수 있는 범위 — 설계표(`balance.json`)다.
## **레벨은 안 본다.** 여섯 종이 전부 퍼센트라 어디서나 같은 뜻이라야 한다
## **최소는 최대의 절반이다** (2026-09-21: "최소 최대 수치가 50% 상한을 둬").
## 배수(`optionPower`)를 곱하고 정수로 끊는다 — `gear.ts` 의 `optionRange` 와 같은 순서다
static func option_range(kind: String, grade: int, _level: int = 1) -> Dictionary:
	var power := float(_g().get("optionPower", 1.0))
	var top := float(_g().get("optionMaxValue", {}).get(kind, 0.0)) * power * option_grade_scale(grade)
	return {"min": float(roundi(top * 0.5)), "max": float(roundi(top))}


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


## --- 옵션 차수 ---
## **1차는 드랍, 2차는 크리스탈, 3차는 비워 둔다** (2026-09-23). 표는 `optionTiers`
## — 차수마다 저장 칸(`options` · `options2` · `options3`)과 줄 수가 있다.
## 수치 범위는 셋 다 장비 등급의 `option_range` 다

static func option_tiers() -> Array:
	return _t().get("optionTiers", [])


static func option_tier(tier: int) -> Dictionary:
	for row in option_tiers():
		if int(row.get("tier", 0)) == tier:
			return row
	return {}


## 그 차수의 옵션을 굴린다. 종류는 **같은 차수 안에서만** 안 겹친다
static func roll_tier_options(tier: int, grade: int, rng: RandomNumberGenerator) -> Array:
	var count := int(option_tier(tier).get("count", 0))
	var pool: Array = _t().get("optionKinds", []).duplicate()
	var out: Array = []
	for i in mini(count, pool.size()):
		var kind := str(pool.pop_at(int(rng.randf() * pool.size())))
		var span := option_range(kind, grade)
		out.append({
			"kind": kind,
			"value": snappedf(span.min + rng.randf() * (span.max - span.min), 0.1),
		})
	return out


static func describe_option(option: Dictionary) -> String:
	var label: Dictionary = _t().get("optionLabel", {})
	# 저장된 옛 아이템의 공격력·방어력 옵션 — 지금 표에 없어 영어 키가 찍혔다 (2026-09-23).
	# 옛 값은 퍼센트가 아니라 고정 수치다
	var legacy: Dictionary = _t().get("legacyOptionLabel", {})
	if legacy.has(option.kind):
		return "%s +%d" % [legacy[option.kind], int(option.value)]
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


## +from 에서 +goal 까지 **한 번도 안 부서지고** 오를 확률 — 단계 확률의 곱.
## 자동 강화 팝업이 "목표 도달" 로 적는다
static func enhance_reach_odds(from: int, goal: int) -> float:
	var odds := 1.0
	for level in range(maxi(from, 0), mini(goal, max_enhance())):
		odds *= float(enhance_odds(level).success)
	return odds


## 일괄 강화에 드는 칸인가 — **판정(World)과 팝업이 같은 규칙을 쓴다.**
## 장비이고, `mode` 가 "item" 이면 같은 아이템(id·등급), "grade" 면 같은 등급,
## 그리고 강화가 `cap` 아래인 것. 재료·+cap 이상은 빠진다
static func batch_match(stack: Dictionary, mode: String, ref_id: String, grade: int, cap: int) -> bool:
	if get_item(str(stack.get("id", ""))).is_empty():
		return false
	if int(stack.get("enhance", 0)) >= mini(cap, max_enhance()):
		return false
	if int(stack.get("grade", 1)) != grade:
		return false
	match mode:
		"item": return str(stack.get("id", "")) == ref_id
		"grade": return true
	return false


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
	# 나머지 다섯은 비율(0.07 = 7%)로 바꿔 담는다. **1·2·3차를 다 더한다**
	var options: Array = []
	for row in option_tiers():
		options.append_array(stack.get(str(row.key), []))
	for option in options:
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


## 그 레벨에서 낄 수 있는 가장 높은 등급 (1~7). 표(`gradeLevels`)를 거꾸로 훑는다 —
## 30레벨 간격을 고도에도 적어 두면 두 곳이 어긋난다
static func grade_for_level(level: int) -> int:
	var levels: Array = _t().get("gradeLevels", [])
	var top := int(_t().get("gradeMin", 1))
	for i in levels.size():
		if level >= int(levels[i]):
			top = i + 1
	return top


## 아이템 id — `g{등급}_{슬롯코드}`. 만드는 규칙은 `packages/shared/src/items.ts` 와 같다
static func item_id(grade: int, slot: String) -> String:
	return "g%d_%s" % [grade, str(_t().get("slotCode", {}).get(slot, "?"))]


## 옛 id 를 지금 id 로 — **한 번 쓰고 버릴 다리다.** ★
##
## 2026-09-21 에 단계 20개 축을 없애면서 `w_fighter_07`·`a_07` 이 전부 사라졌다.
## 그냥 두면 저장에 남은 가방이 통째로 빈다. 단계는 요구 레벨을 거쳐 등급으로
## 옮길 수 있다 (단계 7 = Lv70 = 3등급). 빈 문자열이면 갈 자리가 없다는 뜻이다
static func migrate_id(id: String) -> String:
	if not get_item(id).is_empty():
		return id
	var parts := id.split("_")
	if parts.size() < 2:
		return ""
	var tier := int(str(parts[parts.size() - 1]))
	var code := str(parts[0])
	var codes: Dictionary = _t().get("slotCode", {})
	for slot in codes:
		if str(codes[slot]) == code:
			return item_id(grade_for_level(1 if tier == 0 else tier * 10), str(slot))
	return ""


## 그 몬스터가 선 사냥터(1~20). `items.json` 의 `dropGrades` 를 찾는 열쇠다
static func field_of(monster_level: int) -> int:
	return clampi(ceili(monster_level / 10.0), 1, 20)


## 그 몬스터가 떨굴 수 있는 등급들 — **사냥터가 정한다.** ★
##
## 2026-09-21 요청: "지금 상태면 1레벨짜리 잡고 최종템을 먹을수도 있는거자나."
## 표는 `packages/shared/src/gear.ts` 의 `dropField` 에서 나오고 여기는 읽기만
## 한다 → docs/features/items.md "사냥터가 등급을 정한다"
## **정수로 돌려준다** — JSON 숫자는 실수로 들어와서 `1 in [1.0]` 이 false 다
static func drop_grades(monster_level: int) -> Array:
	var table: Array = _t().get("dropGrades", [])
	var field := field_of(monster_level)
	var row: Array = table[field] if field < table.size() else []
	if row.is_empty():
		return [int(_t().get("gradeMin", 1))]
	var out: Array = []
	for g in row:
		out.append(int(g))
	return out


## 등급 하나의 킬당 확률(0~1). 표는 **퍼센트 단위**라 100 으로 나눈다
static func grade_drop_rate(grade: int) -> float:
	var rates: Array = _t().get("gradeDropRate", [])
	if rates.is_empty():
		return 0.0
	return float(rates[clampi(grade, 1, rates.size()) - 1]) / 100.0


## 그 몬스터가 장비를 떨굴 확률 — 창에 든 등급들의 확률을 **더한 값**이다.
##
## 2026-09-21 까지는 `dropChance` 평면값 0.14 였다. 설계값(`GEAR_DROP_RATE`)은
## `balance.json` 에 있기만 하고 판정이 안 읽고 있었다 → docs/features/items.md
static func drop_chance(monster_level: int) -> float:
	var sum := 0.0
	for g in drop_grades(monster_level):
		sum += grade_drop_rate(int(g))
	return sum


## 그 사냥터 안에서 등급 하나 — **설계의 등급별 드랍률 비 그대로.**
## 예전에는 2^(n-g) 로 임의로 반씩 깎았는데, 설계가 절대 확률을 정해 두었으므로
## 그 비로 나누면 두 값이 어긋날 일이 없다
static func roll_grade(roll: float, monster_level: int) -> int:
	var grades := drop_grades(monster_level)
	var weights: Array = []
	var total := 0.0
	for g in grades:
		var w := grade_drop_rate(int(g))
		weights.append(w)
		total += w

	var cursor := clampf(roll, 0.0, 0.999999) * total
	for i in weights.size():
		cursor -= weights[i]
		if cursor < 0.0:
			return int(grades[i])
	return int(grades[grades.size() - 1])


## 처치 보상을 굴린다.
## **떨어지는 장비는 잡은 사람이 쓸 수 있는 것만 고른다** — 못 쓰는 무기가
## 가방을 채우면 정리하는 게 일이 된다
static func roll_drop(monster_level: int, job: String, rng: RandomNumberGenerator) -> Dictionary:
	var base := 2.0 + monster_level * 1.5
	# ±30% 흔들어 매번 같은 숫자가 나오지 않게 한다
	var gold := maxi(1, roundi(base * (0.7 + rng.randf() * 0.6)))

	# 크리스탈은 장비와 **따로** 굴린다. 순서는 골드 → 장비 → (슬롯 → 등급 → 옵션) → 크리스탈
	# — `items.ts` 와 같은 순서라야 같은 씨앗에서 같은 것이 나온다
	var drop := {"gold": gold}
	if rng.randf() < drop_chance(monster_level):
		drop["item"] = _roll_gear_drop(monster_level, rng)
	if rng.randf() < crystal_drop_chance():
		drop["crystal"] = 1
	return drop


static func _roll_gear_drop(monster_level: int, rng: RandomNumberGenerator) -> Dictionary:
	# 슬롯은 고루 나와야 한다 — 한쪽만 나오면 나머지 자리는 영영 빈다.
	# 직업은 더 이상 후보를 가르지 않는다. **굴리는 순서는 슬롯 → 등급** —
	# `items.ts` 와 같은 순서라야 같은 씨앗에서 같은 것이 나온다
	var all_slots := slots()
	var pick := mini(all_slots.size() - 1, int(rng.randf() * all_slots.size()))
	var grade := roll_grade(rng.randf(), monster_level)
	var id := item_id(grade, str(all_slots[pick]))
	var def := get_item(id)
	return {
		"id": id,
		"grade": grade,
		"enhance": 0,
		"options": roll_options(def, grade, rng) if not def.is_empty() else [],
	}


## 상점에 뜨는 것 — **무기만.** 방어구·장신구는 사냥으로만 줍는다.
## 장비가 직업을 안 타므로(2026-09-21) 진열은 등급으로만 거른다 —
## 낄 수 있는 등급과 그 아래 하나까지 (아래를 같이 두는 건 강화 여벌 때문이다)
static func shop_stock(_job: String, level: int) -> Array:
	var top := grade_for_level(level)
	var out: Array = []
	for id in all():
		var item: Dictionary = all()[id]
		if str(item.get("slot", "")) != "weapon":
			continue
		if int(item.level) <= level and int(item.get("grade", 1)) >= top - 1:
			out.append(id)
	out.sort()
	return out


## 팔 때 받는 값. **등급이 높으면 더 쳐준다** — 애써 올린 걸 헐값에 넘기면
## 팔 이유가 없다
static func sell_price(item: Dictionary, grade: int) -> int:
	return maxi(1, roundi(float(item.get("price", 0)) * 0.4 * grade_multiplier(grade)))


## 제작(등급 올리기·새로 만들기)은 2026-09-20 에 걷었다 — 장비는 사냥으로만
## 나온다. 되살리려면 이 커밋을 뒤집는 게 빠르다.
