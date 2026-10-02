extends SceneTree

## 자동 장착 (2026-10-02). 인벤토리의 **자동장착** 단추가 `autoEquip` 을 보내면
## 장부가 부위마다 전투력(`Ledger.gear_power`)이 가장 높아지는 것을 낀다.
##
##   godot --headless --path godot --script tests/auto_equip_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_upgrade()
	_case_level_gate()
	_case_keep_better()
	_case_best_everywhere()
	_case_transport()
	Save.clear()

	if _failed == 0:
		print("자동 장착: 전부 통과")
		quit(0)
	else:
		print("자동 장착: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _world(level: int) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.level = level
	me.bag.clear()
	me.equipped.clear()
	return [w, me]


func _gear(grade: int, slot: String, enhance := 0) -> Dictionary:
	return {"id": Items.item_id(grade, slot), "grade": grade, "enhance": enhance, "options": []}


func _notices(w: World) -> Array:
	var out: Array = []
	for event in w.drain_events():
		if str(event.get("type", "")) == "notice":
			out.append(str(event.text))
	return out


## 높은 등급이 가방에 있으면 바꿔 끼고, 벗은 것은 가방으로. 빈 부위는 채운다
func _case_upgrade() -> void:
	var made := _world(200)
	var w: World = made[0]
	var me: Dictionary = made[1]
	me.equipped["weapon"] = _gear(1, "weapon")
	me.bag.append(_gear(3, "weapon"))
	me.bag.append(_gear(2, "armor"))
	me.bag.append({"id": Items.crystal_id(), "count": 5})
	w.drain_events()
	w.auto_equip("me")
	_eq("무기 바꿈", str(me.equipped.weapon.id), Items.item_id(3, "weapon"))
	_eq("빈 갑옷 채움", str(me.equipped.get("armor", {}).get("id", "")), Items.item_id(2, "armor"))
	var ids: Array = me.bag.map(func(s: Dictionary) -> String: return str(s.id))
	_eq("벗은 무기는 가방에", ids.has(Items.item_id(1, "weapon")), true)
	_eq("크리스탈은 그대로", ids.has(Items.crystal_id()), true)
	_eq("가방 수", me.bag.size(), 2)
	_eq("알림", _notices(w).has("자동 장착 — 2부위를 바꿨습니다"), true)


## 착용 레벨이 모자라면 후보가 아니다
func _case_level_gate() -> void:
	var made := _world(1)
	var w: World = made[0]
	var me: Dictionary = made[1]
	me.bag.append(_gear(7, "weapon"))
	me.bag.append(_gear(1, "weapon"))
	w.auto_equip("me")
	_eq("낄 수 있는 것만", str(me.equipped.get("weapon", {}).get("id", "")), Items.item_id(1, "weapon"))
	_eq("못 끼는 건 가방에", str(me.bag[0].id), Items.item_id(7, "weapon"))


## 이미 좋은 걸 끼고 있으면 아무것도 안 바꾼다
func _case_keep_better() -> void:
	var made := _world(200)
	var w: World = made[0]
	var me: Dictionary = made[1]
	me.equipped["weapon"] = _gear(5, "weapon")
	me.bag.append(_gear(2, "weapon"))
	w.drain_events()
	w.auto_equip("me")
	_eq("그대로", str(me.equipped.weapon.id), Items.item_id(5, "weapon"))
	_eq("가방 그대로", me.bag.size(), 1)
	_eq("알림", _notices(w).has("이미 가장 좋은 장비를 끼고 있습니다"), true)


## 섞인 가방 — 끝나면 어느 부위든 가방의 어떤 것으로 바꿔도 전투력이 오르지 않는다
## (강화 높은 낮은 등급 vs 무강 높은 등급처럼 등급만으로 못 가르는 것까지)
func _case_best_everywhere() -> void:
	var made := _world(200)
	var w: World = made[0]
	var me: Dictionary = made[1]
	for slot in Items.slots():
		me.equipped[slot] = _gear(1, slot)
		for grade in [3, 4, 5]:
			for enhance in [0, 5, 9]:
				me.bag.append(_gear(grade, slot, enhance))
	w.auto_equip("me")
	var now := Ledger.gear_power(me, me.equipped)
	for stack in me.bag:
		var slot := str(Items.get_item(str(stack.id)).get("slot", ""))
		var trial: Dictionary = me.equipped.duplicate()
		trial[slot] = stack
		if Ledger.gear_power(me, trial) > now:
			_eq("더 나은 것이 남음 %s" % stack.id, false, true)
			return
	_eq("물건 수는 그대로", me.bag.size() + me.equipped.size(), 6 * 9 + 6)


## 화면이 보내는 요청(`autoEquip`)이 장부까지 닿는다
func _case_transport() -> void:
	var t := LocalTransport.new()
	t.open("village")
	var me: Dictionary = t._world.snapshot().players["me"]
	me.level = 200
	me.bag.clear()
	me.equipped.clear()
	me.bag.append(_gear(2, "boots"))
	t.send(&"autoEquip", {})
	_eq("요청으로 낌", str(me.equipped.get("boots", {}).get("id", "")), Items.item_id(2, "boots"))
