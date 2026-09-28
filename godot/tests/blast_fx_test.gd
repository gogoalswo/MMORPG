extends SceneTree

## 폭렬 찍기(`blast_heel`) 이펙트 — **착지에 터지고, 잔불이 남았다가 식는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — `npm run shot:godot -- blast_heel` 로 찍어서 눈으로 본다
## → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/blast_fx_test.gd

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

	await _case_cast(game)
	_case_shape()
	await _case_embers(game)
	await _case_gone(game)
	_done()


## 액션바의 폭렬 찍기를 누르면 **착지 뒤에** 이펙트가 선다 — 실제 경로로 쏜다.
## 4차 전직(Lv.180) 스킬이라 레벨·포인트·전직 단계를 직접 올린다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["job_tier"] = 4
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "blast_heel"})
	game._transport.send(&"setSkillBar", {"bar": ["blast_heel"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("blast_heel" in me.get("skill_bar", [])):
		_fail("액션바에 폭렬 찍기가 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "blast_heel"})
	for i in 4:
		await process_frame
	var delay := float(Skills.get_skill("fighter", "blast_heel").get("delayMs", 0)) / 1000.0
	if delay <= 0.0:
		_fail("폭렬 찍기에 착지 지연(delayMs)이 없다 — 뛰어오르는 동작보다 먼저 터진다")
	elif _newest(game) != null:
		_fail("폭렬 찍기 이펙트가 착지(%.2f초) 전에 섰다" % delay)
	await create_timer(delay + 0.1).timeout
	if _newest(game) == null:
		_fail("폭렬 찍기를 썼는데 착지 뒤에도 이펙트가 안 섰다")
	if game._camera._shake_left <= 0.0:
		_fail("폭렬 찍기를 썼는데 화면이 안 흔들린다")


## 판정 표와 맞나 — 바닥 불길이 멈추는 거리 · 불꽃 자리가 사거리 안이다
func _case_shape() -> void:
	var reach := float(Skills.get_skill("fighter", "blast_heel").get("range", 0.0))
	var stop := BlastFx.WAVE_SPEED_MAX * BlastFx.WAVE_SPEED_MAX / (2.0 * BlastFx.WAVE_DAMP)
	print("  바닥 불길 %.1fm · 사거리 %.1fm" % [stop, reach])
	if stop > reach:
		_fail("바닥 불길이 사거리(%.1fm)를 넘어 %.1fm 까지 간다" % [reach, stop])
	var spots := BlastFx.flame_points()
	if spots.size() < 12:
		_fail("잔불 불꽃 자리가 %d곳뿐이다" % spots.size())
	for p in spots:
		if Vector2(p.x, p.z).length() > reach:
			_fail("잔불 불꽃이 사거리 밖(%.1fm)에서 난다" % Vector2(p.x, p.z).length())
			break


## 잔불 — 터지고 나서도 금·불꽃이 남아 있다가, `EMBER_TIME` 이 지나면 새 불꽃이 멎고 식는다.
## 시계를 직접 넣어 본다 — 4초를 기다리지 않는다. 금 메시는 천붕각 것을 돌려 쓴다
func _case_embers(game: Node3D) -> void:
	var fx := BlastFx.blast(game._zone_node, Vector3.ZERO, 1.0)
	await process_frame
	await process_frame
	var first := _newest(game)
	if fx._lava.mesh != QuakeFx.crack_meshes()[0] or fx._core.mesh != QuakeFx.crack_meshes()[1]:
		_fail("금 메시를 새로 깎는다 — 천붕각 것을 돌려 써야 한다")
	if first != null and fx._char.mesh != first._char.mesh:
		_fail("달무리 메시를 쓸 때마다 새로 깎는다")
	if absf(fx._turn.rotation.y - 1.0) > 1e-4:
		_fail("금·불꽃 자리가 캐릭터가 보는 쪽으로 안 돌았다")
	if not fx._bursts[0].emitting:
		_fail("불덩이가 안 터졌다")
	fx._t = BlastFx.EMBER_TIME - 0.5
	await process_frame
	if not (fx._lava.visible and fx._embers[0].emitting):
		_fail("잔불이 %.1f초 전에 꺼졌다 (금 %s · 불꽃 %s)" % [
			BlastFx.EMBER_TIME, fx._lava.visible, fx._embers[0].emitting])
	fx._t = BlastFx.EMBER_TIME + 0.1
	await process_frame
	for e in fx._embers:
		if e.emitting:
			_fail("잔불이 식을 때가 지났는데 새 불꽃·불씨가 계속 난다")
			break
	fx._t = BlastFx.EMBER_TIME + BlastFx.EMBER_FADE + 0.05
	await process_frame
	if fx._lava.visible or fx._char.visible:
		_fail("잔불이 다 식었는데 금이 남아 있다")
	fx.queue_free()
	await process_frame


func _case_gone(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		return
	fx._t = BlastFx.span() - 0.01
	for i in 3:
		await process_frame
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")


func _newest(game: Node3D) -> BlastFx:
	if game._fx == null:
		return null
	var found: BlastFx = null
	for child in game._fx.get_children():
		if child is BlastFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("폭렬 찍기 이펙트: 통과")
		quit(0)
	else:
		print("폭렬 찍기 이펙트: %d개 실패" % _failed)
		quit(1)
