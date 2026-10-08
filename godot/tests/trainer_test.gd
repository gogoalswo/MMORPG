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
	_case_fuse()
	_case_stats()
	_case_buddy()
	_case_buddy_lunge()
	_case_buddy_follow()
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


## 합성 — 칸에 등록한 카드(같은 등급 여분, 트레이너마다 1장은 남긴다)를 3장씩 끊어 한 번씩 도전 · 9장까지
func _case_fuse() -> void:
	var ledger := Ledger.new()
	ledger.rng.seed = 11
	var me := Ledger.fresh("fighter")
	me.trainers = {"n01": 3, "n02": 1}
	ledger.trainer_fuse(me, ["n01", "n01", "n02"])
	ledger.trainer_fuse(me, ["n01", "n01", "n01"])
	if int(me.trainers.n01) != 3 or int(me.trainers.n02) != 1:
		_fail("여분을 넘게 넣었는데 합성됐다: %s" % [me.trainers])
	me.trainers = {"n01": 4, "n02": 2, "a01": 1}
	if Trainers.spare(me.trainers, 1) != 4:
		_fail("여분이 %d (n01 3 + n02 1 = 4)" % Trainers.spare(me.trainers, 1))
	ledger.trainer_fuse(me, ["n01", "n01"])
	ledger.trainer_fuse(me, ["n01", "n02", "a01"])
	if int(me.trainers.n01) != 4 or int(me.trainers.a01) != 1:
		_fail("3장 줄이 아니거나 등급이 섞였는데 합성됐다: %s" % [me.trainers])
	# 자동 등록 — 남은 여분이 많은 트레이너부터 (같으면 명단 앞)
	var auto := Trainers.auto_pick(me.trainers, 1, [], 9)
	if auto != ["n01", "n01", "n01", "n02"]:
		_fail("자동 등록이 %s" % [auto])
	if Trainers.auto_pick(me.trainers, 1, ["n01", "n01"], 9) != ["n01", "n02"]:
		_fail("이미 칸에 넣은 것을 빼지 않았다")
	ledger.take_events()
	ledger.trainer_fuse(me, ["n01", "n01", "n02"])
	var events := ledger.take_events()
	var fuse: Dictionary = {}
	for e in events:
		if str(e.type) == "trainerFuse":
			fuse = e
	if fuse.is_empty() or (fuse.results as Array).size() != 1 or fuse.results[0].used != ["n01", "n01", "n02"]:
		_fail("합성 알림이 %s" % [fuse])
	else:
		# 성공은 고급 1명(`got`), 실패는 같은 등급(일반) 1명(`back`) — 둘 중 하나만
		var got := str(fuse.results[0].got)
		var back := str(fuse.results[0].back)
		var gain := got if got != "" else back
		var expect := {"n01": 2, "n02": 1}
		expect[gain] = int(expect.get(gain, 0)) + 1
		if (got == "") == (back == "") or int(Trainers.trainer(gain).grade) != (2 if got != "" else 1):
			_fail("합성 결과가 got %s · back %s (성공은 고급, 실패는 일반 1장)" % [got, back])
		for id in expect:
			if int(me.trainers.get(id, 0)) != int(expect[id]):
				_fail("합성 한 번 뒤 %s — 넣은 3장이 빠지고 %s 1장만 늘어야 한다" % [me.trainers, gain])
	# 칸 30장 = 10번 도전, 그보다 많으면 거절. 일반 여분 300장을 자동 등록해 다 쓸 때까지 합성 — 실패는 일반 1장을 돌려주니
	# (한 번에 3장 빠지고 실패면 1장 돌아옴) 대략 130 ~ 140번, 20% 라 성공은 대략 15 ~ 45번
	var many := {}
	for info in Trainers.of_grade(1):
		many[str(info.id)] = 16
	me.trainers = many
	var over := Trainers.fuse_slots() + Trainers.fuse_cost()
	ledger.trainer_fuse(me, Trainers.auto_pick(me.trainers, 1, [], over))
	if Trainers.spare(me.trainers, 1) != 300:
		_fail("%d장(칸보다 많이)을 넣었는데 합성됐다" % over)
	ledger.take_events()
	var tries := 0
	var wins := 0
	var backs := 0
	for round in 50:
		var ids := Trainers.auto_pick(me.trainers, 1, [], Trainers.fuse_slots())
		ids = ids.slice(0, ids.size() / Trainers.fuse_cost() * Trainers.fuse_cost())
		if ids.is_empty():
			break
		ledger.trainer_fuse(me, ids)
		for e in ledger.take_events():
			if str(e.type) == "trainerFuse":
				tries += (e.results as Array).size()
				wins += (e.results as Array).filter(func(r: Dictionary) -> bool: return str(r.got) != "").size()
				backs += (e.results as Array).filter(func(r: Dictionary) -> bool:
					return str(r.back) != "" and int(Trainers.trainer(str(r.back)).grade) == 1).size()
	if tries < 110 or tries > 150 or wins < 15 or wins > 45 or wins + backs != tries:
		_fail("일반 여분 300장 합성 — %d번 · 성공 %d · 돌려받음 %d (실패마다 일반 1장)" % [tries, wins, backs])
	if Trainers.spare(me.trainers, 1) >= Trainers.fuse_cost():
		_fail("다 합성한 뒤 일반 여분이 %d" % Trainers.spare(me.trainers, 1))
	# 전설은 더 위가 없다
	me.trainers = {"l01": 9}
	ledger.trainer_fuse(me, ["l01", "l01", "l01"])
	if int(me.trainers.l01) != 9:
		_fail("전설을 합성했다")
	if str(LedgerServer.OPS.get("trainer_fuse", "")) != "w":
		_fail("서버가 trainer_fuse 요청을 모른다")


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


## 따라오기 — 내가 계속 걸으면 트레이너는 **계속 달린다.** 거리만 보던 때는 ×1.25 로 곧장 붙어 서고
## 한 걸음 뒤 다시 달려 Idle ↔ Run 이 몇 프레임마다 뒤집혔다 (2026-10-07 "버벅거린다"). 서면 같이 선다
func _case_buddy_follow() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	w.set_invincible("me", true)
	me.trainers = {"h01": 1}
	me.trainer_active = "h01"
	me.x = 0.0
	me.z = 0.0
	w.step(1.0 / 60.0)
	var flips := 0
	var last := ""
	for i in 120:
		w.input_move("me", i + 1, 0.0, 1.0, 1.0 / 60.0)
		w.step(1.0 / 60.0)
		var state := str(me.buddy.get("state", ""))
		if i >= 10 and state != last:
			flips += 1
		last = state
	if flips > 0 or last != "run":
		_fail("걷는 동안 트레이너가 섰다 달렸다 한다 (%d번 바뀜, 마지막 %s)" % [flips, last])
	# 돌아서도 튀지 않는다 — 몸은 `BUDDY_TURN` 씩만 돌고, 곁 자리는 건너뛰지 않고 내 둘레를 돈다
	# (2026-10-07 "방향 전환할 때도 살짝 튄다"). 옆으로 꺾기 · 뒤로 돌기 둘 다 본다
	var turn_max := World.BUDDY_TURN / 60.0 + 0.001
	var worst := 0.0
	var seq := 200
	for way in [Vector2(-1.0, 0.0), Vector2(0.0, -1.0)]:
		for i in 60:
			var before := float(me.buddy.rot)
			seq += 1
			w.input_move("me", seq, way.x, way.y, 1.0 / 60.0)
			w.step(1.0 / 60.0)
			worst = maxf(worst, absf(angle_difference(before, float(me.buddy.rot))))
			if str(me.buddy.state) != "run":
				_fail("돌아서는 동안 트레이너가 섰다: %s" % me.buddy)
				break
	if worst > turn_max:
		_fail("돌아설 때 트레이너가 한 틱에 %.0f° 돌았다 (한도 %.0f°)" % [rad_to_deg(worst), rad_to_deg(turn_max)])
	OS.delay_msec(World.BUDDY_MOVE_GRACE_MS + 50)
	for i in 30:
		w.step(1.0 / 60.0)
	if str(me.buddy.get("state", "")) != "idle":
		_fail("내가 섰는데 트레이너가 안 선다: %s" % me.buddy)


## 동행 날라차기 — 같이 칠 놈이 `LUNGE_MIN` 보다 멀면 달려가지 않고 날아 붙어서, 닿는 순간 한 대 (`_buddy_lunge`)
func _case_buddy_lunge() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	w.set_invincible("me", true)
	me.trainers = {"h01": 1}
	me.trainer_active = "h01"
	var mob: Dictionary = w.snapshot().monsters[0]
	mob.speed = 0.0
	me.x = float(mob.x)
	me.z = float(mob.z) + 7.0
	me.rot = PI
	w.step(1.0 / 60.0)
	var buddy: Dictionary = me.buddy
	var start := Vector2(float(buddy.x), float(buddy.z)).distance_to(Vector2(float(mob.x), float(mob.z)))
	if start <= World.LUNGE_MIN or start > World.LUNGE_MAX:
		_fail("시험 자리가 날라차기 거리가 아니다: %.1fm" % start)
		return
	w.drain_events()
	w._hit_monster(me, mob, 1.0, "")
	var lunged := {}
	var hit_frame := -1
	for i in 60:
		w.step(1.0 / 60.0)
		for e in w.drain_events():
			if str(e.type) == "buddyLunge":
				lunged = e
			elif str(e.type) == "hit" and bool(e.get("buddy", false)) and hit_frame < 0:
				hit_frame = i
		if hit_frame >= 0:
			break
	if lunged.is_empty():
		_fail("트레이너가 %.1fm 떨어진 몬스터에게 날라차기를 안 했다" % start)
		return
	if hit_frame < 0 or hit_frame > ceili(World.LUNGE_MAX_S * 60.0) + 2:
		_fail("날라차기가 %.2f초 안에 안 닿았다 (프레임 %d)" % [World.LUNGE_MAX_S, hit_frame])
	var near := Vector2(float(me.buddy.x), float(me.buddy.z)).distance_to(Vector2(float(mob.x), float(mob.z)))
	if near > World.BUDDY_REACH + float(mob.get("r", 0.5)):
		_fail("날라차기 뒤 트레이너가 주먹 거리 밖이다: %.2fm" % near)
	if float(lunged.speed) <= 0.0 or int(lunged.ms) <= World.LUNGE_LAND_MS:
		_fail("buddyLunge 배속·시간이 이상하다: %s" % lunged)
	# 가까우면 날지 않고 걸어서 붙는다
	var w2 := World.new()
	w2.open("meadow")
	w2.join("me")
	var me2: Dictionary = w2.snapshot().players["me"]
	w2.set_invincible("me", true)
	me2.trainers = {"h01": 1}
	me2.trainer_active = "h01"
	var mob2: Dictionary = w2.snapshot().monsters[0]
	mob2.speed = 0.0
	me2.x = float(mob2.x) + 3.0
	me2.z = float(mob2.z)
	w2.step(1.0 / 60.0)
	w2.drain_events()
	w2._hit_monster(me2, mob2, 1.0, "")
	for i in 120:
		w2.step(1.0 / 60.0)
		for e in w2.drain_events():
			if str(e.type) == "buddyLunge":
				_fail("가까운(%.1fm) 몬스터에게 날라차기를 했다" % Vector2(float(me2.buddy.x), float(me2.buddy.z)).distance_to(Vector2(float(mob2.x), float(mob2.z))))
				return


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
	# 원화를 주더라도 카드는 쓰지 않는다 — 3D 를 찍기 전에는 빈 칸 (2026-10-07 "3D 로딩이 안 됐으면 비어 있게")
	var concept := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var arts := func(_id: String) -> Texture2D: return concept
	var panel := TrainerPanel.make(boxes, arts)
	root.add_child(panel)
	panel.open()
	panel.refresh({"trainers": {"n01": 1, "l01": 2}, "trainer_active": "l01"})
	await process_frame
	if panel.cards().size() != 53:
		_fail("전체 탭 카드가 %d장" % panel.cards().size())
	# 목록은 **끌어서도** 내려가고, 그 자리에서 떼면 그 카드를 고른다 (2026-10-08 — 휠로만 내려갔다)
	await process_frame
	var list_scroll := panel.find_child("scroll", true, false) as ScrollContainer
	var list_drag: DragScroll = list_scroll.get_meta("drag_scroll")
	var hold := list_scroll.size * 0.5
	list_drag.on_input(_trainer_mouse(hold, true))
	for i in 6:
		hold.y -= 40
		var pull := InputEventMouseMotion.new()
		pull.position = hold
		list_drag.on_input(pull)
	list_drag.on_input(_trainer_mouse(hold, false))
	if list_scroll.scroll_vertical <= 0:
		_fail("트레이너 목록을 끌었는데 안 내려갔다")
	list_scroll.scroll_vertical = 0
	await process_frame
	var was := str(panel._selected)
	var second := panel.cards()[1] as Control
	var spot := second.global_position - list_scroll.global_position + second.size * 0.5
	list_drag.on_input(_trainer_mouse(spot, true))
	list_drag.on_input(_trainer_mouse(spot, false))
	if str(panel._selected) != str(Trainers.all()[1].id):
		_fail("목록에서 카드를 눌렀다 뗐는데 %s 가 골라졌다" % panel._selected)
	panel.select(was)
	for card in panel.cards():
		if (card.find_child("art", true, false) as TextureRect).texture == concept:
			_fail("3D 를 찍기 전인데 카드에 원화가 섰다 (%s)" % card.name)
			break
	panel.tab_buttons()[5].pressed.emit()
	if panel.cards().size() != 3:
		_fail("전설 탭 카드가 %d장" % panel.cards().size())
	if panel.detail_name() != "권신 아수라" or panel.pick_button().text != "돌려보내기":
		_fail("동행 중인 권신을 골랐는데 %s · %s" % [panel.detail_name(), panel.pick_button().text])
	# 오른쪽은 그림이 아니라 **3D 모델**이 대기 동작으로 선다 (2026-10-06) — 고르면 그 트레이너로 바뀐다
	var first := panel.stage().rig()
	if first == null:
		_fail("오른쪽 무대에 모델이 없다 (에셋을 동기화했나)")
	elif not first.is_inside_tree() or first.get_viewport() == panel.get_viewport():
		_fail("무대 모델이 창의 SubViewport 안에 있지 않다")
	panel.select("n02")
	await process_frame
	if panel.stage().rig() == null or panel.stage().rig() == first:
		_fail("다른 트레이너를 골랐는데 무대 모델이 안 바뀌었다")
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
	# 합성 보기 — 왼쪽 등급 탭 → 카드를 눌러 칸에 등록 → 3장마다 한 번 도전 (2026-10-08)
	# 머리의 합성은 등급 탭과 같은 탭이다 (2026-10-08) — 누르면 합성 보기, 등급 탭을 누르면 목록으로
	(panel.find_child("fuse_toggle", true, false) as Button).pressed.emit()
	if not panel.fuse_shown() or not (panel.fuse_buttons()[1] as Button).disabled:
		_fail("합성 탭을 눌러도 합성 보기가 안 섰거나, 칸이 비었는데 합성 단추가 켜져 있다")
	if panel.fuse_tab(5) != null or panel.fuse_tab(1) == null or not (panel.tab_buttons()[0] as Button).visible:
		_fail("합성 탭이 전설에 있거나 일반에 없다 · 머리의 등급 탭이 숨었다")
	panel.tab_buttons()[1].pressed.emit()
	if panel.fuse_shown():
		_fail("합성 보기에서 등급 탭을 눌러도 목록으로 안 돌아간다")
	panel.show_fuse(true)
	# 보유 효과는 등록 칸 오른쪽(도감 능력치)에 서고 아래 합계 줄은 숨는다 (2026-10-08)
	var codex_count := panel.find_child("codex_count", true, false) as Label
	var summary := panel.find_child("summary", true, false) as Label
	if codex_count == null or not ("2 / 53" in codex_count.text) or summary.visible:
		_fail("합성 보기에 도감 능력치가 없거나(%s) 아래 합계 줄이 그대로 보인다" % (codex_count.text if codex_count else "없음"))
	# 칸 30개(도전 10번)는 원래 크기 그대로 아래로 쭉 — 스크롤 안이라 단추 둘(맨 아래)까지 1280 × 720 한 화면에 든다 (2026-10-08)
	var need := panel.get_combined_minimum_size()
	var slot0 := panel.fuse_slots()[0] as Control
	if panel.fuse_slots().size() != 30 or need.x > 1280 or need.y > 720:
		_fail("합성 칸 %d개 · 창 최소 크기 %s (30칸이 1280 × 720 에 들어야)" % [panel.fuse_slots().size(), need])
	elif slot0.custom_minimum_size != Vector2(88, 117) or not (slot0.get_parent().get_parent() is ScrollContainer):
		_fail("합성 칸이 %s · 스크롤 안에 없다 (88 × 117 로 아래로 쭉)" % slot0.custom_minimum_size)
	# 칸은 **끌어서도** 내려간다 — 휠만 되고 끌기는 칸 단추가 먹었다 (2026-10-08 "클릭해서 내리는 건 안돼")
	await process_frame
	await process_frame
	var slot_scroll := panel.find_child("slot_scroll", true, false) as ScrollContainer
	var slot_drag: DragScroll = slot_scroll.get_meta("drag_scroll")
	var grab := slot_scroll.size * 0.5
	slot_drag.on_input(_trainer_mouse(grab, true))
	for i in 6:
		grab.y -= 40
		var move := InputEventMouseMotion.new()
		move.position = grab
		slot_drag.on_input(move)
	slot_drag.on_input(_trainer_mouse(grab, false))
	if slot_scroll.scroll_vertical <= 0 or slot0.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("합성 칸을 끌었는데 안 내려갔다 (스크롤 %d) · 칸 단추가 입력을 먹는다" % slot_scroll.scroll_vertical)
	slot_scroll.scroll_vertical = 0
	panel.refresh({"trainers": {"n01": 5, "n02": 2, "l01": 2}, "trainer_active": "l01"})
	if panel.fuse_cards().size() != 2 or not panel.fuse_tab(1).get_node("red_dot").visible:
		_fail("일반 합성 카드 %d장 (n01 · n02 둘이어야) · 빨간 점" % panel.fuse_cards().size())
	var fused: Array = []
	panel.fuse_requested.connect(func(ids: Array) -> void: fused.append(ids))
	# n01 카드를 다섯 번 — 여분 4장까지만 들어간다
	for i in 5:
		for card in panel.fuse_cards():
			if card.name == "card_n01":
				(card.get_node("hit") as Button).pressed.emit()
	if panel.slot_ids() != ["n01", "n01", "n01", "n01"]:
		_fail("카드를 눌러 등록한 칸이 %s" % [panel.slot_ids()])
	# 칸은 끌기 목록이 받는다 — 그 자리에서 눌렀다 떼면 그 칸이 빠진다
	await process_frame
	var at := slot0.global_position - slot_scroll.global_position + slot0.size * 0.5
	slot_drag.on_input(_trainer_mouse(at, true))
	slot_drag.on_input(_trainer_mouse(at, false))
	if panel.slot_ids().size() != 3:
		_fail("칸을 눌러도 빠지지 않았다: %s" % [panel.slot_ids()])
	(panel.fuse_buttons()[0] as Button).pressed.emit()
	if panel.slot_ids() != ["n01", "n01", "n01", "n01", "n02"] or not (panel.fuse_buttons()[0] as Button).disabled:
		_fail("자동 등록 뒤 칸이 %s (여분을 다 쓰면 자동 등록 단추가 꺼져야)" % [panel.slot_ids()])
	(panel.fuse_buttons()[1] as Button).pressed.emit()
	if fused != [["n01", "n01", "n01"]] or panel.slot_ids() != ["n01", "n02"]:
		_fail("합성 요청이 %s · 남은 칸 %s (3장 한 줄만 보내고 나머지는 남아야)" % [fused, panel.slot_ids()])
	panel.fuse_tab(4).pressed.emit()
	if not panel.slot_ids().is_empty() or not panel.fuse_cards().is_empty():
		_fail("등급 탭을 바꿨는데 칸 %s · 카드 %d장" % [panel.slot_ids(), panel.fuse_cards().size()])
	panel.show_fuse_result({"grade": 1, "results": [{"used": [], "got": "a01", "back": ""}, {"used": [], "got": "", "back": "n02"}]})
	if panel.fuse_note() != "합성 2번 — 성공 1 · 실패 1":
		_fail("합성 결과 줄이 %s" % panel.fuse_note())
	# 합성 결과 판 — 도전마다 카드 한 장(성공은 얻은 트레이너 · 실패는 돌려받은 같은 등급 1장), 테두리는 그 카드의 등급 색, X 로 걷는다
	var result := panel.fuse_result()
	if result == null:
		_fail("합성 결과 판이 안 떴다")
	else:
		result.finish()
		var names: Array = result.cards().map(func(c: Control) -> String: return str(c.name))
		var edge := func(i: int) -> Color:
			return ((result.cards()[i].get_node("frame") as Panel).get_theme_stylebox("panel") as StyleBoxFlat).border_color
		if names != ["card_a01", "card_fail_n02"] or not result.top_level:
			_fail("합성 결과 판 카드가 %s (화면 전체를 덮어야)" % [names])
		elif (result.cards()[0] as Control).modulate.a < 0.99 or result.cards()[0].get_node_or_null("flame") == null:
			_fail("성공 카드가 다 안 섰거나 테두리 불길이 없다")
		elif result.cards()[1].get_node_or_null("flame") != null:
			_fail("실패 카드에 불길이 있다")
		elif edge.call(0) != TrainerFuseResult.edge_color(2) or edge.call(1) != TrainerFuseResult.edge_color(1):
			_fail("결과 카드 테두리가 %s · %s (고급 · 일반 등급 색이어야)" % [edge.call(0), edge.call(1)])
		elif edge.call(0) == edge.call(1):
			_fail("등급이 다른데 테두리 색이 같다")
		result.close_button().pressed.emit()
		if panel.fuse_result() != null:
			_fail("X 를 눌러도 결과 판이 남았다")
	# 도전 10번 — 결과 카드 10장이 5장씩 두 줄로 선다
	var ten: Array = []
	for i in 10:
		ten.append({"used": [], "got": "a01" if i % 2 == 0 else ""})
	panel.show_fuse_result({"grade": 1, "results": ten})
	var big := panel.fuse_result()
	if big == null or big.cards().size() != 10 or big.get_node("cards").get_child_count() != 2:
		_fail("결과 10번이 카드 10장 · 두 줄로 안 섰다")
	panel.hide_fuse_result()
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
	# 뽑기 연출 — 뽑은 수만큼 밀랍 조각상(일반·고급 흰색 · 희귀 이상 금), 좋은 등급이 앞자리, [모두 보기] → 카드 (이름은 등급 색)
	if TrainerDraw.slots(10).size() != 10 or TrainerDraw.slots(1) != [Vector3.ZERO]:
		_fail("뽑기 자리 수가 틀리다: %d" % TrainerDraw.slots(10).size())
	store.show_draw(["n01", "a01", "r01", "l01"], [true, false, false, false])
	var shown := store.draw_shown() as TrainerDraw
	if shown == null or shown.pieces().size() != 4:
		_fail("뽑기 판에 조각상 넷이 없다")
	else:
		var golds: Array = shown.pieces().map(func(p): return "%s:%s" % [p.id, "금" if p.gold else "흰"])
		if golds != ["l01:금", "r01:금", "a01:흰", "n01:흰"]:
			_fail("조각상 색·자리가 %s" % [golds])
		if not shown.cards().is_empty():
			_fail("보기 전에 카드가 섰다")
		(shown.find_child("reveal", true, false) as Button).pressed.emit()
		shown.finish()
		if shown.cards().size() != 4:
			_fail("모두 보기 뒤 카드가 %d장" % shown.cards().size())
		else:
			var legend: Label = shown.cards()[0].find_child("name", true, false)
			if legend.text != str(Trainers.trainer("l01").name) \
					or legend.get_theme_color("font_color") != TrainerPanel.grade_color(5).lightened(0.2):
				_fail("전설 카드 이름이 등급 색이 아니다")
			if shown.cards()[3].find_child("tag", true, false) == null or shown.cards()[0].find_child("tag", true, false) != null:
				_fail("새로 얻은 것에만 NEW 가 붙어야 한다")
		var ok: Button = shown.find_child("ok", true, false)
		if not ok.visible:
			_fail("다 본 뒤 확인 단추가 없다")
		# [N회 뽑기] — 확인 옆에 서고, 누르면 상점 단추와 같은 구매 요청이 나간다 (4장 판은 여러 장이라 10회)
		var again: Button = shown.find_child("again", true, false)
		if again == null or not again.visible or again.text != "%d회 뽑기" % Trainers.draw_multi():
			_fail("다 본 뒤 [%d회 뽑기] 단추가 없다" % Trainers.draw_multi())
		elif absf(again.get_global_rect().position.y - ok.get_global_rect().position.y) > 0.5 \
				or again.get_global_rect().intersects(ok.get_global_rect()):
			_fail("다시 뽑기 단추가 확인 옆에 나란히 서지 않았다")
		else:
			var again_asked: Array = []
			store.buy_requested.connect(func(id: String) -> void: again_asked.append(id))
			again.pressed.emit()
			if again_asked != ["trainer_10"]:
				_fail("다시 뽑기가 보낸 요청이 %s" % [again_asked])
		ok.pressed.emit()
		await process_frame
		if store.draw_shown() != null:
			_fail("확인을 눌러도 뽑기 판이 남았다")
	# 10회 — 카드가 서로 겹치지 않고 [확인] 위 화면 안에 선다 (2026-10-08 "서로 겹치지 않게")
	store.show_draw(["n01", "n02", "n03", "a01", "a02", "r01", "r02", "h01", "l01", "l02"], [true, true, true, true, true, true, true, true, true, true])
	var big_draw := store.draw_shown() as TrainerDraw
	if big_draw != null:
		big_draw.finish()
		var rects: Array = big_draw.cards().map(func(c: Control) -> Rect2: return c.get_global_rect())
		if rects.size() != 10:
			_fail("10회 카드가 %d장" % rects.size())
		var view := big_draw.get_global_rect()
		var ok_top := (big_draw.find_child("ok", true, false) as Control).get_global_rect().position.y
		for i in rects.size():
			var r: Rect2 = rects[i]
			if not view.encloses(r) or r.end.y > ok_top:
				_fail("10회 카드 %d 가 화면 밖이거나 확인 단추를 덮는다: %s (화면 %s)" % [i, r, view])
			for j in range(i + 1, rects.size()):
				if r.grow(-1.0).intersects(rects[j]):
					_fail("10회 카드 %d · %d 가 겹친다: %s · %s" % [i, j, r, rects[j]])
		big_draw.closed.emit()
	# 1회 판은 [1회 뽑기] — 상점의 1회 단추와 같은 요청
	var one := TrainerDraw.make(["n01"], [true])
	var one_again: Button = one.find_child("again", true, false)
	if one_again == null or one_again.text != "1회 뽑기":
		_fail("1회 판의 다시 뽑기 단추가 [1회 뽑기] 가 아니다")
	else:
		var one_asked: Array = []
		one.again.connect(func(times: int) -> void: one_asked.append(times))
		one_again.pressed.emit()
		if one_asked != [1]:
			_fail("1회 판의 다시 뽑기가 %s 회를 청했다" % [one_asked])
	one.free()
	store.queue_free()


## 끌기 목록에 넣는 왼쪽 단추 누르기 · 떼기 (목록 기준 좌표)
func _trainer_mouse(at: Vector2, down: bool) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	return click
