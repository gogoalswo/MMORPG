extends SceneTree

## 할퀴기 스킬 이펙트가 실제로 서고, 양쪽에서 엇갈리고, 제 시간에 사라지는지 본다.
##
## 스크린샷을 찍지 않는다 — "가닥이 몇 개인가 · 서로 반대로 기울었나 · 앞쪽에 섰나 ·
## 화면에서 몇 px 인가 · 치우고 갔나" 는 전부 노드로 읽을 수 있다.
## 눈으로 볼 것은 색과 속도감뿐이다.
##
##   godot --headless --path godot --script tests/skill_fx_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
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
	await _case_shape(game)
	await _case_visible(game)
	await _case_other_skill(game)
	await _case_gone(game)
	_done()


## 액션바의 할퀴기를 누르면(= 서버가 `skill` 이벤트를 낸다) 자국이 선다.
## **실제 경로로 쏜다** — 이벤트만 흉내 내면 액션바·전송이 끊겨도 통과한다
func _case_cast(game: Node3D) -> void:
	# 새 캐릭터는 아직 아무것도 안 배웠다 — 배우고 액션바에 올려야 쏠 수 있다
	# (서버가 액션바에 올라간 스킬만 받아 준다)
	game._transport.send(&"learnSkill", {"skill": "rising_kick"})
	game._transport.send(&"setSkillBar", {"bar": ["rising_kick"]})
	await process_frame
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var bar: Array = me.get("skill_bar", [])
	if not ("rising_kick" in bar):
		_fail("액션바에 할퀴기가 없다 (%s) — 기본 직업이 격투가가 아니다" % str(bar))
		return
	game._transport.send(&"skill", {"skill": "rising_kick"})
	for i in 3:
		await process_frame

	var fx := _newest(game)
	if fx == null:
		_fail("할퀴기를 썼는데 자국이 안 섰다")
		return
	if fx._strokes.size() != SkillFx.SETS * SkillFx.STROKES:
		_fail("가닥이 %d개다 (%d개여야 한다)" % [fx._strokes.size(), SkillFx.SETS * SkillFx.STROKES])
	else:
		print("  할퀴기: 가닥 %d개" % fx._strokes.size())


## **양쪽에서 들어와 X 로 엇갈려야 한다.** 한 세트 안은 나란하고(각이 거의 같고),
## 두 세트는 부호가 반대다. 나란하게만 두면 한쪽으로만 그은 빗금이 된다
func _case_shape(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("모양을 볼 자국이 없다")
		return

	var first: Array = []
	var second: Array = []
	for i in fx._strokes.size():
		var node: MeshInstance3D = fx._strokes[i].node
		if i < SkillFx.STROKES:
			first.append(node.rotation.z)
		else:
			second.append(node.rotation.z)

	if _mean(first) * _mean(second) >= 0.0:
		_fail("두 세트가 같은 쪽으로 그어졌다 (%.2f, %.2f) — 빗금이지 할퀸 자국이 아니다" % [
			_mean(first), _mean(second)
		])
	for angle in first:
		if absf(angle - _mean(first)) > SkillFx.JITTER + 1e-3:
			_fail("한 세트 안에서 각이 %.2f 나 벌어졌다 — 별표가 된다" % absf(angle - _mean(first)))

	# 두 세트가 좌우로 갈려 들어온다
	var left: MeshInstance3D = fx._strokes[0].node
	var right: MeshInstance3D = fx._strokes[SkillFx.STROKES].node
	if left.position.x >= right.position.x:
		_fail("두 세트가 좌우로 안 갈렸다 (%.2f, %.2f)" % [left.position.x, right.position.x])

	# 두 번째 세트가 늦게 들어온다 — 동시에 그으면 손이 두 번 지나간 것으로 안 읽힌다
	if fx._strokes[SkillFx.STROKES].delay <= fx._strokes[0].delay:
		_fail("두 번째 세트가 먼저 나온다")

	# **캐릭터가 보는 쪽 앞에 선다.** 화면이 아니라 몸이 보는 쪽이어야 한다
	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	var here := Vector3(me.x, 0.0, me.z)
	var facing := Vector3(sin(float(me.rot)), 0.0, cos(float(me.rot)))
	var away := fx.global_position - here
	away.y = 0.0
	if away.normalized().dot(facing) < 0.9:
		_fail("자국이 앞쪽에 없다 (보는 쪽과 %.2f)" % away.normalized().dot(facing))
	elif absf(fx.global_position.y - SkillFx.HEIGHT) > 1e-3:
		_fail("자국 높이가 %.2f 다 — 가슴 높이여야 한다" % fx.global_position.y)
	else:
		print("  자리: 앞 %.1fm, 높이 %.2fm, 세트 간격 %.0fms" % [
			away.length(), fx.global_position.y, fx._strokes[SkillFx.STROKES].delay * 1000.0
		])


## **화면에서 몇 px 로 보이나.** 미터로 정하면 서기만 하고 안 보인다 —
## 피격 이펙트에서 숫자 16px 로 잡았다가 "이펙트가 안 나온다" 는 말을 들었다
## (2026-09-17, `hit_fx_test.gd` 의 같은 검사)
func _case_visible(game: Node3D) -> void:
	var fx := _newest(game)
	if fx == null:
		_fail("크기를 잴 자국이 없다")
		return

	var cam: Camera3D = game._camera
	var at: Vector3 = game._player.global_position + Vector3.UP
	var per_m := (cam.unproject_position(at) - cam.unproject_position(at + Vector3.UP)).length()
	var length := SkillFx.LENGTH * per_m
	var width := SkillFx.WIDTH * per_m
	var spread := (SkillFx.STROKES - 1) * SkillFx.GAP * per_m
	print("  1m=%.0fpx — 자국 길이 %.0fpx · 폭 %.0fpx · 세 가닥 폭 %.0fpx" % [
		per_m, length, width, spread
	])

	# 기준은 피격 이펙트에서 눈으로 정한 선을 따른다 — 파편이 5px 하한이었다
	if length < 50.0:
		_fail("자국이 %.0fpx 다 — 캐릭터(74px)보다 한참 짧으면 안 읽힌다" % length)
	if width < 4.0:
		_fail("자국 폭이 %.0fpx 다 — 배경에 묻힌다" % width)
	if width > length / 8.0:
		_fail("자국이 넓적하다 (길이의 1/%.0f) — 손톱 자국이 아니라 마름모다" % (length / width))


## 다른 스킬은 이 자국을 그리지 않는다. 스킬마다 그림이 달라야 한다
func _case_other_skill(game: Node3D) -> void:
	var before := _count(game)
	game._on_event(&"skill", {
		"id": game._transport.my_id(), "skill": "tiger_roar", "root_ms": 400,
	})
	await process_frame
	if _count(game) != before:
		_fail("호포각에 할퀴기 자국이 떴다")


## 스스로 사라진다. 부르는 쪽이 목록을 들고 있지 않으므로 여기서 안 지우면 쌓인다
func _case_gone(game: Node3D) -> void:
	var waited := 0
	while _newest(game) != null and waited < 240:
		await process_frame
		waited += 1
	if _newest(game) != null:
		_fail("자국이 안 사라졌다")
	else:
		print("  %d프레임 뒤 치워졌다" % waited)


func _newest(game: Node3D) -> SkillFx:
	if game._zone_node == null:
		return null
	var found: SkillFx = null
	for child in game._zone_node.get_children():
		if child is SkillFx:
			found = child
	return found


func _count(game: Node3D) -> int:
	if game._zone_node == null:
		return 0
	var n := 0
	for child in game._zone_node.get_children():
		if child is SkillFx:
			n += 1
	return n


func _mean(values: Array) -> float:
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(max(1, values.size()))


func _done() -> void:
	if _failed == 0:
		print("스킬 이펙트: 통과")
		quit(0)
	else:
		print("스킬 이펙트: %d개 실패" % _failed)
		quit(1)
