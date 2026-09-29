extends SceneTree

## 폭렬 찍기(`blast_heel`) — **발이 닿을 때 타겟 자리에서 폭발 기둥이 솟는지** 본다.
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
	_case_target()
	await _case_pillar(game)
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
	# 기둥은 **내 발밑이 아니라** 앞쪽(잡을 놈이 없으면 `AT_TARGET_AHEAD`)에 선다
	var fx := _newest(game)
	if fx != null:
		var gap := Vector2(fx.position.x - float(me.x), fx.position.z - float(me.z)).length()
		print("  기둥이 선 자리: 나에게서 %.1fm" % gap)
		if gap < 1.0:
			_fail("폭발 기둥이 내 발밑(%.1fm)에 섰다 — 타겟 자리여야 한다" % gap)


## 판정 — **겨눈 놈 자리가 중심**이고 반경은 터지는 반경(`blast_radius`)이다. 내 옆에 붙은 놈은
## 안 맞는다. 잡을 놈이 없으면 보는 쪽 앞에서 터진다. 자리는 누르는 순간 정해 이벤트에 싣는다
func _case_target() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me["job_tier"] = 4
	me.skills = ["blast_heel"]
	me.skill_bar = ["blast_heel"]
	var mobs: Array = w.snapshot().monsters
	var near := World.make_monster("near", GameData.monster_kind("mob003"),
		float(me.x) + 1.2, float(me.z), 100000.0, 0.0)
	var far := World.make_monster("far", GameData.monster_kind("mob003"),
		float(me.x) + 6.0, float(me.z), 100000.0, 0.0)
	mobs.append(near)
	mobs.append(far)
	var near_hp := int(near.hp)
	var far_hp := int(far.hp)
	w.drain_events()
	w.cast("me", "blast_heel", "far")
	var shown := _event(w.drain_events(), "skill")
	if not (is_equal_approx(float(shown.get("tx", 0.0)), float(far.x))
			and is_equal_approx(float(shown.get("tz", 0.0)), float(far.z))):
		_fail("skill 이벤트에 겨눈 놈 자리가 안 실렸다 (%s)" % str(shown))
	# 늦게 떨어지는 스킬 — 시계를 넘겨 떨어뜨린다
	w._run_landings(Time.get_ticks_msec() + 5000)
	var ring := _event(w.drain_events(), "skillRange")
	var skill := Skills.get_skill("fighter", "blast_heel")
	if ring.is_empty():
		_fail("떨어졌는데 판정 범위가 안 왔다")
		return
	if not (is_equal_approx(float(ring.x), float(far.x)) and is_equal_approx(float(ring.z), float(far.z))):
		_fail("판정 중심이 겨눈 놈 자리가 아니다 (%.1f, %.1f)" % [ring.x, ring.z])
	if not is_equal_approx(float(ring.reach), Skills.blast_radius(skill)):
		_fail("터지는 반경이 %.1f 여야 하는데 %.1f" % [Skills.blast_radius(skill), ring.reach])
	if int(far.hp) >= far_hp:
		_fail("겨눈 놈이 안 맞았다")
	if int(near.hp) < near_hp:
		_fail("내 옆(1.2m)에 붙은 놈이 맞았다 — 내 둘레가 아니라 타겟 자리에서 터져야 한다")
	print("  판정: 6m 앞 겨눈 놈 자리 · 반경 %.1fm · 옆에 붙은 놈은 안 맞음" % float(ring.reach))

	# 잡을 놈이 없으면 — 보는 쪽 앞에서 터진다
	mobs.clear()
	me.cast_until = 0
	me.skill_ready_at = {}
	me.rot = 0.0
	w.cast("me", "blast_heel")
	shown = _event(w.drain_events(), "skill")
	var ahead := Vector2(float(shown.get("tx", me.x)) - float(me.x), float(shown.get("tz", me.z)) - float(me.z))
	if absf(ahead.length() - World.AT_TARGET_AHEAD) > 0.01 or ahead.y <= 0.0:
		_fail("잡을 놈이 없을 때 앞 %.1fm 에서 터져야 하는데 %s" % [World.AT_TARGET_AHEAD, str(ahead)])


## 기둥 — 땅에서 치솟았다(높이) 가늘어지며 사그라든다. 잔불·옆으로 퍼지는 것은 없다.
## 빛살 메시는 한 번만 깐다. 시계를 직접 넣어 본다
func _case_pillar(game: Node3D) -> void:
	var fx := BlastFx.blast(game._zone_node, Vector3.ZERO, 1.0)
	await process_frame
	await process_frame
	var first := _newest(game)
	if first != null and fx._ray_core.mesh != first._ray_core.mesh:
		_fail("빛살 메시를 쓸 때마다 새로 깎는다")
	if not fx._bursts[0].emitting:
		_fail("불덩이 기둥이 안 솟았다")
	if BlastFx.ray_end() > BlastFx.RAY_END:
		_fail("빛살이 %.2f초까지 가는데 %.2f초에 숨긴다" % [BlastFx.ray_end(), BlastFx.RAY_END])
	# 불덩이는 **위로** 솟는다 — 옆으로 퍼지면 "내 주변 연기" 로 보인다 (2026-09-29 지적)
	for e in fx._bursts:
		if e.direction != Vector3.UP or e.spread > 45.0:
			_fail("위로 솟지 않고 옆으로 퍼지는 방출기가 있다 (%s · %.0f°)" % [e.direction, e.spread])
			break
		if not e.one_shot:
			_fail("계속 나는 방출기가 있다 — 불꽃 잔해는 없앴다")
			break
	var top := BlastFx.COLUMN_SPEED_MAX * BlastFx.COLUMN_SPEED_MAX / (2.0 * BlastFx.COLUMN_DAMP)
	print("  불덩이 기둥이 멎는 높이 %.1fm · 판 %.1fm" % [top, BlastFx.PILLAR_HEIGHT])
	fx._t = BlastFx.PILLAR_RISE
	await process_frame
	if not fx._pillar.visible or fx._pillar.scale.y < 0.95:
		_fail("기둥이 %.2f초에 다 안 솟았다 (높이 배율 %.2f)" % [BlastFx.PILLAR_RISE, fx._pillar.scale.y])
	fx._t = BlastFx.PILLAR_END + 0.01
	await process_frame
	if fx._pillar.visible:
		_fail("기둥이 %.2f초 뒤에도 남아 있다" % BlastFx.PILLAR_END)
	if BlastFx.span() > 1.5:
		_fail("이펙트가 %.1f초나 간다 — 잔해를 남기지 않는다" % BlastFx.span())
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


func _event(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


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
