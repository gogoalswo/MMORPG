extends SceneTree

## 장비 잠금 (2026-10-02). 상세 창 **잠금** 단추가 `toggleLock` 을 보내면 장부가 스택에
## `locked` 를 단다. 잠근 것은 판매 · 강화(단일 · 다중) · 도감 등록을 장부가 거절한다.
##
##   godot --headless --path godot --script tests/lock_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_toggle()
	_case_refuse()
	_case_codex_auto()
	_case_keep_on_equip()
	_case_transport()
	Save.clear()

	if _failed == 0:
		print("잠금: 전부 통과")
		quit(0)
	else:
		print("잠금: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _player() -> Dictionary:
	var p := Ledger.fresh("fighter")
	p.level = 200
	p.gold = 1000000000
	p.bag = []
	p.equipped = {}
	return p


func _gear(grade: int, slot: String, enhance := 0) -> Dictionary:
	return {"id": Items.item_id(grade, slot), "grade": grade, "enhance": enhance, "options": []}


func _notices(ledger: Ledger) -> Array:
	var out: Array = []
	for event in ledger.take_events():
		if str(event.get("type", "")) == "notice":
			out.append(str(event.text))
	return out


## 두 번 누르면 풀린다. 재료는 잠그지 않는다 (겹쳐서 새로 들어온 것까지 잠긴다)
func _case_toggle() -> void:
	var ledger := Ledger.new()
	var p := _player()
	p.bag.append(_gear(1, "weapon"))
	p.bag.append({"id": Items.crystal_id(), "count": 3})
	ledger.toggle_lock(p, "bag", 0)
	_eq("잠금", Items.is_locked(p.bag[0]), true)
	ledger.toggle_lock(p, "bag", 0)
	_eq("풀림", Items.is_locked(p.bag[0]), false)
	_eq("키도 지운다", p.bag[0].has("locked"), false)
	ledger.toggle_lock(p, "bag", 1)
	_eq("재료는 안 잠근다", Items.is_locked(p.bag[1]), false)
	p.equipped["ring"] = _gear(1, "ring")
	ledger.toggle_lock(p, "equip", "ring")
	_eq("낀 것도 잠근다", Items.is_locked(p.equipped.ring), true)


## 판매 · 강화 · 다중 강화 · 도감 등록(고른 칸) — 전부 거절하고 물건 · 골드는 그대로
func _case_refuse() -> void:
	var ledger := Ledger.new()
	var p := _player()
	var locked := _gear(1, "weapon", 2)
	locked.locked = true
	p.bag.append(locked)
	var gold := int(p.gold)
	ledger.take_events()

	ledger.sell(p, 0)
	_eq("판매 거절", p.bag.size(), 1)
	ledger.enhance(p, "bag", 0)
	_eq("강화 거절", int(p.bag[0].enhance), 2)
	ledger.enhance_many(p, [0])
	_eq("다중 강화 거절", int(p.bag[0].enhance), 2)
	ledger.codex_register(p, Items.item_id(1, "weapon"), 2, 0)
	_eq("도감 거절", p.bag.size(), 1)
	_eq("도감 칸 비어 있음", Codex.has(p.get("codex", {}), Items.item_id(1, "weapon"), 2), false)
	_eq("골드 그대로", int(p.gold), gold)
	var said := _notices(ledger)
	for text in ["잠근 장비는 팔 수 없습니다", "잠근 장비는 강화할 수 없습니다", "잠근 장비는 도감에 넣을 수 없습니다"]:
		_eq("알림 %s" % text, said.has(text), true)

	# 낀 것도 강화 거절
	p.equipped["ring"] = _gear(1, "ring", 1)
	p.equipped.ring.locked = true
	ledger.enhance(p, "equip", "ring")
	_eq("낀 것 강화 거절", int(p.equipped.ring.enhance), 1)
	# 강화 팝업 목록(`batch_match`)에서도 빠진다
	_eq("목록에서 빠짐", Items.batch_match(locked, "all", "", 0, 9), false)


## 도감 자동 고르기(-1)는 잠근 것을 건너뛰고 안 잠근 것을 넣는다
func _case_codex_auto() -> void:
	var ledger := Ledger.new()
	var p := _player()
	var keep := _gear(2, "boots")
	keep.locked = true
	p.bag.append(keep)
	p.bag.append(_gear(2, "boots"))
	ledger.codex_register(p, Items.item_id(2, "boots"), 0)
	_eq("하나만 남음", p.bag.size(), 1)
	_eq("남은 것은 잠근 것", Items.is_locked(p.bag[0]), true)
	# 잠근 것만 남았으면 넣지 않는다
	p.codex = {}
	ledger.codex_register(p, Items.item_id(2, "boots"), 0)
	_eq("잠근 것만 있으면 그대로", p.bag.size(), 1)


## 끼고 벗어도 잠금은 따라간다
func _case_keep_on_equip() -> void:
	var ledger := Ledger.new()
	var p := _player()
	var item := _gear(1, "armor")
	item.locked = true
	p.bag.append(item)
	ledger.equip(p, 0)
	_eq("낀 뒤 잠금", Items.is_locked(p.equipped.get("armor", {})), true)
	ledger.unequip(p, "armor")
	_eq("벗은 뒤 잠금", Items.is_locked(p.bag[0]), true)


## 화면이 보내는 요청(`toggleLock`)이 장부까지 닿고, 서버도 그 요청을 안다
func _case_transport() -> void:
	var t := LocalTransport.new()
	t.open("village")
	var me: Dictionary = t._world.snapshot().players["me"]
	me.bag.clear()
	me.bag.append(_gear(1, "necklace"))
	t.send(&"toggleLock", {"where": "bag", "key": 0})
	_eq("요청으로 잠금", Items.is_locked(me.bag[0]), true)
	_eq("서버 요청 표", str(LedgerServer.OPS.get("toggle_lock", "")), "sk")
