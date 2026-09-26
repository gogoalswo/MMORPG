extends SceneTree

## 모드를 고르면 뜨는 **로딩 막** (2026-09-26). → docs/features/play-mode.md
##
## - 단추를 누르면 막이 덮인다 — 불투명, 뒤를 못 누르게 막는다, 단추는 잠긴다
## - 게임(`main.tscn`)이 자리 잡을 때까지 막이 남아 있다
## - 그다음 반투명을 거쳐 걷히고, 다 걷히면 막이 스스로 지워진다
##
##   godot --headless --path godot --script tests/loading_screen_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	var start: Control = load("res://start.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame

	start.choose(PlayMode.NORMAL)
	var curtain: LoadingScreen = null
	for child in root.get_children():
		if child is LoadingScreen:
			curtain = child
	if curtain == null:
		_fail("모드를 골랐는데 로딩 막이 안 떴다")
		quit(1)
		return
	var cover: Control = curtain._root
	if cover.modulate.a < 1.0 or cover.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("막이 처음엔 불투명하고 뒤를 막아야 한다")
	if not start.normal_button.disabled:
		_fail("막이 덮인 뒤에도 모드 단추가 눌린다")

	# 게임이 자리 잡을 때까지 막이 그대로여야 한다
	var game_ready_at := -1
	var saw_half := false
	var frames := 0
	while is_instance_valid(curtain) and frames < 600:
		await process_frame
		frames += 1
		var scene := current_scene
		if game_ready_at < 0 and scene != null and scene != start and scene.is_node_ready():
			game_ready_at = frames
			if is_instance_valid(curtain) and cover.modulate.a < 1.0:
				_fail("게임이 뜨기 전에 막이 벌써 걷히기 시작했다")
		if is_instance_valid(curtain) and cover.modulate.a > 0.05 and cover.modulate.a < 0.95:
			saw_half = true
	if game_ready_at < 0:
		_fail("게임 장면(main.tscn)으로 안 넘어갔다")
	elif current_scene.name != "Game":
		_fail("넘어간 장면이 Game 이 아니다: %s" % current_scene.name)
	if is_instance_valid(curtain):
		_fail("600 프레임이 지나도 막이 안 걷혔다")
	elif not saw_half:
		_fail("막이 서서히 걷히지 않고 한 번에 사라졌다")
	PlayMode.current = ""
	if _failed == 0:
		print("  누르면 막이 덮이고, 게임이 자리 잡은 뒤 %d 프레임에 걸쳐 서서히 걷힌다" % (frames - game_ready_at))
	quit(1 if _failed > 0 else 0)
