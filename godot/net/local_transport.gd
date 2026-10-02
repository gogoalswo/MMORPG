class_name LocalTransport
extends Transport

## 서버 없이 World 를 이 자리에서 돌린다. 혼자 노는 모드다.
##
## 웹 클라이언트의 net/local/localServer.ts 에 해당하지만 훨씬 얇다 —
## 저쪽은 TS 서버 코드를 브라우저에서 그대로 돌리려고 node:sqlite 같은
## 대체물을 다섯 개 끼웠는데, 여기는 같은 언어라 그냥 부르면 된다.

const MY_ID := "me"

var _world: World
## 서버에 붙었으면 장부는 여기로 간다 (docs/features/server.md 3단계). null 이면 혼자 논다
var _server: ServerLedger = null


## 서버 주소 — 명령줄 `-- --server=ws://…` 이 먼저, 없으면 프로젝트 설정 `mmorpg/server_url`.
## **비어 있으면 서버 없이 논다** — GitHub Pages 화면은 서버가 없어서 비워 둔다
static func server_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			return arg.trim_prefix("--server=")
	return str(ProjectSettings.get_setting("mmorpg/server_url", ""))


func open(zone_id: String) -> void:
	_world = World.new()
	_world.open(zone_id)
	_world.join(MY_ID)
	# 저장한 것이 있으면 그 자리에서 이어서 시작한다 (서버에 붙으면 장부 칸은 welcome 이 덮는다 —
	# 자리·설정만 여기서 온다)
	var restored := _world.restore(MY_ID)
	if restored:
		print("저장에서 이어서 시작: %s" % _world.zone_id)
	# 시작 화면에서 정한 이름 — 비었으면 저장에 있던 것을 그대로 쓴다 (docs/features/play-mode.md "이름")
	if not PlayMode.player_name.is_empty():
		_world.set_name(MY_ID, PlayMode.player_name)
	# **테스트 모드는 서버에 안 붙는다** — 치트가 기기에서 장부를 바꾸는데 서버 답이 덮어 버린다
	var url := server_url()
	if not url.is_empty() and PlayMode.current == PlayMode.NORMAL:
		_attach(url)
		return  # 시작 장비·첫 선물은 서버가 계정을 만들 때 준다
	if not restored:
		# 새 캐릭터 — 일반 등급 무기·갑옷을 끼워서 시작한다 (2026-09-26 요청)
		_world.grant_starter_gear(MY_ID)
	# 첫 선물(크리스탈 30개) — 한 번만. 받았다는 표시가 저장에 남는다 (`Ledger.welcome_gifts`)
	for gift in Ledger.welcome_gifts():
		_world.grant_once(MY_ID, str(gift[0]), gift[1])


func _attach(url: String) -> void:
	_server = ServerLedger.new(url)
	# 이름을 hello 에 싣는다 — 서버가 같은 규칙(`Names`)으로 다시 거르고 확정한 이름을 welcome 으로 준다
	_server.name = str(_world.snapshot().get("players", {}).get(MY_ID, {}).get("name", ""))
	_server.welcomed.connect(func(ledger: Dictionary) -> void:
		_world.apply_ledger(MY_ID, ledger, [])
		_world.set_name(MY_ID, _server.name))
	_server.replied.connect(func(ledger: Dictionary, events: Array) -> void:
		_world.apply_ledger(MY_ID, ledger, events))
	_server.failed.connect(func(reason: String) -> void:
		if reason == "chat_limit":
			event.emit(&"chat", {"system": true, "text": "말을 너무 빨리 보냈습니다 — 잠시 뒤에 다시"})
			return
		push_warning("서버가 요청을 거절했다: %s" % reason))
	# 채팅은 World 를 거치지 않는다 — 장부가 아니라 사람끼리 오가는 말이다
	_server.chat.connect(func(line: Dictionary) -> void:
		event.emit(&"chat", line))
	_server.ranked.connect(func(board: Dictionary) -> void:
		event.emit(&"rank", board))
	_server.sandbag_ranked.connect(func(board: Dictionary) -> void:
		event.emit(&"sandbagRank", board))
	_server.purchase_done.connect(func(result: Dictionary) -> void:
		event.emit(&"purchase", result))
	_world.remote = _server
	# 지금 존을 알린다 — 이 뒤로는 `World.open` 이 존을 옮길 때마다 알린다
	_server.request(&"enter", [_world.zone_id])
	print("서버에 붙는다: %s" % url)


func online() -> bool:
	return _server != null


func send(message: StringName, payload: Dictionary) -> void:
	if _world == null:
		return
	if message == &"chat":
		if _server != null:
			_server.say(str(payload.get("text", "")))
		return
	# 결제 영수증 — 서버만 확인한다. 서버가 없으면 살 수 없다
	if message == &"purchase":
		if _server != null:
			_server.purchase(str(payload.get("product", "")), str(payload.get("token", "")))
		return
	# 샌드백 랭킹전 순위 — 서버에 붙어 있으면 서버의 표, 아니면 **혼자라 나 하나**의 표 (docs/features/sandbag.md)
	if message == &"sandbagRank":
		if _server != null:
			_server.ask_sandbag_rank()
		else:
			event.emit(&"sandbagRank", _local_sandbag_board())
		return
	# 랭킹도 World 를 거치지 않는다 — 서버만 가진 표다
	if message == &"rank":
		if _server != null:
			_server.ask_rank()
		return
	match message:
		&"input":
			_world.input_move(
				MY_ID,
				int(payload.get("seq", 0)),
				float(payload.get("dx", 0.0)),
				float(payload.get("dz", 0.0)),
				float(payload.get("dt", 0.0)),
			)
		&"attack":
			_world.attack(MY_ID)
		&"strike":
			_world.strike(MY_ID, str(payload.get("id", "")))
		&"revive":
			_world.revive(MY_ID)
		&"autoHunt":
			_world.set_auto(MY_ID, bool(payload.get("on", false)))
		&"travel":
			_world.travel(MY_ID, str(payload.get("zone", "")))
		&"npc":
			_world.npc_open(MY_ID, str(payload.get("name", "")))
		&"learnPassive":
			_world.learn_passive(MY_ID, str(payload.get("id", "")))
		&"learnSkill":
			_world.learn_skill(MY_ID, str(payload.get("skill", "")))
		&"setSkillBar":
			_world.set_skill_bar(MY_ID, payload.get("bar", []))
		&"invincible":
			_world.set_invincible(MY_ID, bool(payload.get("on", false)))
		&"debugGauntlets":
			_world.debug_gauntlets(MY_ID)
		&"debugFillBag":
			_world.debug_fill_bag(MY_ID)
		&"testKit":
			_world.grant_test_kit(MY_ID)
		&"testLevel":
			_world.grant_test_level(MY_ID)
		&"testSkills":
			_world.grant_test_skills(MY_ID)
		&"debugCrystals":
			_world.debug_crystals(MY_ID, int(payload.get("count", 30)), str(payload.get("id", "")))
		&"debugLevel":
			_world.debug_level(MY_ID, int(payload.get("level", 1)))
		&"debugGear":
			_world.debug_gear(
				MY_ID,
				int(payload.get("level", 1)),
				int(payload.get("grade", 1)),
				int(payload.get("enhance", 0)),
			)
		&"testSwitch":
			_world.set_test_switch(str(payload.get("name", "")), bool(payload.get("on", false)))
		&"skill":
			_world.cast(MY_ID, str(payload.get("skill", "")))
		&"equip":
			_world.equip(MY_ID, int(payload.get("index", -1)))
		&"unequip":
			_world.unequip(MY_ID, str(payload.get("slot", "")))
		&"sortBag":
			_world.sort_bag(MY_ID)
		&"feedUpgrade":
			_world.feed_upgrade(
				MY_ID,
				str(payload.get("skill", "")),
				int(payload.get("slot", -1)),
			)
		&"fitnessUp":
			_world.fitness_up(MY_ID, str(payload.get("kind", "")), bool(payload.get("auto", false)))
		&"codexRegister":
			_world.codex_register(
				MY_ID, str(payload.get("id", "")), int(payload.get("enhance", -1)), int(payload.get("index", -1))
			)
		&"debugProtein":
			_world.debug_protein(MY_ID)
		&"debugSkillExp":
			_world.debug_skill_exp(MY_ID)
		&"debugLearnAll":
			_world.debug_learn_all(MY_ID)
		&"debugUpgradeAll":
			_world.debug_upgrade_all(MY_ID, int(payload.get("slot", 0)))
		&"debugResetUpgrades":
			_world.debug_reset_upgrades(MY_ID)
		&"useCrystal":
			_world.use_crystal(MY_ID, str(payload.get("where", "")), payload.get("key", -1), int(payload.get("tier", 2)))
		&"npcBuy":
			_world.npc_buy(MY_ID, str(payload.get("item", "")))
		&"npcSell":
			_world.npc_sell(MY_ID, int(payload.get("index", -1)))
		&"enhanceItem":
			_world.enhance_item(MY_ID, str(payload.get("where", "")), payload.get("key", -1))
		&"enhanceMany":
			_world.enhance_many(MY_ID, payload.get("indices", []), int(payload.get("cap", -1)))
		&"npcEnhance":
			_world.npc_enhance(MY_ID, int(payload.get("index", -1)))
		&"save":
			_world.save(MY_ID)
		&"potion":
			_world.drink_potion(MY_ID)
		&"potionPct":
			_world.set_potion_pct(MY_ID, int(payload.get("pct", 0)))
		&"autoPriority":
			_world.set_auto_priority(MY_ID, payload.get("ids", []))
		_:
			push_warning("모르는 메시지: %s" % message)


func snapshot() -> Dictionary:
	return _world.snapshot() if _world != null else {}


func my_id() -> String:
	return MY_ID


func _process(delta: float) -> void:
	if _world == null:
		return
	if _server != null:
		_server.poll()
	_world.step(delta)
	# 판정이 낸 일들을 화면으로 흘린다. 서버를 붙이면 이 자리가 소켓이 된다
	for e in _world.drain_events():
		event.emit(StringName(e.get("type", "?")), e)


## 탭을 닫거나 앱을 내릴 때 한 번 더 남긴다. 주기 저장(10초) 사이에 잃는 것을 줄인다
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _world != null:
			_world.save(MY_ID)


## 서버 없이 노는 판의 샌드백 순위 — 나 하나뿐이다. 이번 주 기록이 있으면 1위, 없으면 순위 없음.
## 모양은 서버 답(`LedgerServer._sandbag_rank`)과 같다 — 창이 둘을 가리지 않게
func _local_sandbag_board() -> Dictionary:
	var me: Dictionary = _world.snapshot().get("players", {}).get(MY_ID, {})
	var week := _world.sandbag_week()
	var mine: Dictionary = me.get("sandbag", {})
	var best := int(mine.get("best", 0)) if int(mine.get("week", -1)) == week else 0
	var top: Array = []
	if best > 0:
		top.append({"rank": 1, "name": str(me.get("name", "")), "best": best})
	return {
		"t": "sandbagRank", "top": top, "me": {"rank": 1 if best > 0 else 0, "best": best},
		"total": top.size(), "week": week, "ends_at": Sandbag.week_end(week), "local": true,
	}
