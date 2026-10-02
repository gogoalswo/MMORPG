extends SceneTree

## 샌드백 랭킹전 (docs/features/sandbag.md) — 3초 카운트 → 15초 동안 넣은 피해를 센다 → 주 최고 기록 →
## 주가 바뀌면 순위로 옐로우 크리스탈. 로컬(혼자 = 1위)과 서버(모든 계정을 줄 세운다) 둘 다 본다.
## 옐로우 크리스탈로 3차 옵션을 굴리는 것도 여기서 본다 (items.md "옵션 차수와 크리스탈")
##
##   godot --headless --path godot --script tests/sandbag_test.gd

const DIR := "user://test_sandbag_accounts"
var _failed := 0


func _init() -> void:
	Save.clear()
	_wipe()
	_case_zone()
	_case_countdown()
	_case_auto()
	_case_count_and_finish()
	_case_local_week()
	_case_save()
	_case_yellow_crystal()
	_case_server()
	_wipe()
	if _failed == 0:
		print("샌드백: 전부 통과")
		quit(0)
	else:
		print("샌드백: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _all(events: Array, type_name: String) -> Array:
	return events.filter(func(e): return str(e.get("type", "")) == type_name)


func _count(me: Dictionary, id: String) -> int:
	for stack in me.bag:
		if str(stack.get("id", "")) == id:
			return int(stack.get("count", 1))
	return 0


func _wipe() -> void:
	var path := ProjectSettings.globalize_path(DIR)
	for sub in ["sandbag", ""]:
		var at := path.path_join(sub) if sub != "" else path
		var dir := DirAccess.open(at)
		if dir == null:
			continue
		for name in dir.get_files():
			dir.remove(name)
		DirAccess.remove_absolute(at)


## 마을에서 HUD 단추로 들어온 캐릭터 — 입장 창의 입장과 같은 `travel`
func _enter(clock: Array = []) -> World:
	var w := World.new()
	if not clock.is_empty():
		w.set_unix_clock(func() -> float: return float(clock[0]))
	w.open("village")
	w.join("me")
	w.snapshot().players["me"].level = 50
	w.travel("me", Sandbag.zone())
	w.drain_events()
	return w


func _bag_of(w: World) -> Dictionary:
	return w.snapshot().players["me"]


## 둘이 나란히 · 샌드백 하나 · 판이 열린다
func _case_zone() -> void:
	var w := _enter()
	var snap := w.snapshot()
	var mobs: Array = snap.monsters
	if mobs.size() != 1 or not bool(mobs[0].get("dummy", false)):
		_fail("샌드백 하나여야 한다: %s" % str(mobs.map(func(m): return m.kind)))
		return
	var me: Dictionary = snap.players.me
	var gap := Vector2(float(mobs[0].x) - float(me.x), float(mobs[0].z) - float(me.z)).length()
	if gap > 2.2:
		_fail("샌드백이 사거리(2.2) 밖이다: %.2f" % gap)
	if str(snap.dungeon.get("dungeon", "")) != "sandbag" or str(snap.dungeon.result) != "":
		_fail("판이 안 열렸다: %s" % str(snap.dungeon))
	if int(snap.dungeon.ends_at) - int(snap.dungeon.starts_at) != 15000:
		_fail("재는 시간이 15초가 아니다")
	if snap.gate.size() != 0:
		_fail("차원문이 있다")


## 카운트 동안은 못 친다
func _case_countdown() -> void:
	var w := _enter()
	w.attack("me")
	if not _all(w.drain_events(), "hit").is_empty():
		_fail("카운트 중에 맞았다")
	if int(w.snapshot().dungeon.damage) != 0:
		_fail("카운트 중 피해가 셌다")


## 카운트 동안은 가만히 · 끝나면 누르지 않아도 저절로 친다 · 결과가 나면 멈춘다 · 마을에선 꺼져 있다
func _case_auto() -> void:
	var w := _enter()
	var me: Dictionary = w.snapshot().players.me
	w.step(0.016)
	if bool(me.auto):
		_fail("카운트 중에 저절로 치기가 켜졌다")
	var run: Dictionary = w.snapshot().dungeon
	run.starts_at = Time.get_ticks_msec() - 1
	run.ends_at = Time.get_ticks_msec() + 60000
	for i in 30:
		me.next_attack_at = 0
		me.rooted_until = 0
		me.cast_until = 0
		w.step(0.016)
	if not bool(me.auto) or int(run.damage) <= 0:
		_fail("카운트가 끝났는데 저절로 안 친다: 켜짐 %s · 피해 %d" % [me.auto, int(run.damage)])
	run.ends_at = Time.get_ticks_msec() - 1
	w.step(0.016)
	if bool(me.auto):
		_fail("결과가 났는데 계속 친다")
	w.travel("me", "village")
	w.step(0.016)
	if bool(w.snapshot().players.me.auto):
		_fail("마을에서 자동사냥이 켜져 있다")


## 카운트가 끝나면 친 만큼 센다 · 샌드백은 안 죽고 안 움직인다 · 15초가 지나면 기록과 결과창
func _case_count_and_finish() -> void:
	var w := _enter()
	var run: Dictionary = w.snapshot().dungeon
	var now := Time.get_ticks_msec()
	run.starts_at = now - 1
	run.ends_at = now + 60000
	var bag: Dictionary = w.snapshot().monsters[0]
	var at := Vector2(float(bag.x), float(bag.z))
	var total := 0
	for i in 5:
		w.snapshot().players.me.next_attack_at = 0
		w.attack("me")
		w.step(0.016)
		for hit in _all(w.drain_events(), "hit"):
			if str(hit.get("target_kind", "")) != "monster":
				continue  # 물약이 저절로 들어가며 내는 회복(`heal`)이 섞인다
			total += int(hit.amount)
			if bool(hit.killed):
				_fail("샌드백이 죽었다")
	if total <= 0:
		_fail("한 대도 안 맞았다")
	if int(run.damage) != total:
		_fail("센 피해가 다르다: %d != %d" % [int(run.damage), total])
	if int(bag.hp) != int(bag.max_hp):
		_fail("샌드백 체력이 줄었다")
	if Vector2(float(bag.x), float(bag.z)) != at:
		_fail("샌드백이 움직였다")

	run.ends_at = Time.get_ticks_msec() - 1
	w.step(0.016)
	var events := w.drain_events()
	var results := _all(events, "dungeonResult")
	if results.size() != 1 or int(results[0].get("damage", -1)) != total or str(results[0].dungeon) != "sandbag":
		_fail("결과가 한 번, 넣은 피해로 나와야 한다: %s" % str(results))
	var records := _all(events, "sandbagRecord")
	if records.size() != 1 or int(records[0].best) != total or not bool(records[0].new_best):
		_fail("기록이 남지 않았다: %s" % str(records))
	if int(w.snapshot().players.me.sandbag.get("best", 0)) != total:
		_fail("장부의 최고 기록이 다르다")
	# 끝난 뒤의 피해는 세지 않는다 · 결과는 한 번뿐
	w.step(0.016)
	if not _all(w.drain_events(), "dungeonResult").is_empty():
		_fail("결과가 두 번 나왔다")

	# 다음 판이 낮으면 최고는 그대로
	w.travel("me", "village")
	w.travel("me", Sandbag.zone())
	w.drain_events()
	var again: Dictionary = w.snapshot().dungeon
	again.ends_at = Time.get_ticks_msec() - 1
	w.step(0.016)
	var second := _all(w.drain_events(), "sandbagRecord")
	if second.size() != 1 or bool(second[0].new_best) or int(second[0].best) != total:
		_fail("낮은 기록이 최고를 덮었다: %s" % str(second))


## 주가 바뀌면 혼자 노는 판은 1위 보상 — 옐로우 크리스탈 30개, 기록은 새 주로
func _case_local_week() -> void:
	var clock := [1_790_000_000.0]
	var w := _enter(clock)
	var me := _bag_of(w)
	me.sandbag = {"week": w.sandbag_week(), "best": 12345}
	clock[0] += 7 * 86400.0
	w._check_sandbag_week(0, true)  # 실제로는 1초마다 `step` 이 본다
	var events := w.drain_events()
	var paid := _all(events, "sandbagReward")
	if paid.size() != 1 or int(paid[0].rank) != 1 or int(paid[0].crystals) != Sandbag.reward(1):
		_fail("지난주 정산이 안 됐다: %s" % str(paid))
	if _count(me, Items.yellow_crystal_id()) != Sandbag.reward(1):
		_fail("옐로우 크리스탈이 안 들어왔다")
	if int(me.sandbag.week) != w.sandbag_week() or int(me.sandbag.best) != 0 or me.sandbag.has("unpaid"):
		_fail("새 주로 안 넘어갔다: %s" % str(me.sandbag))
	# 한 번만 준다
	w._check_sandbag_week(0, true)
	if not _all(w.drain_events(), "sandbagReward").is_empty():
		_fail("두 번 줬다")
	# 기록이 없던 주는 아무것도 안 준다
	clock[0] += 7 * 86400.0
	w._check_sandbag_week(0, true)
	if not _all(w.drain_events(), "sandbagReward").is_empty():
		_fail("기록이 없는데 줬다")

	# 가방이 꽉 차 있으면 못 받은 채로 남았다가 자리가 나면 들어온다
	var full := _enter(clock)
	var p := _bag_of(full)
	p.sandbag = {"week": full.sandbag_week(), "best": 99}
	p.bag.clear()
	for i in Items.bag_size():
		p.bag.append({"id": Items.all().keys()[0], "grade": 1})
	clock[0] += 7 * 86400.0
	full._check_sandbag_week(0, true)
	full.drain_events()
	if not p.sandbag.has("unpaid"):
		_fail("못 받은 보상이 남지 않았다")
	p.bag.pop_back()
	full._check_sandbag_week(0, true)
	if p.sandbag.has("unpaid") or _count(p, Items.yellow_crystal_id()) != Sandbag.reward(1):
		_fail("자리가 났는데 안 들어왔다")


## 저장했다 불러와도 그 주 기록이 남는다
func _case_save() -> void:
	var w := _enter()
	_bag_of(w).sandbag = {"week": w.sandbag_week(), "best": 777}
	w.save("me")
	var back := World.new()
	back.open("village")
	if not back.restore("me"):
		_fail("불러오기 실패")
		return
	if int(back.snapshot().players.me.sandbag.get("best", 0)) != 777:
		_fail("기록이 저장되지 않았다: %s" % str(back.snapshot().players.me.get("sandbag")))
	Save.clear()


## 옐로우 크리스탈은 3차를 굴린다 — 2차는 그대로
func _case_yellow_crystal() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me := _bag_of(w)
	me.bag.clear()
	me.bag.append({"id": Items.all().keys()[0], "grade": 3, "options": [], "options2": [{"kind": "crit", "value": 1.0}]})
	w.debug_crystals("me", 2, Items.yellow_crystal_id())
	w.use_crystal("me", "bag", 0, 3)
	var item: Dictionary = me.bag[0]
	if item.get("options3", []).size() != 1:
		_fail("3차가 안 붙었다: %s" % str(item))
	if item.options2 != [{"kind": "crit", "value": 1.0}]:
		_fail("2차가 바뀌었다")
	if _count(me, Items.yellow_crystal_id()) != 1:
		_fail("옐로우 크리스탈이 하나 줄어야 한다")
	# 크리스탈(2차)이 없으면 2차는 못 굴린다 — 재료가 섞이지 않는다
	w.use_crystal("me", "bag", 0, 2)
	if item.options2 != [{"kind": "crit", "value": 1.0}]:
		_fail("크리스탈 없이 2차가 굴렀다")
	if Items.material_tier(Items.yellow_crystal_id()) != 3 or Items.material_tier(Items.crystal_id()) != 2:
		_fail("재료 → 차수")


## 서버 — 들어온 지 18초가 지나야 · 한 판 한 번 · 상한 · 순위 · 주가 바뀌면 굳힌 순위로 정산
func _case_server() -> void:
	var store := AccountStore.new(DIR)
	var server := LedgerServer.new(store)
	var now := [500000]
	var unix := [1_790_000_000.0]
	server.clock = func() -> int: return now[0]
	server.ledger.unix_now = func() -> float: return float(unix[0])
	server._roll_sandbag_week()

	var sessions: Array = []
	for i in 3:
		var s := {}
		server.handle(s, {"t": "hello"})
		s.account.ledger.level = 40
		sessions.append(s)
	var ids := [1000, 2000, 3000]
	var send := func(who: int, op: String, args: Array) -> Dictionary:
		ids[who] += 1
		return server.handle(sessions[who], {"t": "op", "id": ids[who], "op": op, "args": args})

	if str(send.call(0, "sandbag_record", [10]).get("reason", "")) != "wrong_zone":
		_fail("샌드백 존이 아닌데 받았다")
	send.call(0, "enter", [Sandbag.zone()])
	if str(send.call(0, "sandbag_record", [10]).get("reason", "")) != "too_early":
		_fail("카운트 + 15초 전에 받았다")
	now[0] += 18000
	if str(send.call(0, "sandbag_record", [999_999_999]).get("reason", "")) != "too_much":
		_fail("말이 안 되는 피해를 받았다")
	var ok: Dictionary = send.call(0, "sandbag_record", [300])
	if _all(ok.get("events", []), "sandbagRecord").is_empty():
		_fail("기록을 안 받았다: %s" % str(ok))
	if str(send.call(0, "sandbag_record", [301]).get("reason", "")) != "claimed":
		_fail("한 판에 두 번 받았다")
	# 둘째 · 셋째 계정
	for who in [1, 2]:
		send.call(who, "enter", [Sandbag.zone()])
	now[0] += 18000
	send.call(1, "sandbag_record", [500])
	send.call(2, "sandbag_record", [100])

	var board: Dictionary = server.handle(sessions[0], {"t": "sandbagRank"})
	var bests: Array = board.top.map(func(r): return int(r.best))
	if bests != [500, 300, 100] or int(board.me.rank) != 2 or int(board.total) != 3:
		_fail("이번 주 순위가 다르다: %s" % str(board))
	# 100위까지 싣는다 (2026-10-02 요청 "순위는 100위까지 스크롤 가능하게") — 레벨 랭킹(50)과 따로
	if LedgerServer.SANDBAG_RANK_TOP != 100:
		_fail("샌드백 순위는 100위까지")

	# 주가 바뀐다 → 들어오는 계정마다 굳힌 순위로 받는다
	unix[0] += 7 * 86400.0
	var paid: Dictionary = send.call(1, "sort_bag", [])
	var reward := _all(paid.get("events", []), "sandbagReward")
	if reward.size() != 1 or int(reward[0].rank) != 1 or int(reward[0].crystals) != Sandbag.reward(1):
		_fail("1위 정산이 다르다: %s" % str(reward))
	var third: Dictionary = send.call(2, "sort_bag", [])
	var reward3 := _all(third.get("events", []), "sandbagReward")
	if reward3.size() != 1 or int(reward3[0].rank) != 3:
		_fail("3위 정산이 다르다: %s" % str(reward3))
	if store.find_sandbag_ranks(Sandbag.week(unix[0]) - 1).size() != 3:
		_fail("지난주 순위를 굳히지 않았다")
	# 새 주 순위표는 비었다
	var fresh: Dictionary = server.handle(sessions[0], {"t": "sandbagRank"})
	if int(fresh.total) != 0:
		_fail("새 주인데 지난 기록이 남았다: %s" % str(fresh))
	# 다시 와도 또 안 준다
	if not _all(send.call(1, "sort_bag", []).get("events", []), "sandbagReward").is_empty():
		_fail("두 번 정산했다")
