extends SceneTree

## 몬스터가 때릴 때 **화면에서도 휘두르는지** 본다 — 내가 쉬지 않고 때리는 동안에도.
##
## 판정(`World`)은 멀쩡히 때리는데 화면은 서 있기만 한 일이 있었다 (2026-09-24,
## "몬스터를 연속으로 공격하면 반격을 못해"). 화면이 상태(`attack`)만 보고 3.73초짜리
## `Attack` 을 준비 자세부터 틀어서, 서버가 1.2초마다 때리는 동안 할퀴기가 3.7초에
## 한 번꼴로만 나왔다. 여기서는 서버가 때린 횟수와 화면이 할퀴기 자리를 지난
## 횟수를 센다. 모델이 없으면(에셋 미동기화) 기둥이라 휘두를 것이 없어 건너뛴다.
##
##   godot --headless --path godot --script tests/mob_swing_test.gd

## 오우거 `Attack` 첫 할퀴기 (0.90~1.05초) 의 한가운데
const CLAW_AT := 0.97
const FRAMES := 360

var _failed := 0
var _hits := 0
var _mob_id := ""


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

	var snap: Dictionary = game._transport.snapshot()
	var mob: Dictionary = {}
	for m in snap.get("monsters", []):
		if mob.is_empty() and game._mob_nodes.get(str(m.id)) is Rig:
			mob = m
		else:
			# 한 마리만 덤비게 한다. 무리가 같이 때리면 누가 휘둘렀는지 가리기 어렵다
			m.aggro = 0.0
			m.target = ""
	if mob.is_empty():
		print("  모델로 선 몬스터가 없다 (에셋 미동기화) — 건너뜀")
		_done()
		return
	_mob_id = str(mob.id)

	# 바로 앞에 세우고 쉬지 않고 때린다. 죽지 않게 무적·체력 무한
	var me: Dictionary = snap.players[game._transport.my_id()]
	me.x = float(mob.x)
	me.z = float(mob.z) + 1.5
	mob.home_x = mob.x
	mob.home_z = mob.z
	mob.max_hp = 99999999
	mob.hp = 99999999
	game._transport.send(&"invincible", {"on": true})
	game._transport.event.connect(_on_event)

	var rig: Rig = game._mob_nodes[_mob_id]
	var claws := 0
	var before := -1.0
	for i in FRAMES:
		game._transport.send(&"attack", {})
		OS.delay_msec(16)
		await process_frame
		var anim: AnimationPlayer = rig._anim
		var now := anim.current_animation_position if anim.current_animation == "Attack" else -1.0
		if before >= 0.0 and before < CLAW_AT and now >= CLAW_AT:
			claws += 1
		before = now

	print("  %d초 동안 서버가 %d대 때렸고 화면이 %d번 할퀴었다" % [FRAMES * 16 / 1000, _hits, claws])
	if _hits < 3:
		_fail("몬스터가 거의 안 때렸다 (%d대) — 시험 배치가 틀렸다" % _hits)
	# 마지막 한 대는 할퀴기 전에 끝날 수 있다
	elif claws < _hits - 1:
		_fail("서버는 %d대 때렸는데 화면은 %d번만 휘둘렀다" % [_hits, claws])
	_done()


func _on_event(name: StringName, payload: Dictionary) -> void:
	if name == &"hit" and str(payload.get("source", "")) == _mob_id:
		_hits += 1


func _done() -> void:
	if _failed == 0:
		print("몬스터 휘두르기: 통과")
		quit(0)
	else:
		print("몬스터 휘두르기: %d개 실패" % _failed)
		quit(1)
