class_name ServerLedger
extends RefCounted

## 기기 쪽 서버 통로 — 장부 요청을 서버로 보내고, 답으로 `World` 의 장부를 덮는다
## (docs/features/server.md 3단계). `World.remote` 에 꽂히고, `LocalTransport` 가 매 프레임 `poll` 한다.
##
## 기기는 **판정하지 않는다.** 요청을 보내 두고 답(`replied`)을 기다린다. 먼저 바꿔 보이지도
## 않는다 — 드롭·강화는 굴림이라 기기가 먼저 보여 줄 값이 없다.
##
## 끊기면 `RETRY_MS` 뒤에 같은 토큰으로 다시 붙는다. 번호 규칙 (서버가 같은 번호를 한 번만 판정한다):
## - welcome 의 `last_req` 보다 **작은** 번호로 보냈던 것 → 이미 판정됐다. 버린다 (장부는 welcome 이 준다)
## - `last_req` 와 **같은** 것 → 다시 보낸다. 서버가 판정하지 않고 남겨 둔 답을 준다
## - 더 큰 것 · 아직 안 보낸 것 → 보낸다. 안 보낸 것은 `last_req` 뒤로 번호를 새로 매긴다

signal welcomed(ledger: Dictionary)
signal replied(ledger: Dictionary, events: Array)
signal failed(reason: String)
## 채팅 한 줄 `{from, text}` 또는 알림 `{system: true, text}` — welcome 때는 지난 줄들이 차례로 온다
signal chat(line: Dictionary)
## 랭킹 답 `{top: [{rank, name, level, exp}], me: {rank, level, exp}, total}`
signal ranked(board: Dictionary)
## 결제 결과 — `{t:"purchased", product, diamonds, already?}` 이거나 `{t:"error", reason, product}`.
## **`purchased` 를 받은 뒤에만** 기기가 그 구매를 소모(consume)한다 — 소모해야 같은 상품을 또 산다
signal purchase_done(result: Dictionary)

const TOKEN_PATH := "user://account.json"
const RETRY_MS := 2000

var url := ""
## 끊긴 뒤 다시 붙기까지 (테스트는 줄인다)
var retry_ms := RETRY_MS
## welcome 을 받았나. 받기 전의 요청은 쌓아 뒀다가 받으면 보낸다
var ready := false

var _token_path := ""
var _ws: WebSocketPeer = null
var _hello_sent := false
var _retry_at := 0
var _next_id := 1
## 답을 못 받은 요청들, 보낸 순서대로 — `{id, op, args, sent}`
var _pending: Array = []


func _init(server_url: String, token_path := TOKEN_PATH) -> void:
	url = server_url
	_token_path = token_path
	_connect()


func request(op: StringName, args: Array) -> void:
	var entry := {"id": _next_id, "op": str(op), "args": args, "sent": false}
	_next_id += 1
	_pending.append(entry)
	if ready:
		_send(entry)


## 말 한 줄을 보낸다. 붙어 있지 않으면 버리고 false — 채팅은 쌓아 두었다 보내지 않는다
## (다시 붙었을 때 한참 전 말이 뒤늦게 가면 엉뚱하다). 이름은 서버가 붙인다
func say(text: String) -> bool:
	if not ready or text.strip_edges().is_empty():
		return false
	_ws.send_text(JSON.stringify({"t": "chat", "text": text}))
	return true


## 랭킹을 묻는다. 붙어 있지 않으면 false — 답은 `ranked` 로 온다
func ask_rank() -> bool:
	if not ready:
		return false
	_ws.send_text(JSON.stringify({"t": "rank"}))
	return true


## 구글 플레이에서 산 것의 영수증(구매 토큰)을 보낸다. 붙어 있지 않으면 false —
## 기기는 소모하지 않은 구매를 들고 있다가 다시 붙으면 또 보낸다 (서버가 두 번 넣지 않는다)
func purchase(product: String, token: String) -> bool:
	if not ready:
		return false
	_ws.send_text(JSON.stringify({"t": "purchase", "product": product, "token": token}))
	return true


## 아직 답을 못 받은 요청 수 (테스트·로딩 표시가 본다)
func waiting() -> int:
	return _pending.size()


func close() -> void:
	if _ws != null:
		_ws.close()


func poll() -> void:
	if _ws == null:
		if Time.get_ticks_msec() >= _retry_at:
			_connect()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_hello_sent = true
				_ws.send_text(JSON.stringify({"t": "hello", "token": _load_token()}))
			while _ws.get_available_packet_count() > 0:
				_on_message(JSON.parse_string(_ws.get_packet().get_string_from_utf8()))
		WebSocketPeer.STATE_CLOSED:
			# 다음에 다시 붙으면 보낸 것도 welcome 규칙대로 다시 가린다
			ready = false
			_ws = null
			_retry_at = Time.get_ticks_msec() + retry_ms


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = GameServer.BUFFER
	_ws.outbound_buffer_size = GameServer.BUFFER
	_hello_sent = false
	if _ws.connect_to_url(url) != OK:
		_ws = null
		_retry_at = Time.get_ticks_msec() + retry_ms


func _send(entry: Dictionary) -> void:
	entry.sent = true
	_ws.send_text(JSON.stringify({"t": "op", "id": entry.id, "op": entry.op, "args": entry.args}))


func _on_message(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var message: Dictionary = Ledger.from_json(raw)
	match str(message.get("t", "")):
		"welcome":
			if message.has("token"):
				_save_token(str(message.token))
			_welcome(int(message.get("last_req", 0)))
			welcomed.emit(message.get("ledger", {}))
			for line in message.get("chat", []):
				chat.emit(line)
		"chat":
			chat.emit(message)
		"rank":
			ranked.emit(message)
		"purchased":
			replied.emit(message.get("ledger", {}), message.get("events", []))
			purchase_done.emit(message)
		"result":
			_drop(int(message.get("id", 0)))
			replied.emit(message.get("ledger", {}), message.get("events", []))
		"error":
			if message.has("id"):
				_drop(int(message.id))
			if message.has("product"):
				purchase_done.emit(message)
			failed.emit(str(message.get("reason", "")))


func _welcome(last_req: int) -> void:
	var kept: Array = []
	var top := last_req
	for entry in _pending:
		if entry.sent and int(entry.id) < last_req:
			continue  # 이미 판정됐다
		if entry.sent:
			top = maxi(top, int(entry.id))
		kept.append(entry)
	for entry in kept:
		if not entry.sent:
			top += 1
			entry.id = top
	_pending = kept
	_next_id = top + 1
	ready = true
	for entry in _pending:
		_send(entry)


func _drop(id: int) -> void:
	for i in _pending.size():
		if int(_pending[i].id) == id:
			_pending.remove_at(i)
			return


## 토큰은 서버 주소마다 따로 둔다 — 다른 서버에 남의 토큰을 내밀지 않게
func _load_token() -> String:
	if not FileAccess.file_exists(_token_path):
		return ""
	var saved = JSON.parse_string(FileAccess.get_file_as_string(_token_path))
	return str(saved.get(url, "")) if typeof(saved) == TYPE_DICTIONARY else ""


func _save_token(token: String) -> void:
	var saved := {}
	if FileAccess.file_exists(_token_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_token_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			saved = parsed
	saved[url] = token
	var file := FileAccess.open(_token_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(saved))
		file.close()
