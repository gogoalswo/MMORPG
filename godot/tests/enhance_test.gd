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
	_case_reach()
	_case_many()
	_case_many_rounds()
	_case_fill()
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


## 목표 도달 확률 = 단계 확률의 곱 (+0→+3 = 0.9 × 0.8 × 0.7)
func _case_reach() -> void:
	_eq("+0→+3 도달", snappedf(Items.enhance_reach_odds(0, 3), 0.0001), 0.504)
	_eq("+5→+5 는 1", Items.enhance_reach_odds(5, 5), 1.0)


## 다중 강화 (리니지M "다중 강화" 그림) — 고른 가방 번호만, 겹친 칸은 한 개씩,
## 끼운 것·안 고른 것·재료·+cap 이상은 그대로. 남은 칸의 새 번호(`picked`)를 돌려준다
func _case_many() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w._rng.seed = 5
	var pile := _gear(0)
	pile.count = 4
	me.bag.append(pile)                                                     # 0 고름 — 4개
	me.bag.append({"id": "g1_a", "grade": 1, "enhance": 0, "options": []})  # 1 안 고름
	me.bag.append(_gear(3))                                                 # 2 고름
	me.bag.append({"id": Items.crystal_id(), "count": 2})                   # 3 재료(고려도 빠진다)
	me.bag.append(_gear(Items.max_enhance()))                               # 4 +9 는 빠진다
	me.equipped.weapon = _gear(1)
	w.enhance_many("me", [0, 2, 3, 4, 2, 99])
	var event := _batch_event(w)
	_eq("대상 개수", int(event.get("pieces", 0)), 5)
	_eq("성공+파괴 = 대상", int(event.success) + int(event.destroyed), 5)
	_eq("끼운 것 그대로", int(me.equipped.weapon.enhance), 1)
	_eq("안 고른 것 그대로", me.bag.filter(func(x: Dictionary) -> bool: return str(x.id) == "g1_a").size(), 1)
	_eq("재료 그대로", me.bag.filter(func(x: Dictionary) -> bool: return Items.is_material(str(x.id))).size(), 1)
	# results 는 칸마다 새 번호를 정확히 가리킨다 — 두드린 칸은 +1 / +4, +9 는 두드리지 않고
	# 번호만 따라간다 (팝업이 칸 자리를 지키며 칸별로 연출한다). 재료는 결과에 없다
	_eq("결과 칸 수 (고름 0·2·4)", (event.results as Array).map(func(r: Dictionary) -> int: return int(r.at)), [4, 2, 0])
	var alive := 0
	for r in event.results:
		for at in r.to:
			var stack: Dictionary = me.bag[int(at)]
			_eq("to 는 같은 아이템", str(stack.id), "g1_w")
			if int(r.from) == Items.max_enhance():
				_eq("+9 는 그대로", int(stack.enhance), Items.max_enhance())
			else:
				_eq("두드린 칸은 한 단계 위", int(stack.enhance), int(r.from) + 1)
				alive += int(stack.get("count", 1))
		_eq("성공+파괴 = 개수", int(r.success) + int(r.destroyed), 0 if int(r.from) == 9 else (4 if int(r.at) == 0 else 1))
	_eq("살아남은 수 = 성공 수", alive, int(event.success))
	_eq("picked = results 의 to", (event.picked as Array).size(), (event.results as Array).reduce(
		func(n: int, r: Dictionary) -> int: return n + (r.to as Array).size(), 0))
	# 고른 것이 없으면 아무것도 안 한다
	w.enhance_many("me", [1 + 99])
	_eq("대상 없음 → 이벤트 없음", _batch_event(w).is_empty(), true)


func _batch_event(w: World) -> Dictionary:
	var event: Dictionary = {}
	for e in w.drain_events():
		if str(e.get("type", "")) == "enhanceBatch":
			event = e
	return event


## 목표(cap) 바퀴 되풀이 — +cap 아래만 한 번씩 두드리고, `picked` 로 이어 가면 끝에 남은 것은
## 전부 +cap 이다 (팝업의 다중 강화가 이렇게 돈다). 사이에 안 고른 칸이 있어도 번호가 맞는다
func _case_many_rounds() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w._rng.seed = 7
	var chosen: Array = []
	for i in 12:
		me.bag.append({"id": "g1_a", "grade": 1, "enhance": 0, "options": []})  # 안 고름
		me.bag.append(_gear(1))
		chosen.append(i * 2 + 1)
	var pile := _gear(1)
	pile.count = 10
	me.bag.append(pile)
	chosen.append(me.bag.size() - 1)
	var rounds := 0
	var destroyed := 0
	while rounds < 20:
		var below := chosen.filter(func(at: int) -> bool: return int(me.bag[at].enhance) < 3)
		if below.is_empty():
			break
		w.enhance_many("me", chosen, 3)
		var event := _batch_event(w)
		destroyed += int(event.destroyed)
		chosen = event.picked
		rounds += 1
	var alive := 0
	for at in chosen:
		_eq("다 돌면 +3 뿐", int(me.bag[at].enhance), 3)
		_eq("고른 것만", str(me.bag[at].id), "g1_w")
		alive += int(me.bag[at].get("count", 1))
	_eq("남은 수 + 파괴 = 22", alive + destroyed, 22)
	_eq("안 고른 12개 그대로", me.bag.filter(
		func(x: Dictionary) -> bool: return str(x.id) == "g1_a" and int(x.enhance) == 0
	).size(), 12)
	print("  다중 +1→+3 을 %d바퀴: 22개 중 %d개 도달 (기댓값 약 12)" % [rounds, alive])


## 테스트 단추 "가방 채우기" (2026-09-24 "테스트하기 위해서 아이템을 인벤토리에 채워") —
## 빈칸을 장비로 꽉 채우고, 같은 아이템이 여럿이며 강화 단계가 섞여 있어야 다중 강화를 시험할 수 있다
func _case_fill() -> void:
	var s := _world()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.bag.append({"id": Items.crystal_id(), "count": 2})
	w.debug_fill_bag("me")
	w.drain_events()
	_eq("가방이 꽉 찬다", me.bag.size(), Items.bag_size())
	var gear: Array = me.bag.filter(func(x: Dictionary) -> bool: return not Items.get_item(str(x.id)).is_empty())
	_eq("크리스탈 말고 전부 장비", gear.size(), Items.bag_size() - 1)
	var same: Array = gear.filter(func(x: Dictionary) -> bool: return str(x.id) == str(gear[0].id))
	var levels := {}
	for x in same:
		levels[int(x.enhance)] = true
	_eq("같은 아이템이 넷 이상", same.size() >= 4, true)
	_eq("같은 아이템의 강화 단계가 섞였다", levels.size() >= 4, true)
	_eq("일곱 등급이 다 있다", gear.map(func(x: Dictionary) -> int: return int(x.grade)).max(), 7)
