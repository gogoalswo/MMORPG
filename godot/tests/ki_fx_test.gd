extends SceneTree

## 파천장(`ki_burst`) 이펙트 — **손바닥에서 기가 앞으로 휘몰아치는지** 본다.
##
## 여기서는 **판정 표와 어긋나지 않는지 · 규칙을 지키는지 · 치워지는지** 를 본다.
## 생김새는 노드로 못 본다 — `npm run shot:godot -- ki_burst` 로 찍어서 눈으로 본다
## → [verification.md](../../docs/features/verification.md)
##
##   godot --headless --path godot --script tests/ki_fx_test.gd

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
	_case_reach()
	await _case_once(game)
	await _case_gone(game)
	_done()


## 액션바의 파천장을 누르면 이펙트가 서고 화면이 흔들린다 — **실제 경로로 쏜다.**
## 4차 전직(Lv.180) 스킬이라 레벨·포인트·전직 단계를 직접 올린다
func _case_cast(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = 180
	player["job_tier"] = 4
	player["skill_points"] = 5
	game._transport.send(&"learnSkill", {"skill": "ki_burst"})
	game._transport.send(&"setSkillBar", {"bar": ["ki_burst"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not ("ki_burst" in me.get("skill_bar", [])):
		_fail("액션바에 파천장이 없다 (%s)" % str(me.get("skill_bar", [])))
		return
	game._transport.send(&"skill", {"skill": "ki_burst"})
	for i in 4:
		await process_frame
	var fx := _newest(game)
	if fx == null:
		_fail("파천장을 썼는데 이펙트가 안 섰다")
		return
	if game._camera._shake_left <= 0.0:
		_fail("파천장을 썼는데 화면이 안 흔들린다")
	if absf(wrapf(fx.rotation.y - float(me.rot), -PI, PI)) > 1e-3:
		_fail("이펙트가 캐릭터가 보는 쪽(%.2f)이 아니라 %.2f 로 섰다" % [float(me.rot), fx.rotation.y])
	for e: CPUParticles3D in [fx._dust, fx._motes, fx._aura]:
		if not e.emitting:
			_fail("내지를 때 켜질 방출기가 안 켜졌다")
		if not e.one_shot:
			_fail("방출기가 one_shot 이 아니다 — 계속 뿜는다")
	# 규칙 3절 — 퍼지는 동그란 고리 메시는 없다. 띠는 파티클이 아니라 메시다
	for node in fx.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is TorusMesh:
			_fail("고리 메시가 있다 — 퍼지는 충격 파동 고리는 쓰지 않는다")


## 가장 먼 것(소용돌이 · 빛살)이 **판정 사거리 안**이고 **앞쪽**이다
func _case_reach() -> void:
	var reach := float(Skills.get_skill("fighter", "ki_burst").get("range", 0.0))
	var far := 0.0
	for i in KiFx.SWIRLS:
		far = maxf(far, KiFx.SWIRL_Z[i] + KiFx.SWIRL_DEPTH * KiFx.radius_at(KiFx.SWIRL_Z[i]))
	var box := KiFx.streak_mesh().get_aabb()
	var streak_far := KiFx.PALM + box.end.z
	if far > reach or streak_far > reach:
		_fail("사거리 %.1fm 를 넘는다 — 소용돌이 %.2fm · 빛살 %.2fm" % [reach, far, streak_far])
	if box.position.z < 0.0:
		_fail("빛살이 손바닥 뒤로 뻗는다 (%.2f)" % box.position.z)
	print("  소용돌이 %.2fm · 빛살 %.2fm 까지 (사거리 %.1fm)" % [far, streak_far, reach])


## 메시는 게임 전체에서 한 번만 깐다 — 두 번째 것도 같은 메시를 쓴다
func _case_once(game: Node3D) -> void:
	var first := _newest(game)
	if first == null:
		return
	var fx := KiFx.new()
	game._zone_node.add_child(fx)
	fx._build()
	var a: MeshInstance3D = (first._swirls[0].node as Node3D).get_child(0)
	var b: MeshInstance3D = (fx._swirls[0].node as Node3D).get_child(0)
	if a.mesh != b.mesh or first._streaks[0].node.mesh != fx._streaks[0].node.mesh:
		_fail("소용돌이·빛살 메시를 쓸 때마다 새로 깎는다")
	fx.queue_free()
	await process_frame


func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 600:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("이펙트가 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


func _newest(game: Node3D) -> KiFx:
	if game._fx == null:
		return null
	var found: KiFx = null
	for child in game._fx.get_children():
		if child is KiFx and FxPool.busy(child):
			found = child
	return found


func _done() -> void:
	if _failed == 0:
		print("파천장 이펙트: 통과")
		quit(0)
	else:
		print("파천장 이펙트: %d개 실패" % _failed)
		quit(1)
