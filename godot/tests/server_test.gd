extends SceneTree

## 서버 뼈대 (docs/features/server.md 2단계) — 계정 저장소 · 장부 요청 · 웹소켓 왕복.
## 계정은 테스트 전용 폴더에 만들고 **끝나면 지운다.**
##
##   godot --headless --path godot --script tests/server_test.gd

const DIR := "user://server_test_accounts"

var _failed := 0


func _init() -> void:
	_wipe()
	_case_fresh_matches_join()
	_case_store()
	_case_hello_and_ops()
	_case_rejects()
	_case_socket()
	_wipe()

	if _failed == 0:
		print("서버: 전부 통과")
		quit(0)
	else:
		print("서버: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _wipe() -> void:
	var path := ProjectSettings.globalize_path(DIR)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(path)


## 서버가 만드는 새 계정과 기기의 새 캐릭터는 **장부가 같아야 한다** — 어긋나면
## 서버에 붙는 순간 스킬이나 포인트가 바뀐다
func _case_fresh_matches_join() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var joined := Ledger.view(w._players["me"])
	var fresh := Ledger.fresh(World.DEFAULT_JOB)
	for key in Ledger.KEYS:
		if JSON.stringify(joined[key]) != JSON.stringify(fresh[key]):
			_fail("새 계정의 %s 가 join 과 다르다 — join %s · fresh %s" % [key, joined[key], fresh[key]])


func _case_store() -> void:
	var store := AccountStore.new(DIR)
	var made := store.create({"gold": 5})
	var token := str(made.get("token", ""))
	if token.split(".").size() != 2:
		_fail("토큰 모양이 <id>.<비밀> 이 아니다: %s" % token)
		return
	var found := store.find(token)
	if int(found.get("ledger", {}).get("gold", -1)) != 5:
		_fail("만든 계정을 토큰으로 못 찾는다")
	if found.has("token"):
		_fail("저장된 계정에 토큰이 그대로 남았다 — 해시만 남아야 한다")
	var text := FileAccess.get_file_as_string(DIR.path_join(str(made.id) + ".json"))
	if text.contains(token.split(".")[1]):
		_fail("파일에 비밀이 그대로 적혔다")
	if not store.find(str(made.id) + ".00").is_empty():
		_fail("틀린 비밀로 계정이 열린다")
	if not store.find("../../project.x").is_empty() or not store.find("").is_empty():
		_fail("이상한 토큰이 빈 계정이 아니다")


func _case_hello_and_ops() -> void:
	var server := LedgerServer.new(AccountStore.new(DIR))
	var session := {}
	var welcome := server.handle(session, {"t": "hello"})
	if welcome.get("t") != "welcome" or not welcome.has("token"):
		_fail("토큰 없는 hello 에 새 계정이 안 나온다: %s" % welcome)
		return
	var ledger: Dictionary = welcome.ledger
	for slot in Ledger.STARTER_SLOTS:
		if ledger.equipped.get(slot, {}).is_empty():
			_fail("새 계정에 시작 장비(%s)가 안 끼워졌다" % slot)
	if ledger.skills.is_empty():
		_fail("새 계정이 첫 스킬을 안 배웠다")

	# 벗기 → 팔기. 판 값은 다시 보내도 한 번만 들어온다
	var off := server.handle(session, {"t": "op", "id": 1, "op": "unequip", "args": ["weapon"]})
	if off.get("t") != "result" or off.ledger.bag.size() != 1:
		_fail("unequip 이 가방에 안 넣었다: %s" % off)
		return
	var sold := server.handle(session, {"t": "op", "id": 2, "op": "sell", "args": [0]})
	var gold := int(sold.ledger.gold)
	if gold <= 0 or not sold.ledger.bag.is_empty():
		_fail("sell 이 골드를 안 줬다: %s" % sold.ledger)
	var again := server.handle(session, {"t": "op", "id": 2, "op": "sell", "args": [0]})
	if int(again.get("ledger", {}).get("gold", -1)) != gold:
		_fail("같은 요청 번호를 두 번 판정했다 — 골드 %s → %s" % [gold, again.get("ledger", {}).get("gold")])

	# 다시 들어오면 **저장된 장부**와 마지막 번호가 온다
	var back := server.handle({}, {"t": "hello", "token": welcome.token})
	if back.has("token"):
		_fail("있는 계정에 토큰을 다시 내줬다")
	if int(back.ledger.gold) != gold or back.ledger.equipped.has("weapon"):
		_fail("다시 들어왔는데 장부가 저장된 것과 다르다: %s" % back.ledger)
	if int(back.get("last_req", 0)) != 2:
		_fail("last_req 가 2 가 아니다: %s" % back.get("last_req"))

	# 남겨 둔 답은 **그때 값**이다 — 뒤에 바뀐 장부가 스며들면 안 된다
	# (장부는 `Ledger.view` 가 복사한다. 이벤트의 inventory 가 가방을 그대로 가리키는 게 샌다)
	var kept := JSON.stringify(sold)
	server.handle(session, {"t": "op", "id": 3, "op": "unequip", "args": ["armor"]})
	if JSON.stringify(sold) != kept:
		_fail("보낸 답(이벤트)이 나중 변경을 따라 바뀌었다")

	# 같은 토큰으로 **두 번 붙어도 장부는 하나다** — 한쪽에서 판 것을 다른 쪽이 또 못 판다
	var twin := {}
	server.handle(twin, {"t": "hello", "token": welcome.token})
	var first := server.handle(session, {"t": "op", "id": 4, "op": "sell", "args": [0]})
	var second := server.handle(twin, {"t": "op", "id": 5, "op": "sell", "args": [0]})
	# 사본을 따로 들면 양쪽 골드가 똑같이 한 번씩만 늘어서 골드로는 못 잡는다 — **팔렸는지**를 본다
	if first.events.is_empty() or not second.events.is_empty():
		_fail("두 연결에서 같은 갑옷을 두 번 팔았다 — %s · %s" % [first.events, second.events])


func _case_rejects() -> void:
	var server := LedgerServer.new(AccountStore.new(DIR))
	var session := {}
	var cases := [
		[{"t": "op", "id": 1, "op": "sort_bag", "args": []}, "no_hello"],
	]
	for pair in cases:
		var reply := server.handle(session, pair[0])
		if reply.get("reason") != pair[1]:
			_fail("%s → %s 이어야 하는데 %s" % [pair[0], pair[1], reply])
	server.handle(session, {"t": "hello"})
	cases = [
		[{"t": "op", "id": 1, "op": "kill", "args": [{}]}, "unknown_op"],
		[{"t": "op", "id": 2, "op": "grant_once", "args": ["x", {"id": "crystal", "count": 999}]}, "unknown_op"],
		[{"t": "op", "id": 3, "op": "equip", "args": ["0"]}, "bad_args"],
		[{"t": "op", "id": 4, "op": "equip", "args": []}, "bad_args"],
		[{"t": "op", "op": "sort_bag", "args": []}, "no_id"],
		[{"t": "nope"}, "unknown_type"],
	]
	for pair in cases:
		var reply := server.handle(session, pair[0])
		if reply.get("reason") != pair[1]:
			_fail("%s → %s 이어야 하는데 %s" % [pair[0], pair[1], reply])
	var ok := server.handle(session, {"t": "op", "id": 9, "op": "sort_bag", "args": []})
	var stale := server.handle(session, {"t": "op", "id": 5, "op": "sort_bag", "args": []})
	if ok.get("t") != "result" or stale.get("reason") != "stale":
		_fail("지난 번호를 막지 않는다: %s · %s" % [ok, stale])
	if server.handle(session, "문자열").get("reason") != "bad_message":
		_fail("사전이 아닌 메시지를 받았다")


## 실제 웹소켓으로 hello → welcome → op → result
func _case_socket() -> void:
	var server := GameServer.new(AccountStore.new(DIR))
	if server.listen(0) != OK:
		_fail("서버가 못 떴다")
		return
	var client := WebSocketPeer.new()
	client.inbound_buffer_size = GameServer.BUFFER
	client.connect_to_url("ws://127.0.0.1:%d" % server.port())
	var welcome := _exchange(server, client, {"t": "hello"})
	if welcome.get("t") != "welcome":
		_fail("웹소켓으로 welcome 이 안 왔다: %s" % welcome)
	else:
		var result := _exchange(server, client, {"t": "op", "id": 1, "op": "sort_bag", "args": []})
		if result.get("t") != "result" or int(result.get("id", 0)) != 1:
			_fail("웹소켓으로 result 가 안 왔다: %s" % result)
	client.close()
	server.stop()


func _exchange(server: GameServer, client: WebSocketPeer, message: Dictionary) -> Dictionary:
	var sent := false
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not sent:
				client.send_text(JSON.stringify(message))
				sent = true
			elif client.get_available_packet_count() > 0:
				var parsed = JSON.parse_string(client.get_packet().get_string_from_utf8())
				return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
		OS.delay_msec(5)
	return {"t": "timeout"}
