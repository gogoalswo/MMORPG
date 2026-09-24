extends SceneTree

## 여러 마리에게 둘러싸여 맞는 중에 스킬을 써도 **스킬 동작이 끝까지 도는지** 본다.
##
##   godot --headless --path godot --script tests/skill_motion_test.gd

const MOBS := 8

var _failed := 0


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 3:
		await process_frame
	if not game._player is Rig:
		print("  내 캐릭터가 모델이 아니다 (에셋 미동기화) — 건너뜀")
		_done()
		return
	var rig: Rig = game._player

	var snap: Dictionary = game._transport.snapshot()
	var me: Dictionary = snap.players[game._transport.my_id()]
	game._transport.send(&"invincible", {"on": true})
	game._transport.send(&"learnSkill", {"skill": "rising_kick"})
	game._transport.send(&"setSkillBar", {"bar": ["rising_kick"]})
	# 여덟 마리를 둘레 1.5m 에 세운다. 나머지는 덤비지 않게 한다
	var near := 0
	for m in snap.get("monsters", []):
		if near < MOBS:
			var a := TAU * near / MOBS
			m.x = float(me.x) + sin(a) * 1.5
			m.z = float(me.z) + cos(a) * 1.5
			m.home_x = m.x
			m.home_z = m.z
			m.max_hp = 99999999
			m.hp = 99999999
			near += 1
		else:
			m.aggro = 0.0
			m.target = ""
	# 무리가 한 바퀴 때리기 시작할 때까지
	for i in 90:
		OS.delay_msec(16)
		await process_frame

	var clip := str(game.SKILL_CLIPS["rising_kick"])
	var length := rig.clip_length(clip)
	var worst := INF
	var frozen := 0
	for cast in 3:
		# 앞 동작의 경직이 풀린 뒤에 쏜다 — 묶여 있으면 서버가 안 받아 준다
		while Time.get_ticks_msec() < int(me.rooted_until):
			OS.delay_msec(16)
			await process_frame
		me.skill_ready_at = {}
		game._transport.send(&"skill", {"skill": "rising_kick"})
		var last := 0.0
		var started := false
		for i in 150:
			OS.delay_msec(16)
			await process_frame
			if rig._anim.current_animation != clip:
				if started:
					break
				continue
			started = true
			last = rig._anim.current_animation_position
			if rig._freeze > 0.0:
				frozen += 1
		worst = minf(worst, last)

	print("  %s %.2f초 중 제일 덜 돈 것 %.2f초 · 멈춘 프레임 %d" % [clip, length, worst, frozen])
	if worst < length - 0.1:
		_fail("맞는 중에 스킬 동작이 %.2f/%.2f초에서 끊겼다" % [worst, length])
	_done()


func _done() -> void:
	if _failed == 0:
		print("스킬 동작: 통과")
		quit(0)
	else:
		print("스킬 동작: %d개 실패" % _failed)
		quit(1)
