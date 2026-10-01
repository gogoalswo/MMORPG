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
