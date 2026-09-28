class_name GameServer
extends RefCounted

## 웹소켓으로 받고 `LedgerServer` 에 넘긴다. **판정은 여기 없다** — 소켓만 맡는다.
## `poll` 을 부르는 쪽이 돌린다: 실제 서버는 `server_main.gd` 가 매 프레임, 테스트는 고리에서.
##
## TLS 는 여기서 안 한다 — 앞에 선 Caddy 가 `wss://` 를 받아 이리로 넘긴다
## (docs/features/server.md "어디에 올리나"). 그래서 기본은 `127.0.0.1` 에서만 듣는다.

## 한 번에 오가는 JSON 의 상한. 가방 200칸을 통째로 실은 답이 수십 KB 라 넉넉히 둔다
const BUFFER := 1 << 20

var ledger_server: LedgerServer
var _tcp := TCPServer.new()
var _peers: Array = []  # [{ws: WebSocketPeer, session: {}}]


func _init(store: AccountStore) -> void:
	ledger_server = LedgerServer.new(store)


func listen(port: int, bind := "127.0.0.1") -> Error:
	return _tcp.listen(port, bind)


func stop() -> void:
	for peer in _peers:
		peer.ws.close()
	_peers.clear()
	_tcp.stop()


## 실제로 듣는 포트 — `listen(0)` 이면 비어 있는 것을 골라 준다 (테스트가 쓴다)
func port() -> int:
	return _tcp.get_local_port()


func connections() -> int:
	return _peers.size()


func poll() -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER
		ws.outbound_buffer_size = BUFFER
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_peers.append({"ws": ws, "session": {}})

	for peer in _peers.duplicate():
		var ws: WebSocketPeer = peer.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var text := ws.get_packet().get_string_from_utf8()
					var reply := ledger_server.handle(peer.session, JSON.parse_string(text))
					ws.send_text(JSON.stringify(reply))
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(peer)
