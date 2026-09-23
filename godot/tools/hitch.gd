extends SceneTree

## **스킬을 쓸 때 어디서 프레임이 튀나 잰다.** 사냥터 무리 한가운데에 서서
## 스킬마다 여러 번 쓰고, 한 프레임을 덩어리별로 나눠 잰다.
##
##   godot --headless --path godot --script tools/hitch.gd
##
## - `시전` — 시전 요청을 판정이 받는 값 (`World.cast`, 첫 대 판정까지)
## - `판정 틱` — `World.step` (연타 · 몬스터 · 자동사냥). **무리 속에서는 스킬 없이도
##   매 프레임 든다** — 맨 아래 `(안 씀)` 줄과 비교해서 읽는다
## - `이벤트:이름` — 화면이 판정 이벤트를 받아 그리는 값 (이펙트 · 숫자 · 알림)
## - `화면 틱` — `game._process`
##
## 프레임 전체를 재면 무리 속 몬스터 틱이 들쭉날쭉해서 스킬 몫이 묻힌다 — 그래서
## 전송(`LocalTransport`)과 `game._process` 를 멈추고 여기서 직접 돌리며 잰다.
## 헤드리스라 그리는 값(셰이더 컴파일)은 빠진다 — 그건 `FxWarm` · `FxPool` 몫이다.
## 2026-09-23 에 만들었다 ("스킬 사용할 때 자꾸 히치가 걸려") → skills.md "히치"

const ZONE := "meadow"
const PACK := Vector3(-28.0, 0.0, -28.0)
## 마지막 `none` 은 안 쓰고 서 있기만 한다 — 판정 틱의 바닥값
const SKILLS := ["rising_kick", "thunder_fall", "sky_breaker", "frost_pillar", "none"]
## 첫 번째는 버리고(글자·재질을 처음 굽는 값) 나머지의 최댓값을 본다
const CASTS := 4
const WATCH_FRAMES := 60
const REST_FRAMES := 60

var _game: Node3D
var _net: Node
var _worst: Dictionary = {}


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_game = root.get_node("Game")
	_net = _game._transport
	await process_frame
	Skills.set_switch("cooldownOff", true)
	_net.send(&"travel", {"zone": ZONE})
	await process_frame
	var player: Dictionary = _net._world._players[_net.my_id()]
	player["level"] = 200
	player["skill_points"] = 99
	for skill in SKILLS:
		_net.send(&"learnSkill", {"skill": skill})
	_net.set_process(false)
	_game.set_process(false)
	# 굽기(`FxWarm`)가 끝나고 무리가 몰려올 때까지
	for i in 150:
		await _frame()

	print("가장 긴 값(ms), 첫 시전 뺀 %d번 중" % (CASTS - 1))
	for skill in SKILLS:
		_net.send(&"setSkillBar", {"bar": [skill]})
		var seen: Dictionary = {}
		for c in CASTS:
			# 죽지 않게 — 무리 한가운데서 오래 버틴다
			player["x"] = PACK.x
			player["z"] = PACK.z
			player["hp"] = 1_000_000_000
			_worst.clear()
			if skill != "none":
				var t0 := Time.get_ticks_usec()
				_net.send(&"skill", {"skill": skill})
				_note("시전", t0)
			for f in WATCH_FRAMES:
				await _frame()
			if c > 0:
				for key in _worst:
					seen[key] = maxf(float(seen.get(key, 0.0)), float(_worst[key]))
			for f in REST_FRAMES:
				await _frame()
		var keys := seen.keys()
		keys.sort()
		var line := "%-13s" % (skill if skill != "none" else "(안 씀)")
		for key in keys:
			line += "  %s %.2f" % [key, seen[key]]
		print(line)
	quit(0)


## 한 프레임 — 판정 틱 · 이벤트 · 화면 틱을 따로 잰다
func _frame() -> void:
	await process_frame
	var dt := 1.0 / 60.0
	var t0 := Time.get_ticks_usec()
	_net._world.step(dt)
	_note("판정 틱", t0)
	for e in _net._world.drain_events():
		var name := str(e.get("type", "?"))
		var t1 := Time.get_ticks_usec()
		_game._on_event(StringName(name), e)
		_note("이벤트:" + name, t1)
	var t2 := Time.get_ticks_usec()
	_game._process(dt)
	_note("화면 틱", t2)


func _note(key: String, since: int) -> void:
	var ms := float(Time.get_ticks_usec() - since) * 0.001
	_worst[key] = maxf(float(_worst.get(key, 0.0)), ms)
