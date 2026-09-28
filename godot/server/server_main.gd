extends SceneTree

## 고도 헤드리스 서버를 띄운다 (docs/features/server.md).
##
##   godot --headless --path godot --script server/server_main.gd -- --port=8765 --data=/srv/mmorpg/accounts \
##       [--play-package=com.example.game --play-key=/srv/mmorpg/play-service-account.json]
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
	# 구글 플레이 결제 검증 — 패키지 이름과 서비스 계정 키(JSON 파일 경로)를 **둘 다** 줘야 켠다.
	# 키는 저장소에 넣지 않는다. 안 주면 결제를 받지 않는다(`store_off`)
	var package := str(options.get("play-package", ""))
	var key_path := str(options.get("play-key", ""))
	if not package.is_empty() and not key_path.is_empty():
		var account = JSON.parse_string(FileAccess.get_file_as_string(key_path))
		if typeof(account) == TYPE_DICTIONARY:
			_server.ledger_server.verifier = GooglePlayVerifier.new(package, account)
			print("구글 플레이 결제 검증을 켰다: %s" % package)
		else:
			printerr("서비스 계정 키를 못 읽었다: %s" % key_path)
	var err := _server.listen(port, bind)
	if err != OK:
		printerr("서버를 못 띄웠다 %s:%d — %s" % [bind, port, error_string(err)])
		quit(1)
		return
	print("서버 %s:%d 에서 듣는다 — 계정 %s" % [bind, port, ProjectSettings.globalize_path(data)])


func _process(_delta: float) -> bool:
	_server.poll()
	return false
