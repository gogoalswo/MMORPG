extends SceneTree

## 결투장 (docs/features/arena.md) — 더미 50명 표(`Arena.board`) · 결투(상대 세우기 · 카운트 · 같은 피해 공식 ·
## 승리 · 패배 · 시간 끝 · 점수) · 서버(표 답 · 결과 검증) · 창(메뉴 → 전체 화면 · 랭킹 · 도전자 목록 굴림 · 글자 ·
## 도전 → 결투장 → 결과창). 스크린샷 없이 노드로 읽는다.
##
##   godot --headless --path godot --script tests/arena_test.gd

const DIR := "user://test_arena_accounts"
const FONT := "res://assets/fonts/NotoSansKR-subset.ttf"

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_board()
	_case_duel_start()
	_case_duel_countdown()
	_case_duel_hits()
	_case_duel_win()
	_case_duel_lose()
	_case_duel_time()
	_case_server()
	# 위 World 들이 저장을 남겼다 — 화면은 새로 시작한다
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


## 표 — 더미 50명 · 이름이 서로 다름 · 점수 순 · 나는 26위 / 51명 · 레벨은 내 레벨 ± 5 (1 ~ 만렙 안)
func _case_board() -> void:
	var board := Arena.board({"name": "나", "job": "fighter", "level": 30, "equipped": {}})
	var list: Array = board.get("challengers", [])
	var ranking: Array = board.get("ranking", [])
	if list.size() != 50 or ranking.size() != 51 or int(board.get("total", 0)) != 51:
		_fail("더미 50명 · 랭킹 51줄이어야 한다: %d · %d" % [list.size(), ranking.size()])
		return
	var names := {}
	for row in list:
		names[str(row.name)] = true
		if int(row.level) < 25 or int(row.level) > 35:
			_fail("더미 레벨이 내 레벨 ± 5 밖: %s Lv.%d" % [row.name, int(row.level)])
		if int(row.get("power", 0)) <= 0 or int(row.get("rank", 0)) <= 0 or str(row.get("job", "")) != "fighter":
			_fail("더미 줄에 전투력 · 순위 · 직업이 없다: %s" % row)
	if names.size() != 50:
		_fail("더미 이름이 겹친다: 서로 다른 이름 %d개" % names.size())
	for i in ranking.size() - 1:
		if int(ranking[i].score) < int(ranking[i + 1].score) or int(ranking[i].rank) != i + 1:
			_fail("랭킹이 점수 순이 아니다: %d번째" % i)
			break
	var me: Dictionary = board.get("me", {})
	if int(me.get("rank", 0)) != 26 or int(me.get("score", 0)) != Arena.start_score() or str(me.get("name", "")) != "나":
		_fail("처음 들어온 나는 26위 · 점수 %d: %s" % [Arena.start_score(), me])
	if not bool(ranking[25].get("me", false)):
		_fail("랭킹 26번째 줄이 내 줄이 아니다")
	if int(list[0].level) <= int(list[49].level):
		_fail("점수가 높은 더미가 레벨도 높아야 한다")
	# 전투력은 공속만큼 곱한다 — 같은 레벨 · 장비라도 질풍각을 배우면 그 배수만큼 오른다 (2026-10-12)
	var bare := {"job": "fighter", "level": 30, "equipped": {}}
	var fast := {"job": "fighter", "level": 30, "equipped": {}, "passives": {"gale_kicks": 5}}
	# 공격 × 체력의 곱이라 제곱근을 씌운다 (같은 날 "48억은 너무 높아")
	if Arena.power(bare) != roundi(sqrt(Ledger.gear_power(bare, {}))):
		_fail("공속 패시브가 없으면 전투력이 √(자동 장착 값)이어야 한다: %d / %d" % [Arena.power(bare), roundi(sqrt(Ledger.gear_power(bare, {})))])
	var s := World.stats_of("fighter", 30, {}, fast.passives)
	var mul := float(s.attackCooldown) / float(Combat.effective_cooldown(float(s.attackCooldown), float(s.attackSpeed)))
	if mul <= 1.0 or Arena.power(fast) != roundi(sqrt(Ledger.gear_power(fast, {}) * mul)):
		_fail("질풍각 5단 전투력이 공속 배수(%.2f)만큼 안 올랐다: %d / 맨몸 %d" % [mul, Arena.power(fast), Arena.power(bare)])
	# 장부에 점수가 있으면 그 점수로 선다
	var high := Arena.board({"name": "나", "job": "fighter", "level": 30, "equipped": {}, "arena": {"score": 2000}})
	if int(high.me.rank) != 1:
		_fail("점수 2000 이면 1위여야 한다: %d위" % int(high.me.rank))
	# 레벨 끝 — 1레벨은 1 아래로, 만렙은 만렙 위로 안 간다
	var max_level := int(GameData.combat().maxLevel)
	for level in [1, max_level]:
		for row in Arena.dummies(level):
			if int(row.level) < 1 or int(row.level) > max_level:
				_fail("더미 레벨이 1 ~ %d 밖: Lv.%d (내 레벨 %d)" % [max_level, int(row.level), level])
				break


## 마을에서 [도전] — 30레벨 나, 상대는 더미 첫째 복사본
func _duel(copy: Dictionary = {}) -> World:
	var w := World.new()
	w.open("village")
	w.join("me")
	w.debug_level("me", 30)
	if copy.is_empty():
		copy = Arena.dummies(30)[0]
	w.start_duel("me", copy)
	w.drain_events()
	return w


func _foe(w: World) -> Dictionary:
	for monster in w.snapshot().monsters:
		if bool(monster.get("duel", false)):
			return monster
	return {}


## 결투장 존 · 상대 하나(복사본 능력치 · 이름 · 내 모델) · 판이 열린다 · 나는 가득 찬 체력
func _case_duel_start() -> void:
	var copy: Dictionary = Arena.dummies(30)[0]
	var w := World.new()
	w.open("village")
	w.join("me")
	w.debug_level("me", 30)
	var me: Dictionary = w.snapshot().players.me
	me.hp = 1
	w.start_duel("me", copy)
	var snap := w.snapshot()
	if str(snap.zone) != Arena.zone():
		_fail("도전했는데 결투장이 아니다: %s" % snap.zone)
		return
	var mobs: Array = snap.monsters
	if mobs.size() != 1 or not bool(mobs[0].get("duel", false)):
		_fail("상대 하나여야 한다: %d" % mobs.size())
		return
	var foe: Dictionary = mobs[0]
	var s := World.stats_of("fighter", int(copy.level), {})
	if int(foe.max_hp) != int(s.maxHp) or int(foe.level) != int(copy.level) or str(foe.name) != str(copy.name):
		_fail("상대 능력치가 복사본과 다르다: 체력 %d / %d · Lv %d" % [int(foe.max_hp), int(s.maxHp), int(foe.level)])
	if str(GameData.monster_kind(str(foe.kind)).get("look", "")) != "varco_fighter":
		_fail("상대가 캐릭터 모델이 아니다")
	if str(snap.dungeon.get("dungeon", "")) != "arena" or str(snap.dungeon.foe) != str(copy.name):
		_fail("결투 판이 안 열렸다: %s" % snap.dungeon)
	if int(snap.dungeon.ends_at) - int(snap.dungeon.starts_at) != Arena.play_ms():
		_fail("싸우는 시간이 %d초가 아니다" % (Arena.play_ms() / 1000))
	me = snap.players.me
	if int(me.hp) != int(me.stats.maxHp):
		_fail("결투장에 들어오면 체력이 가득해야 한다: %d / %d" % [int(me.hp), int(me.stats.maxHp)])
	var gap := Vector2(float(foe.x) - float(me.x), float(foe.z) - float(me.z)).length()
	# 샌드백처럼 붙어서 시작한다 — 둘 다 걷지 않고 바로 친다 (2026-10-12 요청)
	if gap > float(foe.attack_range) or gap > float(me.stats.attackRange):
		_fail("둘이 붙어 있지 않다(사거리 밖): %.1f" % gap)
	var facing := atan2(float(me.x) - float(foe.x), float(me.z) - float(foe.z))
	if absf(wrapf(float(foe.rot) - facing, -PI, PI)) > 0.01:
		_fail("상대가 나를 보고 서 있지 않다")
	# 이미 결투장이면 또 도전할 수 없다
	w.start_duel("me", Arena.dummies(30)[1])
	if str(_foe(w).name) != str(copy.name):
		_fail("결투장 안에서 다시 도전이 됐다")


## 카운트 동안 — 둘 다 선다 · 못 친다 · 못 걷는다 · 물약도 못 마신다. 끝나면 저절로 싸운다
func _case_duel_countdown() -> void:
	var w := _duel()
	var me: Dictionary = w.snapshot().players.me
	var foe := _foe(w)
	var at := Vector2(float(foe.x), float(foe.z))
	for i in 5:
		w.step(0.1)
	if Vector2(float(foe.x), float(foe.z)).distance_to(at) > 1e-4 or bool(me.auto):
		_fail("카운트 중에 상대가 움직였거나 자동이 켜졌다")
	w.attack("me")
	if not _events_of(w.drain_events(), "hit").is_empty():
		_fail("카운트 중에 맞았다")
	var mine := Vector2(float(me.x), float(me.z))
	w.input_move("me", 1, 1.0, 0.0, 0.5)
	if Vector2(float(me.x), float(me.z)).distance_to(mine) > 1e-4:
		_fail("결투장에서 걸었다")
	me.hp = 10
	w.drink_potion("me")
	if int(me.hp) != 10:
		_fail("결투장에서 물약을 마셨다")
	# 카운트가 끝나면 둘 다 친다 — 나는 자동사냥, 상대는 붙어 있으니 걷지 않고 바로 휘두른다
	w.snapshot().dungeon.starts_at = Time.get_ticks_msec() - 1
	var swung := false
	for i in 5:
		w.step(0.1)
		if not _events_of(w.drain_events(), "mobSwing").is_empty():
			swung = true
	if not bool(me.auto):
		_fail("카운트가 끝났는데 자동이 안 켜졌다")
	if not swung:
		_fail("카운트가 끝났는데 상대가 안 휘둘렀다")
	# 걸어도 자동은 그대로다 (사람이 몰지 않는다)
	w.input_move("me", 2, 0.0, 1.0, 0.5)
	if not bool(me.auto):
		_fail("이동 입력에 자동이 꺼졌다")


## 상대는 내가 때릴 때와 같은 식으로 때린다 — `Stats.damage`(몬스터 쪽 K 가 아니다) · 관통 · 치명타
func _case_duel_hits() -> void:
	var w := _duel()
	w.snapshot().dungeon.starts_at = Time.get_ticks_msec() - 1
	var me: Dictionary = w.snapshot().players.me
	var foe := _foe(w)
	foe.crit = 0.0
	var before := int(me.hp)
	w._hit_player(me, foe)
	var want := roundi(Stats.damage(float(foe.attack), int(foe.level), float(me.stats.defense)))
	if before - int(me.hp) != want:
		_fail("상대 피해가 때리는 공식과 다르다: %d (기대 %d)" % [before - int(me.hp), want])
	foe.crit = 1.0
	foe.crit_damage = 1.0
	me.hp = before
	w.drain_events()
	w._hit_player(me, foe)
	var hit: Array = _events_of(w.drain_events(), "hit")
	if before - int(me.hp) != roundi(want * 2.0) or hit.is_empty() or not bool(hit[0].crit):
		_fail("상대 치명타가 두 배가 아니다: %d (기대 %d)" % [before - int(me.hp), roundi(want * 2.0)])
	# 공속이 아주 빠르면 간격을 늘리고 한 대를 세게 — 초당 피해는 같다
	var fast := Arena.foe({"job": "fighter", "level": 200, "passives": {}}, 0.0, 0.0)
	if float(fast.attack_cooldown) < Arena.FOE_MIN_SWING_MS:
		_fail("상대 간격이 바닥(%dms)보다 짧다: %.0f" % [Arena.FOE_MIN_SWING_MS, float(fast.attack_cooldown)])


## 이기면 — 결과(승리 · 점수 +20) · 장부 점수 · 상대는 되살아나지 않는다 · 둘 다 멈춘다
func _case_duel_win() -> void:
	var w := _duel()
	w.snapshot().dungeon.starts_at = Time.get_ticks_msec() - 1
	var me: Dictionary = w.snapshot().players.me
	var foe := _foe(w)
	foe.hp = 1
	w._hit_monster(me, foe, 999999.0, "")
	var results: Array = _events_of(w.drain_events(), "dungeonResult")
	if results.size() != 1 or str(results[0].result) != "clear" or str(results[0].dungeon) != "arena":
		_fail("상대가 쓰러졌는데 승리 결과가 아니다: %s" % str(results))
		return
	var start := Arena.start_score()
	if int(results[0].before) != start or int(results[0].score) != Arena.next_score(start, true):
		_fail("승리 점수: %d → %d" % [int(results[0].before), int(results[0].score)])
	if Arena.score_of(me) != Arena.next_score(start, true) or int(me.arena.get("wins", 0)) != 1:
		_fail("장부 점수가 안 올랐다: %s" % me.arena)
	if bool(me.auto):
		_fail("결과가 났는데 자동이 남았다")
	for i in 3:
		w.step(0.1)
	if int(foe.hp) > 0:
		_fail("쓰러진 상대가 되살아났다")
	w.attack("me")
	if not _events_of(w.drain_events(), "hit").is_empty():
		_fail("결과 뒤에 또 쳤다")
	if not Ledger.view(me).has("arena"):
		_fail("장부 보기에 arena 칸이 없다")


## 지면 — 쓰러짐 · 패배 · 점수 −10. 0 아래로는 안 간다
func _case_duel_lose() -> void:
	var w := _duel()
	w.snapshot().dungeon.starts_at = Time.get_ticks_msec() - 1
	var me: Dictionary = w.snapshot().players.me
	me.arena = {"score": 5}
	var foe := _foe(w)
	me.hp = 1
	w._hit_player(me, foe, 999999.0)
	var results: Array = _events_of(w.drain_events(), "dungeonResult")
	if not bool(me.dead) or results.size() != 1 or str(results[0].result) != "fail":
		_fail("쓰러졌는데 패배가 아니다: 쓰러짐 %s · %s" % [me.dead, str(results)])
		return
	if Arena.score_of(me) != 0 or int(results[0].score) != 0:
		_fail("점수 5 에서 지면 0 이어야 한다: %d" % Arena.score_of(me))
	if int(me.arena.get("losses", 0)) != 1:
		_fail("진 횟수가 안 늘었다")
	# 되살아나면 마을이다
	w.revive("me")
	if str(w.snapshot().zone) != GameData.start_zone():
		_fail("쓰러진 뒤 되살아났는데 마을이 아니다")


## 시간이 다 되면 남은 체력 비율 — 높은 쪽이 이긴다
func _case_duel_time() -> void:
	for mine_ratio in [1.0, 0.2]:
		var w := _duel()
		var run: Dictionary = w.snapshot().dungeon
		run.starts_at = Time.get_ticks_msec() - 1
		var me: Dictionary = w.snapshot().players.me
		var foe := _foe(w)
		foe.hp = int(foe.max_hp) / 2
		me.hp = maxi(1, roundi(float(me.stats.maxHp) * mine_ratio))
		run.ends_at = Time.get_ticks_msec() - 1
		w.step(0.016)
		var results: Array = _events_of(w.drain_events(), "dungeonResult")
		var want := "clear" if mine_ratio > 0.5 else "fail"
		if results.size() != 1 or str(results[0].result) != want:
			_fail("시간 끝 — 내 체력 %.0f%% 대 50%% 인데 %s" % [mine_ratio * 100.0, str(results)])


## 서버 — 인사한 계정에 표를 준다 · 결과는 결투장에 들어와 카운트가 지나야 · 한 판 한 번
func _case_server() -> void:
	_wipe()
	var server := LedgerServer.new(AccountStore.new(DIR))
	var now := [500000]
	server.clock = func() -> int: return now[0]
	if str(server.handle({}, {"t": "arenaBoard"}).get("reason", "")) != "no_hello":
		_fail("인사 전에 결투장 표를 줬다")
	var session := {}
	server.handle(session, {"t": "hello"})
	session.account.ledger.level = 40
	var board: Dictionary = server.handle(session, {"t": "arenaBoard"})
	if str(board.get("t", "")) != "arenaBoard" or board.get("challengers", []).size() != 50:
		_fail("서버 결투장 답이 아니다: %s" % board.keys())
	elif str(board.me.name) != server.name_of(session.account) or int(board.me.level) != 40:
		_fail("서버 답의 내 줄이 장부와 다르다: %s" % board.me)

	var req := [100]
	var send := func(op: String, args: Array) -> Dictionary:
		req[0] += 1
		return server.handle(session, {"t": "op", "id": req[0], "op": op, "args": args})
	if str(send.call("arena_result", [1, "dummy_01"]).get("reason", "")) != "wrong_zone":
		_fail("결투장이 아닌데 결과를 받았다")
	send.call("enter", [Arena.zone()])
	if str(send.call("arena_result", [1, "dummy_01"]).get("reason", "")) != "too_early":
		_fail("카운트 전에 결과를 받았다")
	now[0] += Arena.countdown_ms()
	var ok: Dictionary = send.call("arena_result", [1, "dummy_01"])
	if _events_of(ok.get("events", []), "arenaResult").is_empty():
		_fail("결과를 안 받았다: %s" % ok)
	elif Arena.score_of(session.account.ledger) != Arena.next_score(Arena.start_score(), true):
		_fail("서버 장부 점수가 안 올랐다: %s" % session.account.ledger.get("arena"))
	if str(send.call("arena_result", [1, "dummy_01"]).get("reason", "")) != "claimed":
		_fail("한 판에 결과를 두 번 받았다")
	_wipe()


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


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# 메뉴 판(≡) 안에 결투장 단추 — 누르면 판은 접히고 창이 전체 화면으로
	var cell: Control = null
	for c in game._menu_cells:
		var cap: Label = c.find_child("caption", true, false)
		if cap != null and cap.text == "결투장":
			cell = c
	if cell == null:
		_fail("메뉴에 결투장 단추가 없다")
		_finish()
		return
	if cell.get_parent() != game._menu_grid:
		_fail("결투장 단추가 메뉴 판 안이 아니다")
	game._set_menu_open(true)
	(cell.find_child("hit", true, false) as Button).pressed.emit()
	for i in 3:
		await process_frame
	var panel: ArenaPanel = game._arena_panel
	if not panel.visible or game._menu_sheet.visible:
		_fail("결투장 단추를 눌렀는데 창 %s · 판 %s" % [panel.visible, game._menu_sheet.visible])
		_finish()
		return
	if panel.get_global_rect().size != panel.get_viewport_rect().size:
		_fail("결투장 창이 전체 화면이 아니다: %s" % panel.get_global_rect())

	# 로컬 답이 바로 들어와 표가 선다 — 랭킹 51줄(내 줄 청록) · 도전자 50줄
	var ranking: Array = panel.ranking_rows()
	var rows: Array = panel.challenger_rows()
	if ranking.size() != 51 or rows.size() != 50:
		_fail("랭킹 %d줄 · 도전자 %d줄 (51 · 50 이어야 한다)" % [ranking.size(), rows.size()])
		_finish()
		return
	var mine: Control = null
	for row in ranking:
		if row.name == "me":
			mine = row
	if mine == null or (mine.get_child(1) as Label).get_theme_color("font_color") != ArenaPanel.ME:
		_fail("랭킹에 청록 내 줄이 없다")

	# 둘 다 넘쳐서 굴린다
	for scroll_name in ["RankingScroll", "ChallengerScroll"]:
		var scroll: ScrollContainer = panel.find_child(scroll_name, true, false)
		if scroll.get_v_scroll_bar().max_value <= scroll.size.y:
			_fail("%s 가 굴릴 만큼 안 찼다" % scroll_name)
		elif not scroll.has_meta("drag_scroll"):
			_fail("%s 에 끌기가 없다" % scroll_name)

	# 글자 모으기 (폰트 검사는 결과창까지 모은 뒤에)
	var font: Font = load(FONT)
	var seen := ""
	for label in panel.find_children("*", "Label", true, false):
		seen += label.text
	for button in panel.find_children("*", "Button", true, false):
		seen += button.text

	# 같은 층 창과 서로 닫는다
	game._toggle_sandbag()
	if panel.visible:
		_fail("샌드백 창을 열었는데 결투장 창이 남았다")
	game._toggle_arena()
	if not panel.visible or game._sandbag_panel.visible:
		_fail("결투장을 열면 샌드백 창이 닫혀야 한다")
	for i in 2:
		await process_frame

	# 도전자 줄을 누르면(진짜 입력) 창이 닫히고 결투장으로 — 카운트 · 시계 줄(VS 이름) · 물약·자동사냥 칸 숨김
	rows = panel.challenger_rows()
	var at := (rows[0] as Control).get_global_rect().get_center()
	_push_mouse(at, true)
	_push_mouse(at, false)
	for i in 3:
		await process_frame
	var foe_name := Arena.dummy_name(0)
	if panel.visible or game._shown_zone != Arena.zone():
		_fail("도전했는데 창 %s · 존 %s" % [panel.visible, game._shown_zone])
		_finish()
		return
	if not game._sandbag_count.visible or game._sandbag_count.text != "3":
		_fail("들어오면 가운데 큰 카운트 3: 보임 %s '%s'" % [game._sandbag_count.visible, game._sandbag_count.text])
	var run: Dictionary = game._transport.snapshot().dungeon
	run.starts_at = Time.get_ticks_msec() - 1
	await process_frame
	if not game._trial_hud.visible or not game._trial_hud.text.contains("VS %s" % foe_name):
		_fail("시계 줄에 상대 이름이 없다: '%s'" % game._trial_hud.text)
	seen += game._trial_hud.text
	if game._potion_cell.is_visible_in_tree() or game._auto_cell.is_visible_in_tree():
		_fail("결투장에 물약·자동사냥 칸이 남았다")
	if not game._mob_nodes.has("duel_foe") or not game._mob_nodes["duel_foe"] is Rig:
		_fail("상대가 캐릭터 모델로 안 섰다")
	else:
		# 상대가 휘두르면 내 연속 앞차기(평타 넷 중 하나)를 공속 배속으로 찬다 — 몬스터 할퀴기(`Attack`)가 아니다
		game._on_event(&"mobSwing", {"id": "duel_foe"})
		await process_frame
		var foe_rig: Rig = game._mob_nodes["duel_foe"]
		if not game._foe_clip in game.SWING_CLIPS or foe_rig._playing != game._foe_clip:
			_fail("상대 공격 동작이 앞차기가 아니다: 고른 것 '%s' · 트는 것 '%s'" % [game._foe_clip, foe_rig._playing])

	# 이기면 결과창 — 승리 · VS 이름 · 점수 1,000 → 1,020. 확인 → 마을
	var world: World = game._transport._world
	var foe: Dictionary = {}
	for monster in world.snapshot().monsters:
		if bool(monster.get("duel", false)):
			foe = monster
	foe.hp = 1
	world._hit_monster(world.snapshot().players.values()[0], foe, 999999.0, "")
	for i in 3:
		await process_frame
	var result: DungeonResult = game._dungeon_result
	var start := Arena.start_score()
	var want := "%s → %s" % [DungeonResult.comma(start), DungeonResult.comma(Arena.next_score(start, true))]
	if not result.visible or result._verdict.text != "승리" or not result._count.text.contains(want) \
			or not result._count.text.contains(foe_name):
		_fail("결과창: 보임 %s · '%s' · '%s'" % [result.visible, result._verdict.text, result._count.text])
	seen += result._title.text + result._verdict.text + result._count.text + "패배"
	var missing := ""
	for ch in seen:
		if ch != " " and ch != "\n" and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	if missing != "":
		_fail("결투장 글자가 폰트에 없다: %s" % missing)
	result.confirm_button().pressed.emit()
	for i in 3:
		await process_frame
	if game._shown_zone != GameData.start_zone():
		_fail("결과창 확인 → 마을이 아니다: %s" % game._shown_zone)
	# 다시 열면 오른 점수로 선다
	game._toggle_arena()
	await process_frame
	var me_rank: Label = panel.find_child("me_rank", true, false)
	if not me_rank.text.contains(DungeonResult.comma(Arena.next_score(start, true))):
		_fail("이긴 뒤 창의 점수가 안 올랐다: '%s'" % me_rank.text)
	_finish()


func _finish() -> void:
	Save.clear()
	if _failed == 0:
		print("arena_test: 통과")
	else:
		print("arena_test: 실패 %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _push_mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
