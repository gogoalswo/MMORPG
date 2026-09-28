extends SceneTree

## 고도 헤드리스 서버를 띄운다 (docs/features/server.md).
##
##   godot --headless --path godot --script server/server_main.gd -- --port=8765 --data=/srv/mmorpg/accounts
##
## `--bind=0.0.0.0` 을 주지 않으면 이 기계 안에서만 받는다 — 바깥은 Caddy 가 `wss://` 로 받아 넘긴다.
## `--data` 를 안 주면 `user://accounts` (고도의 사용자 폴더)에 계정을 둔다.

const DEFAULT_PORT := 8765

var _server: GameServer


func _initialize() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else ""
	var port := int(options.get("port", DEFAULT_PORT))
	var bind := str(options.get("bind", "127.0.0.1"))
	var data := str(options.get("data", "user://accounts"))

	_server = GameServer.new(AccountStore.new(data))
	var err := _server.listen(port, bind)
	if err != OK:
		printerr("서버를 못 띄웠다 %s:%d — %s" % [bind, port, error_string(err)])
		quit(1)
		return
	print("서버 %s:%d 에서 듣는다 — 계정 %s" % [bind, port, ProjectSettings.globalize_path(data)])


func _process(_delta: float) -> bool:
	_server.poll()
	return false
