extends SceneTree

## 전직 — 전직 NPC → N차 전직 버튼 → 시험(보스) → 잡으면 전직 · 스킬 해금.
## 레벨·단계·거리는 **World 가 다시 본다** (docs/features/job-advance.md).
##
##   godot --headless --path godot --script tests/job_advance_test.gd

const NPC := "전직관 레온"

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_locked()
	_case_npc_state()
	_case_trial()
	_case_no_shortcut()
	_case_save()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


## 마을에서 전직 NPC 곁에 선 캐릭터
func _village(level: int) -> World:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.level = level
	for npc in w.snapshot().npcs:
		if str(npc.get("name", "")) == NPC:
			me.x = float(npc.x) - 2.0
			me.z = float(npc.z)
	w.drain_events()
	return w


## 전직 전에는 낙뢰·빙주각·천붕각을 배우지도 쓰지도 못한다. 할퀴기는 된다
func _case_locked() -> void:
	var w := _village(200)
	var me: Dictionary = w.snapshot().players["me"]
	for id in ["thunder_fall", "frost_pillar", "sky_breaker"]:
		w.learn_skill("me", id)
		if id in me.skills:
			_fail("전직 전에 %s 을(를) 배웠다" % id)
	w.learn_skill("me", "rising_kick")
	if not ("rising_kick" in me.skills):
		_fail("기본 스킬 할퀴기를 못 배웠다")
	# 전직 전 저장에 배운 채로 남은 것도 못 쓴다
	me.skills.append("thunder_fall")
	me.skill_bar = ["thunder_fall"]
	w.drain_events()
	w.cast("me", "thunder_fall")
	if not _first(w.drain_events(), "skill").is_empty():
		_fail("전직 전에 낙뢰가 나갔다")
	print("  전직 전: 할퀴기만 배운다 · 낙뢰는 배워 있어도 안 나간다")


## NPC 창에는 **다음 전직 하나**만. 레벨이 모자라면 버튼이 안 눌린다
func _case_npc_state() -> void:
	for row in [[0, 29, 1, false], [0, 30, 1, true], [2, 120, 3, true], [2, 119, 3, false]]:
		var w := _village(int(row[1]))
		w.snapshot().players["me"].job_tier = int(row[0])
		w.npc_open("me", NPC)
		var job: Dictionary = _first(w.drain_events(), "npc").get("job", {})
		var next: Dictionary = job.get("next", {})
		if int(next.get("tier", 0)) != int(row[2]) or bool(job.get("ready", false)) != bool(row[3]):
			_fail("%d차 · Lv.%d: 다음 %s · 버튼 %s (%d차 · %s 여야 한다)" % [
				row[0], row[1], next.get("tier", "-"), job.get("ready", "-"), row[2], row[3]
			])
	var w := _village(200)
	w.snapshot().players["me"].job_tier = 4
	w.npc_open("me", NPC)
	var done: Dictionary = _first(w.drain_events(), "npc").get("job", {})
	if not done.get("next", {}).is_empty():
		_fail("4차를 마쳤는데 다음 전직이 있다")
	print("  NPC 창: 2차면 '3차 전직', Lv.29 에서는 1차 버튼이 막힌다, 4차 뒤엔 없다")


## 버튼 → 시험 존(보스 한 마리) → 잡으면 전직 · 낙뢰 해금
func _case_trial() -> void:
	var w := _village(1)
	var me: Dictionary = w.snapshot().players["me"]
	w.job_advance("me")
	if w.zone_id != "village":
		_fail("Lv.1 인데 시험으로 갔다 (%s)" % w.zone_id)

	w = _village(30)
	w.job_advance("me")
	if w.zone_id != "job_1":
		_fail("Lv.30 인데 1차 시험으로 안 갔다 (%s)" % w.zone_id)
		return
	me = w.snapshot().players["me"]
	var mobs: Array = w.snapshot().monsters
	if mobs.size() != 1 or not bool(mobs[0].get("boss", false)):
		_fail("1차 시험에 보스 한 마리가 아니다 (%d)" % mobs.size())
		return
	if int(me.job_tier) != 0:
		_fail("시험에 들어가기만 했는데 전직됐다")
	w.drain_events()
	w._hit_monster(me, mobs[0], 1e9, "")
	var events := w.drain_events()
	if int(me.job_tier) != 1 or _first(events, "jobAdvanced").is_empty():
		_fail("보스를 잡았는데 1차 전직이 안 됐다 (%d)" % int(me.job_tier))
	w.learn_skill("me", "thunder_fall")
	if not ("thunder_fall" in me.skills):
		_fail("1차 전직 뒤에도 낙뢰를 못 배운다")
	w.learn_skill("me", "frost_pillar")
	if "frost_pillar" in me.skills:
		_fail("1차 전직으로 빙주각(2차)까지 풀렸다")

	# 같은 시험을 다시 잡아도 2차가 되지는 않는다
	mobs[0].hp = mobs[0].max_hp
	w._hit_monster(me, mobs[0], 1e9, "")
	if int(me.job_tier) != 1:
		_fail("1차 시험 보스를 또 잡았더니 %d차가 됐다" % int(me.job_tier))
	print("  1차: Lv.30 → job_1 · 보스 %s 처치 → 1차 · 낙뢰 해금 (빙주각은 잠김)" % mobs[0].kind)


## 차원문·던전 창 길(travel)로는 시험에 못 간다 — 전직 NPC 로만
func _case_no_shortcut() -> void:
	var w := _village(200)
	w.travel("me", "job_1")
	if w.zone_id != "village":
		_fail("travel 로 전직 시험에 들어갔다 (%s)" % w.zone_id)
	# NPC 곁이 아니면 버튼 요청도 버린다
	w.snapshot().players["me"].x = 0.0
	w.snapshot().players["me"].z = -10.0
	w.job_advance("me")
	if w.zone_id != "village":
		_fail("NPC 에게서 먼데 시험으로 갔다")


## 전직 창 모양 — 화면 가운데 안 · 단계 점 다섯(마친 데까지 금빛) · 해금 스킬 아이콘 ·
## 조건 줄 · 단추가 창 안 · 닫기 X 가 오른쪽 위
func _check_layout(game: Node3D, panel: JobPanel) -> void:
	await process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rect := panel.get_global_rect()
	if not screen.encloses(rect):
		_fail("전직 창이 화면 밖으로 나간다 (%s)" % rect)
	if absf(rect.get_center().x - 640.0) > 2.0:
		_fail("전직 창이 가운데가 아니다 (%s)" % rect)
	var steps := 0
	for i in 5:
		var step: Node = panel.find_child("step%d" % i, true, false)
		if step != null:
			steps += 1
	if steps != 5:
		_fail("단계 점이 %d개 (기본 + 4차 = 5)" % steps)
	var done: StyleBoxFlat = panel.find_child("step1", true, false).get_node("dot").get_theme_stylebox("panel")
	var ahead: StyleBoxFlat = panel.find_child("step3", true, false).get_node("dot").get_theme_stylebox("panel")
	if done.bg_color == ahead.bg_color:
		_fail("1차를 마쳤는데 1차 점과 3차 점이 같은 색이다")
	var icon: TextureRect = panel.find_child("skill_icon", true, false)
	if icon.texture == null:
		_fail("해금 스킬(빙주각) 아이콘이 없다 — npm run sync:godot 을 돌렸나")
	var level_row: Label = panel.find_child("level_row", true, false)
	var boss_row: Label = panel.find_child("boss_row", true, false)
	if not level_row.text.begins_with("레벨 70") or not boss_row.text.contains("Lv.69"):
		_fail("조건 줄이 다르다: '%s' · '%s'" % [level_row.text, boss_row.text])
	var button: Button = panel.find_child("advance", true, false)
	if not rect.encloses(button.get_global_rect()):
		_fail("단추가 창 밖이다")
	var close: Control = panel.find_child("close", true, false)
	if close == null:
		_fail("닫기 X 가 없다")
	else:
		var x := close.get_global_rect()
		if x.get_center().x < rect.get_center().x or x.get_center().y > rect.position.y + 100:
			_fail("닫기 X 가 오른쪽 위가 아니다 (%s)" % x)
	print("  전직 창: %s · 단계 5 · '%s' · '%s'" % [rect.size, level_row.text, boss_row.text])


## 치트 "스킬 모두 배우기" — 전직을 끝까지 올리고 그 직업 스킬을 다 배워 액션바에 올린다
func _case_learn_all(game: Node3D) -> void:
	var cheat: Button = game._cheat_column.find_child("learnAll", true, false)
	if cheat == null:
		_fail("치트 목록에 '스킬 모두 배우기' 단추가 없다")
		return
	# 단추가 늘면 목록이 위로 자란다 — 펼쳤을 때 맨 위 단추가 화면 안이어야 누를 수 있다
	game._set_cheats_open(true)
	await process_frame
	var rect := cheat.get_global_rect()
	if rect.position.y < 0.0 or rect.end.y > 720.0:
		_fail("'스킬 모두 배우기' 단추가 화면 밖이다 (%s)" % rect)
	if game._cheat_column.size.x > 240.0:
		_fail("치트 목록이 넓어졌다 (%.0f)" % game._cheat_column.size.x)
	var me: Dictionary = game._transport._world._players[game._transport.my_id()]
	me.job_tier = 0
	me.skills = []
	me.skill_bar = []
	cheat.pressed.emit()
	await process_frame
	var all := Skills.for_job(str(me.job))
	if int(me.job_tier) != Skills.job_advances().size():
		_fail("전직이 끝까지 안 올랐다 (%d차)" % int(me.job_tier))
	for id in all:
		if not (str(id) in me.skills):
			_fail("%s 을(를) 안 배웠다" % id)
	if me.skill_bar.size() != mini(all.size(), 4):
		_fail("액션바가 %d칸" % me.skill_bar.size())
	# 배운 낙뢰가 실제로 나간다
	me.cast_until = 0
	me.skill_ready_at = {}
	game._transport._world.cast(game._transport.my_id(), "thunder_fall")
	if int(me.skill_ready_at.get("thunder_fall", 0)) == 0:
		_fail("모두 배운 뒤에도 낙뢰가 안 나간다")
	print("  치트: %d차 전직 · 스킬 %d개 · 액션바 %s" % [int(me.job_tier), me.skills.size(), str(me.skill_bar)])


## 전직 단계는 저장에 남는다
func _case_save() -> void:
	var w := _village(70)
	w.snapshot().players["me"].job_tier = 2
	w.save("me")
	var back := World.new()
	back.open("village")
	if not back.restore("me"):
		_fail("저장을 못 읽었다")
		return
	var tier := int(back.snapshot().players["me"].get("job_tier", -1))
	if tier != 2:
		_fail("저장에서 전직 단계가 %d (2 여야 한다)" % tier)
	Save.clear()


## 화면 — 전직 NPC 를 누르면 창에 "N차 전직" 버튼 하나. 누르면 시험으로 간다
func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	me.x = 5.0
	me.z = 7.0
	me.level = 70
	me.job_tier = 1
	game._transport.send(&"npc", {"name": NPC})
	await process_frame

	var panel: JobPanel = game._job_panel
	var button: Button = panel.find_child("advance", true, false)
	await _check_layout(game, panel)
	if not panel.visible or button == null:
		_fail("전직 창이나 버튼이 안 떴다")
	elif game._npc_panel.visible:
		_fail("전직 창과 상점 창이 같이 떴다")
	elif button.text != "2차 전직 시험 입장" or button.disabled:
		_fail("1차 · Lv.70 인데 버튼이 '%s' (막힘 %s)" % [button.text, button.disabled])
	else:
		# 레벨이 모자라면 단추가 막히고 몇 레벨에 열리는지 적는다
		me.level = 60
		game._transport.send(&"npc", {"name": NPC})
		await process_frame
		if not button.disabled or button.text != "Lv.70 에 열립니다":
			_fail("Lv.60 인데 단추가 '%s' (막힘 %s)" % [button.text, button.disabled])
		me.level = 70
		game._transport.send(&"npc", {"name": NPC})
		await process_frame
		button.pressed.emit()
		await process_frame
		await process_frame
		var zone := str(game._transport.snapshot().get("zone", ""))
		if zone != "job_2" or panel.visible:
			_fail("버튼을 눌렀는데 2차 시험에 안 갔다 (%s · 창 %s)" % [zone, panel.visible])
		else:
			print("  창: '%s' → 누르니 %s" % [button.text, zone])

	await _case_learn_all(game)

	Save.clear()
	if _failed == 0:
		print("전직: 전부 통과")
		quit(0)
	else:
		print("전직: %d개 실패" % _failed)
		quit(1)
