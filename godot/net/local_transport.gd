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
		_:
			push_warning("모르는 메시지: %s" % message)


func snapshot() -> Dictionary:
	return _world.snapshot() if _world != null else {}


func my_id() -> String:
	return MY_ID


func _process(delta: float) -> void:
	if _world != null:
		_world.step(delta)
