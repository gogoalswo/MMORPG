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
	_case_roster_matches_spawn()
	_case_known_keys()
	_case_kill_checks()
	_case_trial_check()
	_case_chat()
	_case_rank()
	_case_purchase()
	_case_google_verifier()
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
	var orders := DirAccess.open(path.path_join("orders"))
	if orders != null:
		for name in orders.get_files():
			orders.remove(name)
		DirAccess.remove_absolute(path.path_join("orders"))
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
	# 첫 스킬을 배운 채 시작한다 — 보이는 스킬이 없는 직업(격투가, 2026-09-29)은 빈 채
	if ledger.skills.size() != mini(1, Skills.for_job(str(ledger.job)).size()):
		_fail("새 계정이 첫 스킬을 안 배웠다")

	# 벗기 → 팔기. 판 값은 다시 보내도 한 번만 들어온다
	var off := server.handle(session, {"t": "op", "id": 1, "op": "unequip", "args": ["weapon"]})
	if off.get("t") != "result" or _gear(off.ledger.bag) < 0:
		_fail("unequip 이 가방에 안 넣었다: %s" % off)
		return
	var sold := server.handle(session, {"t": "op", "id": 2, "op": "sell", "args": [_gear(off.ledger.bag)]})
	var gold := int(sold.ledger.gold)
	if gold <= 0 or _gear(sold.ledger.bag) >= 0:
		_fail("sell 이 골드를 안 줬다: %s" % sold.ledger)
	var again := server.handle(session, {"t": "op", "id": 2, "op": "sell", "args": [_gear(off.ledger.bag)]})
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
	var armor := server.handle(session, {"t": "op", "id": 3, "op": "unequip", "args": ["armor"]})
	if JSON.stringify(sold) != kept:
		_fail("보낸 답(이벤트)이 나중 변경을 따라 바뀌었다")

	# 같은 토큰으로 **두 번 붙어도 장부는 하나다** — 한쪽에서 판 것을 다른 쪽이 또 못 판다
	var twin := {}
	server.handle(twin, {"t": "hello", "token": welcome.token})
	var first := server.handle(session, {"t": "op", "id": 4, "op": "sell", "args": [_gear(armor.ledger.bag)]})
	var second := server.handle(twin, {"t": "op", "id": 5, "op": "sell", "args": [_gear(armor.ledger.bag)]})
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
		[{"t": "op", "id": 1, "op": "kill", "args": ["wolf"]}, "bad_args"],
		[{"t": "op", "id": 2, "op": "grant_once", "args": ["x", {"id": "crystal", "count": 999}]}, "unknown_op"],
		[{"t": "op", "id": 3, "op": "equip", "args": ["0"]}, "bad_args"],
		[{"t": "op", "id": 4, "op": "equip", "args": []}, "bad_args"],
		# 습득 부위·옵션은 글자 목록이다 — 숫자가 섞이면 거절
		[{"t": "op", "id": 5, "op": "set_loot_skip_slots", "args": [["weapon", 1]]}, "bad_args"],
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
	var slots := server.handle(session, {"t": "op", "id": 10, "op": "set_loot_skip_slots", "args": [["ring", "weapon"]]})
	if slots.get("t") != "result" or slots.get("ledger", {}).get("loot_skip_slots") != ["weapon", "ring"]:
		_fail("습득 부위 요청이 장부에 안 들어갔다: %s" % [slots])
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


## 가방에서 첫 장비 칸 번호 (재료 — 첫 선물 크리스탈 — 는 건너뛴다). 없으면 -1
func _gear(bag: Array) -> int:
	for i in bag.size():
		if not Items.is_material(str(bag[i].get("id", ""))):
			return i
	return -1


## 서버의 명단(`World.roster`)과 기기가 실제로 놓는 몬스터는 **id·종류가 같아야 한다** — 모든 존
func _case_roster_matches_spawn() -> void:
	var w := World.new()
	for zone in GameData.zones().get("zones", {}):
		w.open(str(zone))
		var roster := World.roster(str(zone))
		if roster.size() != w._monsters.size():
			_fail("%s 명단 %d마리 · 실제 %d마리" % [zone, roster.size(), w._monsters.size()])
			continue
		for monster in w._monsters:
			var entry: Dictionary = roster.get(str(monster.id), {})
			if str(entry.get("kind", "")) != str(monster.kind) or float(entry.get("respawn_ms", -1)) != float(monster.respawn_ms):
				_fail("%s 의 %s 가 명단과 다르다: %s" % [zone, monster.id, entry])
				break


## 스킬·강화 표에 **처치 검증이 모르는 칸**이 생기면 멈춘다 — 피해를 올리는 효과면
## `KillCheck.min_ms` 가 모르는 채로 정상 처치를 거절한다
func _case_known_keys() -> void:
	for skill in Skills.all().values():
		for key in skill:
			if not (key in KillCheck.KNOWN_SKILL_KEYS):
				_fail("스킬 칸 %s 를 KillCheck 가 모른다 — 피해와 관계있으면 min_ms 에 넣고 KNOWN_SKILL_KEYS 에 적는다" % key)
	for upgrade in GameData.load_table("skills").get("upgrades", []):
		for key in upgrade:
			if not (key in KillCheck.KNOWN_UPGRADE_KEYS):
				_fail("강화 칸 %s 를 KillCheck 가 모른다 — 피해와 관계있으면 min_ms 에 넣고 KNOWN_UPGRADE_KEYS 에 적는다" % key)


## 입장 · 명단 · 되살아나기 · 최소 처치 시간 — 서버 시계는 가짜로 돌린다
func _case_kill_checks() -> void:
	var server := LedgerServer.new(AccountStore.new(DIR))
	var now := [100000]
	server.clock = func() -> int: return now[0]
	var session := {}
	server.handle(session, {"t": "hello"})
	var ledger: Dictionary = session.account.ledger
	var id := [100]
	var send := func(op: String, args: Array) -> Dictionary:
		id[0] += 1
		return server.handle(session, {"t": "op", "id": id[0], "op": op, "args": args})

	if send.call("kill", [{"kind": "x", "zone": "meadow", "id": "x_0"}]).get("reason") != "no_zone":
		_fail("존에 들기 전의 처치를 받았다")
	if send.call("enter", ["없는존"]).get("reason") != "no_zone":
		_fail("없는 존에 들어갔다")

	# 새 캐릭터가 **바로는 못 잡는** 몬스터가 있는 사냥터를 고른다
	var pick := {}
	for zone in GameData.zones().get("zones", {}):
		for mob_id in World.roster(str(zone)):
			var kind_id := str(World.roster(str(zone))[mob_id].kind)
			var kind: Dictionary = GameData.load_table("monsters").kinds[kind_id]
			var need := KillCheck.min_ms(ledger, kind)
			if need * KillCheck.HEADROOM > KillCheck.SLACK_MS + 1000:
				pick = {"zone": str(zone), "id": str(mob_id), "kind": kind_id, "need": need}
				break
		if not pick.is_empty():
			break
	if pick.is_empty():
		_fail("바로는 못 잡는 몬스터를 못 찾았다 — 검사를 못 한다")
		return
	if send.call("enter", [pick.zone]).get("t") != "result":
		_fail("사냥터 %s 에 못 들어갔다" % pick.zone)
		return
	var target := {"kind": pick.kind, "zone": pick.zone, "id": pick.id}
	if send.call("kill", [target]).get("reason") != "too_fast":
		_fail("들어오자마자 잡은 %s 를 받았다 (최소 %dms)" % [pick.id, int(pick.need)])
	if send.call("kill", [{"kind": pick.kind, "zone": "meadow", "id": pick.id}]).get("reason") != "wrong_zone":
		_fail("다른 존의 처치를 받았다")
	if send.call("kill", [{"kind": pick.kind, "zone": pick.zone, "id": "없는_0"}]).get("reason") != "not_in_roster":
		_fail("명단에 없는 id 를 받았다")
	if send.call("kill", [{"kind": "slime", "zone": pick.zone, "id": pick.id}]).get("reason") != "not_in_roster":
		_fail("종류가 틀린 처치를 받았다")

	var exp_before := int(ledger.exp)
	now[0] += int(pick.need) + 1
	var ok: Dictionary = send.call("kill", [target])
	if ok.get("t") != "result" or int(ok.ledger.exp) <= exp_before and int(ok.ledger.level) <= 1:
		_fail("시간이 충분히 지난 처치를 거절했다: %s" % ok.get("reason", ok.get("t")))
	now[0] += 10
	if send.call("kill", [target]).get("reason") != "not_respawned":
		_fail("되살아나기 전에 또 잡은 것을 받았다")


## 시련의 탑 — 서버가 **제가 인정한 처치**를 센다. 모자라면 · 시간이 지나서 잡았으면 · 두 번째면 거절
func _case_trial_check() -> void:
	var server := LedgerServer.new(AccountStore.new(DIR))
	var now := [500000]
	server.clock = func() -> int: return now[0]
	var session := {}
	server.handle(session, {"t": "hello"})
	var ledger: Dictionary = session.account.ledger
	ledger.level = 30
	var id := [1000]
	var send := func(op: String, args: Array) -> Dictionary:
		id[0] += 1
		return server.handle(session, {"t": "op", "id": id[0], "op": op, "args": args})
	var zone := "trial_02"
	var stage := GameData.dungeon_stage(zone)
	var roster := World.roster(zone)
	var ids: Array = roster.keys()
	var kind: Dictionary = GameData.load_table("monsters").kinds[str(roster[ids[0]].kind)]
	# 최소 처치 시간이 지난 뒤에 잡는다 — 들어온 때부터 재므로 한 번만 기다리면 된다
	var wait := int(KillCheck.min_ms(ledger, kind) * KillCheck.HEADROOM) + 1
	if wait >= int(stage.seconds) * 1000:
		_fail("Lv.30 이 시련 2단계 몬스터를 30초 안에 못 잡는다고 친다 (%dms) — 검사를 못 한다" % wait)
		return

	if send.call("trial_clear", [zone]).get("reason") != "wrong_zone":
		_fail("들어오지도 않은 시련을 통과시켰다")
	send.call("enter", [zone])
	now[0] += wait
	for i in int(stage.kills) - 1:
		send.call("kill", [{"kind": str(roster[ids[i]].kind), "zone": zone, "id": str(ids[i])}])
	if send.call("trial_clear", [zone]).get("reason") != "too_few":
		_fail("%d마리만 잡았는데 통과시켰다" % (int(stage.kills) - 1))
	var last := int(stage.kills) - 1
	send.call("kill", [{"kind": str(roster[ids[last]].kind), "zone": zone, "id": str(ids[last])}])
	var ok: Dictionary = send.call("trial_clear", [zone])
	var reward: Array = ok.get("events", []).filter(func(e): return str(e.get("type", "")) == "trialReward")
	if ok.get("t") != "result" or reward.is_empty() or int(reward[0].crystal) != int(stage.crystals):
		_fail("7마리를 잡았는데 통과를 거절했다: %s" % ok.get("reason", ok))
	if send.call("trial_clear", [zone]).get("reason") != "claimed":
		_fail("한 번 들어와 두 번 받았다")

	# 같은 날 다시 들어오면 막는다 — 하루 한 번 (dungeons.md "하루 한 번")
	if send.call("enter", [zone]).get("reason") != "daily_used":
		_fail("같은 날 시련에 두 번 들어왔다")
	# 다음 날 다시 들어와 30초가 지난 뒤에 잡은 것은 안 센다
	var tomorrow := float(Time.get_unix_time_from_system()) + 86400.0
	server.ledger.unix_now = func() -> float: return tomorrow
	if send.call("enter", [zone]).get("t") != "result":
		_fail("다음 날인데 시련에 못 들어왔다")
	now[0] += int(stage.seconds) * 1000 + int(KillCheck.SLACK_MS) + 1
	for i in int(stage.kills):
		send.call("kill", [{"kind": str(roster[ids[i]].kind), "zone": zone, "id": str(ids[i])}])
	if send.call("trial_clear", [zone]).get("reason") != "too_few":
		_fail("시간이 지난 뒤 잡은 것으로 통과시켰다")


## 채팅 — 모두에게 뿌리기 · 서버가 붙이는 이름 · 제어 문자 · 도배 막기 · 지난 줄 · 강화 알림
func _case_chat() -> void:
	var server := LedgerServer.new(AccountStore.new(DIR))
	var now := [0]
	server.clock = func() -> int: return now[0]
	if server.handle({}, {"t": "chat", "text": "누구"}).get("reason") != "no_hello":
		_fail("hello 전에 말을 받았다")
	var a := {}
	server.handle(a, {"t": "hello"})
	var name := LedgerServer.display_name(str(a.account.id))

	var reply := server.handle(a, {"t": "chat", "text": "  안녕\n하세요\u0007  ", "from": "운영자"})
	var out := server.take_outbox()
	if not reply.is_empty() or out.size() != 1:
		_fail("말 한 줄이 방송 한 줄이 아니다: 답 %s · 방송 %s" % [reply, out])
		return
	if out[0].text != "안녕하세요" or out[0].from != name:
		_fail("방송된 줄이 %s — 제어 문자를 빼고 이름은 서버가 붙여야 한다(%s)" % [out[0], name])
	if server.handle(a, {"t": "chat", "text": " \n "}).get("reason") != "chat_empty":
		_fail("빈 말을 받았다")
	var long := "가".repeat(LedgerServer.CHAT_MAX_LEN + 50)
	server.handle(a, {"t": "chat", "text": long})
	if str(server.take_outbox()[0].text).length() != LedgerServer.CHAT_MAX_LEN:
		_fail("긴 말을 %d 자에서 안 잘랐다" % LedgerServer.CHAT_MAX_LEN)

	# 연달아 세 번까지 — 네 번째는 막히고, 시간이 지나면 다시 된다
	server.handle(a, {"t": "chat", "text": "셋"})
	if server.handle(a, {"t": "chat", "text": "넷"}).get("reason") != "chat_limit":
		_fail("도배를 안 막았다")
	now[0] += int(LedgerServer.CHAT_REFILL_MS)
	if not server.handle(a, {"t": "chat", "text": "다시"}).is_empty():
		_fail("기다린 뒤에도 막혔다")
	server.take_outbox()

	# 나중에 들어온 사람은 지난 줄을 welcome 으로 받는다
	var b := {}
	var welcome := server.handle(b, {"t": "hello"})
	var texts: Array = welcome.get("chat", []).map(func(l: Dictionary) -> String: return str(l.text))
	if not ("안녕하세요" in texts and "다시" in texts):
		_fail("welcome 에 지난 줄이 없다: %s" % [texts])

	# 강화 알림 — +7 이상 성공만
	server._announce(a.account, [{"type": "enhanceResult", "result": "success", "level": 6, "name": "검"}])
	server._announce(a.account, [{"type": "enhanceResult", "result": "destroy", "level": 9, "name": "검"}])
	if not server.take_outbox().is_empty():
		_fail("+6 성공이나 실패를 알렸다")
	server._announce(a.account, [{"type": "enhanceResult", "result": "success", "level": 7, "name": "흑철 건틀릿"}])
	server._announce(a.account, [{"type": "enhanceBatch", "results": [{"from": 8, "success": 1}, {"from": 3, "success": 2}]}])
	var notices := server.take_outbox()
	if notices.size() != 2 or not bool(notices[0].get("system", false)) \
			or not str(notices[0].text).contains("흑철 건틀릿 +7") or not str(notices[1].text).contains("+9"):
		_fail("강화 알림이 %s" % [notices])


## 랭킹 — 레벨 → 경험치 순 · 내 순위 · 위 50명만 · 서버를 다시 켜도 파일에서 다시 세운다
func _case_rank() -> void:
	var store := AccountStore.new(DIR)
	var server := LedgerServer.new(store)
	if server.handle({}, {"t": "rank"}).get("reason") != "no_hello":
		_fail("hello 전에 랭킹을 줬다")
	var who := {}
	for name in ["a", "b", "c"]:
		who[name] = {}
		server.handle(who[name], {"t": "hello"})
	var set_level := func(name: String, level: int, exp_now: int, req: int) -> void:
		who[name].account.ledger.level = level
		who[name].account.ledger.exp = exp_now
		# 장부 요청이 끝날 때 파일에 남고 순위표가 고쳐진다
		server.handle(who[name], {"t": "op", "id": req, "op": "sort_bag", "args": []})
	set_level.call("a", 90, 5, 1)
	set_level.call("b", 90, 50, 1)
	set_level.call("c", 80, 999, 1)

	var board := server.handle(who.a, {"t": "rank"})
	var names: Array = board.get("top", []).slice(0, 3).map(func(r: Dictionary) -> String: return str(r.name))
	var want: Array = ["b", "a", "c"].map(func(n: String) -> String:
		return LedgerServer.display_name(str(who[n].account.id)))
	if names != want:
		_fail("순위가 %s — 레벨 → 경험치 순이면 %s" % [names, want])
	if int(board.get("me", {}).get("rank", 0)) != 2 or int(board.get("total", 0)) < 3:
		_fail("내 순위가 %s · 전체 %s" % [board.get("me"), board.get("total")])

	# 다시 켠 서버 — 파일만 읽고도 같은 순위다
	var again := LedgerServer.new(store)
	var fresh_session := {}
	again.handle(fresh_session, {"t": "hello"})
	var top: Array = again.handle(fresh_session, {"t": "rank"}).get("top", [])
	if top.size() < 3 or str(top[0].name) != want[0] or int(top[0].level) != 90:
		_fail("다시 켠 서버의 1위가 %s" % [top.slice(0, 1)])

	# 위 50명만 싣는다
	for i in LedgerServer.RANK_TOP:
		again.handle({}, {"t": "hello"})
	var many: Dictionary = again.handle(fresh_session, {"t": "rank"})
	if many.top.size() != LedgerServer.RANK_TOP or int(many.total) <= LedgerServer.RANK_TOP:
		_fail("윗줄 %d명 · 전체 %d명 — 윗줄은 %d명이어야 한다" % [many.top.size(), many.total, LedgerServer.RANK_TOP])


## 가짜 검증기 — 토큰마다 정해 둔 답을 두 번째 poll 에 준다 (검증이 시간이 걸리는 것처럼)
class FakeVerifier extends PurchaseVerifier:
	var answers := {}

	func start(product_id: String, token: String) -> Dictionary:
		return {"product": product_id, "token": token, "done": false, "ok": false, "reason": "", "left": 2}

	func poll(job: Dictionary) -> void:
		job.left -= 1
		if job.left > 0:
			return
		var answer: Dictionary = answers.get(job.token, {"ok": false, "reason": "unknown"})
		job.ok = bool(answer.get("ok", false))
		job.reason = str(answer.get("reason", ""))
		job.order_id = str(answer.get("order_id", ""))
		job.done = true


## 결제 — 영수증 한 장에 한 번 · 다른 계정은 못 쓴다 · 거절 · 다시 켜도 기억한다 · 기기는 다이아를 못 넣는다
func _case_purchase() -> void:
	var store := AccountStore.new(DIR)
	var server := LedgerServer.new(store)
	var a := {}
	var welcome := server.handle(a, {"t": "hello"})
	var buy := func(session: Dictionary, product: String, token: String) -> Dictionary:
		var now := server.handle(session, {"t": "purchase", "product": product, "token": token})
		if not now.is_empty():
			return now
		for i in 5:
			server.poll_jobs()
		for pair in server.take_replies():
			if is_same(pair[0], session):
				return pair[1]
		return {"t": "no_reply"}

	if buy.call(a, "dia_100", "good").get("reason") != "store_off":
		_fail("검증기 없이 결제를 받았다")
	var fake := FakeVerifier.new()
	fake.answers = {"good": {"ok": true, "order_id": "GPA.1"}, "bad": {"ok": false, "reason": "canceled"}}
	server.verifier = fake
	if buy.call(a, "dia_999", "good").get("reason") != "unknown_product":
		_fail("표에 없는 상품을 받았다")

	# 검증 중에 같은 영수증을 또 보내면 기다리게 한다
	server.handle(a, {"t": "purchase", "product": "dia_100", "token": "good"})
	if server.handle(a, {"t": "purchase", "product": "dia_100", "token": "good"}).get("reason") != "in_progress":
		_fail("검증 중인 영수증을 또 걸었다")
	for i in 5:
		server.poll_jobs()
	var got: Array = server.take_replies()
	var want := int(GameData.load_table("store").products.dia_100)
	if got.size() != 1 or got[0][1].get("t") != "purchased" or int(got[0][1].ledger.diamonds) != want:
		_fail("결제가 다이아 %d 을 안 넣었다: %s" % [want, got])
		return

	var again: Dictionary = buy.call(a, "dia_100", "good")
	if not bool(again.get("already", false)) or int(again.ledger.diamonds) != want:
		_fail("같은 영수증으로 또 넣었다: %s" % again.get("ledger", {}).get("diamonds"))
	var b := {}
	server.handle(b, {"t": "hello"})
	if buy.call(b, "dia_100", "good").get("reason") != "order_taken":
		_fail("다른 계정이 남의 영수증으로 받았다")
	var bad: Dictionary = buy.call(a, "dia_100", "bad")
	if bad.get("reason") != "purchase_invalid" or bad.get("detail") != "canceled":
		_fail("취소된 결제가 %s" % bad)

	# 다시 켠 서버도 기억한다 — 파일에 남았다
	var restarted := LedgerServer.new(store)
	restarted.verifier = fake
	var a2 := {}
	restarted.handle(a2, {"t": "hello", "token": welcome.token})
	if int(a2.account.ledger.diamonds) != want:
		_fail("다시 켰더니 다이아가 %s" % a2.account.ledger.diamonds)
	var after := restarted.handle(a2, {"t": "purchase", "product": "dia_100", "token": "good"})
	if not bool(after.get("already", false)):
		_fail("다시 켠 서버가 쓴 영수증을 잊었다: %s" % after)

	# 계정은 썼는데 주문 파일을 쓰기 전에 꺼졌다 — 계정의 표시로 막는다
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join("orders").path_join("good".sha256_text() + ".json"))
	var crashed := restarted.handle(a2, {"t": "purchase", "product": "dia_100", "token": "good"})
	if not bool(crashed.get("already", false)) or int(a2.account.ledger.diamonds) != want:
		_fail("주문 파일이 없을 때 또 넣었다: %s" % crashed)

	for op in LedgerServer.OPS:
		if str(op).contains("diamond") or op == "grant_once":
			_fail("기기가 부를 수 있는 요청에 %s 가 있다 — 다이아는 결제로만 들어온다" % op)


## 구글 검증기 — 테스트 안에 **가짜 구글**(토큰 · 영수증)을 띄우고 실제 HTTP 로 묻는다.
## JWT 서명은 진짜 RSA 키로 만들고 공개키로 풀어 본다
func _case_google_verifier() -> void:
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var verifier := GooglePlayVerifier.new("com.test.game", {
		"client_email": "svc@test.iam.gserviceaccount.com", "private_key": key.save_to_string(false)})

	var jwt := verifier.jwt(1000)
	var parts := jwt.split(".")
	if parts.size() != 3:
		_fail("JWT 가 세 조각이 아니다")
		return
	var claim = JSON.parse_string(_b64url_text(parts[1]))
	if typeof(claim) != TYPE_DICTIONARY or claim.get("scope") != GooglePlayVerifier.SCOPE or int(claim.exp) != 4600:
		_fail("JWT 내용이 %s" % claim)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(("%s.%s" % [parts[0], parts[1]]).to_utf8_buffer())
	if not crypto.verify(HashingContext.HASH_SHA256, hashing.finish(), _b64url_raw(parts[2]), key):
		_fail("JWT 서명이 공개키로 안 풀린다")

	var google := TCPServer.new()
	google.listen(0, "127.0.0.1")
	var base := "http://127.0.0.1:%d" % google.get_local_port()
	verifier.token_url = base + "/token"
	verifier.api_base = base
	var seen := {"token": 0, "auth": true}
	var jobs := [verifier.start("dia_100", "tok-ok"), verifier.start("dia_100", "tok-cancel")]
	var conns: Array = []
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not (jobs[0].done and jobs[1].done):
		for job in jobs:
			verifier.poll(job)
		while google.is_connection_available():
			conns.append({"peer": google.take_connection(), "buf": PackedByteArray()})
		for conn in conns.duplicate():
			var peer: StreamPeerTCP = conn.peer
			peer.poll()
			if peer.get_available_bytes() > 0:
				conn.buf.append_array(peer.get_data(peer.get_available_bytes())[1])
			var text: String = conn.buf.get_string_from_utf8()
			if not text.contains("\r\n\r\n"):
				continue
			var head := text.get_slice("\r\n\r\n", 0)
			var length := 0
			for line in head.split("\r\n"):
				if line.to_lower().begins_with("content-length:"):
					length = int(line.get_slice(":", 1).strip_edges())
			if text.get_slice("\r\n\r\n", 1).to_utf8_buffer().size() < length:
				continue
			var answer := {"error": "not found"}
			var status := "404 Not Found"
			if head.begins_with("POST /token"):
				seen.token += 1
				if text.contains("assertion=") and text.contains("jwt-bearer"):
					answer = {"access_token": "AT1", "expires_in": 3600}
					status = "200 OK"
			elif head.begins_with("GET /androidpublisher/v3/applications/com.test.game/purchases/products/dia_100/tokens/"):
				if not head.contains("Authorization: Bearer AT1"):
					seen.auth = false
				status = "200 OK"
				answer = {"purchaseState": 0, "consumptionState": 0, "orderId": "GPA.7"} \
					if head.contains("/tok-ok ") else {"purchaseState": 1, "orderId": "GPA.8"}
			var body := JSON.stringify(answer).to_utf8_buffer()
			peer.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]).to_utf8_buffer())
			peer.put_data(body)
			conns.erase(conn)
		OS.delay_msec(5)
	google.stop()
	if not (jobs[0].done and jobs[1].done):
		_fail("구글 검증이 안 끝났다: %s · %s" % [jobs[0].get("reason"), jobs[1].get("reason")])
		return
	if not jobs[0].ok or jobs[0].get("order_id") != "GPA.7":
		_fail("결제된 영수증을 안 받았다: %s" % jobs[0].reason)
	if jobs[1].ok or jobs[1].reason != "canceled":
		_fail("취소된 영수증이 %s" % jobs[1].reason)
	if seen.token != 1 or not seen.auth:
		_fail("접근 토큰을 %d번 받았다 · 영수증 요청에 토큰이 %s" % [seen.token, "붙었다" if seen.auth else "안 붙었다"])


static func _b64url_raw(text: String) -> PackedByteArray:
	var plain := text.replace("-", "+").replace("_", "/")
	while plain.length() % 4 != 0:
		plain += "="
	return Marshalls.base64_to_raw(plain)


static func _b64url_text(text: String) -> String:
	return _b64url_raw(text).get_string_from_utf8()
