extends SceneTree

## 오른쪽 아래 경험치 알림(`ExpToast`, 2026-09-28) — 잡으면 "경험치를 얻었습니다 (+n)" 이 떴다가
## 잠시 뒤 사라지는지, 자리가 오른쪽 아래 · 경험치 띠 위이고 퀵슬롯과 안 겹치는지 본다.
##
## 진짜로 잡는다(`World._hit_monster`). 스크린샷을 찍지 않는다 — 자리·글자는 노드로 읽는다.
##
##   godot --headless --path godot --script tests/exp_toast_test.gd

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
	var toast: ExpToast = game._exp_toast
	if toast == null:
		_fail("경험치 알림이 없다")
		_done()
		return

	await _case_kill(game, toast)
	_case_place(game, toast)
	await _case_fade(toast)
	_case_cap(toast)
	_done()


## 사냥터에서 한 마리를 잡으면 오른쪽 아래에 뜬다
func _case_kill(game: Node3D, toast: ExpToast) -> void:
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 3:
		await process_frame
	var world = game._transport._world
	var player: Dictionary = world._players[game._transport.my_id()]
	var mobs: Array = world.snapshot().monsters
	if mobs.is_empty():
		_fail("사냥터에 몬스터가 없다")
		return
	var mob: Dictionary = mobs[0]
	mob.hp = 1
	world._hit_monster(player, mob, 1.0, "")
	for i in 3:
		await process_frame
	var want := "경험치를 얻었습니다 (+%d)" % int(mob.exp_reward)
	var shown := toast.lines()
	if shown.is_empty() or shown.back() != want:
		_fail("잡았는데 '%s' 가 안 떴다 (%s)" % [want, toast.lines()])
	else:
		print("  잡으니 뜸: %s" % want)


## 오른쪽 아래 구석, 경험치 띠 바로 위. 퀵슬롯·자동사냥 칸·채팅창과 안 겹치고, 터치를 안 받는다
func _case_place(game: Node3D, toast: ExpToast) -> void:
	var box := toast.get_global_rect()
	var screen := game.get_viewport().get_visible_rect().size
	if box.end.x < screen.x - 40 or box.end.y < screen.y - 60 or box.end.y > screen.y - game.EXP_GAUGE_H:
		_fail("오른쪽 아래 구석이 아니다: %s (화면 %s)" % [box, screen])
	var others: Array = game._bar_buttons.duplicate()
	others.append(game._auto_cell)
	others.append(game._chat)
	for other in others:
		if box.intersects(other.get_global_rect()):
			_fail("%s 와 겹친다 (%s)" % [other.name, other.get_global_rect()])
	if toast.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("알림이 터치를 받는다 — 글자 뒤 땅이 안 눌린다")
	for line in toast.get_children():
		if line.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("알림 글자가 터치를 받는다")
			break
	print("  자리: %s" % box)


## 잠깐 떴다가 사라진다 — 머무는 시간 + 옅어지는 시간이 지나면 한 줄도 없다
func _case_fade(toast: ExpToast) -> void:
	var began := Time.get_ticks_msec()
	var wait := int((ExpToast.SHOW_SEC + ExpToast.FADE_SEC) * 1000) + 300
	while Time.get_ticks_msec() - began < wait:
		await process_frame
	await process_frame
	if not toast.lines().is_empty():
		_fail("%.1f초가 지나도 남아 있다 (%s)" % [wait / 1000.0, toast.lines()])
	else:
		print("  %.1f초 뒤 사라짐" % (wait / 1000.0))


## 한꺼번에 많이 잡아도 `MAX_LINES` 줄까지만 — 새 것이 맨 아래
func _case_cap(toast: ExpToast) -> void:
	var count := ExpToast.MAX_LINES + 4
	for i in count:
		toast.add_exp(i + 1)
	var shown := toast.lines()
	if shown.size() != ExpToast.MAX_LINES:
		_fail("줄이 %d개다 (%d개여야)" % [shown.size(), ExpToast.MAX_LINES])
	elif shown.back() != "경험치를 얻었습니다 (+%d)" % count:
		_fail("맨 아래가 새 줄이 아니다 (%s)" % shown.back())
	else:
		print("  %d줄까지, 새 것이 맨 아래" % shown.size())


func _done() -> void:
	if _failed == 0:
		print("경험치 알림: 통과")
		quit(0)
	else:
		print("경험치 알림: %d개 실패" % _failed)
		quit(1)
