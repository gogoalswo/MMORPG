class_name Codex
extends RefCounted

## 장비 도감 표 읽기 — `codex.json` (원본은 packages/shared/src/codex.ts).
## 판정은 장부(`Ledger.codex_register`), 창은 `CodexPanel` → docs/features/codex.md
##
## 장부 칸 하나:
##   `codex` = { 아이템 id(등급·부위, 예 "g3_w"): 채운 강화의 비트 } — +0 이 1, +1 이 2, … +9 가 512.
##   등급·부위는 아이템 id 하나가 이미 정한다 (등급 7 × 부위 6 = 42종) — 칸 주소를 따로 만들지 않는다


static func table() -> Dictionary:
	return GameData.load_table("codex")


static func max_enhance() -> int:
	return int(table().get("maxEnhance", 9))


## 칸 비트를 다 켠 값 — +0 ~ +9 면 1023
static func full_mask() -> int:
	return (1 << (max_enhance() + 1)) - 1


## 부위가 올리는 능력치 — "attack" · "defense" · "maxHp"
static func slot_stat(slot: String) -> String:
	return str(table().get("slotStat", {}).get(slot, ""))


static func stat_name(stat: String) -> String:
	return str(table().get("statNames", {}).get(stat, stat))


## (등급, 강화) 칸 하나의 몫(%)
static func cell_value(grade: int, enhance: int) -> float:
	var cells: Array = table().get("cells", [])
	if grade < 1 or grade > cells.size():
		return 0.0
	var row: Array = cells[grade - 1]
	if enhance < 0 or enhance >= row.size():
		return 0.0
	return float(row[enhance])


## 그 칸이 찼나
static func has(codex: Dictionary, item_id: String, enhance: int) -> bool:
	return (int(codex.get(item_id, 0)) >> enhance) & 1 == 1


## **자동 등록**이 넣을 가방 번호 — 아직 빈 칸마다 하나, 같은 칸의 장비가 여럿이면 **옵션 줄(1·2·3차 합)이 가장
## 적은 것** (`Ledger.codex_register` 의 기본과 같은 셈 — 좋은 것을 남긴다). **잠근 것은 빼고** 번호 오름차순.
## 장부(`Ledger.codex_register_all`)와 확인 창(`CodexPicker.open_all`)이 같이 쓴다 → codex.md "자동 등록"
static func auto_picks(codex: Dictionary, bag: Array) -> Array:
	var best := {}
	for at in bag.size():
		var stack: Dictionary = bag[at]
		var item_id := str(stack.get("id", ""))
		var enhance := int(stack.get("enhance", 0))
		# 잠근 장비는 건너뛴다 — 장부가 도감 등록을 거절한다 (inventory-equipment.md "잠금")
		if Items.get_item(item_id).is_empty() or enhance < 0 or enhance > max_enhance() \
				or has(codex, item_id, enhance) or Items.is_locked(stack):
			continue
		var key := "%s:%d" % [item_id, enhance]
		if not best.has(key) or Items.option_lines(stack) < Items.option_lines(bag[best[key]]):
			best[key] = at
	var out: Array = best.values()
	out.sort()
	return out


## **자동 등록**(주울 때)이 노리는 칸 — `from` 강화 이상에서 **가장 낮은 빈 칸**, 다 찼으면 -1.
## 지금 단계가 비었으면 그대로 넣고, 찼으면 이 단계까지 두드려 올린다 (`Ledger._codex_auto`) → codex.md "주울 때 자동 등록"
static func next_empty(codex: Dictionary, item_id: String, from: int) -> int:
	for enhance in range(maxi(from, 0), max_enhance() + 1):
		if not has(codex, item_id, enhance):
			return enhance
	return -1


## 도감 창 [강화] 가 강화 창에 고를 가방 번호 — 그 칸(`item_id` +`enhance`)을 채우려고 **같은 장비를 목표 아래에서**
## 끌어올린다. 목표에 **가장 가까운 것**(두드릴 횟수가 적다), 같으면 옵션 줄이 적은 것. 잠근 것은 빼고
## (장부가 강화를 거절한다), 없으면 -1 → codex.md "강화 단추"
static func enhance_source(bag: Array, item_id: String, enhance: int) -> int:
	var best := -1
	for at in bag.size():
		var stack: Dictionary = bag[at]
		var level := int(stack.get("enhance", 0))
		if str(stack.get("id", "")) != item_id or level >= enhance or Items.is_locked(stack):
			continue
		if best < 0:
			best = at
			continue
		var top := int(bag[best].get("enhance", 0))
		if level > top or (level == top and Items.option_lines(stack) < Items.option_lines(bag[best])):
			best = at
	return best


## 찬 칸 수 — `grade` 를 주면 그 등급만
static func filled(codex: Dictionary, grade: int = 0) -> int:
	var count := 0
	for id in codex:
		var item := Items.get_item(str(id))
		if item.is_empty() or (grade > 0 and int(item.get("grade", 0)) != grade):
			continue
		var mask := int(codex[id])
		while mask > 0:
			count += mask & 1
			mask >>= 1
	return count


## 장부 `codex` → 능력치별 보너스 `{attack, defense, maxHp}` (%) — `World.stats_of` 가 곱한다.
## `grade` 를 주면 그 등급 칸만 더한다 (도감 창의 "이 등급" 줄)
static func stat_bonus(codex: Dictionary, grade: int = 0) -> Dictionary:
	var out := {"attack": 0.0, "defense": 0.0, "maxHp": 0.0}
	for id in codex:
		var item := Items.get_item(str(id))
		if item.is_empty() or (grade > 0 and int(item.get("grade", 0)) != grade):
			continue
		var stat := slot_stat(str(item.get("slot", "")))
		if not out.has(stat):
			continue
		var mask := int(codex[id])
		for enhance in max_enhance() + 1:
			if (mask >> enhance) & 1 == 1:
				out[stat] = float(out[stat]) + cell_value(int(item.get("grade", 0)), enhance)
	# 0.01 을 수백 번 더하면 0.30000000000000004 같은 끝자리가 남는다 — 화면이 그대로 적지 않게 자른다
	for key in out:
		out[key] = snappedf(float(out[key]), 0.01)
	return out


## 저장을 되살릴 때 — **표에 있는 장비 id 만**, 비트는 +0 ~ +9 안으로. 빈 칸은 버린다
static func clean(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for id in raw:
		if Items.get_item(str(id)).is_empty():
			continue
		var mask := int(raw[id]) & full_mask()
		if mask > 0:
			out[str(id)] = mask
	return out
