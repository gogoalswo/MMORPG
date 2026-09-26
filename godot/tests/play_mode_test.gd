extends SceneTree

## 시작 화면의 **테스트 모드 / 일반 모드** (2026-09-25). → docs/features/play-mode.md
##
## - 시작 화면에 단추 둘이 있고, 누르면 `PlayMode.current` 에 적는다
## - 테스트 모드: 무적 켬 · 쿨타임 0 켬 · 치트 목록은 접힌 채 여닫기 단추만 보인다
## - 일반 모드: 무적 끔 · 쿨타임 0 끔 · 치트 목록도 여닫기 단추도 안 보인다
##
##   godot --headless --path godot --script tests/play_mode_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	if ProjectSettings.get_setting("application/run/main_scene") != "res://start.tscn":
		_fail("게임을 켜면 시작 화면(start.tscn)이 떠야 한다")

	# 시작 화면 — 단추 둘. **장면 넘김은 여기서 안 한다** (SceneTree 스크립트라 current_scene 이 없다).
	# 고른 값만 본다
	var start: Control = load("res://start.tscn").instantiate()
	root.add_child(start)
	await process_frame
	if start.test_button == null or start.normal_button == null:
		_fail("시작 화면에 모드 단추가 없다")
	start.queue_free()
	await _case_reset()

	await _case(PlayMode.TEST)
	await _case(PlayMode.NORMAL)
	PlayMode.current = ""
	if _failed == 0:
		print("  초기화 단추: 두 번에 지움 · 테스트 모드: 무적·쿨타임 0 켬, 목록 접힘, 장비 42종·크리스탈 300·Lv200 · 일반 모드: 전부 끔, 목록 숨김")
	quit(1 if _failed > 0 else 0)


func _case(mode: String) -> void:
	PlayMode.current = mode
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var test := mode == PlayMode.TEST
	if bool(me.get("invincible", false)) != test:
		_fail("%s: 무적이 %s 이어야 한다" % [mode, test])
	if Skills.cooldown_off() != test:
		_fail("%s: 쿨타임 0 이 %s 이어야 한다" % [mode, test])
	if game._cheat_column.visible:
		_fail("%s: 치트 목록은 접힌 채 시작해야 한다" % mode)
	if game._cheat_toggle.visible != test:
		_fail("%s: 치트 여닫기 단추가 %s 이어야 한다" % [mode, "보여야" if test else "숨어야"])
	if test and not game._invincible_button.text.ends_with("켬"):
		_fail("테스트 모드인데 무적 단추 글자가 켬이 아니다: %s" % game._invincible_button.text)
	if test:
		_check_test_kit(me)
		await _check_test_level(game, me)
	# 다음 경우를 위해 되돌린다 — 쿨타임 스위치는 표(static)라 장면을 치워도 남는다
	Skills.set_switch("cooldownOff", false)
	game.queue_free()
	await process_frame


## 저장 초기화 단추 — 한 번 누르면 되묻기만 하고, 두 번째에 지운다 (2026-09-26)
func _case_reset() -> void:
	Save.write("town", {"x": 0.0, "z": 0.0, "level": 100, "exp": 0, "hp": 1})
	var start: Control = load("res://start.tscn").instantiate()
	root.add_child(start)
	await process_frame
	if start.reset_button == null or start.reset_button.disabled:
		_fail("저장이 있는데 초기화 단추가 없거나 꺼져 있다")
	else:
		start.reset_button.pressed.emit()
		if not FileAccess.file_exists(Save.PATH):
			_fail("초기화 단추를 한 번 눌렀는데 벌써 지웠다")
		start.reset_button.pressed.emit()
		if FileAccess.file_exists(Save.PATH):
			_fail("초기화 단추를 두 번 눌렀는데 저장이 남았다")
		if not start.reset_button.disabled:
			_fail("지운 뒤에도 초기화 단추가 켜져 있다")
	start.queue_free()
	await process_frame


## 테스트 모드는 200레벨로 시작한다 — 한 번만 (2026-09-26). 설계 창으로 낮춘 뒤
## 다시 들어와도 200 으로 되돌아가면 안 된다
func _check_test_level(game: Node3D, me: Dictionary) -> void:
	var want := mini(200, Stats.max_level())
	if int(me.get("level", 0)) != want:
		_fail("테스트 모드: Lv%d 로 시작해야 한다 — Lv%d" % [want, int(me.get("level", 0))])
	game._transport.send(&"debugGear", {"level": 50, "grade": 1, "enhance": 0})
	game._transport.send(&"testLevel", {})
	await process_frame
	var again := int(game._transport.snapshot().players[game._transport.my_id()].get("level", 0))
	if again != 50:
		_fail("테스트 모드: 200레벨은 한 번만 줘야 한다 — 50 으로 낮췄는데 Lv%d" % again)


## 테스트 모드 꾸러미 — 모든 장비 등급별로 하나씩(+0), 크리스탈 300개 (2026-09-26)
func _check_test_kit(me: Dictionary) -> void:
	var seen := {}
	var crystals := 0
	for stack in me.get("bag", []):
		if str(stack.id) == Items.crystal_id():
			crystals += int(stack.get("count", 1))
		elif int(stack.get("enhance", 0)) == 0:
			seen[str(stack.id)] = true
	var want := Stats.grade_count() * Items.slots().size()
	if seen.size() != want:
		_fail("테스트 모드: +0 장비가 %d종이어야 한다 — %d종" % [want, seen.size()])
	if crystals < 300:
		_fail("테스트 모드: 크리스탈이 300개 이상이어야 한다 — %d개" % crystals)
