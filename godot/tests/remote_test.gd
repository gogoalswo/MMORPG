extends SceneTree

## 기기 ↔ 서버 (docs/features/server.md 3단계) — 실제 웹소켓으로 `World` 를 서버에 붙인다.
## 서버(`GameServer`)와 기기(`ServerLedger`)를 한 프로세스에서 번갈아 `poll` 한다.
## 계정·토큰은 테스트 전용 자리에 만들고 **끝나면 지운다.**
##
##   godot --headless --path godot --script tests/remote_test.gd

const DIR := "user://remote_test_accounts"
const TOKEN := "user://remote_test_token.json"
const ME := "me"

var _failed := 0
var _server: GameServer
var _link: ServerLedger
var _world: World
var _skew := 0


func _init() -> void:
	_wipe()
	_server = GameServer.new(AccountStore.new(DIR))
	if _server.listen(0) != OK:
		_fail("서버가 못 떴다")
	else:
		_run()
		_link.close()
		_server.stop()
	_wipe()

	if _failed == 0:
		print("기기-서버: 전부 통과")
		quit(0)
	else:
		print("기기-서버: %d개 실패" % _failed)
		quit(1)


func _run() -> void:
	_world = World.new()
	_world.open("meadow")
	_world.join(ME)
	_link = ServerLedger.new("ws://127.0.0.1:%d" % _server.port(), TOKEN)
	_link.retry_ms = 50
	_link.welcomed.connect(func(ledger: Dictionary) -> void: _world.apply_ledger(ME, ledger, []))
	_link.replied.connect(func(ledger: Dictionary, events: Array) -> void:
		_world.apply_ledger(ME, ledger, events))
	_world.remote = _link
	_link.request(&"enter", [_world.zone_id])  # LocalTransport._attach 가 하는 것과 같다
	# 서버 시계를 앞당길 수 있게 — 처치는 최소 처치 시간이 지나야 받는다
	_server.ledger_server.clock = func() -> int: return Time.get_ticks_msec() + _skew

	# 붙기 **전에** 낸 요청은 쌓였다가 welcome 뒤에 간다
	_world.sort_bag(ME)
	if not _pump(func() -> bool: return _link.ready and _link.waiting() == 0):
		_fail("welcome·첫 요청 답이 안 왔다")
		return
	_world.drain_events()
	_case_welcome()
	_case_kill()
	_case_lost_reply()


## 새 계정의 장부가 기기에 들어온다 — 시작 장비·첫 선물은 **서버가** 줬다. 숫자는 정수로 온다
func _case_welcome() -> void:
	var me: Dictionary = _world._players[ME]
	for slot in Ledger.STARTER_SLOTS:
		if me.equipped.get(slot, {}).is_empty():
			_fail("서버가 준 시작 장비(%s)가 기기에 없다" % slot)
	var crystal: Array = me.bag.filter(func(s: Dictionary) -> bool: return s.get("id") == Items.crystal_id())
	if crystal.is_empty() or int(crystal[0].count) != 30:
		_fail("첫 선물(크리스탈 30개)이 기기에 없다: %s" % [me.bag])
	if typeof(me.level) != TYPE_INT or typeof(me.equipped.weapon.grade) != TYPE_INT:
		_fail("JSON 을 거친 숫자가 정수로 안 돌아왔다: level %s · grade %s" % [
			type_string(typeof(me.level)), type_string(typeof(me.equipped.weapon.get("grade")))])
	if not FileAccess.file_exists(TOKEN):
		_fail("토큰을 안 남겼다")


## 처치 → **기기는 판정하지 않고** 서버의 답으로 경험치·보상을 받는다
func _case_kill() -> void:
	var me: Dictionary = _world._players[ME]
	var target: Dictionary = _world._monsters[0]
	var exp_before := int(me.exp)
	var level_before := int(me.level)
	_skew += 600000  # 10분 — 어떤 몬스터든 최소 처치 시간이 지났다
	_world._kill(me, target, Time.get_ticks_msec())
	if int(me.exp) != exp_before:
		_fail("서버에 붙었는데 기기가 경험치를 먼저 올렸다")
	if not _pump(func() -> bool: return _link.waiting() == 0):
		_fail("처치 답이 안 왔다")
		return
	if int(me.exp) == exp_before and int(me.level) == level_before:
		_fail("서버 답이 왔는데 경험치가 그대로다 — %s" % target.kind)
	var types := _world.drain_events().map(func(e: Dictionary) -> String: return str(e.type))
	if not ("loot" in types and "reward" in types):
		_fail("처치 이벤트(loot·reward)가 화면으로 안 흘렀다: %s" % [types])


## 판 요청의 **답만 잃고** 끊겼다 → 다시 붙어 같은 번호로 보내면 서버는 다시 팔지 않는다
func _case_lost_reply() -> void:
	var me: Dictionary = _world._players[ME]
	# 장비를 **둘** 가방에 둔다 — 같은 번호를 두 번 판정하면 남은 하나가 또 팔려서 드러난다
	_world.unequip(ME, "weapon")
	_world.unequip(ME, "armor")
	_pump(func() -> bool: return _link.waiting() == 0)
	var at := -1
	for i in me.bag.size():
		if at < 0 and not Items.is_material(str(me.bag[i].id)):
			at = i
	var gold := int(me.gold)
	# NPC 곁이 아니라 `World.npc_sell` 은 막힌다 — 통로에 바로 넣는다
	_link.request(&"sell", [at])
	# 기기가 보내고(poll) → 서버가 판정해 답을 보내면(poll) → **기기가 읽기 전에** 끊는다
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_link.poll()
		_server.poll()
		if _server_gold() > gold:
			break
		OS.delay_msec(5)
	var sold_gold := _server_gold()
	if sold_gold <= gold:
		_fail("서버가 판매를 판정하지 않았다")
		return
	_link.close()
	if not _pump(func() -> bool: return _link.ready and _link.waiting() == 0):
		_fail("다시 붙어 남은 요청을 못 끝냈다")
		return
	if _server_gold() != sold_gold or int(me.gold) != sold_gold:
		_fail("잃은 답을 다시 받다가 두 번 팔았다 — 서버 %d · 기기 %d · 한 번 판 값 %d" % [
			_server_gold(), int(me.gold), sold_gold])


func _server_gold() -> int:
	for account in _server.ledger_server._accounts.values():
		return int(account.ledger.gold)
	return -1


## 서버와 기기를 번갈아 돌린다. 조건이 서면 true
func _pump(done: Callable, ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		_server.poll()
		_link.poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _wipe() -> void:
	if FileAccess.file_exists(TOKEN):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN))
	var path := ProjectSettings.globalize_path(DIR)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(path)
