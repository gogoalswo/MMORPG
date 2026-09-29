extends SceneTree

## 시련의 탑 — 30초 안에 7마리를 잡으면 통과, 크리스탈 단계 × 1개 (docs/features/dungeons.md "시련의 탑").
## 시계·잡은 수는 World 가, 크리스탈은 장부(`Ledger.trial_clear`)가 본다.
##
##   godot --headless --path godot --script tests/trial_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_zone()
	_case_clear()
	_case_fail()
	_case_leave()
	if _failed == 0:
		print("시련의 탑: 전부 통과")
		quit(0)
	else:
		print("시련의 탑: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _all(events: Array, type_name: String) -> Array:
	return events.filter(func(e): return str(e.get("type", "")) == type_name)


func _crystals(me: Dictionary) -> int:
	var total := 0
	for stack in me.bag:
		if str(stack.get("id", "")) == Items.crystal_id():
			total += int(stack.get("count", 1))
	return total


## 마을에서 들어온 캐릭터 — 던전 창의 입장과 같은 `travel`
func _enter(stage: int) -> World:
	var w := World.new()
	w.open("village")
	w.join("me")
	w.snapshot().players["me"].level = 200
	w.travel("me", "trial_%02d" % stage)
	w.drain_events()
	return w


## 좁은 맵 · 몬스터 열 마리 · 들어오면 시계가 돈다
func _case_zone() -> void:
	var w := _enter(3)
	var snap := w.snapshot()
	if w.zone_id != "trial_03":
		_fail("시련 3단계로 못 갔다 (%s)" % w.zone_id)
		return
	if float(snap.size) >= float(GameData.zone("village").get("size", 66)):
		_fail("시련 맵이 마을보다 작지 않다 (%s)" % snap.size)
	if snap.monsters.size() != 10:
		_fail("몬스터가 %d마리 (10 이어야 한다)" % snap.monsters.size())
	var trial: Dictionary = snap.get("trial", {})
	if int(trial.get("need", 0)) != 7 or str(trial.get("result", "x")) != "":
		_fail("시계가 안 걸렸다: %s" % trial)
	var left := int(trial.get("ends_at", 0)) - Time.get_ticks_msec()
	if left < 29000 or left > 30000:
		_fail("남은 시간이 30초가 아니다 (%dms)" % left)
	print("  맵 %s · 몬스터 %d · %d마리 / %.0f초" % [snap.size, snap.monsters.size(), int(trial.need), left / 1000.0])


## 일곱째에 통과 — 크리스탈 단계 수만큼, 결과는 한 번만
func _case_clear() -> void:
	var w := _enter(4)
	var me: Dictionary = w.snapshot().players["me"]
	var before := _crystals(me)
	var dropped := 0
	var events: Array = []
	var mobs: Array = w.snapshot().monsters
	for i in 8:
		w._hit_monster(me, mobs[i], 1e9, "")
		var got := w.drain_events()
		for loot in _all(got, "loot"):
			dropped += int(loot.get("crystal", 0))
		if i == 5 and not _all(got, "trial").is_empty():
			_fail("여섯째에 결과가 났다")
		events.append_array(got)
	var results := _all(events, "trial")
	if results.size() != 1:
		_fail("결과가 %d번 났다 (한 번이어야 한다)" % results.size())
		return
	var result: Dictionary = results[0]
	if str(result.result) != "clear" or int(result.kills) != 7 or int(result.crystals) != 4:
		_fail("통과 결과가 틀렸다: %s" % result)
	if _all(events, "trialReward").is_empty():
		_fail("장부가 크리스탈을 안 줬다")
	var gained := _crystals(me) - before - dropped
	if gained != 4:
		_fail("크리스탈이 %d개 늘었다 (4단계 = 4개)" % gained)
	print("  7마리째 통과 · 크리스탈 +%d" % gained)


## 시간이 다 되면 실패 — 크리스탈 없음, 그 뒤 처치는 안 센다
func _case_fail() -> void:
	var w := _enter(2)
	var me: Dictionary = w.snapshot().players["me"]
	var mobs: Array = w.snapshot().monsters
	for i in 3:
		w._hit_monster(me, mobs[i], 1e9, "")
	w.snapshot().trial.ends_at = Time.get_ticks_msec() - 1
	w.drain_events()
	w.step(0.016)
	var results := _all(w.drain_events(), "trial")
	if results.size() != 1 or str(results[0].result) != "fail" or int(results[0].crystals) != 0 or int(results[0].kills) != 3:
		_fail("시간이 다 됐는데 실패가 아니다: %s" % [results])
	for i in range(3, 10):
		w._hit_monster(me, mobs[i], 1e9, "")
	var late := w.drain_events()
	if not _all(late, "trial").is_empty() or not _all(late, "trialReward").is_empty():
		_fail("시간이 지난 뒤 처치로 통과했다")
	print("  30초 지나면 실패 (3/7) · 늦은 처치는 안 센다")


## 나가면 시계가 없어진다 — 마을에는 시련이 없다
func _case_leave() -> void:
	var w := _enter(1)
	w.travel("me", "village")
	if not w.snapshot().get("trial", {}).is_empty():
		_fail("마을로 나왔는데 시련 시계가 남았다")
	w.step(0.016)
	if not _all(w.drain_events(), "trial").is_empty():
		_fail("나온 뒤에 결과가 났다")
