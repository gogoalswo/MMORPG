class_name LocalTransport
extends Transport

## 서버 없이 World 를 이 자리에서 돌린다. 혼자 노는 모드다.
##
## 웹 클라이언트의 net/local/localServer.ts 에 해당하지만 훨씬 얇다 —
## 저쪽은 TS 서버 코드를 브라우저에서 그대로 돌리려고 node:sqlite 같은
## 대체물을 다섯 개 끼웠는데, 여기는 같은 언어라 그냥 부르면 된다.

const MY_ID := "me"

var _world: World


func open(zone_id: String) -> void:
	_world = World.new()
	_world.open(zone_id)
	_world.join(MY_ID)
	# 저장한 것이 있으면 그 자리에서 이어서 시작한다
	if _world.restore(MY_ID):
		print("저장에서 이어서 시작: %s" % _world.zone_id)


func send(message: StringName, payload: Dictionary) -> void:
	if _world == null:
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
		&"revive":
			_world.revive(MY_ID)
		&"autoHunt":
			_world.set_auto(MY_ID, bool(payload.get("on", false)))
		&"travel":
			_world.travel(MY_ID, str(payload.get("zone", "")))
		&"npc":
			_world.npc_open(MY_ID, str(payload.get("name", "")))
		&"learnSkill":
			_world.learn_skill(MY_ID, str(payload.get("skill", "")))
		&"setSkillBar":
			_world.set_skill_bar(MY_ID, payload.get("bar", []))
		&"invincible":
			_world.set_invincible(MY_ID, bool(payload.get("on", false)))
		&"debugGauntlets":
			_world.debug_gauntlets(MY_ID)
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
		&"npcBuy":
			_world.npc_buy(MY_ID, str(payload.get("item", "")))
		&"npcSell":
			_world.npc_sell(MY_ID, int(payload.get("index", -1)))
		&"npcEnhance":
			_world.npc_enhance(MY_ID, int(payload.get("index", -1)))
		&"save":
			_world.save(MY_ID)
		_:
			push_warning("모르는 메시지: %s" % message)


func snapshot() -> Dictionary:
	return _world.snapshot() if _world != null else {}


func my_id() -> String:
	return MY_ID


func _process(delta: float) -> void:
	if _world == null:
		return
	_world.step(delta)
	# 판정이 낸 일들을 화면으로 흘린다. 서버를 붙이면 이 자리가 소켓이 된다
	for e in _world.drain_events():
		event.emit(StringName(e.get("type", "?")), e)


## 탭을 닫거나 앱을 내릴 때 한 번 더 남긴다. 주기 저장(10초) 사이에 잃는 것을 줄인다
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _world != null:
			_world.save(MY_ID)
