extends SceneTree

## 상세 창 강화 (2026-09-23 요청: "아이템 상세 정보창 누르면 강화 버튼 나오게 해.
## 강화는 예전에 만든 밸런스 문서 참고해서 확률 적용해").
##
## 확률은 설계 4장 그대로 — +0→+1 90% … +8→+9 10%, **실패하면 무조건 파괴**.
## NPC 없이 가방에 든 것과 끼고 있는 것 둘 다 두드린다.
##
##   godot --headless --path godot --script tests/enhance_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_odds()
	_case_rate()
	_case_stack()
	_case_worn()
	_case_max()
	Save.clear()

	if _failed == 0:
		print("강화: 전부 통과")
		quit(0)
	else:
		print("강화: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _world() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.bag.clear()
	return [w, me]


func _gear(enhance: int = 0) -> Dictionary:
	return {"id": "g1_w", "grade": 1, "enhance": enhance, "options": []}


## 설계표(stat-balance.md 4장)와 같은가 — 유지 구간은 없다
func _case_odds() -> void:
	var got: Array = []
	for level in Items.max_enhance():
		var odds := Items.enhance_odds(level)
		got.append(roundi(float(odds.success) * 100.0))
		_eq("+%d 유지" % level, float(odds.keep), 0.0)
	_eq("성공률 표", got, [90, 80, 70, 60, 50, 40, 30, 20, 10])


## 실제로 굴려서 +0→+1 이 90% 언저리인가 (씨앗 고정)
func _case_rate() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w._rng.seed = 3
	var tries := 2000
	var wins := 0
	for i in tries:
		me.bag.clear()
		me.bag.append(_gear())
		w.enhance_item("me", "bag", 0)
		if not me.bag.is_empty() and int(me.bag[0].enhance) == 1:
			wins += 1
		elif not me.bag.is_empty():
			_eq("실패하면 파괴", me.bag.size(), 0)
			return
	w.drain_events()
	var rate := float(wins) / tries
	if absf(rate - 0.9) > 0.03:
		print("  실패 +0→+1 성공률 %.3f — 0.9 언저리여야 한다" % rate)
		_failed += 1
	print("  +0→+1: %d번에 %d번 성공 (%.1f%%)" % [tries, wins, rate * 100.0])


## 겹친 칸은 한 개만 떼어서 두드린다
func _case_stack() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var seen := {"success": false, "destroy": false}
	for i in 200:
		me.bag.clear()
		var pile := _gear(8)  # 10% — 두 결과가 다 나오게
		pile.count = 3
		me.bag.append(pile)
		w.enhance_item("me", "bag", 0)
		var result := ""
		for e in w.drain_events():
			if str(e.get("type", "")) == "enhanceResult":
				result = str(e.result)
		_eq("남은 칸 개수", int(me.bag[0].count), 2)
		if result == "success":
			_eq("성공하면 뗀 것이 바로 뒤에", me.bag.size(), 2)
			_eq("뗀 것 강화", int(me.bag[1].enhance), 9)
			_eq("뗀 것 개수", int(me.bag[1].get("count", 1)), 1)
			_eq("남은 칸 강화", int(me.bag[0].enhance), 8)
		else:
			_eq("부서지면 칸은 그대로", me.bag.size(), 1)
		seen[result] = true
		if seen.success and seen.destroy:
			break
	if not (seen.success and seen.destroy):
		print("  실패 겹친 칸에서 성공·파괴를 다 못 봤다: %s" % seen)
		_failed += 1


## 끼고 있는 것 — 성공하면 능력치가 오르고, 부서지면 슬롯이 빈다
func _case_worn() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var seen := {"success": false, "destroy": false}
	for i in 200:
		me.equipped.weapon = _gear(4)  # 50%
		var attack := float(Items.equipment_stats(me.equipped).attack)
		w.enhance_item("me", "equip", "weapon")
		var now := float(Items.equipment_stats(me.equipped).attack)
		if me.equipped.has("weapon"):
			_eq("끼운 채 강화", int(me.equipped.weapon.enhance), 5)
			if now <= attack:
				print("  실패 +5 가 됐는데 장비 공격력%%가 안 올랐다 (%s → %s)" % [attack, now])
				_failed += 1
			seen.success = true
		else:
			if now >= attack:
				print("  실패 무기가 부서졌는데 장비 공격력%%가 그대로다")
				_failed += 1
			seen.destroy = true
		w.drain_events()
		if seen.success and seen.destroy:
			break
	if not (seen.success and seen.destroy):
		print("  실패 끼운 무기에서 성공·파괴를 다 못 봤다: %s" % seen)
		_failed += 1


## +9 는 끝이다 — 두드려도 그대로
func _case_max() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append(_gear(Items.max_enhance()))
	w.enhance_item("me", "bag", 0)
	_eq("+9 는 그대로", me.bag.size(), 1)
	_eq("+9 강화", int(me.bag[0].enhance), Items.max_enhance())
	# 재료(크리스탈)는 두드리지 않는다
	me.bag.clear()
	me.bag.append({"id": Items.crystal_id(), "count": 2})
	w.enhance_item("me", "bag", 0)
	_eq("크리스탈은 그대로", int(me.bag[0].count), 2)
