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
	"learn_passive": "s",
	"feed_upgrade": "si",
	"equip": "i",
	"unequip": "s",
	"sort_bag": "",
	"use_crystal": "sk",
	"buy": "s",
	"sell": "i",
	"enhance": "sk",
	"enhance_many": "ai",
	"trial_clear": "s",
	# 헬스 — 운동 id · 자동(1)이냐 한 번(0)이냐. 확률은 서버가 굴린다
	"fitness_up": "si",
}

var store: AccountStore
var ledger := Ledger.new()
## 한 번이라도 들어온 계정은 **메모리에 하나만** 둔다 (id → 계정). 같은 토큰으로 두 번 붙어도
## 두 연결이 같은 사전을 만진다 — 따로 읽으면 양쪽에서 같은 물건을 팔아 복사할 수 있다
var _accounts := {}
## 계정마다 지금 사냥 중인 존 — `{zone, entered_at, roster, killed: {몬스터 id: 잡은 시각}}`.
## 메모리에만 둔다 (서버를 다시 켜면 다음 `enter` 부터 다시 센다)
var _hunts := {}
## 채팅 — 붙은 사람 모두에게 보낼 것(`take_outbox`), 최근 줄(welcome 에 싣는다), 도배 막기 통
var outbox: Array = []
var _chat_log: Array = []
var _chat_buckets := {}
const CHAT_MAX_LEN := 100
const CHAT_HISTORY := 30
const CHAT_BURST := 3
const CHAT_REFILL_MS := 2000.0
## 이 단계 이상으로 강화에 성공하면 모두에게 알린다
const ANNOUNCE_ENHANCE := 7
## 랭킹 — 계정마다 한 줄 `{id, name, level, exp}`, 줄 세운 것은 장부가 바뀌면 버린다
var _board := {}
var _board_order: Array = []
## 랭킹 창에 싣는 윗줄 수 (내 순위는 따로 싣는다)
const RANK_TOP := 50
## 결제 검증기 — 없으면 결제를 받지 않는다(`store_off`). 실제 서버는 `GooglePlayVerifier`
var verifier: PurchaseVerifier = null
## 검증 중인 결제 `[{session, account, product, key, job}]` 과, 끝난 뒤 **그 연결에만** 보낼 답
var _jobs: Array = []
var _replies: Array = []
## 서버 시계(ms). 테스트는 바꿔 끼워 시간을 앞으로 돌린다
var clock: Callable = func() -> int: return Time.get_ticks_msec()


func _init(account_store: AccountStore) -> void:
	store = account_store
	# 랭킹은 켤 때 계정 파일을 전부 읽어 세운다 — 그 뒤로는 장부가 바뀔 때마다 그 줄만 고친다
	for saved in store.all():
		_board[saved.id] = _board_row(str(saved.id), saved.ledger)
		_board[saved.id].name = name_of(saved)


## 연결 하나의 상태는 `session` 사전에 둔다 (`server_main` 이 연결마다 하나씩 쥔다)
func handle(session: Dictionary, message: Variant) -> Dictionary:
	if typeof(message) != TYPE_DICTIONARY:
		return _error(null, "bad_message")
	match str(message.get("t", "")):
		"hello":
			return _hello(session, message)
		"op":
			return _op(session, message)
		"chat":
			return _chat(session, message)
		"rank":
			return _rank(session)
		"purchase":
			return _purchase(session, message)
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
		_touch_board(account)
	else:
		account = _accounts.get_or_add(account.id, account)
	session["account"] = account
	# 이름 — **같은 규칙(`Names`)으로 다시 거른다.** 안 맞으면 버리고 있던 이름을 그대로 쓴다.
	# 들어올 때마다 새 이름을 주면 바꾼다 (시작 화면에서 고칠 수 있다)
	var wanted := Names.clean(str(message.get("name", "")))
	if Names.valid(wanted) and str(account.get("name", "")) != wanted:
		account["name"] = wanted
		store.write(account)
		_touch_board(account)
	var reply := {
		"t": "welcome",
		"name": name_of(account),
		"ledger": Ledger.view(account.ledger),
		"last_req": int(account.get("last_req", 0)),
		"chat": _chat_log.duplicate(true),  # 들어오기 전에 오간 말 — 채팅창이 비어 있지 않게
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
		"trial_clear":
			var why := _check_trial(account, str(args[0]))
			if not why.is_empty():
				print("시련 거절 %s %s: %s" % [account.id, why, str(args[0])])
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
	_announce(account, reply.events)
	_touch_board(account)
	return reply


## --- 랭킹 (docs/features/server.md 6단계) ---

## 순위 — **레벨 → 경험치**, 둘이 같으면 계정 id 순(늘 같은 순서가 나오게).
## 서버가 가진 값으로만 매긴다 — 기기가 보낸 숫자는 없다
func _rank(session: Dictionary) -> Dictionary:
	var account: Dictionary = session.get("account", {})
	if account.is_empty():
		return _error(null, "no_hello")
	var order := _sorted_board()
	var top: Array = []
	var mine := {}
	for i in order.size():
		var row: Dictionary = order[i]
		if i < RANK_TOP:
			top.append({"rank": i + 1, "name": row.name, "level": row.level, "exp": row.exp})
		if row.id == account.id:
			mine = {"rank": i + 1, "level": row.level, "exp": row.exp}
	return {"t": "rank", "top": top, "me": mine, "total": order.size()}


func _board_row(id: String, p: Dictionary) -> Dictionary:
	return {"id": id, "name": display_name(id), "level": int(p.get("level", 1)), "exp": int(p.get("exp", 0))}


## 장부가 바뀐 계정의 줄만 고친다. 레벨·경험치가 그대로면 다시 줄 세우지 않는다
func _touch_board(account: Dictionary) -> void:
	var row := _board_row(str(account.id), account.ledger)
	row.name = name_of(account)
	var old: Dictionary = _board.get(account.id, {})
	if old.get("level") == row.level and old.get("exp") == row.exp and old.get("name") == row.name:
		return
	_board[account.id] = row
	_board_order.clear()


func _sorted_board() -> Array:
	if _board_order.is_empty() and not _board.is_empty():
		_board_order = _board.values()
		_board_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.level != b.level:
				return a.level > b.level
			if a.exp != b.exp:
				return a.exp > b.exp
			return str(a.id) < str(b.id))
	return _board_order


## --- 채팅 (docs/features/server.md 5단계) ---

## 말 한 줄. 받으면 **붙은 사람 모두에게**(`outbox`) 뿌리고 보낸 사람에게는 따로 답하지 않는다 —
## 제 말도 방송으로 돌아와 채팅창에 적힌다. 이름은 **서버가 붙인다**(`display_name`) — 기기가
## 보낸 이름을 믿으면 남의 이름으로 말할 수 있다
func _chat(session: Dictionary, message: Dictionary) -> Dictionary:
	var account: Dictionary = session.get("account", {})
	if account.is_empty():
		return _error(null, "no_hello")
	var text := _clean(str(message.get("text", "")))
	if text.is_empty():
		return _error(null, "chat_empty")
	# 도배 막기 — 연달아 `CHAT_BURST` 번, 그 뒤로는 `CHAT_REFILL_MS` 마다 한 번씩 찬다
	var now := int(clock.call())
	var bucket: Dictionary = _chat_buckets.get_or_add(account.id, {"left": float(CHAT_BURST), "at": now})
	bucket.left = minf(float(CHAT_BURST), float(bucket.left) + float(now - int(bucket.at)) / CHAT_REFILL_MS)
	bucket.at = now
	if bucket.left < 1.0:
		return _error(null, "chat_limit")
	bucket.left = float(bucket.left) - 1.0
	_say({"t": "chat", "from": name_of(account), "text": text})
	return {}


## 알림 — 누가 무엇을 해냈다. 강화 +`ANNOUNCE_ENHANCE` 이상 성공만 알린다
func _announce(account: Dictionary, events: Array) -> void:
	var best := 0
	var item := ""
	for event in events:
		match str(event.get("type", "")):
			"enhanceResult":
				if str(event.get("result", "")) == "success" and int(event.get("level", 0)) > best:
					best = int(event.level)
					item = str(event.get("name", ""))
			"enhanceBatch":
				for entry in event.get("results", []):
					if int(entry.get("success", 0)) > 0 and int(entry.get("from", 0)) + 1 > best:
						best = int(entry.from) + 1
						item = ""
	if best < ANNOUNCE_ENHANCE:
		return
	var what := ("%s +%d" % [item, best]) if not item.is_empty() else "+%d" % best
	_say({"t": "chat", "system": true, "text": "%s 님이 %s 강화에 성공했습니다" % [name_of(account), what]})


func _say(line: Dictionary) -> void:
	outbox.append(line)
	_chat_log.append(line)
	while _chat_log.size() > CHAT_HISTORY:
		_chat_log.remove_at(0)


## 방송할 것을 가져간다 (`GameServer` 가 붙은 사람 모두에게 보낸다)
func take_outbox() -> Array:
	var out := outbox
	outbox = []
	return out


## 채팅·랭킹에 보이는 이름 — 계정의 이름(시작 화면에서 정한 것, `Names` 규칙), 없으면 `display_name`
static func name_of(account: Dictionary) -> String:
	var name := str(account.get("name", ""))
	return name if Names.valid(name) else display_name(str(account.get("id", "")))


## 이름이 없는 계정의 이름 — `모험가#` + 계정 id 앞 네 자리 (`#` 이 있어 `Names` 규칙의 이름과 안 겹친다)
static func display_name(account_id: String) -> String:
	return "모험가#" + account_id.substr(0, 4).to_upper()


## 줄바꿈·제어 문자를 빼고 앞뒤 공백을 자르고 `CHAT_MAX_LEN` 자에서 자른다
static func _clean(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code != 127:
			out += raw[i]
	return out.strip_edges().left(CHAT_MAX_LEN)


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


## 존에 들어왔다. **게임에 있는 입장 규칙만 본다** — 지금은 막는 규칙이 없다 (`World.travel`.
## 전직 시험 존은 2026-09-29 에 전직째로 없앴다). 들어올 때마다 명단을 새로 센다 —
## 기기도 존을 다시 열면 몬스터를 새로 놓는다
func _enter(account: Dictionary, zone: String) -> String:
	if not GameData.zones().get("zones", {}).has(zone):
		return "no_zone"
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


## 시련의 탑 통과를 대 본다 (docs/features/dungeons.md "시련의 탑"). 되면 빈 글자.
## **서버가 인정한 처치만 센다** — 들어온 때(`entered_at`)부터 제한 시간(+흔들림) 안에 잡은 것이
## 필요한 수 이상이어야 한다. 한 번 들어와 한 번만 받는다 (다시 받으려면 다시 들어온다)
func _check_trial(account: Dictionary, zone: String) -> String:
	var hunt: Dictionary = _hunts.get(account.id, {})
	if hunt.is_empty() or str(hunt.zone) != zone:
		return "wrong_zone"
	var stage := GameData.dungeon_stage(zone)
	if int(stage.get("kills", 0)) <= 0:
		return "not_trial"
	if bool(hunt.get("trial_claimed", false)):
		return "claimed"
	var deadline := float(hunt.entered_at) + float(stage.get("seconds", 30)) * 1000.0 + KillCheck.SLACK_MS
	var counted := 0
	for at in hunt.killed.values():
		if float(at) <= deadline:
			counted += 1
	if counted < int(stage.kills):
		return "too_few"
	hunt["trial_claimed"] = true
	return ""


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _error(id: Variant, reason: String) -> Dictionary:
	var out := {"t": "error", "reason": reason}
	if id != null:
		out["id"] = id
	return out


## --- 유료 재화 (docs/features/server.md "유료 재화") ---

## 결제 영수증 `{t:"purchase", product, token}` — 기기가 구글 플레이에서 산 뒤 구매 토큰을 보낸다.
## **다이아 개수는 상품 표(`store.json`)에서 찾는다** — 기기가 보낸 개수는 없다.
## 검증은 시간이 걸려서 여기서는 일감만 걸고 빈 답을 준다 — 끝나면 `poll_jobs` 가 답한다
func _purchase(session: Dictionary, message: Dictionary) -> Dictionary:
	var account: Dictionary = session.get("account", {})
	if account.is_empty():
		return _error(null, "no_hello")
	var product := str(message.get("product", ""))
	var token := str(message.get("token", ""))
	if not GameData.load_table("store").get("products", {}).has(product):
		return {"t": "error", "reason": "unknown_product", "product": product}
	if token.is_empty() or token.length() > 4096:
		return {"t": "error", "reason": "bad_token", "product": product}
	var key := token.sha256_text()
	# **이미 받은 영수증** — 같은 계정이면 받은 것으로 답한다(기기가 이제 소모하면 된다).
	# 다른 계정이면 거절한다. 계정에 남긴 표시도 본다 — 계정은 썼는데 주문 파일을 쓰기 전에 꺼졌을 때
	var order := store.find_order(key)
	if not order.is_empty() or key in account.get("orders", []):
		if order.is_empty() or str(order.get("account", "")) == str(account.id):
			return {"t": "purchased", "product": product, "already": true, "diamonds": 0,
				"ledger": Ledger.view(account.ledger), "events": []}
		return {"t": "error", "reason": "order_taken", "product": product}
	for waiting in _jobs:
		if waiting.key == key:
			return {"t": "error", "reason": "in_progress", "product": product}
	if verifier == null:
		return {"t": "error", "reason": "store_off", "product": product}
	_jobs.append({"session": session, "account": account, "product": product, "key": key,
		"job": verifier.start(product, token)})
	return {}


## 검증 일감을 돌린다 — `GameServer.poll` 이 매 프레임 부른다. 끝난 것은 `take_replies` 로 나간다
func poll_jobs() -> void:
	for entry in _jobs.duplicate():
		if verifier != null:
			verifier.poll(entry.job)
		if not entry.job.done:
			continue
		_jobs.erase(entry)
		if entry.job.ok:
			_replies.append([entry.session, _finish_purchase(entry)])
		else:
			print("결제 거절 %s %s: %s" % [entry.account.id, entry.product, entry.job.reason])
			_replies.append([entry.session, {"t": "error", "reason": "purchase_invalid",
				"product": entry.product, "detail": str(entry.job.reason)}])


## 다이아를 넣는다. **계정을 먼저 쓰고(주문 표시 포함) 주문 파일을 뒤에 쓴다** — 사이에 꺼지면
## 계정의 표시가 두 번 받는 것을 막는다. 반대 순서면 돈만 나가고 다이아가 없는 채로 남을 수 있다
func _finish_purchase(entry: Dictionary) -> Dictionary:
	var account: Dictionary = entry.account
	if not store.find_order(entry.key).is_empty() or entry.key in account.get("orders", []):
		return {"t": "purchased", "product": entry.product, "already": true, "diamonds": 0,
			"ledger": Ledger.view(account.ledger), "events": []}
	var amount := int(GameData.load_table("store").products.get(entry.product, 0))
	ledger.credit_diamonds(account.ledger, amount, entry.product)
	var orders: Array = account.get_or_add("orders", [])
	orders.append(entry.key)
	var reply := {"t": "purchased", "product": entry.product, "diamonds": amount,
		"ledger": Ledger.view(account.ledger), "events": ledger.take_events()}.duplicate(true)
	if not store.write(account):
		return {"t": "error", "reason": "store_failed", "product": entry.product}
	store.write_order(entry.key, {"account": account.id, "product": entry.product,
		"order_id": str(entry.job.get("order_id", "")), "at": int(Time.get_unix_time_from_system())})
	print("결제 %s %s +%d (%s)" % [account.id, entry.product, amount, entry.job.get("order_id", "")])
	return reply


## 끝난 결제의 답 `[[session, 답], …]` — `GameServer` 가 그 연결에만 보낸다
func take_replies() -> Array:
	var out := _replies
	_replies = []
	return out
