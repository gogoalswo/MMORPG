extends SceneTree

## 랭킹 창 (docs/features/server.md "랭킹") — 서버 없이 뜬 게임에는 메뉴 단추가 없고,
## 서버의 답을 넣으면 표가 서고 내 줄이 칠해지는지 본다. 스크린샷 없이 노드로 읽는다.
##
##   godot --headless --path godot --script tests/rank_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	for cell in game._menu_cells:
		var caption: Label = cell.find_child("caption", true, false)
		if caption != null and caption.text == "랭킹":
			_fail("서버 없이 뜬 게임에 랭킹 단추가 있다")

	# 단추는 서버에 붙어야 서지만 그림은 늘 있어야 한다 — sync:godot 을 안 돌렸으면 여기서 멈춘다
	if game._icon("ui_icon_rank") == null:
		_fail("랭킹 아이콘(ui_icon_rank)이 없다 — npm run sync:godot 을 돌렸나")

	game._toggle_rank()
	if not game._rank_panel.visible or not game._rank_note.text.contains("불러오는"):
		_fail("열면 창이 서고 '불러오는 중' 이어야 한다")
	game._on_event(&"rank", {
		"top": [
			{"rank": 1, "name": "모험가#AAAA", "level": 120, "exp": 10},
			{"rank": 2, "name": "모험가#BBBB", "level": 90, "exp": 0},
			{"rank": 3, "name": "모험가#CCCC", "level": 5, "exp": 3},
		],
		"me": {"rank": 2, "level": 90, "exp": 0}, "total": 3,
	})
	await process_frame
	var cells: Array = game._rank_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	if cells.size() != 4 * 4:
		_fail("표 칸이 %d — 머리 줄 + 세 줄 × 4칸이어야 한다" % cells.size())
	else:
		if cells[4 * 2 + 1].text != "모험가#BBBB" or cells[4 * 2 + 1].get_theme_color("font_color") != ChatLog.EXP:
			_fail("내 줄(2위)이 청록이 아니다")
		if cells[4 * 1 + 1].get_theme_color("font_color") != game.INV_GOLD_HI:
			_fail("1위가 밝은 금빛이 아니다")
	if not game._rank_note.text.contains("2위 / 3명"):
		_fail("내 순위 줄이 '%s'" % game._rank_note.text)
	game._toggle_rank()
	if game._rank_panel.visible:
		_fail("다시 누르면 닫혀야 한다")

	Save.clear()
	if _failed == 0:
		print("랭킹 창: 전부 통과")
		quit(0)
	else:
		print("랭킹 창: %d개 실패" % _failed)
		quit(1)
