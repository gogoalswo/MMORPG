extends SceneTree

## PT 트레이너 (docs/features/trainers.md) — 상점에서 다이아로 뽑고, 갖고만 있어도 보유 효과가 붙고,
## 한 명을 데리고 다니면 **내가 친 몬스터를 같이 친다.** 트레이너는 맞지도 겨눠지지도 않는다.
##
##   godot --headless --path godot --script tests/trainer_test.gd

var _failed := 0


func _init() -> void:
	_case_table()
	_case_draw()
	_case_pick()
	_case_stats()
	_case_buddy()
	_case_save()
	_case_server()
	_finish.call_deferred()


func _finish() -> void:
	await _case_panel()
	Save.clear()
	if _failed == 0:
		print("트레이너: 전부 통과")
		quit(0)
	else:
		print("트레이너: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 표 — 등급별 20 · 15 · 10 · 5 · 3명, 계승 20 · 30 · 40 · 60 · 80 %
func _case_table() -> void:
	var counts: Array = []
	var inherit: Array = []
	for g in Trainers.grades():
		counts.append(Trainers.of_grade(int(g.grade)).size())
		inherit.append(int(g.inherit))
	if counts != [20, 15, 10, 5, 3]:
		_fail("등급별 인원이 %s" % [counts])
	if inherit != [20, 30, 40, 60, 80]:
		_fail("계승 %% 가 %s" % [inherit])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 2000:
		var id := Trainers.roll(rng)
		if Trainers.trainer(id).is_empty():
			_fail("굴린 것이 명단에 없다: %s" % id)
			return
		seen[int(Trainers.trainer(id).grade)] = int(seen.get(int(Trainers.trainer(id).grade), 0)) + 1
	# 일반 58% — 2000번이면 1000 ~ 1320 안
	if int(seen.get(1, 0)) < 1000 or int(seen.get(1, 0)) > 1320:
		_fail("일반이 2000번 중 %d번" % int(seen.get(1, 0)))


## 뽑기 — 모자라면 그대로, 10회는 1000 다이아에 열 명, 동행이 없으면 가장 높은 등급이 따라온다
func _case_draw() -> void:
	var ledger := Ledger.new()
	var me := Ledger.fresh("fighter")
	me.diamonds = 50
	ledger.trainer_draw(me, 1)
	if int(me.diamonds) != 50 or not me.trainers.is_empty():
		_fail("다이아가 모자란데 뽑혔다")
	me.diamonds = 1000
	ledger.trainer_draw(me, 3)
	if int(me.diamonds) != 1000:
		_fail("1회 · 10회 말고 3회가 뽑혔다")
	ledger.take_events()
	ledger.trainer_draw(me, 10)
	var events := ledger.take_events()
	var total := 0
	for id in me.trainers:
		total += int(me.trainers[id])
	if int(me.diamonds) != 0 or total != 10:
		_fail("10회 뒤 다이아 %d · 인원 %d" % [int(me.diamonds), total])
	var best := 0
	for id in me.trainers:
		best = maxi(best, int(Trainers.trainer(str(id)).grade))
	if int(Trainers.trainer(str(me.trainer_active)).grade) != best:
		_fail("동행이 가장 높은 등급(%d)이 아니다: %s" % [best, me.trainer_active])
	if events.is_empty() or str(events[-1].type) != "trainerDraw" or (events[-1].got as Array).size() != 10:
		_fail("뽑기 알림이 없다: %s" % [events])


## 동행 — 갖고 있는 것만, ""는 돌려보내기
func _case_pick() -> void:
	var ledger := Ledger.new()
	var me := Ledger.fresh("fighter")
	ledger.trainer_pick(me, "l01")
	if str(me.trainer_active) != "":
		_fail("안 가진 트레이너를 데리고 다닌다")
	me.trainers = {"l01": 1}
	ledger.trainer_pick(me, "l01")
	if str(me.trainer_active) != "l01":
		_fail("가진 트레이너를 못 데리고 다닌다")
	ledger.trainer_pick(me, "")
	if str(me.trainer_active) != "":
		_fail("돌려보내지 못한다")


## 보유 효과 — 공격력은 따로 곱하고(전설 권신 +8%), 치명타는 비율에 더한다(+8%p)
func _case_stats() -> void:
	var bare := World.stats_of("fighter", 100, {})
	var with := World.stats_of("fighter", 100, {}, {}, {}, {}, {"l01": 1, "l03": 1})
	if with.attack != roundi(bare.attack * 1.08):
		_fail("권신 보유 공격력 %d (맨몸 %d × 1.08 = %d)" % [with.attack, bare.attack, roundi(bare.attack * 1.08)])
	if absf(float(with.crit) - float(bare.crit) - 0.08) > 0.0001:
		_fail("선녀 보유 치명타 %.3f → %.3f" % [bare.crit, with.crit])
	if float(with.trainer_attack) != 8.0:
		_fail("캐릭터 정보 창용 trainer_attack 이 %s" % with.trainer_attack)


## 동행 전투 — 내가 친 놈에게 달려가 같이 친다 · 몬스터는 나를 쫓는다 · 트레이너는 목록에 없다
func _case_buddy() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	w.set_invincible("me", true)
	me.trainers = {"h01": 1}
	me.trainer_active = "h01"
	var mob: Dictionary = w.snapshot().monsters[0]
	me.x = float(mob.x) + 6.0
	me.z = float(mob.z)
	w.step(1.0 / 60.0)
	if (me.buddy as Dictionary).is_empty():
		_fail("동행 트레이너가 안 나왔다")
		return
	w.drain_events()
	w._hit_monster(me, mob, 1.0, "")
	var buddy_hits := 0
	var amount := 0
	for i in 240:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if str(e.type) == "hit" and bool(e.get("buddy", false)):
				buddy_hits += 1
				amount = int(e.amount)
		if buddy_hits > 0:
			break
	if buddy_hits == 0:
		_fail("트레이너가 내가 친 몬스터를 안 쳤다 (트레이너 %s, 몬스터 %.1f, %.1f)" % [me.buddy, mob.x, mob.z])
	elif amount <= 0:
		_fail("트레이너 피해가 0")
	if str(mob.target) != "me":
		_fail("트레이너에게 맞은 몬스터가 나를 안 쫓는다: %s" % mob.target)
	for each in w.snapshot().monsters:
		if str(each.get("target", "")) not in ["", "me"]:
			_fail("몬스터가 다른 것을 노린다: %s" % each.target)
	if w.snapshot().players.size() != 1:
		_fail("트레이너가 플레이어 목록에 들어갔다")
	# 돌려보내면 사라진다
	w.trainer_pick("me", "")
	w.step(1.0 / 60.0)
	if not (me.buddy as Dictionary).is_empty():
		_fail("돌려보냈는데 트레이너가 남았다")


## 저장 — 표에 없는 id 는 버리고, 안 가진 동행은 비운다
func _case_save() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.trainers = {"n01": 2, "없는것": 1}
	me.trainer_active = "a01"
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if back.trainers != {"n01": 2}:
		_fail("불러온 트레이너 %s" % [back.trainers])
	if str(back.trainer_active) != "":
		_fail("안 가진 동행이 남았다: %s" % back.trainer_active)
	if float(back.stats.get("trainer_attack", 0)) != 1.0:
		_fail("불러온 뒤 보유 효과가 안 들어갔다")


## 서버 — 요청 표 · 장부 칸 · 처치 검증이 동행 몫을 본다
func _case_server() -> void:
	if str(LedgerServer.OPS.get("trainer_draw", "")) != "i" or str(LedgerServer.OPS.get("trainer_pick", "")) != "s":
		_fail("서버가 trainer_draw · trainer_pick 요청을 모른다")
	if not ("trainers" in Ledger.KEYS and "trainer_active" in Ledger.KEYS):
		_fail("장부 칸에 trainers · trainer_active 가 없다")
	var ledger := Ledger.fresh("fighter")
	ledger.level = 200
	var kind := {}
	for id in GameData.load_table("monsters").kinds:
		var each: Dictionary = GameData.load_table("monsters").kinds[id]
		if kind.is_empty() or int(each.get("level", 0)) > int(kind.get("level", 0)):
			kind = each
	ledger.trainers = {"n01": 1}
	var alone := KillCheck.min_ms(ledger, kind)
	ledger.trainers = {"l01": 1}
	ledger.trainer_active = "l01"
	var together := KillCheck.min_ms(ledger, kind)
	if together >= alone * 0.7:
		_fail("전설 동행인데 최소 처치 시간이 충분히 안 줄었다: %.0f → %.0fms" % [alone, together])


## 창 — 카드 53장 · 등급 탭 · 미보유는 단추 꺼짐 · 동행 단추가 요청을 낸다 · 상점 뽑기 결과 판
func _case_panel() -> void:
	var boxes := func(_name: String, _margin: int, _content: int) -> StyleBox: return StyleBoxFlat.new()
	var arts := func(_id: String) -> Texture2D: return null
	var panel := TrainerPanel.make(boxes, arts)
	root.add_child(panel)
	panel.open()
	panel.refresh({"trainers": {"n01": 1, "l01": 2}, "trainer_active": "l01"})
	await process_frame
	if panel.cards().size() != 53:
		_fail("전체 탭 카드가 %d장" % panel.cards().size())
	panel.tab_buttons()[5].pressed.emit()
	if panel.cards().size() != 3:
		_fail("전설 탭 카드가 %d장" % panel.cards().size())
	if panel.detail_name() != "권신 아수라" or panel.pick_button().text != "돌려보내기":
		_fail("동행 중인 권신을 골랐는데 %s · %s" % [panel.detail_name(), panel.pick_button().text])
	var asked: Array = []
	panel.pick_requested.connect(func(id: String) -> void: asked.append(id))
	panel.select("l02")
	if not panel.pick_button().disabled:
		_fail("미보유 트레이너의 단추가 켜져 있다")
	panel.select("n01")
	panel.pick_button().pressed.emit()
	panel.select("l01")
	panel.pick_button().pressed.emit()
	if asked != ["n01", ""]:
		_fail("동행 · 돌려보내기 요청이 %s" % [asked])
	if not ("2 / 53" in panel.summary_text() and "공격력 +9%" in panel.summary_text()):
		_fail("아래 합계 줄이 %s" % panel.summary_text())
	panel.queue_free()

	var store := StorePanel.make(boxes, func(_n: String) -> Texture2D: return null)
	root.add_child(store)
	store.open()
	var bought: Array = []
	store.buy_requested.connect(func(id: String) -> void: bought.append(id))
	store.tab_buttons()[2].pressed.emit()
	store.set_products("draw/trainer", [{"id": "trainer_1", "name": "1회", "diamonds": 100}])
	await process_frame
	var buy: Button = store.cards()[0].find_child("buy", true, false) if not store.cards().is_empty() else null
	if buy == null or buy.text != "다이아 100":
		_fail("뽑기 카드에 다이아 단추가 없다")
	else:
		buy.pressed.emit()
	if bought != ["trainer_1"]:
		_fail("뽑기 단추가 요청을 안 냈다: %s" % [bought])
	store.show_draw(["n01", "l01"], [true, false], arts)
	var shown := store.draw_shown()
	if shown == null or (shown.find_child("cards", true, false) as GridContainer).get_child_count() != 2:
		_fail("뽑기 결과 판에 카드 둘이 없다")
	store.queue_free()
