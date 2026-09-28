class_name LedgerServer
extends RefCounted

## 서버의 판정 — **메시지 하나를 받아 답을 돌려준다.** 소켓은 모른다 (`server_main.gd` 가 맡는다).
## 그래서 테스트가 소켓 없이도 이 파일을 통째로 돌려 볼 수 있다 (docs/features/server.md).
##
## 주고받는 것 (JSON 한 줄):
##   → {t: "hello", token?}               ← {t: "welcome", token, ledger, last_req}
##   → {t: "op", id, op, args}            ← {t: "result", id, ledger, events}
##                                        ← {t: "error", id?, reason}
## 판정은 `Ledger`(`world/ledger.gd`) — 기기와 **같은 파일**이다.

## 기기가 부를 수 있는 장부 요청과 인자 모양. 여기 없는 것은 받지 않는다.
##   s = 글자 · i = 정수 · k = 가방 번호(정수) 또는 슬롯(글자) · a = 정수 목록 · t = 처치 `{kind, zone}`
## `kill` 은 **종류와 존만** 받는다 — 레벨·경험치·보스 여부는 `Ledger.kill` 이 표에서 찾는다.
## 그 처치가 정말 있었는지(스폰 명부 · 최소 처치 시간)는 4단계에서 본다 — 그때까지는 믿는다.
## `grant_once` 는 끝까지 없다 — 기기가 "이걸 줘" 라고 할 수 있게 되면 끝이다
const OPS := {
	"enter": "s",
	"kill": "t",
	"learn_skill": "s",
	"feed_upgrade": "si",
	"equip": "i",
	"unequip": "s",
	"sort_bag": "",
	"use_crystal": "sk",
	"buy": "s",
	"sell": "i",
	"enhance": "sk",
	"enhance_many": "ai",
}

var store: AccountStore
var ledger := Ledger.new()
## 한 번이라도 들어온 계정은 **메모리에 하나만** 둔다 (id → 계정). 같은 토큰으로 두 번 붙어도
## 두 연결이 같은 사전을 만진다 — 따로 읽으면 양쪽에서 같은 물건을 팔아 복사할 수 있다
var _accounts := {}
## 계정마다 지금 사냥 중인 존 — `{zone, entered_at, roster, killed: {몬스터 id: 잡은 시각}}`.
## 메모리에만 둔다 (서버를 다시 켜면 다음 `enter` 부터 다시 센다)
var _hunts := {}
## 서버 시계(ms). 테스트는 바꿔 끼워 시간을 앞으로 돌린다
var clock: Callable = func() -> int: return Time.get_ticks_msec()


func _init(account_store: AccountStore) -> void:
	store = account_store


## 연결 하나의 상태는 `session` 사전에 둔다 (`server_main` 이 연결마다 하나씩 쥔다)
func handle(session: Dictionary, message: Variant) -> Dictionary:
	if typeof(message) != TYPE_DICTIONARY:
		return _error(null, "bad_message")
	match str(message.get("t", "")):
		"hello":
			return _hello(session, message)
		"op":
			return _op(session, message)
	return _error(message.get("id"), "unknown_type")


## 토큰이 맞으면 그 계정, 없거나 틀리면 **새 게스트 계정**을 만든다
func _hello(session: Dictionary, message: Dictionary) -> Dictionary:
	var account := store.find(str(message.get("token", "")))
	if account.is_empty():
		var fresh := Ledger.fresh(World.DEFAULT_JOB)
		ledger.grant_starter_gear(fresh)
		for gift in Ledger.welcome_gifts():
			ledger.grant_once(fresh, str(gift[0]), gift[1])
		ledger.take_events()
		account = store.create(fresh)
		_accounts[account.id] = account
	else:
		account = _accounts.get_or_add(account.id, account)
	session["account"] = account
	var reply := {
		"t": "welcome",
		"ledger": Ledger.view(account.ledger),
		"last_req": int(account.get("last_req", 0)),
	}
	if account.has("token"):
		reply["token"] = account.token  # 새로 만든 계정만 — 기기가 받아 둔다
		account.erase("token")
	return reply


func _op(session: Dictionary, message: Dictionary) -> Dictionary:
	var id = message.get("id")
	var account: Dictionary = session.get("account", {})
	if account.is_empty():
		return _error(id, "no_hello")
	if typeof(id) != TYPE_FLOAT and typeof(id) != TYPE_INT:
		return _error(null, "no_id")
	var req := int(id)
	# **같은 요청을 두 번 받으면 두 번 판정하지 않는다** — 끊겼다 다시 보낸 것이다.
	# 번호는 계정마다 늘기만 한다 (기기는 welcome 의 last_req 다음부터 쓴다)
	var last := int(account.get("last_req", 0))
	if req == last and account.has("last_reply"):
		return account.last_reply
	if req <= last:
		return _error(req, "stale")

	var op := str(message.get("op", ""))
	if not OPS.has(op):
		return _error(req, "unknown_op")
	var args = _args(OPS[op], message.get("args", []))
	if args == null:
		return _error(req, "bad_args")

	match op:
		"enter":
			var locked := _enter(account, str(args[0]))
			if not locked.is_empty():
				return _error(req, locked)
		"kill":
			var why := _check_kill(account, args[0])
			if not why.is_empty():
				# **이상치는 기록만 한다** — 제재는 사람이 한다. 보상만 안 준다
				print("처치 거절 %s %s: %s" % [account.id, why, JSON.stringify(args[0])])
				return _error(req, why)
			ledger.callv(op, [account.ledger] + args)
		_:
			ledger.callv(op, [account.ledger] + args)
	var reply := {
		"t": "result", "id": req,
		"ledger": Ledger.view(account.ledger),
		"events": ledger.take_events(),
	}.duplicate(true)  # 이벤트가 가방을 가리킨다 — 남겨 둘 답은 지금 값으로 굳힌다
	account["last_req"] = req
	account["last_reply"] = reply
	if not store.write(account):
		return _error(req, "store_failed")
	return reply


## JSON 은 숫자를 전부 실수로 준다 — 모양대로 바꾸고, 안 맞으면 null
func _args(shape: String, raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY or raw.size() != shape.length():
		return null
	var out: Array = []
	for i in shape.length():
		var value = raw[i]
		match shape[i]:
			"s":
				if typeof(value) != TYPE_STRING:
					return null
				out.append(value)
			"i":
				if not _is_number(value):
					return null
				out.append(int(value))
			"k":
				if typeof(value) == TYPE_STRING:
					out.append(value)
				elif _is_number(value):
					out.append(int(value))
				else:
					return null
			"t":
				if typeof(value) != TYPE_DICTIONARY:
					return null
				out.append({
					"kind": str(value.get("kind", "")), "zone": str(value.get("zone", "")),
					"id": str(value.get("id", "")),
				})
			"a":
				if typeof(value) != TYPE_ARRAY:
					return null
				var list: Array = []
				for each in value:
					if not _is_number(each):
						return null
					list.append(int(each))
				out.append(list)
	return out


## 존에 들어왔다. **게임에 있는 입장 규칙만 본다** — 전직 시험은 바로 다음 단계이고 레벨이 될 때만.
## 일반 사냥터·던전은 막는 규칙이 없다 (`World.travel`). 들어올 때마다 명단을 새로 센다 —
## 기기도 존을 다시 열면 몬스터를 새로 놓는다
func _enter(account: Dictionary, zone: String) -> String:
	if not GameData.zones().get("zones", {}).has(zone):
		return "no_zone"
	var tier := Skills.job_tier_of_zone(zone)
	if tier > 0:
		var p: Dictionary = account.ledger
		if tier != int(p.get("job_tier", 0)) + 1 or int(p.level) < int(Skills.job_advance(tier).get("level", 0)):
			return "zone_locked"
	_hunts[account.id] = {"zone": zone, "entered_at": int(clock.call()), "roster": World.roster(zone), "killed": {}}
	return ""


## 처치 보고를 대 본다 (docs/features/server.md "처치 보고를 어떻게 믿나"). 되면 빈 글자
func _check_kill(account: Dictionary, target: Dictionary) -> String:
	var hunt: Dictionary = _hunts.get(account.id, {})
	if hunt.is_empty():
		return "no_zone"
	if str(target.zone) != str(hunt.zone):
		return "wrong_zone"
	var entry: Dictionary = hunt.roster.get(str(target.id), {})
	if entry.is_empty() or str(entry.kind) != str(target.kind):
		return "not_in_roster"
	var now := int(clock.call())
	var available := float(hunt.entered_at)
	if hunt.killed.has(target.id):
		available = float(hunt.killed[target.id]) + float(entry.respawn_ms)
		if now + KillCheck.SLACK_MS < available:
			return "not_respawned"
	var kind: Dictionary = GameData.load_table("monsters").get("kinds", {}).get(str(target.kind), {})
	if not KillCheck.allows(now - available, KillCheck.min_ms(account.ledger, kind)):
		return "too_fast"
	hunt.killed[target.id] = now
	return ""


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _error(id: Variant, reason: String) -> Dictionary:
	var out := {"t": "error", "reason": reason}
	if id != null:
		out["id"] = id
	return out
