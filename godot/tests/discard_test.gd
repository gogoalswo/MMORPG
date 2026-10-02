extends SceneTree

## 버리기 (2026-10-02). 인벤토리 "버리기" 창이 고른 가방 번호를 `discard {indices}` 로 보내면
## 장부(`Ledger.discard`)가 **장비만 · 잠그지 않은 것만** 가방에서 뺀다. 골드는 안 준다.
##
##   godot --headless --path godot --script tests/discard_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_discard()
	_case_refuse()
	_case_transport()
	Save.clear()

	if _failed == 0:
		print("버리기: 전부 통과")
		quit(0)
	else:
		print("버리기: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _player() -> Dictionary:
	var p := Ledger.fresh("fighter")
	p.gold = 100
	p.bag = []
	p.equipped = {}
	return p


func _gear(grade: int, slot: String, enhance := 0) -> Dictionary:
	return {"id": Items.item_id(grade, slot), "grade": grade, "enhance": enhance, "options": []}


## 고른 것만 빠지고 나머지 순서는 그대로 · 겹친 칸은 통째로 · 같은 번호 두 번 · 범위 밖은 무시
func _case_discard() -> void:
	var ledger := Ledger.new()
	var p := _player()
	p.bag.append(_gear(1, "weapon"))
	p.bag.append(_gear(2, "armor"))
	var pair := _gear(3, "ring")
	pair.count = 2
	p.bag.append(pair)
	p.bag.append(_gear(4, "boots"))
	ledger.discard(p, [2, 0, 2, 99, -1])
	_eq("남은 수", p.bag.size(), 2)
	_eq("남은 앞", str(p.bag[0].id), Items.item_id(2, "armor"))
	_eq("남은 뒤", str(p.bag[1].id), Items.item_id(4, "boots"))
	_eq("골드는 그대로", int(p.gold), 100)
	var notices: Array = []
	for event in ledger.take_events():
		if str(event.get("type", "")) == "notice":
			notices.append(str(event.text))
	_eq("알림 — 겹친 칸은 개수대로", notices.has("장비 3개를 버렸습니다"), true)


## 잠근 장비 · 재료는 담겨 와도 남는다
func _case_refuse() -> void:
	var ledger := Ledger.new()
	var p := _player()
	var locked := _gear(5, "weapon")
	locked.locked = true
	p.bag.append(locked)
	p.bag.append({"id": Items.crystal_id(), "count": 3})
	p.bag.append(_gear(1, "helmet"))
	ledger.discard(p, [0, 1, 2])
	_eq("잠금 · 재료만 남는다", p.bag.size(), 2)
	_eq("잠근 것", Items.is_locked(p.bag[0]), true)
	_eq("재료", str(p.bag[1].id), Items.crystal_id())
	ledger.take_events()
	ledger.discard(p, [0, 1])
	_eq("버릴 것이 없으면 그대로", p.bag.size(), 2)


func _case_transport() -> void:
	var t := LocalTransport.new()
	t.open("village")
	var me: Dictionary = t._world.snapshot().players["me"]
	me.bag.clear()
	me.bag.append(_gear(1, "necklace"))
	me.bag.append(_gear(1, "ring"))
	t.send(&"discard", {"indices": [1]})
	_eq("요청으로 버림", me.bag.size(), 1)
	_eq("남은 것", str(me.bag[0].id), Items.item_id(1, "necklace"))
	_eq("서버 요청 표", str(LedgerServer.OPS.get("discard", "")), "a")
	t.free()
