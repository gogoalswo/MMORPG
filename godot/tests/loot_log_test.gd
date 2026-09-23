extends SceneTree

## 왼쪽 획득 알림(`LootLog`) — 몬스터를 잡으면 경험치와 장비 획득이 한 줄씩 뜨는지 본다.
##
## 진짜로 잡는다(`World._hit_monster`) — 보상 이벤트가 화면까지 오는 길을 같이 본다.
## 스크린샷을 찍지 않는다. 자리·글자·줄 수·사라짐은 노드로 읽는다.
##
##   godot --headless --path godot --script tests/loot_log_test.gd

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
	var log: LootLog = game._loot_log
	if log == null:
		_fail("획득 알림이 없다")
		_done()
		return

	await _case_kill(game, log)
	_case_item(game, log)
	_case_cap(log)
	_case_place(game, log)
	await _case_gone(log)
	_done()


## 사냥터에서 한 마리를 잡으면 `경험치 +n` 이 뜬다
func _case_kill(game: Node3D, log: LootLog) -> void:
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
	for pair in log.lines():
		if pair[0] == "경험치" and pair[1] == want:
			print("  잡으니 뜸: 경험치 %s" % want)
			return
	_fail("잡았는데 '경험치 %s' 가 안 떴다 (%s)" % [want, log.lines()])


## 장비를 얻으면 이름이 등급 색으로 뜬다. 골드만 떨어지면 안 뜬다
func _case_item(game: Node3D, log: LootLog) -> void:
	var before := log.lines().size()
	game._on_event(&"loot", {"gold": 5})
	if log.lines().size() != before:
		_fail("골드만 떨어졌는데 줄이 늘었다")
	game._on_event(&"loot", {"gold": 5, "item": {"id": "g3_w", "grade": 3, "enhance": 0}})
	var last: Array = log.lines().back()
	var name := str(Items.get_item("g3_w").get("name", ""))
	if last != ["장비 획득", name]:
		_fail("장비 획득 줄이 '%s' 가 아니다 (%s)" % [name, last])
	else:
		print("  장비 획득: %s" % name)


## 한꺼번에 들어와도 `MAX_LINES` 줄까지만 — 오래된 것부터 밀린다
func _case_cap(log: LootLog) -> void:
	for i in LootLog.MAX_LINES + 3:
		log.add_exp(i + 1)
	var shown := log.lines()
	if shown.size() != LootLog.MAX_LINES:
		_fail("줄이 %d개다 (%d개여야)" % [shown.size(), LootLog.MAX_LINES])
	elif shown.back()[1] != "+%d" % (LootLog.MAX_LINES + 3):
		_fail("맨 아래가 새 줄이 아니다 (%s)" % shown.back())
	else:
		print("  %d줄까지, 새 것이 맨 아래" % shown.size())


## 왼쪽에 있고, 꽉 차도 왼쪽 아래 테스트 단추에 안 닿는다
func _case_place(game: Node3D, log: LootLog) -> void:
	var box := Rect2(log.global_position, Vector2(200, LootLog.MAX_LINES * (LootLog.LINE_H + 4)))
	if box.position.x > 60:
		_fail("왼쪽이 아니다 (x %.0f)" % box.position.x)
	for button in game._switch_buttons.values():
		if box.intersects(button.get_global_rect()):
			_fail("꽉 차면 테스트 단추(%s)와 겹친다" % button.get_global_rect())
	print("  자리: %s, 꽉 차면 아래 끝 %.0f" % [log.global_position, box.end.y])


## `LIFE` 초 뒤에 스스로 사라진다
func _case_gone(log: LootLog) -> void:
	var began := Time.get_ticks_msec()
	var limit := int((LootLog.LIFE + 1.5) * 1000)
	while not log.lines().is_empty() and Time.get_ticks_msec() - began < limit:
		await process_frame
	var waited := float(Time.get_ticks_msec() - began) / 1000.0
	if not log.lines().is_empty():
		_fail("%.1f초가 지나도 줄이 안 사라졌다" % waited)
	elif log.get_child_count() != 0:
		_fail("줄은 비었는데 노드가 %d개 남았다" % log.get_child_count())
	else:
		print("  %.1f초 뒤 전부 사라짐" % waited)


func _done() -> void:
	if _failed == 0:
		print("획득 알림: 통과")
		quit(0)
	else:
		print("획득 알림: %d개 실패" % _failed)
		quit(1)
