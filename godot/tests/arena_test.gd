extends SceneTree

## 결투장 (docs/features/arena.md) — 더미 50명 표(`Arena.board`) · 서버 답 · 창(메뉴 → 전체 화면 · 랭킹 ·
## 도전자 목록 굴림 · 도전 안내 · 닫기 · 글자). 스크린샷 없이 노드로 읽는다.
##
##   godot --headless --path godot --script tests/arena_test.gd

const DIR := "user://test_arena_accounts"
const FONT := "res://assets/fonts/NotoSansKR-subset.ttf"

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_board()
	_case_server()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


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
	if int(me.get("rank", 0)) != 26 or int(me.get("score", 0)) != Arena.START_SCORE or str(me.get("name", "")) != "나":
		_fail("처음 들어온 나는 26위 · 점수 %d: %s" % [Arena.START_SCORE, me])
	if not bool(ranking[25].get("me", false)):
		_fail("랭킹 26번째 줄이 내 줄이 아니다")
	if int(list[0].level) <= int(list[49].level):
		_fail("점수가 높은 더미가 레벨도 높아야 한다")
	# 레벨 끝 — 1레벨은 1 아래로, 만렙은 만렙 위로 안 간다
	var max_level := int(GameData.combat().maxLevel)
	for level in [1, max_level]:
		for row in Arena.dummies(level):
			if int(row.level) < 1 or int(row.level) > max_level:
				_fail("더미 레벨이 1 ~ %d 밖: Lv.%d (내 레벨 %d)" % [max_level, int(row.level), level])
				break


## 서버 — 인사한 계정에 같은 표를 준다 (이름은 서버가 붙인 것). 인사 전에는 거절
func _case_server() -> void:
	_wipe()
	var server := LedgerServer.new(AccountStore.new(DIR))
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
	var mine: Control = ranking[25]
	if mine.name != "me" or (mine.get_child(1) as Label).get_theme_color("font_color") != ArenaPanel.ME:
		_fail("랭킹 26번째가 청록 내 줄이 아니다")
	if not str(panel.find_child("me_rank", true, false).text).begins_with("26위 / 51명"):
		_fail("내 기록 줄: '%s'" % panel.find_child("me_rank", true, false).text)

	# 둘 다 넘쳐서 굴린다
	for scroll_name in ["RankingScroll", "ChallengerScroll"]:
		var scroll: ScrollContainer = panel.find_child(scroll_name, true, false)
		if scroll.get_v_scroll_bar().max_value <= scroll.size.y:
			_fail("%s 가 굴릴 만큼 안 찼다" % scroll_name)
		elif not scroll.has_meta("drag_scroll"):
			_fail("%s 에 끌기가 없다" % scroll_name)

	# 도전자 줄을 누르면(진짜 입력) 안내 줄이 바뀐다 — 결투는 아직 없다
	var first: Control = rows[0]
	var at := first.get_global_rect().get_center()
	_push_mouse(at, true)
	_push_mouse(at, false)
	await process_frame
	var dummy_name := Arena.dummy_name(0)
	if panel.notice_text() != "%s 님과의 결투는 준비 중입니다." % dummy_name:
		_fail("도전을 눌렀는데 안내가 '%s'" % panel.notice_text())

	# 글자가 폰트에 다 있나
	var font: Font = load(FONT)
	var seen := ""
	for label in panel.find_children("*", "Label", true, false):
		seen += label.text
	for button in panel.find_children("*", "Button", true, false):
		seen += button.text
	var missing := ""
	for ch in seen:
		if ch != " " and ch != "\n" and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	if missing != "":
		_fail("결투장 글자가 폰트에 없다: %s" % missing)

	# 같은 층 창과 서로 닫는다 · 단추를 다시 누르면 닫힌다
	game._toggle_sandbag()
	if panel.visible:
		_fail("샌드백 창을 열었는데 결투장 창이 남았다")
	game._toggle_arena()
	if not panel.visible or game._sandbag_panel.visible:
		_fail("결투장을 열면 샌드백 창이 닫혀야 한다")
	game._toggle_arena()
	if panel.visible:
		_fail("다시 누르면 닫혀야 한다")
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
