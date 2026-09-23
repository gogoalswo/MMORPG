extends SceneTree

## 왼쪽 아래 채팅창(`ChatLog`) — 몬스터를 잡으면 경험치와 장비 획득이 한 줄씩 적히는지 본다.
##
## 진짜로 잡는다(`World._hit_monster`) — 보상 이벤트가 화면까지 오는 길을 같이 본다.
## 스크린샷을 찍지 않는다. 자리·글자·줄 수는 노드로 읽는다.
##
##   godot --headless --path godot --script tests/chat_log_test.gd

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
	var chat: ChatLog = game._chat
	if chat == null:
		_fail("채팅창이 없다")
		_done()
		return

	await _case_kill(game, chat)
	_case_item(game, chat)
	_case_place(game, chat)
	await _case_stays(chat)
	_case_cap(chat)
	_done()


## 사냥터에서 한 마리를 잡으면 `경험치 +n` 이 적힌다
func _case_kill(game: Node3D, chat: ChatLog) -> void:
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
	var want := "+%d" % int(mob.exp_reward)
	for pair in chat.lines():
		if pair[0] == "경험치" and pair[1] == want:
			print("  잡으니 적힘: 경험치 %s" % want)
			return
	_fail("잡았는데 '경험치 %s' 가 안 적혔다 (%s)" % [want, chat.lines()])


## 장비를 얻으면 이름이 적힌다. 골드만 떨어지면 안 적힌다
func _case_item(game: Node3D, chat: ChatLog) -> void:
	var before := chat.lines().size()
	game._on_event(&"loot", {"gold": 5})
	if chat.lines().size() != before:
		_fail("골드만 떨어졌는데 줄이 늘었다")
	game._on_event(&"loot", {"gold": 5, "item": {"id": "g3_w", "grade": 3, "enhance": 0}})
	var last: Array = chat.lines().back()
	var name := str(Items.get_item("g3_w").get("name", ""))
	if last != ["장비 획득", name]:
		_fail("장비 획득 줄이 '%s' 가 아니다 (%s)" % [name, last])
	elif not chat._text.get_parsed_text().ends_with(name):
		_fail("창 글자 맨 끝이 '%s' 가 아니다" % name)
	elif name.begins_with(Items.grade_name(3)):
		_fail("이름에 등급 글자가 붙어 있다 (%s) — 등급은 색이 알린다" % name)
	else:
		print("  장비 획득: %s" % name)
	# 등급마다 색이 달라야 한다 — 흰색을 섞던 때는 서로 비슷했다
	var seen := {}
	for g in range(1, 8):
		var c := ChatLog.grade_text_color(g)
		var hue := absf(c.h - Items.grade_color(g).h)
		if g != 2 and minf(hue, 1.0 - hue) > 0.02:
			_fail("%d등급 글자 색의 색상이 표와 다르다" % g)
		seen[c.to_html(false)] = true
	if seen.size() != 7:
		_fail("등급 글자 색이 %d가지뿐이다" % seen.size())


## 왼쪽 아래 구석, 경험치 띠 위. 테스트 단추·퀵슬롯과 안 겹친다
func _case_place(game: Node3D, chat: ChatLog) -> void:
	var box := chat.get_global_rect()
	var screen := game.get_viewport().get_visible_rect().size
	if box.position.x > 40 or box.end.y < screen.y - 60 or box.end.y > screen.y - game.EXP_GAUGE_H:
		_fail("왼쪽 아래 구석이 아니다: %s (화면 %s)" % [box, screen])
	for button in game._switch_buttons.values():
		if box.intersects(button.get_global_rect()):
			_fail("테스트 단추(%s)와 겹친다" % button.get_global_rect())
	for button in game._bar_buttons:
		if box.intersects(button.get_global_rect()):
			_fail("퀵슬롯(%s)과 겹친다" % button.get_global_rect())
	print("  자리: %s" % box)


## 채팅창이라 줄이 **사라지지 않는다** (잠깐 뜨고 지던 알림과 다르다)
func _case_stays(chat: ChatLog) -> void:
	var before := chat.lines().size()
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 1500:
		await process_frame
	if chat.lines().size() != before:
		_fail("시간이 지나니 줄이 %d → %d 로 줄었다" % [before, chat.lines().size()])


## 오래 사냥해도 `MAX_LINES` 줄까지만 — 오래된 것부터 지우고 새 것이 맨 아래
func _case_cap(chat: ChatLog) -> void:
	var count := ChatLog.MAX_LINES + 5
	for i in count:
		chat.add_exp(i + 1)
	var shown := chat.lines()
	if shown.size() != ChatLog.MAX_LINES:
		_fail("줄이 %d개다 (%d개여야)" % [shown.size(), ChatLog.MAX_LINES])
	elif shown.back()[1] != "+%d" % count:
		_fail("맨 아래가 새 줄이 아니다 (%s)" % shown.back())
	elif chat._text.get_paragraph_count() != ChatLog.MAX_LINES:
		_fail("창 글자가 %d줄이다 (%d줄이어야)" % [chat._text.get_paragraph_count(), ChatLog.MAX_LINES])
	else:
		print("  %d줄까지, 새 것이 맨 아래" % shown.size())


func _done() -> void:
	if _failed == 0:
		print("채팅창: 통과")
		quit(0)
	else:
		print("채팅창: %d개 실패" % _failed)
		quit(1)
