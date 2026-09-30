extends SceneTree

## 헬스 (docs/features/fitness.md) — 던전이 프로틴을 주고, 헬스 창에서 넣어 운동 단계를 확률로 올린다.
## **판정은 장부**(`Ledger.fitness_up`)이고 보너스는 `World.stats_of` 가 장비 % 와 **따로 곱한다.**
##
##   godot --headless --path godot --script tests/fitness_test.gd

var _failed := 0


func _init() -> void:
	_case_table()
	_case_dungeon_reward()
	_case_up()
	_case_auto()
	_case_stats()
	_case_save()
	_case_server()
	# 창은 트리에 들어가 한 프레임 돈 뒤에야 크기가 잡힌다 — 끝내기는 거기서 한다
	_finish.call_deferred()


func _finish() -> void:
	await _case_panel()
	Save.clear()
	if _failed == 0:
		print("헬스: 전부 통과")
		quit(0)
	else:
		print("헬스: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _me() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	return [w, w.snapshot().players["me"]]


## 표 — 운동 셋 · 20단계 · 끝 +50%
func _case_table() -> void:
	var names: Array = []
	for kind in Fitness.kinds():
		names.append(str(kind.name))
	if names != ["벤치프레스", "데드리프트", "스쿼트"]:
		_fail("탭 이름이 %s" % [names])
	if Fitness.max_stage() != 20 or Fitness.bonus(20) != 50.0 or Fitness.bonus(0) != 0.0:
		_fail("끝 단계 %d · 끝 보너스 %s" % [Fitness.max_stage(), Fitness.bonus(20)])
	if int(Fitness.step(1).cost) != 10 or int(Fitness.step(1).chance) != 90:
		_fail("1단계가 10개 · 90%% 가 아니다: %s" % [Fitness.step(1)])


## 토벌 보스를 잡거나 시련을 통과하면 프로틴 세 종이 **각각** 단계 × 5 만큼
func _case_dungeon_reward() -> void:
	var ledger := Ledger.new()
	var me := Ledger.fresh("fighter")
	ledger._check_dungeon_clear(me, {"boss": false, "zone": "raid_03"})
	if not me.proteins.is_empty():
		_fail("보스가 아닌데 프로틴을 줬다")
	ledger._check_dungeon_clear(me, {"boss": true, "zone": "raid_03"})
	ledger.trial_clear(me, "trial_02")
	for protein in ["power", "defense", "health"]:
		if int(me.proteins.get(protein, 0)) != 25:
			_fail("토벌 3단계(15) + 시련 2단계(10) 인데 %s 가 %d" % [protein, int(me.proteins.get(protein, 0))])
	var events := ledger.take_events()
	var seen := events.filter(func(e): return str(e.type) == "protein").size()
	if seen != 2:
		_fail("protein 이벤트가 두 번이 아니다: %d" % seen)
	print("  던전: 토벌 3단계 15 + 시련 2단계 10 = 세 종 각 25개")


## 한 번 — 모자라면 거절, 두드리면 그 단계 비용만큼 빠지고 성공이면 한 단계 오른다. 끝 단계는 거절
func _case_up() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.fitness_up("me", "bench", false)
	if int(me.fitness.get("bench", 0)) != 0:
		_fail("프로틴이 없는데 올랐다")
	me.proteins = {"power": 1000}
	var successes := 0
	var fails := 0
	for i in 40:
		var stage := int(me.fitness.get("bench", 0))
		if stage >= 5:
			break
		var before := int(me.proteins.power)
		w.fitness_up("me", "bench", false)
		var after := int(me.fitness.get("bench", 0))
		if before - int(me.proteins.power) != int(Fitness.step(stage + 1).cost):
			_fail("%d단계 한 번에 %d개가 빠졌다" % [stage + 1, before - int(me.proteins.power)])
		if after == stage + 1:
			successes += 1
		elif after == stage:
			fails += 1
		else:
			_fail("한 번에 %d → %d단계" % [stage, after])
	if int(me.fitness.get("bench", 0)) < 5:
		_fail("1000개로 5단계에 못 갔다")
	if int(me.fitness.get("deadlift", 0)) != 0:
		_fail("벤치프레스를 두드렸는데 데드리프트가 올랐다")
	w.fitness_up("me", "없는운동", false)
	me.fitness.squat = 20
	me.proteins.health = 100000
	w.fitness_up("me", "squat", false)
	if int(me.fitness.squat) != 20 or int(me.proteins.health) != 100000:
		_fail("끝 단계에서 또 두드렸다")
	print("  한 번: 성공 %d · 실패 %d 로 5단계 · 끝 단계 거절" % [successes, fails])


## 자동 — 성공하거나 모자랄 때까지. 5% 짜리도 넉넉하면 한 번에 붙는다
func _case_auto() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var cost := int(Fitness.step(20).cost)
	me.fitness = {"deadlift": 19}
	me.proteins = {"defense": cost * 300}
	w.fitness_up("me", "deadlift", true)
	var tries := (cost * 300 - int(me.proteins.defense)) / cost
	if int(me.fitness.deadlift) != 20:
		_fail("자동인데 20단계가 안 붙었다 (%d번)" % tries)
	# 모자라면 거기서 멈춘다 — 실패로 끝나도 단계는 그대로
	me.fitness = {"deadlift": 19}
	me.proteins = {"defense": cost * 2 + 5}
	w.fitness_up("me", "deadlift", true)
	var left := int(me.proteins.defense)
	if left != 5 and not (left == cost + 5 and int(me.fitness.deadlift) == 20):
		_fail("자동이 모자라기 전에 멈췄거나 넘어서 썼다: 남은 %d" % left)
	if int(me.fitness.deadlift) < 19:
		_fail("실패했는데 단계가 내려갔다")
	print("  자동: 5%% 를 %d번 만에 · 모자라면 멈춤" % tries)


## 보너스는 장비 % 와 따로 곱한다 — 벤치 20단계 = 공격력 × 1.5, 정보 창용 `fitness_*` 도 싣는다
func _case_stats() -> void:
	var weapon := {}
	for id in Items.all():
		if str(Items.all()[id].get("slot", "")) == "weapon":
			weapon = {"id": str(id), "grade": int(Items.all()[id].get("grade", 1))}
			break
	var equipped := {"weapon": weapon}
	var bare := World.stats_of("fighter", 100, equipped)
	var fit := World.stats_of("fighter", 100, equipped, {}, {"bench": 20, "deadlift": 10, "squat": 5})
	if int(fit.attack) != roundi(float(bare.attack) * 1.5):
		_fail("공격력 %d → %d (× 1.5 여야 한다)" % [int(bare.attack), int(fit.attack)])
	if int(fit.defense) != roundi(float(bare.defense) * (1.0 + Fitness.bonus(10) / 100.0)):
		_fail("방어력 %d → %d" % [int(bare.defense), int(fit.defense)])
	if int(fit.maxHp) != roundi(float(bare.maxHp) * (1.0 + Fitness.bonus(5) / 100.0)):
		_fail("체력 %d → %d" % [int(bare.maxHp), int(fit.maxHp)])
	if float(fit.get("fitness_attack", 0)) != 50.0 or float(bare.get("fitness_attack", -1)) != 0.0:
		_fail("fitness_attack 이 %s / %s" % [fit.get("fitness_attack"), bare.get("fitness_attack")])
	# 판정 값에도 들어가나 — World 의 플레이어 스탯
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var before := int(me.stats.attack)
	me.fitness = {"bench": 0}
	me.proteins = {"power": 100000}
	while int(me.fitness.get("bench", 0)) < 10:
		w.fitness_up("me", "bench", true)
	if int(me.stats.attack) <= before:
		_fail("10단계인데 공격력이 그대로다 (%d)" % before)
	print("  스탯: 공격력 %d → %d (벤치 20단계 × 1.5) · 방어 %d → %d · 체력 %d → %d" % [
		int(bare.attack), int(fit.attack), int(bare.defense), int(fit.defense), int(bare.maxHp), int(fit.maxHp)
	])


## 저장했다 불러와도 프로틴·단계가 남는다. 표에 없는 것·끝을 넘는 단계는 잘린다
func _case_save() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.proteins = {"power": 7, "health": 3, "없는것": 9}
	me.fitness = {"bench": 4, "squat": 99, "없는운동": 2}
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if back.proteins != {"power": 7, "health": 3}:
		_fail("불러온 프로틴 %s" % [back.proteins])
	if back.fitness != {"bench": 4, "squat": 20}:
		_fail("불러온 단계 %s" % [back.fitness])
	if float(back.stats.get("fitness_attack", 0)) != Fitness.bonus(4):
		_fail("불러온 뒤 스탯에 헬스가 안 들어갔다")


## 서버 — 요청 표에 있고, 새 계정에 칸이 있고, 처치 검증도 헬스 공격력을 본다
func _case_server() -> void:
	if str(LedgerServer.OPS.get("fitness_up", "")) != "si":
		_fail("서버가 fitness_up 요청을 모른다")
	var ledger := Ledger.fresh("fighter")
	if not ("proteins" in Ledger.KEYS and "fitness" in Ledger.KEYS):
		_fail("장부 칸에 proteins · fitness 가 없다")
	if not (ledger.has("proteins") and ledger.has("fitness")):
		_fail("새 계정에 헬스 칸이 없다")
	var kind := {}
	for id in GameData.load_table("monsters").kinds:
		var each: Dictionary = GameData.load_table("monsters").kinds[id]
		if kind.is_empty() or int(each.get("level", 0)) > int(kind.get("level", 0)):
			kind = each
	ledger.level = 200
	var slow := KillCheck.min_ms(ledger, kind)
	ledger.fitness = {"bench": 20}
	var fast := KillCheck.min_ms(ledger, kind)
	if fast >= slow:
		_fail("벤치 20단계인데 최소 처치 시간이 그대로다: %.0f → %.0fms" % [slow, fast])


## 창 — 탭 셋 · 제목 · 모자라면 단추 꺼짐 · 두드릴 수 있으면 탭 빨간 점 · 단추가 요청을 낸다
func _case_panel() -> void:
	var boxes := func(_name: String, _margin: int, _content: int) -> StyleBox: return StyleBoxFlat.new()
	var icons := func(_name: String) -> Texture2D: return null
	var panel := FitnessPanel.make(boxes, icons)
	root.add_child(panel)
	panel.open()
	await process_frame
	panel.refresh({"proteins": {"power": 5}, "fitness": {"bench": 3}})
	if panel.title_text() != "벤치프레스 3단계":
		_fail("제목이 '%s'" % panel.title_text())
	if not panel.up_button().disabled or not panel.auto_button().disabled:
		_fail("프로틴이 모자란데 강화 단추가 켜져 있다")
	if not panel.dotted_tabs().is_empty():
		_fail("두드릴 수 없는데 빨간 점 %s" % [panel.dotted_tabs()])
	panel.refresh({"proteins": {"power": 5, "health": 10}, "fitness": {"bench": 3}})
	if panel.dotted_tabs() != ["squat"]:
		_fail("스쿼트만 빨간 점이어야 하는데 %s" % [panel.dotted_tabs()])
	var tab: Button = panel.find_child("tab_squat", true, false)
	tab.pressed.emit()
	if panel.title_text() != "스쿼트 0단계" or panel.up_button().disabled:
		_fail("스쿼트 탭: '%s' · 단추 꺼짐 %s" % [panel.title_text(), panel.up_button().disabled])
	var asked: Array = []
	panel.up_requested.connect(func(kind: String, auto: bool) -> void: asked.append([kind, auto]))
	panel.up_button().pressed.emit()
	panel.auto_button().pressed.emit()
	if asked != [["squat", false], ["squat", true]]:
		_fail("단추가 낸 요청 %s" % [asked])
	var next: Button = panel.find_child("next", true, false)
	next.pressed.emit()
	if panel.kind_id() != "bench":
		_fail("스쿼트 다음 꺾쇠가 벤치프레스로 돌아가지 않는다: %s" % panel.kind_id())
	# 기준 화면(1280x720)에 들어가나 — 돌판 틀의 여백(카드 34 · 안 30)을 뺀 알맹이 최소 크기로 본다
	var inner := panel.get_combined_minimum_size()
	if inner.x > 1280.0 or inner.y > 720.0:
		_fail("헬스 창 최소 크기 %s 가 화면(1280x720)보다 크다" % inner)
	panel.queue_free()
	print("  창: 제목 · 단추 꺼짐 · 탭 빨간 점 · 강화/자동 요청 · 꺾쇠로 돌기 · 최소 크기 %s" % inner)
