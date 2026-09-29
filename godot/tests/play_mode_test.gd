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
		print("  초기화 단추: 두 번에 지움 · 테스트 모드: 무적·쿨타임 0 켬, 목록 접힘, 장비 42종·크리스탈 300·Lv200·스킬 전부·스킬 목록 · 일반 모드: 전부 끔, 목록 숨김")
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
		await _check_skill_list(game, me)
		await _check_test_skills(game, me)
	if game._skill_list_toggle.visible != test or game._skill_list.visible:
		_fail("%s: 스킬 목록 단추가 %s 이어야 하고 목록은 접혀 있어야 한다" % [mode, "보여야" if test else "숨어야"])
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


## 테스트 모드는 모든 스킬을 배우고 전직도 끝까지 올린 채 시작한다 — 한 번만 (2026-09-28).
## 액션바에서 빼 둔 뒤 다시 들어와도 빈 칸이 도로 채워지면 안 된다
func _check_test_skills(game: Node3D, me: Dictionary) -> void:
	for id in Skills.for_job(str(me.job)):
		if not (str(id) in me.skills):
			_fail("테스트 모드: 스킬 %s 를 배운 채 시작해야 한다" % id)
	if int(me.job_tier) != Skills.job_advances().size():
		_fail("테스트 모드: 전직이 %d차여야 한다 — %d차" % [Skills.job_advances().size(), int(me.job_tier)])
	me.skill_bar.clear()
	game._transport.send(&"testSkills", {})
	await process_frame
	if not me.skill_bar.is_empty():
		_fail("테스트 모드: 스킬은 한 번만 줘야 한다 — 비운 액션바가 %s 로 채워졌다" % [me.skill_bar])


## 테스트 모드 스킬 목록 (2026-09-28) — 펼치면 내 직업 스킬이 다 뜨고, 퀵슬롯에 없는 것도
## 누르면 쓰인다. 왼쪽 끝에 붙고, 퀵슬롯·채팅창을 덮지 않는다 (1280×720). 치트 목록과 같은
## 자리라 한쪽을 펼치면 다른 쪽이 접힌다 (2026-09-29)
func _check_skill_list(game: Node3D, me: Dictionary) -> void:
	game._skill_list_toggle.pressed.emit()
	await process_frame
	var ids: Array = Skills.for_job(str(me.job))
	if not game._skill_list.visible or game._skill_list.get_child_count() != ids.size():
		_fail("스킬 목록: 펼치면 스킬 %d개가 떠야 한다 — %d개" % [ids.size(), game._skill_list.get_child_count()])
		return
	if game._skill_list.get_global_rect().position.x != game._cheat_toggle.get_global_rect().position.x:
		_fail("스킬 목록: 왼쪽 끝(치트 단추와 같은 x)에 붙어야 한다 — %s" % game._skill_list.get_global_rect())
	# 아래 가운데 묶음 — 퀵슬롯 칸이 아니라 레벨 배지·체력 막대까지 담은 통째로 본다
	var dock: Control = game._bar_buttons[0]
	while dock.get_parent() != game._ui_root:
		dock = dock.get_parent()
	var others: Array = [game._cheat_toggle, game._chat, dock]
	for rect_of in [game._skill_list, game._skill_list_toggle]:
		var mine: Rect2 = rect_of.get_global_rect()
		if mine.position.y < 0:
			_fail("스킬 목록: %s 가 화면 위로 넘친다 — %s" % [rect_of.name, mine])
		for other in others:
			if mine.intersects(other.get_global_rect()):
				_fail("스킬 목록: %s 가 %s 를 덮는다" % [rect_of.name, other.name])
	game._set_cheats_open(true)
	if game._skill_list.visible:
		_fail("스킬 목록: 치트 목록을 펼쳤는데 스킬 목록이 안 접혔다")
	game._skill_list_toggle.pressed.emit()
	if game._cheat_column.visible:
		_fail("스킬 목록: 스킬 목록을 펼쳤는데 치트 목록이 안 접혔다")
	var last := str(ids[-1])
	if last in me.skill_bar:
		_fail("스킬 목록: 퀵슬롯에 없는 스킬로 시험해야 한다 — %s 가 퀵슬롯에 있다" % last)
	var before: int = game._swing_until
	game._skill_list.get_node(last).pressed.emit()
	for i in 3:
		await process_frame
	if game._swing_until == before:
		_fail("스킬 목록: %s 를 눌렀는데 쓰이지 않았다" % last)
	game._skill_list_toggle.pressed.emit()


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
