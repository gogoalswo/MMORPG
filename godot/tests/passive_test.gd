extends SceneTree

## 패시브 질풍각 (docs/features/passives.md) — **판정은 장부가 다시 본다.**
## 레벨마다 한 단계가 열리고 [습득] 한 번에 한 단계, 공속은 여기서만 온다.
## Lv.200 · 20단계면 격투가 평타가 100ms = 초당 10번이다 (2026-09-30 요청, 처음엔 8번)
##
##   godot --headless --path godot --script tests/passive_test.gd

var _failed := 0


func _init() -> void:
	_case_learn()
	_case_speed()
	_case_gear()
	_case_save()
	_case_kill_check()
	Save.clear()
	if _failed == 0:
		print("패시브: 전부 통과")
		quit(0)
	else:
		print("패시브: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _me() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	return [w, w.snapshot().players["me"]]


func _rank(me: Dictionary) -> int:
	return int(me.get("passives", {}).get("gale_kicks", 0))


## 레벨이 안 되면 안 오르고, 되면 한 번에 한 단계, 끝 단계를 넘지 않는다
func _case_learn() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.level = 9
	w.learn_passive("me", "gale_kicks")
	if _rank(me) != 0:
		_fail("Lv.9 인데 1단계를 배웠다")
	me.level = 25
	w.learn_passive("me", "gale_kicks")
	w.learn_passive("me", "gale_kicks")
	w.learn_passive("me", "gale_kicks")
	if _rank(me) != 2:
		_fail("Lv.25 는 두 단계까지인데 %d단계" % _rank(me))
	if Skills.passive_learnable("fighter", 25, me.passives):
		_fail("열린 단계를 다 배웠는데 레드닷 조건이 켜져 있다")
	if not Skills.passive_learnable("fighter", 30, me.passives):
		_fail("Lv.30 이면 3단계가 열려 레드닷 조건이 켜져야 한다")
	w.learn_passive("me", "없는패시브")
	me.level = 999
	for i in 30:
		w.learn_passive("me", "gale_kicks")
	var top := int(Skills.passive("gale_kicks").maxRank)
	if _rank(me) != top:
		_fail("끝 단계가 %d 인데 %d단계" % [top, _rank(me)])
	else:
		print("  배우기: Lv.9 막힘 · Lv.25 두 단계까지 · 끝 %d단계에서 멈춤" % top)


## 20단계면 격투가 평타 간격 100ms (초당 10번) — `stats_of` 가 더한다
func _case_speed() -> void:
	var stats := World.stats_of("fighter", 200, {}, {"gale_kicks": 20})
	var interval := Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	if interval != 100:
		_fail("Lv.200 · 20단계 평타 간격이 100ms 가 아니다: %dms" % interval)
	var bare := World.stats_of("fighter", 200, {})
	if float(bare.attackSpeed) != 0.0:
		_fail("패시브 없이 공속이 %s" % bare.attackSpeed)
	print("  공속: 0단계 %dms → 20단계 %dms (초당 %.1f번)" % [
		Combat.effective_cooldown(bare.attackCooldown, bare.attackSpeed), interval, 1000.0 / interval
	])


## 장비의 옛 공속 옵션은 무시한다 (2026-09-29 요청: "장비 옵션에 공속은 제거할꺼야")
func _case_gear() -> void:
	var ring := {"id": str(Items.all().keys()[0]), "options": [{"kind": "attackSpeed", "value": 20}]}
	if float(Items.stack_stats(ring).attackSpeed) != 0.0:
		_fail("옛 공속 옵션이 공속을 올렸다")
	if not Items.shown_options(ring.options).is_empty():
		_fail("옛 공속 옵션이 화면에 적힌다")
	if "attackSpeed" in GameData.load_table("items").get("optionKinds", []):
		_fail("공속이 아직 뽑히는 옵션 목록에 있다")


## 저장했다 불러와도 단계가 남는다
func _case_save() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.level = 50
	for i in 3:
		w.learn_passive("me", "gale_kicks")
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if _rank(back) != 3 or float(back.stats.attackSpeed) <= 0.0:
		_fail("불러온 뒤 질풍각 %d단계 · 공속 %s" % [_rank(back), back.stats.attackSpeed])


## 서버의 처치 검증도 패시브를 본다 — 빼먹으면 빨라진 평타가 "너무 빨리 잡았다" 로 거부된다
func _case_kill_check() -> void:
	if not LedgerServer.OPS.has("learn_passive"):
		_fail("서버가 learn_passive 요청을 모른다")
	# 가장 높은 레벨 몬스터 — 약한 놈은 Lv.200 에게 0ms 라 차이가 안 보인다
	var kind := {}
	for id in GameData.load_table("monsters").kinds:
		var each: Dictionary = GameData.load_table("monsters").kinds[id]
		if kind.is_empty() or int(each.get("level", 0)) > int(kind.get("level", 0)):
			kind = each
	var ledger := Ledger.fresh("fighter")
	ledger.level = 200
	var slow := KillCheck.min_ms(ledger, kind)
	ledger.passives = {"gale_kicks": 20}
	var fast := KillCheck.min_ms(ledger, kind)
	if fast >= slow:
		_fail("패시브를 배웠는데 최소 처치 시간이 그대로다: %.0f → %.0fms" % [slow, fast])
